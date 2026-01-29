defmodule FnXML.Parser do
  @moduledoc """
  Streaming XML parser for Elixir.

  This module provides the main parsing API for FnXML. It supports multiple parser
  implementations:

  - `:default` - Full-featured macro-based parser (`FnXML.Parser.Edition5`)
  - `:fast` - Optimized parser without position tracking (`FnXML.Legacy.FastExBlkParser`)
  - `:legacy` - Legacy runtime parser (`FnXML.Legacy.ExBlkParser`)

  ## Basic Usage

      # Default parser (Edition 5)
      events = FnXML.Parser.parse("<root/>") |> Enum.to_list()

      # Fast parser (no position tracking, faster)
      events = FnXML.Parser.parse(xml, parser: :fast) |> Enum.to_list()

      # Legacy parser (Legacy.ExBlkParser)
      events = FnXML.Parser.parse(xml, parser: :legacy) |> Enum.to_list()

      # Edition 4 parser
      events = FnXML.Parser.parse(xml, edition: 4) |> Enum.to_list()

      # Parse from file stream
      events = File.stream!("large.xml", [], 65536)
               |> FnXML.Parser.parse()
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

  ## Custom Parsers

  FnXML allows you to create custom parser modules at compile time with specific
  event filtering and options for improved performance.

  ### Quick Start

      defmodule MyApp.MinimalParser do
        use FnXML.Parser.Generator,
          edition: 5,
          disable: [:space, :comment]
      end

      # Use your custom parser
      MyApp.MinimalParser.parse("<root>  text  </root>")
      |> Enum.to_list()
      # Events: no :space or :comment events

  ### Generator Options

  When using `FnXML.Parser.Generator`, the following options are available:

  **Required:**
  - `:edition` - XML 1.0 edition (4 or 5)
    - Edition 5: Permissive character validation (recommended)
    - Edition 4: Strict character validation per XML 1.0 spec Appendix B

  **Optional:**
  - `:disable` - List of event types to skip at compile time:
    - `:space` - Skip whitespace-only text nodes
    - `:comment` - Skip XML comments (`<!-- ... -->`)
    - `:cdata` - Skip CDATA sections (`<![CDATA[...]]>`)
    - `:prolog` - Skip XML declarations (`<?xml ...?>`)
    - `:characters` - Skip all text content
    - `:processing_instruction` - Skip processing instructions (`<?target data?>`)

  - `:positions` - Position tracking mode:
    - `:full` (default) - Include line, ls, and abs_pos
    - `:line_only` - Include only line numbers
    - `:none` - No position data (fastest)

  ### Common Use Cases

  #### 1. Minimal Parser (Configuration Files)

  Skip whitespace and comments for parsing configuration files where formatting doesn't matter:

      defmodule MyApp.ConfigParser do
        use FnXML.Parser.Generator,
          edition: 5,
          disable: [:space, :comment]
      end

  **Performance:** ~40% faster than standard parser

  #### 2. Structure-Only Parser (Schema Validation)

  Parse only element structure, ignoring all text content:

      defmodule MyApp.StructureParser do
        use FnXML.Parser.Generator,
          edition: 5,
          disable: [:characters, :space, :comment, :cdata]
      end

  **Use cases:**
  - Schema validation
  - Document structure analysis
  - Element counting and statistics

  #### 3. Fast Parser (Large Files)

  Maximum performance when you don't need position tracking:

      defmodule MyApp.FastParser do
        use FnXML.Parser.Generator,
          edition: 5,
          positions: :none
      end

  **Performance:** ~50% faster than standard parser with position tracking

  #### 4. Content Parser (Text Extraction)

  Extract elements and text while skipping metadata:

      defmodule MyApp.ContentParser do
        use FnXML.Parser.Generator,
          edition: 5,
          disable: [:space, :comment, :prolog, :processing_instruction]
      end

  **Use cases:**
  - Content extraction
  - Text indexing
  - Data migration

  #### 5. Strict Parser (Edition 4)

  Use XML 1.0 Fourth Edition for strict character validation:

      defmodule MyApp.StrictParser do
        use FnXML.Parser.Generator,
          edition: 4
      end

  **Use cases:**
  - Validating legacy XML documents
  - Ensuring maximum compatibility
  - Standards compliance testing

  ### Performance Comparison

  Based on parsing a document with 100 elements:

  | Parser Configuration | Relative Performance | Use Case |
  |---------------------|---------------------|----------|
  | Standard (full) | 100% (baseline) | General purpose |
  | Minimal (no space/comments) | ~60% | Config files |
  | Fast (no positions) | ~60% | Large files, no errors |
  | Structure only | ~55% | Schema validation |
  | Combined (minimal + fast) | ~40% | Maximum performance |

  ### Integration with Pipelines

  Custom parsers work seamlessly with all FnXML APIs:

      # With DOM
      doc = MyApp.MinimalParser.parse(xml)
            |> FnXML.API.DOM.build()

      # With SAX
      {:ok, result} = MyApp.MinimalParser.stream([xml])
                      |> FnXML.API.SAX.dispatch(MyHandler, [])

      # With StAX
      reader = MyApp.MinimalParser.stream([xml])
               |> FnXML.API.StAX.Reader.new()

      # With validation
      events = MyApp.MinimalParser.parse(xml)
               |> FnXML.Event.Validate.well_formed()
               |> FnXML.Namespaces.resolve()
               |> Enum.to_list()

  ### Introspection

  Custom parsers expose their configuration:

      defmodule MyParser do
        use FnXML.Parser.Generator,
          edition: 5,
          disable: [:space, :comment]
      end

      MyParser.edition()        # => 5
      MyParser.disabled()       # => [:space, :comment]
      MyParser.position_mode()  # => :full

  ### Best Practices

  1. **Profile First**: Use the standard parser first, then create custom parsers if performance is an issue

  2. **Match Use Case**: Choose options that match your specific use case:
     - Config files → disable `:space`, `:comment`
     - Schema validation → disable all content events
     - Large files → set `positions: :none`

  3. **Module Naming**: Use descriptive names like `ConfigParser`, `StructureParser`, `FastParser`

  4. **Document Purpose**: Add `@moduledoc` explaining why the parser has specific options

  5. **Test Both**: Test with both standard and custom parsers during development

  ### Complete Example

      defmodule MyApp.Parsers.Minimal do
        @moduledoc \"\"\"
        Optimized XML parser for configuration files.

        Skips whitespace-only text nodes and comments for faster parsing
        of configuration files where formatting and documentation don't matter.

        Approximately 40% faster than the standard parser.
        \"\"\"

        use FnXML.Parser.Generator,
          edition: 5,
          disable: [:space, :comment]

        @doc \"\"\"
        Parse XML configuration file.

        ## Example

            iex> xml = "<config><setting>value</setting></config>"
            iex> #{__MODULE__}.parse(xml) |> Enum.to_list()
            # Only structural and content events
        \"\"\"
        def parse(xml) when is_binary(xml) do
          stream([xml])
        end
      end
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

  ## Examples

      # Get Edition 5 parser
      parser = FnXML.Parser.generate(5)
      parser.parse("<root/>")
      parser.stream(File.stream!("large.xml"))

      # Get Edition 4 parser
      parser = FnXML.Parser.generate(4)

  Note: `generate/1` returns pre-compiled parser modules (Edition4 or Edition5).
  For custom parsers with specific options, use `FnXML.Parser.Generator` directly
  at compile time. See the "Custom Parsers" section in the module documentation.
  """
  @spec generate(edition()) :: module()
  def generate(5), do: __MODULE__.Edition5
  def generate(4), do: __MODULE__.Edition4
  def generate(_), do: __MODULE__.Edition5

  @doc """
  Parse XML from a string or stream.

  Returns a lazy stream of XML events. Automatically detects whether
  the input is a binary string or an enumerable (like File.stream!/1).

  ## Options

  - `:parser` - Parser to use: `:default` or `:fast` (default: `:default`)
  - `:edition` - XML 1.0 edition (4 or 5, default: 5)

  ## Examples

      # Parse a string
      "<root><child/></root>"
      |> FnXML.Parser.parse()
      |> FnXML.API.DOM.build()

      # Parse a file stream
      File.stream!("data.xml", [], 65536)
      |> FnXML.Parser.parse()
      |> FnXML.API.SAX.dispatch(MyHandler, %{})

      # With validation pipeline
      File.stream!("large.xml")
      |> FnXML.Parser.parse()
      |> FnXML.Event.Validate.well_formed()
      |> FnXML.Namespaces.resolve()
      |> FnXML.API.DOM.build()

      # Use fast parser for better performance
      FnXML.Parser.parse(xml, parser: :fast)

      # Use Edition 4 parser
      FnXML.Parser.parse(xml, edition: 4)
  """
  def parse(source, opts \\ [])

  def parse(source, opts) when is_binary(source) do
    delegate_stream = select_parser_stream([source], opts)
    wrap_with_document_events(delegate_stream)
  end

  def parse(source, opts) do
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
        generate(edition).stream(source)
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
  Low-level: parse a single block of XML.

  This is used internally for streaming. Most users should use `parse/2` instead.

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
