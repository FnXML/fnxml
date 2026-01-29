defmodule FnXML.Event.Transform.Normalize do
  @moduledoc """
  XML input normalization per W3C XML 1.0 specification.

  Per Section 2.11, XML processors must normalize line endings before parsing:
  - CRLF (`\\r\\n`) must be converted to LF (`\\n`)
  - Standalone CR (`\\r`) must be converted to LF (`\\n`)

  This module provides both binary and stream-based normalization functions.
  """

  @doc """
  Normalize line endings in a binary: CRLF and standalone CR → LF.

  ## Examples

      iex> FnXML.Event.Transform.Normalize.line_endings("a\\r\\nb")
      "a\\nb"

      iex> FnXML.Event.Transform.Normalize.line_endings("a\\rb")
      "a\\nb"

      iex> FnXML.Event.Transform.Normalize.line_endings("a\\nb")
      "a\\nb"

  ## Usage

      xml = File.read!("input.xml") |> FnXML.Event.Transform.Normalize.line_endings()
      FnXML.Parser.parse(xml) |> Enum.to_list()

  """
  @spec line_endings(binary()) :: binary()
  def line_endings(binary) when is_binary(binary) do
    binary
    |> :binary.replace(<<?\r, ?\n>>, <<?\n>>, [:global])
    |> :binary.replace(<<?\r>>, <<?\n>>, [:global])
  end

  @doc """
  Stream transformer for line ending normalization.

  Handles chunks that may split across CR LF boundaries by holding
  a trailing CR in pending state until the next chunk arrives.

  ## Examples

      File.stream!("large.xml", [], 65536)
      |> FnXML.Event.Transform.Normalize.line_endings_stream()
      |> FnXML.Parser.parse()
      |> Enum.to_list()

  """
  @spec line_endings_stream(Enumerable.t()) :: Enumerable.t()
  def line_endings_stream(stream) do
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
