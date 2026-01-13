defmodule FnXML.ExBlkParser do
  @moduledoc """
  Block-at-a-time XML parser using the same algorithm as the Zig NIF parser.

  This parser:
  - Parses one block/chunk at a time
  - Builds events into a list during block processing
  - Returns batch of events when block is complete or an element spans chunks
  - Uses `Stream.resource` to emit event batches lazily

  This approach is faster than per-event process messaging while still providing
  lazy streaming.

  ## Usage

      # One-shot parsing
      events = FnXML.ExBlkParser.parse("<root><child/></root>")

      # Stream from file (lazy, batched events)
      events = File.stream!("large.xml", [], 64_000)
               |> FnXML.ExBlkParser.stream()
               |> Enum.to_list()

      # Low-level block parsing
      {events, nil, {line, ls, abs_pos}} =
        FnXML.ExBlkParser.parse_block(xml, nil, 0, 1, 0, 0)
  """

  # Inline frequently called helper functions
  @compile {:inline, utf8_size: 1, complete: 4, incomplete: 5}

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

  # Return format helpers (match NIF format)
  defp complete(events, line, ls, abs_pos) do
    {:lists.reverse(events), nil, {line, ls, abs_pos}}
  end

  defp incomplete(events, leftover_pos, line, ls, abs_pos) do
    # Advance error at front for O(1) check
    {[{:error, :advance, nil, line, ls, abs_pos} | :lists.reverse(events)], leftover_pos, {line, ls, abs_pos}}
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

  Returns `{events, leftover_pos, {line, ls, abs_pos}}` where:
  - `events` - List of parsed events (in order)
  - `leftover_pos` - Position where incomplete element starts, or `nil` if complete
  - `{line, ls, abs_pos}` - Updated parser state

  When an element spans chunks, events will include `{:error, :advance, nil, line, ls, pos}`
  to signal that more data is needed.
  """
  def parse_block(block, prev_block, prev_pos, line, ls, abs_pos) do
    # Join with previous if needed
    {input, offset} = join_blocks(block, prev_block, prev_pos)

    # Check for UTF-16 BOM at document start
    if abs_pos == 0 do
      case input do
        <<0xFE, 0xFF, _::binary>> ->
          # UTF-16 BE BOM
          {[{:error, :utf16, nil, line, ls, abs_pos}], nil, {line, ls, abs_pos}}

        <<0xFF, 0xFE, _::binary>> ->
          # UTF-16 LE BOM
          {[{:error, :utf16, nil, line, ls, abs_pos}], nil, {line, ls, abs_pos}}

        _ ->
          # Normal parsing
          parse_content(input, input, 0, abs_pos, line, ls, [], 0, offset)
      end
    else
      parse_content(input, input, 0, abs_pos, line, ls, [], 0, offset)
    end
  end

  # ============================================================================
  # Stream Helpers
  # ============================================================================

  # State tuple: {source, prev_block, prev_pos, line, ls, abs_pos, started, done, join_count}

  defp init_stream(enumerable) do
    {enumerable, nil, 0, 1, 0, 0, false, false, 0}
  end

  defp next_batch({_source, _prev_block, _prev_pos, _line, _ls, _abs_pos, _started, true, _join_count} = state) do
    {:halt, state}
  end

  defp next_batch({source, prev_block, prev_pos, line, ls, abs_pos, started, false, join_count}) do
    case get_chunk(source) do
      {:ok, chunk, rest} ->
        handle_chunk(rest, chunk, prev_block, prev_pos, line, ls, abs_pos, started, join_count)

      :eof ->
        handle_eof(source, prev_block, prev_pos, line, ls, abs_pos, started, join_count)
    end
  end

  defp handle_chunk(rest, chunk, prev_block, prev_pos, line, ls, abs_pos, _started, join_count) do
    {events, leftover_pos, {new_line, new_ls, new_abs_pos}} =
      parse_block(chunk, prev_block, prev_pos, line, ls, abs_pos)

    case find_advance_error(events) do
      nil ->
        # Block fully parsed
        new_state = {rest, nil, 0, new_line, new_ls, new_abs_pos, true, false, 0}
        {events, new_state}

      _advance_error ->
        # Element spans chunks - need to join with next
        if join_count >= 10 do
          # Too many joins, emit error
          {[{:error, :max_chunk_span, nil, new_line, new_ls, new_abs_pos}],
           {[], nil, 0, new_line, new_ls, new_abs_pos, true, true, 0}}
        else
          new_state = {rest, chunk, leftover_pos, new_line, new_ls, new_abs_pos, true, false, join_count + 1}
          # Emit events accumulated so far (filter out advance error)
          {filter_advance_errors(events), new_state}
        end
    end
  end

  # Advance error is always at the front of the list (O(1) check)
  defp find_advance_error([{:error, :advance, nil, _, _, _} = err | _]), do: err
  defp find_advance_error(_), do: nil

  # Advance error is always at the front of the list (O(1) removal)
  defp filter_advance_errors([{:error, :advance, nil, _, _, _} | rest]), do: rest
  defp filter_advance_errors(events), do: events

  defp handle_eof(_source, nil, _prev_pos, line, ls, abs_pos, false, _join_count) do
    # Empty input
    {:halt, {[], nil, 0, line, ls, abs_pos, true, true, 0}}
  end

  defp handle_eof(_source, nil, _prev_pos, line, ls, abs_pos, true, _join_count) do
    # Normal end
    {:halt, {[], nil, 0, line, ls, abs_pos, true, true, 0}}
  end

  defp handle_eof(_source, prev_block, prev_pos, line, ls, abs_pos, _started, _join_count) do
    # Have leftover - try to parse it
    remaining = binary_part(prev_block, prev_pos, byte_size(prev_block) - prev_pos)

    if byte_size(remaining) > 0 do
      # Parse remaining data
      {events, _leftover_pos, {new_line, new_ls, _new_abs_pos}} =
        parse_block(<<>>, remaining, 0, line, ls, abs_pos)

      case find_advance_error(events) do
        nil ->
          {events, {[], nil, 0, new_line, new_ls, abs_pos, true, true, 0}}

        _advance_error ->
          # Still incomplete at EOF - error
          {[{:error, :unexpected_eof, nil, new_line, new_ls, abs_pos}],
           {[], nil, 0, new_line, new_ls, abs_pos, true, true, 0}}
      end
    else
      {:halt, {[], nil, 0, line, ls, abs_pos, true, true, 0}}
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

  defp join_blocks(block, nil, _prev_pos), do: {block, 0}

  defp join_blocks(block, prev_block, prev_pos) do
    leftover = binary_part(prev_block, prev_pos, byte_size(prev_block) - prev_pos)
    {leftover <> block, byte_size(leftover)}
  end

  # ============================================================================
  # Content parsing - entry point
  # ============================================================================

  # Buffer empty - block complete if at top level
  defp parse_content(<<>>, _xml, _buf_pos, abs_pos, line, ls, events, 0, _offset) do
    complete(events, line, ls, abs_pos)
  end

  defp parse_content(<<>>, _xml, buf_pos, abs_pos, line, ls, events, _depth, offset) do
    # Inside an element - incomplete
    # Calculate leftover_pos relative to original block
    leftover_pos = max(0, buf_pos - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  # XML declaration
  defp parse_content(<<"<?xml ", rest::binary>>, xml, buf_pos, abs_pos, line, ls, events, depth, offset) do
    parse_prolog(rest, xml, buf_pos + 6, abs_pos + 6, line, ls, {line, ls, abs_pos + 1}, events, depth, offset)
  end

  defp parse_content(<<"<?xml\t", rest::binary>>, xml, buf_pos, abs_pos, line, ls, events, depth, offset) do
    parse_prolog(rest, xml, buf_pos + 6, abs_pos + 6, line, ls, {line, ls, abs_pos + 1}, events, depth, offset)
  end

  defp parse_content(<<"<?xml\n", rest::binary>>, xml, buf_pos, abs_pos, line, _ls, events, depth, offset) do
    parse_prolog(rest, xml, buf_pos + 6, abs_pos + 6, line + 1, abs_pos + 6, {line, abs_pos + 6 - 6, abs_pos + 1}, events, depth, offset)
  end

  # Element start
  defp parse_content(<<"<", _::binary>> = rest, xml, buf_pos, abs_pos, line, ls, events, depth, offset) do
    parse_element(rest, xml, buf_pos, abs_pos, line, ls, events, depth, offset)
  end

  # All other content (text, whitespace) - let parse_text handle it
  defp parse_content(rest, xml, buf_pos, abs_pos, line, ls, events, depth, offset) do
    parse_text(rest, xml, buf_pos, abs_pos, line, ls, {line, ls, abs_pos}, buf_pos, true, events, depth, offset)
  end

  # ============================================================================
  # Text parsing
  # ============================================================================

  defp parse_text(<<>>, xml, buf_pos, abs_pos, line, ls, loc, start, all_ws, events, depth, offset) do
    # Emit text accumulated so far
    events = if buf_pos > start do
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
    if depth == 0 do
      complete(events, line, ls, abs_pos)
    else
      leftover_pos = max(0, start - offset)
      incomplete(events, leftover_pos, line, ls, abs_pos)
    end
  end

  defp parse_text(<<"<", _::binary>> = rest, xml, buf_pos, abs_pos, line, ls, loc, start, all_ws, events, depth, offset) do
    # Emit accumulated text
    events = if buf_pos > start do
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
    parse_element(rest, xml, buf_pos, abs_pos, line, ls, events, depth, offset)
  end

  # Whitespace characters - keep all_ws as-is
  # Line ending normalization: \r\n -> single line ending
  defp parse_text(<<?\r, ?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, start, all_ws, events, depth, offset) do
    parse_text(rest, xml, buf_pos + 2, abs_pos + 2, line + 1, abs_pos + 2, loc, start, all_ws, events, depth, offset)
  end

  # Line ending normalization: \r alone -> line ending
  defp parse_text(<<?\r, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, start, all_ws, events, depth, offset) do
    parse_text(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, start, all_ws, events, depth, offset)
  end

  defp parse_text(<<?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, start, all_ws, events, depth, offset) do
    parse_text(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, start, all_ws, events, depth, offset)
  end

  defp parse_text(<<c, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, start, all_ws, events, depth, offset)
       when c in [?\s, ?\t] do
    parse_text(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, start, all_ws, events, depth, offset)
  end

  # Non-whitespace - set all_ws to false
  defp parse_text(<<_, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, start, _all_ws, events, depth, offset) do
    parse_text(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, start, false, events, depth, offset)
  end

  # ============================================================================
  # Element dispatch
  # ============================================================================

  defp parse_element(<<"<!--", rest::binary>>, xml, buf_pos, abs_pos, line, ls, events, depth, offset) do
    parse_comment(rest, xml, buf_pos + 4, abs_pos + 4, line, ls, {line, ls, abs_pos + 1}, buf_pos + 4, false, events, depth, offset)
  end

  defp parse_element(<<"<![CDATA[", rest::binary>>, xml, buf_pos, abs_pos, line, ls, events, depth, offset) do
    parse_cdata(rest, xml, buf_pos + 9, abs_pos + 9, line, ls, {line, ls, abs_pos + 1}, buf_pos + 9, events, depth, offset)
  end

  defp parse_element(<<"<!DOCTYPE", rest::binary>>, xml, buf_pos, abs_pos, line, ls, events, depth, offset) do
    # Start position is after "<!" to capture "DOCTYPE ..."
    parse_doctype(rest, xml, buf_pos + 9, abs_pos + 9, line, ls, {line, ls, abs_pos + 1}, buf_pos + 2, 1, events, depth, offset)
  end

  defp parse_element(<<"</", rest::binary>>, xml, buf_pos, abs_pos, line, ls, events, depth, offset) do
    parse_close_tag_name(rest, xml, buf_pos + 2, abs_pos + 2, line, ls, {line, ls, abs_pos + 1}, buf_pos + 2, events, depth, offset)
  end

  defp parse_element(<<"<?", rest::binary>>, xml, buf_pos, abs_pos, line, ls, events, depth, offset) do
    parse_pi_name(rest, xml, buf_pos + 2, abs_pos + 2, line, ls, {line, ls, abs_pos + 1}, buf_pos + 2, events, depth, offset)
  end

  defp parse_element(<<"<", rest2::binary>> = <<"<", c::utf8, _::binary>>, xml, buf_pos, abs_pos, line, ls, events, depth, offset)
       when is_name_start(c) do
    parse_open_tag_name(rest2, xml, buf_pos + 1, abs_pos + 1, line, ls, {line, ls, abs_pos + 1}, buf_pos + 1, events, depth, offset)
  end

  # Need more data - buffer might end with partial element start
  defp parse_element(<<"<">>, _xml, buf_pos, abs_pos, line, ls, events, _depth, offset) do
    # Incomplete - return position of "<"
    leftover_pos = max(0, buf_pos - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_element(<<"<!">>, _xml, buf_pos, abs_pos, line, ls, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_element(<<"<!-">>, _xml, buf_pos, abs_pos, line, ls, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_element(<<"<![">>, _xml, buf_pos, abs_pos, line, ls, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_element(<<"<![C">>, _xml, buf_pos, abs_pos, line, ls, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_element(<<"<![CD">>, _xml, buf_pos, abs_pos, line, ls, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_element(<<"<![CDA">>, _xml, buf_pos, abs_pos, line, ls, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_element(<<"<![CDAT">>, _xml, buf_pos, abs_pos, line, ls, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_element(<<"<![CDATA">>, _xml, buf_pos, abs_pos, line, ls, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_element(_, _xml, _buf_pos, abs_pos, line, ls, events, _depth, _offset) do
    events = [{:error, :invalid_element, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  # ============================================================================
  # Open tag name
  # ============================================================================

  defp parse_open_tag_name(<<>>, _xml, _buf_pos, abs_pos, line, ls, _loc, start, events, _depth, offset) do
    # Tag name incomplete
    leftover_pos = max(0, start - 1 - offset)  # -1 to include the "<"
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  # Fast path for ASCII name chars (most common case)
  defp parse_open_tag_name(<<c, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, start, events, depth, offset)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?- or c == ?. or c == ?: do
    parse_open_tag_name(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, start, events, depth, offset)
  end

  # Slow path for non-ASCII UTF-8 name chars
  defp parse_open_tag_name(<<c::utf8, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, start, events, depth, offset)
       when is_name_char(c) do
    size = utf8_size(c)
    parse_open_tag_name(rest, xml, buf_pos + size, abs_pos + size, line, ls, loc, start, events, depth, offset)
  end

  defp parse_open_tag_name(rest, xml, buf_pos, abs_pos, line, ls, loc, start, events, depth, offset) do
    name = binary_part(xml, start, buf_pos - start)
    # Track element start (position of '<') for incomplete handling
    elem_start = start - 1
    # Use list instead of MapSet for seen attrs (faster for small attr counts)
    finish_open_tag(rest, xml, buf_pos, abs_pos, line, ls, name, [], [], elem_start, loc, events, depth, offset)
  end

  # ============================================================================
  # Finish open tag (parse attributes)
  # ============================================================================

  defp finish_open_tag(<<>>, _xml, _buf_pos, abs_pos, line, ls, _name, _attrs, _seen, elem_start, _loc, events, _depth, offset) do
    # Tag incomplete (in attributes) - back up to element start
    leftover_pos = max(0, elem_start - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp finish_open_tag(<<"/>", rest::binary>>, xml, buf_pos, abs_pos, line, ls, name, attrs, _seen, _elem_start, loc, events, depth, offset) do
    {l, lls, lp} = loc
    events = [{:end_element, name, l, lls, lp} | [{:start_element, name, :lists.reverse(attrs), l, lls, lp} | events]]
    parse_content(rest, xml, buf_pos + 2, abs_pos + 2, line, ls, events, depth, offset)
  end

  defp finish_open_tag(<<">", rest::binary>>, xml, buf_pos, abs_pos, line, ls, name, attrs, _seen, _elem_start, loc, events, depth, offset) do
    {l, lls, lp} = loc
    events = [{:start_element, name, :lists.reverse(attrs), l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, events, depth + 1, offset)
  end

  defp finish_open_tag(<<c, rest::binary>>, xml, buf_pos, abs_pos, line, ls, name, attrs, seen, elem_start, loc, events, depth, offset)
       when c in [?\s, ?\t] do
    finish_open_tag(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, name, attrs, seen, elem_start, loc, events, depth, offset)
  end

  defp finish_open_tag(<<?\r, ?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, name, attrs, seen, elem_start, loc, events, depth, offset) do
    finish_open_tag(rest, xml, buf_pos + 2, abs_pos + 2, line + 1, abs_pos + 2, name, attrs, seen, elem_start, loc, events, depth, offset)
  end

  defp finish_open_tag(<<?\r, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, name, attrs, seen, elem_start, loc, events, depth, offset) do
    finish_open_tag(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, name, attrs, seen, elem_start, loc, events, depth, offset)
  end

  defp finish_open_tag(<<?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, name, attrs, seen, elem_start, loc, events, depth, offset) do
    finish_open_tag(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, name, attrs, seen, elem_start, loc, events, depth, offset)
  end

  defp finish_open_tag(<<c::utf8, _::binary>> = rest, xml, buf_pos, abs_pos, line, ls, name, attrs, seen, elem_start, loc, events, depth, offset)
       when is_name_start(c) do
    parse_attr_name(rest, xml, buf_pos, abs_pos, line, ls, name, attrs, seen, elem_start, loc, buf_pos, events, depth, offset)
  end

  defp finish_open_tag(<<"/">>, _xml, _buf_pos, abs_pos, line, ls, _name, _attrs, _seen, elem_start, _loc, events, _depth, offset) do
    # Need more data for "/>" - back up to element start
    leftover_pos = max(0, elem_start - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp finish_open_tag(_, _xml, _buf_pos, abs_pos, line, ls, _name, _attrs, _seen, _elem_start, _loc, events, _depth, _offset) do
    events = [{:error, :expected_gt_or_attr, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  # ============================================================================
  # Attribute parsing
  # ============================================================================

  defp parse_attr_name(<<>>, _xml, _buf_pos, abs_pos, line, ls, _name, _attrs, _seen, elem_start, _loc, _start, events, _depth, offset) do
    leftover_pos = max(0, elem_start - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  # Fast path for ASCII name chars
  defp parse_attr_name(<<c, rest::binary>>, xml, buf_pos, abs_pos, line, ls, name, attrs, seen, elem_start, loc, start, events, depth, offset)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?- or c == ?. or c == ?: do
    parse_attr_name(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, name, attrs, seen, elem_start, loc, start, events, depth, offset)
  end

  # Slow path for non-ASCII UTF-8
  defp parse_attr_name(<<c::utf8, rest::binary>>, xml, buf_pos, abs_pos, line, ls, name, attrs, seen, elem_start, loc, start, events, depth, offset)
       when is_name_char(c) do
    size = utf8_size(c)
    parse_attr_name(rest, xml, buf_pos + size, abs_pos + size, line, ls, name, attrs, seen, elem_start, loc, start, events, depth, offset)
  end

  defp parse_attr_name(rest, xml, buf_pos, abs_pos, line, ls, name, attrs, seen, elem_start, loc, start, events, depth, offset) do
    attr_name = binary_part(xml, start, buf_pos - start)
    parse_attr_eq(rest, xml, buf_pos, abs_pos, line, ls, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset)
  end

  defp parse_attr_eq(<<>>, _xml, _buf_pos, abs_pos, line, ls, _name, _attrs, _seen, elem_start, _loc, _attr_name, events, _depth, offset) do
    leftover_pos = max(0, elem_start - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_attr_eq(<<c, rest::binary>>, xml, buf_pos, abs_pos, line, ls, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset)
       when c in [?\s, ?\t] do
    parse_attr_eq(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset)
  end

  defp parse_attr_eq(<<?\r, ?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset) do
    parse_attr_eq(rest, xml, buf_pos + 2, abs_pos + 2, line + 1, abs_pos + 2, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset)
  end

  defp parse_attr_eq(<<?\r, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset) do
    parse_attr_eq(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset)
  end

  defp parse_attr_eq(<<?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset) do
    parse_attr_eq(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset)
  end

  defp parse_attr_eq(<<"=", rest::binary>>, xml, buf_pos, abs_pos, line, ls, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset) do
    parse_attr_quote(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset)
  end

  defp parse_attr_eq(_, _xml, _buf_pos, abs_pos, line, ls, _name, _attrs, _seen, _elem_start, _loc, _attr_name, events, _depth, _offset) do
    events = [{:error, :expected_eq, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  defp parse_attr_quote(<<>>, _xml, _buf_pos, abs_pos, line, ls, _name, _attrs, _seen, elem_start, _loc, _attr_name, events, _depth, offset) do
    leftover_pos = max(0, elem_start - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_attr_quote(<<c, rest::binary>>, xml, buf_pos, abs_pos, line, ls, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset)
       when c in [?\s, ?\t] do
    parse_attr_quote(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset)
  end

  defp parse_attr_quote(<<?\r, ?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset) do
    parse_attr_quote(rest, xml, buf_pos + 2, abs_pos + 2, line + 1, abs_pos + 2, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset)
  end

  defp parse_attr_quote(<<?\r, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset) do
    parse_attr_quote(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset)
  end

  defp parse_attr_quote(<<?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset) do
    parse_attr_quote(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset)
  end

  defp parse_attr_quote(<<q, rest::binary>>, xml, buf_pos, abs_pos, line, ls, name, attrs, seen, elem_start, loc, attr_name, events, depth, offset)
       when q in [?", ?'] do
    parse_attr_value(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, name, attrs, seen, elem_start, loc, attr_name, q, buf_pos + 1, events, depth, offset)
  end

  defp parse_attr_quote(_, _xml, _buf_pos, abs_pos, line, ls, _name, _attrs, _seen, _elem_start, _loc, _attr_name, events, _depth, _offset) do
    events = [{:error, :expected_quote, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  defp parse_attr_value(<<>>, _xml, _buf_pos, abs_pos, line, ls, _name, _attrs, _seen, elem_start, _loc, _attr_name, _quote, _start, events, _depth, offset) do
    # Attribute value incomplete - back up to element start
    leftover_pos = max(0, elem_start - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_attr_value(<<q, rest::binary>>, xml, buf_pos, abs_pos, line, ls, name, attrs, seen, elem_start, loc, attr_name, q, start, events, depth, offset) do
    # End of attribute value - check for duplicate (list is faster than MapSet for small attr counts)
    value = binary_part(xml, start, buf_pos - start)
    {l, lls, lp} = loc
    {new_attrs, new_seen, events} = if attr_name in seen do
      # Duplicate attribute - emit error but still add it
      events = [{:error, :attr_unique, nil, l, lls, lp} | events]
      {[{attr_name, value} | attrs], seen, events}
    else
      {[{attr_name, value} | attrs], [attr_name | seen], events}
    end
    finish_open_tag(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, name, new_attrs, new_seen, elem_start, loc, events, depth, offset)
  end

  defp parse_attr_value(<<?\r, ?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, name, attrs, seen, elem_start, loc, attr_name, quote, start, events, depth, offset) do
    parse_attr_value(rest, xml, buf_pos + 2, abs_pos + 2, line + 1, abs_pos + 2, name, attrs, seen, elem_start, loc, attr_name, quote, start, events, depth, offset)
  end

  defp parse_attr_value(<<?\r, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, name, attrs, seen, elem_start, loc, attr_name, quote, start, events, depth, offset) do
    parse_attr_value(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, name, attrs, seen, elem_start, loc, attr_name, quote, start, events, depth, offset)
  end

  defp parse_attr_value(<<?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, name, attrs, seen, elem_start, loc, attr_name, quote, start, events, depth, offset) do
    parse_attr_value(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, name, attrs, seen, elem_start, loc, attr_name, quote, start, events, depth, offset)
  end

  defp parse_attr_value(<<_, rest::binary>>, xml, buf_pos, abs_pos, line, ls, name, attrs, seen, elem_start, loc, attr_name, quote, start, events, depth, offset) do
    parse_attr_value(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, name, attrs, seen, elem_start, loc, attr_name, quote, start, events, depth, offset)
  end

  # ============================================================================
  # Close tag
  # ============================================================================

  defp parse_close_tag_name(<<>>, _xml, buf_pos, abs_pos, line, ls, _loc, _start, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - 2 - offset)  # -2 to include "</"
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  # Fast path for ASCII name chars
  defp parse_close_tag_name(<<c, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, start, events, depth, offset)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?- or c == ?. or c == ?: do
    parse_close_tag_name(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, start, events, depth, offset)
  end

  # Slow path for non-ASCII UTF-8
  defp parse_close_tag_name(<<c::utf8, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, start, events, depth, offset)
       when is_name_char(c) do
    size = utf8_size(c)
    parse_close_tag_name(rest, xml, buf_pos + size, abs_pos + size, line, ls, loc, start, events, depth, offset)
  end

  defp parse_close_tag_name(rest, xml, buf_pos, abs_pos, line, ls, loc, start, events, depth, offset) do
    name = binary_part(xml, start, buf_pos - start)
    parse_close_tag_end(rest, xml, buf_pos, abs_pos, line, ls, name, loc, events, depth, offset)
  end

  defp parse_close_tag_end(<<>>, _xml, buf_pos, abs_pos, line, ls, _name, _loc, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_close_tag_end(<<c, rest::binary>>, xml, buf_pos, abs_pos, line, ls, name, loc, events, depth, offset)
       when c in [?\s, ?\t] do
    parse_close_tag_end(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, name, loc, events, depth, offset)
  end

  defp parse_close_tag_end(<<?\r, ?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, name, loc, events, depth, offset) do
    parse_close_tag_end(rest, xml, buf_pos + 2, abs_pos + 2, line + 1, abs_pos + 2, name, loc, events, depth, offset)
  end

  defp parse_close_tag_end(<<?\r, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, name, loc, events, depth, offset) do
    parse_close_tag_end(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, name, loc, events, depth, offset)
  end

  defp parse_close_tag_end(<<?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, name, loc, events, depth, offset) do
    parse_close_tag_end(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, name, loc, events, depth, offset)
  end

  defp parse_close_tag_end(<<">", rest::binary>>, xml, buf_pos, abs_pos, line, ls, name, loc, events, depth, offset) do
    {l, lls, lp} = loc
    events = [{:end_element, name, l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, events, depth - 1, offset)
  end

  defp parse_close_tag_end(_, _xml, _buf_pos, abs_pos, line, ls, _name, _loc, events, _depth, _offset) do
    events = [{:error, :expected_gt, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  # ============================================================================
  # Comment
  # ============================================================================

  defp parse_comment(<<>>, _xml, buf_pos, abs_pos, line, ls, _loc, _start, _has_double_dash, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - 4 - offset)  # -4 to include "<!--"
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_comment(<<"-->", rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, start, has_double_dash, events, depth, offset) do
    comment = binary_part(xml, start, buf_pos - start)
    {l, lls, lp} = loc
    events = [{:comment, comment, l, lls, lp} | events]
    # Add error if we saw -- inside the comment (not at end)
    events = if has_double_dash do
      [{:error, :comment, nil, l, lls, lp} | events]
    else
      events
    end
    parse_content(rest, xml, buf_pos + 3, abs_pos + 3, line, ls, events, depth, offset)
  end

  # -- not followed by > is invalid, set has_double_dash to true
  defp parse_comment(<<"--", rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, start, _has_double_dash, events, depth, offset) do
    parse_comment(rest, xml, buf_pos + 2, abs_pos + 2, line, ls, loc, start, true, events, depth, offset)
  end

  defp parse_comment(<<"-">>, _xml, buf_pos, abs_pos, line, ls, _loc, _start, _has_double_dash, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - 1 - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_comment(<<?\r, ?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, start, has_double_dash, events, depth, offset) do
    parse_comment(rest, xml, buf_pos + 2, abs_pos + 2, line + 1, abs_pos + 2, loc, start, has_double_dash, events, depth, offset)
  end

  defp parse_comment(<<?\r, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, start, has_double_dash, events, depth, offset) do
    parse_comment(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, start, has_double_dash, events, depth, offset)
  end

  defp parse_comment(<<?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, start, has_double_dash, events, depth, offset) do
    parse_comment(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, start, has_double_dash, events, depth, offset)
  end

  defp parse_comment(<<_, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, start, has_double_dash, events, depth, offset) do
    parse_comment(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, start, has_double_dash, events, depth, offset)
  end

  # ============================================================================
  # CDATA
  # ============================================================================

  defp parse_cdata(<<>>, _xml, buf_pos, abs_pos, line, ls, _loc, _start, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - 9 - offset)  # -9 to include "<![CDATA["
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_cdata(<<"]]>", rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, start, events, depth, offset) do
    cdata = binary_part(xml, start, buf_pos - start)
    {l, lls, lp} = loc
    events = [{:cdata, cdata, l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 3, abs_pos + 3, line, ls, events, depth, offset)
  end

  defp parse_cdata(<<"]]">>, _xml, buf_pos, abs_pos, line, ls, _loc, _start, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - 2 - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_cdata(<<"]">>, _xml, buf_pos, abs_pos, line, ls, _loc, _start, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - 1 - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_cdata(<<?\r, ?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, start, events, depth, offset) do
    parse_cdata(rest, xml, buf_pos + 2, abs_pos + 2, line + 1, abs_pos + 2, loc, start, events, depth, offset)
  end

  defp parse_cdata(<<?\r, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, start, events, depth, offset) do
    parse_cdata(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, start, events, depth, offset)
  end

  defp parse_cdata(<<?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, start, events, depth, offset) do
    parse_cdata(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, start, events, depth, offset)
  end

  defp parse_cdata(<<_, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, start, events, depth, offset) do
    parse_cdata(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, start, events, depth, offset)
  end

  # ============================================================================
  # DOCTYPE - captures full content for DTD processing
  # ============================================================================

  defp parse_doctype(<<>>, _xml, buf_pos, abs_pos, line, ls, _loc, _start, _dtd_depth, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - 9 - offset)  # -9 to include "<!DOCTYPE"
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_doctype(<<">", rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, start, 1, events, depth, offset) do
    # Extract DOCTYPE content (from "DOCTYPE" to just before ">")
    content = binary_part(xml, start, buf_pos - start)
    {l, lls, lp} = loc
    events = [{:dtd, content, l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, events, depth, offset)
  end

  defp parse_doctype(<<">", rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, start, dtd_depth, events, depth, offset) do
    parse_doctype(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, start, dtd_depth - 1, events, depth, offset)
  end

  defp parse_doctype(<<"<", rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, start, dtd_depth, events, depth, offset) do
    parse_doctype(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, start, dtd_depth + 1, events, depth, offset)
  end

  defp parse_doctype(<<?\r, ?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, start, dtd_depth, events, depth, offset) do
    parse_doctype(rest, xml, buf_pos + 2, abs_pos + 2, line + 1, abs_pos + 2, loc, start, dtd_depth, events, depth, offset)
  end

  defp parse_doctype(<<?\r, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, start, dtd_depth, events, depth, offset) do
    parse_doctype(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, start, dtd_depth, events, depth, offset)
  end

  defp parse_doctype(<<?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, start, dtd_depth, events, depth, offset) do
    parse_doctype(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, start, dtd_depth, events, depth, offset)
  end

  defp parse_doctype(<<_, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, start, dtd_depth, events, depth, offset) do
    parse_doctype(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, start, dtd_depth, events, depth, offset)
  end

  # ============================================================================
  # Processing instruction
  # ============================================================================

  defp parse_pi_name(<<>>, _xml, buf_pos, abs_pos, line, ls, _loc, _start, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - 2 - offset)  # -2 to include "<?"
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  # Fast path for ASCII name chars
  defp parse_pi_name(<<c, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, start, events, depth, offset)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?- or c == ?. or c == ?: do
    parse_pi_name(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, start, events, depth, offset)
  end

  # Slow path for non-ASCII UTF-8
  defp parse_pi_name(<<c::utf8, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, start, events, depth, offset)
       when is_name_char(c) do
    size = utf8_size(c)
    parse_pi_name(rest, xml, buf_pos + size, abs_pos + size, line, ls, loc, start, events, depth, offset)
  end

  defp parse_pi_name(rest, xml, buf_pos, abs_pos, line, ls, loc, start, events, depth, offset) do
    target = binary_part(xml, start, buf_pos - start)
    parse_pi_content(rest, xml, buf_pos, abs_pos, line, ls, loc, target, buf_pos, events, depth, offset)
  end

  defp parse_pi_content(<<>>, _xml, buf_pos, abs_pos, line, ls, _loc, _target, _start, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_pi_content(<<"?>", rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, target, start, events, depth, offset) do
    content = binary_part(xml, start, buf_pos - start)
    {l, lls, lp} = loc
    events = [{:processing_instruction, target, content, l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 2, abs_pos + 2, line, ls, events, depth, offset)
  end

  defp parse_pi_content(<<"?">>, _xml, buf_pos, abs_pos, line, ls, _loc, _target, _start, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - 1 - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_pi_content(<<?\r, ?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, target, start, events, depth, offset) do
    parse_pi_content(rest, xml, buf_pos + 2, abs_pos + 2, line + 1, abs_pos + 2, loc, target, start, events, depth, offset)
  end

  defp parse_pi_content(<<?\r, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, target, start, events, depth, offset) do
    parse_pi_content(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, target, start, events, depth, offset)
  end

  defp parse_pi_content(<<?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, target, start, events, depth, offset) do
    parse_pi_content(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, target, start, events, depth, offset)
  end

  defp parse_pi_content(<<_, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, target, start, events, depth, offset) do
    parse_pi_content(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, target, start, events, depth, offset)
  end

  # ============================================================================
  # Prolog
  # ============================================================================

  defp parse_prolog(<<>>, _xml, buf_pos, abs_pos, line, ls, _loc, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - 6 - offset)  # -6 to include "<?xml "
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_prolog(<<"?>", rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, events, depth, offset) do
    {l, lls, lp} = loc
    events = [{:prolog, "xml", [], l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 2, abs_pos + 2, line, ls, events, depth, offset)
  end

  defp parse_prolog(<<"?">>, _xml, buf_pos, abs_pos, line, ls, _loc, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - 1 - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_prolog(<<c, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, events, depth, offset)
       when c in [?\s, ?\t] do
    parse_prolog(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, events, depth, offset)
  end

  defp parse_prolog(<<?\r, ?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, events, depth, offset) do
    parse_prolog(rest, xml, buf_pos + 2, abs_pos + 2, line + 1, abs_pos + 2, loc, events, depth, offset)
  end

  defp parse_prolog(<<?\r, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, events, depth, offset) do
    parse_prolog(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, events, depth, offset)
  end

  defp parse_prolog(<<?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, events, depth, offset) do
    parse_prolog(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, events, depth, offset)
  end

  defp parse_prolog(<<c::utf8, _::binary>> = rest, xml, buf_pos, abs_pos, line, ls, loc, events, depth, offset)
       when is_name_start(c) do
    parse_prolog_attr_name(rest, xml, buf_pos, abs_pos, line, ls, loc, [], buf_pos, events, depth, offset)
  end

  defp parse_prolog(_, _xml, _buf_pos, abs_pos, line, ls, _loc, events, _depth, _offset) do
    events = [{:error, :expected_pi_end_or_attr, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  # Prolog attribute parsing (simplified - just skip to ?>)
  defp parse_prolog_attr_name(<<>>, _xml, buf_pos, abs_pos, line, ls, _loc, _prolog_attrs, _start, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_prolog_attr_name(<<"?>", rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, prolog_attrs, _start, events, depth, offset) do
    {l, lls, lp} = loc
    events = [{:prolog, "xml", Enum.reverse(prolog_attrs), l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 2, abs_pos + 2, line, ls, events, depth, offset)
  end

  # Fast path for ASCII name chars
  defp parse_prolog_attr_name(<<c, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, prolog_attrs, start, events, depth, offset)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?- or c == ?. or c == ?: do
    parse_prolog_attr_name(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, prolog_attrs, start, events, depth, offset)
  end

  # Slow path for non-ASCII UTF-8
  defp parse_prolog_attr_name(<<c::utf8, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, prolog_attrs, start, events, depth, offset)
       when is_name_char(c) do
    size = utf8_size(c)
    parse_prolog_attr_name(rest, xml, buf_pos + size, abs_pos + size, line, ls, loc, prolog_attrs, start, events, depth, offset)
  end

  defp parse_prolog_attr_name(rest, xml, buf_pos, abs_pos, line, ls, loc, prolog_attrs, start, events, depth, offset) do
    attr_name = binary_part(xml, start, buf_pos - start)
    parse_prolog_attr_eq(rest, xml, buf_pos, abs_pos, line, ls, loc, prolog_attrs, attr_name, events, depth, offset)
  end

  defp parse_prolog_attr_eq(<<>>, _xml, buf_pos, abs_pos, line, ls, _loc, _prolog_attrs, _attr_name, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_prolog_attr_eq(<<c, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, prolog_attrs, attr_name, events, depth, offset)
       when c in [?\s, ?\t] do
    parse_prolog_attr_eq(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, prolog_attrs, attr_name, events, depth, offset)
  end

  defp parse_prolog_attr_eq(<<?\r, ?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, prolog_attrs, attr_name, events, depth, offset) do
    parse_prolog_attr_eq(rest, xml, buf_pos + 2, abs_pos + 2, line + 1, abs_pos + 2, loc, prolog_attrs, attr_name, events, depth, offset)
  end

  defp parse_prolog_attr_eq(<<?\r, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, prolog_attrs, attr_name, events, depth, offset) do
    parse_prolog_attr_eq(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, prolog_attrs, attr_name, events, depth, offset)
  end

  defp parse_prolog_attr_eq(<<?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, prolog_attrs, attr_name, events, depth, offset) do
    parse_prolog_attr_eq(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, prolog_attrs, attr_name, events, depth, offset)
  end

  defp parse_prolog_attr_eq(<<"=", rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, prolog_attrs, attr_name, events, depth, offset) do
    parse_prolog_attr_quote(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, prolog_attrs, attr_name, events, depth, offset)
  end

  defp parse_prolog_attr_eq(_, _xml, _buf_pos, abs_pos, line, ls, _loc, _prolog_attrs, _attr_name, events, _depth, _offset) do
    events = [{:error, :expected_eq, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  defp parse_prolog_attr_quote(<<>>, _xml, buf_pos, abs_pos, line, ls, _loc, _prolog_attrs, _attr_name, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_prolog_attr_quote(<<c, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, prolog_attrs, attr_name, events, depth, offset)
       when c in [?\s, ?\t] do
    parse_prolog_attr_quote(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, prolog_attrs, attr_name, events, depth, offset)
  end

  defp parse_prolog_attr_quote(<<?\r, ?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, prolog_attrs, attr_name, events, depth, offset) do
    parse_prolog_attr_quote(rest, xml, buf_pos + 2, abs_pos + 2, line + 1, abs_pos + 2, loc, prolog_attrs, attr_name, events, depth, offset)
  end

  defp parse_prolog_attr_quote(<<?\r, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, prolog_attrs, attr_name, events, depth, offset) do
    parse_prolog_attr_quote(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, prolog_attrs, attr_name, events, depth, offset)
  end

  defp parse_prolog_attr_quote(<<?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, prolog_attrs, attr_name, events, depth, offset) do
    parse_prolog_attr_quote(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, prolog_attrs, attr_name, events, depth, offset)
  end

  defp parse_prolog_attr_quote(<<q, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, prolog_attrs, attr_name, events, depth, offset)
       when q in [?", ?'] do
    parse_prolog_attr_value(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, prolog_attrs, attr_name, q, buf_pos + 1, events, depth, offset)
  end

  defp parse_prolog_attr_quote(_, _xml, _buf_pos, abs_pos, line, ls, _loc, _prolog_attrs, _attr_name, events, _depth, _offset) do
    events = [{:error, :expected_quote, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end

  defp parse_prolog_attr_value(<<>>, _xml, buf_pos, abs_pos, line, ls, _loc, _prolog_attrs, _attr_name, _quote, _start, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_prolog_attr_value(<<q, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, prolog_attrs, attr_name, q, start, events, depth, offset) do
    value = binary_part(xml, start, buf_pos - start)
    new_prolog_attrs = [{attr_name, value} | prolog_attrs]
    parse_prolog_after_attr(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, new_prolog_attrs, events, depth, offset)
  end

  defp parse_prolog_attr_value(<<?\r, ?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, prolog_attrs, attr_name, quote, start, events, depth, offset) do
    parse_prolog_attr_value(rest, xml, buf_pos + 2, abs_pos + 2, line + 1, abs_pos + 2, loc, prolog_attrs, attr_name, quote, start, events, depth, offset)
  end

  defp parse_prolog_attr_value(<<?\r, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, prolog_attrs, attr_name, quote, start, events, depth, offset) do
    parse_prolog_attr_value(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, prolog_attrs, attr_name, quote, start, events, depth, offset)
  end

  defp parse_prolog_attr_value(<<?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, prolog_attrs, attr_name, quote, start, events, depth, offset) do
    parse_prolog_attr_value(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, prolog_attrs, attr_name, quote, start, events, depth, offset)
  end

  defp parse_prolog_attr_value(<<_, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, prolog_attrs, attr_name, quote, start, events, depth, offset) do
    parse_prolog_attr_value(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, prolog_attrs, attr_name, quote, start, events, depth, offset)
  end

  defp parse_prolog_after_attr(<<>>, _xml, buf_pos, abs_pos, line, ls, _loc, _prolog_attrs, events, _depth, offset) do
    leftover_pos = max(0, buf_pos - offset)
    incomplete(events, leftover_pos, line, ls, abs_pos)
  end

  defp parse_prolog_after_attr(<<"?>", rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, prolog_attrs, events, depth, offset) do
    {l, lls, lp} = loc
    events = [{:prolog, "xml", Enum.reverse(prolog_attrs), l, lls, lp} | events]
    parse_content(rest, xml, buf_pos + 2, abs_pos + 2, line, ls, events, depth, offset)
  end

  defp parse_prolog_after_attr(<<c, rest::binary>>, xml, buf_pos, abs_pos, line, ls, loc, prolog_attrs, events, depth, offset)
       when c in [?\s, ?\t] do
    parse_prolog_after_attr(rest, xml, buf_pos + 1, abs_pos + 1, line, ls, loc, prolog_attrs, events, depth, offset)
  end

  defp parse_prolog_after_attr(<<?\r, ?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, prolog_attrs, events, depth, offset) do
    parse_prolog_after_attr(rest, xml, buf_pos + 2, abs_pos + 2, line + 1, abs_pos + 2, loc, prolog_attrs, events, depth, offset)
  end

  defp parse_prolog_after_attr(<<?\r, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, prolog_attrs, events, depth, offset) do
    parse_prolog_after_attr(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, prolog_attrs, events, depth, offset)
  end

  defp parse_prolog_after_attr(<<?\n, rest::binary>>, xml, buf_pos, abs_pos, line, _ls, loc, prolog_attrs, events, depth, offset) do
    parse_prolog_after_attr(rest, xml, buf_pos + 1, abs_pos + 1, line + 1, abs_pos + 1, loc, prolog_attrs, events, depth, offset)
  end

  defp parse_prolog_after_attr(<<c::utf8, _::binary>> = rest, xml, buf_pos, abs_pos, line, ls, loc, prolog_attrs, events, depth, offset)
       when is_name_start(c) do
    parse_prolog_attr_name(rest, xml, buf_pos, abs_pos, line, ls, loc, prolog_attrs, buf_pos, events, depth, offset)
  end

  defp parse_prolog_after_attr(_, _xml, _buf_pos, abs_pos, line, ls, _loc, _prolog_attrs, events, _depth, _offset) do
    events = [{:error, :expected_pi_end_or_attr, nil, line, ls, abs_pos} | events]
    complete(events, line, ls, abs_pos)
  end
end
