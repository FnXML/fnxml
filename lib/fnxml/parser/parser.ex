defmodule FnXML.Parser do
  @moduledoc """
  Streaming XML parser for Elixir.

  This module provides the main parsing API for FnXML. It supports multiple parser
  implementations:

  - `:default` - Full-featured macro-based parser (`FnXML.Parser.Edition5`)
  - `:fast` - Optimized parser without position tracking (`FnXML.Legacy.FastExBlkParser`)
  - `:legacy` - Legacy runtime parser (`FnXML.Legacy.ExBlkParser`)

  ## Options

  - `:parser` - Parser selection: `:default`, `:fast`, or `:legacy` (default: `:default`)
  - `:edition` - XML 1.0 edition (4 or 5, default: 5) - only applies to `:default` parser

  ## Usage

      # Default parser (Edition 5)
      events = FnXML.Parser.stream("<root/>") |> Enum.to_list()

      # Fast parser (no position tracking, faster)
      events = FnXML.Parser.stream(xml, parser: :fast) |> Enum.to_list()

      # Legacy parser (Legacy.ExBlkParser)
      events = FnXML.Parser.stream(xml, parser: :legacy) |> Enum.to_list()

      # Edition 4 parser
      events = FnXML.Parser.stream(xml, edition: 4) |> Enum.to_list()

      # Parse to list directly
      events = FnXML.Parser.parse("<root><child/></root>")

      # Stream from file
      events = File.stream!("large.xml", [], 65536)
               |> FnXML.Parser.stream()
               |> Enum.to_list()

      # Direct access to edition-specific parsers for maximum performance
      FnXML.Parser.Edition5.parse("<root/>")
      FnXML.Parser.Edition4.parse("<root/>")

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

  # ===========================================================================
  # Edition-specific parsers (generated at compile time)
  # ===========================================================================

  defmodule Edition5 do
    @moduledoc """
    XML 1.0 Fifth Edition parser.

    Uses the permissive Edition 5 character validation rules.
    Generated at compile time with zero runtime dispatch overhead.
    """
    use FnXML.Parser.Generator, edition: 5
  end

  defmodule Edition4 do
    @moduledoc """
    XML 1.0 Fourth Edition parser.

    Uses the strict Edition 4 character validation rules from Appendix B.
    Generated at compile time with zero runtime dispatch overhead.
    """
    use FnXML.Parser.Generator, edition: 4
  end

  # ===========================================================================
  # Public API
  # ===========================================================================

  @type edition :: 4 | 5

  @doc """
  Get the parser module for the specified edition.

  Returns the module that can be used for all parsing operations
  without per-call edition dispatch.

  ## Example

      parser = FnXML.Parser.parser(5)
      parser.parse("<root/>")
      parser.stream(File.stream!("large.xml"))
  """
  @spec parser(edition()) :: module()
  def parser(5), do: __MODULE__.Edition5
  def parser(4), do: __MODULE__.Edition4
  def parser(_), do: __MODULE__.Edition5

  @doc """
  Check if a name is valid in BOTH Edition 4 and Edition 5.

  Useful for ensuring maximum interoperability when generating XML.
  """
  @spec interoperable_name?(String.t()) :: boolean()
  def interoperable_name?(name) do
    FnXML.Char.valid_name_ed4?(name)
    # If valid in Ed4, automatically valid in Ed5 (Ed5 is superset)
  end

  @doc """
  Stream XML from a string or enumerable, parsing in chunks.

  Returns a lazy stream of XML events.

  ## Options

  - `:parser` - Parser to use: `:default` or `:fast` (default: `:default`)
  - `:edition` - XML 1.0 edition (4 or 5, default: 5)

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

      # Use Edition 4 parser
      FnXML.Parser.stream(xml, edition: 4)
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
      :fast ->
        FnXML.Legacy.FastExBlkParser.stream(source)

      :legacy ->
        FnXML.Legacy.ExBlkParser.stream(source)

      _ ->
        # Use Edition 5 as default
        edition = Keyword.get(opts, :edition, 5)
        parser(edition).stream(source)
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

  - `:parser` - Parser to use: `:default`, `:fast`, or `:legacy` (default: `:default`)
  - `:edition` - XML 1.0 edition (4 or 5, default: 5)

  ## Examples

      events = FnXML.Parser.parse("<root><child>text</child></root>")
      # => [{:start_document, nil}, {:start_element, "root", [], 1, 0, 1}, ...]

      # Fast parsing
      events = FnXML.Parser.parse(xml, parser: :fast)

      # Edition 4 parsing
      events = FnXML.Parser.parse(xml, edition: 4)
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
    FnXML.Legacy.ExBlkParser.parse_block(block, prev_block, prev_pos, line, ls, abs_pos)
  end
end
