defmodule FnXML.Stream.NativeDataStruct.Format.MapTest do
  use ExUnit.Case

  alias FnXML.Stream.NativeDataStruct, as: NDS

  doctest NDS.Format.Map

  test "map test" do
    data = %{"a" => "hi", "b" => %{"info" => "info", a: 1, b: 1}, c: "hi", d: 4}
    meta = NDS.Encoder.encode(data, [tag_from_parent: "foo"])

    assert NDS.Format.Map.emit(meta) == %{
      "foo" => %{
        "a" => "hi", :c => "hi", :d => "4",
        "b" => %{
          "info" => "info", :a => "1", :b => "1",
          _meta: %{tag: "b", order: ["info"]}
        },
        _meta: %{tag: "foo", order: ["a", "b"]}
      }
    }
  end

  def apply_test(xml, data, opts \\ [])
  def apply_test(xml, data, opts) do
    parsed_data = FnXML.Map.decode(xml, opts) |> Enum.at(0)

    assert parsed_data == data

    key = Map.keys(parsed_data) |> Enum.at(0)
    encoded_data = FnXML.Map.encode(parsed_data[key], tag_from_parent: key)
    assert encoded_data == xml
  end

  def ns_only_meta(%NDS{namespace: ns}) do
    if ns != nil, do: %{_meta: %{namespace: ns}}, else: %{}
  end

  test "parse simple tag" do
    data = %{"foo" => %{}}
    decode =
      FnXML.Parser.parse("<foo></foo>")
      |> NDS.decode(format_meta: &NDS.no_meta/1)
      |> Enum.at(0)

    encode =
      NDS.encode(decode["foo"], [tag_from_parent: "foo"])
      |> FnXML.Stream.to_xml([])
      |> Enum.join()
    assert decode == data
    assert encode == "<foo/>"
  end

  @tag :skip
  test "parse short tag" do
     apply_test("<bar/>", %{"bar" => %{}}, format_meta: &NDS.no_meta/1)
   end
  
  test "parse tag with content" do
     apply_test("<tag>content</tag>", %{"tag" => %{ "text" => "content"}},
       format_meta: &NDS.no_meta/1,
       format_finalize: &NDS.format_raw/1
     )
  end

  test "parse tag with nested tags" do
    apply_test(
      "<tag><nested>content</nested></tag>",
      %{"tag" => %{"nested" => %{ "text" => "content"}}},
      format_meta: &NDS.no_meta/1,
      format_finalize: fn map -> map end
    )
  end

  test "parse tag with multiple nested tags of the same name" do
    apply_test(
      "<tag><nested>content1</nested><nested>content2</nested></tag>",
      %{
        "tag" => %{
          "nested" => ["content1", "content2"],
        }
      },
      format_meta: &NDS.no_meta/1
    )
  end

  @tag focus: true
  test "parse nested tags with content in between" do
    apply_test(
      "<tag><nested>content1</nested>sandwich content<nested>content3</nested>other info<nested>last</nested></tag>",
      %{
        "tag" => %{
          "nested" => ["content1", "content3", "last" ], "text" => ["sandwich content", "other info"],
          :_meta => %{tag: "tag", order: ["nested", "text", "nested", "text", "nested"]}
        }
      }
    )
  end

  test "parse tag with namespace" do
    apply_test(
      "<root ns:myapp=\"http://org/app/\"><nested><myapp:info>content</myapp:info></nested></root>",
      %{
        "root" => %{
          "nested" => %{        
            "info" => %{
              "text" => "content",
              :_meta => %{ namespace: "myapp" }
            }
          },
          "ns:myapp": "http://org/app/"
        }
      },
      format_meta: &NDS.meta_ns_only/1,
      namespace: fn nds -> get_in(nds.private, [:meta, :namespace]) || "" end
    )
  end

  test "parse tag with attributes" do
    apply_test(
      "<tag attr1=\"value1\" attr2=\"value2\"/>",
      %{"tag" => %{attr1: "value1", attr2: "value2"}},
      format_meta: &NDS.no_meta/1
    )
  end

  test "parse tag with attributes and content" do
    apply_test(
      "<tag attr1=\"value1\" attr2=\"value2\">content</tag>",
      %{"tag" => %{"text" => "content", attr1: "value1", attr2: "value2"}},
      format_meta: &NDS.no_meta/1
    )
  end

  test "parse tag with nested tags and attributes" do
    apply_test(
      "<tag><nested attr1=\"value1\" attr2=\"value2\">content</nested></tag>",
      %{"tag" => %{"nested" => %{"text" => "content", attr1: "value1", attr2: "value2"}}},
      format_meta: &NDS.no_meta/1
    )
  end

  test "finalize" do
    apply_test(
      "<bar><foo>a</foo><foo>b</foo><foo last=\"true\">c</foo></bar>",
      %{
        "bar" => %{
          "foo" => [ "a", "b", %{ "text" => "c", last: "true"}]
        }
      },
      format_meta: &NDS.no_meta/1
    )
  end
end
