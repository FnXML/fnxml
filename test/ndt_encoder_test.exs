defmodule XMLStreamTools.NativeDataType.MetaDefaultTest do
  use ExUnit.Case

  alias XMLStreamTools.NativeDataType, as: NDT
  alias XMLStreamTools.NativeDataType.Meta, as: NDT_Meta
  alias XMLStreamTools.NativeDataType.MetaDefault, as: NDT_MetaDefault

  doctest XMLStreamTools.NativeDataType.MetaDefault


  test "value" do
    map = "world"
    assert NDT.to_xml_stream(map, tag: "hello") == [
      open_tag: [tag: "hello"],
      text: ["world"],
      close_tag: [tag: "hello"]
    ]
  end
end
