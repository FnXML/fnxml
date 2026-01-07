defmodule FnXML.Parser.RecursiveSend do
  @moduledoc """
  Recursive descent parser that sends events to a process.

  Uses true tail recursion - no intermediate returns.
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
  Parse XML, sending events to the given pid.
  Sends :done when complete.
  """
  def parse(xml, pid) when is_binary(xml) and is_pid(pid) do
    do_parse(xml, 0, 1, 0, pid)
    send(pid, :done)
    :ok
  end

  @doc """
  Parse XML as a stream (wraps message-passing in Stream).
  """
  def stream(xml) when is_binary(xml) do
    Stream.resource(
      fn ->
        parent = self()
        spawn_link(fn -> parse(xml, parent) end)
      end,
      fn pid ->
        receive do
          :done -> {:halt, pid}
          token -> {[token], pid}
        end
      end,
      fn _pid -> :ok end
    )
  end

  # === Main Parse Loop ===

  defp do_parse(<<>>, _pos, _line, _ls, _pid), do: :ok

  defp do_parse(<<"<?xml", _::binary>> = xml, pos, line, ls, pid) do
    parse_prolog(xml, pos, line, ls, pid)
  end

  defp do_parse(<<"<", _::binary>> = xml, pos, line, ls, pid) do
    parse_element(xml, pos, line, ls, pid)
  end

  defp do_parse(xml, pos, line, ls, pid) do
    parse_text(xml, pos, line, ls, pid)
  end

  # === Prolog ===

  defp parse_prolog(<<"<?xml", xml::binary>>, pos, line, ls, pid) do
    loc = {line, ls, pos + 1}
    {xml, pos, line, ls} = skip_ws(xml, pos + 5, line, ls)
    {attrs, xml, pos, line, ls} = parse_attributes(xml, pos, line, ls, [])
    {xml, pos, line, ls} = skip_ws(xml, pos, line, ls)

    case xml do
      <<"?>", rest::binary>> ->
        send(pid, {:prolog, "xml", attrs, loc})
        {rest, pos, line, ls} = skip_ws(rest, pos + 2, line, ls)
        do_parse(rest, pos, line, ls, pid)
      _ ->
        send(pid, {:error, "Expected '?>'", loc})
    end
  end

  # === Elements ===

  defp parse_element(<<"<!--", xml::binary>>, pos, line, ls, pid) do
    parse_comment(xml, pos + 4, line, ls, {line, ls, pos + 1}, pid)
  end

  defp parse_element(<<"<![CDATA[", xml::binary>>, pos, line, ls, pid) do
    parse_cdata(xml, pos + 9, line, ls, {line, ls, pos + 1}, pid)
  end

  defp parse_element(<<"</", xml::binary>>, pos, line, ls, pid) do
    parse_close_tag(xml, pos + 2, line, ls, {line, ls, pos + 1}, pid)
  end

  defp parse_element(<<"<?", xml::binary>>, pos, line, ls, pid) do
    parse_pi(xml, pos + 2, line, ls, {line, ls, pos + 1}, pid)
  end

  defp parse_element(<<"<", c, _::binary>> = xml, pos, line, ls, pid) when is_name_start(c) do
    <<"<", rest::binary>> = xml
    parse_open_tag(rest, pos + 1, line, ls, {line, ls, pos + 1}, pid)
  end

  defp parse_element(<<"<", _::binary>>, pos, line, ls, pid) do
    send(pid, {:error, "Invalid element", {line, ls, pos}})
  end

  # === Open Tag ===

  defp parse_open_tag(xml, pos, line, ls, loc, pid) do
    {name, xml, pos, line, ls} = parse_name(xml, pos, line, ls)
    {xml, pos, line, ls} = skip_ws(xml, pos, line, ls)

    case xml do
      <<"/>", rest::binary>> ->
        send(pid, {:open, name, [], loc})
        send(pid, {:close, name})
        do_parse(rest, pos + 2, line, ls, pid)

      <<">", rest::binary>> ->
        send(pid, {:open, name, [], loc})
        do_parse(rest, pos + 1, line, ls, pid)

      <<c, _::binary>> when is_name_start(c) ->
        {attrs, xml, pos, line, ls} = parse_attributes(xml, pos, line, ls, [])
        {xml, pos, line, ls} = skip_ws(xml, pos, line, ls)
        finish_open_tag_attrs(xml, pos, line, ls, name, attrs, loc, pid)

      _ ->
        send(pid, {:error, "Expected '>' or '/>'", {line, ls, pos}})
    end
  end

  defp finish_open_tag_attrs(<<"/>", rest::binary>>, pos, line, ls, name, attrs, loc, pid) do
    send(pid, {:open, name, attrs, loc})
    send(pid, {:close, name})
    do_parse(rest, pos + 2, line, ls, pid)
  end

  defp finish_open_tag_attrs(<<">", rest::binary>>, pos, line, ls, name, attrs, loc, pid) do
    send(pid, {:open, name, attrs, loc})
    do_parse(rest, pos + 1, line, ls, pid)
  end

  defp finish_open_tag_attrs(_, pos, line, ls, _, _, _, pid) do
    send(pid, {:error, "Expected '>' or '/>'", {line, ls, pos}})
  end

  # === Close Tag ===

  defp parse_close_tag(xml, pos, line, ls, loc, pid) do
    {name, xml, pos, line, ls} = parse_name(xml, pos, line, ls)
    {xml, pos, line, ls} = skip_ws(xml, pos, line, ls)

    case xml do
      <<">", rest::binary>> ->
        send(pid, {:close, name, loc})
        do_parse(rest, pos + 1, line, ls, pid)
      _ ->
        send(pid, {:error, "Expected '>'", {line, ls, pos}})
    end
  end

  # === Comment ===

  defp parse_comment(xml, pos, line, ls, loc, pid) do
    case scan_until(xml, pos, line, ls, "--") do
      {content, <<">", rest::binary>>, pos, line, ls} ->
        send(pid, {:comment, content, loc})
        do_parse(rest, pos + 1, line, ls, pid)
      {_, _, pos, line, ls} ->
        send(pid, {:error, "Expected '-->'", {line, ls, pos}})
    end
  end

  # === CDATA ===

  defp parse_cdata(xml, pos, line, ls, loc, pid) do
    case scan_until(xml, pos, line, ls, "]]") do
      {content, <<">", rest::binary>>, pos, line, ls} ->
        send(pid, {:text, content, loc})
        do_parse(rest, pos + 1, line, ls, pid)
      {_, _, pos, line, ls} ->
        send(pid, {:error, "Expected ']]>'", {line, ls, pos}})
    end
  end

  # === Processing Instruction ===

  defp parse_pi(xml, pos, line, ls, loc, pid) do
    {name, xml, pos, line, ls} = parse_name(xml, pos, line, ls)
    {xml, pos, line, ls} = skip_ws(xml, pos, line, ls)

    case scan_until(xml, pos, line, ls, "?") do
      {content, <<">", rest::binary>>, pos, line, ls} ->
        send(pid, {:proc_inst, name, String.trim(content), loc})
        do_parse(rest, pos + 1, line, ls, pid)
      {_, _, pos, line, ls} ->
        send(pid, {:error, "Expected '?>'", {line, ls, pos}})
    end
  end

  # === Text ===

  defp parse_text(xml, pos, line, ls, pid) do
    loc = {line, ls, pos}
    {content, rest, pos, line, ls} = scan_text(xml, pos, line, ls, 0)
    send(pid, {:text, content, loc})
    do_parse(rest, pos, line, ls, pid)
  end

  # === Helpers ===

  defp parse_name(<<c, _::binary>> = xml, pos, line, ls) when is_name_start(c) do
    scan_name(xml, pos, line, ls, 0)
  end

  defp parse_name(xml, pos, line, ls), do: {"", xml, pos, line, ls}

  defp scan_name(xml, pos, line, ls, len) do
    case xml do
      <<_::binary-size(len), c, _::binary>> when is_name_char(c) ->
        scan_name(xml, pos, line, ls, len + 1)
      _ ->
        name = binary_part(xml, 0, len)
        rest = binary_part(xml, len, byte_size(xml) - len)
        {name, rest, pos + len, line, ls}
    end
  end

  defp parse_attributes(<<c, _::binary>> = xml, pos, line, ls, acc) when is_name_start(c) do
    {name, xml, pos, line, ls} = parse_name(xml, pos, line, ls)
    {xml, pos, line, ls} = skip_ws(xml, pos, line, ls)

    case xml do
      <<"=", rest::binary>> ->
        {rest, pos, line, ls} = skip_ws(rest, pos + 1, line, ls)
        {value, xml, pos, line, ls} = parse_quoted(rest, pos, line, ls)
        {xml, pos, line, ls} = skip_ws(xml, pos, line, ls)
        parse_attributes(xml, pos, line, ls, [{name, value} | acc])
      _ ->
        {Enum.reverse(acc), xml, pos, line, ls}
    end
  end

  defp parse_attributes(xml, pos, line, ls, acc) do
    {Enum.reverse(acc), xml, pos, line, ls}
  end

  defp parse_quoted(<<"\"", xml::binary>>, pos, line, ls) do
    scan_quoted(xml, pos + 1, line, ls, ?\", 0)
  end

  defp parse_quoted(<<"'", xml::binary>>, pos, line, ls) do
    scan_quoted(xml, pos + 1, line, ls, ?', 0)
  end

  defp parse_quoted(xml, pos, line, ls), do: {"", xml, pos, line, ls}

  defp scan_quoted(xml, pos, line, ls, q, len) do
    case xml do
      <<_::binary-size(len), ^q, rest::binary>> ->
        value = binary_part(xml, 0, len)
        {value, rest, pos + len + 1, line, ls}
      <<_::binary-size(len), ?\n, _::binary>> ->
        scan_quoted(xml, pos, line + 1, pos + len + 1, q, len + 1)
      <<_::binary-size(len), _, _::binary>> ->
        scan_quoted(xml, pos, line, ls, q, len + 1)
      _ ->
        {binary_part(xml, 0, len), "", pos + len, line, ls}
    end
  end

  defp skip_ws(<<?\n, rest::binary>>, pos, line, _ls) do
    skip_ws(rest, pos + 1, line + 1, pos + 1)
  end

  defp skip_ws(<<c, rest::binary>>, pos, line, ls) when c in @ws do
    skip_ws(rest, pos + 1, line, ls)
  end

  defp skip_ws(xml, pos, line, ls), do: {xml, pos, line, ls}

  defp scan_until(xml, pos, line, ls, delim) do
    dlen = byte_size(delim)
    do_scan_until(xml, pos, line, ls, delim, dlen, 0)
  end

  defp do_scan_until(xml, pos, line, ls, delim, dlen, len) do
    case xml do
      <<_::binary-size(len), ^delim::binary-size(dlen), rest::binary>> ->
        content = binary_part(xml, 0, len)
        {content, rest, pos + len + dlen, line, ls}
      <<_::binary-size(len), ?\n, _::binary>> ->
        do_scan_until(xml, pos, line + 1, pos + len + 1, delim, dlen, len + 1)
      <<_::binary-size(len), _, _::binary>> ->
        do_scan_until(xml, pos, line, ls, delim, dlen, len + 1)
      _ ->
        {xml, "", pos + byte_size(xml), line, ls}
    end
  end

  defp scan_text(xml, pos, line, ls, len) do
    case xml do
      <<_::binary-size(len), ?<, _::binary>> ->
        content = binary_part(xml, 0, len)
        rest = binary_part(xml, len, byte_size(xml) - len)
        {content, rest, pos + len, line, ls}
      <<_::binary-size(len), ?\n, _::binary>> ->
        scan_text(xml, pos, line + 1, pos + len + 1, len + 1)
      <<_::binary-size(len), _, _::binary>> ->
        scan_text(xml, pos, line, ls, len + 1)
      _ ->
        {xml, "", pos + byte_size(xml), line, ls}
    end
  end
end
