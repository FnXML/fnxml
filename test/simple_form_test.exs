defmodule FnXML.SimpleFormTest do
  use ExUnit.Case

  alias FnXML.Transform.Stream.SimpleForm

  # doctest SimpleForm  # Disabled due to quote escaping issues in expected outputs

  describe "decode/2" do
    test "decodes simple element" do
      assert SimpleForm.decode("<root/>") == {"root", [], []}
    end

    test "decodes element with text" do
      assert SimpleForm.decode("<root>hello</root>") == {"root", [], ["hello"]}
    end

    test "decodes element with attributes" do
      # Parser returns attributes in reverse order
      result = SimpleForm.decode("<root id=\"1\" class=\"main\"/>")
      assert elem(result, 0) == "root"
      assert {"id", "1"} in elem(result, 1)
      assert {"class", "main"} in elem(result, 1)
      assert elem(result, 2) == []
    end

    test "decodes nested elements" do
      xml = "<root><child>text</child></root>"

      assert SimpleForm.decode(xml) == {"root", [], [{"child", [], ["text"]}]}
    end

    test "decodes deeply nested elements" do
      xml = "<a><b><c><d>deep</d></c></b></a>"

      assert SimpleForm.decode(xml) ==
               {"a", [], [{"b", [], [{"c", [], [{"d", [], ["deep"]}]}]}]}
    end

    test "decodes multiple children" do
      xml = "<root><a>1</a><b>2</b><c>3</c></root>"

      assert SimpleForm.decode(xml) ==
               {"root", [],
                [
                  {"a", [], ["1"]},
                  {"b", [], ["2"]},
                  {"c", [], ["3"]}
                ]}
    end

    test "decodes mixed content" do
      xml = "<root>before<child/>after</root>"

      assert SimpleForm.decode(xml) ==
               {"root", [], ["before", {"child", [], []}, "after"]}
    end

    test "preserves trailing whitespace in text" do
      xml = "<root>spaced  </root>"

      assert SimpleForm.decode(xml) == {"root", [], ["spaced  "]}
    end

    test "includes comments when option set" do
      xml = "<root><!-- comment --><child/></root>"

      assert SimpleForm.decode(xml, include_comments: true) ==
               {"root", [], [{:comment, " comment "}, {"child", [], []}]}
    end

    test "excludes comments by default" do
      xml = "<root><!-- comment --><child/></root>"

      assert SimpleForm.decode(xml) == {"root", [], [{"child", [], []}]}
    end

    test "includes prolog when option set" do
      xml = "<?xml version=\"1.0\"?><root/>"

      assert SimpleForm.decode(xml, include_prolog: true) ==
               {:prolog, [{"version", "1.0"}], {"root", [], []}}
    end

    test "decodes namespaced elements" do
      xml = "<ns:root xmlns:ns=\"http://example.com\"><ns:child/></ns:root>"

      assert SimpleForm.decode(xml) ==
               {"ns:root", [{"xmlns:ns", "http://example.com"}], [{"ns:child", [], []}]}
    end
  end

  describe "encode/2" do
    test "encodes simple element" do
      assert SimpleForm.encode({"root", [], []}) == "<root></root>"
    end

    test "encodes element with text" do
      assert SimpleForm.encode({"root", [], ["hello"]}) == "<root>hello</root>"
    end

    test "encodes element with attributes" do
      assert SimpleForm.encode({"root", [{"id", "1"}], []}) == "<root id=\"1\"></root>"
    end

    test "encodes nested elements" do
      simple_form = {"root", [], [{"child", [], ["text"]}]}

      assert SimpleForm.encode(simple_form) == "<root><child>text</child></root>"
    end

    test "encodes multiple children" do
      simple_form = {"root", [], [{"a", [], []}, {"b", [], []}, {"c", [], []}]}

      assert SimpleForm.encode(simple_form) == "<root><a></a><b></b><c></c></root>"
    end

    test "encodes mixed content" do
      simple_form = {"root", [], ["before", {"child", [], []}, "after"]}

      assert SimpleForm.encode(simple_form) == "<root>before<child></child>after</root>"
    end

    test "encodes with pretty printing" do
      simple_form = {"root", [], [{"child", [], []}]}

      result = SimpleForm.encode(simple_form, pretty: true)
      # Pretty printing adds newlines around elements
      assert String.contains?(result, "<root>")
      assert String.contains?(result, "<child>")
      assert String.contains?(result, "\n")
    end
  end

  describe "from_stream/2" do
    test "converts stream to simple form" do
      stream = FnXML.Parser.parse("<root><item>value</item></root>")

      assert SimpleForm.from_stream(stream) ==
               {"root", [], [{"item", [], ["value"]}]}
    end

    test "handles self-closing tags" do
      stream = FnXML.Parser.parse("<root><empty/></root>")

      assert SimpleForm.from_stream(stream) ==
               {"root", [], [{"empty", [], []}]}
    end
  end

  describe "to_stream/1" do
    test "converts simple form to stream" do
      events =
        {"root", [], ["text"]}
        |> SimpleForm.to_stream()
        |> Enum.to_list()

      assert events == [
               {:start_element, "root", [], 1, 0, 0},
               {:characters, "text", 1, 0, 0},
               {:end_element, "root", 1, 0, 0}
             ]
    end

    test "converts nested elements to stream" do
      events =
        {"root", [], [{"child", [{"id", "1"}], ["value"]}]}
        |> SimpleForm.to_stream()
        |> Enum.to_list()

      assert events == [
               {:start_element, "root", [], 1, 0, 0},
               {:start_element, "child", [{"id", "1"}], 1, 0, 0},
               {:characters, "value", 1, 0, 0},
               {:end_element, "child", 1, 0, 0},
               {:end_element, "root", 1, 0, 0}
             ]
    end

    test "stream can be piped to FnXML.Transform.Stream.to_xml" do
      xml =
        {"root", [{"attr", "val"}], [{"child", [], ["text"]}]}
        |> SimpleForm.to_stream()
        |> FnXML.Transform.Stream.to_xml()
        |> Enum.join()

      assert xml == "<root attr=\"val\"><child>text</child></root>"
    end
  end

  describe "round-trip" do
    test "decode then encode preserves structure" do
      xml = "<root><child id=\"1\">text</child></root>"

      result =
        xml
        |> SimpleForm.decode()
        |> SimpleForm.encode()

      assert result == xml
    end

    test "encode then decode preserves structure" do
      simple_form = {"root", [{"id", "1"}], [{"child", [], ["text"]}, {"child", [], ["more"]}]}

      result =
        simple_form
        |> SimpleForm.encode()
        |> SimpleForm.decode()

      assert result == simple_form
    end

    test "stream round-trip preserves data" do
      original = {"root", [], [{"a", [], ["1"]}, {"b", [], ["2"]}]}

      result =
        original
        |> SimpleForm.to_stream()
        |> SimpleForm.from_stream()

      assert result == original
    end
  end

  describe "list_to_stream/1" do
    test "converts list of elements to stream" do
      events =
        [{"a", [], []}, {"b", [], []}]
        |> SimpleForm.list_to_stream()
        |> Enum.to_list()

      assert events == [
               {:start_element, "a", [], 1, 0, 0},
               {:end_element, "a", 1, 0, 0},
               {:start_element, "b", [], 1, 0, 0},
               {:end_element, "b", 1, 0, 0}
             ]
    end
  end
end
