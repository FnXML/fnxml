defmodule FnXML.StreamTest do
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
               |> FnXML.Stream.tap(label: "test_stream")
               |> Enum.map(& &1)
             end)
             |> all_lines_start_with?("test_stream:")
    end

    test "custom tap function receives events" do
      test_pid = self()
      stream = [{:start_element, "foo", [], nil}, {:end_element, "foo"}]

      FnXML.Stream.tap(stream, fn event, _path -> send(test_pid, {:event, event}) end,
        label: "test"
      )
      |> Enum.to_list()

      assert_received {:event, {:start_element, "foo", [], nil}}
    end
  end

  describe "to_xml" do
    test "roundtrips XML" do
      xml = "<foo a=\"1\">first element<bar>nested element</bar></foo>"
      assert FnXML.Parser.parse(xml) |> FnXML.Stream.to_xml() |> Enum.join() == xml
    end

    test "handles all XML constructs" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <foo a=\"1\">text<!--comment--><?pi data?><bar/><![CDATA[<x>]]></foo>
      """

      result = FnXML.Parser.parse(xml) |> FnXML.Stream.to_xml() |> Enum.join() |> strip_ws()
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
        {:start_element, "root", [], nil},
        {:characters, "<script>", nil},
        {:end_element, "root"}
      ]

      assert FnXML.Stream.to_xml(stream) |> Enum.join() =~ "<![CDATA["
    end
  end

  describe "transform" do
    test "passes events through with path tracking" do
      xml = "<foo><bar/></foo>"

      result =
        FnXML.Parser.parse(xml)
        |> FnXML.Stream.transform(fn element, _path, acc -> {element, acc} end)
        |> Enum.to_list()

      # Parser outputs 6-tuple: {:start_element, tag, attrs, line, ls, pos}
      assert match?({:start_element, "foo", _, _, _, _}, Enum.at(result, 1))
      assert match?({:start_element, "bar", _, _, _, _}, Enum.at(result, 2))
    end

    test "to_xml with simple stream" do
      result =
        [
          {:start_element, "a", [], nil},
          {:start_element, "b", [], nil},
          {:end_element, "b"},
          {:end_element, "a"}
        ]
        |> FnXML.Stream.to_xml()
        |> Enum.join()

      assert result == "<a><b></b></a>"
    end
  end

  describe "filter" do
    test "filter_ws removes whitespace-only characters" do
      stream = [
        {:start_element, "foo", [], nil},
        {:characters, "keep", nil},
        {:characters, " \t\n", nil},
        {:end_element, "foo"}
      ]

      result = FnXML.Stream.filter_ws(stream) |> Enum.to_list()

      assert length(result) == 3
      refute Enum.any?(result, &match?({:characters, " \t\n", _}, &1))
    end

    test "filter passes through document markers" do
      stream = [
        {:start_document, nil},
        {:start_element, "foo", [], nil},
        {:end_element, "foo"},
        {:end_document, nil}
      ]

      result = FnXML.Stream.filter(stream, fn _, _, acc -> {true, acc} end) |> Enum.to_list()

      assert {:start_document, nil} in result
      assert {:end_document, nil} in result
    end

    test "filter excludes elements matching predicate" do
      stream = [
        {:start_element, "foo", [], nil},
        {:characters, "skip", nil},
        {:characters, "keep", nil},
        {:end_element, "foo"}
      ]

      result =
        FnXML.Stream.filter(stream, fn
          {:characters, "skip", _}, _, acc -> {false, acc}
          _, _, acc -> {true, acc}
        end)
        |> Enum.to_list()

      assert length(result) == 3
      refute Enum.any?(result, &match?({:characters, "skip", _}, &1))
    end
  end

  describe "filter_namespaces" do
    test "filters by namespace prefix" do
      stream = [
        {:start_element, "foo", [], nil},
        {:start_element, "bar:child", [], nil},
        {:end_element, "bar:child"},
        {:start_element, "baz:other", [], nil},
        {:end_element, "baz:other"},
        {:end_element, "foo"}
      ]

      # Exclude bar and baz namespaces
      result =
        FnXML.Stream.filter_namespaces(stream, ["bar", "baz"], exclude: true) |> Enum.to_list()

      # Only foo start and end
      assert length(result) == 2

      # Include only bar namespace
      result2 = FnXML.Stream.filter_namespaces(stream, ["bar"], include: true) |> Enum.to_list()
      assert Enum.any?(result2, &match?({:start_element, "bar:child", _, _}, &1))
    end

    test "handles end_element with and without loc" do
      stream = [
        {:start_element, "foo", [], nil},
        {:start_element, "bar:x", [], nil},
        {:end_element, "bar:x", {1, 0, 10}},
        {:end_element, "foo"}
      ]

      result = FnXML.Stream.filter_namespaces(stream, ["bar"], include: true) |> Enum.to_list()
      assert Enum.any?(result, &match?({:start_element, "bar:x", _, _}, &1))
    end
  end

  describe "transform error handling" do
    test "raises on unexpected or mismatched close tags" do
      assert_raise FnXML.Stream.Exception, ~r/unexpected close tag/, fn ->
        [{:end_element, "foo"}]
        |> FnXML.Stream.transform(fn e, _, acc -> {e, acc} end)
        |> Enum.to_list()
      end

      assert_raise FnXML.Stream.Exception, ~r/unexpected close tag/, fn ->
        [{:end_element, "foo", {1, 0, 5}}]
        |> FnXML.Stream.transform(fn e, _, acc -> {e, acc} end)
        |> Enum.to_list()
      end

      assert_raise FnXML.Stream.Exception, ~r/mis-matched close tag/, fn ->
        [{:start_element, "foo", [], nil}, {:end_element, "bar"}]
        |> FnXML.Stream.transform(fn e, _, acc -> {e, acc} end)
        |> Enum.to_list()
      end
    end

    test "raises on non-whitespace text outside element" do
      assert_raise FnXML.Stream.Exception, ~r/Text element outside/, fn ->
        [{:characters, "text", nil}]
        |> FnXML.Stream.transform(fn e, _, acc -> {e, acc} end)
        |> Enum.to_list()
      end
    end

    test "ignores whitespace outside element" do
      stream = [
        {:characters, "  \n  ", nil},
        {:start_element, "root", [], nil},
        {:end_element, "root"}
      ]

      result = FnXML.Stream.transform(stream, fn e, _, acc -> {e, acc} end) |> Enum.to_list()
      assert length(result) >= 2
    end
  end
end
