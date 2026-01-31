#!/usr/bin/env elixir

# Simple XML parsing example using FnXML

Mix.install([{:fnxml, path: "."}])

xml = """
<?xml version="1.0" encoding="UTF-8"?>
<catalog>
  <book id="1">
    <title>The Great Adventure</title>
    <author>Jane Doe</author>
    <price currency="USD">29.99</price>
  </book>
  <book id="2">
    <title>Mystery Manor</title>
    <author>John Smith</author>
  </book>
</catalog>
"""

IO.puts("=== Input XML ===")
IO.puts(xml)

IO.puts("\n=== Parsed Events ===\n")

# Parse XML to stream and display events
FnXML.parse_stream(xml)
|> Enum.each(&IO.inspect/1)

IO.puts("\n=== DOM Parsing ===\n")

# Build a DOM tree
doc = FnXML.DOM.parse(xml)
IO.puts("Root element: #{doc.root.tag}")
IO.puts("Children count: #{length(doc.root.children)}")
IO.puts("\nFirst book:")
[first_book | _] = doc.root.children
IO.puts("  Tag: #{first_book.tag}")
IO.puts("  ID: #{FnXML.DOM.Element.get_attribute(first_book, "id")}")

IO.puts("\n=== SAX Parsing ===\n")

defmodule BookCounter do
  @behaviour FnXML.SAX

  @impl true
  def start_document(state), do: {:ok, state}

  @impl true
  def end_document(state), do: {:ok, state}

  @impl true
  def start_element(_uri, "book", _qname, _attrs, state) do
    {:ok, Map.update(state, :book_count, 1, &(&1 + 1))}
  end

  def start_element(_uri, _local, _qname, _attrs, state), do: {:ok, state}

  @impl true
  def end_element(_uri, _local, _qname, state), do: {:ok, state}

  @impl true
  def characters(_chars, state), do: {:ok, state}
end

{:ok, result} = FnXML.SAX.parse(xml, BookCounter, %{})
IO.puts("Number of books: #{result.book_count}")

IO.puts("\n=== StAX Parsing (Pull-based) ===\n")

# Create a StAX reader and iterate through events
reader = FnXML.StAX.create_reader(xml)

defmodule StAXExample do
  alias FnXML.StAX.Reader

  def collect_titles(reader, titles \\ []) do
    if Reader.has_next?(reader) do
      reader = Reader.next(reader)

      # When we encounter a <title> element, collect its text content
      titles =
        if Reader.start_element?(reader) and Reader.local_name(reader) == "title" do
          reader = Reader.next(reader)

          if Reader.characters?(reader) do
            [Reader.text(reader) | titles]
          else
            titles
          end
        else
          titles
        end

      collect_titles(reader, titles)
    else
      Enum.reverse(titles)
    end
  end
end

titles = StAXExample.collect_titles(reader)
IO.puts("Book titles found:")
Enum.each(titles, fn title -> IO.puts("  - #{title}") end)

IO.puts("\n=== Comparison of Approaches ===\n")
IO.puts("""
1. Stream/Events: Lazy enumerable - best for filtering and transforming
2. DOM: Tree structure - best for random access and modification
3. SAX: Push-based callbacks - best for event-driven processing
4. StAX: Pull-based iteration - best for application-controlled parsing
""")
