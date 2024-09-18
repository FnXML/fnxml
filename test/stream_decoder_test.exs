defmodule FnXML.Stream.DecoderTest do
  use ExUnit.Case

  alias FnXML.Stream.Decoder

  doctest Decoder
  doctest Decoder.Default
  
  test "tag" do
    result = 
      [ open: [tag: "a"], close: [tag: "a"] ]
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

    assert result ==  [
      tag: "ns:hello",
      attributes: [{"a", "1"}],
      text: [content: "hello"],
      child: [tag: "child", attributes: [{"b", "2"}], text: [content: "child world"]],
      text: [content: "world"]
    ]
  end
end
