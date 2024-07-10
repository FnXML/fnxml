defmodule FnXML.Stream.NativeDataStruct.Format.Map do
  alias FnXML.Stream.NativeDataStruct, as: NDS

  @behaviour NDS.Formatter

  @doc """
  Emit returns a list of XML stream elements.

  ## Examples

      iex> data = %{"a" => "hi", "b" => %{"info" => "info", a: 1, b: 1}, c: "hi", d: 4}
      iex> meta = NDS.EncoderDefault.encode(data, [tag_from_parent: "foo"])
      iex> NDS.Format.Map.emit(meta)
      %{
        "a" => "hi", :c => "hi", :d => 4,
        "b" => %{ "info" => "info", :a => 1, :b => 1 }
      }
  """
  @impl NDS.Formatter
  def emit(meta, opts \\ [])
  def emit(%NDS{} = meta, opts) do
    children =
      meta.order_id_list
      |> Enum.map(fn key -> emit_data(key, meta.child_list[key], meta.data[key], opts) end)
      |> Enum.into(%{})
    attributes =
      meta.attr_list
      |> Enum.into(%{})
    Map.merge(children, attributes)
  end

  def emit(list, opts) when is_list(list), do: Enum.map(list, fn x -> emit(x, opts) end)


  def emit_data(key, child, _, opts) when not is_nil(child), do: {key, emit(child, opts)}
  def emit_data(key, _, data, _) when not is_nil(data), do: {key, data}
  def emit_data(_, _, _, _), do: {}
end

