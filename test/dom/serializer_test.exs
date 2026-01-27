defmodule FnXML.DOM.SerializerTest do
  use ExUnit.Case, async: true

  alias FnXML.API.DOM.{Serializer, Document, Element}

  describe "to_string/2" do
    test "serializes special child types (comment, CDATA, PI)" do
      elem =
        Element.new("root", [], [
          {:comment, "test comment"},
          {:cdata, "<data>"},
          {:pi, "target", "data"},
          {:pi, "empty", nil}
        ])

      result = Serializer.to_string(elem)

      assert result =~ "<!--test comment-->"
      assert result =~ "<![CDATA[<data>]]>"
      assert result =~ "<?target data?>"
      assert result =~ "<?empty?>"
    end

    test "handles nil and unknown child types" do
      elem = Element.new("root", [], [nil, "text", {:unknown, "data"}])
      result = Serializer.to_string(elem)
      assert result =~ "text"
      assert result =~ "<root>"
    end

    test "serializes document with prolog" do
      doc = %Document{
        root: Element.new("root", [], []),
        prolog: %{version: "1.0", encoding: "UTF-8"}
      }

      result = Serializer.to_string(doc, xml_declaration: true)
      assert result =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)

      # Without encoding
      doc2 = %Document{root: Element.new("root", [], []), prolog: %{version: "1.0"}}
      result2 = Serializer.to_string(doc2, xml_declaration: true)
      assert result2 =~ ~s(<?xml version="1.0"?>)
    end

    test "serializes document with doctype" do
      doc = %Document{root: Element.new("html", [], []), doctype: "html"}
      assert Serializer.to_string(doc) =~ "<!DOCTYPE html>"
    end

    test "handles document with nil root" do
      assert Serializer.to_string(%Document{root: nil}) == ""
    end

    test "pretty printing with indent options" do
      elem =
        Element.new("root", [], [
          {:comment, "c"},
          {:cdata, "d"},
          {:pi, "t", "d"},
          Element.new("child", [], [])
        ])

      # Tab indent
      assert Serializer.to_string(elem, pretty: true, indent: "\t") =~ "\t<child/>"
      # Numeric indent
      assert Serializer.to_string(elem, pretty: true, indent: 4) =~ "    <child/>"
      # Invalid indent falls back to default
      assert Serializer.to_string(elem, pretty: true, indent: :invalid) =~ "  <child/>"
    end
  end

  describe "to_iodata/2" do
    test "returns iodata for element and document" do
      elem = Element.new("root", [], ["text"])
      assert IO.iodata_to_binary(Serializer.to_iodata(elem)) == "<root>text</root>"

      doc = %Document{root: Element.new("root", [], [])}
      assert IO.iodata_to_binary(Serializer.to_iodata(doc)) =~ "<root/>"
    end
  end

  describe "to_stream/1" do
    test "streams element events including special types" do
      elem =
        Element.new("root", [], [
          "text",
          {:comment, "c"},
          {:cdata, "d"},
          {:pi, "t", "d"},
          Element.new("child", [], [])
        ])

      events = Serializer.to_stream(elem) |> Enum.to_list()

      assert {:start_element, "root", [], nil} in events
      assert {:characters, "text", nil} in events
      assert {:comment, "c", nil} in events
      assert {:cdata, "d", nil} in events
      assert {:processing_instruction, "t", "d", nil} in events
      assert {:start_element, "child", [], nil} in events
      assert {:end_element, "root"} in events
    end

    test "handles document and nil root" do
      doc = %Document{root: Element.new("root", [], [])}
      events = Serializer.to_stream(doc) |> Enum.to_list()
      assert {:start_element, "root", [], nil} in events

      assert Serializer.to_stream(%Document{root: nil}) |> Enum.to_list() == []
    end

    test "skips nil children" do
      elem = Element.new("root", [], [nil, "text", nil])
      events = Serializer.to_stream(elem) |> Enum.to_list()
      text_events = Enum.filter(events, &match?({:characters, _, _}, &1))
      assert length(text_events) == 1
    end
  end
end
