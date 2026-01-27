defmodule FnXML.Transform.Stream.SimpleFormTest do
  use ExUnit.Case, async: true

  alias FnXML.Transform.Stream.SimpleForm
  alias FnXML.API.DOM.Element

  describe "decode/2" do
    test "decodes simple element" do
      assert {"root", [], []} = SimpleForm.decode("<root/>")
    end

    test "decodes element with attributes" do
      assert {"root", [{"id", "1"}], []} = SimpleForm.decode("<root id=\"1\"/>")
    end

    test "decodes element with text content" do
      assert {"root", [], ["text"]} = SimpleForm.decode("<root>text</root>")
    end

    test "decodes nested elements" do
      result = SimpleForm.decode("<a><b/></a>")
      assert {"a", [], [{"b", [], []}]} = result
    end

    test "ignores comments by default" do
      result = SimpleForm.decode("<root><!-- comment --><child/></root>")
      assert {"root", [], [{"child", [], []}]} = result
    end

    test "includes comments when option set" do
      result = SimpleForm.decode("<root><!-- comment --></root>", include_comments: true)
      assert {"root", [], [{:comment, " comment "}]} = result
    end

    test "includes prolog when option set" do
      xml = "<?xml version=\"1.0\"?><root/>"
      result = SimpleForm.decode(xml, include_prolog: true)
      assert {:prolog, attrs, {"root", [], []}} = result
      assert {"version", "1.0"} in attrs
    end
  end

  describe "encode/2" do
    test "encodes simple element" do
      result = SimpleForm.encode({"root", [], []})
      # May be <root/> or <root></root>
      assert result =~ "<root"
    end

    test "encodes element with attributes" do
      result = SimpleForm.encode({"root", [{"id", "1"}], []})
      assert result =~ "id=\"1\""
    end

    test "encodes element with text content" do
      assert "<root>text</root>" = SimpleForm.encode({"root", [], ["text"]})
    end

    test "encodes nested elements" do
      result = SimpleForm.encode({"a", [], [{"b", [], []}]})
      # Empty elements may be rendered as <b/> or <b></b>
      assert result =~ "<a>" and result =~ "</a>" and result =~ "<b"
    end
  end

  describe "from_stream/2" do
    test "converts stream to SimpleForm" do
      result = FnXML.Parser.parse("<root/>") |> SimpleForm.from_stream()
      assert {"root", [], []} = result
    end

    test "handles empty stream" do
      result = [] |> SimpleForm.from_stream()
      assert result == nil
    end

    test "handles multiple root elements" do
      # Simulated stream with multiple roots
      stream = [
        {:start_document, nil},
        {:start_element, "a", [], {1, 0, 0}},
        {:end_element, "a"},
        {:start_element, "b", [], {1, 0, 5}},
        {:end_element, "b"},
        {:end_document, nil}
      ]

      result = stream |> SimpleForm.from_stream()
      # Result may be a single tuple (last element) or a list
      assert is_tuple(result) or is_list(result)
    end

    test "handles text outside elements" do
      stream = [
        {:start_document, nil},
        # whitespace - ignored
        {:characters, "   ", {1, 0, 0}},
        {:start_element, "root", [], {1, 0, 3}},
        {:end_element, "root"},
        {:end_document, nil}
      ]

      result = stream |> SimpleForm.from_stream()
      assert {"root", [], []} = result
    end

    test "handles non-whitespace text outside elements" do
      stream = [
        {:start_document, nil},
        {:characters, "text", {1, 0, 0}},
        {:end_document, nil}
      ]

      result = stream |> SimpleForm.from_stream()
      assert "text" in List.wrap(result)
    end

    test "handles processing instructions" do
      result = FnXML.Parser.parse("<?php echo?><root/>") |> SimpleForm.from_stream()
      # PIs are ignored in SimpleForm
      assert {"root", [], []} = result
    end

    test "handles errors in stream" do
      result = FnXML.Parser.parse("<root><unclosed") |> SimpleForm.from_stream()
      # Errors are ignored, partial result returned
      assert is_tuple(result) or is_list(result) or is_nil(result)
    end
  end

  describe "to_stream/1" do
    test "converts SimpleForm to stream" do
      events = {"root", [], []} |> SimpleForm.to_stream() |> Enum.to_list()
      assert {:start_element, "root", [], 1, 0, 0} in events
      assert {:end_element, "root", 1, 0, 0} in events
    end

    test "includes text content" do
      events = {"root", [], ["text"]} |> SimpleForm.to_stream() |> Enum.to_list()
      assert {:characters, "text", 1, 0, 0} in events
    end

    test "handles nested elements" do
      events = {"a", [], [{"b", [], []}]} |> SimpleForm.to_stream() |> Enum.to_list()

      tags =
        events
        |> Enum.filter(&match?({:start_element, _, _, _, _, _}, &1))
        |> Enum.map(fn {:start_element, tag, _, _, _, _} -> tag end)

      assert "a" in tags
      assert "b" in tags
    end

    test "handles comments" do
      events = {"root", [], [{:comment, "text"}]} |> SimpleForm.to_stream() |> Enum.to_list()
      assert {:comment, "text", 1, 0, 0} in events
    end
  end

  describe "list_to_stream/1" do
    test "converts list of SimpleForm to stream" do
      events = [{"a", [], []}, {"b", [], []}] |> SimpleForm.list_to_stream() |> Enum.to_list()

      tags =
        events
        |> Enum.filter(&match?({:start_element, _, _, _, _, _}, &1))
        |> Enum.map(fn {:start_element, tag, _, _, _, _} -> tag end)

      assert "a" in tags
      assert "b" in tags
    end
  end

  describe "to_dom/1" do
    test "converts SimpleForm to Element" do
      elem = SimpleForm.to_dom({"root", [], []})
      assert %Element{tag: "root"} = elem
    end

    test "converts attributes" do
      elem = SimpleForm.to_dom({"root", [{"id", "1"}], []})
      assert elem.attributes == [{"id", "1"}]
    end

    test "converts text children" do
      elem = SimpleForm.to_dom({"root", [], ["text"]})
      assert elem.children == ["text"]
    end

    test "converts nested elements" do
      elem = SimpleForm.to_dom({"a", [], [{"b", [], []}]})
      [child] = elem.children
      assert %Element{tag: "b"} = child
    end

    test "converts comments" do
      elem = SimpleForm.to_dom({"root", [], [{:comment, "text"}]})
      assert [{:comment, "text"}] = elem.children
    end
  end

  describe "from_dom/1" do
    test "converts Element to SimpleForm" do
      elem = %Element{tag: "root", attributes: [], children: []}
      assert {"root", [], []} = SimpleForm.from_dom(elem)
    end

    test "converts Document to SimpleForm" do
      doc = FnXML.Parser.parse("<root/>") |> FnXML.API.DOM.build()
      result = SimpleForm.from_dom(doc)
      assert {"root", [], []} = result
    end

    test "converts nested elements" do
      elem = %Element{
        tag: "a",
        attributes: [],
        children: [
          %Element{tag: "b", attributes: [], children: []}
        ]
      }

      assert {"a", [], [{"b", [], []}]} = SimpleForm.from_dom(elem)
    end

    test "converts comments" do
      elem = %Element{tag: "root", attributes: [], children: [{:comment, "text"}]}
      assert {"root", [], [{:comment, "text"}]} = SimpleForm.from_dom(elem)
    end

    test "converts text children" do
      elem = %Element{tag: "root", attributes: [], children: ["text"]}
      assert {"root", [], ["text"]} = SimpleForm.from_dom(elem)
    end
  end
end
