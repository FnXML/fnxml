defmodule FnXML.Stream.NativeDataStructTest do
  use ExUnit.Case

  alias FnXML.Stream.NativeDataStruct, as: NDS

  doctest FnXML.Stream.NativeDataStruct


  test "value" do
    map = "world"
    assert NDS.encode(map, tag: "hello") == [
      open: [tag: "hello"],
      text: ["world"],
      close: [tag: "hello"]
    ]
  end

  test "list" do
    map = ["hello", "world"]
    assert NDS.encode(map, tag: "greeting") == [
      open: [tag: "greeting"],
      text: ["hello"],
      close: [tag: "greeting"],
      open: [tag: "greeting"],
      text: ["world"],
      close: [tag: "greeting"]
    ]
  end

  test "base map" do
    map = %{ :a => "1" }
    NDS.Encoder.encode(map, tag: "foo")
    assert NDS.encode(map, tag: "foo") == [
      open: [tag: "foo", close: true, attributes: [{"a", "1"}]]
    ]
  end

  test "minimal map" do
    map = %{ "text" => "hi" }
    assert NDS.encode(map, [tag: "minimal"]) == [
      open: [tag: "minimal"],
      text: ["hi"],
      close: [tag: "minimal"]
    ]
  end

  test "encode 1" do
    map = %{
      :a => "1",
      "t" => ["bar"]
    }
    assert NDS.encode(map, [tag_from_parent: "foo", namespace: "ns", order: ["t"]]) == [
      open: [tag: "foo", namespace: "ns", attributes: [{"a", "1"}]],
      text: ["bar"],
      close: [tag: "foo", namespace: "ns"]
    ]
  end

  test "complex encode 1" do
    map = %{
      :a => "1",
      :ook => "2",
      "text" => [ "text goes between baz and biz tags", "at the end"],
      "baz" => [
        %{ :a => "1", "text" => ["message"] },
        %{ :b => "2", "text" => ["other message"] },
        %{ "text" => ["other message"], "deep_tag" => %{ "t" => "deep message" } }
      ],
      "biz" => %{ "text" => ["last tag message"] }
    }

    encode =
      NDS.Encoder.encode(
        map, tag_from_parent: "bar", namespace: "foo", order: ["baz", "baz", "baz", "text", "biz", "text"]
      )
      |> NDS.Format.XML.emit()
    
    assert encode == [
      open: [tag: "bar", namespace: "foo", attributes: [{"a", "1"}, {"ook", "2"}]],
      open: [tag: "baz", attributes: [{"a", "1"}]],
      text: ["message"],
      close: [tag: "baz"],
      open: [tag: "baz", attributes: [{"b", "2"}]],
      text: ["other message"],
      close: [tag: "baz"],
      open: [tag: "baz"],
      text: ["other message"],
      open: [tag: "deep_tag"],
      text: ["deep message"],
      close: [tag: "deep_tag"],
      close: [tag: "baz"],
      text: ["text goes between baz and biz tags"],
      open: [tag: "biz"],
      text: ["last tag message"],
      close: [tag: "biz"],
      text: ["at the end"],
      close: [tag: "bar", namespace: "foo"]
    ]

    assert FnXML.Stream.to_xml(encode, pretty: true) |> Enum.join() == """
    <foo:bar a=\"1\" ook=\"2\">
      <baz a=\"1\">
        message
      </baz>
      <baz b=\"2\">
        other message
      </baz>
      <baz>
        other message
        <deep_tag>
          deep message
        </deep_tag>
      </baz>
      text goes between baz and biz tags
      <biz>
        last tag message
      </biz>
      at the end
    </foo:bar>
    """
  end
end
