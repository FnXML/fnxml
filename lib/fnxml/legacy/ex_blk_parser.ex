defmodule FnXML.Legacy.ExBlkParser do
  @moduledoc """
  Legacy block-at-a-time XML parser using the same algorithm as the Zig NIF parser.

  **Note**: This parser is kept for benchmarking and backwards compatibility only.
  It is a legacy implementation that may be removed in future versions.
  For production use, prefer `FnXML.Parser` instead.

  This parser:
  - Parses one block/chunk at a time
  - Builds events into a list during block processing
  - Returns batch of events when block is complete or an element spans chunks
  - Uses `Stream.resource` to emit event batches lazily

  This approach is faster than per-event process messaging while still providing
  lazy streaming.

  ## Usage

      # One-shot parsing
      events = FnXML.Legacy.ExBlkParser.parse("<root><child/></root>")

      # Stream from file (lazy, batched events)
      events = File.stream!("large.xml", [], 64_000)
               |> FnXML.Legacy.ExBlkParser.stream()
               |> Enum.to_list()

      # Low-level block parsing
      {events, nil, {line, ls, abs_pos}} =
        FnXML.Legacy.ExBlkParser.parse_block(xml, nil, 0, 1, 0, 0)
  """

  # Inline frequently called helper functions
  @compile {:inline, utf8_size: 1, complete: 4, incomplete: 5}

  # XML character guard per XML spec production [2]
  # Char ::= #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
  defguardp is_xml_char(c)
            when c == 0x9 or c == 0xA or c == 0xD or
                   c in 0x20..0xD7FF or c in 0xE000..0xFFFD or
                   c in 0x10000..0x10FFFF

  # Name character guards per XML spec
  defguardp is_name_start(c)
            when c in ?a..?z or c in ?A..?Z or c == ?_ or c == ?: or
                   c in 0x00C0..0x00D6 or c in 0x00D8..0x00F6 or
                   c in 0x00F8..0x02FF or c in 0x0370..0x037D or
                   c in 0x037F..0x1FFF or c in 0x200C..0x200D or
                   c in 0x2070..0x218F or c in 0x2C00..0x2FEF or
                   c in 0x3001..0xD7FF or c in 0xF900..0xFDCF or
                   c in 0xFDF0..0xFFFD or c in 0x10000..0xEFFFF

  defguardp is_name_char(c)
            when is_name_start(c) or c == ?- or c == ?. or c in ?0..?9 or
                   c == 0x00B7 or c in 0x0300..0x036F or c in 0x203F..0x2040

  # UTF-8 codepoint byte size
  defp utf8_size(c) when c < 0x80, do: 1
  defp utf8_size(c) when c < 0x800, do: 2
  defp utf8_size(c) when c < 0x10000, do: 3
  defp utf8_size(_), do: 4

  # Return format helper - complete (no leftover)
  defp complete(events, line, ls, abs_pos) do
    {:lists.reverse(events), nil, {line, ls, abs_pos}}
  end

  # Return format helper - incomplete (has leftover starting at elem_start)
  defp incomplete(events, elem_start, line, ls, abs_pos) do
    {:lists.reverse(events), elem_start, {line, ls, abs_pos}}
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Parse complete XML (one-shot mode).
  Returns list of all events.
  """
  def parse(input) when is_binary(input) do
    stream([input]) |> Enum.to_list()
  end

  @doc """
  Stream XML from any enumerable source.
  Returns lazy stream of events (batched per block).
  """
  def stream(enumerable) do
    Stream.resource(
      fn -> init_stream(enumerable) end,
      &next_batch/1,
      fn _ -> :ok end
    )
  end

  @doc """
  Parse a single block of XML.

  - `events` - List of parsed events (in order)
  - `{line, ls, abs_pos}` - Updated parser state

  When an element spans chunks, events will include `{:error, :advance, nil, line, ls, pos}`
  to signal that more data is needed.
  """
  def parse_block(block, _prev_block, _prev_pos, line, ls, abs_pos) do
    # Check for UTF-16 BOM at document start
    if abs_pos == 0 do
      case block do
        <<0xFE, 0xFF, _::binary>> ->
          # UTF-16 BE BOM
          {[{:error, :utf16, nil, line, ls, abs_pos}], nil, {line, ls, abs_pos}}

        <<0xFF, 0xFE, _::binary>> ->
          # UTF-16 LE BOM
          {[{:error, :utf16, nil, line, ls, abs_pos}], nil, {line, ls, abs_pos}}

        _ ->
          # Normal parsing
          parse_content(block, block, 0, abs_pos, line, ls, [])
      end
    else
      parse_content(block, block, 0, abs_pos, line, ls, [])
    end
  end

  # ============================================================================
  # Stream Helpers
  # ============================================================================

  # State tuple: {source, leftover, line, ls, abs_pos, done}

  defp init_stream(enumerable) do
    {enumerable, nil, 1, 0, 0, false}
  end

  defp next_batch({_source, _leftover, _line, _ls, _abs_pos, true} = state) do
    {:halt, state}
  end

  defp next_batch({source, leftover, line, ls, abs_pos, false}) do
    case get_chunk(source) do
      {:ok, chunk, rest} ->
        if leftover do
          handle_leftover(rest, leftover, chunk, line, ls, abs_pos)
        else
          handle_chunk(rest, chunk, line, ls, abs_pos)
        end

      :eof ->
        {:halt, {source, leftover, line, ls, abs_pos, true}}
    end
  end

  defp get_chunk([chunk | rest]) when is_binary(chunk), do: {:ok, chunk, rest}
  defp get_chunk([]), do: :eof

  defp get_chunk(stream) do
    case Enum.take(stream, 1) do
      [chunk] -> {:ok, chunk, Stream.drop(stream, 1)}
      [] -> :eof
    end
  end

  # Parse a chunk when there's no leftover from previous chunk
  defp handle_chunk(rest, chunk, line, ls, abs_pos) do
    {events, leftover_pos, {new_line, new_ls, new_abs_pos}} =
      parse_block(chunk, nil, 0, line, ls, abs_pos)

    if leftover_pos do
      leftover = binary_part(chunk, leftover_pos, byte_size(chunk) - leftover_pos)
      {events, {rest, leftover, new_line, new_ls, new_abs_pos, false}}
    else
      {events, {rest, nil, new_line, new_ls, new_abs_pos, false}}
    end
  end

  # Handle leftover from previous chunk using mini-block approach
  defp handle_leftover(rest, leftover, chunk, line, ls, abs_pos) do
    case :binary.match(chunk, ">") do
      {pos, 1} ->
        # Create mini-block: leftover + portion up to and including '>'
        mini = leftover <> binary_part(chunk, 0, pos + 1)

        {events, leftover_pos, {new_line, new_ls, new_abs_pos}} =
          parse_block(mini, nil, 0, line, ls, abs_pos)

        if leftover_pos do
          # Still incomplete - extract new leftover and try next '>'
          new_leftover = binary_part(mini, leftover_pos, byte_size(mini) - leftover_pos)

          handle_leftover_continue(
            rest,
            new_leftover,
            chunk,
            pos + 1,
            new_line,
            new_ls,
            new_abs_pos,
            events
          )
        else
          # Mini-block complete - parse rest of chunk
          parse_rest_of_chunk(rest, chunk, pos + 1, new_line, new_ls, new_abs_pos, events)
        end

      :nomatch ->
        # No '>' in chunk - append entire chunk to leftover
        {[], {rest, leftover <> chunk, line, ls, abs_pos, false}}
    end
  end

  # Continue handling leftover when first '>' wasn't enough
  defp handle_leftover_continue(
         rest,
         leftover,
         chunk,
         search_start,
         line,
         ls,
         abs_pos,
         acc_events
       ) do
    remaining = byte_size(chunk) - search_start

    case :binary.match(chunk, ">", [{:scope, {search_start, remaining}}]) do
      {pos, 1} ->
        mini = leftover <> binary_part(chunk, search_start, pos - search_start + 1)

        {events, leftover_pos, {new_line, new_ls, new_abs_pos}} =
          parse_block(mini, nil, 0, line, ls, abs_pos)

        all_events = acc_events ++ events

        if leftover_pos do
          new_leftover = binary_part(mini, leftover_pos, byte_size(mini) - leftover_pos)

          handle_leftover_continue(
            rest,
            new_leftover,
            chunk,
            pos + 1,
            new_line,
            new_ls,
            new_abs_pos,
            all_events
          )
        else
          parse_rest_of_chunk(rest, chunk, pos + 1, new_line, new_ls, new_abs_pos, all_events)
        end

      :nomatch ->
        # No more '>' - buffer leftover + rest of chunk
        new_leftover = leftover <> binary_part(chunk, search_start, remaining)
        {acc_events, {rest, new_leftover, line, ls, abs_pos, false}}
    end
  end

  # Parse the rest of a chunk after mini-block completed
  defp parse_rest_of_chunk(rest, chunk, start_pos, line, ls, abs_pos, acc_events) do
    chunk_remaining = byte_size(chunk) - start_pos

    if chunk_remaining > 0 do
      rest_chunk = binary_part(chunk, start_pos, chunk_remaining)

      {events, leftover_pos, {new_line, new_ls, new_abs_pos}} =
        parse_block(rest_chunk, nil, 0, line, ls, abs_pos)

      all_events = acc_events ++ events

      if leftover_pos do
        leftover = binary_part(rest_chunk, leftover_pos, byte_size(rest_chunk) - leftover_pos)
        {all_events, {rest, leftover, new_line, new_ls, new_abs_pos, false}}
      else
        {all_events, {rest, nil, new_line, new_ls, new_abs_pos, false}}
      end
    else
      {acc_events, {rest, nil, line, ls, abs_pos, false}}
    end
  end

  # ============================================================================
  # Content parsing - entry point
  # ============================================================================

  # Buffer empty - return events
  defp parse_content(<<>>, _xml, __buf_pos, abs_pos, line, ls, events) do
    complete(events, line, ls, abs_pos)
  end

  # XML declaration - elem_start = buf_pos (position of '<')
  defp parse_content(<<"<?xml ", rest::binary>>, xml, buf_pos, abs_pos, line, ls, events) do
    parse_prolog(
      rest,
      xml,
      buf_pos + 6,
      abs_pos + 6,
      line,
      ls,
      {line, ls, abs_pos + 1},
      buf_pos,
      events
    )
  end

  defp parse_content(<<"<?xml\t", rest::binary>>, xml, buf_pos, abs_pos, line, ls, events) do
    parse_prolog(
      rest,
      xml,
      buf_pos + 6,
      abs_pos + 6,
      line,
      ls,
      {line, ls, abs_pos + 1},
      buf_pos,
      events
    )
  end

  defp parse_content(<<"<?xml\n", rest::binary>>, xml, buf_pos, abs_pos, line, _ls, events) do
    parse_prolog(
      rest,
      xml,
      buf_pos + 6,
      abs_pos + 6,
      line + 1,
      abs_pos + 6,
      {line, abs_pos + 6 - 6, abs_pos + 1},
      buf_pos,
      events
    )
  end

  # Element start
  defp parse_content(<<"<", _::binary>> = rest, xml, buf_pos, abs_pos, line, ls, events) do
    parse_element(rest, xml, buf_pos, abs_pos, line, ls, events)
  end

  # All other content (text, whitespace) - let parse_text handle it
  defp parse_content(rest, xml, buf_pos, abs_pos, line, ls, events) do
    parse_text(rest, xml, buf_pos, abs_pos, line, ls, {line, ls, abs_pos}, buf_pos, true, events)
  end

  # ============================================================================
  # Text parsing
  # ============================================================================

  defp parse_text(<<>>, xml, buf_pos, abs_pos, line, ls, loc, start, all_ws, events) do
    # Emit text accumulated so far
    events =
      if buf_pos > start do
        text = binary_part(xml, start, buf_pos - start)
        {l, lls, lp} = loc

        if all_ws do
          [{:space, text, l, lls, lp} | events]
        else
          [{:characters, text, l, lls, lp} | events]
        end
      else
        events
      end

    # Block ended - return based on depth
    complete(events, line, ls, abs_pos)
  end

  defp parse_text(
         <<"<", _::binary>> = rest,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         all_ws,
         events
       ) do
    # Emit accumulated text
    events =
      if buf_pos > start do
        text = binary_part(xml, start, buf_pos - start)
        {l, lls, lp} = loc

        if all_ws do
          [{:space, text, l, lls, lp} | events]
        else
          [{:characters, text, l, lls, lp} | events]
        end
      else
        events
      end

    # Parse element
    parse_element(rest, xml, buf_pos, abs_pos, line, ls, events)
  end

  # Whitespace characters - keep all_ws as-is
  defp parse_text(
         <<?\n, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         _ls,
         loc,
         start,
         all_ws,
         events
       ) do
    parse_text(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line + 1,
      abs_pos + 1,
      loc,
      start,
      all_ws,
      events
    )
  end

  defp parse_text(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         all_ws,
         events
       )
       when c in [?\s, ?\t] do
    parse_text(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, start, all_ws, events)
  end

  # ]]> is not allowed in text content (outside CDATA)
  defp parse_text(
         <<"]]>", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         all_ws,
         events
       ) do
    # Emit text accumulated so far (if any)
    events =
      if buf_pos > start do
        text = binary_part(xml, start, buf_pos - start)
        {l, lls, lp} = loc

        if all_ws do
          [{:space, text, l, lls, lp} | events]
        else
          [{:characters, text, l, lls, lp} | events]
        end
      else
        events
      end

    # Emit error for ]]> in content
    events = [
      {:error, :text_cdata_end, "']]>' not allowed in text content", line, ls, abs_pos} | events
    ]

    # Continue parsing after the illegal sequence (new text starts after ]]>)
    parse_text(
      rest,
      xml,
      buf_pos + 3,
      abs_pos + 3,
      line,
      ls,
      {line, ls, abs_pos + 3},
      buf_pos + 3,
      true,
      events
    )
  end

  # Non-whitespace - set all_ws to false
  defp parse_text(
         <<_, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         _all_ws,
         events
       ) do
    parse_text(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, start, false, events)
  end

  # ============================================================================
  # Element dispatch
  # ============================================================================

  # elem_start = buf_pos (position of '<') for incomplete tracking
  defp parse_element(<<"<!--", rest::binary>>, xml, buf_pos, abs_pos, line, ls, events) do
    parse_comment(
      rest,
      xml,
      buf_pos + 4,
      abs_pos + 4,
      line,
      ls,
      {line, ls, abs_pos + 1},
      buf_pos + 4,
      false,
      buf_pos,
      events
    )
  end

  defp parse_element(<<"<![CDATA[", rest::binary>>, xml, buf_pos, abs_pos, line, ls, events) do
    parse_cdata(
      rest,
      xml,
      buf_pos + 9,
      abs_pos + 9,
      line,
      ls,
      {line, ls, abs_pos + 1},
      buf_pos + 9,
      buf_pos,
      events
    )
  end

  defp parse_element(<<"<!DOCTYPE", rest::binary>>, xml, buf_pos, abs_pos, line, ls, events) do
    # Start position is after "<!" to capture "DOCTYPE ..."
    # Initial quote state is nil (not in quotes)
    parse_doctype(
      rest,
      xml,
      buf_pos + 9,
      abs_pos + 9,
      line,
      ls,
      {line, ls, abs_pos + 1},
      buf_pos + 2,
      1,
      nil,
      buf_pos,
      events
    )
  end

  defp parse_element(
         <<"</", rest2::binary>> = <<"</", c::utf8, _::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         events
       )
       when is_name_start(c) do
    parse_close_tag_name(
      rest2,
      xml,
      buf_pos + 2,
      abs_pos + 2,
      line,
      ls,
      {line, ls, abs_pos + 1},
      buf_pos + 2,
      buf_pos,
      events
    )
  end

  # Invalid close tag name start character
  defp parse_element(<<"</", _::binary>>, _xml, _buf_pos, abs_pos, line, ls, events) do
    events = [
      {:error, :invalid_close_tag, "Close tag must start with a valid name character", line, ls,
       abs_pos + 2}
      | events
    ]

    complete(events, line, ls, abs_pos + 2)
  end

  defp parse_element(
         <<"<?", rest2::binary>> = <<"<?", c::utf8, _::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         events
       )
       when is_name_start(c) do
    parse_pi_name(
      rest2,
      xml,
      buf_pos + 2,
      abs_pos + 2,
      line,
      ls,
      {line, ls, abs_pos + 1},
      buf_pos + 2,
      buf_pos,
      events
    )
  end

  # Invalid PI target start character
  defp parse_element(<<"<?", _::binary>>, _xml, _buf_pos, abs_pos, line, ls, events) do
    events = [
      {:error, :invalid_pi_target, "PI target must start with a valid name character", line, ls,
       abs_pos + 2}
      | events
    ]

    complete(events, line, ls, abs_pos + 2)
  end

  defp parse_element(
         <<"<", rest2::binary>> = <<"<", c::utf8, _::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         events
       )
       when is_name_start(c) do
    parse_open_tag_name(
      rest2,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      {line, ls, abs_pos + 1},
      buf_pos + 1,
      buf_pos,
      events
    )
  end

  # Need more data - buffer might end with partial element start
  # Return elem_start (buf_pos) for incomplete
  defp parse_element(<<"<">>, _xml, buf_pos, abs_pos, line, ls, events) do
    incomplete(events, buf_pos, line, ls, abs_pos)
  end

  defp parse_element(<<"<!">>, _xml, buf_pos, abs_pos, line, ls, events) do
    incomplete(events, buf_pos, line, ls, abs_pos)
  end

  defp parse_element(<<"<!-">>, _xml, buf_pos, abs_pos, line, ls, events) do
    incomplete(events, buf_pos, line, ls, abs_pos)
  end

  defp parse_element(<<"<![">>, _xml, buf_pos, abs_pos, line, ls, events) do
    incomplete(events, buf_pos, line, ls, abs_pos)
  end

  defp parse_element(<<"<![C">>, _xml, buf_pos, abs_pos, line, ls, events) do
    incomplete(events, buf_pos, line, ls, abs_pos)
  end

  defp parse_element(<<"<![CD">>, _xml, buf_pos, abs_pos, line, ls, events) do
    incomplete(events, buf_pos, line, ls, abs_pos)
  end

  defp parse_element(<<"<![CDA">>, _xml, buf_pos, abs_pos, line, ls, events) do
    incomplete(events, buf_pos, line, ls, abs_pos)
  end

  defp parse_element(<<"<![CDAT">>, _xml, buf_pos, abs_pos, line, ls, events) do
    incomplete(events, buf_pos, line, ls, abs_pos)
  end

  defp parse_element(<<"<![CDATA">>, _xml, buf_pos, abs_pos, line, ls, events) do
    incomplete(events, buf_pos, line, ls, abs_pos)
  end

  defp parse_element(_, _xml, _buf_pos, abs_pos, line, ls, events) do
    events = [{:error, :invalid_element, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  # ============================================================================
  # Open tag name
  # ============================================================================

  defp parse_open_tag_name(
         <<>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _start,
         elem_start,
         events
       ) do
    # Tag name incomplete
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  # Fast path for ASCII name chars (most common case)
  defp parse_open_tag_name(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         elem_start,
         events
       )
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?- or c == ?. or c == ?: do
    parse_open_tag_name(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      start,
      elem_start,
      events
    )
  end

  # Slow path for non-ASCII UTF-8 name chars
  defp parse_open_tag_name(
         <<c::utf8, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         elem_start,
         events
       )
       when is_name_char(c) do
    size = utf8_size(c)

    parse_open_tag_name(
      rest,
      xml,
      buf_pos + size,
      abs_pos + size,
      line,
      ls,
      loc,
      start,
      elem_start,
      events
    )
  end

  defp parse_open_tag_name(rest, xml, buf_pos, abs_pos, line, ls, loc, start, elem_start, events) do
    name = binary_part(xml, start, buf_pos - start)
    # Use list instead of MapSet for seen attrs (faster for small attr counts)
    finish_open_tag(rest, xml, buf_pos, abs_pos, line, ls, name, [], [], loc, elem_start, events)
  end

  # ============================================================================
  # Finish open tag (parse attributes)
  # ============================================================================

  defp finish_open_tag(
         <<>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _name,
         _attrs,
         _seen,
         _loc,
         elem_start,
         events
       ) do
    # Tag incomplete (in attributes) - back up to element start
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp finish_open_tag(
         <<"/>", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         attrs,
         _seen,
         loc,
         _elem_start,
         events
       ) do
    {l, lls, lp} = loc

    events = [
      {:end_element, name, l, lls, lp} | [{:start_element, name, attrs, l, lls, lp} | events]
    ]

    parse_content(rest, xml, buf_pos + 2, abs_pos + 2, line, ls, events)
  end

  defp finish_open_tag(
         <<">", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         attrs,
         _seen,
         loc,
         _elem_start,
         events
       ) do
    {l, lls, lp} = loc
    events = [{:start_element, name, attrs, l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, events)
  end

  defp finish_open_tag(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         attrs,
         seen,
         loc,
         elem_start,
         events
       )
       when c in [?\s, ?\t] do
    finish_open_tag_ws(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      name,
      attrs,
      seen,
      loc,
      elem_start,
      events
    )
  end

  defp finish_open_tag(
         <<?\n, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         _ls,
         name,
         attrs,
         seen,
         loc,
         elem_start,
         events
       ) do
    finish_open_tag_ws(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line + 1,
      abs_pos + 1,
      name,
      attrs,
      seen,
      loc,
      elem_start,
      events
    )
  end

  # No whitespace before attribute name - this is an error
  defp finish_open_tag(
         <<c::utf8, _::binary>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _name,
         _attrs,
         _seen,
         _loc,
         _elem_start,
         events
       )
       when is_name_start(c) do
    events = [{:error, :missing_whitespace_before_attr, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  defp finish_open_tag(
         <<"/">>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _name,
         _attrs,
         _seen,
         _loc,
         elem_start,
         events
       ) do
    # Need more data for "/>" - back up to element start
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp finish_open_tag(
         _,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _name,
         _attrs,
         _seen,
         _loc,
         _elem_start,
         events
       ) do
    events = [{:error, :expected_gt_or_attr, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  # After whitespace in open tag - attribute names are now allowed
  defp finish_open_tag_ws(
         <<>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _name,
         _attrs,
         _seen,
         _loc,
         elem_start,
         events
       ) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp finish_open_tag_ws(
         <<"/>", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         attrs,
         _seen,
         loc,
         _elem_start,
         events
       ) do
    {l, lls, lp} = loc

    events = [
      {:end_element, name, l, lls, lp} | [{:start_element, name, attrs, l, lls, lp} | events]
    ]

    parse_content(rest, xml, buf_pos + 2, abs_pos + 2, line, ls, events)
  end

  defp finish_open_tag_ws(
         <<">", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         attrs,
         _seen,
         loc,
         _elem_start,
         events
       ) do
    {l, lls, lp} = loc
    events = [{:start_element, name, attrs, l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, events)
  end

  defp finish_open_tag_ws(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         attrs,
         seen,
         loc,
         elem_start,
         events
       )
       when c in [?\s, ?\t] do
    finish_open_tag_ws(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      name,
      attrs,
      seen,
      loc,
      elem_start,
      events
    )
  end

  defp finish_open_tag_ws(
         <<?\n, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         _ls,
         name,
         attrs,
         seen,
         loc,
         elem_start,
         events
       ) do
    finish_open_tag_ws(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line + 1,
      abs_pos + 1,
      name,
      attrs,
      seen,
      loc,
      elem_start,
      events
    )
  end

  defp finish_open_tag_ws(
         <<c::utf8, _::binary>> = rest,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         attrs,
         seen,
         loc,
         elem_start,
         events
       )
       when is_name_start(c) do
    parse_attr_name(
      rest,
      xml,
      buf_pos,
      abs_pos,
      line,
      ls,
      name,
      attrs,
      seen,
      loc,
      buf_pos,
      elem_start,
      events
    )
  end

  defp finish_open_tag_ws(
         <<"/">>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _name,
         _attrs,
         _seen,
         _loc,
         elem_start,
         events
       ) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp finish_open_tag_ws(
         _,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _name,
         _attrs,
         _seen,
         _loc,
         _elem_start,
         events
       ) do
    events = [{:error, :expected_gt_or_attr, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  # ============================================================================
  # Attribute parsing
  # ============================================================================

  defp parse_attr_name(
         <<>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _name,
         _attrs,
         _seen,
         _loc,
         _start,
         elem_start,
         events
       ) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  # Fast path for ASCII name chars
  defp parse_attr_name(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         attrs,
         seen,
         loc,
         start,
         elem_start,
         events
       )
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?- or c == ?. or c == ?: do
    parse_attr_name(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      name,
      attrs,
      seen,
      loc,
      start,
      elem_start,
      events
    )
  end

  # Slow path for non-ASCII UTF-8
  defp parse_attr_name(
         <<c::utf8, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         attrs,
         seen,
         loc,
         start,
         elem_start,
         events
       )
       when is_name_char(c) do
    size = utf8_size(c)

    parse_attr_name(
      rest,
      xml,
      buf_pos + size,
      abs_pos + size,
      line,
      ls,
      name,
      attrs,
      seen,
      loc,
      start,
      elem_start,
      events
    )
  end

  defp parse_attr_name(
         rest,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         attrs,
         seen,
         loc,
         start,
         elem_start,
         events
       ) do
    attr_name = binary_part(xml, start, buf_pos - start)

    parse_attr_eq(
      rest,
      xml,
      buf_pos,
      abs_pos,
      line,
      ls,
      name,
      attrs,
      seen,
      loc,
      attr_name,
      elem_start,
      events
    )
  end

  defp parse_attr_eq(
         <<>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _name,
         _attrs,
         _seen,
         _loc,
         _attr_name,
         elem_start,
         events
       ) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_attr_eq(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         attrs,
         seen,
         loc,
         attr_name,
         elem_start,
         events
       )
       when c in [?\s, ?\t] do
    parse_attr_eq(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      name,
      attrs,
      seen,
      loc,
      attr_name,
      elem_start,
      events
    )
  end

  defp parse_attr_eq(
         <<?\n, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         _ls,
         name,
         attrs,
         seen,
         loc,
         attr_name,
         elem_start,
         events
       ) do
    parse_attr_eq(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line + 1,
      abs_pos + 1,
      name,
      attrs,
      seen,
      loc,
      attr_name,
      elem_start,
      events
    )
  end

  defp parse_attr_eq(
         <<"=", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         attrs,
         seen,
         loc,
         attr_name,
         elem_start,
         events
       ) do
    parse_attr_quote(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      name,
      attrs,
      seen,
      loc,
      attr_name,
      elem_start,
      events
    )
  end

  defp parse_attr_eq(
         _,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _name,
         _attrs,
         _seen,
         _loc,
         _attr_name,
         _elem_start,
         events
       ) do
    events = [{:error, :expected_eq, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  defp parse_attr_quote(
         <<>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _name,
         _attrs,
         _seen,
         _loc,
         _attr_name,
         elem_start,
         events
       ) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_attr_quote(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         attrs,
         seen,
         loc,
         attr_name,
         elem_start,
         events
       )
       when c in [?\s, ?\t] do
    parse_attr_quote(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      name,
      attrs,
      seen,
      loc,
      attr_name,
      elem_start,
      events
    )
  end

  defp parse_attr_quote(
         <<?\n, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         _ls,
         name,
         attrs,
         seen,
         loc,
         attr_name,
         elem_start,
         events
       ) do
    parse_attr_quote(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line + 1,
      abs_pos + 1,
      name,
      attrs,
      seen,
      loc,
      attr_name,
      elem_start,
      events
    )
  end

  defp parse_attr_quote(
         <<q, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         attrs,
         seen,
         loc,
         attr_name,
         elem_start,
         events
       )
       when q in [?", ?'] do
    parse_attr_value(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      name,
      attrs,
      seen,
      loc,
      attr_name,
      q,
      buf_pos + 1,
      elem_start,
      events
    )
  end

  defp parse_attr_quote(
         _,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _name,
         _attrs,
         _seen,
         _loc,
         _attr_name,
         _elem_start,
         events
       ) do
    events = [{:error, :expected_quote, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  defp parse_attr_value(
         <<>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _name,
         _attrs,
         _seen,
         _loc,
         _attr_name,
         _quote,
         _start,
         elem_start,
         events
       ) do
    # Attribute value incomplete - back up to element start
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_attr_value(
         <<q, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         attrs,
         seen,
         loc,
         attr_name,
         q,
         start,
         elem_start,
         events
       ) do
    # End of attribute value - check for duplicate (list is faster than MapSet for small attr counts)
    value = binary_part(xml, start, buf_pos - start)
    {l, lls, lp} = loc

    {new_attrs, new_seen, events} =
      if attr_name in seen do
        # Duplicate attribute - emit error but still add it
        events = [{:error, :attr_unique, nil, l, lls, lp} | events]
        {[{attr_name, value} | attrs], seen, events}
      else
        {[{attr_name, value} | attrs], [attr_name | seen], events}
      end

    finish_open_tag(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      name,
      new_attrs,
      new_seen,
      loc,
      elem_start,
      events
    )
  end

  defp parse_attr_value(
         <<?\n, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         _ls,
         name,
         attrs,
         seen,
         loc,
         attr_name,
         quote,
         start,
         elem_start,
         events
       ) do
    parse_attr_value(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line + 1,
      abs_pos + 1,
      name,
      attrs,
      seen,
      loc,
      attr_name,
      quote,
      start,
      elem_start,
      events
    )
  end

  # < is not allowed in attribute values
  defp parse_attr_value(
         <<"<", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         attrs,
         seen,
         loc,
         attr_name,
         quote,
         start,
         elem_start,
         events
       ) do
    events = [
      {:error, :attr_lt, "'<' not allowed in attribute value", line, ls, abs_pos} | events
    ]

    # Continue parsing to recover - skip the < and continue
    parse_attr_value(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      name,
      attrs,
      seen,
      loc,
      attr_name,
      quote,
      start,
      elem_start,
      events
    )
  end

  defp parse_attr_value(
         <<_, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         attrs,
         seen,
         loc,
         attr_name,
         quote,
         start,
         elem_start,
         events
       ) do
    parse_attr_value(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      name,
      attrs,
      seen,
      loc,
      attr_name,
      quote,
      start,
      elem_start,
      events
    )
  end

  # ============================================================================
  # Close tag
  # ============================================================================

  defp parse_close_tag_name(
         <<>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _start,
         elem_start,
         events
       ) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  # Fast path for ASCII name chars
  defp parse_close_tag_name(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         elem_start,
         events
       )
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?- or c == ?. or c == ?: do
    parse_close_tag_name(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      start,
      elem_start,
      events
    )
  end

  # Slow path for non-ASCII UTF-8
  defp parse_close_tag_name(
         <<c::utf8, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         elem_start,
         events
       )
       when is_name_char(c) do
    size = utf8_size(c)

    parse_close_tag_name(
      rest,
      xml,
      buf_pos + size,
      abs_pos + size,
      line,
      ls,
      loc,
      start,
      elem_start,
      events
    )
  end

  defp parse_close_tag_name(rest, xml, buf_pos, abs_pos, line, ls, loc, start, elem_start, events) do
    name = binary_part(xml, start, buf_pos - start)
    parse_close_tag_end(rest, xml, buf_pos, abs_pos, line, ls, name, loc, elem_start, events)
  end

  defp parse_close_tag_end(
         <<>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _name,
         _loc,
         elem_start,
         events
       ) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_close_tag_end(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         loc,
         elem_start,
         events
       )
       when c in [?\s, ?\t] do
    parse_close_tag_end(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      name,
      loc,
      elem_start,
      events
    )
  end

  defp parse_close_tag_end(
         <<?\n, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         _ls,
         name,
         loc,
         elem_start,
         events
       ) do
    parse_close_tag_end(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line + 1,
      abs_pos + 1,
      name,
      loc,
      elem_start,
      events
    )
  end

  defp parse_close_tag_end(
         <<">", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         name,
         loc,
         _elem_start,
         events
       ) do
    {l, lls, lp} = loc
    events = [{:end_element, name, l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, events)
  end

  defp parse_close_tag_end(_, _xml, _buf_pos, abs_pos, line, ls, _name, _loc, _elem_start, events) do
    events = [{:error, :expected_gt, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  # ============================================================================
  # Comment
  # ============================================================================

  defp parse_comment(
         <<>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _start,
         _has_double_dash,
         elem_start,
         events
       ) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_comment(
         <<"-->", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         has_double_dash,
         _elem_start,
         events
       ) do
    comment = binary_part(xml, start, buf_pos - start)
    {l, lls, lp} = loc
    events = [{:comment, comment, l, lls, lp} | events]
    # Add error if we saw -- inside the comment (not at end)
    events =
      if has_double_dash do
        [{:error, :comment, nil, l, lls, lp} | events]
      else
        events
      end

    parse_content(rest, xml, buf_pos + 3, abs_pos + 3, line, ls, events)
  end

  # ---> is invalid (comment ending with - followed by -->)
  # Emit the comment with error and continue parsing
  defp parse_comment(
         <<"--->", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         _has_double_dash,
         _elem_start,
         events
       ) do
    # Comment content includes the trailing - (up to buf_pos + 1)
    comment = binary_part(xml, start, buf_pos - start + 1)
    {l, lls, lp} = loc
    events = [{:comment, comment, l, lls, lp} | events]
    # Emit error for the ---> ending (-- inside comment)
    events = [{:error, :comment, nil, l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 4, abs_pos + 4, line, ls, events)
  end

  # -- not followed by > is invalid, set has_double_dash to true
  defp parse_comment(
         <<"--", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         _has_double_dash,
         elem_start,
         events
       ) do
    parse_comment(
      rest,
      xml,
      buf_pos + 2,
      abs_pos + 2,
      line,
      ls,
      loc,
      start,
      true,
      elem_start,
      events
    )
  end

  defp parse_comment(
         <<"-">>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _start,
         _has_double_dash,
         elem_start,
         events
       ) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_comment(
         <<?\n, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         _ls,
         loc,
         start,
         has_double_dash,
         elem_start,
         events
       ) do
    parse_comment(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line + 1,
      abs_pos + 1,
      loc,
      start,
      has_double_dash,
      elem_start,
      events
    )
  end

  defp parse_comment(
         <<_, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         has_double_dash,
         elem_start,
         events
       ) do
    parse_comment(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      start,
      has_double_dash,
      elem_start,
      events
    )
  end

  # ============================================================================
  # CDATA
  # ============================================================================

  defp parse_cdata(<<>>, _xml, _buf_pos, abs_pos, line, ls, _loc, _start, elem_start, events) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_cdata(
         <<"]]>", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         _elem_start,
         events
       ) do
    cdata = binary_part(xml, start, buf_pos - start)
    {l, lls, lp} = loc
    events = [{:cdata, cdata, l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 3, abs_pos + 3, line, ls, events)
  end

  defp parse_cdata(<<"]]">>, _xml, _buf_pos, abs_pos, line, ls, _loc, _start, elem_start, events) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_cdata(<<"]">>, _xml, _buf_pos, abs_pos, line, ls, _loc, _start, elem_start, events) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_cdata(
         <<?\n, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         _ls,
         loc,
         start,
         elem_start,
         events
       ) do
    parse_cdata(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line + 1,
      abs_pos + 1,
      loc,
      start,
      elem_start,
      events
    )
  end

  defp parse_cdata(
         <<_, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         elem_start,
         events
       ) do
    parse_cdata(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, start, elem_start, events)
  end

  # ============================================================================
  # DOCTYPE - captures full content for DTD processing
  # Tracks quote state to properly handle < and > inside quoted strings
  # quote: nil = not in quote, ?" = in double quote, ?' = in single quote
  # ============================================================================

  defp parse_doctype(
         <<>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _start,
         _dtd_depth,
         _quote,
         elem_start,
         events
       ) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  # End of DOCTYPE (depth=1, not in quotes)
  defp parse_doctype(
         <<">", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         1,
         nil,
         _elem_start,
         events
       ) do
    content = binary_part(xml, start, buf_pos - start)
    {l, lls, lp} = loc
    events = [{:dtd, content, l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, events)
  end

  # > decrements depth only when not in quotes
  defp parse_doctype(
         <<">", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         dtd_depth,
         nil,
         elem_start,
         events
       ) do
    parse_doctype(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      start,
      dtd_depth - 1,
      nil,
      elem_start,
      events
    )
  end

  # > inside quotes - just skip
  defp parse_doctype(
         <<">", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         dtd_depth,
         quote,
         elem_start,
         events
       ) do
    parse_doctype(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      start,
      dtd_depth,
      quote,
      elem_start,
      events
    )
  end

  # < increments depth only when not in quotes
  defp parse_doctype(
         <<"<", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         dtd_depth,
         nil,
         elem_start,
         events
       ) do
    parse_doctype(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      start,
      dtd_depth + 1,
      nil,
      elem_start,
      events
    )
  end

  # < inside quotes - just skip
  defp parse_doctype(
         <<"<", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         dtd_depth,
         quote,
         elem_start,
         events
       ) do
    parse_doctype(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      start,
      dtd_depth,
      quote,
      elem_start,
      events
    )
  end

  # Double quote - toggle quote state
  defp parse_doctype(
         <<"\"", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         dtd_depth,
         nil,
         elem_start,
         events
       ) do
    parse_doctype(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      start,
      dtd_depth,
      ?",
      elem_start,
      events
    )
  end

  defp parse_doctype(
         <<"\"", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         dtd_depth,
         ?",
         elem_start,
         events
       ) do
    parse_doctype(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      start,
      dtd_depth,
      nil,
      elem_start,
      events
    )
  end

  # Single quote - toggle quote state
  defp parse_doctype(
         <<"'", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         dtd_depth,
         nil,
         elem_start,
         events
       ) do
    parse_doctype(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      start,
      dtd_depth,
      ?',
      elem_start,
      events
    )
  end

  defp parse_doctype(
         <<"'", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         dtd_depth,
         ?',
         elem_start,
         events
       ) do
    parse_doctype(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      start,
      dtd_depth,
      nil,
      elem_start,
      events
    )
  end

  defp parse_doctype(
         <<?\n, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         _ls,
         loc,
         start,
         dtd_depth,
         quote,
         elem_start,
         events
       ) do
    parse_doctype(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line + 1,
      abs_pos + 1,
      loc,
      start,
      dtd_depth,
      quote,
      elem_start,
      events
    )
  end

  # Fast path for common ASCII characters (valid XML chars in 0x20-0x7F range, excluding < > " ', plus tab and CR)
  defp parse_doctype(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         dtd_depth,
         quote,
         elem_start,
         events
       )
       when c in 0x20..0x21 or c in 0x23..0x26 or c in 0x28..0x3B or c == 0x3D or c in 0x3F..0x7F or
              c == 0x9 or c == 0xD do
    parse_doctype(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      start,
      dtd_depth,
      quote,
      elem_start,
      events
    )
  end

  # Slow path for non-ASCII UTF-8 - validate is_xml_char
  defp parse_doctype(
         <<c::utf8, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         dtd_depth,
         quote,
         elem_start,
         events
       )
       when is_xml_char(c) do
    size = utf8_size(c)

    parse_doctype(
      rest,
      xml,
      buf_pos + size,
      abs_pos + size,
      line,
      ls,
      loc,
      start,
      dtd_depth,
      quote,
      elem_start,
      events
    )
  end

  # Invalid XML character in DOCTYPE
  defp parse_doctype(
         <<c::utf8, _rest::binary>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _start,
         _dtd_depth,
         _quote,
         _elem_start,
         events
       ) do
    events = [
      {:error, :invalid_char,
       "Invalid XML character U+#{Integer.to_string(c, 16) |> String.pad_leading(4, "0")} in DOCTYPE",
       line, ls, abs_pos}
      | events
    ]

    complete(events, line, ls, abs_pos)
  end

  # ============================================================================
  # Processing instruction
  # ============================================================================

  defp parse_pi_name(<<>>, _xml, _buf_pos, abs_pos, line, ls, _loc, _start, elem_start, events) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  # Fast path for ASCII name chars
  defp parse_pi_name(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         elem_start,
         events
       )
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?- or c == ?. or c == ?: do
    parse_pi_name(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, start, elem_start, events)
  end

  # Slow path for non-ASCII UTF-8
  defp parse_pi_name(
         <<c::utf8, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         start,
         elem_start,
         events
       )
       when is_name_char(c) do
    size = utf8_size(c)

    parse_pi_name(
      rest,
      xml,
      buf_pos + size,
      abs_pos + size,
      line,
      ls,
      loc,
      start,
      elem_start,
      events
    )
  end

  defp parse_pi_name(rest, xml, buf_pos, abs_pos, line, ls, loc, start, elem_start, events) do
    target = binary_part(xml, start, buf_pos - start)

    parse_pi_content(
      rest,
      xml,
      buf_pos,
      abs_pos,
      line,
      ls,
      loc,
      target,
      buf_pos,
      elem_start,
      events
    )
  end

  defp parse_pi_content(
         <<>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _target,
         _start,
         elem_start,
         events
       ) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_pi_content(
         <<"?>", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         target,
         start,
         _elem_start,
         events
       ) do
    content = binary_part(xml, start, buf_pos - start)
    {l, lls, lp} = loc
    events = [{:processing_instruction, target, content, l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 2, abs_pos + 2, line, ls, events)
  end

  defp parse_pi_content(
         <<"?">>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _target,
         _start,
         elem_start,
         events
       ) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_pi_content(
         <<?\n, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         _ls,
         loc,
         target,
         start,
         elem_start,
         events
       ) do
    parse_pi_content(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line + 1,
      abs_pos + 1,
      loc,
      target,
      start,
      elem_start,
      events
    )
  end

  defp parse_pi_content(
         <<_, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         target,
         start,
         elem_start,
         events
       ) do
    parse_pi_content(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      target,
      start,
      elem_start,
      events
    )
  end

  # ============================================================================
  # Prolog
  # ============================================================================

  defp parse_prolog(<<>>, _xml, _buf_pos, abs_pos, line, ls, _loc, elem_start, events) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_prolog(
         <<"?>", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         _elem_start,
         events
       ) do
    {l, lls, lp} = loc
    events = [{:prolog, "xml", [], l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 2, abs_pos + 2, line, ls, events)
  end

  defp parse_prolog(<<"?">>, _xml, _buf_pos, abs_pos, line, ls, _loc, elem_start, events) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_prolog(<<c, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, elem_start, events)
       when c in [?\s, ?\t] do
    parse_prolog(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, elem_start, events)
  end

  defp parse_prolog(
         <<?\n, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         _ls,
         loc,
         elem_start,
         events
       ) do
    parse_prolog(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line + 1,
      abs_pos + 1,
      loc,
      elem_start,
      events
    )
  end

  defp parse_prolog(
         <<c::utf8, _::binary>> = rest,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         elem_start,
         events
       )
       when is_name_start(c) do
    parse_prolog_attr_name(
      rest,
      xml,
      buf_pos,
      abs_pos,
      line,
      ls,
      loc,
      [],
      buf_pos,
      elem_start,
      events
    )
  end

  defp parse_prolog(_, _xml, _buf_pos, abs_pos, line, ls, _loc, _elem_start, events) do
    events = [{:error, :expected_pi_end_or_attr, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  # Prolog attribute parsing (simplified - just skip to ?>)
  defp parse_prolog_attr_name(
         <<>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _prolog_attrs,
         _start,
         elem_start,
         events
       ) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_prolog_attr_name(
         <<"?>", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         prolog_attrs,
         _start,
         _elem_start,
         events
       ) do
    {l, lls, lp} = loc
    events = [{:prolog, "xml", Enum.reverse(prolog_attrs), l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 2, abs_pos + 2, line, ls, events)
  end

  # Fast path for ASCII name chars
  defp parse_prolog_attr_name(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         prolog_attrs,
         start,
         elem_start,
         events
       )
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?- or c == ?. or c == ?: do
    parse_prolog_attr_name(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      prolog_attrs,
      start,
      elem_start,
      events
    )
  end

  # Slow path for non-ASCII UTF-8
  defp parse_prolog_attr_name(
         <<c::utf8, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         prolog_attrs,
         start,
         elem_start,
         events
       )
       when is_name_char(c) do
    size = utf8_size(c)

    parse_prolog_attr_name(
      rest,
      xml,
      buf_pos + size,
      abs_pos + size,
      line,
      ls,
      loc,
      prolog_attrs,
      start,
      elem_start,
      events
    )
  end

  defp parse_prolog_attr_name(
         rest,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         prolog_attrs,
         start,
         elem_start,
         events
       ) do
    attr_name = binary_part(xml, start, buf_pos - start)

    parse_prolog_attr_eq(
      rest,
      xml,
      buf_pos,
      abs_pos,
      line,
      ls,
      loc,
      prolog_attrs,
      attr_name,
      elem_start,
      events
    )
  end

  defp parse_prolog_attr_eq(
         <<>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _prolog_attrs,
         _attr_name,
         elem_start,
         events
       ) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_prolog_attr_eq(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         prolog_attrs,
         attr_name,
         elem_start,
         events
       )
       when c in [?\s, ?\t] do
    parse_prolog_attr_eq(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      prolog_attrs,
      attr_name,
      elem_start,
      events
    )
  end

  defp parse_prolog_attr_eq(
         <<?\n, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         _ls,
         loc,
         prolog_attrs,
         attr_name,
         elem_start,
         events
       ) do
    parse_prolog_attr_eq(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line + 1,
      abs_pos + 1,
      loc,
      prolog_attrs,
      attr_name,
      elem_start,
      events
    )
  end

  defp parse_prolog_attr_eq(
         <<"=", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         prolog_attrs,
         attr_name,
         elem_start,
         events
       ) do
    parse_prolog_attr_quote(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      prolog_attrs,
      attr_name,
      elem_start,
      events
    )
  end

  defp parse_prolog_attr_eq(
         _,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _prolog_attrs,
         _attr_name,
         _elem_start,
         events
       ) do
    events = [{:error, :expected_eq, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  defp parse_prolog_attr_quote(
         <<>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _prolog_attrs,
         _attr_name,
         elem_start,
         events
       ) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_prolog_attr_quote(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         prolog_attrs,
         attr_name,
         elem_start,
         events
       )
       when c in [?\s, ?\t] do
    parse_prolog_attr_quote(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      prolog_attrs,
      attr_name,
      elem_start,
      events
    )
  end

  defp parse_prolog_attr_quote(
         <<?\n, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         _ls,
         loc,
         prolog_attrs,
         attr_name,
         elem_start,
         events
       ) do
    parse_prolog_attr_quote(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line + 1,
      abs_pos + 1,
      loc,
      prolog_attrs,
      attr_name,
      elem_start,
      events
    )
  end

  defp parse_prolog_attr_quote(
         <<q, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         prolog_attrs,
         attr_name,
         elem_start,
         events
       )
       when q in [?", ?'] do
    parse_prolog_attr_value(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      prolog_attrs,
      attr_name,
      q,
      buf_pos + 1,
      elem_start,
      events
    )
  end

  defp parse_prolog_attr_quote(
         _,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _prolog_attrs,
         _attr_name,
         _elem_start,
         events
       ) do
    events = [{:error, :expected_quote, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  defp parse_prolog_attr_value(
         <<>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _prolog_attrs,
         _attr_name,
         _quote,
         _start,
         elem_start,
         events
       ) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_prolog_attr_value(
         <<q, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         prolog_attrs,
         attr_name,
         q,
         start,
         elem_start,
         events
       ) do
    value = binary_part(xml, start, buf_pos - start)
    new_prolog_attrs = [{attr_name, value} | prolog_attrs]

    parse_prolog_after_attr(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      new_prolog_attrs,
      elem_start,
      events
    )
  end

  defp parse_prolog_attr_value(
         <<?\n, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         _ls,
         loc,
         prolog_attrs,
         attr_name,
         quote,
         start,
         elem_start,
         events
       ) do
    parse_prolog_attr_value(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line + 1,
      abs_pos + 1,
      loc,
      prolog_attrs,
      attr_name,
      quote,
      start,
      elem_start,
      events
    )
  end

  defp parse_prolog_attr_value(
         <<_, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         prolog_attrs,
         attr_name,
         quote,
         start,
         elem_start,
         events
       ) do
    parse_prolog_attr_value(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      prolog_attrs,
      attr_name,
      quote,
      start,
      elem_start,
      events
    )
  end

  defp parse_prolog_after_attr(
         <<>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _prolog_attrs,
         elem_start,
         events
       ) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_prolog_after_attr(
         <<"?>", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         prolog_attrs,
         _elem_start,
         events
       ) do
    {l, lls, lp} = loc
    events = [{:prolog, "xml", Enum.reverse(prolog_attrs), l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 2, abs_pos + 2, line, ls, events)
  end

  defp parse_prolog_after_attr(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         prolog_attrs,
         elem_start,
         events
       )
       when c in [?\s, ?\t] do
    # After whitespace, allow more whitespace, ?>, or attribute name
    parse_prolog_after_attr_ws(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      prolog_attrs,
      elem_start,
      events
    )
  end

  defp parse_prolog_after_attr(
         <<?\n, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         _ls,
         loc,
         prolog_attrs,
         elem_start,
         events
       ) do
    parse_prolog_after_attr_ws(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line + 1,
      abs_pos + 1,
      loc,
      prolog_attrs,
      elem_start,
      events
    )
  end

  # No whitespace before next attribute name - this is an error
  defp parse_prolog_after_attr(
         <<c::utf8, _::binary>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _prolog_attrs,
         _elem_start,
         events
       )
       when is_name_start(c) do
    events = [{:error, :missing_whitespace_before_attr, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  defp parse_prolog_after_attr(
         _,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _prolog_attrs,
         _elem_start,
         events
       ) do
    events = [{:error, :expected_pi_end_or_attr, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  # After we've seen whitespace, allow attribute names
  defp parse_prolog_after_attr_ws(
         <<>>,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _prolog_attrs,
         elem_start,
         events
       ) do
    incomplete(events, elem_start, line, ls, abs_pos)
  end

  defp parse_prolog_after_attr_ws(
         <<"?>", rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         prolog_attrs,
         _elem_start,
         events
       ) do
    {l, lls, lp} = loc
    events = [{:prolog, "xml", Enum.reverse(prolog_attrs), l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 2, abs_pos + 2, line, ls, events)
  end

  defp parse_prolog_after_attr_ws(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         prolog_attrs,
         elem_start,
         events
       )
       when c in [?\s, ?\t] do
    parse_prolog_after_attr_ws(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line,
      ls,
      loc,
      prolog_attrs,
      elem_start,
      events
    )
  end

  defp parse_prolog_after_attr_ws(
         <<?\n, rest::binary>>,
         xml,
         buf_pos,
         abs_pos,
         line,
         _ls,
         loc,
         prolog_attrs,
         elem_start,
         events
       ) do
    parse_prolog_after_attr_ws(
      rest,
      xml,
      buf_pos + 1,
      abs_pos + 1,
      line + 1,
      abs_pos + 1,
      loc,
      prolog_attrs,
      elem_start,
      events
    )
  end

  defp parse_prolog_after_attr_ws(
         <<c::utf8, _::binary>> = rest,
         xml,
         buf_pos,
         abs_pos,
         line,
         ls,
         loc,
         prolog_attrs,
         elem_start,
         events
       )
       when is_name_start(c) do
    parse_prolog_attr_name(
      rest,
      xml,
      buf_pos,
      abs_pos,
      line,
      ls,
      loc,
      prolog_attrs,
      buf_pos,
      elem_start,
      events
    )
  end

  defp parse_prolog_after_attr_ws(
         _,
         _xml,
         _buf_pos,
         abs_pos,
         line,
         ls,
         _loc,
         _prolog_attrs,
         _elem_start,
         events
       ) do
    events = [{:error, :expected_pi_end_or_attr, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end
end
