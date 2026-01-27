defmodule FnXML.Transform.StreamTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  def all_lines_start_with?(lines, prefix) do
    String.split(lines, "\n")
    |> Enum.filter(fn line -> String.trim(line) != "" end)
    |> Enum.all?(fn line -> String.starts_with?(line, prefix) end)
  end

  def strip_ws(str), do: String.replace(str, ~r/[\s\r\n]+/, "")

  describe "tap" do
    test "outputs events with label" do
      xml = "<foo a='1'>text<bar/></foo>"

      assert capture_io(fn ->
               FnXML.Parser.parse(xml)
               |> FnXML.Transform.Stream.tap(label: "test_stream")
               |> Enum.map(& &1)
             end)
             |> all_lines_start_with?("test_stream:")
    end

    test "custom tap function receives events" do
      test_pid = self()
      stream = [{:start_element, "foo", [], 1, 0, 1}, {:end_element, "foo", 1, 0, 10}]

      FnXML.Transform.Stream.tap(stream, fn event, _path -> send(test_pid, {:event, event}) end,
        label: "test"
      )
      |> Enum.to_list()

      assert_received {:event, {:start_element, "foo", [], 1, 0, 1}}
    end
  end

  describe "to_xml" do
    test "roundtrips XML" do
      xml = "<foo a=\"1\">first element<bar>nested element</bar></foo>"
      assert FnXML.Parser.parse(xml) |> FnXML.Transform.Stream.to_xml() |> Enum.join() == xml
    end

    test "handles all XML constructs" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <foo a=\"1\">text<!--comment--><?pi data?><bar/><![CDATA[<x>]]></foo>
      """

      result =
        FnXML.Parser.parse(xml) |> FnXML.Transform.Stream.to_xml() |> Enum.join() |> strip_ws()

      # Empty elements may be serialized as <bar></bar> instead of <bar/>
      assert result =~ "<?xmlversion=\"1.0\"encoding=\"UTF-8\"?>"
      assert result =~ "<fooa=\"1\">"
      assert result =~ "text"
      assert result =~ "<!--comment-->"
      assert result =~ "<?pidata?>"
      assert result =~ "<![CDATA[<x>]]>"
      assert result =~ "</foo>"
    end

    test "escapes special chars in CDATA" do
      stream = [
        {:start_element, "root", [], 1, 0, 1},
        {:characters, "<script>", 1, 0, 7},
        {:end_element, "root", 1, 0, 15}
      ]

      assert FnXML.Transform.Stream.to_xml(stream) |> Enum.join() =~ "<![CDATA["
    end
  end

  describe "transform" do
    test "passes events through with path tracking" do
      xml = "<foo><bar/></foo>"

      result =
        FnXML.Parser.parse(xml)
        |> FnXML.Transform.Stream.transform(fn element, _path, acc -> {element, acc} end)
        |> Enum.to_list()

      # Parser outputs 6-tuple: {:start_element, tag, attrs, line, ls, pos}
      assert match?({:start_element, "foo", _, _, _, _}, Enum.at(result, 1))
      assert match?({:start_element, "bar", _, _, _, _}, Enum.at(result, 2))
    end

    test "to_xml with simple stream" do
      result =
        [
          {:start_element, "a", [], 1, 0, 1},
          {:start_element, "b", [], 1, 0, 4},
          {:end_element, "b", 1, 0, 7},
          {:end_element, "a", 1, 0, 11}
        ]
        |> FnXML.Transform.Stream.to_xml()
        |> Enum.join()

      assert result == "<a><b></b></a>"
    end
  end

  describe "filter" do
    test "filter_ws removes whitespace-only characters" do
      stream = [
        {:start_element, "foo", [], 1, 0, 1},
        {:characters, "keep", 1, 0, 6},
        {:characters, " \t\n", 1, 0, 10},
        {:end_element, "foo", 1, 0, 13}
      ]

      result = FnXML.Transform.Stream.filter_ws(stream) |> Enum.to_list()

      assert length(result) == 3
      refute Enum.any?(result, &match?({:characters, " \t\n", _, _, _}, &1))
    end

    test "filter passes through document markers" do
      stream = [
        {:start_document, nil},
        {:start_element, "foo", [], 1, 0, 1},
        {:end_element, "foo", 1, 0, 10},
        {:end_document, nil}
      ]

      result =
        FnXML.Transform.Stream.filter(stream, fn _, _, acc -> {true, acc} end) |> Enum.to_list()

      assert {:start_document, nil} in result
      assert {:end_document, nil} in result
    end

    test "filter excludes elements matching predicate" do
      stream = [
        {:start_element, "foo", [], 1, 0, 1},
        {:characters, "skip", 1, 0, 6},
        {:characters, "keep", 1, 0, 10},
        {:end_element, "foo", 1, 0, 14}
      ]

      result =
        FnXML.Transform.Stream.filter(stream, fn
          {:characters, "skip", _, _, _}, _, acc -> {false, acc}
          _, _, acc -> {true, acc}
        end)
        |> Enum.to_list()

      assert length(result) == 3
      refute Enum.any?(result, &match?({:characters, "skip", _, _, _}, &1))
    end
  end

  describe "filter_namespaces" do
    test "filters by namespace prefix" do
      stream = [
        {:start_element, "foo", [], 1, 0, 1},
        {:start_element, "bar:child", [], 1, 0, 6},
        {:end_element, "bar:child", 1, 0, 17},
        {:start_element, "baz:other", [], 1, 0, 29},
        {:end_element, "baz:other", 1, 0, 40},
        {:end_element, "foo", 1, 0, 52}
      ]

      # Exclude bar and baz namespaces
      result =
        FnXML.Transform.Stream.filter_namespaces(stream, ["bar", "baz"], exclude: true)
        |> Enum.to_list()

      # Only foo start and end
      assert length(result) == 2

      # Include only bar namespace
      result2 =
        FnXML.Transform.Stream.filter_namespaces(stream, ["bar"], include: true) |> Enum.to_list()

      assert Enum.any?(result2, &match?({:start_element, "bar:child", _, _, _, _}, &1))
    end

    test "handles end_element with and without loc" do
      stream = [
        {:start_element, "foo", [], 1, 0, 1},
        {:start_element, "bar:x", [], 1, 0, 6},
        {:end_element, "bar:x", 1, 0, 13},
        {:end_element, "foo", 1, 0, 20}
      ]

      result =
        FnXML.Transform.Stream.filter_namespaces(stream, ["bar"], include: true) |> Enum.to_list()

      assert Enum.any?(result, &match?({:start_element, "bar:x", _, _, _, _}, &1))
    end
  end

  describe "transform error handling" do
    test "raises on unexpected or mismatched close tags" do
      assert_raise FnXML.Transform.Stream.Exception, ~r/unexpected close tag/, fn ->
        [{:end_element, "foo"}]
        |> FnXML.Transform.Stream.transform(fn e, _, acc -> {e, acc} end)
        |> Enum.to_list()
      end

      assert_raise FnXML.Transform.Stream.Exception, ~r/unexpected close tag/, fn ->
        [{:end_element, "foo", 1, 0, 5}]
        |> FnXML.Transform.Stream.transform(fn e, _, acc -> {e, acc} end)
        |> Enum.to_list()
      end

      assert_raise FnXML.Transform.Stream.Exception, ~r/mis-matched close tag/, fn ->
        [{:start_element, "foo", [], 1, 0, 1}, {:end_element, "bar", 1, 0, 10}]
        |> FnXML.Transform.Stream.transform(fn e, _, acc -> {e, acc} end)
        |> Enum.to_list()
      end
    end

    test "raises on non-whitespace text outside element" do
      assert_raise FnXML.Transform.Stream.Exception, ~r/Text element outside/, fn ->
        [{:characters, "text", 1, 0, 1}]
        |> FnXML.Transform.Stream.transform(fn e, _, acc -> {e, acc} end)
        |> Enum.to_list()
      end
    end

    test "ignores whitespace outside element" do
      stream = [
        {:characters, "  \n  ", 1, 0, 1},
        {:start_element, "root", [], 1, 0, 6},
        {:end_element, "root", 1, 0, 12}
      ]

      result =
        FnXML.Transform.Stream.transform(stream, fn e, _, acc -> {e, acc} end) |> Enum.to_list()

      assert length(result) >= 2
    end
  end
end
