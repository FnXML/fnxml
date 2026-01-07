defmodule FnXML.Parser.RecursivePos do
  @moduledoc """
  Recursive descent parser tracking position instead of sub-binaries.

  No "rest" sub-binaries - just advances position integer.
  Only creates sub-binaries for actual content (names, values, text).
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
      fn -> {xml, byte_size(xml), 0, 1, 0} end,
      &next_token/1,
      fn _ -> :ok end
    )
  end

  # State: {xml, len, pos, line, line_start}

  defp next_token({_xml, len, pos, _line, _ls}) when pos >= len do
    {:halt, nil}
  end

  defp next_token({xml, len, pos, line, ls}) do
    {tokens, pos, line, ls} = do_parse_one(xml, len, pos, line, ls, [])
    {Enum.reverse(tokens), {xml, len, pos, line, ls}}
  end

  # === Main dispatch ===

  defp do_parse_one(_xml, len, pos, line, ls, acc) when pos >= len do
    {acc, pos, line, ls}
  end

  defp do_parse_one(xml, len, pos, line, ls, acc) do
    c = :binary.at(xml, pos)
    cond do
      c == ?< -> parse_element(xml, len, pos, line, ls, acc)
      c in @ws ->
        {pos, line, ls} = skip_ws(xml, len, pos, line, ls)
        do_parse_one(xml, len, pos, line, ls, acc)
      true -> parse_text(xml, len, pos, line, ls, acc)
    end
  end

  # === Element dispatch ===

  defp parse_element(xml, len, pos, line, ls, acc) do
    cond do
      match_at?(xml, len, pos, "<?xml") ->
        parse_prolog(xml, len, pos + 5, line, ls, {line, ls, pos + 1}, acc)

      match_at?(xml, len, pos, "<!--") ->
        parse_comment(xml, len, pos + 4, line, ls, {line, ls, pos + 1}, acc)

      match_at?(xml, len, pos, "<![CDATA[") ->
        parse_cdata(xml, len, pos + 9, line, ls, {line, ls, pos + 1}, acc)

      match_at?(xml, len, pos, "</") ->
        parse_close_tag(xml, len, pos + 2, line, ls, {line, ls, pos + 1}, acc)

      match_at?(xml, len, pos, "<?") ->
        parse_pi(xml, len, pos + 2, line, ls, {line, ls, pos + 1}, acc)

      pos + 1 < len and is_name_start(:binary.at(xml, pos + 1)) ->
        parse_open_tag(xml, len, pos + 1, line, ls, {line, ls, pos + 1}, acc)

      true ->
        {[{:error, "Invalid element", {line, ls, pos}} | acc], len, line, ls}
    end
  end

  # === Prolog ===

  defp parse_prolog(xml, len, pos, line, ls, loc, acc) do
    {pos, line, ls} = skip_ws(xml, len, pos, line, ls)
    {attrs, pos, line, ls} = parse_attributes(xml, len, pos, line, ls, [])
    {pos, line, ls} = skip_ws(xml, len, pos, line, ls)

    if match_at?(xml, len, pos, "?>") do
      {pos, line, ls} = skip_ws(xml, len, pos + 2, line, ls)
      {[{:prolog, "xml", attrs, loc} | acc], pos, line, ls}
    else
      {[{:error, "Expected '?>'", {line, ls, pos}} | acc], len, line, ls}
    end
  end

  # === Open Tag ===

  defp parse_open_tag(xml, len, pos, line, ls, loc, acc) do
    {name, pos, line, ls} = parse_name(xml, len, pos, line, ls)
    {pos, line, ls} = skip_ws(xml, len, pos, line, ls)

    cond do
      match_at?(xml, len, pos, "/>") ->
        acc = [{:close, name} | [{:open, name, [], loc} | acc]]
        {acc, pos + 2, line, ls}

      match_at?(xml, len, pos, ">") ->
        {[{:open, name, [], loc} | acc], pos + 1, line, ls}

      pos < len and is_name_start(:binary.at(xml, pos)) ->
        {attrs, pos, line, ls} = parse_attributes(xml, len, pos, line, ls, [])
        {pos, line, ls} = skip_ws(xml, len, pos, line, ls)
        finish_open_tag(xml, len, pos, line, ls, name, attrs, loc, acc)

      true ->
        {[{:error, "Expected '>' or '/>'", {line, ls, pos}} | acc], len, line, ls}
    end
  end

  defp finish_open_tag(xml, len, pos, line, ls, name, attrs, loc, acc) do
    cond do
      match_at?(xml, len, pos, "/>") ->
        acc = [{:close, name} | [{:open, name, attrs, loc} | acc]]
        {acc, pos + 2, line, ls}

      match_at?(xml, len, pos, ">") ->
        {[{:open, name, attrs, loc} | acc], pos + 1, line, ls}

      true ->
        {[{:error, "Expected '>' or '/>'", {line, ls, pos}} | acc], len, line, ls}
    end
  end

  # === Close Tag ===

  defp parse_close_tag(xml, len, pos, line, ls, loc, acc) do
    {name, pos, line, ls} = parse_name(xml, len, pos, line, ls)
    {pos, line, ls} = skip_ws(xml, len, pos, line, ls)

    if match_at?(xml, len, pos, ">") do
      {[{:close, name, loc} | acc], pos + 1, line, ls}
    else
      {[{:error, "Expected '>'", {line, ls, pos}} | acc], len, line, ls}
    end
  end

  # === Comment ===

  defp parse_comment(xml, len, pos, line, ls, loc, acc) do
    case scan_until(xml, len, pos, line, ls, "--") do
      {:ok, content, pos, line, ls} ->
        if match_at?(xml, len, pos, ">") do
          {[{:comment, content, loc} | acc], pos + 1, line, ls}
        else
          {[{:error, "Expected '>'", {line, ls, pos}} | acc], len, line, ls}
        end

      {:error, pos, line, ls} ->
        {[{:error, "Unterminated comment", {line, ls, pos}} | acc], len, line, ls}
    end
  end

  # === CDATA ===

  defp parse_cdata(xml, len, pos, line, ls, loc, acc) do
    case scan_until(xml, len, pos, line, ls, "]]") do
      {:ok, content, pos, line, ls} ->
        if match_at?(xml, len, pos, ">") do
          {[{:text, content, loc} | acc], pos + 1, line, ls}
        else
          {[{:error, "Expected '>'", {line, ls, pos}} | acc], len, line, ls}
        end

      {:error, pos, line, ls} ->
        {[{:error, "Unterminated CDATA", {line, ls, pos}} | acc], len, line, ls}
    end
  end

  # === Processing Instruction ===

  defp parse_pi(xml, len, pos, line, ls, loc, acc) do
    {name, pos, line, ls} = parse_name(xml, len, pos, line, ls)
    {pos, line, ls} = skip_ws(xml, len, pos, line, ls)

    case scan_until(xml, len, pos, line, ls, "?") do
      {:ok, content, pos, line, ls} ->
        if match_at?(xml, len, pos, ">") do
          {[{:proc_inst, name, String.trim(content), loc} | acc], pos + 1, line, ls}
        else
          {[{:error, "Expected '>'", {line, ls, pos}} | acc], len, line, ls}
        end

      {:error, pos, line, ls} ->
        {[{:error, "Unterminated PI", {line, ls, pos}} | acc], len, line, ls}
    end
  end

  # === Text ===

  defp parse_text(xml, len, pos, line, ls, acc) do
    loc = {line, ls, pos}
    {content, pos, line, ls} = scan_text(xml, len, pos, line, ls)
    {[{:text, content, loc} | acc], pos, line, ls}
  end

  # === Helpers ===

  defp match_at?(xml, len, pos, pattern) do
    plen = byte_size(pattern)
    pos + plen <= len and binary_part(xml, pos, plen) == pattern
  end

  defp parse_name(xml, len, pos, line, ls) do
    start = pos
    pos = scan_name_chars(xml, len, pos)
    name = binary_part(xml, start, pos - start)
    {name, pos, line, ls}
  end

  defp scan_name_chars(xml, len, pos) when pos < len do
    c = :binary.at(xml, pos)
    if is_name_char(c), do: scan_name_chars(xml, len, pos + 1), else: pos
  end
  defp scan_name_chars(_xml, _len, pos), do: pos

  defp parse_attributes(xml, len, pos, line, ls, acc) do
    if pos < len and is_name_start(:binary.at(xml, pos)) do
      {name, pos, line, ls} = parse_name(xml, len, pos, line, ls)
      {pos, line, ls} = skip_ws(xml, len, pos, line, ls)

      if pos < len and :binary.at(xml, pos) == ?= do
        {pos, line, ls} = skip_ws(xml, len, pos + 1, line, ls)
        {value, pos, line, ls} = parse_quoted(xml, len, pos, line, ls)
        {pos, line, ls} = skip_ws(xml, len, pos, line, ls)
        parse_attributes(xml, len, pos, line, ls, [{name, value} | acc])
      else
        {Enum.reverse(acc), pos, line, ls}
      end
    else
      {Enum.reverse(acc), pos, line, ls}
    end
  end

  defp parse_quoted(xml, len, pos, line, ls) do
    if pos >= len do
      {"", pos, line, ls}
    else
      q = :binary.at(xml, pos)
      if q == ?" or q == ?' do
        scan_quoted(xml, len, pos + 1, line, ls, q, pos + 1)
      else
        {"", pos, line, ls}
      end
    end
  end

  defp scan_quoted(xml, len, pos, line, ls, q, start) do
    cond do
      pos >= len ->
        {binary_part(xml, start, pos - start), pos, line, ls}
      :binary.at(xml, pos) == q ->
        {binary_part(xml, start, pos - start), pos + 1, line, ls}
      :binary.at(xml, pos) == ?\n ->
        scan_quoted(xml, len, pos + 1, line + 1, pos + 1, q, start)
      true ->
        scan_quoted(xml, len, pos + 1, line, ls, q, start)
    end
  end

  defp skip_ws(xml, len, pos, line, ls) do
    cond do
      pos >= len -> {pos, line, ls}
      :binary.at(xml, pos) == ?\n -> skip_ws(xml, len, pos + 1, line + 1, pos + 1)
      :binary.at(xml, pos) in @ws -> skip_ws(xml, len, pos + 1, line, ls)
      true -> {pos, line, ls}
    end
  end

  defp scan_until(xml, len, pos, line, ls, delim) do
    dlen = byte_size(delim)
    do_scan_until(xml, len, pos, line, ls, delim, dlen, pos)
  end

  defp do_scan_until(xml, len, pos, line, ls, delim, dlen, start) do
    cond do
      pos + dlen > len ->
        {:error, pos, line, ls}
      binary_part(xml, pos, dlen) == delim ->
        {:ok, binary_part(xml, start, pos - start), pos + dlen, line, ls}
      :binary.at(xml, pos) == ?\n ->
        do_scan_until(xml, len, pos + 1, line + 1, pos + 1, delim, dlen, start)
      true ->
        do_scan_until(xml, len, pos + 1, line, ls, delim, dlen, start)
    end
  end

  defp scan_text(xml, len, pos, line, ls) do
    do_scan_text(xml, len, pos, line, ls, pos)
  end

  defp do_scan_text(xml, len, pos, line, ls, start) do
    cond do
      pos >= len ->
        {binary_part(xml, start, pos - start), pos, line, ls}
      :binary.at(xml, pos) == ?< ->
        {binary_part(xml, start, pos - start), pos, line, ls}
      :binary.at(xml, pos) == ?\n ->
        do_scan_text(xml, len, pos + 1, line + 1, pos + 1, start)
      true ->
        do_scan_text(xml, len, pos + 1, line, ls, start)
    end
  end
end
