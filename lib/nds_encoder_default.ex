defmodule FnXML.Stream.NativeDataStruct.EncoderDefault do
  @moduledoc """
  This Module is used to convert a Native Data Structs (NDS) to a NDS Meta type, which can then be used
  to encode the NDS to an XML stream.

  So this module is used in conjunction with the NativeDataType.Formatter to convert it to an XML stream.

  An encoder takes a native type like a map, and encodes it as a %NDS_Meta{} struct.  This provides all
  the data needed to make the XML stream.  The formatter then takes the %NDS_Meta{} struct and converts it to an XML stream.

  ## Example:

      iex> data = %{"a" => "hi", "b" => %{a: 1, b: 1}, c: "hi", d: 4}
      iex> NDS.EncoderDefault.encode(data, tag_from_parent: "foo")
      iex> |> NDS.Format.XML.emit()
      [
        open_tag: [tag: "foo", attr_list: [c: "hi", d: 4]],
        text: ["hi"],
        open_tag: [tag: "b", close: true, attr_list: [a: 1, b: 1]],
        close_tag: [tag: "foo"],
      ]

  # How a tag name is determined:
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
          tag: "root",
          attr_list: [{:a, 1}],
          namespace: "",
          private: %{opts: []}
      }

      iex> data = %{"a" => "hi", "b" => %{a: 1, b: 1}, c: "hi", d: 4}
      iex> NDS.EncoderDefault.encode(data, [tag_from_parent: "foo"]) |> NDS.TestHelpers.clear_private()
      %NDS{
          data: data,
          tag: "foo",
          attr_list: [{:c, "hi"}, {:d, 4}],
          child_list: %{
              "b" => %NDS {
                  tag: "b",
                  namespace: "",
                  attr_list: [{:a, 1}, {:b, 1}], 
                  data: %{a: 1, b: 1},
              }
          },
          order_id_list: ["a", "b"],
          namespace: "",
      }
  
  """
  @impl NDS.Encoder
  def encode(data, opts \\ [])
  def encode(nds = %NDS{}, opts) do
    meta_fun = Keyword.get(opts, :encoder_meta, &default_encoder_meta/1)
    
    nds
    |> meta_fun.()
    |> fn nds -> %NDS{nds | private: put_in(nds.private, [:opts], opts)} end.()
    |> NDS.tag(Keyword.get(opts, :tag, fn nds -> default_tag(nds, opts) end))
    |> NDS.namespace(Keyword.get(opts, :namespace, &default_namespace/1))
    |> NDS.attr_list(Keyword.get(opts, :attr, &default_attributes/1))
    |> NDS.child_list(Keyword.get(opts, :children, &default_children/1))
    |> NDS.order_id_list(Keyword.get(opts, :order, &default_order/1))
  end
  def encode(map, opts) when is_map(map), do: encode(%NDS{data: map}, opts)

  @doc """
  Returns a tuple with the type of the struct and the struct itself.  If `struct`
  is not a real struct, it returns the tuple {nil, struct}
  """
  def struct_type(struct) do
    try do
      {to_string(struct.__struct__) |> String.trim_leading("Elixir."), Map.from_struct(struct)}
    rescue
      _ -> {nil, struct}
    end
  end

  ##
  ## Default Behaviors
  ##  

  @doc """
  extract metadata from nds.data

  ## Examples

      iex> NDS.EncoderDefault.default_encoder_meta(%NDS{data: %{_meta: %{tag: "blue"}, a: 1}})
      %NDS{
          data: %{a: 1},
          private: %{_meta: %{tag: "blue"}}
      }
  """

  def default_encoder_meta(%NDS{data: %{ _meta: meta}} = nds) when not is_nil(meta) do
    %NDS{nds | private: Map.put(nds.private, :_meta, meta), data: Map.delete(nds.data, :_meta)}
  end
  def default_encoder_meta(%NDS{} = nds), do: nds

  @doc """
  get namespace for nds

  ## Examples

      iex> NDS.EncoderDefault.default_namespace(%NDS{
      iex>   data: %{"_meta" => %{"t" => "hi"}, a: 1},
      iex>   private: %{ _meta: %{namespace: "foo", }}
      iex> })
      "foo"
  """
  def default_namespace(nds), do: get_in(nds.private, [:_meta, :namespace]) || ""

  
  @doc """
  find tag for nds

  1. use `:tag_from_parent` option if provided.
  2. if the data is a struct, use the type of the struct
  3. default to "root"

  ## Examples:

      iex> NDS.EncoderDefault.default_tag(%NDS{data: %{"a" => 1}}, [])
      "root"

      iex> NDS.EncoderDefault.default_tag(%NDS{data: %{"a" => 1}}, tag_from_parent: "foo")
      "foo"
  """
  def default_tag(nds, opts) do
    tag_from_parent = Keyword.get(opts, :tag_from_parent)
    {type, _map} = struct_type(nds.data)
    tag_from_parent || type || get_in(nds.private, [:meta, :tag]) || "root"
    |> fn
      s when is_binary(s) -> s
      s -> to_string(s)
    end.()
  end


  @doc """
  default function to calculate attributes, this can be overriden by specifying a list of options or another
  function in opts[:attr]

  ## Examples

      iex> NDS.EncoderDefault.default_attributes(%NDS{data: %{"text" => "not an attribute", a: 1, b: 2}})
      [{:a, 1}, {:b, 2}]
  """
  def default_attributes(nds) do
    valid_attribute_types = [Binary, Integer, Float, Boolean]
    Map.keys(nds.data)
    |> Enum.map(fn
      k ->
        item = nds.data[k]
        {k, item, FnXML.Type.type(item)}
    end)
    |> Enum.filter(fn {k, _, type} -> is_atom(k) and type in valid_attribute_types end)
    |> Enum.map(fn {k, v, _} -> {k, v} end)
    |> Enum.sort(fn {k1, _}, {k2, _} -> k1 < k2 end)
  end
  
  
  @doc """
  Return a list of children from a nds.data.

  ## Examples

      iex> nds = %NDS{data: %{"c" => %{a: 1}, a: 1, b: 2}}
      iex> NDS.EncoderDefault.default_children(nds)
      %{ "c" => %NDS{
          tag: "c",
          namespace: "",
          attr_list: [a: 1],
          data: %{a: 1},
          private: %{opts: [tag_from_parent: "c"]}
      } }
  """
  def default_children(nds) do
    Map.keys(nds.data)
    |> Enum.filter(fn k -> valid_child(nds.data[k]) end)
    |> Enum.map(fn k -> encode_child(nds, k, nds.data[k]) end)
    |> Enum.into(%{})
  end

  def valid_child(child) when is_map(child), do: true
  def valid_child([child|_]) when is_map(child), do: true
  def valid_child(_), do: false

  def encode_child(nds, key, child) when is_list(child) do
    {
      key,
      Enum.map(child, fn
        v -> encode(v, [{:tag_from_parent, key} | nds.private[:opts] || []] |> propagate_opts())
      end)
    }
  end
  def encode_child(nds, key, child) when is_map(child) do
    {key, encode(child, [{:tag_from_parent, key} | nds.private[:opts] || []] |> propagate_opts())}
  end

  def propagate_opts(opts) do
    Enum.filter(opts, fn {k, v} -> is_function(v) or k in [:tag_from_parent, :encoder_meta] end)
  end
        

  @doc """
  Returns a list of element ids in the order they should be encoded/decoded.  The default function
  takes a guess, that the keys for children and text are interleaved and that the list of children
  or text which is the longest appears first.

  ## Examples:

      iex> %NDS{data: %{"text" => ["a", "b"], a: 1, b: 2}, attr_list: [a: 1, b: 2], child_list: %{"child" => %NDS{data: %{"text" => "c"}}}}
      iex> |> NDS.EncoderDefault.default_order()
      ["text", "child", "text"]

      iex> %NDS{data: %{"text" => ["a", "b", "c"], a: 1}, child_list: %{"d" => %NDS{data: %{"text" => "c"}}},
      iex>   private: %{meta: %{order: ["text", "text", "child", "text"]}}
      iex> }
      iex> |> NDS.EncoderDefault.default_order()
      ["text", "text", "child", "text"]
  """
  def default_order(%NDS{private: %{meta: %{order: order}}}), do: order
  def default_order(nds) do
    order_keys = Enum.filter(Map.keys(nds.data), fn k -> k not in nds.attr_list end)
    child_keys =
      Map.keys(nds.child_list)
      |> Enum.map(fn k -> order_item(k, nds.child_list[k]) end)
      |> List.flatten()
    text_keys =
      Enum.filter(order_keys, fn k -> k not in child_keys ++ Keyword.keys(nds.attr_list) end)
      |> Enum.reduce([], fn k, acc -> acc ++ order_item(k, nds.data[k]) end)

    interleave(text_keys, child_keys)
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
  def order_item(k, value) when is_list(value), do: List.duplicate(k, length(value))
  def order_item(k, _), do: [k]

  @doc """
  This function takes two lists and combines them into a new list alternatiting elements between each list.
  The first element is always from the longest list, and the lists do not have to be the same length, when
  list is empty, the remaining elements are appended to the accumulator.

  ## Examples

      iex> NDS.EncoderDefault.interleave([1, 2, 3], ["a", "b"])
      [1, "a", 2, "b", 3]

      iex> NDS.EncoderDefault.interleave([1, 2], ["a", "b", "c"])
      ["a", 1, "b", 2, "c"]

      iex> NDS.EncoderDefault.interleave([1, 2, 3], ["a"])
      [1, "a", 2, 3]
  """
  def interleave(a, b) when length(a) >= length(b), do: interleave(a, b, [])
  def interleave(a, b), do: interleave(b, a, [])
  
  defp interleave([], [], acc), do: acc
  defp interleave([a|a_rest], [b|b_rest], acc), do: interleave(a_rest, b_rest, acc ++ [a, b])
  defp interleave(a, [], acc), do: acc ++ a
  defp interleave([], b, acc), do: acc ++ b
end

