defmodule FnXML.Stream.NativeDataStruct.Format.Struct do
  alias FnXML.Stream.NativeDataStruct, as: NDS

  @behaviour NDS.Formatter

  @doc """
  Emit returns a list of XML stream elements.

  `:remap_fn` option is used to remap the meta data keys to the struct fields.  (this overrides the default behavior)
  `:tag_map` option is used to map the struct fields to the meta data keys.

  `:tag_map`: can be a map like:
    %{struct_field: meta_key}

  It can also be a map with a list of possible meta keys; (the first
  one found will be used)
    %{struct_field: [meta_key1, meta_key2, ...]}

  It can also be a tuple with the following fields:
    %{struct_field: {meta_key_list, default_value}}

  it can be a function that takes the meta data and returns the value
  to use for the struct field.  This is how mapping to a different
  child struct can be done.

  %[struct_field: fn(meta) -> meta.child_list["key"] |> NDS.Format.Struct.emit(NDS_SubTest, tag_map: %{a: "a", b: "b"})]

  The default mapping behavior is to find the struct field that
  matches a field in the meta data.  If there is a 1 to 1
  correspondence, then the tag_map is not needed.

  """
  @impl NDS.Formatter
  def emit(meta, struct, opts \\ [])
  def emit(%NDS{} = meta, struct, opts) do
    tag_map = Keyword.get(opts, :tag_map, %{})
    remap_fn = Keyword.get(opts, :remap_fn, &remap_fn/3)

    remap_fn.(meta, struct, tag_map)
  end

  def emit(list, struct, opts) when is_list(list), do: Enum.map(list, fn x -> emit(x, struct, opts) end)

  def remap_fn(meta, struct_id, tag_map) do
    s = struct(struct_id)
    keys = Map.keys(s) |> Enum.filter(&(&1 != :__struct__))

    fields = Enum.map(keys, fn key -> {key, collect_values(meta, tag_map[key] || key)} end)
    struct(struct_id, fields)
  end

  def collect_values(meta, fun) when is_function(fun, 1), do: fun.(meta)
  def collect_values(meta, key), do: get_value(meta.child_list[key], meta.data[key])

  def get_value(child, _) when not is_nil(child), do: child
  def get_value(_, data) when not is_nil(data), do: data
  def get_value(_, _), do: nil
end
#
