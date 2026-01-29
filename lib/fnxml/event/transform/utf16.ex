defmodule FnXML.Event.Transform.Utf16 do
  @moduledoc """
  UTF-16 to UTF-8 conversion for XML parsing.

  This module detects UTF-16 encoding via BOM (Byte Order Mark) and converts
  to UTF-8 for parsing. UTF-8 input passes through unchanged.

  ## Usage

      # With streams
      File.stream!("document.xml", [], 65536)
      |> FnXML.Event.Transform.Utf16.to_utf8()
      |> FnXML.Parser.parse()

      # With binaries
      xml = File.read!("document.xml") |> FnXML.Event.Transform.Utf16.to_utf8()
      FnXML.Parser.parse(xml)

  ## Supported Encodings

  - UTF-8 (with or without BOM) - passed through unchanged
  - UTF-16 LE (Little Endian) - detected by BOM `0xFF 0xFE`
  - UTF-16 BE (Big Endian) - detected by BOM `0xFE 0xFF`

  ## Notes

  - UTF-16 without BOM is not auto-detected (ambiguous)
  - For known UTF-16 without BOM, use `to_utf8/2` with explicit encoding
  """

  @utf16_le_bom <<0xFF, 0xFE>>
  @utf16_be_bom <<0xFE, 0xFF>>
  @utf8_bom <<0xEF, 0xBB, 0xBF>>

  @doc """
  Convert input to UTF-8, auto-detecting encoding from BOM.

  Works with both streams and binaries:

  ## Examples

      # Stream input
      File.stream!("file.xml")
      |> FnXML.Event.Transform.Utf16.to_utf8()
      |> FnXML.Parser.parse()

      # Binary input
      xml = File.read!("file.xml") |> FnXML.Event.Transform.Utf16.to_utf8()
      FnXML.Parser.parse(xml)

  """
  @spec to_utf8(binary() | Enumerable.t()) :: binary() | Enumerable.t()
  def to_utf8(input) when is_binary(input) do
    convert_binary(input)
  end

  def to_utf8(stream) do
    Stream.transform(stream, :detect, &transform_chunk/2)
  end

  @doc """
  Convert input to UTF-8 with explicit encoding.

  Use when you know the encoding and don't need BOM detection.

  ## Options

  - `:encoding` - `:utf16_le`, `:utf16_be`, or `:utf8` (default: `:utf8`)

  ## Examples

      # Known UTF-16 LE file without BOM
      File.stream!("utf16le_no_bom.xml")
      |> FnXML.Event.Transform.Utf16.to_utf8(encoding: :utf16_le)
      |> FnXML.Parser.parse()

  """
  @spec to_utf8(binary() | Enumerable.t(), keyword()) :: binary() | Enumerable.t()
  def to_utf8(input, opts) when is_binary(input) do
    case Keyword.get(opts, :encoding, :utf8) do
      :utf8 -> input
      :utf16_le -> convert_binary_raw(input, {:utf16, :little})
      :utf16_be -> convert_binary_raw(input, {:utf16, :big})
    end
  end

  def to_utf8(stream, opts) do
    encoding = Keyword.get(opts, :encoding, :utf8)

    case encoding do
      :utf8 ->
        stream

      :utf16_le ->
        Stream.transform(stream, <<>>, &convert_utf16_chunk(&1, &2, {:utf16, :little}))

      :utf16_be ->
        Stream.transform(stream, <<>>, &convert_utf16_chunk(&1, &2, {:utf16, :big}))
    end
  end

  @doc """
  Detect encoding from BOM.

  Returns `{encoding, data_without_bom}`.

  ## Examples

      iex> FnXML.Event.Transform.Utf16.detect_encoding(<<0xFF, 0xFE, 0x3C, 0x00>>)
      {:utf16_le, <<0x3C, 0x00>>}

      iex> FnXML.Event.Transform.Utf16.detect_encoding(<<0xFE, 0xFF, 0x00, 0x3C>>)
      {:utf16_be, <<0x00, 0x3C>>}

      iex> FnXML.Event.Transform.Utf16.detect_encoding("<root/>")
      {:utf8, "<root/>"}

  """
  @spec detect_encoding(binary()) :: {:utf8 | :utf16_le | :utf16_be, binary()}
  def detect_encoding(<<@utf16_le_bom, rest::binary>>), do: {:utf16_le, rest}
  def detect_encoding(<<@utf16_be_bom, rest::binary>>), do: {:utf16_be, rest}
  def detect_encoding(<<@utf8_bom, rest::binary>>), do: {:utf8, rest}
  def detect_encoding(binary), do: {:utf8, binary}

  # ============================================================================
  # Private Implementation
  # ============================================================================

  # Convert complete binary with BOM detection
  defp convert_binary(binary) do
    case detect_encoding(binary) do
      {:utf8, data} ->
        data

      {:utf16_le, data} ->
        convert_binary_raw(data, {:utf16, :little})

      {:utf16_be, data} ->
        convert_binary_raw(data, {:utf16, :big})
    end
  end

  # Convert complete binary without BOM detection
  defp convert_binary_raw(binary, encoding) do
    case :unicode.characters_to_binary(binary, encoding, :utf8) do
      result when is_binary(result) ->
        result

      {:incomplete, _converted, _rest} ->
        raise ArgumentError, "Incomplete #{format_encoding(encoding)} sequence"

      {:error, _converted, _rest} ->
        raise ArgumentError, "Invalid #{format_encoding(encoding)} sequence"
    end
  end

  defp format_encoding({:utf16, :little}), do: "UTF-16 LE"
  defp format_encoding({:utf16, :big}), do: "UTF-16 BE"

  # Stream transformation - first chunk detects encoding
  defp transform_chunk(chunk, :detect) do
    case detect_encoding(chunk) do
      {:utf8, data} ->
        {[data], :utf8}

      {:utf16_le, data} ->
        convert_first_utf16_chunk(data, {:utf16, :little})

      {:utf16_be, data} ->
        convert_first_utf16_chunk(data, {:utf16, :big})
    end
  end

  # UTF-8 mode: pass through unchanged
  defp transform_chunk(chunk, :utf8) do
    {[chunk], :utf8}
  end

  # UTF-16 mode: convert chunk, handling partial characters
  defp transform_chunk(chunk, {encoding, leftover}) do
    convert_utf16_chunk(chunk, leftover, encoding)
  end

  # Convert first UTF-16 chunk after BOM detection
  defp convert_first_utf16_chunk(data, encoding) do
    case convert_with_leftover(data, encoding) do
      {:ok, converted, leftover} ->
        {[converted], {encoding, leftover}}

      {:error, reason} ->
        raise ArgumentError, reason
    end
  end

  # Convert a UTF-16 chunk, prepending leftover bytes from previous chunk
  defp convert_utf16_chunk(chunk, leftover, encoding) do
    input = leftover <> chunk

    case convert_with_leftover(input, encoding) do
      {:ok, converted, new_leftover} ->
        {[converted], {encoding, new_leftover}}

      {:error, reason} ->
        raise ArgumentError, reason
    end
  end

  # Convert binary, returning any incomplete bytes at the end
  defp convert_with_leftover(binary, encoding) do
    case :unicode.characters_to_binary(binary, encoding, :utf8) do
      result when is_binary(result) ->
        {:ok, result, <<>>}

      {:incomplete, converted, rest} ->
        {:ok, converted, rest}

      {:error, _converted, _rest} ->
        {:error, "Invalid #{format_encoding(encoding)} sequence"}
    end
  end
end
