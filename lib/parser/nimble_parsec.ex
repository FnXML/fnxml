defmodule FnXML.Parser.NimbleParsec do
  @moduledoc """
  XML Parser: This parser emits a stream of XML tags and text.

  This parser attempts to follow the spcification at: https://www.w3.org/TR/xml

  It is designed to be used with Streams.  The parser emits 3 different types of items:
  {:open, [... open tag data...]}
  {:close, [... close tag data...]}
  {:text, [... text data...]}

  These are available as a stream of items which can be processed by other stream functions.
  """
  import NimbleParsec

  alias FnXML.Parser.Element

  # Batch size for event emission - reduces Stream.resource overhead
  # Smaller batches are better for early termination (take/filter)
  # Larger batches reduce overhead for full traversal
  # 32 is a good balance for both use cases
  @batch_size 32

  @doc """
  Basic XML Parser, parses to a stream of tags and text.  This makes it possible to process XML as a stream.
  """

  defparsec(:prolog, optional(Element.prolog()))

  defparsec(:next_element, Element.next())

  def parse_prolog(xml) do
    case prolog(xml) do
      {:ok, [prolog], xml, %{}, line, abs_char} -> {[prolog], xml, line, abs_char}
      {:ok, [], xml, %{}, line, abs_char} -> {xml, line, abs_char}
    end
  end

  # End of input - halt the stream
  def parse_next({"", _line, _abs_char} = state), do: {:halt, state}

  # Main batch parsing entry point
  def parse_next({xml, line, abs_char}) do
    parse_batch(xml, line, abs_char, [], @batch_size)
  end

  # Handle prolog at start - emit prolog then continue with batch
  def parse_next({[prolog], xml, line, abs_char}) do
    case parse_batch(xml, line, abs_char, [], @batch_size - 1) do
      {:halt, state} -> {[prolog], state}
      {tokens, state} -> {[prolog | tokens], state}
    end
  end

  # Batch parsing: collect multiple events before emitting
  defp parse_batch("", line, abs_char, acc, _remaining) do
    # End of input - emit what we have and halt
    case acc do
      [] -> {:halt, {"", line, abs_char}}
      _ -> {Enum.reverse(acc), {"", line, abs_char}}
    end
  end

  defp parse_batch(xml, line, abs_char, acc, 0) do
    # Batch complete - emit events
    {Enum.reverse(acc), {xml, line, abs_char}}
  end

  defp parse_batch(xml, line, abs_char, acc, remaining) do
    {:ok, items, rest, _, new_line, new_abs_char} =
      next_element__0(xml, [], [], [], line, abs_char)

    # Handle events - most common case is a single event
    # For self-closing tags: <a/> becomes {:open, ...} + {:close, ...}
    # We prepend to acc, then reverse at end, so add in reverse order
    case items do
      # Self-closing tag with attributes: [tag: t, close: true, attributes: a, loc: l]
      [{:open, [tag: tag, close: true, attributes: attrs, loc: loc]}] ->
        new_acc = [{:close, [tag: tag]}, {:open, [tag: tag, attributes: attrs, loc: loc]} | acc]
        parse_batch(rest, new_line, new_abs_char, new_acc, remaining - 2)

      # Self-closing tag without attributes: [tag: t, close: true, loc: l]
      [{:open, [tag: tag, close: true, loc: loc]}] ->
        new_acc = [{:close, [tag: tag]}, {:open, [tag: tag, loc: loc]} | acc]
        parse_batch(rest, new_line, new_abs_char, new_acc, remaining - 2)

      # Single event (most common case) - just prepend
      [event] ->
        parse_batch(rest, new_line, new_abs_char, [event | acc], remaining - 1)

      # Multiple events (rare) - prepend all in reverse order
      events ->
        new_acc = prepend_all(events, acc)
        parse_batch(rest, new_line, new_abs_char, new_acc, remaining - length(events))
    end
  end

  # Helper to prepend a list of items to accumulator
  defp prepend_all([], acc), do: acc
  defp prepend_all([h | t], acc), do: prepend_all(t, [h | acc])

  def parse(xml), do: Stream.resource(fn -> parse_prolog(xml) end, &parse_next/1, fn _ -> :ok end)
end
