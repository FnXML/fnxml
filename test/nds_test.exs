defmodule FnXML.Stream.NativeDataStructTest do
  use ExUnit.Case

  alias FnXML.Stream.NativeDataStruct, as: NDS

  doctest FnXML.Stream.NativeDataStruct


  test "value" do
    map = "world"
    assert NDS.encode(map, tag: "hello") == [
      open_tag: [tag: "hello"],
      text: ["world"],
      close_tag: [tag: "hello"]
    ]
  end

  test "list" do
    map = ["hello", "world"]
    assert NDS.encode(map, tag: "greeting") == [
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
    assert NDS.encode(map, tag: "foo") == [
      open_tag: [tag: "foo", close: true, attr_list: [a: "1"]],
    ]
  end

  test "minimal map" do
    map = %{ "text" => "hi" }
    assert NDS.encode(map, [tag: "minimal"]) == [
      open_tag: [tag: "minimal"],
      text: ["hi"],
      close_tag: [tag: "minimal"]
    ]
  end

  test "encode 1" do
    map = %{
      :a => "1",
      :text => ["bar"]
    }
    assert NDS.encode(map, [tag_from_parent: "foo", namespace: "ns", order: [:text]]) == [
      open_tag: [tag: "foo", namespace: "ns", attr_list: [a: "1"]],
      text: ["bar"],
      close_tag: [tag: "foo", namespace: "ns"]
    ]
  end

  test "complex encode 1" do
    map = %{
      :a => "1",
      :ook => "2",
      :_text => [ "text goes between baz and biz tags", "at the end"],
      "baz" => [
        %{ :a => "1", :_text => ["message"] },
        %{ :b => "2", :_text => ["other message"] },
        %{ :_text => ["other message"], "deep_tag" => %{ "t" => "deep message" } }
      ],
      "biz" => %{ :_text => ["last tag message"] }
    }

    encode =
      NDS.encode(
        map, tag_from_parent: "bar", namespace: "foo", order: ["baz", "baz", "baz", :_text, "biz", :_text]
      )
    
    assert encode == [
      open_tag: [tag: "bar", namespace: "foo", attr_list: [{:a, "1"}, {:ook, "2"}]],
      open_tag: [tag: "baz", attr_list: [{:a, "1"}]],
      text: ["message"],
      close_tag: [tag: "baz"],
      open_tag: [tag: "baz", attr_list: [{:b, "2"}]],
      text: ["other message"],
      close_tag: [tag: "baz"],
      open_tag: [tag: "baz"],
      text: ["other message"],
      open_tag: [tag: "deep_tag"],
      text: ["deep message"],
      close_tag: [tag: "deep_tag"],
      close_tag: [tag: "baz"],
      text: ["text goes between baz and biz tags"],
      open_tag: [tag: "biz"],
      text: ["last tag message"],
      close_tag: [tag: "biz"],
      text: ["at the end"],
      close_tag: [tag: "bar", namespace: "foo"]
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
