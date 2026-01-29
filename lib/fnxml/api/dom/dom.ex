defmodule FnXML.API.DOM do
  @moduledoc """
  Document Object Model (DOM) for XML.

  Provides an in-memory tree representation of XML documents with APIs
  inspired by the W3C DOM specification. The DOM loads the entire document
  into memory, enabling random access and modification of any node.

  ## Specifications

  - W3C DOM Level 1 Core: https://www.w3.org/TR/REC-DOM-Level-1/
  - W3C DOM Level 2 Core: https://www.w3.org/TR/DOM-Level-2-Core/

  ## Memory Characteristics

  DOM uses O(n) memory where n is the document size. Use `FnXML.API.SAX` or
  `FnXML.API.StAX` for large documents where streaming is preferred.

  ## Usage

      # Build DOM from parser stream (recommended)
      doc = FnXML.Parser.parse("<root><child id='1'>text</child></root>")
            |> FnXML.API.DOM.build()
      doc.root.tag  # => "root"

      # With validation/transformation pipeline
      doc = File.stream!("data.xml")
            |> FnXML.Parser.parse()
            |> FnXML.Event.Validate.well_formed()
            |> FnXML.Namespaces.resolve()
            |> FnXML.API.DOM.build()

      # Quick parse (convenience, skips pipeline)
      doc = FnXML.API.DOM.parse("<root><child id='1'>text</child></root>")

      # Serialize back to XML (convert to events, then to string)
      doc
      |> FnXML.API.DOM.to_event()
      |> FnXML.Event.to_iodata()
      |> IO.iodata_to_binary()
      # => "<root><child id=\"1\">text</child></root>"

  ## Node Types

  The DOM uses these node type constants (compatible with W3C DOM):

  - `element_node/0` (1) - Element nodes
  - `text_node/0` (3) - Text content
  - `cdata_node/0` (4) - CDATA sections
  - `comment_node/0` (8) - Comments
  - `document_node/0` (9) - Document root
  - `document_fragment_node/0` (11) - Document fragments

  ## Related Modules

  - `FnXML.API.DOM.Document` - Document struct and operations
  - `FnXML.API.DOM.Element` - Element struct and operations
  - `FnXML.API.DOM.Builder` - Build DOM from events

  ## Comparison with SimpleForm

  `FnXML.API.DOM` uses structs while `FnXML.Event.SimpleForm` uses tuples:

      # DOM
      %FnXML.API.DOM.Element{tag: "div", attributes: [{"id", "1"}], children: ["text"]}

      # SimpleForm
      {"div", [{"id", "1"}], ["text"]}

  DOM provides richer functionality (namespace support, element methods),
  while SimpleForm is simpler and compatible with the Saxy library.
  """

  alias FnXML.API.DOM.{Builder, Document, Element}

  # Node type constants (W3C DOM compatible)
  @element_node 1
  @text_node 3
  @cdata_node 4
  @comment_node 8
  @document_node 9
  @document_fragment_node 11

  @doc "Node type constant for elements (1)"
  def element_node, do: @element_node

  @doc "Node type constant for text (3)"
  def text_node, do: @text_node

  @doc "Node type constant for CDATA sections (4)"
  def cdata_node, do: @cdata_node

  @doc "Node type constant for comments (8)"
  def comment_node, do: @comment_node

  @doc "Node type constant for documents (9)"
  def document_node, do: @document_node

  @doc "Node type constant for document fragments (11)"
  def document_fragment_node, do: @document_fragment_node

  @doc """
  Build DOM from an FnXML event stream.

  This is the primary way to create a DOM from parsed XML, enabling
  stream transformations before building the tree.

  ## Options

  - `:include_comments` - Include comment nodes (default: false)
  - `:include_prolog` - Parse XML declaration (default: true)

  ## Examples

      iex> FnXML.Parser.parse("<root>text</root>")
      ...> |> FnXML.API.DOM.build()
      ...> |> then(& &1.root.tag)
      "root"

      # With validation
      FnXML.Parser.parse(xml)
      |> FnXML.Event.Validate.well_formed()
      |> FnXML.API.DOM.build()

      # With namespace resolution
      FnXML.Parser.parse(xml)
      |> FnXML.Namespaces.resolve()
      |> FnXML.API.DOM.build()
  """
  @spec build(Enumerable.t(), keyword()) :: Document.t()
  def build(stream, opts \\ []) do
    Builder.from_stream(stream, opts)
  end

  @doc """
  Convert DOM to an FnXML event stream.

  Generates XML events from a DOM tree. Use with `FnXML.Event.to_iodata/2`
  for serialization to iodata/string.

  ## Examples

      # Convert to event stream
      iex> FnXML.API.DOM.parse("<root>text</root>")
      ...> |> FnXML.API.DOM.to_event()
      ...> |> Enum.to_list()
      ...> |> Enum.map(&elem(&1, 0))
      [:start_element, :characters, :end_element]

      # Serialize to string
      doc
      |> FnXML.API.DOM.to_event()
      |> FnXML.Event.to_iodata()
      |> IO.iodata_to_binary()

      # Serialize to iodata (more efficient for I/O)
      doc
      |> FnXML.API.DOM.to_event()
      |> FnXML.Event.to_iodata()
  """
  @spec to_event(Document.t() | Element.t()) :: Enumerable.t()
  def to_event(node) do
    Stream.resource(
      fn -> init_event_stream(node) end,
      &emit_next_event/1,
      fn _ -> :ok end
    )
  end

  # Initialize stream state based on node type
  defp init_event_stream(%Document{root: nil}), do: []
  defp init_event_stream(%Document{root: root}), do: [root]
  defp init_event_stream(%Element{} = elem), do: [elem]

  # Stream emission - nothing left
  defp emit_next_event([]), do: {:halt, []}

  # Emit element - open tag, queue content and close
  defp emit_next_event([%Element{} = elem | rest]) do
    qname = Element.qualified_name(elem)
    open = {:start_element, qname, elem.attributes, nil}
    new_queue = elem.children ++ [{:close_tag, qname}] ++ rest
    {[open], new_queue}
  end

  # Emit close tag marker
  defp emit_next_event([{:close_tag, tag} | rest]) do
    {[{:end_element, tag}], rest}
  end

  # Emit text content
  defp emit_next_event([text | rest]) when is_binary(text) do
    {[{:characters, text, nil}], rest}
  end

  # Emit comment
  defp emit_next_event([{:comment, content} | rest]) do
    {[{:comment, content, nil}], rest}
  end

  # Emit CDATA
  defp emit_next_event([{:cdata, content} | rest]) do
    {[{:cdata, content, nil}], rest}
  end

  # Emit processing instruction
  defp emit_next_event([{:pi, target, data} | rest]) do
    {[{:processing_instruction, target, data, nil}], rest}
  end

  # Skip nil values
  defp emit_next_event([nil | rest]) do
    emit_next_event(rest)
  end

  # Convenience aliases for creating nodes

  @doc """
  Create a new element.

  ## Examples

      iex> FnXML.API.DOM.element("div", [{"class", "container"}], ["Hello"])
      %FnXML.API.DOM.Element{tag: "div", attributes: [{"class", "container"}], children: ["Hello"]}
  """
  @spec element(String.t(), [{String.t(), String.t()}], [Element.child()]) :: Element.t()
  def element(tag, attributes \\ [], children \\ []) do
    Element.new(tag, attributes, children)
  end

  @doc """
  Create a new document.

  ## Examples

      iex> root = FnXML.API.DOM.element("html")
      iex> doc = FnXML.API.DOM.document(root)
      iex> doc.root.tag
      "html"
  """
  @spec document(Element.t(), keyword()) :: Document.t()
  def document(root, opts \\ []) do
    Document.new(root, opts)
  end
end
