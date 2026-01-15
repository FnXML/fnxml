defmodule FnXML.Parser do
  @moduledoc """
  Streaming XML parser for Elixir.

  This module provides the main parsing API for FnXML. It supports two parser
  implementations:

  - `:default` - Full-featured parser with position tracking (`FnXML.ExBlkParser`)
  - `:fast` - Optimized parser without position tracking (`FnXML.FastExBlkParser`)

  ## Options

  - `:parser` - Parser selection: `:default` or `:fast` (default: `:default`)

  ## Usage

      # Default parser (with position tracking)
      events = FnXML.Parser.stream("<root/>") |> Enum.to_list()

      # Fast parser (no position tracking, faster)
      events = FnXML.Parser.stream(xml, parser: :fast) |> Enum.to_list()

      # Parse to list directly
      events = FnXML.Parser.parse("<root><child/></root>")

      # Stream from file
      events = File.stream!("large.xml", [], 65536)
               |> FnXML.Parser.stream()
               |> Enum.to_list()

  ## Event Format

  Events are emitted as tuples with the format:

  - `{:start_document, nil}` - Document start marker
  - `{:end_document, nil}` - Document end marker
  - `{:start_element, tag, attrs, line, ls, pos}` - Opening tag
  - `{:end_element, tag, line, ls, pos}` - Closing tag
  - `{:characters, content, line, ls, pos}` - Text content
  - `{:space, content, line, ls, pos}` - Whitespace (default parser only)
  - `{:comment, content, line, ls, pos}` - Comment
  - `{:cdata, content, line, ls, pos}` - CDATA section
  - `{:dtd, content, line, ls, pos}` - DOCTYPE declaration
  - `{:prolog, "xml", attrs, line, ls, pos}` - XML declaration
  - `{:processing_instruction, target, data, line, ls, pos}` - PI
  - `{:error, type, msg, line, ls, pos}` - Parse error

  Location fields (`line`, `ls`, `pos`) are:
  - `line` - 1-based line number
  - `ls` - Byte offset where current line starts
  - `pos` - Absolute byte position

  Note: The fast parser emits `nil` for all location fields.
  """

  @doc """
  Stream XML from a string or enumerable, parsing in chunks.

  Returns a lazy stream of XML events.

  ## Options

  - `:parser` - Parser to use: `:default` or `:fast` (default: `:default`)

  ## Examples

      # Parse a string
      FnXML.Parser.stream("<root><child/></root>")
      |> Enum.to_list()

      # Parse a file stream
      File.stream!("data.xml", [], 65536)
      |> FnXML.Parser.stream()
      |> Enum.to_list()

      # Use fast parser for better performance
      FnXML.Parser.stream(xml, parser: :fast)
      |> Enum.to_list()
  """
  def stream(source, opts \\ [])

  def stream(source, opts) when is_binary(source) do
    delegate_stream = select_parser_stream([source], opts)
    wrap_with_document_events(delegate_stream)
  end

  def stream(source, opts) do
    delegate_stream = select_parser_stream(source, opts)
    wrap_with_document_events(delegate_stream)
  end

  defp select_parser_stream(source, opts) do
    case Keyword.get(opts, :parser, :default) do
      :fast -> FnXML.FastExBlkParser.stream(source)
      _ -> FnXML.ExBlkParser.stream(source)
    end
  end

  defp wrap_with_document_events(delegate_stream) do
    Stream.concat([
      [{:start_document, nil}],
      delegate_stream,
      [{:end_document, nil}]
    ])
  end

  @doc """
  Parse XML and return all events as a list.

  This is a convenience function that calls `stream/2` and collects
  all events into a list.

  ## Options

  - `:parser` - Parser to use: `:default` or `:fast` (default: `:default`)

  ## Examples

      events = FnXML.Parser.parse("<root><child>text</child></root>")
      # => [{:start_document, nil}, {:start_element, "root", [], 1, 0, 1}, ...]

      # Fast parsing
      events = FnXML.Parser.parse(xml, parser: :fast)
  """
  def parse(source, opts \\ []) do
    stream(source, opts) |> Enum.to_list()
  end

  @doc """
  Low-level: parse a single block of XML.

  This is used internally for streaming. Most users should use `stream/2`
  or `parse/2` instead.

  ## Parameters

  - `block` - The XML data to parse
  - `prev_block` - Previous block data (for handling incomplete elements)
  - `prev_pos` - Position in previous block
  - `state` - Parser state tuple `{line, line_start, abs_pos}`

  ## Returns

  `{events, leftover_pos, new_state}` where:
  - `events` - List of parsed event tuples
  - `leftover_pos` - Position where parsing stopped, or `nil` if complete
  - `new_state` - Updated `{line, line_start, abs_pos}` state
  """
  def parse_block(block, prev_block, prev_pos, {line, ls, abs_pos}) do
    FnXML.ExBlkParser.parse_block(block, prev_block, prev_pos, line, ls, abs_pos)
  end
end
