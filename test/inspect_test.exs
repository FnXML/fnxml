defmodule XMLStreamTools.InspectorTest do
  use ExUnit.Case
  #  alias XMLStreamTools.Inspector
  alias XMLStreamTools.ToMap
  doctest XMLStreamTools.Inspector

  def parse_to_map(xml, opts \\ []) do
    xml
    |> XMLStreamTools.Parser.parse()
    |> XMLStreamTools.Transformer.transform(ToMap.to_map_fn(private: opts))
    |> Enum.map(fn x -> x end)
  end

  # test "test inspect" do
  #   xml = "<foo a='1'>first element<bar>nested element</bar></foo>"

  #   result =
  #     XMLStreamTools.Parser.parse(xml)
  #     |> XMLStreamTools.Transformer.transform(
  #       XMLStreamTools.Inspector.inspect_fn(label: "test_stream")
  #     )
  #     |> Enum.map(fn x -> x end)

  #   IO.inspect(result)
  # end
end
