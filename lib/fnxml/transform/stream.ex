defmodule FnXML.Transform.Stream.Exception do
  defexception message: "Invalid XML stream"
end

defmodule FnXML.Transform.Stream do
  @moduledoc """
  Stream transformation functions for XML event streams.

  This module provides composable functions for filtering, transforming, and
  serializing XML event streams produced by `FnXML.Parser`. All functions operate
  on Elixir streams and maintain O(1) memory complexity.

  ## Specifications

  - W3C XML 1.0 (Fifth Edition): https://www.w3.org/TR/xml/

  ## Event Formats

  The stream functions support two event formats:

  ### Parser Format (from `FnXML.Parser`)

  Events with explicit position info (line, line_start, byte_offset):

  | Event | Description |
  |-------|-------------|
  | `{:start_document, nil}` | Document start marker |
  | `{:end_document, nil}` | Document end marker |
  | `{:start_element, tag, attrs, line, ls, pos}` | Opening tag |
  | `{:end_element, tag, line, ls, pos}` | Closing tag |
  | `{:characters, content, line, ls, pos}` | Text content |
  | `{:space, content, line, ls, pos}` | Whitespace |
  | `{:comment, content, line, ls, pos}` | Comment |
  | `{:prolog, "xml", attrs, line, ls, pos}` | XML prolog |
  | `{:processing_instruction, name, content, line, ls, pos}` | Processing instruction |

  ### Normalized Format (for programmatic generation)

  Events with optional packed location tuple or nil:

  | Event | Description |
  |-------|-------------|
  | `{:start_element, tag, attrs, loc}` | Opening tag (loc is `nil` or `{line, ls, pos}`) |
  | `{:end_element, tag, loc}` | Closing tag |
  | `{:characters, content, loc}` | Text content |
  | `{:space, content, loc}` | Whitespace |
  | `{:comment, content, loc}` | Comment |
  | `{:prolog, "xml", attrs, loc}` | XML prolog |
  | `{:processing_instruction, name, content, loc}` | Processing instruction |

  The normalized format is useful when generating XML events programmatically
  (e.g., from data structures) where position information is not available.

  ## Use Cases

  ### Serialize XML Events to String

      xml_string = FnXML.Parser.parse("<root><child>text</child></root>")
      |> FnXML.Transform.Stream.to_xml()
      |> Enum.join()
      # => "<root><child>text</child></root>"

  ### Pretty Print XML

      pretty_xml = FnXML.Parser.parse("<root><child/></root>")
      |> FnXML.Transform.Stream.to_xml(pretty: true, indent: 4)
      |> Enum.join()
      # => "<root>\\n    <child/>\\n</root>\\n"

  ### Filter Whitespace

      FnXML.Parser.parse(xml)
      |> FnXML.Transform.Stream.filter_ws()
      |> Enum.to_list()

  ### Transform with Path Context

      # Extract all <item> elements content
      FnXML.Parser.parse(xml)
      |> FnXML.Transform.Stream.transform(fn event, path, acc ->
        case {event, path} do
          {{:characters, content, _, _, _}, [{"item", _} | _]} -> {content, acc}
          _ -> acc
        end
      end)
      |> Enum.to_list()

  ### Debug Stream with Tap

      FnXML.Parser.parse(xml)
      |> FnXML.Transform.Stream.tap(fn event, path ->
        IO.inspect({event, path}, label: "XML Event")
      end, label: "debug")
      |> Enum.to_list()

  ### Filter by Namespace

      # Include only elements in specific namespace
      FnXML.Parser.parse(xml)
      |> FnXML.Transform.Stream.filter_namespaces(["http://example.org"], include: true)
      |> Enum.to_list()

  ## API Overview

  | Function | Description |
  |----------|-------------|
  | `to_xml/2` | Serialize events to XML string stream |
  | `transform/3` | Apply custom transformation with path context |
  | `filter/3` | Filter events based on predicate with path context |
  | `filter_ws/1` | Remove whitespace-only text events |
  | `filter_namespaces/3` | Filter events by namespace URI |
  | `tap/3` | Inspect events without modifying stream |
  """

  alias FnXML.Element

  @doc """
  Format the XML Stream into a string.

  options:
    - pretty: if true, format the XML with newlines and indentation (defaults to false)
    - indent: the number of spaces to use for indentation (defaults to 2)

  ## Example

      iex> [
      iex>   {:start_element, "fizz:foo", [{"a", "1"}], 1, 0, 1},
      iex>   {:characters, "hello", 1, 0, 20},
      iex>   {:end_element, "fizz:foo", 1, 0, 25}
      iex> ]
      iex> |> FnXML.Transform.Stream.to_xml()
      iex> |> Enum.join()
      "<fizz:foo a=\"1\">hello</fizz:foo>"
  """
  def to_xml(stream, opts \\ [])
  def to_xml(list, opts) when is_list(list), do: Stream.into(list, []) |> to_xml(opts)

  def to_xml(stream, opts) do
    pretty = Keyword.get(opts, :pretty, false)
    indent = Keyword.get(opts, :indent, 2)

    fun = fn
      element, path, acc ->
        to_xml_fn(element, path, acc, pretty, indent)
    end

    transform(stream, fun)
  end

  defp to_xml_fn(element, path, acc, pretty, indent) do
    {depth, formatted_element} = format_element(element, path, acc)

    if pretty do
      indent = String.duplicate(" ", indent * depth)
      {"#{indent}#{formatted_element}\n", acc}
    else
      {formatted_element, acc}
    end
  end

  defp add_leading_space(str = ""), do: str
  defp add_leading_space(str), do: " " <> str

  defp format_attributes(attributes) do
    attributes
    |> Enum.map(fn {k, v} -> "#{k}=\"#{v}\"" end)
    |> Enum.join(" ")
    |> add_leading_space()
  end

  # Document start/end markers emit nothing
  defp format_element({:start_document, _}, path, _acc), do: {length(path), ""}
  defp format_element({:end_document, _}, path, _acc), do: {length(path), ""}

  # 6-tuple format (from parser)
  defp format_element({:prolog, tag, attrs, _line, _ls, _pos}, path, _acc) do
    attrs_str = format_attributes(attrs)
    {length(path), "<?#{tag}#{attrs_str}?>"}
  end

  defp format_element({:start_element, tag, attrs, _line, _ls, _pos}, path, _acc) do
    attrs_str = format_attributes(attrs)
    {length(path) - 1, "<#{tag}#{attrs_str}>"}
  end

  defp format_element({:end_element, tag, _line, _ls, _pos}, path, _acc) do
    {length(path) - 1, "</#{tag}>"}
  end

  defp format_element({:characters, content, _line, _ls, _pos}, path, _acc) do
    if Regex.match?(~r/[<>]/, content) do
      {length(path), "<![CDATA[#{content}]]>"}
    else
      {length(path), content}
    end
  end

  defp format_element({:space, content, _line, _ls, _pos}, path, _acc) do
    {length(path), content}
  end

  defp format_element({:cdata, content, _line, _ls, _pos}, path, _acc) do
    {length(path), "<![CDATA[#{content}]]>"}
  end

  defp format_element({:comment, content, _line, _ls, _pos}, path, _acc) do
    {length(path), "<!--#{content}-->"}
  end

  defp format_element({:processing_instruction, name, content, _line, _ls, _pos}, path, _acc) do
    {length(path), "<?#{name} #{content}?>"}
  end

  defp format_element({:dtd, content, _line, _ls, _pos}, path, _acc) do
    {length(path), content}
  end

  # 2-tuple format (no location)
  defp format_element({:end_element, tag}, path, _acc) do
    {length(path) - 1, "</#{tag}>"}
  end

  @doc """
  Apply a transform function to a stream of XML elements.

  the function `fun` is called with each element in the stream, the current stack of open tags and the current accumulator.

  fun:
      a function that takes three arguments:
          - element: the current element, ex: {:start_element, "foo", [], 1, 0, 1}
          - stack: the current stack of open tags (the path), ex: [ {"bar", ""}, {"foo", ""} ], each element on the stack
            contains a tuple: {tag, namespace}.
          - the current accumulator
      this function should return:
          - the new accumulator or {element to emit, new accumulator}

          if [:a, :b] is returned, the process continues without emitting anything downstream

          if {:a, [:b]} is returned, the process emits :a, and continues with the accumulator as [:b]

  Note the stack is a list of tuples, where the first element is the tag name and the second element is the namespace.

  See FnXML.Transform.Stream.Inspector for an example of how to use this module.
  """
  @valid_element_id Element.id_list()

  def transform(stream, acc \\ [], fun) do
    stream
    |> Stream.chunk_while(initial_acc(acc, fun), &process_item/2, &after_fn/1)
  end

  defp initial_acc(acc, fun), do: {[], acc, fun}

  # 6-element start_element: {:start_element, tag, attrs, line, ls, pos}
  defp process_item({:start_element, tag, _attrs, _line, _ls, _pos} = element, {stack, acc, fun}) do
    tag_tuple = Element.tag(tag)
    new_stack = [tag_tuple | stack]
    fun.(element, new_stack, acc) |> next(new_stack, fun)
  end

  # 5-element end_element: {:end_element, tag, line, ls, pos}
  defp process_item({:end_element, _tag, _line, _ls, _pos} = element, {[], _, _}) do
    tag_str = Element.tag_string(element)
    error(element, "unexpected close tag #{tag_str}, missing open tag")
  end

  defp process_item(
         {:end_element, tag, _line, _ls, _pos} = element,
         {[head | new_stack] = stack, acc, fun}
       ) do
    tag_tuple = Element.tag(tag)

    cond do
      tag_tuple == head ->
        fun.(element, stack, acc) |> next(new_stack, fun)

      tag_tuple != head ->
        error(
          element,
          "mis-matched close tag #{inspect(tag_tuple)}, expecting: #{Element.tag_name(head)}"
        )
    end
  end

  # 2-element end_element (no location): {:end_element, tag}
  defp process_item({:end_element, tag} = element, {[], _, _}) do
    error(element, "unexpected close tag #{tag}, missing open tag")
  end

  defp process_item({:end_element, tag} = element, {[head | new_stack] = stack, acc, fun}) do
    tag_tuple = Element.tag(tag)

    cond do
      tag_tuple == head ->
        fun.(element, stack, acc) |> next(new_stack, fun)

      tag_tuple != head ->
        error(
          element,
          "mis-matched close tag #{inspect(tag_tuple)}, expecting: #{Element.tag_name(head)}"
        )
    end
  end

  # 5-element characters: {:characters, content, line, ls, pos}
  defp process_item({:characters, content, _line, _ls, _pos} = element, {[], acc, fun}) do
    if String.match?(content, ~r/^[\s\n]*$/) do
      acc |> next([], fun)
    else
      error(
        element,
        "Text element outside of a tag: '#{element |> inspect()}', a root element is required"
      )
    end
  end

  # 5-element space: {:space, content, line, ls, pos}
  defp process_item({:space, _content, _line, _ls, _pos}, {[], acc, fun}) do
    # Whitespace outside root element is ignored
    acc |> next([], fun)
  end

  # Generic handlers for 5-element and 6-element events
  defp process_item({id, _, _, _, _} = element, {stack, acc, fun}) when id in @valid_element_id do
    fun.(element, stack, acc) |> next(stack, fun)
  end

  defp process_item({id, _, _, _, _, _} = element, {stack, acc, fun})
       when id in @valid_element_id do
    fun.(element, stack, acc) |> next(stack, fun)
  end

  # Document start/end markers - pass through without modifying stack
  defp process_item({:start_document, _} = element, {stack, acc, fun}) do
    fun.(element, stack, acc) |> next(stack, fun)
  end

  defp process_item({:end_document, _} = element, {stack, acc, fun}) do
    fun.(element, stack, acc) |> next(stack, fun)
  end

  defp process_item(element, {_stack, _acc, _fun}) do
    error(element, "unknown element type #{inspect(element)}")
  end

  defp next({element, acc}, stack, fun), do: {:cont, element, {stack, acc, fun}}
  defp next(acc, stack, fun), do: {:cont, {stack, acc, fun}}

  defp after_fn([]), do: {:cont, []}
  defp after_fn(acc), do: {:cont, acc}

  defp error(element, msg) do
    {line, char} = Element.position(element)
    raise FnXML.Transform.Stream.Exception, message: "Error (line: #{line}, char: #{char}) #{msg}"
  end

  @doc """
  Tap into a stream of XML elements.  The defult function displays each Stream element to
  the console.  However, a custom function could be provided which sends a copy of the data to another
  stream or to an event queue, etc...

  arguments:
    - stream: the stream to tap into
    - fun: an optional function to call with each element, path and meta (see details below)
    - opts: a keyword list of options
        - :label: a label to display with each element

  if fun is nil, the default function will display each element to the console.
  otherwise fun must be a function that takes two arguments:
    - element: the current element, ex: {:start_element, "foo", [], 1, 0, 1}
    - path: the current stack of open tags (the path), ex: [ {"bar", ""}, {"foo", ""} ]

  The return value of the fun is discarded, and has no effect on the stream.  With tap, there is no way to modify the stream.
  """

  def tap(stream, fun \\ nil, opts) do
    label = Keyword.get(opts, :label, "")

    inspect_fun =
      fun ||
        fn element, path ->
          IO.puts("#{label}: #{inspect(element)}, path: #{inspect(path)}")
        end

    inspector = fn element, path, _ ->
      inspect_fun.(element, path)
      {element, []}
    end

    transform(stream, inspector)
  end

  @doc """
  Filter the stream of XML elements.

  arguments:
    - stream: the stream to filter
    - fun: a function that takes two arguments:
      - element: the current element, ex: {:start_element, "foo", [], 1, 0, 1}
      - path: the current stack of open tags (the path), ex: [ {"bar", ""}, {"foo", ""} ]
      - acc: an accumulator which can be used to keep state between invocations.

      The function must return a tuple with `{ filter boolean, acc }`  The filter boolean indicates if the element
      should be filtered or not, and the accumulator contains state passed to the next invokation of the filter
      function.

  ## Example

      iex> stream = FnXML.Parser.parse("<foo><bar>1</bar><bar>2</bar></foo>")
      iex> FnXML.Transform.Stream.filter(stream, fn _, [{tag, ""} | _], _ -> {tag == "bar", []} end)
      iex> |> Enum.map(fn x -> x end)
      [
        {:start_document, nil},
        {:start_element, "bar", [], 1, 0, 6},
        {:characters, "1", 1, 0, 10},
        {:end_element, "bar", 1, 0, 12},
        {:start_element, "bar", [], 1, 0, 18},
        {:characters, "2", 1, 0, 22},
        {:end_element, "bar", 1, 0, 24},
        {:end_document, nil}
      ]
  """
  def filter(stream, fun, acc \\ []) do
    FnXML.Transform.Stream.transform(
      stream,
      acc,
      fn
        # Pass through document start/end markers
        {:start_document, _} = element, _path, acc ->
          {element, acc}

        {:end_document, _} = element, _path, acc ->
          {element, acc}

        element, path, acc ->
          case fun.(element, path, acc) do
            {true, acc} -> {element, acc}
            {false, acc} -> acc
          end
      end
    )
  end

  @doc """
  Filter out whitespace-only text events from the stream.

  Removes `{:characters, content, line, ls, pos}` and `{:space, ...}` events
  where `content` contains only whitespace characters (spaces, tabs, newlines).
  Useful for cleaning up streams where indentation whitespace is not significant.

  ## Examples

      FnXML.Parser.parse("<root>  <child/>  </root>")
      |> FnXML.Transform.Stream.filter_ws()
      |> Enum.to_list()
      # Returns events without the whitespace text nodes

  """
  @spec filter_ws(Enumerable.t()) :: Enumerable.t()
  def filter_ws(stream) do
    filter(stream, fn
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
      |> FnXML.Transform.Stream.filter_namespaces(["http://www.w3.org/1999/xhtml"])
      |> Enum.to_list()

      # Exclude SVG namespace
      FnXML.Parser.parse(xml)
      |> FnXML.Transform.Stream.filter_namespaces(["http://www.w3.org/2000/svg"], exclude: true)
      |> Enum.to_list()

  """
  @spec filter_namespaces(Enumerable.t(), [String.t()], keyword()) :: Enumerable.t()
  def filter_namespaces(stream, ns_list, opts \\ []) when is_list(ns_list) do
    include = Keyword.get(opts, :include, not Keyword.get(opts, :exclude, false))

    filter(stream, fn
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
