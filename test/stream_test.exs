defmodule FnXML.StreamTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  doctest FnXML.Stream

  def all_lines_start_with?(lines, prefix) do
    String.split(lines, "\n")
    |> Enum.filter(fn line -> String.trim(line) != "" end)
    |> Enum.all?(fn line -> String.starts_with?(line, prefix) end)
  end

  def strip_ws(str), do: String.replace(str, ~r/[\s\r\n]+/, "")

  test "test tap" do
    xml = "<foo a='1'>first element<bar>nested element</bar></foo>"

    assert capture_io(fn ->
             FnXML.Parser.parse(xml)
             |> FnXML.Stream.tap(label: "test_stream")
             |> Enum.map(fn x -> x end)
           end)
           |> all_lines_start_with?("test_stream:")
  end

  describe "to_xml" do
    @tag focus: true
    test "basic" do
      xml = "<foo a=\"1\">first element<bar>nested element</bar></foo>"

      assert FnXML.Parser.parse(xml) |> FnXML.Stream.to_xml() |> Enum.join() == xml
    end

    test "with all elements" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <foo a=\"1\">first element
        <!--comment-->
        <?pi-test this is processing instruction?>
        <bar>nested element</bar>
        <![CDATA[<bar>nested element</bar>]]>
      </foo>
      """

      assert FnXML.Parser.parse(xml) |> FnXML.Stream.to_xml() |> Enum.join() |> strip_ws() ==
               strip_ws(xml)
    end
  end

  describe "transform" do
    test "remove location meta transform" do
      xml = "<foo a='1'>first element<bar>nested element</bar></foo>"

      result =
        FnXML.Parser.parse(xml)
        |> FnXML.Stream.transform(fn element, _path, acc ->
          {element, acc}
        end)
        |> Enum.to_list()

      # New format: {:doc_start, nil}, {:open, tag, attrs, loc}, {:text, content, loc}, etc., {:doc_end, nil}
      assert length(result) == 8
      assert match?({:doc_start, nil}, Enum.at(result, 0))
      assert match?({:open, "foo", [{"a", "1"}], _}, Enum.at(result, 1))
      assert match?({:text, "first element", _}, Enum.at(result, 2))
      assert match?({:open, "bar", [], _}, Enum.at(result, 3))
    end

    test "transform empty tag" do
      # New format: {:open, tag, attrs, loc}
      result =
        [{:open, "a", [], nil}, {:open, "b", [], nil}, {:close, "b"}, {:close, "a"}]
        |> FnXML.Stream.to_xml()
        |> Enum.join()

      assert result == "<a><b></b></a>"
    end
  end

  describe "filter" do
    test "whitespace 0" do
      # New format: {:text, content, loc}
      stream = [
        {:open, "foo", [], nil},
        {:text, "first element", nil},
        {:text, " \t", nil},
        {:text, "  \n\t", nil},
        {:close, "foo"}
      ]

      result = FnXML.Stream.filter_ws(stream) |> Enum.to_list()
      assert length(result) == 3
      assert match?({:open, "foo", [], nil}, Enum.at(result, 0))
      assert match?({:text, "first element", nil}, Enum.at(result, 1))
      assert match?({:close, "foo"}, Enum.at(result, 2))
    end

    test "namespace 0" do
      # New format: {:open, tag, attrs, loc}
      stream = [
        {:open, "foo", [], nil},
        {:open, "biz:bar", [], nil},
        {:close, "biz:bar"},
        {:open, "bar:baz", [], nil},
        {:close, "bar:baz"},
        {:open, "bar", [], nil},
        {:close, "bar"},
        {:open, "baz:buz", [], nil},
        {:close, "baz:buz"},
        {:close, "foo"}
      ]

      result =
        FnXML.Stream.filter_namespaces(stream, ["bar", "baz"], exclude: true) |> Enum.to_list()

      assert length(result) == 6
      tags = Enum.map(result, fn
        {:open, tag, _, _} -> tag
        {:close, tag} -> tag
        {:close, tag, _} -> tag
      end)
      assert tags == ["foo", "biz:bar", "biz:bar", "bar", "bar", "foo"]
    end
  end
end
