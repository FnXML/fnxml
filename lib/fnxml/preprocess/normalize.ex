defmodule FnXML.Preprocess.Normalize do
  @moduledoc """
  XML input normalization per W3C XML 1.0 specification.

  This is a **preprocessor** that operates on binaries before parsing.
  It normalizes line endings per Section 2.11 of the XML 1.0 specification:
  - CRLF (`\\r\\n`) must be converted to LF (`\\n`)
  - Standalone CR (`\\r`) must be converted to LF (`\\n`)

  This module provides a polymorphic `line_endings/1` function that works
  with both binaries and streams through pattern matching.

  ## Usage

      # Preprocess a binary before parsing
      xml = File.read!("input.xml")
      |> FnXML.Preprocess.Normalize.line_endings()
      |> FnXML.Parser.parse()

      # Preprocess a stream before parsing
      File.stream!("large.xml", [], 65536)
      |> FnXML.Preprocess.Normalize.line_endings()
      |> FnXML.Parser.parse()
      |> Enum.to_list()

  """

  @doc """
  Normalize line endings: CRLF and standalone CR → LF.

  Works with both binaries and streams through pattern matching.

  ## Examples

      # Binary input
      iex> FnXML.Preprocess.Normalize.line_endings("a\\r\\nb")
      "a\\nb"

      iex> FnXML.Preprocess.Normalize.line_endings("a\\rb")
      "a\\nb"

      iex> FnXML.Preprocess.Normalize.line_endings("a\\nb")
      "a\\nb"

      # Stream input
      File.stream!("large.xml", [], 65536)
      |> FnXML.Preprocess.Normalize.line_endings()
      |> FnXML.Parser.parse()
      |> Enum.to_list()

  ## Usage

      # Binary
      xml = File.read!("input.xml") |> FnXML.Preprocess.Normalize.line_endings()
      FnXML.Parser.parse(xml) |> Enum.to_list()

      # Stream
      File.stream!("large.xml")
      |> FnXML.Preprocess.Normalize.line_endings()
      |> FnXML.Parser.parse()

  """
  @spec line_endings(binary() | Enumerable.t()) :: binary() | Enumerable.t()
  def line_endings(binary) when is_binary(binary) do
    binary
    |> :binary.replace(<<?\r, ?\n>>, <<?\n>>, [:global])
    |> :binary.replace(<<?\r>>, <<?\n>>, [:global])
  end

  def line_endings(stream) do
    Stream.transform(stream, <<>>, &normalize_chunk/2)
    |> Stream.concat(
      Stream.resource(
        fn -> :flush end,
        fn
          :flush -> {:halt, :done}
          :done -> {:halt, :done}
        end,
        fn _ -> :ok end
      )
    )
  end

  # Process a chunk with any pending data from previous chunk
  defp normalize_chunk(chunk, pending) do
    data = pending <> chunk

    case byte_size(data) do
      0 ->
        {[], <<>>}

      _ ->
        {normalized, new_pending} = normalize_with_pending(data)
        {[normalized], new_pending}
    end
  end

  # Handle case where chunk ends with CR (might be CRLF split across chunks)
  defp normalize_with_pending(<<>>) do
    {<<>>, <<>>}
  end

  defp normalize_with_pending(data) do
    case :binary.last(data) do
      ?\r ->
        # CR at end - hold it in pending, might be start of CRLF
        case byte_size(data) do
          1 ->
            {<<>>, <<?\r>>}

          _ ->
            # Get everything except the last CR
            head = binary_part(data, 0, byte_size(data) - 1)
            normalized = normalize_inner(head)
            {normalized, <<?\r>>}
        end

      _ ->
        {normalize_inner(data), <<>>}
    end
  end

  defp normalize_inner(data) do
    data
    |> :binary.replace(<<?\r, ?\n>>, <<?\n>>, [:global])
    |> :binary.replace(<<?\r>>, <<?\n>>, [:global])
  end
end
