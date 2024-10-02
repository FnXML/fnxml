defmodule FnXML.Stream.DecoderTest do
  use ExUnit.Case

  alias FnXML.Stream.Decoder
  alias FnXML.Element

  doctest Decoder
  doctest Decoder.Default

  @tag focus: true
  test "tag" do
    result =
      [open: [tag: "a"], close: [tag: "a"]]
      |> FnXML.Stream.Decoder.decode()
      |> Enum.at(0)

    assert result == [{:tag, "a"}]
  end

  test "tag with all meta" do
    result =
      [
        open: [tag: "ns:hello", attributes: [{"a", "1"}]],
        text: [content: "world"],
        close: [tag: "ns:hello"]
      ]
      |> FnXML.Stream.Decoder.decode()
      |> Enum.at(0)

    assert result == [tag: "ns:hello", attributes: [{"a", "1"}], text: [content: "world"]]
  end

  test "decode with child" do
    result =
      [
        open: [tag: "ns:hello", attributes: [{"a", "1"}]],
        text: [content: "hello"],
        open: [tag: "child", attributes: [{"b", "2"}]],
        text: [content: "child world"],
        close: [tag: "child"],
        text: [content: "world"],
        close: [tag: "ns:hello"]
      ]
      |> FnXML.Stream.Decoder.decode()
      |> Enum.at(0)

    assert result == [
             tag: "ns:hello",
             attributes: [{"a", "1"}],
             text: [content: "hello"],
             child: [tag: "child", attributes: [{"b", "2"}], text: [content: "child world"]],
             text: [content: "world"]
           ]
  end


  def handler(element, path, opts, acc \\ %{})
  def handler([], _path, _opts, element), do: {element.tag |> elem(0) |> String.to_atom(), element}
  def handler([item | rest], path, opts, acc), do: handler(rest, path, opts, handle_item(item, acc))

  def handle_item({:tag, _} = tag, acc), do: Map.merge(acc, %{ tag: Element.tag([tag]), content: []})
  def handle_item({:attributes, attrs}, acc), do: Map.merge(acc, %{ attributes: attrs})
  def handle_item({:loc, _}, acc), do: acc
  def handle_item({:text, [{:content, t}]}, acc), do: %{acc | content: Listy.insert(acc.content, {:text, t})}
  def handle_item(item, acc), do: %{acc | content: Listy.insert(acc.content, item)}


  test "decode using handler" do
                                        
    result =
      [
        open: [tag: "ns:hello", attributes: [{"a", "1"}]],
        text: [content: "hello"],
        open: [tag: "child", attributes: [{"b", "2"}]],
        text: [content: "child world"],
        open: [tag: "grandchild", attributes: [{"c", "3"}]],
        close: [tag: "grandchild"],
        close: [tag: "child"],
        text: [content: "world"],
        close: [tag: "ns:hello"]
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
