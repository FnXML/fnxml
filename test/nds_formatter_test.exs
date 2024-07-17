defmodule FnXML.Stream.NativeDataStruct.Format.XMLTest do
  use ExUnit.Case

  alias FnXML.Stream.NativeDataStruct, as: NDS

  doctest NDS.Format.XML

  describe "Format NDS to XML Stream:" do
    test "value" do
      assert NDS.encode("world", tag: "hello") == [
        open_tag: [tag: "hello"],
        text: ["world"],
        close_tag: [tag: "hello"]
      ]
    end

    test "basic map" do
      map = %{ "text" => "hi", :a => "1" }
      assert NDS.encode(map, tag: "foo") == [
        open_tag: [tag: "foo", attr_list: [a: "1"]],
        text: ["hi"],
        close_tag: [tag: "foo"]
      ]
    end

    test "nested map" do
      map = %{
        :a => "1",
        "text" => "world",
        "child" => %{
          :b => "2",
          "text" => "child world"
        }
      }

      assert NDS.encode(map, tag_from_parent: "hello") == [
        open_tag: [tag: "hello", attr_list: [a: "1"]],
        text: ["world"],
        open_tag: [tag: "child", attr_list: [b: "2"]],
        text: ["child world"],
        close_tag: [tag: "child"],
        close_tag: [tag: "hello"]
      ]
    end

    test "nested map with child list" do
      map = %{
        :a => "1",
        "text" => "world",
        "child" => [
          %{ :b => "1", "text" => "child world" },
          %{ :b => "2", "text" => "child alt world" },
          %{ :b => "3", "text" => "child other world" }
        ]
      }

      assert NDS.encode(map, tag_from_parent: "hello") == [
        open_tag: [tag: "hello", attr_list: [a: "1"]],
        open_tag: [tag: "child", attr_list: [b: "1"]],
        text: ["child world"],
        close_tag: [tag: "child"],
        text: ["world"],
        open_tag: [tag: "child", attr_list: [b: "2"]],
        text: ["child alt world"],
        close_tag: [tag: "child"],
        open_tag: [tag: "child", attr_list: [b: "3"]],
        text: ["child other world"],
        close_tag: [tag: "child"],
        close_tag: [tag: "hello"]
      ]
    end
  end
end
