defmodule FnXML.Stream.NativeDataStruct.Format.Map do
  alias FnXML.Stream.NativeDataStruct, as: NDS

  @behaviour NDS.Formatter

  @doc """
  Emit returns a list of XML stream elements.

  ## Examples

      iex> data = %{"a" => "hi", "b" => %{"info" => "info", a: 1, b: 1}, c: "hi", d: 4}
      iex> nds = NDS.EncoderDefault.encode(data, [tag_from_parent: "foo"])
      iex> NDS.Format.Map.emit(nds)
      %{
        "foo" => %{
          "a" => "hi", :c => "hi", :d => 4,
          "b" => %{ "info" => "info", :a => 1, :b => 1, _meta: %{tag: "b", order: ["info"]} },
          _meta: %{tag: "foo", order: ["a", "b"]}
        }
      }
  """
  @impl NDS.Formatter
  def emit(nds, opts \\ [])
  def emit(%NDS{} = nds, opts) do
    [emit_child(nds, opts)] |> Enum.into(%{})
  end
  def emit(list, opts) when is_list(list) do
    Enum.map(list, fn x -> emit(x, opts) end)
  end

  def emit_child(%NDS{} = nds, opts) do
    meta_fun = Keyword.get(opts, :decode_meta, &default_meta/1)
    attr = Enum.map(nds.attr_list, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} -> { to_string(k) |> String.to_atom(), v}
    end)
    |> Enum.into(%{})

    {
      nds.tag,
      meta_fun.(nds)
      |> Map.merge(attr)
      |> Map.merge(id_list(nds, opts))
    }
  end
  def emit_child([h|_] = list, opts) when is_list(list) do
    {h.tag, Enum.map(list, fn x -> emit_child(x, opts) |> elem(1) end)}
  end

  def id_list(%NDS{} = nds, opts) do
    nds.order_id_list
    |> Enum.map(fn key -> emit_data(key, nds.child_list[key], nds.data[key], opts) end)
    |> Enum.into(%{})
  end

  def emit_data(_, child, _, opts) when not is_nil(child), do: emit_child(child, opts)
  def emit_data(key, _, data, _) when not is_nil(data), do: {key, data}
  def emit_data(_, _, _, _), do: {}

  def default_meta(%NDS{} = nds)do
    namespace = nds.namespace
    order = if nds.order_id_list == [], do: nil, else: nds.order_id_list
    meta =
      %{ tag: nds.tag, namespace: namespace, order: order }
      |> Enum.filter(fn
        {_, v} when is_binary(v) -> v != ""
        {_, v} -> not is_nil(v)
      end)
      |> Enum.into(%{})
    
    %{_meta: meta}
  end
end

