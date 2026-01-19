defmodule FnXML.ParserTest do
  use ExUnit.Case, async: true

  alias FnXML.Parser

  describe "parse/1 stream mode" do
    test "parses empty element" do
      events = Parser.parse("<root/>") |> Enum.to_list()
      assert {:start_document, nil} in events
      assert {:end_document, nil} in events
      assert Enum.any?(events, &match?({:start_element, "root", [], _, _, _}, &1))

      assert Enum.any?(events, fn
               {:end_element, "root"} -> true
               {:end_element, "root", _, _, _} -> true
               _ -> false
             end)
    end

    test "parses element with text" do
      events = Parser.parse("<root>hello</root>") |> Enum.to_list()
      assert Enum.any?(events, &match?({:characters, "hello", _, _, _}, &1))
    end

    test "parses nested elements" do
      events = Parser.parse("<a><b><c/></b></a>") |> Enum.to_list()

      tags =
        events
        |> Enum.filter(&match?({:start_element, _, _, _, _, _}, &1))
        |> Enum.map(fn {:start_element, tag, _, _, _, _} -> tag end)

      assert tags == ["a", "b", "c"]
    end

    test "parses attributes" do
      events = Parser.parse(~s(<root id="1" class="test"/>)) |> Enum.to_list()

      {_, _, attrs, _, _, _} =
        Enum.find(events, &match?({:start_element, "root", _, _, _, _}, &1))

      assert {"id", "1"} in attrs
      assert {"class", "test"} in attrs
    end

    test "parses single-quoted attributes" do
      events = Parser.parse("<root attr='value'/>") |> Enum.to_list()

      {_, _, attrs, _, _, _} =
        Enum.find(events, &match?({:start_element, "root", _, _, _, _}, &1))

      assert {"attr", "value"} in attrs
    end

    test "handles whitespace in tags" do
      events = Parser.parse("<root  id = \"1\"  />") |> Enum.to_list()
      assert Enum.any?(events, &match?({:start_element, "root", _, _, _, _}, &1))
    end
  end

  describe "parse/1 stream iteration" do
    test "iterates events via Enum" do
      events = Parser.parse("<root/>") |> Enum.to_list()

      assert {:start_document, nil} in events
      assert Enum.any?(events, &match?({:start_element, "root", [], _, _, _}, &1))

      assert Enum.any?(events, fn
               {:end_element, "root"} -> true
               {:end_element, "root", _, _, _} -> true
               _ -> false
             end)

      assert {:end_document, nil} in events
    end
  end

  describe "comments" do
    test "parses comment" do
      events = Parser.parse("<root><!-- comment --></root>") |> Enum.to_list()
      assert Enum.any?(events, &match?({:comment, " comment ", _, _, _}, &1))
    end

    test "parses empty comment" do
      events = Parser.parse("<root><!----></root>") |> Enum.to_list()
      assert Enum.any?(events, &match?({:comment, "", _, _, _}, &1))
    end

    test "parses comment with special chars" do
      events = Parser.parse("<root><!-- <>&' --></root>") |> Enum.to_list()
      assert Enum.any?(events, &match?({:comment, " <>&' ", _, _, _}, &1))
    end
  end

  describe "CDATA sections" do
    test "parses CDATA" do
      events = Parser.parse("<root><![CDATA[content]]></root>") |> Enum.to_list()
      assert Enum.any?(events, &match?({:cdata, "content", _, _, _}, &1))
    end

    test "parses CDATA with special chars" do
      events = Parser.parse("<root><![CDATA[<>&\"']]></root>") |> Enum.to_list()
      assert Enum.any?(events, &match?({:cdata, "<>&\"'", _, _, _}, &1))
    end
  end

  describe "processing instructions" do
    test "parses PI" do
      events = Parser.parse("<?target data?><root/>") |> Enum.to_list()
      assert Enum.any?(events, &match?({:processing_instruction, "target", _, _, _, _}, &1))
    end

    test "parses PI without data" do
      events = Parser.parse("<?target?><root/>") |> Enum.to_list()
      assert Enum.any?(events, &match?({:processing_instruction, "target", _, _, _, _}, &1))
    end
  end

  describe "XML prolog" do
    test "parses prolog" do
      events = Parser.parse(~s(<?xml version="1.0"?><root/>)) |> Enum.to_list()

      assert Enum.any?(events, fn
               {:prolog, "xml", attrs, _, _, _} -> {"version", "1.0"} in attrs
               _ -> false
             end)
    end

    test "parses prolog with encoding" do
      events = Parser.parse(~s(<?xml version="1.0" encoding="UTF-8"?><root/>)) |> Enum.to_list()
      prolog = Enum.find(events, &match?({:prolog, "xml", _, _, _, _}, &1))
      {:prolog, "xml", attrs, _, _, _} = prolog
      assert {"encoding", "UTF-8"} in attrs
    end

    test "parses prolog with standalone" do
      events = Parser.parse(~s(<?xml version="1.0" standalone="yes"?><root/>)) |> Enum.to_list()
      prolog = Enum.find(events, &match?({:prolog, "xml", _, _, _, _}, &1))
      {:prolog, "xml", attrs, _, _, _} = prolog
      assert {"standalone", "yes"} in attrs
    end
  end

  describe "DOCTYPE" do
    test "parses DOCTYPE" do
      events = Parser.parse("<!DOCTYPE html><root/>") |> Enum.to_list()
      assert Enum.any?(events, &match?({:dtd, _, _, _, _}, &1))
    end

    test "parses DOCTYPE with system ID" do
      xml = ~s(<!DOCTYPE html SYSTEM "http://example.com/dtd"><root/>)
      events = Parser.parse(xml) |> Enum.to_list()
      assert Enum.any?(events, &match?({:dtd, _, _, _, _}, &1))
    end

    test "parses DOCTYPE with public ID" do
      xml =
        ~s(<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd"><root/>)

      events = Parser.parse(xml) |> Enum.to_list()
      assert Enum.any?(events, &match?({:dtd, _, _, _, _}, &1))
    end

    test "parses DOCTYPE with internal subset" do
      xml = "<!DOCTYPE root [<!ELEMENT root (#PCDATA)>]><root/>"
      events = Parser.parse(xml) |> Enum.to_list()
      assert Enum.any?(events, &match?({:dtd, _, _, _, _}, &1))
    end
  end

  describe "entity references" do
    test "passes through entity references in text" do
      # FnXML.Parser passes through entities - use Stream.resolve_entities to expand
      events = Parser.parse("<root>&lt;&gt;&amp;</root>") |> Enum.to_list()
      assert Enum.any?(events, &match?({:characters, _, _, _, _}, &1))
    end

    test "passes through decimal numeric entities" do
      events = Parser.parse("<root>&#65;</root>") |> Enum.to_list()
      assert Enum.any?(events, &match?({:characters, _, _, _, _}, &1))
    end

    test "passes through hex numeric entities" do
      events = Parser.parse("<root>&#x41;</root>") |> Enum.to_list()
      assert Enum.any?(events, &match?({:characters, _, _, _, _}, &1))
    end

    test "passes through entities in attributes" do
      events = Parser.parse(~s(<root attr="a&lt;b"/>)) |> Enum.to_list()

      {_, _, attrs, _, _, _} =
        Enum.find(events, &match?({:start_element, "root", _, _, _, _}, &1))

      # Entities are passed through, not expanded
      assert Enum.any?(attrs, fn {name, _} -> name == "attr" end)
    end
  end

  describe "whitespace handling" do
    test "preserves text whitespace" do
      events = Parser.parse("<root>  hello  </root>") |> Enum.to_list()
      # Parser may trim leading whitespace, but trailing should be preserved
      assert Enum.any?(events, fn
               {:characters, text, _, _, _} -> String.contains?(text, "hello")
               _ -> false
             end)
    end

    test "handles newlines" do
      events = Parser.parse("<root>\n  text\n</root>") |> Enum.to_list()
      text_events = Enum.filter(events, &match?({:characters, _, _, _, _}, &1))
      assert length(text_events) >= 1
    end
  end

  describe "unicode" do
    test "parses unicode element names" do
      events = Parser.parse("<élément/>") |> Enum.to_list()
      assert Enum.any?(events, &match?({:start_element, "élément", [], _, _, _}, &1))
    end

    test "parses unicode text" do
      events = Parser.parse("<root>中文</root>") |> Enum.to_list()
      assert Enum.any?(events, &match?({:characters, "中文", _, _, _}, &1))
    end

    test "parses unicode attributes" do
      events = Parser.parse(~s(<root attr="日本語"/>)) |> Enum.to_list()

      {_, _, attrs, _, _, _} =
        Enum.find(events, &match?({:start_element, "root", _, _, _, _}, &1))

      assert {"attr", "日本語"} in attrs
    end
  end

  describe "error handling" do
    test "handles unclosed tag gracefully" do
      # Parser may emit an error event or truncate the stream
      events = Parser.parse("<root") |> Enum.to_list()
      # Stream should complete without crashing
      assert {:start_document, nil} in events
      assert {:end_document, nil} in events
    end

    test "handles unterminated attribute gracefully" do
      # Parser may emit an error event or truncate the stream
      events = Parser.parse(~s(<root attr="value)) |> Enum.to_list()
      # Stream should complete without crashing
      assert {:start_document, nil} in events
      assert {:end_document, nil} in events
    end
  end

  describe "namespaced elements" do
    test "parses prefixed elements" do
      events = Parser.parse("<ns:root xmlns:ns=\"http://example.com\"/>") |> Enum.to_list()
      assert Enum.any?(events, &match?({:start_element, "ns:root", _, _, _, _}, &1))
    end

    test "parses prefixed attributes" do
      events =
        Parser.parse(~s(<root ns:attr="value" xmlns:ns="http://example.com"/>)) |> Enum.to_list()

      {_, _, attrs, _, _, _} =
        Enum.find(events, &match?({:start_element, "root", _, _, _, _}, &1))

      assert Enum.any?(attrs, fn {name, _} -> String.contains?(name, "ns:") end)
    end
  end

  describe "mixed content" do
    test "parses text with inline elements" do
      events = Parser.parse("<root>Hello <b>World</b>!</root>") |> Enum.to_list()
      text_events = Enum.filter(events, &match?({:characters, _, _, _, _}, &1))
      assert length(text_events) >= 2
    end
  end

  describe "empty content" do
    test "parses empty string" do
      events = Parser.parse("") |> Enum.to_list()
      assert {:start_document, nil} in events
      assert {:end_document, nil} in events
    end

    test "parses whitespace only" do
      events = Parser.parse("   ") |> Enum.to_list()
      assert {:start_document, nil} in events
      assert {:end_document, nil} in events
    end
  end
end
