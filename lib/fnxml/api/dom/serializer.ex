defmodule FnXML.API.DOM.Serializer do
  @moduledoc """
  Serialize DOM trees to XML strings or event streams.

  ## Examples

      doc = FnXML.API.DOM.parse("<root><child/></root>")
      FnXML.API.DOM.Serializer.to_string(doc)
      # => "<root><child/></root>"

      FnXML.API.DOM.Serializer.to_string(doc, pretty: true)
      # => "<root>\\n  <child/>\\n</root>"
  """

  alias FnXML.API.DOM.{Document, Element}

  @doc """
  Serialize DOM to XML string.

  ## Options

  - `:pretty` - Format with indentation (default: false)
  - `:indent` - Indentation spaces or string (default: 2)
  - `:xml_declaration` - Include XML declaration (default: false)

  ## Examples

      iex> elem = FnXML.API.DOM.Element.new("root", [], ["text"])
      iex> FnXML.API.DOM.Serializer.to_string(elem)
      "<root>text</root>"
  """
  @spec to_string(Document.t() | Element.t(), keyword()) :: String.t()
  def to_string(node, opts \\ []) do
    node
    |> to_iodata(opts)
    |> IO.iodata_to_binary()
  end

  @doc """
  Serialize DOM to iodata (more efficient for large documents).
  """
  @spec to_iodata(Document.t() | Element.t(), keyword()) :: iodata()
  def to_iodata(node, opts \\ []) do
    pretty = Keyword.get(opts, :pretty, false)
    indent = Keyword.get(opts, :indent, 2)
    xml_decl = Keyword.get(opts, :xml_declaration, false)

    indent_str =
      cond do
        is_binary(indent) -> indent
        is_integer(indent) -> String.duplicate(" ", indent)
        true -> "  "
      end

    state = %{
      pretty: pretty,
      indent: indent_str,
      depth: 0
    }

    case node do
      %Document{} = doc ->
        serialize_document(doc, state, xml_decl)

      %Element{} = elem ->
        serialize_element(elem, state)
    end
  end

  @doc """
  Convert DOM to an FnXML event stream.

  ## Examples

      iex> elem = FnXML.API.DOM.Element.new("root", [], ["text"])
      iex> FnXML.API.DOM.Serializer.to_stream(elem) |> Enum.to_list()
      [{:start_element, "root", [], nil}, {:characters, "text", nil}, {:end_element, "root"}]
  """
  @spec to_stream(Document.t() | Element.t()) :: Enumerable.t()
  def to_stream(node) do
    Stream.resource(
      fn -> init_stream(node) end,
      &emit_next/1,
      fn _ -> :ok end
    )
  end

  # Initialize stream state based on node type
  defp init_stream(%Document{root: nil}), do: []
  defp init_stream(%Document{root: root}), do: [root]
  defp init_stream(%Element{} = elem), do: [elem]

  # Stream emission - nothing left
  defp emit_next([]), do: {:halt, []}

  # Emit element - open tag, queue content and close
  defp emit_next([%Element{} = elem | rest]) do
    qname = Element.qualified_name(elem)
    open = {:start_element, qname, elem.attributes, nil}
    new_queue = elem.children ++ [{:close_tag, qname}] ++ rest
    {[open], new_queue}
  end

  # Emit close tag marker
  defp emit_next([{:close_tag, tag} | rest]) do
    {[{:end_element, tag}], rest}
  end

  # Emit text content
  defp emit_next([text | rest]) when is_binary(text) do
    {[{:characters, text, nil}], rest}
  end

  # Emit comment
  defp emit_next([{:comment, content} | rest]) do
    {[{:comment, content, nil}], rest}
  end

  # Emit CDATA
  defp emit_next([{:cdata, content} | rest]) do
    {[{:cdata, content, nil}], rest}
  end

  # Emit processing instruction
  defp emit_next([{:pi, target, data} | rest]) do
    {[{:processing_instruction, target, data, nil}], rest}
  end

  # Skip nil values
  defp emit_next([nil | rest]) do
    emit_next(rest)
  end

  # Serialize document with optional XML declaration
  defp serialize_document(%Document{root: nil}, _state, _xml_decl), do: []

  defp serialize_document(
         %Document{root: root, prolog: prolog, doctype: doctype},
         state,
         xml_decl
       ) do
    parts = []

    # XML declaration
    parts =
      if xml_decl or prolog do
        version = if prolog, do: prolog[:version], else: "1.0"
        encoding = if prolog, do: prolog[:encoding], else: nil

        decl =
          case encoding do
            nil -> "<?xml version=\"#{version}\"?>"
            enc -> "<?xml version=\"#{version}\" encoding=\"#{enc}\"?>"
          end

        parts ++ [decl, if(state.pretty, do: "\n", else: "")]
      else
        parts
      end

    # DOCTYPE
    parts =
      if doctype do
        parts ++ ["<!DOCTYPE ", doctype, ">", if(state.pretty, do: "\n", else: "")]
      else
        parts
      end

    # Root element
    parts ++ serialize_element(root, state)
  end

  # Serialize element
  defp serialize_element(%Element{} = elem, state) do
    qname = Element.qualified_name(elem)
    indent = if state.pretty, do: String.duplicate(state.indent, state.depth), else: ""

    # Opening tag
    attrs_str = serialize_attributes(elem.attributes)

    if Enum.empty?(elem.children) do
      # Self-closing tag
      [indent, "<", qname, attrs_str, "/>"]
    else
      # Opening tag
      open = [indent, "<", qname, attrs_str, ">"]

      # Children
      child_state = %{state | depth: state.depth + 1}
      has_element_children = Enum.any?(elem.children, &match?(%Element{}, &1))

      children =
        if state.pretty and has_element_children do
          # Pretty print with newlines between element children
          elem.children
          |> Enum.flat_map(fn child ->
            ["\n" | serialize_child(child, child_state)]
          end)
        else
          Enum.flat_map(elem.children, &serialize_child(&1, child_state))
        end

      # Closing tag
      close_indent = if state.pretty and has_element_children, do: ["\n", indent], else: []
      close = [close_indent, "</", qname, ">"]

      [open, children, close]
    end
  end

  # Serialize child nodes
  defp serialize_child(text, _state) when is_binary(text) do
    [escape_text(text)]
  end

  defp serialize_child(%Element{} = elem, state) do
    serialize_element(elem, state)
  end

  defp serialize_child({:comment, content}, state) do
    indent = if state.pretty, do: String.duplicate(state.indent, state.depth), else: ""
    [indent, "<!--", content, "-->"]
  end

  defp serialize_child({:cdata, content}, state) do
    indent = if state.pretty, do: String.duplicate(state.indent, state.depth), else: ""
    [indent, "<![CDATA[", content, "]]>"]
  end

  defp serialize_child({:pi, target, nil}, state) do
    indent = if state.pretty, do: String.duplicate(state.indent, state.depth), else: ""
    [indent, "<?", target, "?>"]
  end

  defp serialize_child({:pi, target, data}, state) do
    indent = if state.pretty, do: String.duplicate(state.indent, state.depth), else: ""
    [indent, "<?", target, " ", data, "?>"]
  end

  defp serialize_child(_, _state), do: []

  # Serialize attributes
  defp serialize_attributes([]), do: ""

  defp serialize_attributes(attrs) do
    attrs
    |> Enum.map(fn {name, value} ->
      [" ", name, "=\"", escape_attr(value), "\""]
    end)
  end

  # Escape text content
  defp escape_text(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  # Escape attribute values
  defp escape_attr(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
