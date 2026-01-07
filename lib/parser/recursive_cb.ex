defmodule FnXML.Parser.RecursiveCB do
  @moduledoc """
  Recursive descent XML parser with callback-based event emission.

  Same as Recursive but uses internal callbacks to reduce tuple creation.
  Events are accumulated via emit/4 and only wrapped for Stream at the boundary.
  """

  @ws [?\s, ?\t, ?\r, ?\n]

  defguardp is_name_start(c) when
    c in ?a..?z or c in ?A..?Z or c == ?_ or c == ?: or
    c in 0x00C0..0x00D6 or c in 0x00D8..0x00F6 or
    c in 0x00F8..0x02FF or c in 0x0370..0x037D or
    c in 0x037F..0x1FFF or c in 0x200C..0x200D

  defguardp is_name_char(c) when
    is_name_start(c) or c == ?- or c == ?. or c in ?0..?9 or
    c == 0x00B7 or c in 0x0300..0x036F or c in 0x203F..0x2040

  def parse(xml) when is_binary(xml) do
    Stream.resource(
      fn -> {xml, 1, 0, 0} end,
      &next_token/1,
      fn _ -> :ok end
    )
  end

  # Stream interface - only place we create the return tuple
  defp next_token({"", _, _, _}), do: {:halt, nil}

  defp next_token({xml, line, line_start, pos}) do
    # Accumulator for tokens, will be reversed at end
    case do_next(xml, line, line_start, pos, []) do
      {:ok, tokens, xml, line, line_start, pos} ->
        {tokens, {xml, line, line_start, pos}}
      {:halt, tokens} ->
        {tokens, {"", 0, 0, 0}}
    end
  end

  # Internal dispatch - no tuple returns, just flat args + accumulator
  defp do_next("", _line, _ls, _pos, acc), do: {:halt, Enum.reverse(acc)}

  defp do_next(<<"<?xml", _::binary>> = xml, line, ls, pos, acc) do
    parse_prolog(xml, line, ls, pos, acc)
  end

  defp do_next(<<"<", _::binary>> = xml, line, ls, pos, acc) do
    parse_element(xml, line, ls, pos, acc)
  end

  defp do_next(xml, line, ls, pos, acc) do
    parse_text(xml, line, ls, pos, acc)
  end

  # === Emit callback - builds event and adds to accumulator ===
  defp emit(type, meta, loc, acc) do
    [{type, [{:loc, loc} | meta]} | acc]
  end

  defp emit_error(message, context, loc, acc) do
    [{:error, [message: message, context: context, loc: loc]} | acc]
  end

  # === Prolog ===

  defp parse_prolog(<<"<?xml", xml::binary>>, line, ls, pos, acc) do
    tag_loc = {line, ls, pos + 1}
    {xml, line, ls, pos} = skip_ws(xml, line, ls, pos + 5)
    {attrs, xml, line, ls, pos} = parse_attributes(xml, line, ls, pos, [])
    {xml, line, ls, pos} = skip_ws(xml, line, ls, pos)
    finish_prolog(xml, line, ls, pos, attrs, tag_loc, acc)
  end

  defp finish_prolog(<<"?>", xml::binary>>, line, ls, pos, attrs, tag_loc, acc) do
    acc = emit(:prolog, [tag: "xml", attributes: attrs], tag_loc, acc)
    {xml, line, ls, pos} = skip_ws(xml, line, ls, pos + 2)
    {:ok, Enum.reverse(acc), xml, line, ls, pos}
  end

  defp finish_prolog(xml, line, ls, pos, _attrs, _tag_loc, acc) do
    acc = emit_error("Expected '?>' to close XML declaration", extract_context(xml), {line, ls, pos}, acc)
    {:ok, Enum.reverse(acc), "", line, ls, pos}
  end

  # === Elements ===

  defp parse_element(<<"<!--", xml::binary>>, line, ls, pos, acc) do
    parse_comment(xml, line, ls, pos + 4, {line, ls, pos + 1}, acc)
  end

  defp parse_element(<<"<![CDATA[", xml::binary>>, line, ls, pos, acc) do
    parse_cdata(xml, line, ls, pos + 9, {line, ls, pos + 1}, acc)
  end

  defp parse_element(<<"</", xml::binary>>, line, ls, pos, acc) do
    parse_close_tag(xml, line, ls, pos + 2, {line, ls, pos + 1}, acc)
  end

  defp parse_element(<<"<?", xml::binary>>, line, ls, pos, acc) do
    parse_pi(xml, line, ls, pos + 2, {line, ls, pos + 1}, acc)
  end

  defp parse_element(<<"<", c, _::binary>> = xml, line, ls, pos, acc) when is_name_start(c) do
    <<"<", rest::binary>> = xml
    parse_open_tag(rest, line, ls, pos + 1, {line, ls, pos + 1}, acc)
  end

  defp parse_element(<<"<", c, _::binary>> = xml, line, ls, pos, acc) do
    acc = emit_error("Invalid name start character '#{<<c::utf8>>}'", extract_context(xml), {line, ls, pos}, acc)
    {:ok, Enum.reverse(acc), "", line, ls, pos}
  end

  defp parse_element(<<"<">> = xml, line, ls, pos, acc) do
    acc = emit_error("Unexpected end of input after '<'", extract_context(xml), {line, ls, pos}, acc)
    {:ok, Enum.reverse(acc), "", line, ls, pos}
  end

  # === Open Tag ===

  defp parse_open_tag(xml, line, ls, pos, tag_loc, acc) do
    {name, xml, line, ls, pos} = parse_name(xml, line, ls, pos)
    {xml, line, ls, pos} = skip_ws(xml, line, ls, pos)
    finish_open_tag(xml, line, ls, pos, name, tag_loc, acc)
  end

  defp finish_open_tag(<<"/>", xml::binary>>, line, ls, pos, name, tag_loc, acc) do
    acc = emit(:open, [tag: name], tag_loc, acc)
    acc = [{:close, [tag: name]} | acc]
    {:ok, Enum.reverse(acc), xml, line, ls, pos + 2}
  end

  defp finish_open_tag(<<">", xml::binary>>, line, ls, pos, name, tag_loc, acc) do
    acc = emit(:open, [tag: name], tag_loc, acc)
    {:ok, Enum.reverse(acc), xml, line, ls, pos + 1}
  end

  defp finish_open_tag(<<c, _::binary>> = xml, line, ls, pos, name, tag_loc, acc) when is_name_start(c) do
    {attrs, xml, line, ls, pos} = parse_attributes(xml, line, ls, pos, [])
    {xml, line, ls, pos} = skip_ws(xml, line, ls, pos)
    finish_open_tag_attrs(xml, line, ls, pos, name, attrs, tag_loc, acc)
  end

  defp finish_open_tag(xml, line, ls, pos, _name, _tag_loc, acc) do
    acc = emit_error("Expected '>', '/>', or attribute name", extract_context(xml), {line, ls, pos}, acc)
    {:ok, Enum.reverse(acc), "", line, ls, pos}
  end

  defp finish_open_tag_attrs(<<"/>", xml::binary>>, line, ls, pos, name, attrs, tag_loc, acc) do
    acc = emit(:open, [tag: name, attributes: attrs], tag_loc, acc)
    acc = [{:close, [tag: name]} | acc]
    {:ok, Enum.reverse(acc), xml, line, ls, pos + 2}
  end

  defp finish_open_tag_attrs(<<">", xml::binary>>, line, ls, pos, name, attrs, tag_loc, acc) do
    acc = emit(:open, [tag: name, attributes: attrs], tag_loc, acc)
    {:ok, Enum.reverse(acc), xml, line, ls, pos + 1}
  end

  defp finish_open_tag_attrs(xml, line, ls, pos, _name, _attrs, _tag_loc, acc) do
    acc = emit_error("Expected '>' or '/>' to close tag", extract_context(xml), {line, ls, pos}, acc)
    {:ok, Enum.reverse(acc), "", line, ls, pos}
  end

  # === Close Tag ===

  defp parse_close_tag(xml, line, ls, pos, tag_loc, acc) do
    {name, xml, line, ls, pos} = parse_name(xml, line, ls, pos)
    {xml, line, ls, pos} = skip_ws(xml, line, ls, pos)
    finish_close_tag(xml, line, ls, pos, name, tag_loc, acc)
  end

  defp finish_close_tag(<<">", xml::binary>>, line, ls, pos, name, tag_loc, acc) do
    acc = emit(:close, [tag: name], tag_loc, acc)
    {:ok, Enum.reverse(acc), xml, line, ls, pos + 1}
  end

  defp finish_close_tag(xml, line, ls, pos, _name, _tag_loc, acc) do
    acc = emit_error("Expected '>' to close tag", extract_context(xml), {line, ls, pos}, acc)
    {:ok, Enum.reverse(acc), "", line, ls, pos}
  end

  # === Comment ===

  defp parse_comment(xml, line, ls, pos, tag_loc, acc) do
    {content, xml, line, ls, pos} = scan_until(xml, line, ls, pos, "--")
    finish_comment(xml, line, ls, pos, content, tag_loc, acc)
  end

  defp finish_comment(<<">", xml::binary>>, line, ls, pos, content, tag_loc, acc) do
    acc = emit(:comment, [content: content], tag_loc, acc)
    {:ok, Enum.reverse(acc), xml, line, ls, pos + 1}
  end

  defp finish_comment(xml, line, ls, pos, _content, _tag_loc, acc) do
    acc = emit_error("Expected '>' after '--'", extract_context(xml), {line, ls, pos}, acc)
    {:ok, Enum.reverse(acc), "", line, ls, pos}
  end

  # === CDATA ===

  defp parse_cdata(xml, line, ls, pos, tag_loc, acc) do
    {content, xml, line, ls, pos} = scan_until(xml, line, ls, pos, "]]")
    finish_cdata(xml, line, ls, pos, content, tag_loc, acc)
  end

  defp finish_cdata(<<">", xml::binary>>, line, ls, pos, content, tag_loc, acc) do
    acc = emit(:text, [content: content], tag_loc, acc)
    {:ok, Enum.reverse(acc), xml, line, ls, pos + 1}
  end

  defp finish_cdata(xml, line, ls, pos, _content, _tag_loc, acc) do
    acc = emit_error("Expected '>' after ']]'", extract_context(xml), {line, ls, pos}, acc)
    {:ok, Enum.reverse(acc), "", line, ls, pos}
  end

  # === Processing Instruction ===

  defp parse_pi(xml, line, ls, pos, tag_loc, acc) do
    {name, xml, line, ls, pos} = parse_name(xml, line, ls, pos)
    {xml, line, ls, pos} = skip_ws(xml, line, ls, pos)
    {content, xml, line, ls, pos} = scan_until(xml, line, ls, pos, "?")
    finish_pi(xml, line, ls, pos, name, content, tag_loc, acc)
  end

  defp finish_pi(<<">", xml::binary>>, line, ls, pos, name, content, tag_loc, acc) do
    acc = emit(:proc_inst, [tag: name, content: String.trim(content)], tag_loc, acc)
    {:ok, Enum.reverse(acc), xml, line, ls, pos + 1}
  end

  defp finish_pi(xml, line, ls, pos, _name, _content, _tag_loc, acc) do
    acc = emit_error("Expected '>' after '?'", extract_context(xml), {line, ls, pos}, acc)
    {:ok, Enum.reverse(acc), "", line, ls, pos}
  end

  # === Text ===

  defp parse_text(xml, line, ls, pos, acc) do
    tag_loc = {line, ls, pos}
    {content, xml, line, ls, pos} = scan_text(xml, line, ls, pos, 0)
    acc = emit(:text, [content: content], tag_loc, acc)
    {:ok, Enum.reverse(acc), xml, line, ls, pos}
  end

  # === Helpers (same as Recursive) ===

  defp parse_name(<<c, _::binary>> = xml, line, ls, pos) when is_name_start(c) do
    scan_name(xml, line, ls, pos, 0)
  end

  defp parse_name(<<>>, line, ls, pos) do
    {"", "", line, ls, pos}
  end

  defp parse_name(<<c, _::binary>>, line, ls, pos) do
    # Return empty name, let caller handle error
    {"", <<c>>, line, ls, pos}
  end

  defp scan_name(xml, line, ls, pos, len) do
    case xml do
      <<_::binary-size(len), c, _::binary>> when is_name_char(c) ->
        scan_name(xml, line, ls, pos, len + 1)
      _ ->
        name = binary_part(xml, 0, len)
        rest = binary_part(xml, len, byte_size(xml) - len)
        {name, rest, line, ls, pos + len}
    end
  end

  defp parse_attributes(<<c, _::binary>> = xml, line, ls, pos, attrs) when is_name_start(c) do
    {attr, xml, line, ls, pos} = parse_one_attr(xml, line, ls, pos)
    {xml, line, ls, pos} = skip_ws(xml, line, ls, pos)
    parse_attributes(xml, line, ls, pos, [attr | attrs])
  end

  defp parse_attributes(xml, line, ls, pos, attrs) do
    {Enum.reverse(attrs), xml, line, ls, pos}
  end

  defp parse_one_attr(xml, line, ls, pos) do
    {name, xml, line, ls, pos} = parse_name(xml, line, ls, pos)
    {xml, line, ls, pos} = skip_ws(xml, line, ls, pos)
    case xml do
      <<"=", rest::binary>> ->
        {rest, line, ls, pos} = skip_ws(rest, line, ls, pos + 1)
        {value, xml, line, ls, pos} = parse_quoted(rest, line, ls, pos)
        {{name, value}, xml, line, ls, pos}
      _ ->
        {{name, ""}, xml, line, ls, pos}
    end
  end

  defp parse_quoted(<<"\"", xml::binary>>, line, ls, pos) do
    scan_quoted(xml, line, ls, pos + 1, ?\", 0)
  end

  defp parse_quoted(<<"'", xml::binary>>, line, ls, pos) do
    scan_quoted(xml, line, ls, pos + 1, ?', 0)
  end

  defp parse_quoted(xml, line, ls, pos) do
    {"", xml, line, ls, pos}
  end

  defp scan_quoted(xml, line, ls, pos, quote, len) do
    case xml do
      <<_::binary-size(len), ^quote, rest::binary>> ->
        value = binary_part(xml, 0, len)
        {value, rest, line, ls, pos + len + 1}
      <<_::binary-size(len), ?\n, _::binary>> ->
        scan_quoted(xml, line + 1, pos + len + 1, pos + len + 1, quote, len + 1)
      <<_::binary-size(len), _, _::binary>> ->
        scan_quoted(xml, line, ls, pos, quote, len + 1)
      _ ->
        {binary_part(xml, 0, len), "", line, ls, pos + len}
    end
  end

  defp skip_ws(<<?\n, xml::binary>>, line, _ls, pos) do
    skip_ws(xml, line + 1, pos + 1, pos + 1)
  end

  defp skip_ws(<<c, xml::binary>>, line, ls, pos) when c in @ws do
    skip_ws(xml, line, ls, pos + 1)
  end

  defp skip_ws(xml, line, ls, pos), do: {xml, line, ls, pos}

  defp scan_until(xml, line, ls, pos, delim) do
    dlen = byte_size(delim)
    do_scan_until(xml, line, ls, pos, delim, dlen, 0)
  end

  defp do_scan_until(xml, line, ls, pos, delim, dlen, len) do
    case xml do
      <<_::binary-size(len), ^delim::binary-size(dlen), rest::binary>> ->
        content = binary_part(xml, 0, len)
        {content, rest, line, ls, pos + len + dlen}
      <<_::binary-size(len), ?\n, _::binary>> ->
        do_scan_until(xml, line + 1, pos + len + 1, pos + len + 1, delim, dlen, len + 1)
      <<_::binary-size(len), _, _::binary>> ->
        do_scan_until(xml, line, ls, pos, delim, dlen, len + 1)
      _ ->
        {xml, "", line, ls, pos + byte_size(xml)}
    end
  end

  defp scan_text(xml, line, ls, pos, len) do
    case xml do
      <<_::binary-size(len), ?<, _::binary>> ->
        content = binary_part(xml, 0, len)
        rest = binary_part(xml, len, byte_size(xml) - len)
        {content, rest, line, ls, pos + len}
      <<_::binary-size(len), ?\n, _::binary>> ->
        scan_text(xml, line + 1, pos + len + 1, pos + len + 1, len + 1)
      <<_::binary-size(len), _, _::binary>> ->
        scan_text(xml, line, ls, pos, len + 1)
      _ ->
        {xml, "", line, ls, pos + byte_size(xml)}
    end
  end

  defp extract_context(<<>>), do: "<end of input>"
  defp extract_context(xml) do
    len = min(byte_size(xml), 20)
    snippet = binary_part(xml, 0, len)
    if len < byte_size(xml), do: snippet <> "...", else: snippet
  end
end
