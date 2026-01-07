defmodule FnXML.Stream.NativeDataStructTest do
  use ExUnit.Case

  alias FnXML.Stream.NativeDataStruct, as: NDS

  doctest FnXML.Stream.NativeDataStruct

  describe "encode" do
    test "value" do
      map = "world"

      result = NDS.encode(map, tag: "hello")
      # New format: {:open, tag, attrs, loc}, {:text, content, loc}, {:close, tag}
      assert match?([{:open, "hello", [], nil}, {:text, "world", nil}, {:close, "hello"}], result)
    end

    test "list" do
      map = ["hello", "world"]

      result = NDS.encode(map, tag: "greeting")
      assert length(result) == 6
      assert match?({:open, "greeting", [], nil}, Enum.at(result, 0))
      assert match?({:text, "hello", nil}, Enum.at(result, 1))
      assert match?({:close, "greeting"}, Enum.at(result, 2))
    end

    test "base map" do
      map = %{:a => "1"}
      NDS.Encoder.encode(map, tag: "foo")

      result = NDS.encode(map, tag: "foo")
      # Empty content elements get open + close
      assert length(result) == 2
      assert match?({:open, "foo", [{"a", "1"}], nil}, Enum.at(result, 0))
      assert match?({:close, "foo"}, Enum.at(result, 1))
    end

    test "minimal map" do
      map = %{"text" => "hi"}

      result = NDS.encode(map, tag: "minimal")
      assert match?(
        [{:open, "minimal", [], nil}, {:text, "hi", nil}, {:close, "minimal"}],
        result
      )
    end

    test "encode 1" do
      map = %{
        :a => "1",
        "t" => ["bar"]
      }

      result = NDS.encode(map, tag_from_parent: "foo", namespace: "ns", order: ["t"])
      assert match?({:open, "ns:foo", [{"a", "1"}], nil}, Enum.at(result, 0))
      assert match?({:text, "bar", nil}, Enum.at(result, 1))
      assert match?({:close, "ns:foo"}, Enum.at(result, 2))
    end

    test "complex encode 1" do
      map = %{
        :a => "1",
        :ook => "2",
        "text" => ["text goes between baz and biz tags", "at the end"],
        "baz" => [
          %{:a => "1", "text" => ["message"]},
          %{:b => "2", "text" => ["other message"]},
          %{"text" => ["other message"], "deep_tag" => %{"t" => "deep message"}}
        ],
        "biz" => %{"text" => ["last tag message"]}
      }

      encode =
        NDS.Encoder.encode(
          map,
          tag_from_parent: "bar",
          namespace: "foo",
          order: ["baz", "baz", "baz", "text", "biz", "text"]
        )
        |> NDS.Format.XML.emit()

      # Check structure - new format uses tuples
      assert match?({:open, "foo:bar", _, nil}, Enum.at(encode, 0))

      # Test the XML output which is format-agnostic
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
end
