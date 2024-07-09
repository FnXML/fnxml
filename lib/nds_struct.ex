defmodule FnXML.Stream.NativeDataStruct.Format.Struct do
  alias FnXML.Stream.NativeDataStruct, as: NDS

  @behaviour NDS.Formatter

  @doc """
  Emit returns a list of XML stream elements.

  ## Examples

      iex> data = %{"a" => "hi", "b" => %{"info" => "info", a: 1, b: 1}, c: "hi", d: 4}
      iex> meta = NDS.EncoderDefault.encode(data, [tag_from_parent: "foo"])
      iex> NDS.XML.emit(meta)
      %{
      "a" => "hi"
      :c => "hi"
      :d => 4
      "b" => %{
        "info" => "info"
        :a => 1
        :b => 1
      }
  """
  @impl NDS.Formatter
  def emit(%NDS{} = meta, opts) do
    children =
      meta.child_list |> Map.keys() |> Enum.map(fn key -> {key, emit(meta.child_list[key], opts)} end)
      |> Enum.into(%{})
    attributes =
      meta.attr_list
      |> Enum.into(%{})
    Map.merge(children, attributes)
  end    
end
#
