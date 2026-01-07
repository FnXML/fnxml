defmodule FnXML.Stream.Exception do
  defexception message: "Invalid XML stream"
end

defmodule FnXML.Stream do
  @moduledoc """
  This module provides functions for transforming a stream of XML elements.

  Event formats:
  - `{:doc_start, nil}` - Document start marker
  - `{:doc_end, nil}` - Document end marker
  - `{:open, tag, attrs, loc}` - Opening tag
  - `{:close, tag}` or `{:close, tag, loc}` - Closing tag
  - `{:text, content, loc}` - Text content
  - `{:comment, content, loc}` - Comment
  - `{:prolog, "xml", attrs, loc}` - XML prolog
  - `{:proc_inst, name, content, loc}` - Processing instruction
  """

  alias FnXML.Element

  @doc """
  Format the XML Stream into a string.

  options:
    - pretty: if true, format the XML with newlines and indentation (defaults to false)
    - indent: the number of spaces to use for indentation (defaults to 2)

  ## Example

      iex> [
      iex>   {:open, "fizz:foo", [{"a", "1"}], {1, 0, 1}},
      iex>   {:text, "hello", {1, 0, 20}},
      iex>   {:close, "fizz:foo"}
      iex> ]
      iex> |> FnXML.Stream.to_xml()
      iex> |> Enum.join()
      "<fizz:foo a=\\"1\\">hello</fizz:foo>"
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
  defp format_element({:doc_start, _}, path, _acc), do: {length(path), ""}
  defp format_element({:doc_end, _}, path, _acc), do: {length(path), ""}

  defp format_element({:prolog, tag, attrs, _loc}, path, _acc) do
    attrs_str = format_attributes(attrs)
    {length(path), "<?#{tag}#{attrs_str}?>"}
  end

  defp format_element({:open, tag, attrs, _loc}, path, _acc) do
    attrs_str = format_attributes(attrs)
    {length(path) - 1, "<#{tag}#{attrs_str}>"}
  end

  defp format_element({:close, tag}, path, _acc) do
    {length(path) - 1, "</#{tag}>"}
  end

  defp format_element({:close, tag, _loc}, path, _acc) do
    {length(path) - 1, "</#{tag}>"}
  end

  defp format_element({:text, content, _loc}, path, _acc) do
    if Regex.match?(~r/[<>]/, content) do
      {length(path), "<![CDATA[#{content}]]>"}
    else
      {length(path), content}
    end
  end

  defp format_element({:comment, content, _loc}, path, _acc) do
    {length(path), "<!--#{content}-->"}
  end

  defp format_element({:proc_inst, name, content, _loc}, path, _acc) do
    {length(path), "<?#{name} #{content}?>"}
  end

  @doc """
  Apply a transform function to a stream of XML elements.

  the function `fun` is called with each element in the stream, the current stack of open tags and the current accumulator.

  fun:
      a function that takes three arguments:
          - element: the current element, ex: {:open, "foo", [], {1, 0, 1}}
          - stack: the current stack of open tags (the path), ex: [ {"bar", ""}, {"foo", ""} ], each element on the stack
            contains a tuple: {tag, namespace}.
          - the current accumulator
      this function should return:
          - the new accumulator or {element to emit, new accumulator}

          if [:a, :b] is returned, the process continues without emitting anything downstream

          if {:a, [:b]} is returned, the process emits :a, and continues with the accumulator as [:b]

  Note the stack is a list of tuples, where the first element is the tag name and the second element is the namespace.

  See XMLStreamTools.Inspector for an example of how to use this module.
  """
  @valid_element_id Element.id_list()

  def transform(stream, acc \\ [], fun) do
    stream
    |> Stream.chunk_while(initial_acc(acc, fun), &process_item/2, &after_fn/1)
  end

  defp initial_acc(acc, fun), do: {[], acc, fun}

  defp process_item({:open, tag, _attrs, _loc} = element, {stack, acc, fun}) do
    tag_tuple = Element.tag(tag)
    new_stack = [tag_tuple | stack]
    fun.(element, new_stack, acc) |> next(new_stack, fun)
  end

  defp process_item({:close, _tag} = element, {[], _, _}) do
    tag_str = Element.tag_string(element)
    error(element, "unexpected close tag #{tag_str}, missing open tag")
  end

  defp process_item({:close, _tag, _loc} = element, {[], _, _}) do
    tag_str = Element.tag_string(element)
    error(element, "unexpected close tag #{tag_str}, missing open tag")
  end

  defp process_item({:close, tag} = element, {[head | new_stack] = stack, acc, fun}) do
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

  defp process_item({:close, tag, _loc} = element, {[head | new_stack] = stack, acc, fun}) do
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

  defp process_item({:text, content, _loc} = element, {[], acc, fun}) do
    if String.match?(content, ~r/^[\s\n]*$/) do
      acc |> next([], fun)
    else
      error(element, "Text element outside of a tag: '#{element |> inspect()}', a root element is required")
    end
  end

  defp process_item({id, _, _} = element, {stack, acc, fun}) when id in @valid_element_id do
    fun.(element, stack, acc) |> next(stack, fun)
  end

  defp process_item({id, _, _, _} = element, {stack, acc, fun}) when id in @valid_element_id do
    fun.(element, stack, acc) |> next(stack, fun)
  end

  # Document start/end markers - pass through without modifying stack
  defp process_item({:doc_start, _} = element, {stack, acc, fun}) do
    fun.(element, stack, acc) |> next(stack, fun)
  end

  defp process_item({:doc_end, _} = element, {stack, acc, fun}) do
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
    raise FnXML.Stream.Exception, message: "Error (line: #{line}, char: #{char}) #{msg}"
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
    - element: the current element, ex: {:open, "foo", [], {1, 0, 1}}
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
      - element: the current element, ex: {:open, "foo", [], {1, 0, 1}}
      - path: the current stack of open tags (the path), ex: [ {"bar", ""}, {"foo", ""} ]
      - acc: an accumulator which can be used to keep state between invocations.

      The function must return a tuple with `{ filter boolean, acc }`  The filter boolean indicates if the element
      should be filtered or not, and the accumulator contains state passed to the next invokation of the filter
      function.

  ## Example

      iex> stream = FnXML.Parser.parse("<foo><bar>1</bar><bar>2</bar></foo>")
      iex> FnXML.Stream.filter(stream, fn _, [{tag, ""} | _], _ -> {tag == "bar", []} end)
      iex> |> Enum.map(fn x -> x end)
      [
        {:doc_start, nil},
        {:open, "bar", [], {1, 0, 6}},
        {:text, "1", {1, 0, 10}},
        {:close, "bar", {1, 0, 12}},
        {:open, "bar", [], {1, 0, 18}},
        {:text, "2", {1, 0, 22}},
        {:close, "bar", {1, 0, 24}},
        {:doc_end, nil}
      ]
  """
  def filter(stream, fun, acc \\ []) do
    FnXML.Stream.transform(
      stream,
      acc,
      fn
        # Pass through document start/end markers
        {:doc_start, _} = element, _path, acc -> {element, acc}
        {:doc_end, _} = element, _path, acc -> {element, acc}
        element, path, acc ->
          case fun.(element, path, acc) do
            {true, acc} -> {element, acc}
            {false, acc} -> acc
          end
      end
    )
  end

  @doc """
  Filter out whitespace only elements from the stream.
  """
  def filter_ws(stream) do
    filter(stream, fn
      {:text, content, _loc}, _, acc -> {not String.match?(content, ~r/^\s*$/), acc}
      _, _, acc -> {true, acc}
    end)
  end

  @doc """
  Filter in/out specific namespaces from the stream
  """
  def filter_namespaces(stream, ns_list, opts \\ []) when is_list(ns_list) do
    include = Keyword.get(opts, :include, not Keyword.get(opts, :exclude, false))

    filter(stream, fn
      {:open, tag, _attrs, _loc}, _, acc ->
        {_tag, ns} = Element.tag(tag)
        result = if ns in ns_list, do: include, else: not include
        {result, [result | acc]}

      {:close, _tag}, _, [result | rest] ->
        {result, rest}

      {:close, _tag, _loc}, _, [result | rest] ->
        {result, rest}

      _, _, [result | _] = acc ->
        {result, acc}
    end)
  end
end
