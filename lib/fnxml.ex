defmodule FnXML do
  @moduledoc """
  Unified XML parsing interface for FnXML.

  Provides convenient functions for parsing XML documents into event streams.
  This module offers a high-level API for common XML processing tasks, built on
  top of the streaming `FnXML.Parser`.

  ## Specifications

  - W3C XML 1.0 (Fifth Edition): https://www.w3.org/TR/xml/
  - W3C Namespaces in XML 1.0: https://www.w3.org/TR/xml-names/

  ## API Overview

  | Function | Description |
  |----------|-------------|
  | `parse/1` | Parse XML string to list of events (eager) |
  | `parse_stream/1` | Parse XML string to lazy stream (memory efficient) |
  | `halt_on_error/1` | Stop stream on first parse error |
  | `log_on_error/2` | Log errors while passing through |
  | `filter_whitespace/1` | Remove whitespace-only text events |
  | `open_tags/1` | Extract only opening tag events |
  | `text_content/1` | Extract text content as strings |
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

      # Parse to list
      events = FnXML.parse("<root><item>Hello</item></root>")
      # => [{:start_document, nil}, {:start_element, "root", [], 1, 0, 1}, ...]

      # Parse as stream (lazy evaluation)
      FnXML.parse_stream("<root>...</root>")
      |> Stream.filter(fn {:start_element, _, _, _, _, _} -> true; _ -> false end)
      |> Enum.to_list()

      # Halt on first error
      FnXML.parse_stream(xml)
      |> FnXML.halt_on_error()
      |> Enum.to_list()

      # Fully XML Spec Compliant Parsing
      stream
      |> FnXML.Transform.Utf16.to_utf8()                          # Ensure UTF-16 will work
      |> FnXML.Transform.Normalize.line_endings_stream()  # convert /r, /r/n -> /n
      |> FnXML.parse_stream()                           # Generate a stream of XML events (validates characters)
      |> FnXML.Validate.well_formed()                   # validate that open/close tags are properly matched
      |> FnXML.Validate.attributes()                    # validate that attributes are unique
      |> FnXML.Validate.comments()                      # Ensure comments don't have '--' in them
      |> FnXML.Validate.namespaces()                    # Ensure namespace prefixes are properly declared
  """

  require Logger

  @doc """
  Parse an XML string into a list of events.

  This is the simplest way to parse XML - it eagerly consumes the entire
  document and returns all events as a list.

  ## Parameters

  - `xml` - The XML document as a binary string

  ## Returns

  A list of event tuples.

  ## Examples

      iex> FnXML.parse("<root>Hello</root>")
      [
        {:start_document, nil},
        {:start_element, "root", [], 1, 0, 1},
        {:characters, "Hello", 1, 0, 6},
        {:end_element, "root", 1, 0, 12},
        {:end_document, nil}
      ]

      iex> FnXML.parse("<item attr=\\"value\\"/>")
      [
        {:start_document, nil},
        {:start_element, "item", [{"attr", "value"}], 1, 0, 1},
        {:end_element, "item", 1, 0, 1},
        {:end_document, nil}
      ]

  """
  @spec parse(binary()) :: [tuple()]
  def parse(xml) when is_binary(xml) do
    xml
    |> FnXML.Parser.parse()
    |> Enum.to_list()
  end

  @doc """
  Parse an XML string into a lazy stream of events.

  Events are generated on-demand as you consume the stream, making this
  memory-efficient for large documents. Supports early termination with
  functions like `Enum.take/2`.

  ## Parameters

  - `xml` - The XML document as a binary string

  ## Returns

  A `Stream` of event tuples.

  ## Examples

      # Lazy evaluation - only parses as needed
      FnXML.parse_stream(large_xml)
      |> Enum.take(10)

      # Stream transformations
      FnXML.parse_stream(xml)
      |> Stream.filter(fn {:characters, _, _, _, _} -> true; _ -> false end)
      |> Stream.map(fn {:characters, content, _, _, _} -> content end)
      |> Enum.to_list()

      # Find first matching element
      FnXML.parse_stream(xml)
      |> Enum.find(fn {:start_element, "target", _, _, _, _} -> true; _ -> false end)

  """
  @spec parse_stream(binary()) :: Enumerable.t()
  def parse_stream(xml) when is_binary(xml) do
    FnXML.Parser.stream(xml)
  end

  @doc """
  Parse XML with full validation pipeline for strict XML 1.0 compliance.

  This function applies comprehensive validation checks including:
  - Well-formedness constraints (tag matching, unique attributes)
  - Comment validation (no '--' within comments)
  - Namespace validation (proper prefix declarations)

  For most use cases, the standard `parse/1` or `parse_stream/1` functions
  are sufficient. Use this function when you need strict XML 1.0 conformance
  or when validating untrusted XML input.

  ## Parameters

  - `xml` - The XML document as a binary string
  - `opts` - Options (optional)
    - `:halt_on_error` - Stop on first error (default: false)
    - `:validate_namespaces` - Enable namespace validation (default: true)

  ## Returns

  A list of event tuples with validation errors included as `{:error, ...}` events.

  ## Examples

      # Strict validation
      case FnXML.parse_compliant(xml) do
        {:ok, events} ->
          # All validation passed
          process_events(events)
        {:error, errors} ->
          # Validation failures detected
          report_errors(errors)
      end

      # Get events with errors inline (don't check)
      events = FnXML.parse_compliant(xml, check: false)

  """
  @spec parse_compliant(binary(), keyword()) :: {:ok, [tuple()]} | {:error, [tuple()]} | [tuple()]
  def parse_compliant(xml, opts \\ []) when is_binary(xml) do
    halt? = Keyword.get(opts, :halt_on_error, false)
    validate_ns? = Keyword.get(opts, :validate_namespaces, true)
    check? = Keyword.get(opts, :check, true)
    on_error = Keyword.get(opts, :on_error, :emit)

    stream =
      xml
      |> FnXML.Parser.stream()
      |> FnXML.Validate.character_references(on_error: on_error)
      |> FnXML.Validate.xml_declaration(on_error: on_error)
      |> FnXML.Validate.processing_instructions(on_error: on_error)
      |> FnXML.Validate.well_formed(on_error: on_error)
      |> FnXML.Validate.root_boundary(on_error: on_error)
      |> FnXML.Validate.attributes(on_error: on_error)
      |> FnXML.Validate.comments(on_error: on_error)

    stream =
      if validate_ns? do
        stream |> FnXML.Validate.namespaces(on_error: on_error)
      else
        stream
      end

    stream =
      if halt? do
        stream |> halt_on_error()
      else
        stream
      end

    events = Enum.to_list(stream)

    if check? do
      check_errors(events)
    else
      events
    end
  end

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
      FnXML.parse_stream(malformed_xml)
      |> FnXML.halt_on_error()
      |> Enum.to_list()
      # => [...events..., {:error, :syntax, "Expected '>'", 3, 20, 45}]

      # Combine with other stream operations
      FnXML.parse_stream(xml)
      |> FnXML.filter_whitespace()
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
      FnXML.parse_stream(xml)
      |> FnXML.log_on_error()
      |> Enum.to_list()
      # Logs: [warning] XML parse error at line 3, column 5: Expected '>'

      # Log errors at error level with custom prefix
      FnXML.parse_stream(xml)
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
  Filter out whitespace-only text events from an event stream.

  Useful for simplifying event streams when whitespace between elements
  is not significant.

  ## Parameters

  - `events` - Enumerable of XML events

  ## Returns

  A stream with whitespace-only text events removed.

  ## Examples

      FnXML.parse_stream(xml)
      |> FnXML.filter_whitespace()
      |> Enum.to_list()

  """
  @spec filter_whitespace(Enumerable.t()) :: Enumerable.t()
  def filter_whitespace(events) do
    Stream.reject(events, fn
      # 5-tuple format (from parser)
      {:characters, content, _line, _ls, _pos} -> String.trim(content) == ""
      _ -> false
    end)
  end

  @doc """
  Extract only open tag events from an event stream.

  ## Parameters

  - `events` - Enumerable of XML events

  ## Returns

  A stream of only `:start_element` events.

  ## Examples

      FnXML.parse_stream(xml)
      |> FnXML.open_tags()
      |> Enum.map(fn {:start_element, name, _, _, _, _} -> name end)
      # => ["root", "child1", "child2", ...]

  """
  @spec open_tags(Enumerable.t()) :: Enumerable.t()
  def open_tags(events) do
    Stream.filter(events, fn
      # 6-tuple format (from parser)
      {:start_element, _, _, _, _, _} -> true
      # 4-tuple format (normalized)
      {:start_element, _, _, _} -> true
      _ -> false
    end)
  end

  @doc """
  Extract text content from an event stream.

  Returns only the text content, discarding structure and location info.

  ## Parameters

  - `events` - Enumerable of XML events

  ## Returns

  A stream of text content strings.

  ## Examples

      FnXML.parse_stream("<root>Hello <b>World</b>!</root>")
      |> FnXML.text_content()
      |> Enum.join("")
      # => "Hello World!"

  """
  @spec text_content(Enumerable.t()) :: Enumerable.t()
  def text_content(events) do
    events
    |> Stream.filter(fn
      # 5-tuple format (from parser)
      {:characters, _, _, _, _} -> true
      # 3-tuple format (normalized)
      {:characters, _, _} -> true
      _ -> false
    end)
    |> Stream.map(fn
      {:characters, content, _, _, _} -> content
      {:characters, content, _} -> content
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
