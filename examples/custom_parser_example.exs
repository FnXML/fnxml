# Custom Parser Examples
#
# This file demonstrates how to create custom parser modules with specific
# event filtering and options using FnXML.Parser.Generator.

# Example 1: Minimal Parser (no whitespace or comments)
# Useful for parsing XML where you only care about structure and content,
# not formatting or documentation.

defmodule MinimalParser do
  @moduledoc """
  Custom parser that skips whitespace-only text nodes and comments.
  Perfect for parsing configuration files where formatting doesn't matter.
  """
  use FnXML.Parser.Generator,
    edition: 5,
    disable: [:space, :comment]
end

# Example 2: Structure Only Parser
# Only parses element structure, ignoring all text content.
# Useful for analyzing document structure without caring about content.

defmodule StructureOnlyParser do
  @moduledoc """
  Parser that only emits element start/end events.
  Useful for schema validation or structure analysis.
  """
  use FnXML.Parser.Generator,
    edition: 5,
    disable: [:characters, :space, :comment, :cdata]
end

# Example 3: Fast Parser (no position tracking)
# Maximum performance when you don't need line/column information.

defmodule FastParser do
  @moduledoc """
  Parser optimized for speed by disabling position tracking.
  Use when parsing large files and errors are rare.
  """
  use FnXML.Parser.Generator,
    edition: 5,
    positions: :none
end

# Example 4: Content Parser (structure + text only)
# Skips everything except elements and their text content.

defmodule ContentParser do
  @moduledoc """
  Parser that captures elements and text, but skips metadata.
  Perfect for extracting content from documents.
  """
  use FnXML.Parser.Generator,
    edition: 5,
    disable: [:space, :comment, :prolog, :processing_instruction]
end

# Usage Examples
IO.puts("\n=== Custom Parser Examples ===\n")

xml = """
<?xml version="1.0"?>
<!-- This is a comment -->
<root id="1">
  <child>Hello World</child>
  <empty/>
</root>
"""

# Standard parser (all events)
IO.puts("Standard Parser Events:")
FnXML.Parser.parse(xml)
|> Enum.each(fn event ->
  IO.puts("  #{inspect(elem(event, 0))}")
end)

# Minimal parser (no space, no comments)
IO.puts("\nMinimal Parser Events (no :space, no :comment):")
MinimalParser.stream([xml])
|> Enum.each(fn event ->
  IO.puts("  #{inspect(elem(event, 0))}")
end)

# Structure only parser
IO.puts("\nStructure Only Parser Events (elements only):")
StructureOnlyParser.stream([xml])
|> Enum.each(fn event ->
  IO.puts("  #{inspect(elem(event, 0))}")
end)

# Content parser
IO.puts("\nContent Parser Events (structure + text):")
ContentParser.stream([xml])
|> Enum.each(fn event ->
  IO.puts("  #{inspect(elem(event, 0))}")
end)

IO.puts("\n=== Performance Comparison ===\n")

# Generate some test XML
large_xml = """
<root>
  #{for i <- 1..100 do
    "<item id=\"#{i}\">Content #{i}</item>"
  end |> Enum.join("\n  ")}
</root>
"""

# Benchmark different parsers
{time_standard, _} = :timer.tc(fn ->
  FnXML.Parser.parse(large_xml) |> Enum.to_list()
end)

{time_minimal, _} = :timer.tc(fn ->
  MinimalParser.stream([large_xml]) |> Enum.to_list()
end)

{time_fast, _} = :timer.tc(fn ->
  FastParser.stream([large_xml]) |> Enum.to_list()
end)

{time_structure, _} = :timer.tc(fn ->
  StructureOnlyParser.stream([large_xml]) |> Enum.to_list()
end)

IO.puts("Standard Parser:      #{time_standard} μs")
IO.puts("Minimal Parser:       #{time_minimal} μs (#{Float.round(time_minimal / time_standard * 100, 1)}%)")
IO.puts("Fast Parser:          #{time_fast} μs (#{Float.round(time_fast / time_standard * 100, 1)}%)")
IO.puts("Structure Only:       #{time_structure} μs (#{Float.round(time_structure / time_standard * 100, 1)}%)")

IO.puts("\n=== Using FnXML.Parser.generate/1 ===\n")

# Get pre-built parser modules at runtime
parser_ed5 = FnXML.Parser.generate(5)
parser_ed4 = FnXML.Parser.generate(4)

IO.puts("Edition 5 parser: #{inspect(parser_ed5)}")
IO.puts("Edition 4 parser: #{inspect(parser_ed4)}")

# Use them directly
events_ed5 = parser_ed5.parse("<root/>") |> Enum.to_list()
IO.puts("\nEdition 5 events: #{inspect(events_ed5)}")
