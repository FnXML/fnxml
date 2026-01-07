defmodule FnXML.Parser.Recursive do
  @moduledoc """
  Recursive descent XML parser using binary pattern matching.

  Single-pass parser that tracks positions instead of copying values.
  Validates character classes for XML names.
  """

  # XML Whitespace: space, tab, CR, LF
  @ws [?\s, ?\t, ?\r, ?\n]

  # NameStartChar ranges (simplified for ASCII + common Unicode)
  defguardp is_name_start(c) when
    c in ?a..?z or c in ?A..?Z or c == ?_ or c == ?: or
    c in 0x00C0..0x00D6 or c in 0x00D8..0x00F6 or
    c in 0x00F8..0x02FF or c in 0x0370..0x037D or
    c in 0x037F..0x1FFF or c in 0x200C..0x200D

  # NameChar: NameStartChar + hyphen, period, digits, combining chars
  defguardp is_name_char(c) when
    is_name_start(c) or c == ?- or c == ?. or c in ?0..?9 or
    c == 0x00B7 or c in 0x0300..0x036F or c in 0x203F..0x2040

  @doc """
  Parse XML string into a stream of events.
  """
  def parse(xml) when is_binary(xml) do
    Stream.resource(
      fn -> {xml, 1, 0, 0} end,
      &next_token/1,
      fn _ -> :ok end
    )
  end

  # === Stream Interface ===
  # State: {xml, line, line_start, pos}

  defp next_token({"", _, _, _}), do: {:halt, nil}

  defp next_token({<<"<?xml", _::binary>> = xml, line, line_start, pos}) do
    parse_prolog(xml, line, line_start, pos)
  end

  defp next_token({<<"<", _::binary>> = xml, line, line_start, pos}) do
    parse_element(xml, line, line_start, pos)
  end

  defp next_token({xml, line, line_start, pos}) do
    parse_text(xml, line, line_start, pos)
  end

  # === Prolog: <?xml ... ?> ===

  defp parse_prolog(<<"<?xml", xml::binary>>, line, line_start, pos) do
    tag_loc = {line, line_start, pos + 1}
    {xml, line, line_start, pos} = skip_ws(xml, line, line_start, pos + 5)
    {attrs, xml, line, line_start, pos} = parse_attributes(xml, line, line_start, pos, [])
    {xml, line, line_start, pos} = skip_ws(xml, line, line_start, pos)
    finish_prolog(xml, line, line_start, pos, attrs, tag_loc)
  end

  defp finish_prolog(<<"?>", xml::binary>>, line, line_start, pos, attrs, tag_loc) do
    token = emit(:prolog, [tag: "xml", attributes: attrs], tag_loc)
    {xml, line, line_start, pos} = skip_ws(xml, line, line_start, pos + 2)
    {[token], {xml, line, line_start, pos}}
  end

  defp finish_prolog(xml, line, line_start, pos, _attrs, _tag_loc) do
    error(xml, line, line_start, pos, "Expected '?>' to close XML declaration")
  end

  # === Elements: < ... > ===

  defp parse_element(<<"<!--", xml::binary>>, line, line_start, pos) do
    parse_comment(xml, line, line_start, pos + 4, {line, line_start, pos + 1})
  end

  defp parse_element(<<"<![CDATA[", xml::binary>>, line, line_start, pos) do
    parse_cdata(xml, line, line_start, pos + 9, {line, line_start, pos + 1})
  end

  defp parse_element(<<"</", xml::binary>>, line, line_start, pos) do
    parse_close_tag(xml, line, line_start, pos + 2, {line, line_start, pos + 1})
  end

  defp parse_element(<<"<?", xml::binary>>, line, line_start, pos) do
    parse_pi(xml, line, line_start, pos + 2, {line, line_start, pos + 1})
  end

  defp parse_element(<<"<", c, _::binary>> = xml, line, line_start, pos) when is_name_start(c) do
    <<"<", rest::binary>> = xml
    parse_open_tag(rest, line, line_start, pos + 1, {line, line_start, pos + 1})
  end

  defp parse_element(<<"<", c, _::binary>> = xml, line, line_start, pos) do
    error(xml, line, line_start, pos, "Invalid name start character '#{<<c::utf8>>}'")
  end

  defp parse_element(<<"<">> = xml, line, line_start, pos) do
    error(xml, line, line_start, pos, "Unexpected end of input after '<'")
  end

  # === Open Tag: <name attrs...> or <name attrs.../> ===

  defp parse_open_tag(xml, line, line_start, pos, tag_loc) do
    {name, xml, line, line_start, pos} = parse_name(xml, line, line_start, pos)
    {xml, line, line_start, pos} = skip_ws(xml, line, line_start, pos)
    finish_open_tag(xml, line, line_start, pos, name, tag_loc)
  end

  defp finish_open_tag(<<"/>", xml::binary>>, line, line_start, pos, name, tag_loc) do
    open = emit(:open, [tag: name], tag_loc)
    close = {:close, [tag: name]}
    {[open, close], {xml, line, line_start, pos + 2}}
  end

  defp finish_open_tag(<<">", xml::binary>>, line, line_start, pos, name, tag_loc) do
    token = emit(:open, [tag: name], tag_loc)
    {[token], {xml, line, line_start, pos + 1}}
  end

  defp finish_open_tag(<<c, _::binary>> = xml, line, line_start, pos, name, tag_loc) when is_name_start(c) do
    {attrs, xml, line, line_start, pos} = parse_attributes(xml, line, line_start, pos, [])
    {xml, line, line_start, pos} = skip_ws(xml, line, line_start, pos)
    finish_open_tag_with_attrs(xml, line, line_start, pos, name, attrs, tag_loc)
  end

  defp finish_open_tag(xml, line, line_start, pos, _name, _tag_loc) do
    error(xml, line, line_start, pos, "Expected '>', '/>', or attribute name")
  end

  defp finish_open_tag_with_attrs(<<"/>", xml::binary>>, line, line_start, pos, name, attrs, tag_loc) do
    open = emit(:open, [tag: name, attributes: attrs], tag_loc)
    close = {:close, [tag: name]}
    {[open, close], {xml, line, line_start, pos + 2}}
  end

  defp finish_open_tag_with_attrs(<<">", xml::binary>>, line, line_start, pos, name, attrs, tag_loc) do
    token = emit(:open, [tag: name, attributes: attrs], tag_loc)
    {[token], {xml, line, line_start, pos + 1}}
  end

  defp finish_open_tag_with_attrs(xml, line, line_start, pos, _name, _attrs, _tag_loc) do
    error(xml, line, line_start, pos, "Expected '>' or '/>' to close tag")
  end

  # === Close Tag: </name> ===

  defp parse_close_tag(xml, line, line_start, pos, tag_loc) do
    {name, xml, line, line_start, pos} = parse_name(xml, line, line_start, pos)
    {xml, line, line_start, pos} = skip_ws(xml, line, line_start, pos)
    finish_close_tag(xml, line, line_start, pos, name, tag_loc)
  end

  defp finish_close_tag(<<">", xml::binary>>, line, line_start, pos, name, tag_loc) do
    token = emit(:close, [tag: name], tag_loc)
    {[token], {xml, line, line_start, pos + 1}}
  end

  defp finish_close_tag(xml, line, line_start, pos, _name, _tag_loc) do
    error(xml, line, line_start, pos, "Expected '>' to close tag")
  end

  # === Comment: <!-- ... --> ===

  defp parse_comment(xml, line, line_start, pos, tag_loc) do
    {content, xml, line, line_start, pos} = scan_until(xml, line, line_start, pos, "--")
    finish_comment(xml, line, line_start, pos, content, tag_loc)
  end

  defp finish_comment(<<">", xml::binary>>, line, line_start, pos, content, tag_loc) do
    token = emit(:comment, [content: content], tag_loc)
    {[token], {xml, line, line_start, pos + 1}}
  end

  defp finish_comment(xml, line, line_start, pos, _content, _tag_loc) do
    error(xml, line, line_start, pos, "Expected '>' after '--' to close comment")
  end

  # === CDATA: <![CDATA[ ... ]]> ===

  defp parse_cdata(xml, line, line_start, pos, tag_loc) do
    {content, xml, line, line_start, pos} = scan_until(xml, line, line_start, pos, "]]")
    finish_cdata(xml, line, line_start, pos, content, tag_loc)
  end

  defp finish_cdata(<<">", xml::binary>>, line, line_start, pos, content, tag_loc) do
    token = emit(:text, [content: content], tag_loc)
    {[token], {xml, line, line_start, pos + 1}}
  end

  defp finish_cdata(xml, line, line_start, pos, _content, _tag_loc) do
    error(xml, line, line_start, pos, "Expected '>' after ']]' to close CDATA section")
  end

  # === Processing Instruction: <? name ... ?> ===

  defp parse_pi(xml, line, line_start, pos, tag_loc) do
    {name, xml, line, line_start, pos} = parse_name(xml, line, line_start, pos)
    {xml, line, line_start, pos} = skip_ws(xml, line, line_start, pos)
    {content, xml, line, line_start, pos} = scan_until(xml, line, line_start, pos, "?")
    finish_pi(xml, line, line_start, pos, name, content, tag_loc)
  end

  defp finish_pi(<<">", xml::binary>>, line, line_start, pos, name, content, tag_loc) do
    token = emit(:proc_inst, [tag: name, content: String.trim(content)], tag_loc)
    {[token], {xml, line, line_start, pos + 1}}
  end

  defp finish_pi(xml, line, line_start, pos, _name, _content, _tag_loc) do
    error(xml, line, line_start, pos, "Expected '>' after '?' to close processing instruction")
  end

  # === Text Content ===

  defp parse_text(xml, line, line_start, pos) do
    tag_loc = {line, line_start, pos}
    {content, xml, line, line_start, pos} = scan_text(xml, line, line_start, pos, 0)
    token = emit(:text, [content: content], tag_loc)
    {[token], {xml, line, line_start, pos}}
  end

  # === Helper: Parse Name ===

  defp parse_name(<<c, _::binary>> = xml, line, line_start, pos) when is_name_start(c) do
    scan_name(xml, line, line_start, pos, 0)
  end

  defp parse_name(<<c, _::binary>> = xml, line, line_start, pos) do
    error(xml, line, line_start, pos, "Invalid name start character '#{<<c::utf8>>}'")
  end

  defp parse_name(<<>> = xml, line, line_start, pos) do
    error(xml, line, line_start, pos, "Unexpected end of input, expected element name")
  end

  defp scan_name(xml, line, line_start, pos, len) do
    case xml do
      <<_::binary-size(len), c, _::binary>> when is_name_char(c) ->
        scan_name(xml, line, line_start, pos, len + 1)

      _ ->
        name = binary_part(xml, 0, len)
        rest = binary_part(xml, len, byte_size(xml) - len)
        {name, rest, line, line_start, pos + len}
    end
  end

  # === Helper: Parse Attributes ===

  defp parse_attributes(<<c, _::binary>> = xml, line, line_start, pos, acc) when is_name_start(c) do
    {attr, xml, line, line_start, pos} = parse_one_attr(xml, line, line_start, pos)
    {xml, line, line_start, pos} = skip_ws(xml, line, line_start, pos)
    parse_attributes(xml, line, line_start, pos, [attr | acc])
  end

  defp parse_attributes(xml, line, line_start, pos, acc) do
    {Enum.reverse(acc), xml, line, line_start, pos}
  end

  defp parse_one_attr(xml, line, line_start, pos) do
    {name, xml, line, line_start, pos} = parse_name(xml, line, line_start, pos)
    {xml, line, line_start, pos} = skip_ws(xml, line, line_start, pos)
    parse_attr_eq(xml, line, line_start, pos, name)
  end

  defp parse_attr_eq(<<"=", xml::binary>>, line, line_start, pos, name) do
    {xml, line, line_start, pos} = skip_ws(xml, line, line_start, pos + 1)
    {value, xml, line, line_start, pos} = parse_quoted(xml, line, line_start, pos)
    {{name, value}, xml, line, line_start, pos}
  end

  defp parse_attr_eq(xml, line, line_start, pos, _name) do
    error(xml, line, line_start, pos, "Expected '=' after attribute name")
  end

  defp parse_quoted(<<"\"", xml::binary>>, line, line_start, pos) do
    scan_quoted(xml, line, line_start, pos + 1, ?\", 0)
  end

  defp parse_quoted(<<"'", xml::binary>>, line, line_start, pos) do
    scan_quoted(xml, line, line_start, pos + 1, ?', 0)
  end

  defp parse_quoted(xml, line, line_start, pos) do
    error(xml, line, line_start, pos, "Expected quoted attribute value (single or double quotes)")
  end

  defp scan_quoted(xml, line, line_start, pos, quote_char, len) do
    case xml do
      <<_::binary-size(len), ^quote_char, rest::binary>> ->
        value = binary_part(xml, 0, len)
        {value, rest, line, line_start, pos + len + 1}

      <<_::binary-size(len), ?\n, _::binary>> ->
        scan_quoted(xml, line + 1, pos + len + 1, pos + len + 1, quote_char, len + 1)

      <<_::binary-size(len), _, _::binary>> ->
        scan_quoted(xml, line, line_start, pos, quote_char, len + 1)

      _ ->
        quote = if quote_char == ?", do: "double", else: "single"
        error(xml, line, line_start, pos, "Unterminated attribute value, expected closing #{quote} quote")
    end
  end

  # === Helper: Skip Whitespace ===

  defp skip_ws(<<?\n, xml::binary>>, line, _line_start, pos) do
    skip_ws(xml, line + 1, pos + 1, pos + 1)
  end

  defp skip_ws(<<c, xml::binary>>, line, line_start, pos) when c in @ws do
    skip_ws(xml, line, line_start, pos + 1)
  end

  defp skip_ws(xml, line, line_start, pos) do
    {xml, line, line_start, pos}
  end

  # === Helper: Scan Until Delimiter ===

  defp scan_until(xml, line, line_start, pos, delim) do
    delim_len = byte_size(delim)
    do_scan_until(xml, line, line_start, pos, delim, delim_len, 0)
  end

  defp do_scan_until(xml, line, line_start, pos, delim, delim_len, len) do
    case xml do
      <<_::binary-size(len), ^delim::binary-size(delim_len), rest::binary>> ->
        content = binary_part(xml, 0, len)
        {content, rest, line, line_start, pos + len + delim_len}

      <<_::binary-size(len), ?\n, _::binary>> ->
        do_scan_until(xml, line + 1, pos + len + 1, pos + len + 1, delim, delim_len, len + 1)

      <<_::binary-size(len), _, _::binary>> ->
        do_scan_until(xml, line, line_start, pos, delim, delim_len, len + 1)

      _ ->
        error(xml, line, line_start, pos, "Expected '#{delim}' not found before end of input")
    end
  end

  # === Helper: Scan Text Until '<' ===

  defp scan_text(xml, line, line_start, pos, len) do
    case xml do
      <<_::binary-size(len), ?<, _::binary>> ->
        content = binary_part(xml, 0, len)
        rest = binary_part(xml, len, byte_size(xml) - len)
        {content, rest, line, line_start, pos + len}

      <<_::binary-size(len), ?\n, _::binary>> ->
        scan_text(xml, line + 1, pos + len + 1, pos + len + 1, len + 1)

      <<_::binary-size(len), _, _::binary>> ->
        scan_text(xml, line, line_start, pos, len + 1)

      _ ->
        {xml, "", line, line_start, pos + byte_size(xml)}
    end
  end

  # === Helper: Emit Event ===

  defp emit(type, meta, loc) do
    {type, [{:loc, loc} | meta]}
  end

  # === Helper: Error Handling ===

  defp error(xml, line, line_start, pos, message) do
    context = extract_context(xml)
    token = {:error, [message: message, context: context, loc: {line, line_start, pos}]}
    {[token], {"", line, line_start, pos}}
  end

  defp extract_context(<<>>), do: "<end of input>"
  defp extract_context(xml) do
    len = min(byte_size(xml), 20)
    snippet = binary_part(xml, 0, len)
    if len < byte_size(xml), do: snippet <> "...", else: snippet
  end
end
