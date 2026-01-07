defmodule FnXML.Stream.DecoderTest do
  use ExUnit.Case

  alias FnXML.Stream.Decoder
  alias FnXML.Element

  doctest Decoder
  doctest Decoder.Default

  @tag focus: true
  test "tag" do
    # New format: {:open, tag, attrs, loc}
    result =
      [{:open, "a", [], {1, 0, 1}}, {:close, "a"}]
      |> FnXML.Stream.Decoder.decode()
      |> Enum.at(0)

    # Default decoder produces internal format with :tag, :attributes, :loc keys
    # Order may vary, so check individual keys
    assert Keyword.get(result, :tag) == "a"
    assert Keyword.get(result, :attributes) == []
    assert Keyword.get(result, :loc) == {1, 0, 1}
  end

  test "tag with all meta" do
    result =
      [
        {:open, "ns:hello", [{"a", "1"}], {1, 0, 1}},
        {:text, "world", {1, 0, 20}},
        {:close, "ns:hello"}
      ]
      |> FnXML.Stream.Decoder.decode()
      |> Enum.at(0)

    assert Keyword.get(result, :tag) == "ns:hello"
    assert Keyword.get(result, :attributes) == [{"a", "1"}]
    assert Keyword.get(result, :loc) == {1, 0, 1}
    assert Keyword.get(result, :text) == "world"
  end

  test "decode with child" do
    result =
      [
        {:open, "ns:hello", [{"a", "1"}], {1, 0, 1}},
        {:text, "hello", {1, 0, 15}},
        {:open, "child", [{"b", "2"}], {1, 0, 25}},
        {:text, "child world", {1, 0, 40}},
        {:close, "child"},
        {:text, "world", {1, 0, 60}},
        {:close, "ns:hello"}
      ]
      |> FnXML.Stream.Decoder.decode()
      |> Enum.at(0)

    assert Keyword.get(result, :tag) == "ns:hello"
    assert Keyword.get(result, :attributes) == [{"a", "1"}]
    assert Keyword.get(result, :loc) == {1, 0, 1}
    # Check that we have text entries and a child
    texts = Keyword.get_values(result, :text)
    assert "hello" in texts
    assert "world" in texts
    child = Keyword.get(result, :child)
    assert Keyword.get(child, :tag) == "child"
    assert Keyword.get(child, :text) == "child world"
  end


  def handler(element, path, opts, acc \\ %{})
  def handler([], _path, _opts, element), do: {element.tag |> elem(0) |> String.to_atom(), element}
  def handler([item | rest], path, opts, acc), do: handler(rest, path, opts, handle_item(item, acc))

  def handle_item({:tag, t}, acc), do: Map.merge(acc, %{ tag: Element.tag(t), content: []})
  def handle_item({:attributes, attrs}, acc), do: Map.merge(acc, %{ attributes: attrs})
  def handle_item({:loc, _}, acc), do: acc
  def handle_item({:text, t}, acc), do: %{acc | content: Listy.insert(acc.content, {:text, t})}
  def handle_item(item, acc), do: %{acc | content: Listy.insert(acc.content, item)}


  test "decode using handler" do

    result =
      [
        {:open, "ns:hello", [{"a", "1"}], {1, 0, 1}},
        {:text, "hello", {1, 0, 15}},
        {:open, "child", [{"b", "2"}], {1, 0, 25}},
        {:text, "child world", {1, 0, 40}},
        {:open, "grandchild", [{"c", "3"}], {1, 0, 55}},
        {:close, "grandchild"},
        {:close, "child"},
        {:text, "world", {1, 0, 80}},
        {:close, "ns:hello"}
      ]
      |> FnXML.Stream.Decoder.decode(FnXML.Stream.Decoder.Default, handle_element: &handler/3)
      |> Enum.at(0)

    assert result == {
      :hello,
      %{
        attributes: [{"a", "1"}],
        tag: {"hello", "ns"},
        content: [
          text: "world",
          child: %{
            attributes: [{"b", "2"}],
            tag: {"child", ""},
            content: [
              grandchild: %{attributes: [{"c", "3"}], tag: {"grandchild", ""}, content: []},
              text: "child world"
            ]
          },
          text: "hello"
        ]
      }
    }
  end
end
