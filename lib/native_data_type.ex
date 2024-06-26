defmodule XMLStreamTools.NativeDataType do

  alias XMLStreamTools.NativeDataType, as: NDT
  alias XMLstringTools.XMLStream, as: XMLStream
  
  @doc """
  Converts a native data type (NDT) such as a list or map to an XML representation.

  opts:

    - :ops_module - the module to use for the operations, this is what defines the structure of the NDT
  
    - :tag_from_parent - the tag to use if it is not specified in the data structure

    - :meta_id - the key to use for the meta data      (defaults to :_meta)
    - :tag_id - the key to use for the tag             (defaults to [:_meta, :tag])
    - :namespace_id - the key to use for the namespace (defaults to [:_meta, :namespace])
    - :text_id - the key to use for the text           (defaults to :_text)

    - :namespace - namespace for element, or a function which returns the namespace
    - :tag - tag for element, or a function which returns the tag
    - :order - a list of elements in the order they should appear or a function which returns a list of elements
    - :attr - a list of attributes in the map, or a function which returns a list of attributes
    - :children - a list of children in the map, or a function which returns a list of children

       functions defined for :order, :attr, :children should take the following arguments:
         - the map
         - the meta data
         - a key which may or may not be in map
         It should return true if the key should be included in the list, false otherwise
         
    - :text - a list of text elements to add to the map, or a function returns the text

       functions defined for :text should take the following arguments:
         - the map
         - the meta data
         It should return a list of the text to insert into the resulting encoding.
         If there is no text, it should return an empty list

  special keys:
    - :_meta - metadata about the map
    - :_namespace - the namespace
    - :_text - the text of the element

  any atoms as keys will be used as attributes
  any other keys will be used as elements
  """

  def encode(map, opts)
  def encode(nil, opts), do: encode(%{}, opts)
  def encode(list, opts) when is_list(list), do: Enum.reduce(list, [], fn map, acc -> acc ++ encode(map, opts) end)
  def encode(map, opts) when is_map(map) do
    encoder = Keyword.get(opts, :ops_module, NDT.OpsDefault)
    formatter = Keyword.get(opts, :formatter, XMLStream.FormatterDefault)
    encoder.meta(map, opts)
    |> IO.inspect(label: "meta")
    |> formatter.emit()
  end
  def encode(value, opts), do: encode(%{value: to_string(value)}, [{:text, fn map, _ -> map[:value] end} | opts])
  
  def to_xml_stream(map, opts \\ [])
  def to_xml_stream(nil, opts), do: to_xml_stream(%{}, opts)
  def to_xml_stream(map, opts) when is_map(map) do
    map = set_opts(map, opts)
    [ close_tag(map) | [content(map) | [ open_tag(map) ]]]
    |> Enum.reverse
    |> List.flatten
  end
  def to_xml_stream(list, opts) when is_list(list), do: Enum.reduce(list, [], fn map, acc -> acc ++ to_xml_stream(map, opts) end)
  def to_xml_stream(value, opts), do: to_xml_stream(%{_text: to_string(value)}, opts)

  def set_if_nil(map, key, fun) do
    case map[key] do
      nil -> 
        value = fun.()
        if value, do: Map.put(map, key, value), else: map
      _ -> map
    end
  end
  
  def set_opts(map, opts) do
    namespace = Keyword.get(opts, :namespace) || map[:_namespace]
    tag_from_parent = Keyword.get(opts, :tag_from_parent)

    meta_opts =
      %{
        tag: Keyword.get(opts, :tag),
        order: Keyword.get(opts, :order)
      }
      |> Enum.reject(fn {_k, v} -> v == nil end)
      |> Enum.into(%{})

    meta =
      Map.merge(map[:_meta] || %{}, meta_opts)
      |> set_if_nil(:tag, fn -> tag_from_parent || "undef" end)
      |> set_if_nil(:order, fn -> generate_order_list(map) end)

    map
    |> Map.put(:_meta, meta)
    |> Map.put(:_namespace, namespace)
    |> Enum.reject(fn {_k, v} -> v == nil or v == %{} end)
    |> Enum.into(%{})
  end
  
  def generate_order_list(map) do
    for key <- Map.keys(map), key not in [:_meta, :namespace], into: [], do: key
  end

  def get_attrs(map) do
    map
    |> Enum.reduce([], fn
      {k, v}, acc when is_atom(k) and k not in [:_meta, :_namespace, :_text] ->
        [{to_string(k), to_string(v)} | acc]
      {_, _}, acc -> acc
    end)
    |> Enum.reverse()
  end

  def open_tag(map), do: format_open_tag(map[:_namespace], map[:_meta][:tag], get_attrs(map))

  def format_open_tag(nil, tag, []), do: {:open_tag, [tag: tag]}
  def format_open_tag(nil, tag, attrs), do: {:open_tag, [tag: tag, attr: attrs]}
  def format_open_tag(namespace, tag, []), do: {:open_tag, [tag: tag, namespace: namespace]}
  def format_open_tag(namespace, tag, attrs), do: {:open_tag, [tag: tag, namespace: namespace, attr: attrs]}

  def close_tag(map), do: format_close_tag(map[:_namespace], map[:_meta][:tag])

  def format_close_tag(nil, tag), do: {:close_tag, [tag: tag]}
  def format_close_tag(namespace, tag), do: {:close_tag, [tag: tag, namespace: namespace]}

  def content(map) do
    order = get_in(map, [:_meta, :order])

    {result, _} =
      Enum.reduce(order , {[], map}, fn
        :_text, {output, map} ->
          {result, updated_map} = next_text_item(map)
          {output ++ [result], updated_map}
        val, {output, map} when is_binary(val) ->
          result = to_xml_stream(map[val], [tag_from_parent: val])
          {output ++ result , map |> Map.drop([val])}
        _, {output, map} -> {output, map}
      end)
    result
  end

  def next_text_item(%{:_text => text, :_meta => %{ order: [_ | order]}} = map) when is_binary(text) do
    {{:text, [text]}, %{map | :_meta => %{map[:_meta] | order: order}, :_text => []}}
  end
  def next_text_item(%{:_text => [text | rest], :_meta => %{ order: [_ | order]}} = map)  do
    {{:text, [text]}, %{map | :_meta => %{map[:_meta] | order: order}, :_text => rest}}
  end
end
