# FnXML

A functional XML library for Elixir with streaming support and three standard API paradigms: DOM, SAX, and StAX.

## Architecture

```
 ┌─────────────────────────────────────────────────────────────────┐
 │                        High-Level APIs                          │
 ├─────────────────┬─────────────────────┬─────────────────────────┤
 │  FnXML.DOM      │  FnXML.SAX          │  FnXML.StAX             │
 │  (Tree)         │  (Push Callbacks)   │  (Pull Cursor)          │
 │  O(n) memory    │  O(1) memory        │  O(1) memory            │
 ├─────────────────┴─────────────────────┴─────────────────────────┤
 │                     FnXML.Stream                                │
 │            Event stream transformations & formatting            │
 ├─────────────────────────────────────────────────────────────────┤
 │  FnXML.Namespaces          │  FnXML.Stream.SimpleForm           │
 │  Namespace resolution      │  Saxy compatibility                │
 ├─────────────────────────────────────────────────────────────────┤
 │                      FnXML.Parser                               │
 │      Auto-selects: Zig NIF (>60KB) or ExBlkParser (<60KB)       │
 ├─────────────────────────────────────────────────────────────────┤
 │  FnXML.ExBlkParser         │  FnXML.FastExBlkParser             │
 │  Pure Elixir, streaming    │  Optimized variant                 │
 └─────────────────────────────────────────────────────────────────┘
```

The parser uses CPS (continuation-passing style) recursive descent for efficient tail-call optimization and minimal memory usage.

## Quick Start

```elixir
# Parse XML to DOM tree
doc = FnXML.DOM.parse("<root><child id=\"1\">Hello</child></root>")
doc.root.tag  # => "root"

# SAX callback-based parsing
defmodule CountHandler do
  use FnXML.SAX.Handler
  def start_element(_uri, _local, _qname, _attrs, count), do: {:ok, count + 1}
end
{:ok, 2} = FnXML.SAX.parse("<root><child/></root>", CountHandler, 0)

# StAX pull-based parsing
reader = FnXML.StAX.Reader.new("<root attr=\"val\"/>")
reader = FnXML.StAX.Reader.next(reader)
FnXML.StAX.Reader.local_name(reader)  # => "root"
FnXML.StAX.Reader.attribute_value(reader, nil, "attr")  # => "val"
```

## Installation

```elixir
def deps do
  [{:fnxml, "~> 0.1.0"}]
end
```

## APIs

### DOM (Document Object Model)

Build an in-memory tree representation. Best for small-to-medium documents where you need random access.

```elixir
# Parse
doc = FnXML.DOM.parse("<root><child id=\"1\">text</child></root>")

# Navigate
doc.root.tag                                    # => "root"
doc.root.children                               # => [%Element{...}]
FnXML.DOM.Element.get_attribute(elem, "id")     # => "1"

# Serialize
FnXML.DOM.to_string(doc)                        # => "<root>..."
FnXML.DOM.to_string(doc, pretty: true)          # => formatted XML

# Build programmatically
alias FnXML.DOM.Element
elem = Element.new("div", [{"class", "container"}], ["Hello"])
```

### SAX (Simple API for XML)

Push-based event callbacks. Best for large documents where you only need specific data.

```elixir
defmodule MyHandler do
  use FnXML.SAX.Handler

  @impl true
  def start_element(_uri, local_name, _qname, _attrs, state) do
    {:ok, [local_name | state]}
  end

  @impl true
  def characters(text, state) do
    {:ok, Map.update(state, :text, text, &(&1 <> text))}
  end

  @impl true
  def end_document(state) do
    {:ok, Enum.reverse(state)}
  end
end

{:ok, result} = FnXML.SAX.parse(xml, MyHandler, [])
```

**Callbacks:** `start_document/1`, `end_document/1`, `start_element/5`, `end_element/4`, `characters/2`

**Return values:** `{:ok, state}`, `{:halt, state}` (stop early), `{:error, reason}`

### StAX (Streaming API for XML)

Pull-based cursor navigation. Best for large documents with complex processing logic.

```elixir
reader = FnXML.StAX.Reader.new(xml)

# Pull events one at a time (lazy - O(1) memory)
reader = FnXML.StAX.Reader.next(reader)

# Query current event
FnXML.StAX.Reader.event_type(reader)      # => :start_element
FnXML.StAX.Reader.local_name(reader)      # => "root"
FnXML.StAX.Reader.attribute_count(reader) # => 2
FnXML.StAX.Reader.attribute_value(reader, nil, "id")  # => "123"

# Convenience methods
FnXML.StAX.Reader.start_element?(reader)  # => true
FnXML.StAX.Reader.has_next?(reader)       # => true
{text, reader} = FnXML.StAX.Reader.element_text(reader)  # read all text in element
```

**Writer for building XML:**

```elixir
xml = FnXML.StAX.Writer.new()
|> FnXML.StAX.Writer.start_document()
|> FnXML.StAX.Writer.start_element("root")
|> FnXML.StAX.Writer.attribute("id", "1")
|> FnXML.StAX.Writer.characters("Hello")
|> FnXML.StAX.Writer.end_element()
|> FnXML.StAX.Writer.to_string()
# => "<?xml version=\"1.0\"?><root id=\"1\">Hello</root>"
```

### Low-Level Stream API

Direct access to the event stream for custom processing.

```elixir
# Parse to event stream (auto-selects NIF or Elixir)
FnXML.Parser.parse("<root><child/></root>")
# => [{:start_document, nil}, {:start_element, "root", [], {1, 0, 1}}, ...]

# Stream from file (64KB chunks, lazy evaluation)
File.stream!("large.xml", [], 65536)
|> FnXML.Parser.stream()
|> Enum.to_list()

# Force specific parser backend
FnXML.Parser.stream(xml, parser: :nif)     # Force Zig NIF
FnXML.Parser.stream(xml, parser: :elixir)  # Force pure Elixir

# Direct access to block parsers
events = FnXML.ExBlkParser.parse("<root/>")
events = FnXML.FastExBlkParser.parse("<root/>")

# With namespace resolution
FnXML.Parser.parse("<root xmlns=\"http://example.org\"><child/></root>")
|> FnXML.Namespaces.resolve()
|> Enum.to_list()
# => [{:start_element, {"http://example.org", "root"}, [...], ...}, ...]

# Convert stream to XML
events
|> FnXML.Stream.to_xml()
|> Enum.join()
```

**Parser Options:**
- `:parser` - Force parser: `:nif`, `:elixir`, or `:auto` (default)
- `:threshold` - Auto-selection cutoff in bytes (default: 60KB)
- `:block_size` - For streams, hint about chunk size for auto-selection

**Event types (W3C StAX-compatible):**
- `{:start_element, tag, attrs, location}` - Start element
- `{:end_element, tag}` or `{:end_element, tag, location}` - End element
- `{:characters, content, location}` - Text content
- `{:comment, content, location}` - Comment
- `{:cdata, content, location}` - CDATA section
- `{:prolog, "xml", attrs, location}` - XML declaration
- `{:processing_instruction, target, data, location}` - Processing instruction

### Saxy Compatibility

For codebases using Saxy's SimpleForm format:

```elixir
# Decode to SimpleForm tuple
{"root", attrs, children} = FnXML.Stream.SimpleForm.decode("<root><child/></root>")

# Encode back to XML
FnXML.Stream.SimpleForm.encode({"root", [], ["text"]})

# Convert between SimpleForm and DOM
elem = FnXML.Stream.SimpleForm.to_dom({"root", [{"id", "1"}], ["text"]})
tuple = FnXML.Stream.SimpleForm.from_dom(elem)
```

## Choosing an API

| Use Case | Recommended API |
|----------|-----------------|
| Small documents, need random access | DOM |
| Large documents, extract specific data | SAX |
| Large documents, complex state machine | StAX |
| Stream transformations | Low-level Stream |
| Saxy migration/interop | SimpleForm |

## Features

- **NIF acceleration** - Optional Zig NIF for high-throughput parsing (auto-selected for large inputs)
- **Streaming parser** - Process XML incrementally without loading entire document
- **Chunk boundary handling** - Mini-block approach handles elements spanning chunk boundaries
- **Namespace support** - Full XML namespace resolution
- **Three standard APIs** - DOM, SAX, StAX for different use cases
- **Lazy evaluation** - StAX Reader uses O(1) memory
- **Location tracking** - Line/column info for error reporting
- **Saxy compatible** - SimpleForm format for easy migration
- **Disable NIF** - Set `FNXML_NIF=false` or `{:fnxml, "~> x.x", nif: false}` for pure Elixir

## License

MIT

## Contributing

Contributions welcome! Please open an issue or PR on GitHub.
