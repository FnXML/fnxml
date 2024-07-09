defmodule FnXML.Stream.NativeDataStruct.EncoderDefault do
  @moduledoc """
  This Module is used to convert a Native Data Structs (NDS) to a NDS Meta type, which can then be used
  to encode the NDS to an XML stream.

  So this module is used in conjunction with the NativeDataType.Formatter to convert it to an XML stream.

  An encoder takes a native type like a map, and encodes it as a %NDS_Meta{} struct.  This provides all
  the data needed to make the XML stream.  The formatter then takes the %NDS_Meta{} struct and converts it to an XML stream.

  ## Example:

      iex> alias FnXML.Stream.NativeDataStruct.FormatterDefault, as: NDS_FormatterDefault
      iex> data = %{"a" => "hi", "b" => %{a: 1, b: 1}, c: "hi", d: 4}
      iex> NDS.EncoderDefault.encode(data, [tag_from_parent: "foo"])
      iex> |> NDS_FormatterDefault.emit()
      [
        open_tag: [tag: "foo", attr_list: [c: "hi", d: 4]],
        text: ["hi"],
        open_tag: [tag: "b", attr_list: [a: 1, b: 1]],
        close_tag: [tag: "b"],
        close_tag: [tag: "foo"]
        ]

  # How a tag name is determined:
  - meta_id: [:_meta][:tag] value
  - option: :tag_from_parent value (this is automatically set for nested structures
  - name of structure if it is a struct
  
  """
  alias FnXML.Stream.NativeDataStruct, as: NDS
  
  @behaviour NDS.Encoder

  @doc """
  encode returns a map of metadata about the data structure.

  ## Examples

      iex> NDS.EncoderDefault.encode(%{a: 1}, [])
      %NDS{
          data: %{a: 1},
          opts: [],
          meta_id: :_meta,
          tag: "undef",
          tag_from_parent: "undef",
          attr_list: [{:a, 1}],
          namespace: "",
      }

      iex> data = %{"a" => "hi", "b" => %{a: 1, b: 1}, c: "hi", d: 4}
      iex> opts = [tag_from_parent: "foo"]
      iex> NDS.EncoderDefault.encode(data, opts)
      %NDS{
          data: data,
          opts: opts,
          meta_id: :_meta,
          tag: "foo",
          tag_from_parent: "foo",
          attr_list: [{:c, "hi"}, {:d, 4}],
          child_list: %{
              "b" => %NDS {
                  meta_id: :_meta,
                  tag: "b",
                  tag_from_parent: "b",
                  namespace: "",
                  attr_list: [{:a, 1}, {:b, 1}], 
                  data: %{a: 1, b: 1},
                  opts: [tag_from_parent: "b", tag_from_parent: "foo"]
              }
          },
          order_id_list: ["a", "b"],
          namespace: "",
      }
  
  """
  @impl NDS.Encoder
  def encode(meta = %NDS{}) do
    # if the data is a struct, get the struct name for the tag
    tag_from_parent = Keyword.get(meta.opts, :tag_from_parent, "undef")

    meta
    |> meta_update(:meta_id, :_meta)
    |> meta_update(:namespace, fn meta -> meta.data[meta.meta_id][:namespace] || "" end)
    |> meta_update(:tag_from_parent, tag_from_parent)
    |> select_tag()
    |> meta_update(:attr_list, fn meta -> attributes(meta) end)
    |> meta_update(:child_list, fn meta -> children(meta, nil) end)
    |> meta_update(:order_id_list, fn meta ->
      Keyword.get(meta.opts, :order, meta.data[meta.meta_id][:order]) || order(meta)
    end)
  end

  @impl NDS.Encoder
  def encode(map, opts) when is_map(map) do
    {type, map} = struct_type(map)
    opts =
    if Keyword.get(opts, :tag_from_parent) do
      opts
    else
      if is_nil(type), do: opts, else: [{:tag_from_parent, type} | opts]
    end
      
    encode(%NDS{data: map, opts: opts})
  end

  def select_tag(meta) do
    meta_update(meta, :tag, meta.data[meta.meta_id][:tag] || meta.tag_from_parent)
  end

  def meta_update(meta, key, default)
  def meta_update(meta, key, default) when key in [:meta_id] do
    NDS.update(meta, key, Keyword.get(meta.opts, key, default))
  end
  def meta_update(meta, key, default) do
    value = Keyword.get(meta.opts, key, default) |> opt_action(meta)
    NDS.update(meta, key, value)
  end

  def struct_type(struct) do
    try do
      {to_string(struct.__struct__) |> String.trim_leading("Elixir."), Map.from_struct(struct)}
    rescue
      _ -> {nil, struct}
    end
  end

  @doc """
  This function is used to select an action for an option based on its value

  In each case the function returns a binary
  """
  def opt_action(value, meta, default \\ nil)
  def opt_action(nil, _meta, default), do: default
  def opt_action(fun, meta, _) when is_function(fun), do: fun.(meta)
  def opt_action(value, _meta, _) when is_binary(value) or is_list(value), do: value
  def opt_action(value, _meta, _), do: to_string(value)

  @doc """
  This function is used to filter the list of keys in the map based on the options.

  the meta data is passed as the first parameter, the second is used to describe the keys being filtered it can take 3 forms:

  A list:

  The filter_list function will return a list of keys that are in the provided list and also exist in the meta.data map.
  
  ## Examples

      iex> meta = %NDS{data: %{"a" => %{a: 1}, "b" => %{b: 2}, c: 3}}
      iex> NDS.EncoderDefault.filter_list(meta, fn meta -> Map.keys(meta.data) |> Enum.filter(fn k -> k in ["a", "b"] end) end)
      ["a", "b"]

  A function that takes the meta data as a parameter, this function should return a list of keys to be included in the list:

  ## Examples

      iex> meta = %NDS{data: %{"a" => %{a: 1}, "b" => %{b: 2}, c: 3}}
      iex> NDS.EncoderDefault.filter_list(meta, fn meta -> Map.keys(meta.data) |> Enum.filter(fn k -> not is_atom(k) end) end)
      ["a", "b"]

  A function that takes the meta data as a parameter and the key being filtered, which returns a boolean value if the key
  should be included in the list.  This function will be called once for each key in the meta.data map.

      iex> meta = %NDS{data: %{"a" => %{a: 1}, "b" => %{b: 2}, c: 3}}
      iex> NDS.EncoderDefault.filter_list(meta, fn _meta, k -> k in ["a", "b"] end)
      ["a", "b"]
  """
  def filter_list(meta, list) when is_list(list), do: Map.keys(meta.data) |> Enum.filter(fn k -> k in list end)
  def filter_list(meta, fun) when is_function(fun, 1), do: fun.(meta)
  def filter_list(meta, fun) when is_function(fun, 2), do: Enum.filter(Map.keys(meta.data), fn k -> fun.(meta, k) end)
        
  @doc """
  Return a list of attributes from a map.
  Arguments:
  - map - the data being encoded
  - meta - the metadata for the data
  - opt - this can be nil, a list, or a function.
      - nil the default behaviour is used which is to select all atoms as attributes except those which are
        listed in the id list in metadata.
      - a list, this can be a list of atoms of binaries, and the attributes will be selected from the map
        based on the list.
      - a function, in this case the function will be run for each key in the map, and should return true/false
        based on whether the key should be included in the list of attributes.

  ## Examples

      iex> NDS.EncoderDefault.attributes(%NDS{data: %{"text" => "not an attribute", a: 1, b: 2}})
      [{:a, 1}, {:b, 2}]

      iex> NDS.EncoderDefault.attributes(%NDS{data: %{a: 1, b: 2, c: 3}, }, [:a, :c])
      [{:c, 3}, {:a, 1}]

      iex> NDS.EncoderDefault.attributes(%NDS{data: %{a: 1, b: 2, c: 3, d: 4}}, fn _, k -> k in [:a, :d] end)
      [{:a, 1}, {:d, 4}]
  """
  def attributes(meta, opt \\ nil)
  def attributes(%NDS{} = meta, opt) do
    exclude_list = [meta.meta_id | Keyword.get(meta.opts || [], :children, [])]
    fun = fn meta, k ->
      is_atom(k) and k not in exclude_list and (meta.data[k] |> FnXML.Type.type()) in [Binary, Integer, Float, Boolean]
    end
    filter_list(meta, opt || fun)
    |> Enum.sort() # without this tests fail because the order of the attributes is not guaranteed, otherwise not needed
    |> Enum.map(fn k -> {k, meta.data[k]} end)
  end


  @doc """
  Return a list of children from a map.
  Arguments:
  - map - the data being encoded
  - meta - the metadata for the data
  - opt - this can be nil, a list, or a function.
      - nil the default behaviour is used which is to select all keys as attributes except those which are
        listed in the id list in metadata, or as an attribute.
      - a list, this can be a list of atoms of binaries, and the children will be selected from the map
        based on the list.
      - a function, in this case the function will be run for each key in the map, and should return true/false
        based on whether the key should be included in the list of children.

  ## Examples

      iex> meta = %NDS{data: %{"c" => %{a: 1}, a: 1, b: 2}, attr_list: [{:a, 1}, {:b, 2}]}
      iex> NDS.EncoderDefault.children(meta, nil)
      %{ "c" => %NDS{
          meta_id: :_meta,
          tag: "c",
          tag_from_parent: "c",
          namespace: "",
          attr_list: [a: 1],
          data: %{a: 1},
          opts: [tag_from_parent: "c"]
      } }

      iex> meta = %NDS{data: %{"c" => %{a: 1}, a: 1, b: 2}, attr_list: [{:a, 1}, {:b, 2}]}
      iex> NDS.EncoderDefault.children(meta, ["c", :b])
      %{ "c" => %NDS{
          meta_id: :_meta,
          tag: "c",
          tag_from_parent: "c",
          namespace: "",
          attr_list: [a: 1],
          data: %{a: 1},
          opts: [tag_from_parent: "c"]
          } }


  """
  def children(meta, opt) do
    # fun defines the default behavior
    fun = fn meta ->
      exclude_list = [meta.meta_id | Keyword.keys(meta.attr_list)]
      Map.keys(meta.data)      
      |> Enum.filter(fn k -> k not in exclude_list and valid_child(meta, meta.data[k]) end)
      |> Enum.reverse()
    end
    filter_list(meta, opt || fun)

    # encode children
    |> Enum.map(fn k -> {k, meta.data[k]} end)
    |> Enum.map(fn {k, child} -> encode_child(meta, k, child) end)
    |> Enum.into(%{})
  end

  def valid_child(_meta, child) when is_map(child), do: true
  def valid_child(_meta, [h|_] = child) when is_list(child) and is_map(h), do: true
  def valid_child(_, _), do: false

  def encode_child(meta, key, child) when is_list(child) do
    {key, child |> Enum.map(fn v -> encode(v, [{:tag_from_parent, key} | meta.opts || []]) end)}
  end
  def encode_child(meta, key, child) when is_map(child) do
    {key, encode(child, [{:tag_from_parent, key} | meta.opts || []])}
  end
        
  @doc """
  Returns a list of elements in the order they should be encoded.
  Arguments:
  - map - the data being encoded
  - meta - the metadata for the data
  - opt - this can be nil, a list, or a function.
      - nil the default behaviour is used which is to select all keys as attributes except those which are
        listed in the id list in metadata, or as an attribute.
      - a list, this can be a list of atoms of binaries, and the children will be selected from the map
        based on the list.
      - a function, in this case the function will be run for each key in the map, and should return true/false
        based on whether the key should be included in the list of children.

  ## Examples

      iex> %NDS{data: %{a: 1, b: 2}, attr_list: [{:a, 1}, {:b, 2}]}
      iex> |> NDS.EncoderDefault.order()
      []

      iex> %NDS{data: %{"text" => "not an attribute", a: 1, b: 2}, attr_list: [{:a, 1}, {:b, 2}]}
      iex> |> NDS.EncoderDefault.order(meta)
      ["text"]

      iex> %NDS{data: %{"text" => ["a", "b"], a: 1, b: 2}, "child" => %NDS{data: %{"text" => "c"}}}
      iex> |> NDS.EncoderDefault.order(meta)
      ["text", "child", "text"]

      iex> %NDS{data: %{"text" => ["a", "b"]}, "child" => [%NDS{data: %{"text" => "c"}}, %NDS{data: %{"text" => "d"}}]}
      iex> |> NDS.EncoderDefault.order(meta)
      ["text", "child", "text", "child"]
  
  """
  def order(%{order: order} = meta) when is_function(order), do: filter_list(meta, order)
  def order(%{meta_id: id, attr_list: attr_list} = meta) do
    fun = fn meta ->
      order_keys = Enum.filter(Map.keys(meta.data), fn k -> k not in [id | Keyword.keys(attr_list)] end)
      child_keys = Enum.filter(order_keys, fn k -> is_map(meta.data[k]) end)
      text_keys =
        Enum.filter(order_keys, fn k -> k not in child_keys end)
        |> Enum.reduce([], fn k, acc -> acc ++ order_item(k, meta.data[k]) end)

      rezip(text_keys, child_keys)
    end
    filter_list(meta, fun)
  end

  @doc """
  for lists, returns a list with the key repeated for each element in the list
  for all other values, returns a list with the key

  ## Examples

      iex> NDS.EncoderDefault.order_item("a", [1, 2, 3])
      ["a", "a", "a"]

      iex> NDS.EncoderDefault.order_item("a", 1)
      ["a"]

      iex> NDS.EncoderDefault.order_item("a", "hello")
      ["a"]
  """
  def order_item(k, value) when is_list(value), do: value |> Enum.map(fn _ -> k end)
  def order_item(k, _), do: [k]

  @doc """
  This function takes two lists and combines them into a new list alternatiting elements between each list.
  The first element is always from the longest list, and the lists do not have to be the same length, when
  list is empty, the remaining elements are appended to the accumulator.

  ## Examples

      iex> NDS.EncoderDefault.rezip([1, 2, 3], ["a", "b"])
      [1, "a", 2, "b", 3]

      iex> NDS.EncoderDefault.rezip([1, 2], ["a", "b", "c"])
      [1, "a", 2, "b", "c"]

      iex> NDS.EncoderDefault.rezip([1, 2, 3], ["a"])
      [1, "a", 2, 3]
  """
  def rezip(a, b) when length(a) >= length(b), do: rezip(a, b, [])
  def rezip(a, b), do: rezip(b, a, [])
  
  defp rezip([], [], acc), do: acc
  defp rezip([a|a_rest], [b|b_rest], acc), do: rezip(a_rest, b_rest, acc ++ [a, b])
  defp rezip(a, [], acc), do: acc ++ a
  defp rezip([], b, acc), do: acc ++ b
end

