defmodule FnXML.Parser.RecursiveCPS do
  @moduledoc """
  Recursive descent parser using continuation-passing style.

  Uses binary pattern matching with `rest`, but never stores `rest` in state.
  Only `original` + `pos` are stored for Stream.resource state.

  Accepts an emit callback for flexible event handling:
  - Stream accumulation (default)
  - Message passing to another process
  - Direct processing
  """

  defguardp is_name_start(c) when
    c in ?a..?z or c in ?A..?Z or c == ?_ or c == ?: or
    c in 0x00C0..0x00D6 or c in 0x00D8..0x00F6 or
    c in 0x00F8..0x02FF or c in 0x0370..0x037D or
    c in 0x037F..0x1FFF or c in 0x200C..0x200D

  defguardp is_name_char(c) when
    is_name_start(c) or c == ?- or c == ?. or c in ?0..?9 or
    c == 0x00B7 or c in 0x0300..0x036F or c in 0x203F..0x2040

  @doc """
  Parse XML into a stream of events.
  """
  def parse(xml) when is_binary(xml) do
    Stream.resource(
      fn -> {xml, 0, 1, 0} end,
      &next_token/1,
      fn _ -> :ok end
    )
  end

  @doc """
  Parse XML with a custom emit callback.

  The callback receives each event as it's parsed.
  Returns `{:ok, final_pos, final_line, final_ls}` or `{:error, reason}`.

  ## Examples

      # Send events to a process
      parse(xml, fn event -> send(pid, event) end)

      # Collect in an agent
      parse(xml, fn event -> Agent.update(agent, &[event | &1]) end)
  """
  def parse(xml, emit) when is_binary(xml) and is_function(emit, 1) do
    rest = xml
    do_parse_all(rest, xml, 0, 1, 0, emit)
  end

  # === Stream interface (fast accumulator path) ===

  defp next_token({xml, pos, _line, _ls}) when pos >= byte_size(xml) do
    {:halt, nil}
  end

  defp next_token({xml, pos, line, ls}) do
    rest = binary_part(xml, pos, byte_size(xml) - pos)
    {tokens, pos, line, ls} = do_parse_one_acc(rest, xml, pos, line, ls, [])
    {Enum.reverse(tokens), {xml, pos, line, ls}}
  end

  # Fast accumulator-based parsing for streams (no callback overhead)
  defp do_parse_one_acc(<<>>, _xml, pos, line, ls, acc), do: {acc, pos, line, ls}

  defp do_parse_one_acc(<<"<?xml", rest::binary>>, xml, pos, line, ls, acc) do
    parse_prolog_acc(rest, xml, pos + 5, line, ls, {line, ls, pos + 1}, acc)
  end

  defp do_parse_one_acc(<<"<", _::binary>> = rest, xml, pos, line, ls, acc) do
    parse_element_acc(rest, xml, pos, line, ls, acc)
  end

  defp do_parse_one_acc(<<c, rest::binary>>, xml, pos, line, ls, acc) when c in [?\s, ?\t, ?\r] do
    do_parse_one_acc(rest, xml, pos + 1, line, ls, acc)
  end

  defp do_parse_one_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, acc) do
    do_parse_one_acc(rest, xml, pos + 1, line + 1, pos + 1, acc)
  end

  defp do_parse_one_acc(rest, xml, pos, line, ls, acc) do
    parse_text_acc(rest, xml, pos, line, ls, {line, ls, pos}, pos, acc)
  end

  # === Full parse with callback (no stream) ===

  defp do_parse_all(<<>>, _xml, pos, line, ls, _emit) do
    {:ok, pos, line, ls}
  end

  defp do_parse_all(rest, xml, pos, line, ls, emit) do
    {pos, line, ls} = do_parse_one(rest, xml, pos, line, ls, emit)
    new_rest = binary_part(xml, pos, byte_size(xml) - pos)
    do_parse_all(new_rest, xml, pos, line, ls, emit)
  end

  # === Main dispatch - parse one event ===

  defp do_parse_one(<<>>, _xml, pos, line, ls, _emit) do
    {pos, line, ls}
  end

  defp do_parse_one(<<"<?xml", rest::binary>>, xml, pos, line, ls, emit) do
    parse_prolog(rest, xml, pos + 5, line, ls, {line, ls, pos + 1}, emit)
  end

  defp do_parse_one(<<"<", _::binary>> = rest, xml, pos, line, ls, emit) do
    parse_element(rest, xml, pos, line, ls, emit)
  end

  defp do_parse_one(<<c, rest::binary>>, xml, pos, line, ls, emit) when c in [?\s, ?\t, ?\r] do
    do_parse_one(rest, xml, pos + 1, line, ls, emit)
  end

  defp do_parse_one(<<?\n, rest::binary>>, xml, pos, line, _ls, emit) do
    do_parse_one(rest, xml, pos + 1, line + 1, pos + 1, emit)
  end

  defp do_parse_one(rest, xml, pos, line, ls, emit) do
    parse_text(rest, xml, pos, line, ls, {line, ls, pos}, pos, emit)
  end

  # === Prolog ===

  defp parse_prolog(<<"?>", _::binary>>, _xml, pos, line, ls, loc, emit) do
    emit.({:prolog, "xml", [], loc})
    skip_ws_then_done(pos + 2, line, ls)
  end

  defp parse_prolog(<<c, rest::binary>>, xml, pos, line, ls, loc, emit) when c in [?\s, ?\t, ?\r] do
    parse_prolog(rest, xml, pos + 1, line, ls, loc, emit)
  end

  defp parse_prolog(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, emit) do
    parse_prolog(rest, xml, pos + 1, line + 1, pos + 1, loc, emit)
  end

  defp parse_prolog(<<c, _::binary>> = rest, xml, pos, line, ls, loc, emit) when is_name_start(c) do
    parse_name(rest, xml, pos, line, ls, :prolog_attr, {loc, [], emit})
  end

  defp parse_prolog(_, _xml, pos, line, ls, _loc, emit) do
    emit.({:error, "Expected '?>' or attribute", {line, ls, pos}})
    {pos, line, ls}
  end

  # Prolog with attrs
  defp parse_prolog_attrs(<<"?>", _::binary>>, _xml, pos, line, ls, loc, attrs, emit) do
    emit.({:prolog, "xml", Enum.reverse(attrs), loc})
    skip_ws_then_done(pos + 2, line, ls)
  end

  defp parse_prolog_attrs(<<c, rest::binary>>, xml, pos, line, ls, loc, attrs, emit) when c in [?\s, ?\t, ?\r] do
    parse_prolog_attrs(rest, xml, pos + 1, line, ls, loc, attrs, emit)
  end

  defp parse_prolog_attrs(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, attrs, emit) do
    parse_prolog_attrs(rest, xml, pos + 1, line + 1, pos + 1, loc, attrs, emit)
  end

  defp parse_prolog_attrs(<<c, _::binary>> = rest, xml, pos, line, ls, loc, attrs, emit) when is_name_start(c) do
    parse_name(rest, xml, pos, line, ls, :prolog_attr, {loc, attrs, emit})
  end

  defp parse_prolog_attrs(_, _xml, pos, line, ls, _loc, _attrs, emit) do
    emit.({:error, "Expected '?>' or attribute", {line, ls, pos}})
    {pos, line, ls}
  end

  # === Element dispatch ===

  defp parse_element(<<"<!--", rest::binary>>, xml, pos, line, ls, emit) do
    parse_comment(rest, xml, pos + 4, line, ls, {line, ls, pos + 1}, pos + 4, emit)
  end

  defp parse_element(<<"<![CDATA[", rest::binary>>, xml, pos, line, ls, emit) do
    parse_cdata(rest, xml, pos + 9, line, ls, {line, ls, pos + 1}, pos + 9, emit)
  end

  defp parse_element(<<"</", rest::binary>>, xml, pos, line, ls, emit) do
    parse_close_tag_start(rest, xml, pos + 2, line, ls, {line, ls, pos + 1}, emit)
  end

  defp parse_element(<<"<?", rest::binary>>, xml, pos, line, ls, emit) do
    parse_pi_start(rest, xml, pos + 2, line, ls, {line, ls, pos + 1}, emit)
  end

  defp parse_element(<<"<", c, _::binary>> = rest, xml, pos, line, ls, emit) when is_name_start(c) do
    <<"<", rest2::binary>> = rest
    parse_name(rest2, xml, pos + 1, line, ls, :open_tag, {{line, ls, pos + 1}, emit})
  end

  defp parse_element(_, _xml, pos, line, ls, emit) do
    emit.({:error, "Invalid element", {line, ls, pos}})
    {pos, line, ls}
  end

  # === Open tag ===

  defp finish_open_tag(<<"/>", _::binary>>, _xml, pos, line, ls, name, attrs, loc, emit) do
    emit.({:open, name, Enum.reverse(attrs), loc})
    emit.({:close, name})
    {pos + 2, line, ls}
  end

  defp finish_open_tag(<<">", _::binary>>, _xml, pos, line, ls, name, attrs, loc, emit) do
    emit.({:open, name, Enum.reverse(attrs), loc})
    {pos + 1, line, ls}
  end

  defp finish_open_tag(<<c, rest::binary>>, xml, pos, line, ls, name, attrs, loc, emit) when c in [?\s, ?\t, ?\r] do
    finish_open_tag(rest, xml, pos + 1, line, ls, name, attrs, loc, emit)
  end

  defp finish_open_tag(<<?\n, rest::binary>>, xml, pos, line, _ls, name, attrs, loc, emit) do
    finish_open_tag(rest, xml, pos + 1, line + 1, pos + 1, name, attrs, loc, emit)
  end

  defp finish_open_tag(<<c, _::binary>> = rest, xml, pos, line, ls, name, attrs, loc, emit) when is_name_start(c) do
    parse_name(rest, xml, pos, line, ls, :attr_name, {name, attrs, loc, emit})
  end

  defp finish_open_tag(_, _xml, pos, line, ls, _name, _attrs, _loc, emit) do
    emit.({:error, "Expected '>', '/>', or attribute", {line, ls, pos}})
    {pos, line, ls}
  end

  # === Close tag ===

  defp parse_close_tag_start(<<c, _::binary>> = rest, xml, pos, line, ls, loc, emit) when is_name_start(c) do
    parse_name(rest, xml, pos, line, ls, :close_tag, {loc, emit})
  end

  defp parse_close_tag_start(_, _xml, pos, line, ls, _loc, emit) do
    emit.({:error, "Expected element name", {line, ls, pos}})
    {pos, line, ls}
  end

  defp finish_close_tag(<<">", _::binary>>, _xml, pos, line, ls, name, loc, emit) do
    emit.({:close, name, loc})
    {pos + 1, line, ls}
  end

  defp finish_close_tag(<<c, rest::binary>>, xml, pos, line, ls, name, loc, emit) when c in [?\s, ?\t, ?\r] do
    finish_close_tag(rest, xml, pos + 1, line, ls, name, loc, emit)
  end

  defp finish_close_tag(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, emit) do
    finish_close_tag(rest, xml, pos + 1, line + 1, pos + 1, name, loc, emit)
  end

  defp finish_close_tag(_, _xml, pos, line, ls, _name, _loc, emit) do
    emit.({:error, "Expected '>'", {line, ls, pos}})
    {pos, line, ls}
  end

  # === Comment ===

  defp parse_comment(<<"-->", _::binary>>, xml, pos, line, ls, loc, start, emit) do
    content = binary_part(xml, start, pos - start)
    emit.({:comment, content, loc})
    {pos + 3, line, ls}
  end

  defp parse_comment(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, emit) do
    parse_comment(rest, xml, pos + 1, line + 1, pos + 1, loc, start, emit)
  end

  defp parse_comment(<<_, rest::binary>>, xml, pos, line, ls, loc, start, emit) do
    parse_comment(rest, xml, pos + 1, line, ls, loc, start, emit)
  end

  defp parse_comment(<<>>, _xml, pos, line, ls, _loc, _start, emit) do
    emit.({:error, "Unterminated comment", {line, ls, pos}})
    {pos, line, ls}
  end

  # === CDATA ===

  defp parse_cdata(<<"]]>", _::binary>>, xml, pos, line, ls, loc, start, emit) do
    content = binary_part(xml, start, pos - start)
    emit.({:text, content, loc})
    {pos + 3, line, ls}
  end

  defp parse_cdata(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, emit) do
    parse_cdata(rest, xml, pos + 1, line + 1, pos + 1, loc, start, emit)
  end

  defp parse_cdata(<<_, rest::binary>>, xml, pos, line, ls, loc, start, emit) do
    parse_cdata(rest, xml, pos + 1, line, ls, loc, start, emit)
  end

  defp parse_cdata(<<>>, _xml, pos, line, ls, _loc, _start, emit) do
    emit.({:error, "Unterminated CDATA", {line, ls, pos}})
    {pos, line, ls}
  end

  # === Processing Instruction ===

  defp parse_pi_start(<<c, _::binary>> = rest, xml, pos, line, ls, loc, emit) when is_name_start(c) do
    parse_name(rest, xml, pos, line, ls, :pi_name, {loc, emit})
  end

  defp parse_pi_start(_, _xml, pos, line, ls, _loc, emit) do
    emit.({:error, "Expected PI target name", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_pi_content(<<"?>", _::binary>>, xml, pos, line, ls, name, loc, start, emit) do
    content = binary_part(xml, start, pos - start) |> String.trim()
    emit.({:proc_inst, name, content, loc})
    {pos + 2, line, ls}
  end

  defp parse_pi_content(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, start, emit) do
    parse_pi_content(rest, xml, pos + 1, line + 1, pos + 1, name, loc, start, emit)
  end

  defp parse_pi_content(<<_, rest::binary>>, xml, pos, line, ls, name, loc, start, emit) do
    parse_pi_content(rest, xml, pos + 1, line, ls, name, loc, start, emit)
  end

  defp parse_pi_content(<<>>, _xml, pos, line, ls, _name, _loc, _start, emit) do
    emit.({:error, "Unterminated PI", {line, ls, pos}})
    {pos, line, ls}
  end

  # === Text ===

  defp parse_text(<<"<", _::binary>>, xml, pos, line, ls, loc, start, emit) do
    content = binary_part(xml, start, pos - start)
    emit.({:text, content, loc})
    {pos, line, ls}
  end

  defp parse_text(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, emit) do
    parse_text(rest, xml, pos + 1, line + 1, pos + 1, loc, start, emit)
  end

  defp parse_text(<<_, rest::binary>>, xml, pos, line, ls, loc, start, emit) do
    parse_text(rest, xml, pos + 1, line, ls, loc, start, emit)
  end

  defp parse_text(<<>>, xml, pos, line, ls, loc, start, emit) do
    content = binary_part(xml, start, pos - start)
    emit.({:text, content, loc})
    {pos, line, ls}
  end

  # === Name parsing with continuation ===

  defp parse_name(rest, xml, pos, line, ls, context, extra) do
    scan_name(rest, xml, pos, line, ls, context, extra, pos)
  end

  defp scan_name(<<c, rest::binary>>, xml, pos, line, ls, context, extra, start) when is_name_char(c) do
    scan_name(rest, xml, pos + 1, line, ls, context, extra, start)
  end

  defp scan_name(rest, xml, pos, line, ls, context, extra, start) do
    name = binary_part(xml, start, pos - start)
    continue(context, rest, xml, pos, line, ls, name, extra)
  end

  # === Continuations ===

  defp continue(:open_tag, rest, xml, pos, line, ls, name, {loc, emit}) do
    finish_open_tag(rest, xml, pos, line, ls, name, [], loc, emit)
  end

  defp continue(:close_tag, rest, xml, pos, line, ls, name, {loc, emit}) do
    finish_close_tag(rest, xml, pos, line, ls, name, loc, emit)
  end

  defp continue(:attr_name, rest, xml, pos, line, ls, name, {tag, attrs, loc, emit}) do
    parse_attr_eq(rest, xml, pos, line, ls, tag, name, attrs, loc, emit)
  end

  defp continue(:prolog_attr, rest, xml, pos, line, ls, name, {loc, attrs, emit}) do
    parse_prolog_attr_eq(rest, xml, pos, line, ls, name, loc, attrs, emit)
  end

  defp continue(:pi_name, rest, xml, pos, line, ls, name, {loc, emit}) do
    skip_ws_then_pi(rest, xml, pos, line, ls, name, loc, emit)
  end

  # === Attribute parsing ===

  defp parse_attr_eq(<<"=", rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, emit) do
    parse_attr_value_start(rest, xml, pos + 1, line, ls, tag, name, attrs, loc, emit)
  end

  defp parse_attr_eq(<<c, rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, emit) when c in [?\s, ?\t, ?\r] do
    parse_attr_eq(rest, xml, pos + 1, line, ls, tag, name, attrs, loc, emit)
  end

  defp parse_attr_eq(<<?\n, rest::binary>>, xml, pos, line, _ls, tag, name, attrs, loc, emit) do
    parse_attr_eq(rest, xml, pos + 1, line + 1, pos + 1, tag, name, attrs, loc, emit)
  end

  defp parse_attr_eq(_, _xml, pos, line, ls, _tag, _name, _attrs, _loc, emit) do
    emit.({:error, "Expected '='", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_attr_value_start(<<c, rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, emit) when c in [?\s, ?\t, ?\r] do
    parse_attr_value_start(rest, xml, pos + 1, line, ls, tag, name, attrs, loc, emit)
  end

  defp parse_attr_value_start(<<?\n, rest::binary>>, xml, pos, line, _ls, tag, name, attrs, loc, emit) do
    parse_attr_value_start(rest, xml, pos + 1, line + 1, pos + 1, tag, name, attrs, loc, emit)
  end

  defp parse_attr_value_start(<<"\"", rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, emit) do
    parse_attr_value(rest, xml, pos + 1, line, ls, ?", tag, name, attrs, loc, pos + 1, emit)
  end

  defp parse_attr_value_start(<<"'", rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, emit) do
    parse_attr_value(rest, xml, pos + 1, line, ls, ?', tag, name, attrs, loc, pos + 1, emit)
  end

  defp parse_attr_value_start(_, _xml, pos, line, ls, _tag, _name, _attrs, _loc, emit) do
    emit.({:error, "Expected quoted value", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_attr_value(<<"\"", rest::binary>>, xml, pos, line, ls, ?", tag, name, attrs, loc, start, emit) do
    value = binary_part(xml, start, pos - start)
    finish_open_tag(rest, xml, pos + 1, line, ls, tag, [{name, value} | attrs], loc, emit)
  end

  defp parse_attr_value(<<"'", rest::binary>>, xml, pos, line, ls, ?', tag, name, attrs, loc, start, emit) do
    value = binary_part(xml, start, pos - start)
    finish_open_tag(rest, xml, pos + 1, line, ls, tag, [{name, value} | attrs], loc, emit)
  end

  defp parse_attr_value(<<?\n, rest::binary>>, xml, pos, line, _ls, q, tag, name, attrs, loc, start, emit) do
    parse_attr_value(rest, xml, pos + 1, line + 1, pos + 1, q, tag, name, attrs, loc, start, emit)
  end

  defp parse_attr_value(<<_, rest::binary>>, xml, pos, line, ls, q, tag, name, attrs, loc, start, emit) do
    parse_attr_value(rest, xml, pos + 1, line, ls, q, tag, name, attrs, loc, start, emit)
  end

  defp parse_attr_value(<<>>, _xml, pos, line, ls, _q, _tag, _name, _attrs, _loc, _start, emit) do
    emit.({:error, "Unterminated attribute value", {line, ls, pos}})
    {pos, line, ls}
  end

  # === Prolog attribute ===

  defp parse_prolog_attr_eq(<<"=", rest::binary>>, xml, pos, line, ls, name, loc, attrs, emit) do
    parse_prolog_attr_value_start(rest, xml, pos + 1, line, ls, name, loc, attrs, emit)
  end

  defp parse_prolog_attr_eq(<<c, rest::binary>>, xml, pos, line, ls, name, loc, attrs, emit) when c in [?\s, ?\t, ?\r] do
    parse_prolog_attr_eq(rest, xml, pos + 1, line, ls, name, loc, attrs, emit)
  end

  defp parse_prolog_attr_eq(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, attrs, emit) do
    parse_prolog_attr_eq(rest, xml, pos + 1, line + 1, pos + 1, name, loc, attrs, emit)
  end

  defp parse_prolog_attr_eq(_, _xml, pos, line, ls, _name, _loc, _attrs, emit) do
    emit.({:error, "Expected '='", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_prolog_attr_value_start(<<c, rest::binary>>, xml, pos, line, ls, name, loc, attrs, emit) when c in [?\s, ?\t, ?\r] do
    parse_prolog_attr_value_start(rest, xml, pos + 1, line, ls, name, loc, attrs, emit)
  end

  defp parse_prolog_attr_value_start(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, attrs, emit) do
    parse_prolog_attr_value_start(rest, xml, pos + 1, line + 1, pos + 1, name, loc, attrs, emit)
  end

  defp parse_prolog_attr_value_start(<<"\"", rest::binary>>, xml, pos, line, ls, name, loc, attrs, emit) do
    parse_prolog_attr_value(rest, xml, pos + 1, line, ls, ?", name, loc, attrs, pos + 1, emit)
  end

  defp parse_prolog_attr_value_start(<<"'", rest::binary>>, xml, pos, line, ls, name, loc, attrs, emit) do
    parse_prolog_attr_value(rest, xml, pos + 1, line, ls, ?', name, loc, attrs, pos + 1, emit)
  end

  defp parse_prolog_attr_value_start(_, _xml, pos, line, ls, _name, _loc, _attrs, emit) do
    emit.({:error, "Expected quoted value", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_prolog_attr_value(<<"\"", rest::binary>>, xml, pos, line, ls, ?", name, loc, attrs, start, emit) do
    value = binary_part(xml, start, pos - start)
    parse_prolog_attrs(rest, xml, pos + 1, line, ls, loc, [{name, value} | attrs], emit)
  end

  defp parse_prolog_attr_value(<<"'", rest::binary>>, xml, pos, line, ls, ?', name, loc, attrs, start, emit) do
    value = binary_part(xml, start, pos - start)
    parse_prolog_attrs(rest, xml, pos + 1, line, ls, loc, [{name, value} | attrs], emit)
  end

  defp parse_prolog_attr_value(<<?\n, rest::binary>>, xml, pos, line, _ls, q, name, loc, attrs, start, emit) do
    parse_prolog_attr_value(rest, xml, pos + 1, line + 1, pos + 1, q, name, loc, attrs, start, emit)
  end

  defp parse_prolog_attr_value(<<_, rest::binary>>, xml, pos, line, ls, q, name, loc, attrs, start, emit) do
    parse_prolog_attr_value(rest, xml, pos + 1, line, ls, q, name, loc, attrs, start, emit)
  end

  defp parse_prolog_attr_value(<<>>, _xml, pos, line, ls, _q, _name, _loc, _attrs, _start, emit) do
    emit.({:error, "Unterminated attribute value", {line, ls, pos}})
    {pos, line, ls}
  end

  # === Helpers ===

  defp skip_ws_then_done(pos, line, ls) do
    {pos, line, ls}
  end

  defp skip_ws_then_pi(<<c, rest::binary>>, xml, pos, line, ls, name, loc, emit) when c in [?\s, ?\t, ?\r] do
    skip_ws_then_pi(rest, xml, pos + 1, line, ls, name, loc, emit)
  end

  defp skip_ws_then_pi(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, emit) do
    skip_ws_then_pi(rest, xml, pos + 1, line + 1, pos + 1, name, loc, emit)
  end

  defp skip_ws_then_pi(rest, xml, pos, line, ls, name, loc, emit) do
    parse_pi_content(rest, xml, pos, line, ls, name, loc, pos, emit)
  end

  # ============================================================
  # ACCUMULATOR-BASED FUNCTIONS (fast path for streams)
  # ============================================================

  # === Prolog (acc) ===

  defp parse_prolog_acc(<<"?>", _::binary>>, _xml, pos, line, ls, loc, acc) do
    {[{:prolog, "xml", [], loc} | acc], pos + 2, line, ls}
  end

  defp parse_prolog_acc(<<c, rest::binary>>, xml, pos, line, ls, loc, acc) when c in [?\s, ?\t, ?\r] do
    parse_prolog_acc(rest, xml, pos + 1, line, ls, loc, acc)
  end

  defp parse_prolog_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, acc) do
    parse_prolog_acc(rest, xml, pos + 1, line + 1, pos + 1, loc, acc)
  end

  defp parse_prolog_acc(<<c, _::binary>> = rest, xml, pos, line, ls, loc, acc) when is_name_start(c) do
    parse_name_acc(rest, xml, pos, line, ls, :prolog_attr, {loc, [], acc})
  end

  defp parse_prolog_acc(_, _xml, pos, line, ls, _loc, acc) do
    {[{:error, "Expected '?>' or attribute", {line, ls, pos}} | acc], pos, line, ls}
  end

  defp parse_prolog_attrs_acc(<<"?>", _::binary>>, _xml, pos, line, ls, loc, attrs, acc) do
    {[{:prolog, "xml", Enum.reverse(attrs), loc} | acc], pos + 2, line, ls}
  end

  defp parse_prolog_attrs_acc(<<c, rest::binary>>, xml, pos, line, ls, loc, attrs, acc) when c in [?\s, ?\t, ?\r] do
    parse_prolog_attrs_acc(rest, xml, pos + 1, line, ls, loc, attrs, acc)
  end

  defp parse_prolog_attrs_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, attrs, acc) do
    parse_prolog_attrs_acc(rest, xml, pos + 1, line + 1, pos + 1, loc, attrs, acc)
  end

  defp parse_prolog_attrs_acc(<<c, _::binary>> = rest, xml, pos, line, ls, loc, attrs, acc) when is_name_start(c) do
    parse_name_acc(rest, xml, pos, line, ls, :prolog_attr, {loc, attrs, acc})
  end

  defp parse_prolog_attrs_acc(_, _xml, pos, line, ls, _loc, _attrs, acc) do
    {[{:error, "Expected '?>' or attribute", {line, ls, pos}} | acc], pos, line, ls}
  end

  # === Element dispatch (acc) ===

  defp parse_element_acc(<<"<!--", rest::binary>>, xml, pos, line, ls, acc) do
    parse_comment_acc(rest, xml, pos + 4, line, ls, {line, ls, pos + 1}, pos + 4, acc)
  end

  defp parse_element_acc(<<"<![CDATA[", rest::binary>>, xml, pos, line, ls, acc) do
    parse_cdata_acc(rest, xml, pos + 9, line, ls, {line, ls, pos + 1}, pos + 9, acc)
  end

  defp parse_element_acc(<<"</", rest::binary>>, xml, pos, line, ls, acc) do
    parse_close_tag_start_acc(rest, xml, pos + 2, line, ls, {line, ls, pos + 1}, acc)
  end

  defp parse_element_acc(<<"<?", rest::binary>>, xml, pos, line, ls, acc) do
    parse_pi_start_acc(rest, xml, pos + 2, line, ls, {line, ls, pos + 1}, acc)
  end

  defp parse_element_acc(<<"<", c, _::binary>> = rest, xml, pos, line, ls, acc) when is_name_start(c) do
    <<"<", rest2::binary>> = rest
    parse_name_acc(rest2, xml, pos + 1, line, ls, :open_tag, {{line, ls, pos + 1}, acc})
  end

  defp parse_element_acc(_, _xml, pos, line, ls, acc) do
    {[{:error, "Invalid element", {line, ls, pos}} | acc], pos, line, ls}
  end

  # === Open tag (acc) ===

  defp finish_open_tag_acc(<<"/>", _::binary>>, _xml, pos, line, ls, name, attrs, loc, acc) do
    acc = [{:close, name} | [{:open, name, Enum.reverse(attrs), loc} | acc]]
    {acc, pos + 2, line, ls}
  end

  defp finish_open_tag_acc(<<">", _::binary>>, _xml, pos, line, ls, name, attrs, loc, acc) do
    {[{:open, name, Enum.reverse(attrs), loc} | acc], pos + 1, line, ls}
  end

  defp finish_open_tag_acc(<<c, rest::binary>>, xml, pos, line, ls, name, attrs, loc, acc) when c in [?\s, ?\t, ?\r] do
    finish_open_tag_acc(rest, xml, pos + 1, line, ls, name, attrs, loc, acc)
  end

  defp finish_open_tag_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, name, attrs, loc, acc) do
    finish_open_tag_acc(rest, xml, pos + 1, line + 1, pos + 1, name, attrs, loc, acc)
  end

  defp finish_open_tag_acc(<<c, _::binary>> = rest, xml, pos, line, ls, name, attrs, loc, acc) when is_name_start(c) do
    parse_name_acc(rest, xml, pos, line, ls, :attr_name, {name, attrs, loc, acc})
  end

  defp finish_open_tag_acc(_, _xml, pos, line, ls, _name, _attrs, _loc, acc) do
    {[{:error, "Expected '>', '/>', or attribute", {line, ls, pos}} | acc], pos, line, ls}
  end

  # === Close tag (acc) ===

  defp parse_close_tag_start_acc(<<c, _::binary>> = rest, xml, pos, line, ls, loc, acc) when is_name_start(c) do
    parse_name_acc(rest, xml, pos, line, ls, :close_tag, {loc, acc})
  end

  defp parse_close_tag_start_acc(_, _xml, pos, line, ls, _loc, acc) do
    {[{:error, "Expected element name", {line, ls, pos}} | acc], pos, line, ls}
  end

  defp finish_close_tag_acc(<<">", _::binary>>, _xml, pos, line, ls, name, loc, acc) do
    {[{:close, name, loc} | acc], pos + 1, line, ls}
  end

  defp finish_close_tag_acc(<<c, rest::binary>>, xml, pos, line, ls, name, loc, acc) when c in [?\s, ?\t, ?\r] do
    finish_close_tag_acc(rest, xml, pos + 1, line, ls, name, loc, acc)
  end

  defp finish_close_tag_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, acc) do
    finish_close_tag_acc(rest, xml, pos + 1, line + 1, pos + 1, name, loc, acc)
  end

  defp finish_close_tag_acc(_, _xml, pos, line, ls, _name, _loc, acc) do
    {[{:error, "Expected '>'", {line, ls, pos}} | acc], pos, line, ls}
  end

  # === Comment (acc) ===

  defp parse_comment_acc(<<"-->", _::binary>>, xml, pos, line, ls, loc, start, acc) do
    content = binary_part(xml, start, pos - start)
    {[{:comment, content, loc} | acc], pos + 3, line, ls}
  end

  defp parse_comment_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, acc) do
    parse_comment_acc(rest, xml, pos + 1, line + 1, pos + 1, loc, start, acc)
  end

  defp parse_comment_acc(<<_, rest::binary>>, xml, pos, line, ls, loc, start, acc) do
    parse_comment_acc(rest, xml, pos + 1, line, ls, loc, start, acc)
  end

  defp parse_comment_acc(<<>>, _xml, pos, line, ls, _loc, _start, acc) do
    {[{:error, "Unterminated comment", {line, ls, pos}} | acc], pos, line, ls}
  end

  # === CDATA (acc) ===

  defp parse_cdata_acc(<<"]]>", _::binary>>, xml, pos, line, ls, loc, start, acc) do
    content = binary_part(xml, start, pos - start)
    {[{:text, content, loc} | acc], pos + 3, line, ls}
  end

  defp parse_cdata_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, acc) do
    parse_cdata_acc(rest, xml, pos + 1, line + 1, pos + 1, loc, start, acc)
  end

  defp parse_cdata_acc(<<_, rest::binary>>, xml, pos, line, ls, loc, start, acc) do
    parse_cdata_acc(rest, xml, pos + 1, line, ls, loc, start, acc)
  end

  defp parse_cdata_acc(<<>>, _xml, pos, line, ls, _loc, _start, acc) do
    {[{:error, "Unterminated CDATA", {line, ls, pos}} | acc], pos, line, ls}
  end

  # === PI (acc) ===

  defp parse_pi_start_acc(<<c, _::binary>> = rest, xml, pos, line, ls, loc, acc) when is_name_start(c) do
    parse_name_acc(rest, xml, pos, line, ls, :pi_name, {loc, acc})
  end

  defp parse_pi_start_acc(_, _xml, pos, line, ls, _loc, acc) do
    {[{:error, "Expected PI target name", {line, ls, pos}} | acc], pos, line, ls}
  end

  defp parse_pi_content_acc(<<"?>", _::binary>>, xml, pos, line, ls, name, loc, start, acc) do
    content = binary_part(xml, start, pos - start) |> String.trim()
    {[{:proc_inst, name, content, loc} | acc], pos + 2, line, ls}
  end

  defp parse_pi_content_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, start, acc) do
    parse_pi_content_acc(rest, xml, pos + 1, line + 1, pos + 1, name, loc, start, acc)
  end

  defp parse_pi_content_acc(<<_, rest::binary>>, xml, pos, line, ls, name, loc, start, acc) do
    parse_pi_content_acc(rest, xml, pos + 1, line, ls, name, loc, start, acc)
  end

  defp parse_pi_content_acc(<<>>, _xml, pos, line, ls, _name, _loc, _start, acc) do
    {[{:error, "Unterminated PI", {line, ls, pos}} | acc], pos, line, ls}
  end

  # === Text (acc) ===

  defp parse_text_acc(<<"<", _::binary>>, xml, pos, line, ls, loc, start, acc) do
    content = binary_part(xml, start, pos - start)
    {[{:text, content, loc} | acc], pos, line, ls}
  end

  defp parse_text_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, acc) do
    parse_text_acc(rest, xml, pos + 1, line + 1, pos + 1, loc, start, acc)
  end

  defp parse_text_acc(<<_, rest::binary>>, xml, pos, line, ls, loc, start, acc) do
    parse_text_acc(rest, xml, pos + 1, line, ls, loc, start, acc)
  end

  defp parse_text_acc(<<>>, xml, pos, line, ls, loc, start, acc) do
    content = binary_part(xml, start, pos - start)
    {[{:text, content, loc} | acc], pos, line, ls}
  end

  # === Name parsing (acc) ===

  defp parse_name_acc(rest, xml, pos, line, ls, context, extra) do
    scan_name_acc(rest, xml, pos, line, ls, context, extra, pos)
  end

  defp scan_name_acc(<<c, rest::binary>>, xml, pos, line, ls, context, extra, start) when is_name_char(c) do
    scan_name_acc(rest, xml, pos + 1, line, ls, context, extra, start)
  end

  defp scan_name_acc(rest, xml, pos, line, ls, context, extra, start) do
    name = binary_part(xml, start, pos - start)
    continue_acc(context, rest, xml, pos, line, ls, name, extra)
  end

  # === Continuations (acc) ===

  defp continue_acc(:open_tag, rest, xml, pos, line, ls, name, {loc, acc}) do
    finish_open_tag_acc(rest, xml, pos, line, ls, name, [], loc, acc)
  end

  defp continue_acc(:close_tag, rest, xml, pos, line, ls, name, {loc, acc}) do
    finish_close_tag_acc(rest, xml, pos, line, ls, name, loc, acc)
  end

  defp continue_acc(:attr_name, rest, xml, pos, line, ls, name, {tag, attrs, loc, acc}) do
    parse_attr_eq_acc(rest, xml, pos, line, ls, tag, name, attrs, loc, acc)
  end

  defp continue_acc(:prolog_attr, rest, xml, pos, line, ls, name, {loc, attrs, acc}) do
    parse_prolog_attr_eq_acc(rest, xml, pos, line, ls, name, loc, attrs, acc)
  end

  defp continue_acc(:pi_name, rest, xml, pos, line, ls, name, {loc, acc}) do
    skip_ws_then_pi_acc(rest, xml, pos, line, ls, name, loc, acc)
  end

  # === Attribute parsing (acc) ===

  defp parse_attr_eq_acc(<<"=", rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, acc) do
    parse_attr_value_start_acc(rest, xml, pos + 1, line, ls, tag, name, attrs, loc, acc)
  end

  defp parse_attr_eq_acc(<<c, rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, acc) when c in [?\s, ?\t, ?\r] do
    parse_attr_eq_acc(rest, xml, pos + 1, line, ls, tag, name, attrs, loc, acc)
  end

  defp parse_attr_eq_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, tag, name, attrs, loc, acc) do
    parse_attr_eq_acc(rest, xml, pos + 1, line + 1, pos + 1, tag, name, attrs, loc, acc)
  end

  defp parse_attr_eq_acc(_, _xml, pos, line, ls, _tag, _name, _attrs, _loc, acc) do
    {[{:error, "Expected '='", {line, ls, pos}} | acc], pos, line, ls}
  end

  defp parse_attr_value_start_acc(<<c, rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, acc) when c in [?\s, ?\t, ?\r] do
    parse_attr_value_start_acc(rest, xml, pos + 1, line, ls, tag, name, attrs, loc, acc)
  end

  defp parse_attr_value_start_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, tag, name, attrs, loc, acc) do
    parse_attr_value_start_acc(rest, xml, pos + 1, line + 1, pos + 1, tag, name, attrs, loc, acc)
  end

  defp parse_attr_value_start_acc(<<"\"", rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, acc) do
    parse_attr_value_acc(rest, xml, pos + 1, line, ls, ?", tag, name, attrs, loc, pos + 1, acc)
  end

  defp parse_attr_value_start_acc(<<"'", rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, acc) do
    parse_attr_value_acc(rest, xml, pos + 1, line, ls, ?', tag, name, attrs, loc, pos + 1, acc)
  end

  defp parse_attr_value_start_acc(_, _xml, pos, line, ls, _tag, _name, _attrs, _loc, acc) do
    {[{:error, "Expected quoted value", {line, ls, pos}} | acc], pos, line, ls}
  end

  defp parse_attr_value_acc(<<"\"", rest::binary>>, xml, pos, line, ls, ?", tag, name, attrs, loc, start, acc) do
    value = binary_part(xml, start, pos - start)
    finish_open_tag_acc(rest, xml, pos + 1, line, ls, tag, [{name, value} | attrs], loc, acc)
  end

  defp parse_attr_value_acc(<<"'", rest::binary>>, xml, pos, line, ls, ?', tag, name, attrs, loc, start, acc) do
    value = binary_part(xml, start, pos - start)
    finish_open_tag_acc(rest, xml, pos + 1, line, ls, tag, [{name, value} | attrs], loc, acc)
  end

  defp parse_attr_value_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, q, tag, name, attrs, loc, start, acc) do
    parse_attr_value_acc(rest, xml, pos + 1, line + 1, pos + 1, q, tag, name, attrs, loc, start, acc)
  end

  defp parse_attr_value_acc(<<_, rest::binary>>, xml, pos, line, ls, q, tag, name, attrs, loc, start, acc) do
    parse_attr_value_acc(rest, xml, pos + 1, line, ls, q, tag, name, attrs, loc, start, acc)
  end

  defp parse_attr_value_acc(<<>>, _xml, pos, line, ls, _q, _tag, _name, _attrs, _loc, _start, acc) do
    {[{:error, "Unterminated attribute value", {line, ls, pos}} | acc], pos, line, ls}
  end

  # === Prolog attribute (acc) ===

  defp parse_prolog_attr_eq_acc(<<"=", rest::binary>>, xml, pos, line, ls, name, loc, attrs, acc) do
    parse_prolog_attr_value_start_acc(rest, xml, pos + 1, line, ls, name, loc, attrs, acc)
  end

  defp parse_prolog_attr_eq_acc(<<c, rest::binary>>, xml, pos, line, ls, name, loc, attrs, acc) when c in [?\s, ?\t, ?\r] do
    parse_prolog_attr_eq_acc(rest, xml, pos + 1, line, ls, name, loc, attrs, acc)
  end

  defp parse_prolog_attr_eq_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, attrs, acc) do
    parse_prolog_attr_eq_acc(rest, xml, pos + 1, line + 1, pos + 1, name, loc, attrs, acc)
  end

  defp parse_prolog_attr_eq_acc(_, _xml, pos, line, ls, _name, _loc, _attrs, acc) do
    {[{:error, "Expected '='", {line, ls, pos}} | acc], pos, line, ls}
  end

  defp parse_prolog_attr_value_start_acc(<<c, rest::binary>>, xml, pos, line, ls, name, loc, attrs, acc) when c in [?\s, ?\t, ?\r] do
    parse_prolog_attr_value_start_acc(rest, xml, pos + 1, line, ls, name, loc, attrs, acc)
  end

  defp parse_prolog_attr_value_start_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, attrs, acc) do
    parse_prolog_attr_value_start_acc(rest, xml, pos + 1, line + 1, pos + 1, name, loc, attrs, acc)
  end

  defp parse_prolog_attr_value_start_acc(<<"\"", rest::binary>>, xml, pos, line, ls, name, loc, attrs, acc) do
    parse_prolog_attr_value_acc(rest, xml, pos + 1, line, ls, ?", name, loc, attrs, pos + 1, acc)
  end

  defp parse_prolog_attr_value_start_acc(<<"'", rest::binary>>, xml, pos, line, ls, name, loc, attrs, acc) do
    parse_prolog_attr_value_acc(rest, xml, pos + 1, line, ls, ?', name, loc, attrs, pos + 1, acc)
  end

  defp parse_prolog_attr_value_start_acc(_, _xml, pos, line, ls, _name, _loc, _attrs, acc) do
    {[{:error, "Expected quoted value", {line, ls, pos}} | acc], pos, line, ls}
  end

  defp parse_prolog_attr_value_acc(<<"\"", rest::binary>>, xml, pos, line, ls, ?", name, loc, attrs, start, acc) do
    value = binary_part(xml, start, pos - start)
    parse_prolog_attrs_acc(rest, xml, pos + 1, line, ls, loc, [{name, value} | attrs], acc)
  end

  defp parse_prolog_attr_value_acc(<<"'", rest::binary>>, xml, pos, line, ls, ?', name, loc, attrs, start, acc) do
    value = binary_part(xml, start, pos - start)
    parse_prolog_attrs_acc(rest, xml, pos + 1, line, ls, loc, [{name, value} | attrs], acc)
  end

  defp parse_prolog_attr_value_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, q, name, loc, attrs, start, acc) do
    parse_prolog_attr_value_acc(rest, xml, pos + 1, line + 1, pos + 1, q, name, loc, attrs, start, acc)
  end

  defp parse_prolog_attr_value_acc(<<_, rest::binary>>, xml, pos, line, ls, q, name, loc, attrs, start, acc) do
    parse_prolog_attr_value_acc(rest, xml, pos + 1, line, ls, q, name, loc, attrs, start, acc)
  end

  defp parse_prolog_attr_value_acc(<<>>, _xml, pos, line, ls, _q, _name, _loc, _attrs, _start, acc) do
    {[{:error, "Unterminated attribute value", {line, ls, pos}} | acc], pos, line, ls}
  end

  # === Helpers (acc) ===

  defp skip_ws_then_pi_acc(<<c, rest::binary>>, xml, pos, line, ls, name, loc, acc) when c in [?\s, ?\t, ?\r] do
    skip_ws_then_pi_acc(rest, xml, pos + 1, line, ls, name, loc, acc)
  end

  defp skip_ws_then_pi_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, acc) do
    skip_ws_then_pi_acc(rest, xml, pos + 1, line + 1, pos + 1, name, loc, acc)
  end

  defp skip_ws_then_pi_acc(rest, xml, pos, line, ls, name, loc, acc) do
    parse_pi_content_acc(rest, xml, pos, line, ls, name, loc, pos, acc)
  end
end
