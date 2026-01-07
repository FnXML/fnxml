defmodule FnXML.Parser.Elixir do
  @moduledoc """
  XML Parser using pure Elixir index-based scanning.

  Same approach as FnXML.Parser.Zig but using pure Elixir for scanning.
  This allows comparison between Zig SIMD and pure Elixir approaches.
  """

  alias FnXML.Scanner.Elixir, as: Scanner

  @doc """
  Parse XML string into a stream of events.

  Uses Elixir scanning to find all bracket positions, then classifies each element.
  Returns the same event format as FnXML.Parser.parse/1.
  """
  def parse(xml) when is_binary(xml) do
    # Get all element boundaries - one scan pass
    elements = Scanner.find_elements(xml)

    Stream.resource(
      fn -> {xml, elements, 0} end,
      &next_tokens/1,
      fn _ -> :ok end
    )
  end

  @doc """
  Parse using :binary.matches for scanning (potentially faster).
  """
  def parse_binary(xml) when is_binary(xml) do
    elements = Scanner.find_elements_binary(xml)

    Stream.resource(
      fn -> {xml, elements, 0} end,
      &next_tokens/1,
      fn _ -> :ok end
    )
  end

  # No more elements
  defp next_tokens({_xml, [], _prev_end}) do
    {:halt, nil}
  end

  # Process next element
  defp next_tokens({xml, [{start, end_pos} | rest], prev_end}) do
    tokens =
      # Check for text content before this element
      if start > prev_end do
        text = binary_part(xml, prev_end, start - prev_end)
        case text do
          <<>> -> []
          _ ->
            if all_whitespace?(text, 0, byte_size(text)) do
              []
            else
              [{:text, [content: text, loc: {1, 0, prev_end}]}]
            end
        end
      else
        []
      end

    # Extract and parse element content
    len = end_pos - start - 1
    element = parse_element_fast(xml, start + 1, len, start)

    # Handle self-closing tags inline
    case element do
      {:open, meta} ->
        case Keyword.get(meta, :close) do
          true ->
            tag = Keyword.get(meta, :tag)
            new_meta = Keyword.delete(meta, :close)
            {[{:open, new_meta}, {:close, [tag: tag]} | tokens],
             {xml, rest, end_pos + 1}}

          _ ->
            {[element | tokens], {xml, rest, end_pos + 1}}
        end

      _ ->
        {[element | tokens], {xml, rest, end_pos + 1}}
    end
  end

  # Fast whitespace check using binary matching
  defp all_whitespace?(_bin, pos, len) when pos >= len, do: true
  defp all_whitespace?(bin, pos, len) do
    case :binary.at(bin, pos) do
      c when c == ?\s or c == ?\n or c == ?\r or c == ?\t ->
        all_whitespace?(bin, pos + 1, len)
      _ ->
        false
    end
  end

  # Fast element parsing using binary pattern matching
  defp parse_element_fast(xml, offset, len, start) do
    case :binary.at(xml, offset) do
      ?! -> parse_special(xml, offset, len, start)
      ?? -> parse_pi(xml, offset, len, start)
      ?/ -> parse_close(xml, offset + 1, len - 1, start)
      _ -> parse_open(xml, offset, len, start)
    end
  end

  # Parse special elements (comments, CDATA)
  defp parse_special(xml, offset, len, start) do
    rest = binary_part(xml, offset + 1, len - 1)
    cond do
      match?(<<"--", _::binary>>, rest) ->
        content = binary_part(xml, offset + 3, len - 5)
        {:comment, [content: content, loc: {1, 0, start}]}

      match?(<<"[CDATA[", _::binary>>, rest) ->
        content = binary_part(xml, offset + 8, len - 10)
        {:text, [content: content, loc: {1, 0, start}]}

      true ->
        {:declaration, [content: rest, loc: {1, 0, start}]}
    end
  end

  # Parse processing instruction
  defp parse_pi(xml, offset, len, start) do
    content = binary_part(xml, offset + 1, len - 1)
    # Trim trailing ?
    content = if String.ends_with?(content, "?") do
      binary_part(content, 0, byte_size(content) - 1)
    else
      content
    end

    {tag, rest} = split_at_whitespace(content)

    if tag == "xml" do
      attrs = parse_attrs_fast(rest)
      {:prolog, [tag: tag, attributes: attrs, loc: {1, 0, start}]}
    else
      {:proc_inst, [tag: tag, content: rest, loc: {1, 0, start}]}
    end
  end

  # Parse close tag
  defp parse_close(xml, offset, len, start) do
    tag = binary_part(xml, offset, len) |> String.trim()
    {:close, [tag: tag, loc: {1, 0, start}]}
  end

  # Parse open tag
  defp parse_open(xml, offset, len, start) do
    content = binary_part(xml, offset, len)

    # Check for self-closing
    {content, self_close} =
      case :binary.last(content) do
        ?/ -> {binary_part(content, 0, len - 1), true}
        _ -> {content, false}
      end

    {tag, rest} = split_at_whitespace(content)
    attrs = parse_attrs_fast(rest)

    meta =
      case {self_close, attrs} do
        {true, []} -> [tag: tag, close: true, loc: {1, 0, start}]
        {true, _} -> [tag: tag, close: true, attributes: attrs, loc: {1, 0, start}]
        {false, []} -> [tag: tag, loc: {1, 0, start}]
        {false, _} -> [tag: tag, attributes: attrs, loc: {1, 0, start}]
      end

    {:open, meta}
  end

  # Split at first whitespace using binary matching
  defp split_at_whitespace(bin), do: split_ws(bin, 0, byte_size(bin))

  defp split_ws(bin, pos, len) when pos >= len, do: {bin, ""}
  defp split_ws(bin, pos, len) do
    case :binary.at(bin, pos) do
      c when c == ?\s or c == ?\n or c == ?\r or c == ?\t ->
        {binary_part(bin, 0, pos), String.trim_leading(binary_part(bin, pos, len - pos))}
      _ ->
        split_ws(bin, pos + 1, len)
    end
  end

  # Fast attribute parsing using binary matching
  defp parse_attrs_fast(<<>>), do: []
  defp parse_attrs_fast(bin), do: do_parse_attrs(bin, [])

  defp do_parse_attrs(<<>>, acc), do: Enum.reverse(acc)
  defp do_parse_attrs(bin, acc) do
    bin = skip_whitespace(bin)
    case bin do
      <<>> -> Enum.reverse(acc)
      _ ->
        case parse_one_attr(bin) do
          {nil, rest} -> do_parse_attrs(rest, acc)
          {attr, rest} -> do_parse_attrs(rest, [attr | acc])
        end
    end
  end

  defp skip_whitespace(<<c, rest::binary>>) when c in [?\s, ?\n, ?\r, ?\t] do
    skip_whitespace(rest)
  end
  defp skip_whitespace(bin), do: bin

  defp parse_one_attr(bin) do
    case find_equals(bin, 0) do
      nil -> {nil, ""}
      eq_pos ->
        name = binary_part(bin, 0, eq_pos) |> String.trim()
        rest = binary_part(bin, eq_pos + 1, byte_size(bin) - eq_pos - 1) |> String.trim_leading()

        case rest do
          <<"\"", rest2::binary>> ->
            case :binary.match(rest2, <<"\"">>) do
              {end_pos, 1} ->
                value = binary_part(rest2, 0, end_pos)
                remaining = binary_part(rest2, end_pos + 1, byte_size(rest2) - end_pos - 1)
                {{name, value}, remaining}
              :nomatch ->
                {nil, ""}
            end

          <<"'", rest2::binary>> ->
            case :binary.match(rest2, <<"'">>) do
              {end_pos, 1} ->
                value = binary_part(rest2, 0, end_pos)
                remaining = binary_part(rest2, end_pos + 1, byte_size(rest2) - end_pos - 1)
                {{name, value}, remaining}
              :nomatch ->
                {nil, ""}
            end

          _ ->
            {nil, ""}
        end
    end
  end

  defp find_equals(<<>>, _pos), do: nil
  defp find_equals(<<?=, _::binary>>, pos), do: pos
  defp find_equals(<<_, rest::binary>>, pos), do: find_equals(rest, pos + 1)
end
