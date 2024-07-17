defmodule FnXML.StreamTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  doctest FnXML.Stream

  def all_lines_start_with?(lines, prefix) do
    String.split(lines, "\n")
    |> Enum.filter(fn line -> String.trim(line) != "" end)
    |> Enum.all?(fn line -> String.starts_with?(line, prefix) end)
  end

  test "test tap" do
    xml = "<foo a='1'>first element<bar>nested element</bar></foo>"

    assert capture_io(fn -> 
      FnXML.Parser.parse(xml)
      |> FnXML.Stream.tap(label: "test_stream")
      |> Enum.map(fn x -> x end)
    end)
    |> all_lines_start_with?("test_stream:")
  end

  test "test to_xml_text" do
    xml = "<foo a=\"1\">first element<bar>nested element</bar></foo>"

    assert (FnXML.Parser.parse(xml) |> FnXML.Stream.to_xml()) |> Enum.join() == xml
  end


  test "transform" do
    xml = "<foo a='1'>first element<bar>nested element</bar></foo>"

    result =
      FnXML.Parser.parse(xml)
      |> FnXML.Stream.transform(fn el, _path, acc -> {el, acc} end)
      # remove loc meta data, to make assert simpler
      |> Enum.map(fn {id, [tag | meta]} -> {id, [tag | Keyword.drop(meta, [:loc])]} end)

    assert result == [
      open_tag: [tag: "foo", attr_list: [{"a", "1"}]],
      text: ["first element"],
      open_tag: [tag: "bar"],
      text: ["nested element"],
      close_tag: [tag: "bar"],
      close_tag: [tag: "foo"]
    ]
  end

  test "open/close tag, depth 1 decode" do
    # this requires the open tag to add the tag to the stack, then immediately remove it before going to the
    # next element
    stream = [
      open_tag: [tag: "bar"],
      open_tag: [tag: "foo", close: true],
      close_tag: [tag: "bar"]
    ]
    result =
      FnXML.Stream.transform(stream, fn el, _path, acc -> {el, acc} end)
      |> Enum.map(fn x -> x end)
    
    assert result == stream
  end
end
