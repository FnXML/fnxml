defmodule FnXML.Stream.NativeDataStruct.Format.Map do
  alias FnXML.Stream.NativeDataStruct, as: NDS

  @behaviour NDS.Formatter

  @doc """
  Emit returns a list of XML stream elements.

  ## Examples

      iex> data = %{"a" => "hi", "b" => %{"info" => "info", a: 1, b: 1}, c: "hi", d: 4}
      iex> nds = NDS.Encoder.encode(data, [tag_from_parent: "foo"])
      iex> NDS.Format.Map.emit(nds)
      %{
        "foo" => %{
          "a" => "hi", :c => "hi", :d => "4",
          "b" => %{ "info" => "info", :a => "1", :b => "1", _meta: %{tag: "b", order: ["info"]} },
          _meta: %{tag: "foo", order: ["a", "b"]}
        }
      }

      iex> xml = "<foo>hi<bar>hello</bar><baz>world</baz></foo>"
      iex> FnXML.Parser.parse(xml) |> NDS.decode(format_meta: &NDS.no_meta/1)
      [%{"foo" => %{ "text" => "hi", "bar" => "hello", "baz" => "world" }}]
  """
  @impl NDS.Formatter
  def emit(nds, opts \\ [])
  def emit(%NDS{} = nds, opts) do
    child_fun = Keyword.get(opts, :format_child, fn x -> x end)
    finalize = Keyword.get(opts, :format_finalize, &default_finalize/1)
    # finalize is run on the final map result

    # emit child is the main function of this module
    [emit_child(nds, opts) |> child_fun.()]
    |> Enum.into(%{})
    |> finalize.()
  end

  # emits a list by iterating over each item
  def emit(list, opts) when is_list(list) do
    Enum.map(list, fn x -> emit(x, opts) end)
  end

  # this is the main part here
  def emit_child(%NDS{} = nds, opts) do
    # formats the meta data
    meta_fun = Keyword.get(opts, :format_meta, &default_meta/1)
    attr_fun = Keyword.get(opts, :format_attributes, &default_attr/1)
    text_fun = Keyword.get(opts, :format_text, fn x -> x end)
    child_fun = Keyword.get(opts, :format_child, fn x -> x end)

    # formats the  attributes into a map
    attr = attr_fun.(nds.attributes)

    { nds.tag,
      meta_fun.(nds)   # format meta-data
      |> Map.merge(attr)
      #|> Map.merge(id_list(nds, opts))  # this needs to be adjusted to fix for the new format:
      
      # iterate over the text and children and emit them --> convert this to content
      |> Map.merge(
        Enum.reduce(nds.content, %{}, fn
          text, acc when is_binary(text) -> {"text", text} |> text_fun.() |> emit_data(acc)
          {:text, _, text}, acc when is_binary(text) -> {"text", text} |> text_fun.() |> emit_data(acc)
          %NDS{} = nds, acc -> emit_child(nds, opts) |> child_fun.() |> emit_data(acc)
          {:child, _, nds}, acc -> emit_child(nds, opts) |> child_fun.() |> emit_data(acc)
        end)
        |> Enum.map(fn
          {k, v} when is_list(v) -> {k, v |> Enum.reverse()}
          {k, v} -> {k, v}
        end)
        |> Enum.into(%{})
      )
    }
  end

  def emit_data({key, data}, acc) do
    Map.put(acc, key, append(acc[key], data))
  end

  def append(nil, item), do: item
  def append(list, item) when is_list(list), do: [item | list]
  def append(value, item), do: [item, value]

  def default_meta(%NDS{} = nds)do
    namespace = nds.namespace
    order = if nds.content == [], do: nil, else: Enum.map(nds.content, fn
            %NDS{} = nds -> nds.tag
            {:child, _k, nds} -> nds.tag
            val when is_binary(val) -> "text"
            {:text, _k, _val} -> "text"
          end)
    %{_meta:
      %{ tag: nds.tag, namespace: namespace, order: order }
      |> Enum.filter(&filter_empty/1)
      |> Enum.into(%{})
    }
  end

  def default_attr(attr_list) do
    Enum.map(attr_list, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
      {k, v} -> { to_string(k) |> String.to_atom(), v}
    end)
    |> Enum.into(%{})
  end

  def filter_empty({_k, v}) when is_binary(v), do: v != ""
  def filter_empty({_k, v}), do: not is_nil(v)

  def content_to_order(content) do
    Enum.map(content, fn
      {:child, _, nds} -> nds.tag
      {:text, _, _} -> "text"
    end)
  end

  # *** test and validate this function
  @doc """
  Finalize the map by removing any nested maps with a single key and a value of a map with a single key of "text"

  ## Examples:

      iex> map = %{"a" => %{"text" => "hello"}}
      iex> NDS.Format.Map.default_finalize(map)
      %{"a" => "hello"}
  """
  def default_finalize(%{__struct__: _} = struct), do: struct   # skip for structs
  def default_finalize(map) when is_map(map) do
    if Map.has_key?(map, :__struct__) do
      IO.puts("is a struct")
    end
    
    Enum.map(map, fn
      {:_meta, _} = meta -> meta
      {k, %{__struct__: _} = v} -> {k, v}
      {k, v} when is_map(v) ->
        map0 = if (is_nil(v[:_meta]) or (v[:_meta][:namespace] not in [nil, ""])), do: v, else: Map.drop(v, [:_meta])
        { k, (if length(Map.keys(map0)) == 1 and Map.has_key?(map0, "text"), do: map0["text"], else: default_finalize(v)) }
      {k, v} when is_list(v) ->
        { k, Enum.map(v, fn map -> default_finalize(%{k => map}) |> Enum.to_list() |> Enum.at(0) |> elem(1) end) }
      {k, v} ->
        {k, v}
    end)
    |> Enum.into(%{})
  end
  def default_finalize(x), do: x

  def default_finalize_item(item) when is_map(item) do
    if length(Map.keys(item)) == 1 and Map.has_key?(item, "text"), do: item["text"], else: default_finalize(item)
  end
  def default_finalize_item(item), do: item
    
end

