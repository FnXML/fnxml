defmodule FnXML.Legacy.FastExBlkParser do
  @moduledoc """
  Fast block-at-a-time XML parser optimized for speed.

  **Note**: This parser is kept for benchmarking and backwards compatibility only.
  It is a legacy implementation that may be removed in future versions.
  For production use, prefer `FnXML.Parser` instead.

  This parser eliminates:
  - `:space` events - whitespace between elements is ignored
  - Position tracking - events have `nil` for location

  Whitespace within text content (mixed content) is preserved.

  ## Usage

      # One-shot parsing
      events = FnXML.Legacy.FastExBlkParser.parse("<root><child/></root>")

      # Stream from file (lazy, batched events)
      events = File.stream!("large.xml", [], 64_000)
               |> FnXML.Legacy.FastExBlkParser.stream()
               |> Enum.to_list()
  """

  # Inline frequently called helper functions
  @compile {:inline, utf8_size: 1}

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

  Returns `{events, leftover_pos}` where:
  - `events` - List of parsed events (in order)
  - `leftover_pos` - Position where incomplete element starts, or `nil` if complete
  """
  def parse_block(block, is_start \\ true) do
    # Check for UTF-16 BOM at document start
    if is_start do
      case block do
        <<0xFE, 0xFF, _::binary>> ->
          # UTF-16 BE BOM
          {[{:error, :utf16, nil, nil}], nil}

        <<0xFF, 0xFE, _::binary>> ->
          # UTF-16 LE BOM
          {[{:error, :utf16, nil, nil}], nil}

        _ ->
          # Normal parsing
          parse_content(block, block, 0, [])
      end
    else
      parse_content(block, block, 0, [])
    end
  end

  # ============================================================================
  # Stream Helpers
  # ============================================================================

  # State tuple: {source, leftover, is_start, done}

  defp init_stream(enumerable) do
    {enumerable, nil, true, false}
  end

  defp next_batch({_source, _leftover, _is_start, true} = state) do
    {:halt, state}
  end

  defp next_batch({source, leftover, is_start, false}) do
    case get_chunk(source) do
      {:ok, chunk, rest} ->
        if leftover do
          handle_leftover(rest, leftover, chunk, is_start)
        else
          handle_chunk(rest, chunk, is_start)
        end

      :eof ->
        {:halt, {source, leftover, is_start, true}}
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
  defp handle_chunk(rest, chunk, is_start) do
    {events, leftover_pos} = parse_block(chunk, is_start)

    if leftover_pos do
      leftover = binary_part(chunk, leftover_pos, byte_size(chunk) - leftover_pos)
      {events, {rest, leftover, false, false}}
    else
      {events, {rest, nil, false, false}}
    end
  end

  # Handle leftover from previous chunk using mini-block approach
  defp handle_leftover(rest, leftover, chunk, is_start) do
    case :binary.match(chunk, ">") do
      {pos, 1} ->
        # Create mini-block: leftover + portion up to and including '>'
        mini = leftover <> binary_part(chunk, 0, pos + 1)
        {events, leftover_pos} = parse_block(mini, is_start)

        if leftover_pos do
          # Still incomplete - extract new leftover and try next '>'
          new_leftover = binary_part(mini, leftover_pos, byte_size(mini) - leftover_pos)
          handle_leftover_continue(rest, new_leftover, chunk, pos + 1, events)
        else
          # Mini-block complete - parse rest of chunk
          parse_rest_of_chunk(rest, chunk, pos + 1, events)
        end

      :nomatch ->
        # No '>' in chunk - append entire chunk to leftover
        {[], {rest, leftover <> chunk, is_start, false}}
    end
  end

  # Continue handling leftover when first '>' wasn't enough
  defp handle_leftover_continue(rest, leftover, chunk, search_start, acc_events) do
    remaining = byte_size(chunk) - search_start

    case :binary.match(chunk, ">", [{:scope, {search_start, remaining}}]) do
      {pos, 1} ->
        mini = leftover <> binary_part(chunk, search_start, pos - search_start + 1)
        {events, leftover_pos} = parse_block(mini, false)

        all_events = acc_events ++ events

        if leftover_pos do
          new_leftover = binary_part(mini, leftover_pos, byte_size(mini) - leftover_pos)
          handle_leftover_continue(rest, new_leftover, chunk, pos + 1, all_events)
        else
          parse_rest_of_chunk(rest, chunk, pos + 1, all_events)
        end

      :nomatch ->
        # No more '>' - buffer leftover + rest of chunk
        new_leftover = leftover <> binary_part(chunk, search_start, remaining)
        {acc_events, {rest, new_leftover, false, false}}
    end
  end

  # Parse the rest of a chunk after mini-block completed
  defp parse_rest_of_chunk(rest, chunk, start_pos, acc_events) do
    chunk_remaining = byte_size(chunk) - start_pos

    if chunk_remaining > 0 do
      rest_chunk = binary_part(chunk, start_pos, chunk_remaining)
      {events, leftover_pos} = parse_block(rest_chunk, false)

      all_events = acc_events ++ events

      if leftover_pos do
        leftover = binary_part(rest_chunk, leftover_pos, byte_size(rest_chunk) - leftover_pos)
        {all_events, {rest, leftover, false, false}}
      else
        {all_events, {rest, nil, false, false}}
      end
    else
      {acc_events, {rest, nil, false, false}}
    end
  end

  # ============================================================================
  # Content parsing - entry point
  # ============================================================================

  # Buffer empty - block complete
  defp parse_content(<<>>, _xml, _buf_pos, events) do
    {:lists.reverse(events), nil}
  end

  # XML declaration
  defp parse_content(<<"<?xml ", rest::binary>>, xml, buf_pos, events) do
    parse_prolog(rest, xml, buf_pos + 6, buf_pos, [], events)
  end

  defp parse_content(<<"<?xml\t", rest::binary>>, xml, buf_pos, events) do
    parse_prolog(rest, xml, buf_pos + 6, buf_pos, [], events)
  end

  defp parse_content(<<"<?xml\n", rest::binary>>, xml, buf_pos, events) do
    parse_prolog(rest, xml, buf_pos + 6, buf_pos, [], events)
  end

  # Element start
  defp parse_content(<<"<", _::binary>> = rest, xml, buf_pos, events) do
    parse_element(rest, xml, buf_pos, buf_pos, events)
  end

  # Whitespace at top level or between elements - check if it's followed by text or element
  defp parse_content(<<c, rest::binary>>, xml, buf_pos, events)
       when c in [?\s, ?\t, ?\r, ?\n] do
    # Track where whitespace started
    skip_whitespace(rest, xml, buf_pos + 1, buf_pos, events)
  end

  # Non-whitespace text content - parse it
  defp parse_content(rest, xml, buf_pos, events) do
    parse_text(rest, xml, buf_pos, buf_pos, events)
  end

  # Skip whitespace until we hit an element or non-whitespace
  # ws_start tracks where the whitespace began
  defp skip_whitespace(<<>>, _xml, _buf_pos, _ws_start, events) do
    {:lists.reverse(events), nil}
  end

  defp skip_whitespace(<<c, rest::binary>>, xml, buf_pos, ws_start, events)
       when c in [?\s, ?\t, ?\r, ?\n] do
    skip_whitespace(rest, xml, buf_pos + 1, ws_start, events)
  end

  defp skip_whitespace(<<"<", _::binary>> = rest, xml, buf_pos, _ws_start, events) do
    # Whitespace followed by element - discard the whitespace
    parse_element(rest, xml, buf_pos, buf_pos, events)
  end

  # Non-whitespace after whitespace - this is text content, include the whitespace
  defp skip_whitespace(rest, xml, buf_pos, ws_start, events) do
    # Include the whitespace we skipped as part of text content
    parse_text(rest, xml, buf_pos, ws_start, events)
  end

  # ============================================================================
  # Text parsing - character content
  # ============================================================================

  defp parse_text(<<>>, xml, buf_pos, start, events) do
    # Emit text accumulated so far and return
    events =
      if buf_pos > start do
        text = binary_part(xml, start, buf_pos - start)
        [{:characters, text, nil} | events]
      else
        events
      end

    {:lists.reverse(events), nil}
  end

  defp parse_text(<<"<", _::binary>> = rest, xml, buf_pos, start, events) do
    # Emit accumulated text
    events =
      if buf_pos > start do
        text = binary_part(xml, start, buf_pos - start)
        [{:characters, text, nil} | events]
      else
        events
      end

    # Parse element - buf_pos is where '<' starts
    parse_element(rest, xml, buf_pos, buf_pos, events)
  end

  # ]]> is not allowed in text content (outside CDATA)
  defp parse_text(<<"]]>", rest::binary>>, xml, buf_pos, start, events) do
    # Emit text accumulated so far (if any)
    events =
      if buf_pos > start do
        text = binary_part(xml, start, buf_pos - start)
        [{:characters, text, nil} | events]
      else
        events
      end

    # Emit error for ]]> in content
    events = [
      {:error, :text_cdata_end, "']]>' not allowed in text content", nil, nil, nil} | events
    ]

    # Continue parsing after the illegal sequence (new text starts after ]]>)
    parse_text(rest, xml, buf_pos + 3, buf_pos + 3, events)
  end

  defp parse_text(<<_, rest::binary>>, xml, buf_pos, start, events) do
    parse_text(rest, xml, buf_pos + 1, start, events)
  end

  # ============================================================================
  # Element dispatch
  # ============================================================================

  defp parse_element(<<"<!--", rest::binary>>, xml, buf_pos, elem_start, events) do
    parse_comment(rest, xml, buf_pos + 4, elem_start, buf_pos + 4, false, events)
  end

  defp parse_element(<<"<![CDATA[", rest::binary>>, xml, buf_pos, elem_start, events) do
    parse_cdata(rest, xml, buf_pos + 9, elem_start, buf_pos + 9, events)
  end

  defp parse_element(<<"<!DOCTYPE", rest::binary>>, xml, buf_pos, elem_start, events) do
    parse_doctype(rest, xml, buf_pos + 9, elem_start, buf_pos + 2, 1, nil, events)
  end

  defp parse_element(
         <<"</", rest2::binary>> = <<"</", c::utf8, _::binary>>,
         xml,
         buf_pos,
         elem_start,
         events
       )
       when is_name_start(c) do
    parse_close_tag_name(rest2, xml, buf_pos + 2, elem_start, buf_pos + 2, events)
  end

  # Invalid close tag name start character
  defp parse_element(<<"</", _::binary>>, _xml, buf_pos, _elem_start, events) do
    events = [
      {:error, :invalid_close_tag, "Close tag must start with a valid name character", nil, nil,
       nil}
      | events
    ]

    {:lists.reverse(events), buf_pos + 2}
  end

  defp parse_element(
         <<"<?", rest2::binary>> = <<"<?", c::utf8, _::binary>>,
         xml,
         buf_pos,
         elem_start,
         events
       )
       when is_name_start(c) do
    parse_pi_name(rest2, xml, buf_pos + 2, elem_start, buf_pos + 2, events)
  end

  # Invalid PI target start character
  defp parse_element(<<"<?", _::binary>>, _xml, buf_pos, _elem_start, events) do
    events = [
      {:error, :invalid_pi_target, "PI target must start with a valid name character", nil, nil,
       nil}
      | events
    ]

    {:lists.reverse(events), buf_pos + 2}
  end

  defp parse_element(
         <<"<", rest2::binary>> = <<"<", c::utf8, _::binary>>,
         xml,
         buf_pos,
         elem_start,
         events
       )
       when is_name_start(c) do
    parse_open_tag_name(rest2, xml, buf_pos + 1, elem_start, buf_pos + 1, events)
  end

  # Need more data - buffer might end with partial element start
  defp parse_element(<<"<">>, _xml, _buf_pos, elem_start, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_element(<<"<!">>, _xml, _buf_pos, elem_start, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_element(<<"<!-">>, _xml, _buf_pos, elem_start, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_element(<<"<![">>, _xml, _buf_pos, elem_start, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_element(<<"<![C">>, _xml, _buf_pos, elem_start, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_element(<<"<![CD">>, _xml, _buf_pos, elem_start, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_element(<<"<![CDA">>, _xml, _buf_pos, elem_start, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_element(<<"<![CDAT">>, _xml, _buf_pos, elem_start, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_element(<<"<![CDATA">>, _xml, _buf_pos, elem_start, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_element(_, _xml, _buf_pos, _elem_start, events) do
    events = [{:error, :invalid_element, nil, nil} | events]
    {:lists.reverse(events), nil}
  end

  # ============================================================================
  # Open tag name
  # ============================================================================

  defp parse_open_tag_name(<<>>, _xml, _buf_pos, elem_start, _start, events) do
    {:lists.reverse(events), elem_start}
  end

  # Fast path for ASCII name chars
  defp parse_open_tag_name(<<c, rest::binary>>, xml, buf_pos, elem_start, start, events)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?- or c == ?. or c == ?: do
    parse_open_tag_name(rest, xml, buf_pos + 1, elem_start, start, events)
  end

  # Slow path for non-ASCII UTF-8
  defp parse_open_tag_name(<<c::utf8, rest::binary>>, xml, buf_pos, elem_start, start, events)
       when is_name_char(c) do
    size = utf8_size(c)
    parse_open_tag_name(rest, xml, buf_pos + size, elem_start, start, events)
  end

  defp parse_open_tag_name(rest, xml, buf_pos, elem_start, start, events) do
    name = binary_part(xml, start, buf_pos - start)
    finish_open_tag(rest, xml, buf_pos, name, [], [], elem_start, events)
  end

  # ============================================================================
  # Finish open tag (parse attributes)
  # ============================================================================

  defp finish_open_tag(<<>>, _xml, _buf_pos, _name, _attrs, _seen, elem_start, events) do
    {:lists.reverse(events), elem_start}
  end

  defp finish_open_tag(
         <<"/>", rest::binary>>,
         xml,
         buf_pos,
         name,
         attrs,
         _seen,
         _elem_start,
         events
       ) do
    events = [{:end_element, name} | [{:start_element, name, attrs, nil} | events]]
    parse_content(rest, xml, buf_pos + 2, events)
  end

  defp finish_open_tag(
         <<">", rest::binary>>,
         xml,
         buf_pos,
         name,
         attrs,
         _seen,
         _elem_start,
         events
       ) do
    events = [{:start_element, name, attrs, nil} | events]
    parse_content(rest, xml, buf_pos + 1, events)
  end

  defp finish_open_tag(<<c, rest::binary>>, xml, buf_pos, name, attrs, seen, elem_start, events)
       when c in [?\s, ?\t, ?\r, ?\n] do
    finish_open_tag(rest, xml, buf_pos + 1, name, attrs, seen, elem_start, events)
  end

  defp finish_open_tag(
         <<c::utf8, _::binary>> = rest,
         xml,
         buf_pos,
         name,
         attrs,
         seen,
         elem_start,
         events
       )
       when is_name_start(c) do
    parse_attr_name(rest, xml, buf_pos, name, attrs, seen, elem_start, buf_pos, events)
  end

  defp finish_open_tag(<<"/">>, _xml, _buf_pos, _name, _attrs, _seen, elem_start, events) do
    {:lists.reverse(events), elem_start}
  end

  defp finish_open_tag(_, _xml, _buf_pos, _name, _attrs, _seen, _elem_start, events) do
    events = [{:error, :expected_gt_or_attr, nil, nil} | events]
    {:lists.reverse(events), nil}
  end

  # ============================================================================
  # Attribute parsing
  # ============================================================================

  defp parse_attr_name(<<>>, _xml, _buf_pos, _name, _attrs, _seen, elem_start, _start, events) do
    {:lists.reverse(events), elem_start}
  end

  # Fast path for ASCII name chars
  defp parse_attr_name(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         name,
         attrs,
         seen,
         elem_start,
         start,
         events
       )
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?- or c == ?. or c == ?: do
    parse_attr_name(rest, xml, buf_pos + 1, name, attrs, seen, elem_start, start, events)
  end

  # Slow path for non-ASCII UTF-8
  defp parse_attr_name(
         <<c::utf8, rest::binary>>,
         xml,
         buf_pos,
         name,
         attrs,
         seen,
         elem_start,
         start,
         events
       )
       when is_name_char(c) do
    size = utf8_size(c)
    parse_attr_name(rest, xml, buf_pos + size, name, attrs, seen, elem_start, start, events)
  end

  defp parse_attr_name(rest, xml, buf_pos, name, attrs, seen, elem_start, start, events) do
    attr_name = binary_part(xml, start, buf_pos - start)
    parse_attr_eq(rest, xml, buf_pos, name, attrs, seen, elem_start, attr_name, events)
  end

  defp parse_attr_eq(<<>>, _xml, _buf_pos, _name, _attrs, _seen, elem_start, _attr_name, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_attr_eq(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         name,
         attrs,
         seen,
         elem_start,
         attr_name,
         events
       )
       when c in [?\s, ?\t, ?\r, ?\n] do
    parse_attr_eq(rest, xml, buf_pos + 1, name, attrs, seen, elem_start, attr_name, events)
  end

  defp parse_attr_eq(
         <<"=", rest::binary>>,
         xml,
         buf_pos,
         name,
         attrs,
         seen,
         elem_start,
         attr_name,
         events
       ) do
    parse_attr_quote(rest, xml, buf_pos + 1, name, attrs, seen, elem_start, attr_name, events)
  end

  defp parse_attr_eq(_, _xml, _buf_pos, _name, _attrs, _seen, _elem_start, _attr_name, events) do
    events = [{:error, :expected_eq, nil, nil} | events]
    {:lists.reverse(events), nil}
  end

  defp parse_attr_quote(
         <<>>,
         _xml,
         _buf_pos,
         _name,
         _attrs,
         _seen,
         elem_start,
         _attr_name,
         events
       ) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_attr_quote(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         name,
         attrs,
         seen,
         elem_start,
         attr_name,
         events
       )
       when c in [?\s, ?\t, ?\r, ?\n] do
    parse_attr_quote(rest, xml, buf_pos + 1, name, attrs, seen, elem_start, attr_name, events)
  end

  defp parse_attr_quote(
         <<q, rest::binary>>,
         xml,
         buf_pos,
         name,
         attrs,
         seen,
         elem_start,
         attr_name,
         events
       )
       when q in [?", ?'] do
    parse_attr_value(
      rest,
      xml,
      buf_pos + 1,
      name,
      attrs,
      seen,
      elem_start,
      attr_name,
      q,
      buf_pos + 1,
      events
    )
  end

  defp parse_attr_quote(_, _xml, _buf_pos, _name, _attrs, _seen, _elem_start, _attr_name, events) do
    events = [{:error, :expected_quote, nil, nil} | events]
    {:lists.reverse(events), nil}
  end

  defp parse_attr_value(
         <<>>,
         _xml,
         _buf_pos,
         _name,
         _attrs,
         _seen,
         elem_start,
         _attr_name,
         _quote,
         _start,
         events
       ) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_attr_value(
         <<q, rest::binary>>,
         xml,
         buf_pos,
         name,
         attrs,
         seen,
         elem_start,
         attr_name,
         q,
         start,
         events
       ) do
    value = binary_part(xml, start, buf_pos - start)

    {new_attrs, new_seen, events} =
      if attr_name in seen do
        events = [{:error, :attr_unique, nil, nil} | events]
        {[{attr_name, value} | attrs], seen, events}
      else
        {[{attr_name, value} | attrs], [attr_name | seen], events}
      end

    finish_open_tag(rest, xml, buf_pos + 1, name, new_attrs, new_seen, elem_start, events)
  end

  # < is not allowed in attribute values
  defp parse_attr_value(
         <<"<", rest::binary>>,
         xml,
         buf_pos,
         name,
         attrs,
         seen,
         elem_start,
         attr_name,
         quote,
         start,
         events
       ) do
    events = [{:error, :attr_lt, "'<' not allowed in attribute value", nil, nil, nil} | events]
    # Continue parsing to recover - skip the < and continue
    parse_attr_value(
      rest,
      xml,
      buf_pos + 1,
      name,
      attrs,
      seen,
      elem_start,
      attr_name,
      quote,
      start,
      events
    )
  end

  defp parse_attr_value(
         <<_, rest::binary>>,
         xml,
         buf_pos,
         name,
         attrs,
         seen,
         elem_start,
         attr_name,
         quote,
         start,
         events
       ) do
    parse_attr_value(
      rest,
      xml,
      buf_pos + 1,
      name,
      attrs,
      seen,
      elem_start,
      attr_name,
      quote,
      start,
      events
    )
  end

  # ============================================================================
  # Close tag
  # ============================================================================

  defp parse_close_tag_name(<<>>, _xml, _buf_pos, elem_start, _start, events) do
    {:lists.reverse(events), elem_start}
  end

  # Fast path for ASCII name chars
  defp parse_close_tag_name(<<c, rest::binary>>, xml, buf_pos, elem_start, start, events)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?- or c == ?. or c == ?: do
    parse_close_tag_name(rest, xml, buf_pos + 1, elem_start, start, events)
  end

  # Slow path for non-ASCII UTF-8
  defp parse_close_tag_name(<<c::utf8, rest::binary>>, xml, buf_pos, elem_start, start, events)
       when is_name_char(c) do
    size = utf8_size(c)
    parse_close_tag_name(rest, xml, buf_pos + size, elem_start, start, events)
  end

  defp parse_close_tag_name(rest, xml, buf_pos, elem_start, start, events) do
    name = binary_part(xml, start, buf_pos - start)
    parse_close_tag_end(rest, xml, buf_pos, elem_start, name, events)
  end

  defp parse_close_tag_end(<<>>, _xml, _buf_pos, elem_start, _name, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_close_tag_end(<<c, rest::binary>>, xml, buf_pos, elem_start, name, events)
       when c in [?\s, ?\t, ?\r, ?\n] do
    parse_close_tag_end(rest, xml, buf_pos + 1, elem_start, name, events)
  end

  defp parse_close_tag_end(<<">", rest::binary>>, xml, buf_pos, _elem_start, name, events) do
    events = [{:end_element, name} | events]
    parse_content(rest, xml, buf_pos + 1, events)
  end

  defp parse_close_tag_end(_, _xml, _buf_pos, _elem_start, _name, events) do
    events = [{:error, :expected_gt, nil, nil} | events]
    {:lists.reverse(events), nil}
  end

  # ============================================================================
  # Comment
  # ============================================================================

  defp parse_comment(<<>>, _xml, _buf_pos, elem_start, _start, _has_double_dash, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_comment(
         <<"-->", rest::binary>>,
         xml,
         buf_pos,
         _elem_start,
         start,
         has_double_dash,
         events
       ) do
    comment = binary_part(xml, start, buf_pos - start)
    events = [{:comment, comment, nil} | events]

    events =
      if has_double_dash do
        [{:error, :comment, nil, nil} | events]
      else
        events
      end

    parse_content(rest, xml, buf_pos + 3, events)
  end

  defp parse_comment(
         <<"--", rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         start,
         _has_double_dash,
         events
       ) do
    parse_comment(rest, xml, buf_pos + 2, elem_start, start, true, events)
  end

  defp parse_comment(<<"-">>, _xml, _buf_pos, elem_start, _start, _has_double_dash, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_comment(
         <<_, rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         start,
         has_double_dash,
         events
       ) do
    parse_comment(rest, xml, buf_pos + 1, elem_start, start, has_double_dash, events)
  end

  # ============================================================================
  # CDATA
  # ============================================================================

  defp parse_cdata(<<>>, _xml, _buf_pos, elem_start, _start, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_cdata(<<"]]>", rest::binary>>, xml, buf_pos, _elem_start, start, events) do
    cdata = binary_part(xml, start, buf_pos - start)
    events = [{:cdata, cdata, nil} | events]
    parse_content(rest, xml, buf_pos + 3, events)
  end

  defp parse_cdata(<<"]]">>, _xml, _buf_pos, elem_start, _start, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_cdata(<<"]">>, _xml, _buf_pos, elem_start, _start, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_cdata(<<_, rest::binary>>, xml, buf_pos, elem_start, start, events) do
    parse_cdata(rest, xml, buf_pos + 1, elem_start, start, events)
  end

  # ============================================================================
  # DOCTYPE
  # Tracks quote state: nil = not in quote, ?" = double quote, ?' = single quote
  # ============================================================================

  defp parse_doctype(<<>>, _xml, _buf_pos, elem_start, _start, _dtd_depth, _quote, events) do
    {:lists.reverse(events), elem_start}
  end

  # End of DOCTYPE (depth=1, not in quotes)
  defp parse_doctype(<<">", rest::binary>>, xml, buf_pos, _elem_start, start, 1, nil, events) do
    content = binary_part(xml, start, buf_pos - start)
    events = [{:dtd, content, nil} | events]
    parse_content(rest, xml, buf_pos + 1, events)
  end

  # > decrements depth only when not in quotes
  defp parse_doctype(
         <<">", rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         start,
         dtd_depth,
         nil,
         events
       ) do
    parse_doctype(rest, xml, buf_pos + 1, elem_start, start, dtd_depth - 1, nil, events)
  end

  # > inside quotes - just skip
  defp parse_doctype(
         <<">", rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         start,
         dtd_depth,
         quote,
         events
       ) do
    parse_doctype(rest, xml, buf_pos + 1, elem_start, start, dtd_depth, quote, events)
  end

  # < increments depth only when not in quotes
  defp parse_doctype(
         <<"<", rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         start,
         dtd_depth,
         nil,
         events
       ) do
    parse_doctype(rest, xml, buf_pos + 1, elem_start, start, dtd_depth + 1, nil, events)
  end

  # < inside quotes - just skip
  defp parse_doctype(
         <<"<", rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         start,
         dtd_depth,
         quote,
         events
       ) do
    parse_doctype(rest, xml, buf_pos + 1, elem_start, start, dtd_depth, quote, events)
  end

  # Double quote - toggle quote state
  defp parse_doctype(
         <<"\"", rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         start,
         dtd_depth,
         nil,
         events
       ) do
    parse_doctype(rest, xml, buf_pos + 1, elem_start, start, dtd_depth, ?", events)
  end

  defp parse_doctype(
         <<"\"", rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         start,
         dtd_depth,
         ?",
         events
       ) do
    parse_doctype(rest, xml, buf_pos + 1, elem_start, start, dtd_depth, nil, events)
  end

  # Single quote - toggle quote state
  defp parse_doctype(
         <<"'", rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         start,
         dtd_depth,
         nil,
         events
       ) do
    parse_doctype(rest, xml, buf_pos + 1, elem_start, start, dtd_depth, ?', events)
  end

  defp parse_doctype(
         <<"'", rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         start,
         dtd_depth,
         ?',
         events
       ) do
    parse_doctype(rest, xml, buf_pos + 1, elem_start, start, dtd_depth, nil, events)
  end

  # Fast path for common ASCII characters (valid XML chars, excluding < > " ')
  defp parse_doctype(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         start,
         dtd_depth,
         quote,
         events
       )
       when c in 0x20..0x21 or c in 0x23..0x26 or c in 0x28..0x3B or c == 0x3D or c in 0x3F..0x7F or
              c == 0x9 or c == 0xA or c == 0xD do
    parse_doctype(rest, xml, buf_pos + 1, elem_start, start, dtd_depth, quote, events)
  end

  # Slow path for non-ASCII UTF-8 - validate is_xml_char
  defp parse_doctype(
         <<c::utf8, rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         start,
         dtd_depth,
         quote,
         events
       )
       when is_xml_char(c) do
    size = utf8_size(c)
    parse_doctype(rest, xml, buf_pos + size, elem_start, start, dtd_depth, quote, events)
  end

  # Invalid XML character in DOCTYPE
  defp parse_doctype(
         <<c::utf8, _rest::binary>>,
         _xml,
         buf_pos,
         _elem_start,
         _start,
         _dtd_depth,
         _quote,
         events
       ) do
    events = [
      {:error, :invalid_char,
       "Invalid XML character U+#{Integer.to_string(c, 16) |> String.pad_leading(4, "0")} in DOCTYPE",
       nil, nil, nil}
      | events
    ]

    {:lists.reverse(events), buf_pos}
  end

  # ============================================================================
  # Processing instruction
  # ============================================================================

  defp parse_pi_name(<<>>, _xml, _buf_pos, elem_start, _start, events) do
    {:lists.reverse(events), elem_start}
  end

  # Fast path for ASCII name chars
  defp parse_pi_name(<<c, rest::binary>>, xml, buf_pos, elem_start, start, events)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?- or c == ?. or c == ?: do
    parse_pi_name(rest, xml, buf_pos + 1, elem_start, start, events)
  end

  # Slow path for non-ASCII UTF-8
  defp parse_pi_name(<<c::utf8, rest::binary>>, xml, buf_pos, elem_start, start, events)
       when is_name_char(c) do
    size = utf8_size(c)
    parse_pi_name(rest, xml, buf_pos + size, elem_start, start, events)
  end

  defp parse_pi_name(rest, xml, buf_pos, elem_start, start, events) do
    target = binary_part(xml, start, buf_pos - start)
    parse_pi_content(rest, xml, buf_pos, elem_start, target, buf_pos, events)
  end

  defp parse_pi_content(<<>>, _xml, _buf_pos, elem_start, _target, _start, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_pi_content(<<"?>", rest::binary>>, xml, buf_pos, _elem_start, target, start, events) do
    content = binary_part(xml, start, buf_pos - start)
    events = [{:processing_instruction, target, content, nil} | events]
    parse_content(rest, xml, buf_pos + 2, events)
  end

  defp parse_pi_content(<<"?">>, _xml, _buf_pos, elem_start, _target, _start, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_pi_content(<<_, rest::binary>>, xml, buf_pos, elem_start, target, start, events) do
    parse_pi_content(rest, xml, buf_pos + 1, elem_start, target, start, events)
  end

  # ============================================================================
  # Prolog
  # ============================================================================

  defp parse_prolog(<<>>, _xml, _buf_pos, elem_start, _prolog_attrs, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_prolog(<<"?>", rest::binary>>, xml, buf_pos, _elem_start, prolog_attrs, events) do
    events = [{:prolog, "xml", Enum.reverse(prolog_attrs), nil} | events]
    parse_content(rest, xml, buf_pos + 2, events)
  end

  defp parse_prolog(<<"?">>, _xml, _buf_pos, elem_start, _prolog_attrs, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_prolog(<<c, rest::binary>>, xml, buf_pos, elem_start, prolog_attrs, events)
       when c in [?\s, ?\t, ?\r, ?\n] do
    parse_prolog(rest, xml, buf_pos + 1, elem_start, prolog_attrs, events)
  end

  defp parse_prolog(<<c::utf8, _::binary>> = rest, xml, buf_pos, elem_start, prolog_attrs, events)
       when is_name_start(c) do
    parse_prolog_attr_name(rest, xml, buf_pos, elem_start, prolog_attrs, buf_pos, events)
  end

  defp parse_prolog(_, _xml, _buf_pos, _elem_start, _prolog_attrs, events) do
    events = [{:error, :expected_pi_end_or_attr, nil, nil} | events]
    {:lists.reverse(events), nil}
  end

  # Prolog attribute parsing
  defp parse_prolog_attr_name(<<>>, _xml, _buf_pos, elem_start, _prolog_attrs, _start, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_prolog_attr_name(
         <<"?>", rest::binary>>,
         xml,
         buf_pos,
         _elem_start,
         prolog_attrs,
         _start,
         events
       ) do
    events = [{:prolog, "xml", Enum.reverse(prolog_attrs), nil} | events]
    parse_content(rest, xml, buf_pos + 2, events)
  end

  defp parse_prolog_attr_name(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         prolog_attrs,
         start,
         events
       )
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?- or c == ?. or c == ?: do
    parse_prolog_attr_name(rest, xml, buf_pos + 1, elem_start, prolog_attrs, start, events)
  end

  defp parse_prolog_attr_name(
         <<c::utf8, rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         prolog_attrs,
         start,
         events
       )
       when is_name_char(c) do
    size = utf8_size(c)
    parse_prolog_attr_name(rest, xml, buf_pos + size, elem_start, prolog_attrs, start, events)
  end

  defp parse_prolog_attr_name(rest, xml, buf_pos, elem_start, prolog_attrs, start, events) do
    attr_name = binary_part(xml, start, buf_pos - start)
    parse_prolog_attr_eq(rest, xml, buf_pos, elem_start, prolog_attrs, attr_name, events)
  end

  defp parse_prolog_attr_eq(<<>>, _xml, _buf_pos, elem_start, _prolog_attrs, _attr_name, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_prolog_attr_eq(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         prolog_attrs,
         attr_name,
         events
       )
       when c in [?\s, ?\t, ?\r, ?\n] do
    parse_prolog_attr_eq(rest, xml, buf_pos + 1, elem_start, prolog_attrs, attr_name, events)
  end

  defp parse_prolog_attr_eq(
         <<"=", rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         prolog_attrs,
         attr_name,
         events
       ) do
    parse_prolog_attr_quote(rest, xml, buf_pos + 1, elem_start, prolog_attrs, attr_name, events)
  end

  defp parse_prolog_attr_eq(_, _xml, _buf_pos, _elem_start, _prolog_attrs, _attr_name, events) do
    events = [{:error, :expected_eq, nil, nil} | events]
    {:lists.reverse(events), nil}
  end

  defp parse_prolog_attr_quote(
         <<>>,
         _xml,
         _buf_pos,
         elem_start,
         _prolog_attrs,
         _attr_name,
         events
       ) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_prolog_attr_quote(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         prolog_attrs,
         attr_name,
         events
       )
       when c in [?\s, ?\t, ?\r, ?\n] do
    parse_prolog_attr_quote(rest, xml, buf_pos + 1, elem_start, prolog_attrs, attr_name, events)
  end

  defp parse_prolog_attr_quote(
         <<q, rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         prolog_attrs,
         attr_name,
         events
       )
       when q in [?", ?'] do
    parse_prolog_attr_value(
      rest,
      xml,
      buf_pos + 1,
      elem_start,
      prolog_attrs,
      attr_name,
      q,
      buf_pos + 1,
      events
    )
  end

  defp parse_prolog_attr_quote(_, _xml, _buf_pos, _elem_start, _prolog_attrs, _attr_name, events) do
    events = [{:error, :expected_quote, nil, nil} | events]
    {:lists.reverse(events), nil}
  end

  defp parse_prolog_attr_value(
         <<>>,
         _xml,
         _buf_pos,
         elem_start,
         _prolog_attrs,
         _attr_name,
         _quote,
         _start,
         events
       ) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_prolog_attr_value(
         <<q, rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         prolog_attrs,
         attr_name,
         q,
         start,
         events
       ) do
    value = binary_part(xml, start, buf_pos - start)
    new_prolog_attrs = [{attr_name, value} | prolog_attrs]
    parse_prolog_after_attr(rest, xml, buf_pos + 1, elem_start, new_prolog_attrs, events)
  end

  defp parse_prolog_attr_value(
         <<_, rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         prolog_attrs,
         attr_name,
         quote,
         start,
         events
       ) do
    parse_prolog_attr_value(
      rest,
      xml,
      buf_pos + 1,
      elem_start,
      prolog_attrs,
      attr_name,
      quote,
      start,
      events
    )
  end

  defp parse_prolog_after_attr(<<>>, _xml, _buf_pos, elem_start, _prolog_attrs, events) do
    {:lists.reverse(events), elem_start}
  end

  defp parse_prolog_after_attr(
         <<"?>", rest::binary>>,
         xml,
         buf_pos,
         _elem_start,
         prolog_attrs,
         events
       ) do
    events = [{:prolog, "xml", Enum.reverse(prolog_attrs), nil} | events]
    parse_content(rest, xml, buf_pos + 2, events)
  end

  defp parse_prolog_after_attr(
         <<c, rest::binary>>,
         xml,
         buf_pos,
         elem_start,
         prolog_attrs,
         events
       )
       when c in [?\s, ?\t, ?\r, ?\n] do
    parse_prolog_after_attr(rest, xml, buf_pos + 1, elem_start, prolog_attrs, events)
  end

  defp parse_prolog_after_attr(
         <<c::utf8, _::binary>> = rest,
         xml,
         buf_pos,
         elem_start,
         prolog_attrs,
         events
       )
       when is_name_start(c) do
    parse_prolog_attr_name(rest, xml, buf_pos, elem_start, prolog_attrs, buf_pos, events)
  end

  defp parse_prolog_after_attr(_, _xml, _buf_pos, _elem_start, _prolog_attrs, events) do
    events = [{:error, :expected_pi_end_or_attr, nil, nil} | events]
    {:lists.reverse(events), nil}
  end
end
