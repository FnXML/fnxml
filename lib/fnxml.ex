defmodule FnXML do
  @moduledoc """
  FnXML is a high-performance, pure Elixir XML processing library that implements
  W3C XML standards using a streaming event-based architecture.

  ## What is FnXML?

  FnXML parses XML documents into lazy streams of events (start element, end element,
  characters, etc.) that flow through a composable pipeline of transformation and
  validation components. This architecture provides:

  - **Constant memory usage** - Process multi-gigabyte files with minimal memory
  - **Lazy evaluation** - Parse only what you need with early termination support
  - **Composable pipelines** - Chain transformations, validations, and conversions
  - **Multiple paradigms** - Use DOM (tree), SAX (push), or StAX (pull) APIs on the same stream
  - **High performance** - Macro-generated parsers with zero-copy binary processing

  ## Standards Implemented

  - **W3C XML 1.0 (Fifth Edition)**: https://www.w3.org/TR/xml/
  - **W3C Namespaces in XML 1.0**: https://www.w3.org/TR/xml-names/

  The library supports both Edition 4 (strict character validation) and Edition 5
  (permissive Unicode) parsing modes.

  ## Architecture Philosophy

  FnXML uses an **event streaming model** where XML processing flows through stages:

  ```
  XML Input
     │
     ▼
  Parser (FnXML.Parser)
     │
     ├─► Events: {:start_element, "root", [], 1, 0, 1}
     │           {:characters, "content", 1, 6, 7}
     │           {:end_element, "root", 1, 13, 14}
     ▼
  Transform Components (optional)
     │
     ├─► FnXML.Namespaces.resolve()      - Resolve namespace URIs
     ├─► FnXML.Event.Transform.*         - Normalize, filter, modify
     ├─► FnXML.Event.Validate.*          - Validation layers
     ▼
  Consumer (your code)
     │
     ├─► FnXML.API.DOM.build()           - Build in-memory tree
     ├─► FnXML.API.SAX.dispatch()        - Callback-based processing
     ├─► FnXML.API.StAX.Reader.new()     - Cursor-based navigation
     └─► Enum.to_list() / Enum.reduce()  - Direct stream consumption
  ```

  Each component receives events, processes them, and emits new events downstream.
  This enables building complex XML processing pipelines from simple, focused
  components.

  ## Module Overview

  This module (`FnXML`) provides utility functions for working with XML event streams
  produced by `FnXML.Parser`. For parsing, use `FnXML.Parser.parse/2` directly or
  the `FnXML.parse/2` alias.

  ## API Overview

  | Function | Description |
  |----------|-------------|
  | `parse/1` or `parse/2` | Alias to `FnXML.Parser.parse/2` |
  | `halt_on_error/1` | Stop stream on first parse error |
  | `log_on_error/2` | Log errors while passing through |
  | `check_errors/1` | Check for parse errors in event list |
  | `position/1` | Convert location tuple to line/column |

  ## Event Types

  The parser emits these event types with flat position arguments:

  | Event | Description |
  |-------|-------------|
  | `{:start_document, nil}` | Document start |
  | `{:end_document, nil}` | Document end |
  | `{:start_element, name, attrs, line, ls, pos}` | Opening tag with attributes |
  | `{:end_element, name, line, ls, pos}` | Closing tag |
  | `{:characters, content, line, ls, pos}` | Text content |
  | `{:space, content, line, ls, pos}` | Whitespace |
  | `{:comment, content, line, ls, pos}` | XML comment |
  | `{:prolog, "xml", attrs, line, ls, pos}` | XML declaration |
  | `{:processing_instruction, target, content, line, ls, pos}` | Processing instruction |
  | `{:dtd, content, line, ls, pos}` | DOCTYPE declaration |
  | `{:cdata, content, line, ls, pos}` | CDATA section |
  | `{:error, type, message, line, ls, pos}` | Parse error |

  ## Position Arguments

  Position is provided as three separate arguments:
  - `line` - 1-based line number
  - `ls` (line_start) - Byte offset where current line begins
  - `pos` (byte_offset) - Absolute byte position from document start

  Use `FnXML.position({line, ls, pos})` or `FnXML.Element.position(event)` to
  convert to `{line, column}` format.

  ## Examples

      # Parse to stream (use FnXML.Parser directly)
      events = FnXML.Parser.parse("<root><item>Hello</item></root>")
      # => Stream of [{:start_document, nil}, {:start_element, "root", [], 1, 0, 1}, ...]

      # Or use the alias
      events = FnXML.parse("<root>...</root>")

      # Halt on first error
      FnXML.Parser.parse(xml)
      |> FnXML.halt_on_error()
      |> Enum.to_list()

      # Fully XML Spec Compliant Parsing
      stream
      |> FnXML.Event.Transform.Utf16.to_utf8()
      |> FnXML.Event.Transform.Normalize.line_endings_stream()
      |> FnXML.Parser.parse()
      |> FnXML.Event.Validate.well_formed()
      |> FnXML.Event.Validate.attributes()
      |> FnXML.Event.Validate.comments()
      |> FnXML.Event.Validate.namespaces()
  """

  require Logger

  @doc """
  Alias to `FnXML.Parser.parse/2`.

  Parse XML from a binary string or stream. See `FnXML.Parser.parse/2` for details.

  ## Examples

      # Parse a string
      FnXML.parse("<root>Hello</root>")
      |> Enum.to_list()

      # Parse a stream
      File.stream!("data.xml")
      |> FnXML.parse()
      |> Enum.to_list()
  """
  defdelegate parse(source), to: FnXML.Parser
  defdelegate parse(source, opts), to: FnXML.Parser

  @doc """
  Halt the stream when an error event is encountered.

  When an `{:error, type, message, line, ls, pos}` event is seen, the stream
  emits that error event and then halts. Useful for fail-fast parsing where
  you want to stop processing on the first parse error.

  ## Parameters

  - `events` - Enumerable of XML events

  ## Returns

  A stream that halts after the first error.

  ## Examples

      # Stop on first error
      FnXML.Parser.parse(malformed_xml)
      |> FnXML.halt_on_error()
      |> Enum.to_list()
      # => [...events..., {:error, :syntax, "Expected '>'", 3, 20, 45}]

      # Combine with validators
      FnXML.Parser.parse(xml)
      |> FnXML.Event.Validate.well_formed()
      |> FnXML.halt_on_error()
      |> Enum.to_list()

  """
  @spec halt_on_error(Enumerable.t()) :: Enumerable.t()
  def halt_on_error(events) do
    Stream.transform(events, :cont, fn
      # 6-tuple error format (from parser)
      {:error, _, _, _, _, _} = error, :cont ->
        {[error], :halt}

      # 3-tuple error format (normalized)
      {:error, _, _} = error, :cont ->
        {[error], :halt}

      _event, :halt ->
        {:halt, :halt}

      event, :cont ->
        {[event], :cont}
    end)
  end

  @doc """
  Log error events to the console while passing them through.

  When an `{:error, type, message, line, ls, pos}` event is seen, it logs a warning with
  the error details and then passes the event through unchanged. The stream
  continues processing after errors.

  ## Parameters

  - `events` - Enumerable of XML events
  - `opts` - Options (optional)
    - `:level` - Log level (`:debug`, `:info`, `:warning`, `:error`). Default: `:warning`
    - `:prefix` - Prefix for log messages. Default: `"XML parse error"`

  ## Returns

  A stream with errors logged.

  ## Examples

      # Log errors as warnings (default)
      FnXML.Parser.parse(xml)
      |> FnXML.log_on_error()
      |> Enum.to_list()
      # Logs: [warning] XML parse error at line 3, column 5: Expected '>'

      # Log errors at error level with custom prefix
      FnXML.Parser.parse(xml)
      |> FnXML.log_on_error(level: :error, prefix: "Parse failure")
      |> Enum.to_list()

  """
  @spec log_on_error(Enumerable.t(), keyword()) :: Enumerable.t()
  def log_on_error(events, opts \\ []) do
    level = Keyword.get(opts, :level, :warning)
    prefix = Keyword.get(opts, :prefix, "XML parse error")

    Stream.map(events, fn
      # 6-tuple error format (from parser)
      {:error, _type, message, line, line_start, byte_offset} = event ->
        column = byte_offset - line_start
        Logger.log(level, "#{prefix} at line #{line}, column #{column}: #{message}")
        event

      # 3-tuple error format (normalized)
      {:error, message, {line, line_start, byte_offset}} = event ->
        column = byte_offset - line_start
        Logger.log(level, "#{prefix} at line #{line}, column #{column}: #{message}")
        event

      event ->
        event
    end)
  end

  @doc """
  Check if the event stream contains any parse errors.

  ## Parameters

  - `events` - List or enumerable of XML events

  ## Returns

  - `{:ok, events}` if no errors found
  - `{:error, errors}` if errors found, where errors is a list of error tuples

  ## Examples

      case FnXML.check_errors(FnXML.parse(xml)) do
        {:ok, events} ->
          # Process valid XML
        {:error, errors} ->
          Enum.each(errors, fn {:error, _type, msg, line, _ls, _pos} ->
            IO.puts("Line \#{line}: \#{msg}")
          end)
      end

  """
  @spec check_errors(Enumerable.t()) :: {:ok, [tuple()]} | {:error, [tuple()]}
  def check_errors(events) when is_list(events) do
    errors =
      Enum.filter(events, fn
        # 6-tuple format (from parser)
        {:error, _, _, _, _, _} -> true
        # 3-tuple format (normalized)
        {:error, _, _} -> true
        _ -> false
      end)

    if errors == [] do
      {:ok, events}
    else
      {:error, errors}
    end
  end

  def check_errors(events) do
    events
    |> Enum.to_list()
    |> check_errors()
  end

  @doc """
  Get the position (line, column) from a location tuple.

  ## Parameters

  - `loc` - Location tuple `{line, line_start, byte_offset}`

  ## Returns

  `{line, column}` tuple with 1-based line and 0-based column.

  ## Examples

      {:start_element, "element", [], loc} = event
      {line, column} = FnXML.position(loc)
      IO.puts("Element at line \#{line}, column \#{column}")

  """
  @spec position({integer(), integer(), integer()}) :: {integer(), integer()}
  def position({line, line_start, byte_offset}) do
    {line, byte_offset - line_start}
  end
end
