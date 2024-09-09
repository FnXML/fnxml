 defmodule FnXML.Stream.NativeDataStruct.Encoder.Default do
  @moduledoc """
  This Module is used to convert a Native Data Structs (NDS) to a NDS Meta type, which can then be used
  to encode the NDS to an XML stream.

  So this module is used in conjunction with the NativeDataType.Formatter to convert it to an XML stream.

  An encoder takes a native type like a map, and encodes it as a %NDS_Meta{} struct.  This provides all
  the data needed to make the XML stream.  The formatter then takes the %NDS_Meta{} struct and converts it to an XML stream.

  ## Example:

      iex> data = %{"a" => "hi", "b" => %{a: 1, b: 1}, c: "hi", d: 4}
      iex> NDS.Encoder.encode(data, module: NDS.Encoder.Default, tag_from_parent: "foo", text_keys: ["a"])
      iex> |> NDS.TestHelpers.clear_private()
      %NDS{
        tag: "foo",
        attributes: [{"c", "hi"}, {"d", "4"}],
        content: [{:text, "a", "hi"}, {:child, "b", %NDS{tag: "b", attributes: [{"a", "1"}, {"b", "1"}]}}]
      }

  # How a tag name is determined:
  - option: :tag_from_parent value (this is automatically set for nested structures
  - name of structure if it is a struct
  
  """
  alias FnXML.Stream.NativeDataStruct, as: NDS
  
  @behaviour NDS.Encoder

  @impl NDS.Encoder
  def meta(nds, map) do
    %NDS{nds | private: put_in(nds.private, [:meta], Map.get(map, :_meta, %{}))}
    |> fn nds -> %NDS{nds | namespace: namespace(nds)} end.()
    |> fn nds -> %NDS{nds | tag: tag(nds, map)} end.()
    |> fn nds -> %NDS{nds | attributes: attributes(map)} end.()
  end

  @impl NDS.Encoder
  def content(nds, map) do
    text_keys = text_keys(nds, map)
    attribute_keys = Enum.map(nds.attributes, fn {k, _} -> String.to_atom(k) end)

    %NDS{ nds | content:
          key_order(nds, map, [:_meta | attribute_keys], text_keys)
          |> encode_item_list(nds)
    }
  end


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
  find tag for nds

  1. use `:tag_from_parent` option if provided.
  2. if the data is a struct, use the type of the struct
  3. default to "root"

  ## Examples:

      iex> NDS.Encoder.Default.tag(%NDS{private: %{opts: []}}, %{a: 1})
      "root"

      iex> NDS.Encoder.Default.tag(%NDS{private: %{ opts: [ tag_from_parent: "foo" ]}}, %{"a" => 1})
      "foo"
  """
  def tag(nds, src) do
    opts = nds.private[:opts] || []
    meta = nds.private[:meta] || %{}
    {type, _map} = struct_type(src)
    
    Keyword.get(opts, :tag_from_parent) || type || meta[:tag] || Keyword.get(opts, :tag) || "root"
    |> to_string()
  end

  def namespace(nds) do
    opts = nds.private[:opts] || []
    meta = nds.private[:meta] || %{}

    Keyword.get(opts, :namespace) || meta[:namespace] || ""
  end


  @doc """
  default function to calculate attributes, this can be overriden by specifying a list of options or another
  function in opts[:attr]

  ## Examples

      iex> NDS.Encoder.Default.attributes(%{"text" => "not an attribute", a: 1, b: 2})
      [{"a", "1"}, {"b", "2"}]
  """
  def attributes(src) do
    Map.keys(src)
    |> Enum.map(fn k -> {k, src[k], FnXML.Type.type(src[k])} end)
    |> Enum.filter(fn {k, _, type} -> is_atom(k) and type in [String, Integer, Float, Boolean] end)
    |> Enum.map(fn {k, v, _} -> {to_string(k), to_string(v)} end)
    |> Enum.sort(fn {k1, _}, {k2, _} -> k1 < k2 end)
  end
  

  @doc """
  returns sorted list of keys which are first sorted by text keys, then alphabetically
  """
  def key_sort_fn(k1, k2, text_keys) do
    (k1 in text_keys and k2 not in text_keys) or ((k1 in text_keys == k2 in text_keys) and (k1 < k2))
  end

  @doc """
  returns an ordered list of keys.

  A key order can be specified in the `nds.private.opts.order` or `nds.private.meta.order` keys.

  If no order is specified, by default the order will be `text_keys` followed by any child keys
  """
  def key_order(nds, map, attribute_keys, text_keys) do
    opts = nds.private[:opts] || []
    meta = nds.private[:meta] || %{}

    # check opts.order, meta.order, or create a default order
    ( Keyword.get(opts, :order) ||
      meta[:order] ||
      default_key_order(map, attribute_keys, text_keys)
    )
    |> Enum.reduce({[], map}, fn k, {acc, map} ->
      type = %{true => :text, false => :child}[k in text_keys]
      {val, map} = case Map.has_key?(map, k) do
        true -> content_value(k, map, type)
        false -> {[], map}
      end
      {[val | acc], map}
    end)
    |> elem(0)  # get only the acc part, discard the map state
    |> Enum.reverse()
    |> List.flatten()
  end

  def default_key_order(map, attribute_keys, text_keys) do
    # ensure keys with lists are included list-length times in the order list
    Enum.reject(Map.keys(map), fn k -> k in attribute_keys end) 
    |> Enum.sort(fn k1, k2 -> key_sort_fn(k1, k2, text_keys) end)
    |> Enum.reduce([], fn k, acc ->
      case map[k] do
        val when is_list(val) -> [List.duplicate(k, length(val)) | acc]
        _val -> [k | acc]
      end
    end)
    |> Enum.reverse()
    |> List.flatten()
  end

  def content_value(_, nil, map, _), do: {[], map}
  def content_value(k, map, :text) do
    {val, rest} = Listy.pop(map[k])
    {[{:text, k, val}], %{map | k => rest}}
  end
  def content_value(k, map, :child) do
    {val, rest} = Listy.pop(map[k])
    { (if valid_child?(val), do: {:child, k, val}, else: []), %{map | k => rest} }
  end

  @doc """
  given an %NDS{} struct and a map, return a list of keys that are text keys

  The default text keys are "text", "t", or "#".  Any of these will be
  treated as text content by default.

  The default can be overridden by specifying a list of text keys in
  opts[:text_keys], or by sepcifying the keys in the `:_meta` key of
  the map as: `%{:_meta => %{text_keys: ["a", "b"]}}`.
  """
  def text_keys(nds, map) do
    opts = nds.private[:opts] || []
    meta = nds.private[:meta] || %{}

    ( Keyword.get(opts, :text_keys) ||
      meta[:text_keys] ||
      ["text", "t", "#"] )
    ( Keyword.get(opts, :text_keys) || meta[:text_keys] || ["text", "t", "#"] )
    |> Enum.reject(fn k -> not Map.has_key?(map, k) end)
  end

  @doc """
  given a value, return true if it is a valid child value
  """
  def valid_child?(child) when is_map(child), do: true
  def valid_child?([child|_]), do: valid_child?(child)
  def valid_child?(child) when is_binary(child), do: true
  def valid_child?(_), do: false

  @doc """
  Iterate over ther order list and select the key values, or the first item in a list of values
  """
  def encode_item_list(item_list, nds) do
    item_list
    |> Enum.reduce([], fn
      {:text, _, _} = item, acc -> [item | acc]
      {:child, key, val}, acc when is_binary(val) -> [ {:child, key,  encode_child(nds, key, val)} | acc]
      {:child, key, val}, acc -> [ {:child, key, encode_child(nds, key, val)} | acc]
    end)
    |> Enum.reverse()
  end

  def encode_child(nds, key, child) when is_list(child) do
    Enum.map(child, fn v -> NDS.Encoder.encode(v, update_opts(nds, key)) end) 
  end
  def encode_child(nds, key, child) when is_map(child) do
    NDS.Encoder.encode(child, update_opts(nds, key))
  end
  def encode_child(nds, key, child) when is_binary(child) do
    if Keyword.get(nds.private.opts, :text_only_tags, false) do
      NDS.Encoder.encode(%{key => %{"text" => child}}, update_opts(nds, key))
    else
      NDS.Encoder.encode(%{"text" => child}, update_opts(nds, key))
    end
  end

  def update_opts(nds, key), do: [{:tag_from_parent, key} | nds.private[:opts] || []] |> propagate_opts()

  def propagate_opts(opts) do
    Enum.filter(opts, fn {k, v} -> is_function(v) or k in [:tag_from_parent, :encoder_meta] end)
  end
        
  
  @doc """
  for lists, returns a list with the key repeated for each element in the list
  for all other values, returns a list with the key

  ## Examples

      iex> NDS.Encoder.Default.order_item("a", [1, 2, 3])
      ["a", "a", "a"]

      iex> NDS.Encoder.Default.order_item("a", 1)
      ["a"]

      iex> NDS.Encoder.Default.order_item("a", "hello")
      ["a"]
  """
  def order_item(k, value) when is_list(value), do: List.duplicate(k, length(value))
  def order_item(k, _), do: [k]
end

