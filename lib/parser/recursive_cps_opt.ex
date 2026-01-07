defmodule FnXML.Parser.RecursiveCPSOpt do
  @moduledoc """
  Optimized variants of RecursiveCPS for benchmarking.
  Each parse_* function tests a specific optimization.
  """

  defguardp is_name_start(c) when
    c in ?a..?z or c in ?A..?Z or c == ?_ or c == ?: or
    c in 0x00C0..0x00D6 or c in 0x00D8..0x00F6 or
    c in 0x00F8..0x02FF or c in 0x0370..0x037D or
    c in 0x037F..0x1FFF or c in 0x200C..0x200D

  defguardp is_name_char(c) when
    is_name_start(c) or c == ?- or c == ?. or c in ?0..?9 or
    c == 0x00B7 or c in 0x0300..0x036F or c in 0x203F..0x2040

  # ============================================================
  # OPTIMIZATION #3: No String.trim on PI content
  # ============================================================

  def parse_no_trim(xml, emit) when is_binary(xml) and is_function(emit, 1) do
    do_parse_all_no_trim(xml, xml, 0, 1, 0, emit)
  end

  defp do_parse_all_no_trim(<<>>, _xml, pos, line, ls, _emit), do: {:ok, pos, line, ls}
  defp do_parse_all_no_trim(rest, xml, pos, line, ls, emit) do
    {pos, line, ls} = do_parse_one_no_trim(rest, xml, pos, line, ls, emit)
    new_rest = binary_part(xml, pos, byte_size(xml) - pos)
    do_parse_all_no_trim(new_rest, xml, pos, line, ls, emit)
  end

  defp do_parse_one_no_trim(<<>>, _xml, pos, line, ls, _emit), do: {pos, line, ls}
  defp do_parse_one_no_trim(<<"<?xml", rest::binary>>, xml, pos, line, ls, emit) do
    parse_prolog_nt(rest, xml, pos + 5, line, ls, {line, ls, pos + 1}, emit)
  end
  defp do_parse_one_no_trim(<<"<", _::binary>> = rest, xml, pos, line, ls, emit) do
    parse_element_nt(rest, xml, pos, line, ls, emit)
  end
  defp do_parse_one_no_trim(<<c, rest::binary>>, xml, pos, line, ls, emit) when c in [?\s, ?\t, ?\r] do
    do_parse_one_no_trim(rest, xml, pos + 1, line, ls, emit)
  end
  defp do_parse_one_no_trim(<<?\n, rest::binary>>, xml, pos, line, _ls, emit) do
    do_parse_one_no_trim(rest, xml, pos + 1, line + 1, pos + 1, emit)
  end
  defp do_parse_one_no_trim(rest, xml, pos, line, ls, emit) do
    parse_text_nt(rest, xml, pos, line, ls, {line, ls, pos}, pos, emit)
  end

  # Simplified element dispatch - just PI handling differs
  defp parse_element_nt(<<"<?", rest::binary>>, xml, pos, line, ls, emit) do
    parse_pi_start_nt(rest, xml, pos + 2, line, ls, {line, ls, pos + 1}, emit)
  end
  defp parse_element_nt(<<"<!--", rest::binary>>, xml, pos, line, ls, emit) do
    parse_comment_nt(rest, xml, pos + 4, line, ls, {line, ls, pos + 1}, pos + 4, emit)
  end
  defp parse_element_nt(<<"<![CDATA[", rest::binary>>, xml, pos, line, ls, emit) do
    parse_cdata_nt(rest, xml, pos + 9, line, ls, {line, ls, pos + 1}, pos + 9, emit)
  end
  defp parse_element_nt(<<"</", rest::binary>>, xml, pos, line, ls, emit) do
    parse_close_tag_nt(rest, xml, pos + 2, line, ls, {line, ls, pos + 1}, emit)
  end
  defp parse_element_nt(<<"<", c, _::binary>> = rest, xml, pos, line, ls, emit) when is_name_start(c) do
    <<"<", rest2::binary>> = rest
    parse_name_nt(rest2, xml, pos + 1, line, ls, :open_tag, {{line, ls, pos + 1}, emit})
  end
  defp parse_element_nt(_, _xml, pos, line, ls, emit) do
    emit.({:error, "Invalid element", {line, ls, pos}})
    {pos, line, ls}
  end

  # PI without trim
  defp parse_pi_start_nt(<<c, _::binary>> = rest, xml, pos, line, ls, loc, emit) when is_name_start(c) do
    parse_name_nt(rest, xml, pos, line, ls, :pi_name, {loc, emit})
  end
  defp parse_pi_start_nt(_, _xml, pos, line, ls, _loc, emit) do
    emit.({:error, "Expected PI target name", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_pi_content_nt(<<"?>", _::binary>>, xml, pos, line, ls, name, loc, start, emit) do
    content = binary_part(xml, start, pos - start)  # NO String.trim!
    emit.({:proc_inst, name, content, loc})
    {pos + 2, line, ls}
  end
  defp parse_pi_content_nt(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, start, emit) do
    parse_pi_content_nt(rest, xml, pos + 1, line + 1, pos + 1, name, loc, start, emit)
  end
  defp parse_pi_content_nt(<<_, rest::binary>>, xml, pos, line, ls, name, loc, start, emit) do
    parse_pi_content_nt(rest, xml, pos + 1, line, ls, name, loc, start, emit)
  end
  defp parse_pi_content_nt(<<>>, _xml, pos, line, ls, _name, _loc, _start, emit) do
    emit.({:error, "Unterminated PI", {line, ls, pos}})
    {pos, line, ls}
  end

  defp skip_ws_then_pi_nt(<<c, rest::binary>>, xml, pos, line, ls, name, loc, emit) when c in [?\s, ?\t, ?\r] do
    skip_ws_then_pi_nt(rest, xml, pos + 1, line, ls, name, loc, emit)
  end
  defp skip_ws_then_pi_nt(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, emit) do
    skip_ws_then_pi_nt(rest, xml, pos + 1, line + 1, pos + 1, name, loc, emit)
  end
  defp skip_ws_then_pi_nt(rest, xml, pos, line, ls, name, loc, emit) do
    parse_pi_content_nt(rest, xml, pos, line, ls, name, loc, pos, emit)
  end

  # Rest of parsing (same as original, just using _nt suffix)
  defp parse_prolog_nt(<<"?>", _::binary>>, _xml, pos, line, ls, loc, emit) do
    emit.({:prolog, "xml", [], loc})
    {pos + 2, line, ls}
  end
  defp parse_prolog_nt(<<c, rest::binary>>, xml, pos, line, ls, loc, emit) when c in [?\s, ?\t, ?\r] do
    parse_prolog_nt(rest, xml, pos + 1, line, ls, loc, emit)
  end
  defp parse_prolog_nt(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, emit) do
    parse_prolog_nt(rest, xml, pos + 1, line + 1, pos + 1, loc, emit)
  end
  defp parse_prolog_nt(<<c, _::binary>> = rest, xml, pos, line, ls, loc, emit) when is_name_start(c) do
    parse_name_nt(rest, xml, pos, line, ls, :prolog_attr, {loc, [], emit})
  end
  defp parse_prolog_nt(_, _xml, pos, line, ls, _loc, emit) do
    emit.({:error, "Expected '?>'", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_prolog_attrs_nt(<<"?>", _::binary>>, _xml, pos, line, ls, loc, attrs, emit) do
    emit.({:prolog, "xml", Enum.reverse(attrs), loc})
    {pos + 2, line, ls}
  end
  defp parse_prolog_attrs_nt(<<c, rest::binary>>, xml, pos, line, ls, loc, attrs, emit) when c in [?\s, ?\t, ?\r] do
    parse_prolog_attrs_nt(rest, xml, pos + 1, line, ls, loc, attrs, emit)
  end
  defp parse_prolog_attrs_nt(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, attrs, emit) do
    parse_prolog_attrs_nt(rest, xml, pos + 1, line + 1, pos + 1, loc, attrs, emit)
  end
  defp parse_prolog_attrs_nt(<<c, _::binary>> = rest, xml, pos, line, ls, loc, attrs, emit) when is_name_start(c) do
    parse_name_nt(rest, xml, pos, line, ls, :prolog_attr, {loc, attrs, emit})
  end
  defp parse_prolog_attrs_nt(_, _xml, pos, line, ls, _loc, _attrs, emit) do
    emit.({:error, "Expected '?>'", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_comment_nt(<<"-->", _::binary>>, xml, pos, line, ls, loc, start, emit) do
    emit.({:comment, binary_part(xml, start, pos - start), loc})
    {pos + 3, line, ls}
  end
  defp parse_comment_nt(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, emit) do
    parse_comment_nt(rest, xml, pos + 1, line + 1, pos + 1, loc, start, emit)
  end
  defp parse_comment_nt(<<_, rest::binary>>, xml, pos, line, ls, loc, start, emit) do
    parse_comment_nt(rest, xml, pos + 1, line, ls, loc, start, emit)
  end
  defp parse_comment_nt(<<>>, _xml, pos, line, ls, _loc, _start, emit) do
    emit.({:error, "Unterminated comment", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_cdata_nt(<<"]]>", _::binary>>, xml, pos, line, ls, loc, start, emit) do
    emit.({:text, binary_part(xml, start, pos - start), loc})
    {pos + 3, line, ls}
  end
  defp parse_cdata_nt(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, emit) do
    parse_cdata_nt(rest, xml, pos + 1, line + 1, pos + 1, loc, start, emit)
  end
  defp parse_cdata_nt(<<_, rest::binary>>, xml, pos, line, ls, loc, start, emit) do
    parse_cdata_nt(rest, xml, pos + 1, line, ls, loc, start, emit)
  end
  defp parse_cdata_nt(<<>>, _xml, pos, line, ls, _loc, _start, emit) do
    emit.({:error, "Unterminated CDATA", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_close_tag_nt(<<c, _::binary>> = rest, xml, pos, line, ls, loc, emit) when is_name_start(c) do
    parse_name_nt(rest, xml, pos, line, ls, :close_tag, {loc, emit})
  end
  defp parse_close_tag_nt(_, _xml, pos, line, ls, _loc, emit) do
    emit.({:error, "Expected element name", {line, ls, pos}})
    {pos, line, ls}
  end

  defp finish_close_tag_nt(<<">", _::binary>>, _xml, pos, line, ls, name, loc, emit) do
    emit.({:close, name, loc})
    {pos + 1, line, ls}
  end
  defp finish_close_tag_nt(<<c, rest::binary>>, xml, pos, line, ls, name, loc, emit) when c in [?\s, ?\t, ?\r] do
    finish_close_tag_nt(rest, xml, pos + 1, line, ls, name, loc, emit)
  end
  defp finish_close_tag_nt(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, emit) do
    finish_close_tag_nt(rest, xml, pos + 1, line + 1, pos + 1, name, loc, emit)
  end
  defp finish_close_tag_nt(_, _xml, pos, line, ls, _name, _loc, emit) do
    emit.({:error, "Expected '>'", {line, ls, pos}})
    {pos, line, ls}
  end

  defp finish_open_tag_nt(<<"/>", _::binary>>, _xml, pos, line, ls, name, attrs, loc, emit) do
    emit.({:open, name, Enum.reverse(attrs), loc})
    emit.({:close, name})
    {pos + 2, line, ls}
  end
  defp finish_open_tag_nt(<<">", _::binary>>, _xml, pos, line, ls, name, attrs, loc, emit) do
    emit.({:open, name, Enum.reverse(attrs), loc})
    {pos + 1, line, ls}
  end
  defp finish_open_tag_nt(<<c, rest::binary>>, xml, pos, line, ls, name, attrs, loc, emit) when c in [?\s, ?\t, ?\r] do
    finish_open_tag_nt(rest, xml, pos + 1, line, ls, name, attrs, loc, emit)
  end
  defp finish_open_tag_nt(<<?\n, rest::binary>>, xml, pos, line, _ls, name, attrs, loc, emit) do
    finish_open_tag_nt(rest, xml, pos + 1, line + 1, pos + 1, name, attrs, loc, emit)
  end
  defp finish_open_tag_nt(<<c, _::binary>> = rest, xml, pos, line, ls, name, attrs, loc, emit) when is_name_start(c) do
    parse_name_nt(rest, xml, pos, line, ls, :attr_name, {name, attrs, loc, emit})
  end
  defp finish_open_tag_nt(_, _xml, pos, line, ls, _name, _attrs, _loc, emit) do
    emit.({:error, "Expected '>' or '/>'", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_text_nt(<<"<", _::binary>>, xml, pos, line, ls, loc, start, emit) do
    emit.({:text, binary_part(xml, start, pos - start), loc})
    {pos, line, ls}
  end
  defp parse_text_nt(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, emit) do
    parse_text_nt(rest, xml, pos + 1, line + 1, pos + 1, loc, start, emit)
  end
  defp parse_text_nt(<<_, rest::binary>>, xml, pos, line, ls, loc, start, emit) do
    parse_text_nt(rest, xml, pos + 1, line, ls, loc, start, emit)
  end
  defp parse_text_nt(<<>>, xml, pos, line, ls, loc, start, emit) do
    emit.({:text, binary_part(xml, start, pos - start), loc})
    {pos, line, ls}
  end

  defp parse_name_nt(rest, xml, pos, line, ls, context, extra) do
    scan_name_nt(rest, xml, pos, line, ls, context, extra, pos)
  end

  defp scan_name_nt(<<c, rest::binary>>, xml, pos, line, ls, context, extra, start) when is_name_char(c) do
    scan_name_nt(rest, xml, pos + 1, line, ls, context, extra, start)
  end
  defp scan_name_nt(rest, xml, pos, line, ls, context, extra, start) do
    name = binary_part(xml, start, pos - start)
    continue_nt(context, rest, xml, pos, line, ls, name, extra)
  end

  defp continue_nt(:open_tag, rest, xml, pos, line, ls, name, {loc, emit}) do
    finish_open_tag_nt(rest, xml, pos, line, ls, name, [], loc, emit)
  end
  defp continue_nt(:close_tag, rest, xml, pos, line, ls, name, {loc, emit}) do
    finish_close_tag_nt(rest, xml, pos, line, ls, name, loc, emit)
  end
  defp continue_nt(:attr_name, rest, xml, pos, line, ls, name, {tag, attrs, loc, emit}) do
    parse_attr_eq_nt(rest, xml, pos, line, ls, tag, name, attrs, loc, emit)
  end
  defp continue_nt(:prolog_attr, rest, xml, pos, line, ls, name, {loc, attrs, emit}) do
    parse_prolog_attr_eq_nt(rest, xml, pos, line, ls, name, loc, attrs, emit)
  end
  defp continue_nt(:pi_name, rest, xml, pos, line, ls, name, {loc, emit}) do
    skip_ws_then_pi_nt(rest, xml, pos, line, ls, name, loc, emit)
  end

  defp parse_attr_eq_nt(<<"=", rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, emit) do
    parse_attr_value_start_nt(rest, xml, pos + 1, line, ls, tag, name, attrs, loc, emit)
  end
  defp parse_attr_eq_nt(<<c, rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, emit) when c in [?\s, ?\t, ?\r] do
    parse_attr_eq_nt(rest, xml, pos + 1, line, ls, tag, name, attrs, loc, emit)
  end
  defp parse_attr_eq_nt(<<?\n, rest::binary>>, xml, pos, line, _ls, tag, name, attrs, loc, emit) do
    parse_attr_eq_nt(rest, xml, pos + 1, line + 1, pos + 1, tag, name, attrs, loc, emit)
  end
  defp parse_attr_eq_nt(_, _xml, pos, line, ls, _tag, _name, _attrs, _loc, emit) do
    emit.({:error, "Expected '='", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_attr_value_start_nt(<<c, rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, emit) when c in [?\s, ?\t, ?\r] do
    parse_attr_value_start_nt(rest, xml, pos + 1, line, ls, tag, name, attrs, loc, emit)
  end
  defp parse_attr_value_start_nt(<<?\n, rest::binary>>, xml, pos, line, _ls, tag, name, attrs, loc, emit) do
    parse_attr_value_start_nt(rest, xml, pos + 1, line + 1, pos + 1, tag, name, attrs, loc, emit)
  end
  defp parse_attr_value_start_nt(<<"\"", rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, emit) do
    parse_attr_value_nt(rest, xml, pos + 1, line, ls, ?", tag, name, attrs, loc, pos + 1, emit)
  end
  defp parse_attr_value_start_nt(<<"'", rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, emit) do
    parse_attr_value_nt(rest, xml, pos + 1, line, ls, ?', tag, name, attrs, loc, pos + 1, emit)
  end
  defp parse_attr_value_start_nt(_, _xml, pos, line, ls, _tag, _name, _attrs, _loc, emit) do
    emit.({:error, "Expected quoted value", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_attr_value_nt(<<"\"", rest::binary>>, xml, pos, line, ls, ?", tag, name, attrs, loc, start, emit) do
    value = binary_part(xml, start, pos - start)
    finish_open_tag_nt(rest, xml, pos + 1, line, ls, tag, [{name, value} | attrs], loc, emit)
  end
  defp parse_attr_value_nt(<<"'", rest::binary>>, xml, pos, line, ls, ?', tag, name, attrs, loc, start, emit) do
    value = binary_part(xml, start, pos - start)
    finish_open_tag_nt(rest, xml, pos + 1, line, ls, tag, [{name, value} | attrs], loc, emit)
  end
  defp parse_attr_value_nt(<<?\n, rest::binary>>, xml, pos, line, _ls, q, tag, name, attrs, loc, start, emit) do
    parse_attr_value_nt(rest, xml, pos + 1, line + 1, pos + 1, q, tag, name, attrs, loc, start, emit)
  end
  defp parse_attr_value_nt(<<_, rest::binary>>, xml, pos, line, ls, q, tag, name, attrs, loc, start, emit) do
    parse_attr_value_nt(rest, xml, pos + 1, line, ls, q, tag, name, attrs, loc, start, emit)
  end
  defp parse_attr_value_nt(<<>>, _xml, pos, line, ls, _q, _tag, _name, _attrs, _loc, _start, emit) do
    emit.({:error, "Unterminated attribute", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_prolog_attr_eq_nt(<<"=", rest::binary>>, xml, pos, line, ls, name, loc, attrs, emit) do
    parse_prolog_attr_value_start_nt(rest, xml, pos + 1, line, ls, name, loc, attrs, emit)
  end
  defp parse_prolog_attr_eq_nt(<<c, rest::binary>>, xml, pos, line, ls, name, loc, attrs, emit) when c in [?\s, ?\t, ?\r] do
    parse_prolog_attr_eq_nt(rest, xml, pos + 1, line, ls, name, loc, attrs, emit)
  end
  defp parse_prolog_attr_eq_nt(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, attrs, emit) do
    parse_prolog_attr_eq_nt(rest, xml, pos + 1, line + 1, pos + 1, name, loc, attrs, emit)
  end
  defp parse_prolog_attr_eq_nt(_, _xml, pos, line, ls, _name, _loc, _attrs, emit) do
    emit.({:error, "Expected '='", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_prolog_attr_value_start_nt(<<c, rest::binary>>, xml, pos, line, ls, name, loc, attrs, emit) when c in [?\s, ?\t, ?\r] do
    parse_prolog_attr_value_start_nt(rest, xml, pos + 1, line, ls, name, loc, attrs, emit)
  end
  defp parse_prolog_attr_value_start_nt(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, attrs, emit) do
    parse_prolog_attr_value_start_nt(rest, xml, pos + 1, line + 1, pos + 1, name, loc, attrs, emit)
  end
  defp parse_prolog_attr_value_start_nt(<<"\"", rest::binary>>, xml, pos, line, ls, name, loc, attrs, emit) do
    parse_prolog_attr_value_nt(rest, xml, pos + 1, line, ls, ?", name, loc, attrs, pos + 1, emit)
  end
  defp parse_prolog_attr_value_start_nt(<<"'", rest::binary>>, xml, pos, line, ls, name, loc, attrs, emit) do
    parse_prolog_attr_value_nt(rest, xml, pos + 1, line, ls, ?', name, loc, attrs, pos + 1, emit)
  end
  defp parse_prolog_attr_value_start_nt(_, _xml, pos, line, ls, _name, _loc, _attrs, emit) do
    emit.({:error, "Expected quoted value", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_prolog_attr_value_nt(<<"\"", rest::binary>>, xml, pos, line, ls, ?", name, loc, attrs, start, emit) do
    value = binary_part(xml, start, pos - start)
    parse_prolog_attrs_nt(rest, xml, pos + 1, line, ls, loc, [{name, value} | attrs], emit)
  end
  defp parse_prolog_attr_value_nt(<<"'", rest::binary>>, xml, pos, line, ls, ?', name, loc, attrs, start, emit) do
    value = binary_part(xml, start, pos - start)
    parse_prolog_attrs_nt(rest, xml, pos + 1, line, ls, loc, [{name, value} | attrs], emit)
  end
  defp parse_prolog_attr_value_nt(<<?\n, rest::binary>>, xml, pos, line, _ls, q, name, loc, attrs, start, emit) do
    parse_prolog_attr_value_nt(rest, xml, pos + 1, line + 1, pos + 1, q, name, loc, attrs, start, emit)
  end
  defp parse_prolog_attr_value_nt(<<_, rest::binary>>, xml, pos, line, ls, q, name, loc, attrs, start, emit) do
    parse_prolog_attr_value_nt(rest, xml, pos + 1, line, ls, q, name, loc, attrs, start, emit)
  end
  defp parse_prolog_attr_value_nt(<<>>, _xml, pos, line, ls, _q, _name, _loc, _attrs, _start, emit) do
    emit.({:error, "Unterminated attribute", {line, ls, pos}})
    {pos, line, ls}
  end

  # ============================================================
  # OPTIMIZATION #4: No line tracking
  # ============================================================

  def parse_no_lines(xml, emit) when is_binary(xml) and is_function(emit, 1) do
    do_parse_all_nl(xml, xml, 0, emit)
  end

  defp do_parse_all_nl(<<>>, _xml, pos, _emit), do: {:ok, pos}
  defp do_parse_all_nl(rest, xml, pos, emit) do
    pos = do_parse_one_nl(rest, xml, pos, emit)
    new_rest = binary_part(xml, pos, byte_size(xml) - pos)
    do_parse_all_nl(new_rest, xml, pos, emit)
  end

  defp do_parse_one_nl(<<>>, _xml, pos, _emit), do: pos
  defp do_parse_one_nl(<<"<?xml", rest::binary>>, xml, pos, emit) do
    parse_prolog_nl(rest, xml, pos + 5, {0, 0, pos + 1}, emit)
  end
  defp do_parse_one_nl(<<"<", _::binary>> = rest, xml, pos, emit) do
    parse_element_nl(rest, xml, pos, emit)
  end
  defp do_parse_one_nl(<<c, rest::binary>>, xml, pos, emit) when c in [?\s, ?\t, ?\r, ?\n] do
    do_parse_one_nl(rest, xml, pos + 1, emit)
  end
  defp do_parse_one_nl(rest, xml, pos, emit) do
    parse_text_nl(rest, xml, pos, {0, 0, pos}, pos, emit)
  end

  defp parse_element_nl(<<"<?", rest::binary>>, xml, pos, emit) do
    parse_pi_start_nl(rest, xml, pos + 2, {0, 0, pos + 1}, emit)
  end
  defp parse_element_nl(<<"<!--", rest::binary>>, xml, pos, emit) do
    parse_comment_nl(rest, xml, pos + 4, {0, 0, pos + 1}, pos + 4, emit)
  end
  defp parse_element_nl(<<"<![CDATA[", rest::binary>>, xml, pos, emit) do
    parse_cdata_nl(rest, xml, pos + 9, {0, 0, pos + 1}, pos + 9, emit)
  end
  defp parse_element_nl(<<"</", rest::binary>>, xml, pos, emit) do
    parse_close_tag_nl(rest, xml, pos + 2, {0, 0, pos + 1}, emit)
  end
  defp parse_element_nl(<<"<", c, _::binary>> = rest, xml, pos, emit) when is_name_start(c) do
    <<"<", rest2::binary>> = rest
    parse_name_nl(rest2, xml, pos + 1, :open_tag, {{0, 0, pos + 1}, emit})
  end
  defp parse_element_nl(_, _xml, pos, emit) do
    emit.({:error, "Invalid element", {0, 0, pos}})
    pos
  end

  defp parse_prolog_nl(<<"?>", _::binary>>, _xml, pos, loc, emit) do
    emit.({:prolog, "xml", [], loc})
    pos + 2
  end
  defp parse_prolog_nl(<<c, rest::binary>>, xml, pos, loc, emit) when c in [?\s, ?\t, ?\r, ?\n] do
    parse_prolog_nl(rest, xml, pos + 1, loc, emit)
  end
  defp parse_prolog_nl(<<c, _::binary>> = rest, xml, pos, loc, emit) when is_name_start(c) do
    parse_name_nl(rest, xml, pos, :prolog_attr, {loc, [], emit})
  end
  defp parse_prolog_nl(_, _xml, pos, _loc, emit) do
    emit.({:error, "Expected '?>'", {0, 0, pos}})
    pos
  end

  defp parse_prolog_attrs_nl(<<"?>", _::binary>>, _xml, pos, loc, attrs, emit) do
    emit.({:prolog, "xml", Enum.reverse(attrs), loc})
    pos + 2
  end
  defp parse_prolog_attrs_nl(<<c, rest::binary>>, xml, pos, loc, attrs, emit) when c in [?\s, ?\t, ?\r, ?\n] do
    parse_prolog_attrs_nl(rest, xml, pos + 1, loc, attrs, emit)
  end
  defp parse_prolog_attrs_nl(<<c, _::binary>> = rest, xml, pos, loc, attrs, emit) when is_name_start(c) do
    parse_name_nl(rest, xml, pos, :prolog_attr, {loc, attrs, emit})
  end
  defp parse_prolog_attrs_nl(_, _xml, pos, _loc, _attrs, emit) do
    emit.({:error, "Expected '?>'", {0, 0, pos}})
    pos
  end

  defp parse_pi_start_nl(<<c, _::binary>> = rest, xml, pos, loc, emit) when is_name_start(c) do
    parse_name_nl(rest, xml, pos, :pi_name, {loc, emit})
  end
  defp parse_pi_start_nl(_, _xml, pos, _loc, emit) do
    emit.({:error, "Expected PI target", {0, 0, pos}})
    pos
  end

  defp parse_pi_content_nl(<<"?>", _::binary>>, xml, pos, name, loc, start, emit) do
    emit.({:proc_inst, name, binary_part(xml, start, pos - start), loc})
    pos + 2
  end
  defp parse_pi_content_nl(<<_, rest::binary>>, xml, pos, name, loc, start, emit) do
    parse_pi_content_nl(rest, xml, pos + 1, name, loc, start, emit)
  end
  defp parse_pi_content_nl(<<>>, _xml, pos, _name, _loc, _start, emit) do
    emit.({:error, "Unterminated PI", {0, 0, pos}})
    pos
  end

  defp skip_ws_then_pi_nl(<<c, rest::binary>>, xml, pos, name, loc, emit) when c in [?\s, ?\t, ?\r, ?\n] do
    skip_ws_then_pi_nl(rest, xml, pos + 1, name, loc, emit)
  end
  defp skip_ws_then_pi_nl(rest, xml, pos, name, loc, emit) do
    parse_pi_content_nl(rest, xml, pos, name, loc, pos, emit)
  end

  defp parse_comment_nl(<<"-->", _::binary>>, xml, pos, loc, start, emit) do
    emit.({:comment, binary_part(xml, start, pos - start), loc})
    pos + 3
  end
  defp parse_comment_nl(<<_, rest::binary>>, xml, pos, loc, start, emit) do
    parse_comment_nl(rest, xml, pos + 1, loc, start, emit)
  end
  defp parse_comment_nl(<<>>, _xml, pos, _loc, _start, emit) do
    emit.({:error, "Unterminated comment", {0, 0, pos}})
    pos
  end

  defp parse_cdata_nl(<<"]]>", _::binary>>, xml, pos, loc, start, emit) do
    emit.({:text, binary_part(xml, start, pos - start), loc})
    pos + 3
  end
  defp parse_cdata_nl(<<_, rest::binary>>, xml, pos, loc, start, emit) do
    parse_cdata_nl(rest, xml, pos + 1, loc, start, emit)
  end
  defp parse_cdata_nl(<<>>, _xml, pos, _loc, _start, emit) do
    emit.({:error, "Unterminated CDATA", {0, 0, pos}})
    pos
  end

  defp parse_close_tag_nl(<<c, _::binary>> = rest, xml, pos, loc, emit) when is_name_start(c) do
    parse_name_nl(rest, xml, pos, :close_tag, {loc, emit})
  end
  defp parse_close_tag_nl(_, _xml, pos, _loc, emit) do
    emit.({:error, "Expected element name", {0, 0, pos}})
    pos
  end

  defp finish_close_tag_nl(<<">", _::binary>>, _xml, pos, name, loc, emit) do
    emit.({:close, name, loc})
    pos + 1
  end
  defp finish_close_tag_nl(<<c, rest::binary>>, xml, pos, name, loc, emit) when c in [?\s, ?\t, ?\r, ?\n] do
    finish_close_tag_nl(rest, xml, pos + 1, name, loc, emit)
  end
  defp finish_close_tag_nl(_, _xml, pos, _name, _loc, emit) do
    emit.({:error, "Expected '>'", {0, 0, pos}})
    pos
  end

  defp finish_open_tag_nl(<<"/>", _::binary>>, _xml, pos, name, attrs, loc, emit) do
    emit.({:open, name, Enum.reverse(attrs), loc})
    emit.({:close, name})
    pos + 2
  end
  defp finish_open_tag_nl(<<">", _::binary>>, _xml, pos, name, attrs, loc, emit) do
    emit.({:open, name, Enum.reverse(attrs), loc})
    pos + 1
  end
  defp finish_open_tag_nl(<<c, rest::binary>>, xml, pos, name, attrs, loc, emit) when c in [?\s, ?\t, ?\r, ?\n] do
    finish_open_tag_nl(rest, xml, pos + 1, name, attrs, loc, emit)
  end
  defp finish_open_tag_nl(<<c, _::binary>> = rest, xml, pos, name, attrs, loc, emit) when is_name_start(c) do
    parse_name_nl(rest, xml, pos, :attr_name, {name, attrs, loc, emit})
  end
  defp finish_open_tag_nl(_, _xml, pos, _name, _attrs, _loc, emit) do
    emit.({:error, "Expected '>' or '/>'", {0, 0, pos}})
    pos
  end

  defp parse_text_nl(<<"<", _::binary>>, xml, pos, loc, start, emit) do
    emit.({:text, binary_part(xml, start, pos - start), loc})
    pos
  end
  defp parse_text_nl(<<_, rest::binary>>, xml, pos, loc, start, emit) do
    parse_text_nl(rest, xml, pos + 1, loc, start, emit)
  end
  defp parse_text_nl(<<>>, xml, pos, loc, start, emit) do
    emit.({:text, binary_part(xml, start, pos - start), loc})
    pos
  end

  defp parse_name_nl(rest, xml, pos, context, extra) do
    scan_name_nl(rest, xml, pos, context, extra, pos)
  end

  defp scan_name_nl(<<c, rest::binary>>, xml, pos, context, extra, start) when is_name_char(c) do
    scan_name_nl(rest, xml, pos + 1, context, extra, start)
  end
  defp scan_name_nl(rest, xml, pos, context, extra, start) do
    name = binary_part(xml, start, pos - start)
    continue_nl(context, rest, xml, pos, name, extra)
  end

  defp continue_nl(:open_tag, rest, xml, pos, name, {loc, emit}) do
    finish_open_tag_nl(rest, xml, pos, name, [], loc, emit)
  end
  defp continue_nl(:close_tag, rest, xml, pos, name, {loc, emit}) do
    finish_close_tag_nl(rest, xml, pos, name, loc, emit)
  end
  defp continue_nl(:attr_name, rest, xml, pos, name, {tag, attrs, loc, emit}) do
    parse_attr_eq_nl(rest, xml, pos, tag, name, attrs, loc, emit)
  end
  defp continue_nl(:prolog_attr, rest, xml, pos, name, {loc, attrs, emit}) do
    parse_prolog_attr_eq_nl(rest, xml, pos, name, loc, attrs, emit)
  end
  defp continue_nl(:pi_name, rest, xml, pos, name, {loc, emit}) do
    skip_ws_then_pi_nl(rest, xml, pos, name, loc, emit)
  end

  defp parse_attr_eq_nl(<<"=", rest::binary>>, xml, pos, tag, name, attrs, loc, emit) do
    parse_attr_value_start_nl(rest, xml, pos + 1, tag, name, attrs, loc, emit)
  end
  defp parse_attr_eq_nl(<<c, rest::binary>>, xml, pos, tag, name, attrs, loc, emit) when c in [?\s, ?\t, ?\r, ?\n] do
    parse_attr_eq_nl(rest, xml, pos + 1, tag, name, attrs, loc, emit)
  end
  defp parse_attr_eq_nl(_, _xml, pos, _tag, _name, _attrs, _loc, emit) do
    emit.({:error, "Expected '='", {0, 0, pos}})
    pos
  end

  defp parse_attr_value_start_nl(<<c, rest::binary>>, xml, pos, tag, name, attrs, loc, emit) when c in [?\s, ?\t, ?\r, ?\n] do
    parse_attr_value_start_nl(rest, xml, pos + 1, tag, name, attrs, loc, emit)
  end
  defp parse_attr_value_start_nl(<<"\"", rest::binary>>, xml, pos, tag, name, attrs, loc, emit) do
    parse_attr_value_nl(rest, xml, pos + 1, ?", tag, name, attrs, loc, pos + 1, emit)
  end
  defp parse_attr_value_start_nl(<<"'", rest::binary>>, xml, pos, tag, name, attrs, loc, emit) do
    parse_attr_value_nl(rest, xml, pos + 1, ?', tag, name, attrs, loc, pos + 1, emit)
  end
  defp parse_attr_value_start_nl(_, _xml, pos, _tag, _name, _attrs, _loc, emit) do
    emit.({:error, "Expected quoted value", {0, 0, pos}})
    pos
  end

  defp parse_attr_value_nl(<<"\"", rest::binary>>, xml, pos, ?", tag, name, attrs, loc, start, emit) do
    finish_open_tag_nl(rest, xml, pos + 1, tag, [{name, binary_part(xml, start, pos - start)} | attrs], loc, emit)
  end
  defp parse_attr_value_nl(<<"'", rest::binary>>, xml, pos, ?', tag, name, attrs, loc, start, emit) do
    finish_open_tag_nl(rest, xml, pos + 1, tag, [{name, binary_part(xml, start, pos - start)} | attrs], loc, emit)
  end
  defp parse_attr_value_nl(<<_, rest::binary>>, xml, pos, q, tag, name, attrs, loc, start, emit) do
    parse_attr_value_nl(rest, xml, pos + 1, q, tag, name, attrs, loc, start, emit)
  end
  defp parse_attr_value_nl(<<>>, _xml, pos, _q, _tag, _name, _attrs, _loc, _start, emit) do
    emit.({:error, "Unterminated attribute", {0, 0, pos}})
    pos
  end

  defp parse_prolog_attr_eq_nl(<<"=", rest::binary>>, xml, pos, name, loc, attrs, emit) do
    parse_prolog_attr_value_start_nl(rest, xml, pos + 1, name, loc, attrs, emit)
  end
  defp parse_prolog_attr_eq_nl(<<c, rest::binary>>, xml, pos, name, loc, attrs, emit) when c in [?\s, ?\t, ?\r, ?\n] do
    parse_prolog_attr_eq_nl(rest, xml, pos + 1, name, loc, attrs, emit)
  end
  defp parse_prolog_attr_eq_nl(_, _xml, pos, _name, _loc, _attrs, emit) do
    emit.({:error, "Expected '='", {0, 0, pos}})
    pos
  end

  defp parse_prolog_attr_value_start_nl(<<c, rest::binary>>, xml, pos, name, loc, attrs, emit) when c in [?\s, ?\t, ?\r, ?\n] do
    parse_prolog_attr_value_start_nl(rest, xml, pos + 1, name, loc, attrs, emit)
  end
  defp parse_prolog_attr_value_start_nl(<<"\"", rest::binary>>, xml, pos, name, loc, attrs, emit) do
    parse_prolog_attr_value_nl(rest, xml, pos + 1, ?", name, loc, attrs, pos + 1, emit)
  end
  defp parse_prolog_attr_value_start_nl(<<"'", rest::binary>>, xml, pos, name, loc, attrs, emit) do
    parse_prolog_attr_value_nl(rest, xml, pos + 1, ?', name, loc, attrs, pos + 1, emit)
  end
  defp parse_prolog_attr_value_start_nl(_, _xml, pos, _name, _loc, _attrs, emit) do
    emit.({:error, "Expected quoted value", {0, 0, pos}})
    pos
  end

  defp parse_prolog_attr_value_nl(<<"\"", rest::binary>>, xml, pos, ?", name, loc, attrs, start, emit) do
    parse_prolog_attrs_nl(rest, xml, pos + 1, loc, [{name, binary_part(xml, start, pos - start)} | attrs], emit)
  end
  defp parse_prolog_attr_value_nl(<<"'", rest::binary>>, xml, pos, ?', name, loc, attrs, start, emit) do
    parse_prolog_attrs_nl(rest, xml, pos + 1, loc, [{name, binary_part(xml, start, pos - start)} | attrs], emit)
  end
  defp parse_prolog_attr_value_nl(<<_, rest::binary>>, xml, pos, q, name, loc, attrs, start, emit) do
    parse_prolog_attr_value_nl(rest, xml, pos + 1, q, name, loc, attrs, start, emit)
  end
  defp parse_prolog_attr_value_nl(<<>>, _xml, pos, _q, _name, _loc, _attrs, _start, emit) do
    emit.({:error, "Unterminated attribute", {0, 0, pos}})
    pos
  end
end
