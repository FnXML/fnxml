defmodule XMLStreamTools.NativeDataTypeTest do
  use ExUnit.Case
  doctest XMLStreamTools.Parser

  alias XMLStreamTools.NativeDataType, as: NDT

  test "value" do
    map = "world"
    assert NDT.to_xml_stream(map, tag: "hello") == [
      open_tag: [tag: "hello"],
      text: ["world"],
      close_tag: [tag: "hello"]
    ]
  end

  test "list" do
    map = ["hello", "world"]
    assert NDT.to_xml_stream(map, tag: "greeting") == [
      open_tag: [tag: "greeting"],
      text: ["hello"],
      close_tag: [tag: "greeting"],
      open_tag: [tag: "greeting"],
      text: ["world"],
      close_tag: [tag: "greeting"]
    ]
  end

  test "base map" do
    map = %{ :a => "1" }
    assert NDT.to_xml_stream(map, tag: "foo") == [
      open_tag: [tag: "foo", attr: [{"a", "1"}]],
      close_tag: [tag: "foo"]
    ]
  end
  
  test "minimal map" do
    map = %{ :_meta => %{tag: "minimal"}, :_text => "hi" }
    assert NDT.to_xml_stream(map) == [
      open_tag: [tag: "minimal"],
      text: ["hi"],
      close_tag: [tag: "minimal"]
    ]
  end
  
  test "test 1" do
    map = %{
      :_meta => %{tag: "foo", loc: {{1, 0}, 1}, order: [:_text]},
      :_namespace => "ns",
      :a => "1",
      :_text => ["bar"]
    }
    assert NDT.to_xml_stream(map) == [
      open_tag: [tag: "foo", namespace: "ns", attr: [{"a", "1"}]],
      text: ["bar"],
      close_tag: [tag: "foo", namespace: "ns"]
    ]
  end

  test "complex test 1" do
    map = %{
      :_meta => %{tag: "bar", order: ["baz", :_text, "biz", :_text]},
      :_namespace => "foo",
      :a => "1",
      :ook => "2",
      :_text => [ "text goes between baz and biz tags", "at the end"],
      "baz" => [
        %{ :a => "1", :_text => ["message"] },
        %{ :b => "2", :_text => ["other message"] },
        %{ :_text => ["other message"], "deep_tag" => %{ :_text => "deep message" } }
      ],
      "biz" => %{
        :_meta => %{tag: "boing", order: [:_text]},
        :_text => ["last tag message"]
      }
    }
    assert NDT.to_xml_stream(map) == [
      open_tag: [tag: "bar", namespace: "foo", attr: [{"a", "1"}, {"ook", "2"}]],
      open_tag: [tag: "baz", attr: [{"a", "1"}]],
      text: ["message"],
      close_tag: [tag: "baz"],
      open_tag: [tag: "baz", attr: [{"b", "2"}]],
      text: ["other message"],
      close_tag: [tag: "baz"],
      open_tag: [tag: "baz"],
      text: ["other message"],
      open_tag: [tag: "deep_tag"],
      text: ["deep message"],
      close_tag: [tag: "deep_tag"],
      close_tag: [tag: "baz"],
      text: ["text goes between baz and biz tags"],
      open_tag: [tag: "boing"],
      text: ["last tag message"],
      close_tag: [tag: "boing"],
      text: ["at the end"],
      close_tag: [tag: "bar", namespace: "foo"]
    ]
  end
end
