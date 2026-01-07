defmodule FnXML.Stream.NativeDataStruct.DecoderTest do
  use ExUnit.Case

  alias FnXML.Stream.NativeDataStruct, as: NDS

  doctest NDS.Decoder

  test "tag" do
    # New format: {:open, tag, attrs, loc}
    result =
      [{:open, "a", [], {1, 0, 1}}, {:close, "a"}]
      |> NDS.Decoder.decode()
      |> Enum.at(0)

    assert result == %NDS{tag: "a", source: [{1, 1}]}
  end

  test "tag with namespace" do
    result =
      [{:open, "ns:a", [], {1, 0, 1}}, {:close, "ns:a"}]
      |> NDS.Decoder.decode()
      |> Enum.at(0)

    assert result == %NDS{tag: "a", namespace: "ns", source: [{1, 1}]}
  end

  test "tag with attributes" do
    result =
      [{:open, "a", [{"b", "c"}, {"d", "e"}], {1, 0, 1}}, {:close, "a"}]
      |> NDS.Decoder.decode([])
      |> Enum.at(0)

    assert result == %NDS{tag: "a", attributes: [{"b", "c"}, {"d", "e"}], source: [{1, 1}]}
  end

  test "tag with text" do
    result =
      [{:open, "a", [], {1, 0, 1}}, {:text, "b", {1, 0, 4}}, {:close, "a"}]
      |> NDS.Decoder.decode([])
      |> Enum.at(0)

    assert result == %NDS{tag: "a", content: ["b"], source: [{1, 1}]}
  end

  test "tag with all meta" do
    result =
      [
        {:open, "ns:hello", [{"a", "1"}], {1, 0, 1}},
        {:text, "world", {1, 0, 20}},
        {:close, "ns:hello"}
      ]
      |> NDS.Decoder.decode([])
      |> Enum.at(0)

    assert result == %NDS{
             tag: "hello",
             namespace: "ns",
             attributes: [{"a", "1"}],
             content: ["world"],
             source: [{1, 1}]
           }
  end

  test "decode with child" do
    result =
      [
        {:open, "ns:hello", [{"a", "1"}], {1, 0, 1}},
        {:text, "hello", {1, 0, 20}},
        {:open, "child", [{"b", "2"}], {1, 0, 30}},
        {:text, "child world", {1, 0, 45}},
        {:close, "child"},
        {:text, "world", {1, 0, 70}},
        {:close, "ns:hello"}
      ]
      |> NDS.Decoder.decode([])
      |> Enum.at(0)

    assert result ==
             %NDS{
               tag: "hello",
               attributes: [{"a", "1"}],
               namespace: "ns",
               content: [
                 "hello",
                 %NDS{tag: "child", attributes: [{"b", "2"}], content: ["child world"], source: [{1, 30}]},
                 "world"
               ],
               source: [{1, 1}]
             }
  end

  test "decode with child list" do
    result =
      [
        {:open, "ns:hello", [{"a", "1"}], {1, 0, 1}},
        {:text, "hello", {1, 0, 15}},
        {:open, "child1", [{"b", "2"}], {2, 13, 14}},
        {:text, "child world", {2, 13, 28}},
        {:close, "child1"},
        {:open, "child1", [{"b", "2"}], {2, 13, 34}},
        {:text, "alt world", {2, 13, 48}},
        {:close, "child1"},
        {:open, "child2", [{"b", "2"}], {3, 35, 36}},
        {:text, "other worldly", {3, 35, 50}},
        {:close, "child2"},
        {:text, "world", {3, 35, 70}},
        {:close, "ns:hello"}
      ]
      |> NDS.Decoder.decode([])
      |> Enum.at(0)

    assert result ==
             %NDS{
               tag: "hello",
               namespace: "ns",
               attributes: [{"a", "1"}],
               content: [
                 "hello",
                 %NDS{
                   tag: "child1",
                   attributes: [{"b", "2"}],
                   content: ["child world"],
                   source: [{2, 1}]
                 },
                 %NDS{
                   tag: "child1",
                   attributes: [{"b", "2"}],
                   content: ["alt world"],
                   source: [{2, 21}]
                 },
                 %NDS{
                   tag: "child2",
                   attributes: [{"b", "2"}],
                   content: ["other worldly"],
                   source: [{3, 1}]
                 },
                 "world"
               ],
               source: [{1, 1}]
             }
  end
end
