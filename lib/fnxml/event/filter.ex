defmodule FnXML.Event.Filter do
  @moduledoc """
  Common event stream filters for XML processing.

  Provides pre-built filter functions for common XML stream transformations
  like removing whitespace and filtering by namespace.

  All functions return lazy streams and maintain O(1) memory complexity.

  ## Examples

      # Remove whitespace
      FnXML.Parser.parse(xml)
      |> FnXML.Event.Filter.filter_ws()
      |> Enum.to_list()

      # Filter by namespace
      FnXML.Parser.parse(xml)
      |> FnXML.Event.Filter.filter_namespaces(["http://example.org"])
      |> Enum.to_list()
  """

  alias FnXML.Element

  @doc """
  Filter out whitespace-only text events from the stream.

  Removes `{:characters, content, line, ls, pos}` and `{:space, ...}` events
  where `content` contains only whitespace characters (spaces, tabs, newlines).
  Useful for cleaning up streams where indentation whitespace is not significant.

  ## Examples

      FnXML.Parser.parse("<root>  <child/>  </root>")
      |> FnXML.Event.Filter.filter_ws()
      |> Enum.to_list()
      # Returns events without the whitespace text nodes

      # In a pipeline
      xml
      |> FnXML.Parser.parse()
      |> FnXML.Event.Filter.filter_ws()
      |> FnXML.Event.to_iodata()
      |> Enum.join()

  """
  @spec filter_ws(Enumerable.t()) :: Enumerable.t()
  def filter_ws(stream) do
    FnXML.Event.filter(stream, fn
      # 5-tuple from parser
      {:characters, content, _line, _ls, _pos}, _, acc ->
        {not String.match?(content, ~r/^\s*$/), acc}

      {:space, _content, _line, _ls, _pos}, _, acc ->
        {false, acc}

      _, _, acc ->
        {true, acc}
    end)
  end

  @doc """
  Filter events by namespace URI.

  Includes or excludes elements (and their descendants) based on their
  namespace. Useful for extracting specific vocabularies from mixed-namespace
  documents.

  ## Parameters

  - `stream` - The XML event stream
  - `ns_list` - List of namespace URIs to filter on
  - `opts` - Options:
    - `:include` - Include matching namespaces (default: true)
    - `:exclude` - Exclude matching namespaces (default: false)

  ## Examples

      # Include only XHTML namespace
      FnXML.Parser.parse(xml)
      |> FnXML.Event.Filter.filter_namespaces(["http://www.w3.org/1999/xhtml"])
      |> Enum.to_list()

      # Exclude SVG namespace
      FnXML.Parser.parse(xml)
      |> FnXML.Event.Filter.filter_namespaces(["http://www.w3.org/2000/svg"], exclude: true)
      |> Enum.to_list()

      # Multiple namespaces
      FnXML.Parser.parse(xml)
      |> FnXML.Event.Filter.filter_namespaces([
        "http://www.w3.org/1999/xhtml",
        "http://www.w3.org/2000/svg"
      ])
      |> Enum.to_list()

  """
  @spec filter_namespaces(Enumerable.t(), [String.t()], keyword()) :: Enumerable.t()
  def filter_namespaces(stream, ns_list, opts \\ []) when is_list(ns_list) do
    include = Keyword.get(opts, :include, not Keyword.get(opts, :exclude, false))

    FnXML.Event.filter(stream, fn
      # 6-tuple from parser
      {:start_element, tag, _attrs, _line, _ls, _pos}, _, acc ->
        {_tag, ns} = Element.tag(tag)
        result = if ns in ns_list, do: include, else: not include
        {result, [result | acc]}

      # 5-tuple from parser
      {:end_element, _tag, _line, _ls, _pos}, _, [result | rest] ->
        {result, rest}

      # 2-tuple legacy
      {:end_element, _tag}, _, [result | rest] ->
        {result, rest}

      _, _, [result | _] = acc ->
        {result, acc}
    end)
  end
end
