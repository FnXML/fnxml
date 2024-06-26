defmodule XMLStreamTools.ToXMLTest do
  use ExUnit.Case
  #  alias XMLStreamTools.Inspector
  alias XMLStreamTools.XMLStream
  doctest XMLStream

  test "test to_xml_text" do
    xml = "<foo a='1'>first element<bar>nested element</bar></foo>"

    result = XMLStreamTools.Parser.parse(xml) |> IO.inspect(label: "to_xml")
    assert "ok" == false
  end
end
