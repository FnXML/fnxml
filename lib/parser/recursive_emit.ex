defmodule FnXML.Parser.RecursiveEmit do
  @moduledoc """
  Recursive descent parser with emit/error callbacks.

  Uses position tracking instead of sub-binaries for "rest".
  Only creates sub-binaries when extracting actual content (names, values, text).
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

  @doc """
  Parse XML string into a stream of events.
  """
  def parse(xml) when is_binary(xml) do
    Stream.resource(
      fn -> {xml, byte_size(xml), 0, 1, 0} end,
      &next_token/1,
      fn _ -> :ok end
    )
  end

  # State: {xml, len, pos, line, line_start}
  # xml and len are constant, pos advances

  defp next_token({_xml, len, pos, _line, _ls}) when pos >= len do
    {:halt, nil}
  end

  defp next_token({xml, len, pos, line, ls}) do
    # Use process dictionary to accumulate tokens
    Process.put(:tokens, [])

    emit = fn token ->
      Process.put(:tokens, [token | Process.get(:tokens)])
    end

    error = fn msg, loc ->
      Process.put(:tokens, [{:error, msg, loc} | Process.get(:tokens)])
    end

    {pos, line, ls} = do_parse_one(xml, len, pos, line, ls, emit, error)

    tokens = Process.get(:tokens) |> Enum.reverse()
    Process.delete(:tokens)

    {tokens, {xml, len, pos, line, ls}}
  end

  # === Main dispatch - parse one event ===

  defp do_parse_one(_xml, len, pos, line, ls, _emit, _error) when pos >= len do
    {pos, line, ls}
  end

  defp do_parse_one(xml, len, pos, line, ls, emit, error) do
    case byte_at(xml, pos) do
      ?< -> parse_element(xml, len, pos, line, ls, emit, error)
      c when c in @ws -> skip_ws_and_continue(xml, len, pos, line, ls, emit, error)
      _ -> parse_text(xml, len, pos, line, ls, emit, error)
    end
  end

  defp skip_ws_and_continue(xml, len, pos, line, ls, emit, error) do
    {pos, line, ls} = skip_ws(xml, len, pos, line, ls)
    if pos >= len do
      {pos, line, ls}
    else
      do_parse_one(xml, len, pos, line, ls, emit, error)
    end
  end

  # === Element dispatch ===

  defp parse_element(xml, len, pos, line, ls, emit, error) do
    cond do
      match_at?(xml, len, pos, "<?xml") ->
        parse_prolog(xml, len, pos + 5, line, ls, {line, ls, pos + 1}, emit, error)

      match_at?(xml, len, pos, "<!--") ->
        parse_comment(xml, len, pos + 4, line, ls, {line, ls, pos + 1}, emit, error)

      match_at?(xml, len, pos, "<![CDATA[") ->
        parse_cdata(xml, len, pos + 9, line, ls, {line, ls, pos + 1}, emit, error)

      match_at?(xml, len, pos, "</") ->
        parse_close_tag(xml, len, pos + 2, line, ls, {line, ls, pos + 1}, emit, error)

      match_at?(xml, len, pos, "<?") ->
        parse_pi(xml, len, pos + 2, line, ls, {line, ls, pos + 1}, emit, error)

      pos + 1 < len and is_name_start(byte_at(xml, pos + 1)) ->
        parse_open_tag(xml, len, pos + 1, line, ls, {line, ls, pos + 1}, emit, error)

      true ->
        error.("Invalid element", {line, ls, pos})
        {len, line, ls}  # halt
    end
  end

  # === Prolog ===

  defp parse_prolog(xml, len, pos, line, ls, loc, emit, error) do
    {pos, line, ls} = skip_ws(xml, len, pos, line, ls)
    {attrs, pos, line, ls} = parse_attributes(xml, len, pos, line, ls, [])
    {pos, line, ls} = skip_ws(xml, len, pos, line, ls)

    if match_at?(xml, len, pos, "?>") do
      emit.({:prolog, "xml", attrs, loc})
      {pos, line, ls} = skip_ws(xml, len, pos + 2, line, ls)
      {pos, line, ls}
    else
      error.("Expected '?>'", {line, ls, pos})
      {len, line, ls}
    end
  end

  # === Open Tag ===

  defp parse_open_tag(xml, len, pos, line, ls, loc, emit, error) do
    {name, pos, line, ls} = parse_name(xml, len, pos, line, ls)
    {pos, line, ls} = skip_ws(xml, len, pos, line, ls)

    cond do
      match_at?(xml, len, pos, "/>") ->
        emit.({:open, name, [], loc})
        emit.({:close, name})
        {pos + 2, line, ls}

      match_at?(xml, len, pos, ">") ->
        emit.({:open, name, [], loc})
        {pos + 1, line, ls}

      pos < len and is_name_start(byte_at(xml, pos)) ->
        {attrs, pos, line, ls} = parse_attributes(xml, len, pos, line, ls, [])
        {pos, line, ls} = skip_ws(xml, len, pos, line, ls)
        finish_open_tag(xml, len, pos, line, ls, name, attrs, loc, emit, error)

      true ->
        error.("Expected '>', '/>', or attribute", {line, ls, pos})
        {len, line, ls}
    end
  end

  defp finish_open_tag(xml, len, pos, line, ls, name, attrs, loc, emit, error) do
    cond do
      match_at?(xml, len, pos, "/>") ->
        emit.({:open, name, attrs, loc})
        emit.({:close, name})
        {pos + 2, line, ls}

      match_at?(xml, len, pos, ">") ->
        emit.({:open, name, attrs, loc})
        {pos + 1, line, ls}

      true ->
        error.("Expected '>' or '/>'", {line, ls, pos})
        {len, line, ls}
    end
  end

  # === Close Tag ===

  defp parse_close_tag(xml, len, pos, line, ls, loc, emit, error) do
    {name, pos, line, ls} = parse_name(xml, len, pos, line, ls)
    {pos, line, ls} = skip_ws(xml, len, pos, line, ls)

    if match_at?(xml, len, pos, ">") do
      emit.({:close, name, loc})
      {pos + 1, line, ls}
    else
      error.("Expected '>'", {line, ls, pos})
      {len, line, ls}
    end
  end

  # === Comment ===

  defp parse_comment(xml, len, pos, line, ls, loc, emit, error) do
    case scan_until(xml, len, pos, line, ls, "--") do
      {:ok, content, pos, line, ls} ->
        if match_at?(xml, len, pos, ">") do
          emit.({:comment, content, loc})
          {pos + 1, line, ls}
        else
          error.("Expected '>'", {line, ls, pos})
          {len, line, ls}
        end

      {:error, pos, line, ls} ->
        error.("Unterminated comment", {line, ls, pos})
        {len, line, ls}
    end
  end

  # === CDATA ===

  defp parse_cdata(xml, len, pos, line, ls, loc, emit, error) do
    case scan_until(xml, len, pos, line, ls, "]]") do
      {:ok, content, pos, line, ls} ->
        if match_at?(xml, len, pos, ">") do
          emit.({:text, content, loc})
          {pos + 1, line, ls}
        else
          error.("Expected '>'", {line, ls, pos})
          {len, line, ls}
        end

      {:error, pos, line, ls} ->
        error.("Unterminated CDATA", {line, ls, pos})
        {len, line, ls}
    end
  end

  # === Processing Instruction ===

  defp parse_pi(xml, len, pos, line, ls, loc, emit, error) do
    {name, pos, line, ls} = parse_name(xml, len, pos, line, ls)
    {pos, line, ls} = skip_ws(xml, len, pos, line, ls)

    case scan_until(xml, len, pos, line, ls, "?") do
      {:ok, content, pos, line, ls} ->
        if match_at?(xml, len, pos, ">") do
          emit.({:proc_inst, name, String.trim(content), loc})
          {pos + 1, line, ls}
        else
          error.("Expected '>'", {line, ls, pos})
          {len, line, ls}
        end

      {:error, pos, line, ls} ->
        error.("Unterminated PI", {line, ls, pos})
        {len, line, ls}
    end
  end

  # === Text ===

  defp parse_text(xml, len, pos, line, ls, emit, _error) do
    loc = {line, ls, pos}
    {content, pos, line, ls} = scan_text(xml, len, pos, line, ls)
    emit.({:text, content, loc})
    {pos, line, ls}
  end

  # === Helpers ===

  defp byte_at(xml, pos), do: :binary.at(xml, pos)

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
    c = byte_at(xml, pos)
    if is_name_char(c), do: scan_name_chars(xml, len, pos + 1), else: pos
  end
  defp scan_name_chars(_xml, _len, pos), do: pos

  defp parse_attributes(xml, len, pos, line, ls, acc) do
    if pos < len and is_name_start(byte_at(xml, pos)) do
      {name, pos, line, ls} = parse_name(xml, len, pos, line, ls)
      {pos, line, ls} = skip_ws(xml, len, pos, line, ls)

      if pos < len and byte_at(xml, pos) == ?= do
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
      quote_char = byte_at(xml, pos)
      if quote_char == ?" or quote_char == ?' do
        scan_quoted(xml, len, pos + 1, line, ls, quote_char, pos + 1)
      else
        {"", pos, line, ls}
      end
    end
  end

  defp scan_quoted(xml, len, pos, line, ls, quote_char, start) do
    cond do
      pos >= len ->
        {binary_part(xml, start, pos - start), pos, line, ls}

      byte_at(xml, pos) == quote_char ->
        {binary_part(xml, start, pos - start), pos + 1, line, ls}

      byte_at(xml, pos) == ?\n ->
        scan_quoted(xml, len, pos + 1, line + 1, pos + 1, quote_char, start)

      true ->
        scan_quoted(xml, len, pos + 1, line, ls, quote_char, start)
    end
  end

  defp skip_ws(xml, len, pos, line, ls) do
    cond do
      pos >= len -> {pos, line, ls}
      byte_at(xml, pos) == ?\n -> skip_ws(xml, len, pos + 1, line + 1, pos + 1)
      byte_at(xml, pos) in @ws -> skip_ws(xml, len, pos + 1, line, ls)
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
        content = binary_part(xml, start, pos - start)
        {:ok, content, pos + dlen, line, ls}

      byte_at(xml, pos) == ?\n ->
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

      byte_at(xml, pos) == ?< ->
        {binary_part(xml, start, pos - start), pos, line, ls}

      byte_at(xml, pos) == ?\n ->
        do_scan_text(xml, len, pos + 1, line + 1, pos + 1, start)

      true ->
        do_scan_text(xml, len, pos + 1, line, ls, start)
    end
  end
end
