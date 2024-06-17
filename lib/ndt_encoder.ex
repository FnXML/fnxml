defmodule XMLStreamTools.NativeDataType.Meta do

  @moduledoc """
  This Module is a behaviour used to encode a Native Data Type (NDT) to an XML stream.
  """

  alias XMLStreamTools.NativeDataType.Meta, as: NDT_Meta

  defstruct meta_id: :_meta, tag: "undef", namespace: nil, order: nil, tag_from_parent: nil,
    attr_list: [], order_id_list: [], child_list: %{}, text_id_list: [],
    data: nil, opts: nil

  def update(meta, key, value), do: Map.put(meta, key, value)
             
  @callback meta(map :: map, opts :: term) :: map
end


defmodule XMLStreamTools.NativeDataType.Formatter do
  @callback emit(meta :: map, map :: map) :: list
end

defmodule XMLStreamTools.XMLStream.NDT_Formatter do
  alias XMLStreamTools.NativeDataType.Meta, as: NDT_Meta

  @behaviour XMLStreamTools.NativeDataType.Formatter

  @impl XMLStreamTools.NativeDataType.Formatter
  def emit(%NDT_Meta{} = meta) do
   [open_tag(meta) | [content_list(meta) | [close_tag(meta)]]]
  end

  def open_tag(%NDT_Meta{tag: tag, namespace: "", attr_list: []}), do: {:open_tag, [tag: tag]}
  def open_tag(%NDT_Meta{tag: tag, namespace: "", attr_list: attrs}), do: {:open_tag, [tag: tag, attr: attrs]}
  def open_tag(%NDT_Meta{tag: tag, namespace: namespace, attr_list: []}), do: {:open_tag, [tag: tag, namespace: namespace]}
  def open_tag(%NDT_Meta{tag: tag, namespace: namespace, attr_list: attrs}),
    do: {:open_tag, [tag: tag, namespace: namespace, attrs: attrs]}

  def close_tag(%NDT_Meta{tag: tag, namespace: ""}), do: {:close_tag, [tag: tag]}
  def close_tag(%NDT_Meta{tag: tag, namespace: namespace}), do: {:close_tag, [tag: tag, namespace: namespace]}

  def content_list(meta) do
    Enum.reduce(meta.order_id_list, [], fn key, acc -> [content(meta, meta.map[key]) | acc] end)
  end

  def content(meta, item) when is_map(item) or is_list(item) do
    
  end
  def content(meta, item) when is_binary(item), do: {:text, [item]}
end


defmodule XMLStreamTools.NativeDataType.MetaDefault do
  @moduledoc """
  This Module is used to encode a Native Data Type (NDT) to an XML stream.
  """
  alias XMLStreamTools.NativeDataType.Meta, as: NDT_Meta
  alias XMLStreamTools.NativeDataType.MetaDefault, as: NDT_MetaDefault
  
  @behaviour NDT_Meta

  @impl NDT_Ops
  @doc """
  Meta returns a map of metadata about the data structure.

  ## Examples

      iex> NDT_MetaDefault.meta(%{a: 1}, [])
      %NDT_Meta{
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
      iex> NDT_MetaDefault.meta(data, opts)
      %NDT_Meta{
          data: data,
          opts: opts,
          meta_id: :_meta,
          tag: "foo",
          tag_from_parent: "foo",
          attr_list: [{:c, "hi"}, {:d, 4}],
          child_list: %{
              "b" => %NDT_Meta {
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
  @impl NDT_Meta
  def meta(map, opts) when is_map(map), do: meta(%NDT_Meta{data: map, opts: opts})


  def meta(meta = %NDT_Meta{}) do
    tag_from_parent = Keyword.get(meta.opts, :tag_from_parent, "undef")

    update = fn meta, key, default -> meta_update(meta, key, default) end

    meta
    |> meta_update(:meta_id, :_meta)
    |> meta_update(:namespace, "")
    |> meta_update(:tag_from_parent, tag_from_parent)
    |> update.(:tag, tag_from_parent)
    |> update.(:order, nil)
    |> update.(:attr_list, fn meta -> attributes(meta, nil) end)
    |> update.(:child_list, fn meta -> children(meta, nil) end)
    |> meta_update(:order_id_list, fn meta -> order(meta) end)
  end

  def meta_update(meta, key, default)
  def meta_update(meta, key, default) when key in [:meta_id] do
    NDT_Meta.update(meta, key, Keyword.get(meta.opts, key, default))
  end
  def meta_update(meta, key, default) do
    value = Keyword.get(meta.opts, key, default) |> opt_action(meta)
    NDT_Meta.update(meta, key, value)
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

  ## Examples

      iex> meta = %NDT_Meta{data: %{"a" => %{a: 1}, "b" => %{b: 2}, c: 3}}
      iex> NDT_MetaDefault.filter_list(meta, nil, fn meta -> Map.keys(meta.data) |> Enum.filter(fn k -> not is_atom(k) end) end)
      ["a", "b"]

      iex> meta = %NDT_Meta{data: %{"a" => %{a: 1}, "b" => %{b: 2}, c: 3}}
      iex> NDT_MetaDefault.filter_list(meta, ["a", "b"], nil)
      ["a", "b"]

      iex> meta = %NDT_Meta{data: %{"a" => %{a: 1}, "b" => %{b: 2}, c: 3}}
      iex> NDT_MetaDefault.filter_list(meta, fn _meta, k -> k in ["a", "b"] end, nil)
      ["a", "b"]
  """
  def filter_list(meta, nil, gen_fun), do: gen_fun.(meta)
  def filter_list(meta, list, _) when is_list(list), do: Enum.filter(Map.keys(meta.data), fn k -> k in list end)
  def filter_list(meta, fun, _) when is_function(fun), do: Enum.filter(Map.keys(meta.data), fn k -> fun.(meta, k) end)
        
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

      iex> NDT_MetaDefault.attributes(%NDT_Meta{data: %{"text" => "not an attribute", a: 1, b: 2}}, nil)
      [{:a, 1}, {:b, 2}]

      iex> NDT_MetaDefault.attributes(%NDT_Meta{data: %{a: 1, b: 2, c: 3}, }, [:a, :c])
      [{:c, 3}, {:a, 1}]

      iex> NDT_MetaDefault.attributes(%NDT_Meta{data: %{a: 1, b: 2, c: 3, d: 4}}, fn _, k -> k in [:a, :d] end)
      [{:a, 1}, {:d, 4}]
  """
  def attributes(meta, opt) do
    gen_fun = fn meta -> Enum.filter(Map.keys(meta.data), fn k -> is_atom(k) and k != meta.meta_id end) end
    filter_list(meta, opt, gen_fun)
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

      iex> meta = %NDT_Meta{data: %{"text" => "not an attribute", a: 1, b: 2}, attr_list: [{:a, 1}, {:b, 2}]}
      iex> NDT_MetaDefault.children(meta, nil)
      %{}

      iex> meta = %NDT_Meta{data: %{"c" => %{a: 1}, a: 1, b: 2}, attr_list: [{:a, 1}, {:b, 2}]}
      iex> NDT_MetaDefault.children(meta, nil)
      %{ "c" => %NDT_Meta{
          meta_id: :_meta,
          tag: "c",
          tag_from_parent: "c",
          namespace: "",
          attr_list: [a: 1],
          data: %{a: 1},
          opts: [tag_from_parent: "c"]
      } }

      iex> meta = %NDT_Meta{data: %{"c" => %{a: 1}, a: 1, b: 2}, attr_list: [{:a, 1}, {:b, 2}]}
      iex> NDT_MetaDefault.children(meta, ["c", :b])
      %{ "c" => %NDT_Meta{
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
    # gen_fun defines the default behavior
    gen_fun = fn meta ->
      exclude_list = [meta.meta_id | Keyword.keys(meta.attr_list)] 
      Enum.filter(Map.keys(meta.data), fn k -> k not in exclude_list and is_map(meta.data[k]) end)
      |> Enum.reverse()
    end
    filter_list(meta, opt, gen_fun)
    # eliminate any children with values not maps
    |> Enum.filter(fn k -> is_map(meta.data[k]) end)
    |> Enum.map(fn k -> {k, meta(meta.data[k], [{:tag_from_parent, k} | meta.opts || []])} end)
    |> Enum.into(%{})
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

      iex> meta = %NDT_Meta{data: %{a: 1, b: 2}, attr_list: [{:a, 1}, {:b, 2}]}
      iex> NDT_MetaDefault.order(meta)
      []

      iex> meta = %NDT_Meta{data: %{"text" => "not an attribute", a: 1, b: 2}, attr_list: [{:a, 1}, {:b, 2}]}
      iex> NDT_MetaDefault.order(meta)
      ["text"]
  """
  def order(%{order: order} = meta) when is_function(order), do: filter_list(meta, nil, order)
  def order(%{meta_id: id, attr_list: attr_list} = meta) do
    gen_fun = fn meta ->
      Enum.filter(Map.keys(meta.data), fn k -> k not in [id | Keyword.keys(attr_list)] end)
    end
    filter_list(meta, nil, gen_fun)
  end
end



defmodule XMLStreamTools.NativeDataType.Decoder do

  @moduledoc """
  This Module is used to decode an XML stream to a Native Data Type (NDT).
  """

  alias XMLStreamTools.NativeDataType.Decoder, as: NDT_Decoder

  
end
