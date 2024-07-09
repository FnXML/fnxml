defmodule FnXML.Stream do

  @moduledoc """
  This module provides functions for transforming a stream of XML elements.
  """


  @doc """
  Format the XML Stream into a string.

  options:
    - pretty: if true, format the XML with newlines and indentation (defaults to false)
    - indent: the number of spaces to use for indentation (defaults to 2)
    
  ## Example

      iex> [
      iex>   {:open_tag, [tag: "foo", namespace: "fizz", attr_list: [{"a", "1"}]]},
      iex>   {:text, ["hello"]},
      iex>   {:close_tag, [tag: "foo", namespace: "fizz"]}
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

    fun = fn element, path, acc -> to_xml_fn(element, path, acc, pretty, indent) end
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

  defp format_element({:open_tag, parts}, path, _acc) do
    tag = Keyword.get(parts, :tag)
    ns = Keyword.get(parts, :namespace)
    ns = if ns, do: "#{ns}:", else: ""
    close = if Keyword.get(parts, :close, false), do: "/", else: ""
    attrs = 
      Keyword.get(parts, :attr_list, [])
      |> Enum.map(fn {k, v} -> " #{k}=\"#{v}\"" end)
      |> Enum.join(" ")

    { length(path) - 1, "<#{ns}#{tag}#{attrs}#{close}>" }
  end

  defp format_element({:text, [text | _]}, path, _acc), do: { length(path), text }

  defp format_element({:close_tag, parts}, path, _acc) do
    tag = Keyword.get(parts, :tag)
    ns = Keyword.get(parts, :namespace)
    ns = if ns, do: "#{ns}:", else: ""

    { length(path) - 1, "</#{ns}#{tag}>" }
  end

  @doc """
  Apply a transform function to a stream of XML elements.

  the function `fun` is called with each element in the stream, the current stack of open tags and the current accumulator.

  fun:
      a function that takes three arguments:
          - element: the current element, ex: {:open_tag, %{tag: "foo"}}
          - stack: the current stack of open tags (the path), ex: [ "bar", "foo" ]
          - the current accumulator
      this function should return:
          - the new accumulator or {element to emit, new accumulator}

          if [:a, :b] is returned, the process continues without emitting anything downstream

          if {:a, [:b]} is returned, the process emits :a, and continues with the accumulator as [:b]

       See XMLStreamTools.Inspector for an example of how to use this module.
  """
  def transform(stream, acc \\ [], fun) do
    stream
    |> Stream.chunk_while(initial_acc(acc, fun), &process_item/2, &after_fn/1)
  end

  defp initial_acc(acc, fun), do: {[], acc, fun}

  defp process_item({:open_tag, parts} = element, {stack, acc, fun}) do
    tag = Keyword.get(parts, :tag)
    stack = [tag | stack]

    fun.(element, stack, acc)
    |> next(stack, fun)
  end

  defp process_item({:text, _} = element, {stack, acc, fun}) do
    fun.(element, stack, acc)
    |> next(stack, fun)
  end

  defp process_item({:close_tag, parts} = element, {[head | stack] = pre_stack, acc, fun}) do
    tag = Keyword.get(parts, :tag)
    ["-#{head}-" | stack]
    cond do
      tag == head ->
        fun.(element, pre_stack, acc)
        |> next(stack, fun)

      tag != head ->
        error(element, "mis-matched close tag #{inspect(tag)}, expecting: #{head}")

      [] == pre_stack ->
        error(element, "unmatched close tag #{inspect(tag)}")
    end
  end

  defp process_item(element, {_, _, _}),
    do: error(element, "unexpected element: #{inspect(element)}")

  defp next({element, acc}, stack, fun), do: {:cont, element, {stack, acc, fun}}
  defp next(acc, stack, fun), do: {:cont, {stack, acc, fun}}

  defp after_fn([]), do: {:cont, []}
  defp after_fn(acc), do: {:cont, acc}

  defp error(element, msg) do
    {{line, line_start}, abs_pos} = element |> elem(1) |> Keyword.get(:loc)
    loc = "line: #{line}, char: #{abs_pos - line_start}"
    raise "Error #{loc}: #{msg}"
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
    - element: the current element, ex: {:open_tag, %{tag: "foo"}}
    - path: the current stack of open tags (the path), ex: [ "bar", "foo" ], where "foo" is the parent of "bar"

  The return value of the fun is discarded, and has no effect on the stream.  With tap, there is no way to modify the stream.
  """

  def tap(stream, fun \\ nil, opts) do
    label = Keyword.get(opts, :label, "")
    inspect_fun = fun || fn {type, meta}, path -> IO.puts("#{label}: #{type}#{inspect(meta)}, path: #{inspect(path)}") end
    inspector = fn element, path, _ ->
      inspect_fun.(element, path)
      {element, []}
    end
    transform(stream, inspector)
  end

  @doc """
  Strip the location meta data from the stream of XML elements.

  ## Example

    iex> FnXML.Parser.parse("<foo>with loc meta</foo>")
    iex> |> Enum.map(fn x -> x end)
    [
      open_tag: [{:tag, "foo"}, {:loc, {{1, 0}, 1}}],
      text: ["with loc meta", {:loc, {{1, 0}, 18}}],
      close_tag: [{:tag, "foo"}, {:loc, {{1, 0}, 20}}]
    ]  

    iex> FnXML.Parser.parse("<foo>no loc meta</foo>")
    iex> |> FnXML.Stream.strip_location_meta()
    iex> |> Enum.map(fn x -> x end)
    [
      {:open_tag, [tag: "foo"]},
      {:text, ["no loc meta"]},
      {:close_tag, [tag: "foo"]}
    ]  
  
  """
  def strip_location_meta(stream) do
    transform(stream, fn {id, [tag | meta]}, _, _ -> {{id, [tag | Keyword.drop(meta, [:loc])]}, []} end)
  end

  @doc """
  Filter the stream of XML elements.

  arguments:
    - stream: the stream to filter
    - fun: a function that takes two arguments:
      - element: the current element, ex: {:open_tag, %{tag: "foo"}}
      - path: the current stack of open tags (the path), ex: [ "bar", "foo" ], where "foo" is the parent of "bar"
      - acc: an accumulator which can be used to keep state between invocations.

      The function must return a tuple with `{ filter boolean, acc }`  The filter boolean indicates if the element
      should be filtered or not, and the accumulator contains state passed to the next invokation of the filter
      function.

  ## Example

    iex> stream = FnXML.Parser.parse("<foo><bar>1</bar><bar>2</bar></foo>")
    iex> FnXML.Stream.filter(stream, fn _, [tag | _], _ -> {tag == "bar", []} end)
    iex> |> Enum.map(fn x -> x end)
    [
      {:open_tag, [tag: "bar", loc: {{1, 0}, 6}]},
      {:text, ["1", {:loc, {{1, 0}, 11}}]},
      {:close_tag, [tag: "bar", loc: {{1, 0}, 13}]},
      {:open_tag, [tag: "bar", loc: {{1, 0}, 18}]},
      {:text, ["2", {:loc, {{1, 0}, 23}}]},
      {:close_tag, [tag: "bar", loc: {{1, 0}, 25}]}
    ]  
  """
  def filter(stream, fun, acc \\ []) do
    FnXML.Stream.transform(
      stream, acc,
      fn
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
      {:text, [t | _]}, _, acc -> {not String.match?(t, ~r/^\s*$/), acc}
      _, _, acc -> {true, acc}
    end)
  end

  @doc """
  Filter in/out specific namespaces from the stream
  """
  def filter_namespaces(stream, ns_list, opts \\ []) when is_list(ns_list) do
    exclude = Keyword.get(opts, :exclude, false)
    include = Keyword.get(opts, :include, not exclude)
    
    filter(stream, fn
      {:open_tag, meta}, _, acc ->
        ns = Keyword.get(meta, :namespace)
        result = if ns in ns_list, do: include, else: not include
        {result, [result | acc]}
      {:text, _}, _, [result | _] = acc -> {result, acc}
      {:close_tag, _}, _, [result | rest] -> {result, rest}
      _, _, acc -> {not include, acc}
    end)
  end

end
