# Custom Parser Guide

FnXML allows you to create custom parser modules at compile time with specific event filtering and options for improved performance.

## Quick Start

```elixir
defmodule MyApp.MinimalParser do
  use FnXML.Parser.Generator,
    edition: 5,
    disable: [:space, :comment]
end

# Use your custom parser
MyApp.MinimalParser.parse("<root>  text  </root>")
|> Enum.to_list()
# Events: no :space or :comment events
```

## Generator Options

When using `FnXML.Parser.Generator`, the following options are available:

### Required Options

- **`:edition`** - XML 1.0 edition (4 or 5)
  - Edition 5: Permissive character validation (default)
  - Edition 4: Strict character validation per XML 1.0 spec Appendix B

### Optional Options

#### `:disable` - Event Type Filtering

Skip specific event types at compile time for improved performance:

- **`:space`** - Skip whitespace-only text nodes
- **`:comment`** - Skip XML comments (`<!-- ... -->`)
- **`:cdata`** - Skip CDATA sections (`<![CDATA[...]]>`)
- **`:prolog`** - Skip XML declarations (`<?xml ...?>`)
- **`:characters`** - Skip all text content
- **`:processing_instruction`** - Skip processing instructions (`<?target data?>`)

Example:
```elixir
disable: [:space, :comment, :cdata]
```

#### `:positions` - Position Tracking

Control how much position information is included in events:

- **`:full`** (default) - Include line number, line start, and absolute byte position
- **`:line_only`** - Include only line numbers (faster)
- **`:none`** - No position data (fastest, but no error location info)

Example:
```elixir
positions: :none
```

## Common Use Cases

### 1. Minimal Parser (Configuration Files)

Skip whitespace and comments for parsing configuration files where formatting doesn't matter:

```elixir
defmodule MyApp.ConfigParser do
  use FnXML.Parser.Generator,
    edition: 5,
    disable: [:space, :comment]
end
```

**Performance:** ~40% faster than standard parser

### 2. Structure-Only Parser (Schema Validation)

Parse only element structure, ignoring all text content:

```elixir
defmodule MyApp.StructureParser do
  use FnXML.Parser.Generator,
    edition: 5,
    disable: [:characters, :space, :comment, :cdata]
end
```

**Use cases:**
- Schema validation
- Document structure analysis
- Element counting and statistics

### 3. Fast Parser (Large Files)

Maximum performance when you don't need position tracking:

```elixir
defmodule MyApp.FastParser do
  use FnXML.Parser.Generator,
    edition: 5,
    positions: :none
end
```

**Performance:** ~50% faster than standard parser with position tracking

### 4. Content Parser (Text Extraction)

Extract elements and text while skipping metadata:

```elixir
defmodule MyApp.ContentParser do
  use FnXML.Parser.Generator,
    edition: 5,
    disable: [:space, :comment, :prolog, :processing_instruction]
end
```

**Use cases:**
- Content extraction
- Text indexing
- Data migration

### 5. Strict Parser (Edition 4)

Use XML 1.0 Fourth Edition for strict character validation:

```elixir
defmodule MyApp.StrictParser do
  use FnXML.Parser.Generator,
    edition: 4
end
```

**Use cases:**
- Validating legacy XML documents
- Ensuring maximum compatibility
- Standards compliance testing

## Performance Comparison

Based on parsing a document with 100 elements:

| Parser Configuration | Relative Performance | Use Case |
|---------------------|---------------------|----------|
| Standard (full) | 100% (baseline) | General purpose |
| Minimal (no space/comments) | ~60% | Config files |
| Fast (no positions) | ~60% | Large files, no errors |
| Structure only | ~55% | Schema validation |
| Combined (minimal + fast) | ~40% | Maximum performance |

## Runtime Access

Get pre-built parser modules at runtime:

```elixir
# Get Edition 5 parser
parser = FnXML.Parser.generate(5)
parser.parse("<root/>")

# Get Edition 4 parser
parser = FnXML.Parser.generate(4)
parser.parse("<root/>")
```

Note: `FnXML.Parser.generate/1` returns pre-compiled parser modules (Edition4 or Edition5). For custom parsers with specific options, define them at compile time using `use FnXML.Parser.Generator`.

## Introspection

Custom parsers expose their configuration:

```elixir
defmodule MyParser do
  use FnXML.Parser.Generator,
    edition: 5,
    disable: [:space, :comment]
end

MyParser.edition()        # => 5
MyParser.disabled()       # => [:space, :comment]
MyParser.position_mode()  # => :full
```

## Integration with Pipelines

Custom parsers work seamlessly with all FnXML APIs:

```elixir
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
```

## Best Practices

1. **Profile First**: Use the standard parser first, then create custom parsers if performance is an issue

2. **Match Use Case**: Choose options that match your specific use case:
   - Config files → disable `:space`, `:comment`
   - Schema validation → disable all content events
   - Large files → set `positions: :none`

3. **Module Naming**: Use descriptive names like `ConfigParser`, `StructureParser`, `FastParser`

4. **Document Purpose**: Add `@moduledoc` explaining why the parser has specific options

5. **Test Both**: Test with both standard and custom parsers during development

## Example: Complete Custom Parser Module

```elixir
defmodule MyApp.Parsers.Minimal do
  @moduledoc """
  Optimized XML parser for configuration files.

  Skips whitespace-only text nodes and comments for faster parsing
  of configuration files where formatting and documentation don't matter.

  Approximately 40% faster than the standard parser.
  """

  use FnXML.Parser.Generator,
    edition: 5,
    disable: [:space, :comment]

  @doc """
  Parse XML configuration file.

  ## Example

      iex> xml = "<config><setting>value</setting></config>"
      iex> #{__MODULE__}.parse(xml) |> Enum.to_list()
      # Only structural and content events
  """
  def parse(xml) when is_binary(xml) do
    stream([xml])
  end
end
```

## See Also

- `FnXML.Parser` - Main parser API
- `FnXML.Parser.Generator` - Parser generator module
- [examples/custom_parser_example.exs](examples/custom_parser_example.exs) - Working examples
