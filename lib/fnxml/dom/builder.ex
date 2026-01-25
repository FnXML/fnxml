defmodule FnXML.DOM.Builder do
  @moduledoc """
  Build DOM trees from XML strings or event streams.

  This module converts FnXML parser events into `FnXML.DOM.Document`
  and `FnXML.DOM.Element` structures.

  ## Examples

      # Pipeline style (recommended) - use FnXML.DOM.build/1
      doc = FnXML.parse_stream("<root><child/></root>")
            |> FnXML.DOM.build()

      # Quick parse (convenience)
      doc = FnXML.DOM.parse("<root><child/></root>")

  ## Internal

  This module provides the implementation for `FnXML.DOM.build/1,2`
  and `FnXML.DOM.parse/1,2`. Use those functions instead of calling
  this module directly.
  """

  alias FnXML.DOM.{Document, Element}

  @doc """
  Parse XML string to DOM Document.

  ## Options

  - `:include_comments` - Include comment nodes (default: false)
  - `:include_prolog` - Parse XML declaration (default: true)

  ## Examples

      iex> doc = FnXML.DOM.Builder.parse("<root attr='val'/>")
      iex> doc.root.tag
      "root"
      iex> FnXML.DOM.Element.get_attribute(doc.root, "attr")
      "val"
  """
  @spec parse(String.t(), keyword()) :: Document.t()
  def parse(xml, opts \\ []) when is_binary(xml) do
    FnXML.Parser.parse(xml)
    |> from_stream(opts)
  end

  @doc """
  Parse XML string to DOM Document, raising on error.
  """
  @spec parse!(String.t(), keyword()) :: Document.t()
  def parse!(xml, opts \\ []) when is_binary(xml) do
    case parse(xml, opts) do
      %Document{} = doc -> doc
      other -> raise "Failed to parse XML: #{inspect(other)}"
    end
  end

  @doc """
  Build DOM from an FnXML event stream.

  ## Options

  - `:include_comments` - Include comment nodes (default: false)
  - `:include_prolog` - Parse XML declaration (default: true)

  ## Examples

      iex> FnXML.Parser.parse("<root>text</root>")
      ...> |> FnXML.DOM.Builder.from_stream()
      ...> |> then(& &1.root.children)
      ["text"]
  """
  @spec from_stream(Enumerable.t(), keyword()) :: Document.t()
  def from_stream(stream, opts \\ []) do
    include_comments = Keyword.get(opts, :include_comments, false)
    include_prolog = Keyword.get(opts, :include_prolog, true)

    {stack, prolog, doctype} =
      Enum.reduce(stream, {[], nil, nil}, fn event, {stack, prolog, doctype} ->
        handle_event(event, stack, prolog, doctype, include_comments)
      end)

    root =
      case stack do
        [root] -> root
        [] -> nil
        _multiple -> hd(stack)
      end

    prolog_map =
      if include_prolog and prolog do
        prolog
        |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
        |> Enum.into(%{})
      else
        nil
      end

    %Document{
      root: root,
      prolog: prolog_map,
      doctype: doctype
    }
  end

  # ===========================================================================
  # handle_event/5 clauses - all grouped together
  # ===========================================================================

  # Handle open tag - 6-tuple from parser
  defp handle_event(
         {:start_element, tag, attrs, _line, _ls, _pos},
         stack,
         prolog,
         doctype,
         include_comments
       ) do
    handle_start_element(tag, attrs, stack, prolog, doctype, include_comments)
  end

  # Handle close tag - 5-tuple from parser
  defp handle_event(
         {:end_element, _tag, _line, _ls, _pos},
         [current | rest],
         prolog,
         doctype,
         _include_comments
       ) do
    handle_close(current, rest, prolog, doctype)
  end

  # Handle close tag - 2-tuple format (legacy)
  defp handle_event({:end_element, _tag}, [current | rest], prolog, doctype, _include_comments) do
    handle_close(current, rest, prolog, doctype)
  end

  # Handle text - 5-tuple from parser
  defp handle_event(
         {:characters, content, _line, _ls, _pos},
         [%Element{children: children} = elem | rest],
         prolog,
         doctype,
         _include_comments
       ) do
    {[%{elem | children: children ++ [content]} | rest], prolog, doctype}
  end

  # Handle text outside of elements (5-tuple from parser)
  defp handle_event(
         {:characters, content, _line, _ls, _pos},
         [],
         prolog,
         doctype,
         _include_comments
       ) do
    if String.match?(content, ~r/^\s*$/) do
      {[], prolog, doctype}
    else
      {[content], prolog, doctype}
    end
  end

  # Handle CDATA - 5-tuple from parser
  defp handle_event(
         {:cdata, content, _line, _ls, _pos},
         [%Element{children: children} = elem | rest],
         prolog,
         doctype,
         _include_comments
       ) do
    {[%{elem | children: children ++ [{:cdata, content}]} | rest], prolog, doctype}
  end

  # Handle comment - 5-tuple from parser (when including)
  defp handle_event(
         {:comment, content, _line, _ls, _pos},
         stack,
         prolog,
         doctype,
         true = _include_comments
       ) do
    handle_comment(content, stack, prolog, doctype)
  end

  # Handle comment - 5-tuple from parser (not including)
  defp handle_event(
         {:comment, _content, _line, _ls, _pos},
         stack,
         prolog,
         doctype,
         false = _include_comments
       ) do
    {stack, prolog, doctype}
  end

  # Handle prolog - 6-tuple from parser
  defp handle_event(
         {:prolog, _name, attrs, _line, _ls, _pos},
         stack,
         _prolog,
         doctype,
         _include_comments
       ) do
    {stack, attrs, doctype}
  end

  # Handle DTD - 5-tuple from parser
  defp handle_event({:dtd, content, _line, _ls, _pos}, stack, prolog, _doctype, _include_comments) do
    {stack, prolog, content}
  end

  # Handle processing instructions - 6-tuple from parser (inside element)
  defp handle_event(
         {:processing_instruction, target, content, _line, _ls, _pos},
         [%Element{children: children} = elem | rest],
         prolog,
         doctype,
         _include_comments
       ) do
    {[%{elem | children: children ++ [{:pi, target, content}]} | rest], prolog, doctype}
  end

  # Handle processing instructions - 6-tuple from parser (outside element)
  defp handle_event(
         {:processing_instruction, _target, _content, _line, _ls, _pos},
         stack,
         prolog,
         doctype,
         _include_comments
       ) do
    {stack, prolog, doctype}
  end

  # Handle errors - 6-tuple from parser (ignore for building)
  defp handle_event(
         {:error, _type, _msg, _line, _ls, _pos},
         stack,
         prolog,
         doctype,
         _include_comments
       ) do
    {stack, prolog, doctype}
  end

  # Handle document start/end markers (ignore)
  defp handle_event({:start_document, _}, stack, prolog, doctype, _include_comments) do
    {stack, prolog, doctype}
  end

  defp handle_event({:end_document, _}, stack, prolog, doctype, _include_comments) do
    {stack, prolog, doctype}
  end

  # Catch-all for unknown events
  defp handle_event(_event, stack, prolog, doctype, _include_comments) do
    {stack, prolog, doctype}
  end

  # ===========================================================================
  # Helper functions
  # ===========================================================================

  defp handle_start_element(tag, attrs, stack, prolog, doctype, _include_comments) do
    {prefix, local_name} = parse_qname(tag)
    namespace_uri = find_namespace_uri(attrs, prefix)

    elem = %Element{
      tag: local_name,
      attributes: attrs,
      children: [],
      namespace_uri: namespace_uri,
      prefix: prefix
    }

    {[elem | stack], prolog, doctype}
  end

  defp handle_comment(content, stack, prolog, doctype) do
    case stack do
      [%Element{children: children} = elem | rest] ->
        {[%{elem | children: children ++ [{:comment, content}]} | rest], prolog, doctype}

      [] ->
        {[{:comment, content}], prolog, doctype}
    end
  end

  # Close element and add to parent or return as root
  defp handle_close(%Element{} = elem, [], prolog, doctype) do
    {[elem], prolog, doctype}
  end

  defp handle_close(
         %Element{} = elem,
         [%Element{children: parent_children} = parent | rest],
         prolog,
         doctype
       ) do
    {[%{parent | children: parent_children ++ [elem]} | rest], prolog, doctype}
  end

  # Parse QName into {prefix, local_name}
  defp parse_qname(qname) do
    case String.split(qname, ":", parts: 2) do
      [local] -> {nil, local}
      [prefix, local] -> {prefix, local}
    end
  end

  # Find namespace URI from xmlns attributes
  defp find_namespace_uri(attrs, nil) do
    # Look for default namespace (xmlns="...")
    case List.keyfind(attrs, "xmlns", 0) do
      {"xmlns", ""} -> nil
      {"xmlns", uri} -> uri
      nil -> nil
    end
  end

  defp find_namespace_uri(attrs, prefix) do
    # Look for prefixed namespace (xmlns:prefix="...")
    xmlns_attr = "xmlns:#{prefix}"

    case List.keyfind(attrs, xmlns_attr, 0) do
      {^xmlns_attr, uri} -> uri
      nil -> nil
    end
  end
end
