defmodule FnXML.StAXTest do
  use ExUnit.Case, async: true

  alias FnXML.API.StAX
  alias FnXML.API.StAX.{Reader, Writer}

  describe "Reader.new/2" do
    test "creates reader from XML string" do
      reader = Reader.new("<root/>")
      assert match?({:stream, _}, reader.stream_state)
      assert reader.current == nil
    end

    test "creates reader from event stream" do
      stream = FnXML.Parser.parse("<root/>")
      reader = Reader.new(stream) |> Reader.next()
      assert Reader.start_element?(reader)
    end
  end

  describe "Reader.close/1" do
    test "closes reader" do
      assert :ok = Reader.close(Reader.new("<root/>"))
    end
  end

  describe "Reader.next/1 and has_next?/1" do
    test "advances through document and detects exhaustion" do
      reader = Reader.new("<root>text</root>")
      assert Reader.has_next?(reader)

      reader = Reader.next(reader)
      assert Reader.event_type(reader) == :start_element
      assert Reader.local_name(reader) == "root"
      assert Reader.has_next?(reader)

      reader = Reader.next(reader)
      assert Reader.event_type(reader) == :characters
      assert Reader.text(reader) == "text"

      reader = Reader.next(reader)
      assert Reader.event_type(reader) == :end_element

      reader = Reader.next(reader)
      refute Reader.has_next?(reader)
    end
  end

  describe "Reader element accessors" do
    test "local_name and prefix for elements" do
      # Simple element
      reader = Reader.new("<root/>") |> Reader.next()
      assert Reader.local_name(reader) == "root"
      assert Reader.prefix(reader) == nil
      assert Reader.name(reader) == {nil, "root"}
      assert Reader.namespace_uri(reader) == nil

      # Prefixed element
      reader = Reader.new("<ns:root/>") |> Reader.next()
      assert Reader.local_name(reader) == "root"
      assert Reader.prefix(reader) == "ns"

      # End element
      reader = Reader.new("<ns:root></ns:root>") |> Reader.next() |> Reader.next()
      assert Reader.local_name(reader) == "root"
      assert Reader.prefix(reader) == "ns"
      assert Reader.name(reader) == {nil, "root"}
    end

    test "returns nil for non-element events" do
      reader = Reader.new("<root>text</root>") |> Reader.next() |> Reader.next()
      assert Reader.characters?(reader)
      assert Reader.local_name(reader) == nil
      assert Reader.prefix(reader) == nil
      assert Reader.name(reader) == nil
    end

    test "type predicates" do
      reader = Reader.new("<root>text</root>")

      reader = Reader.next(reader)
      assert Reader.start_element?(reader)
      refute Reader.end_element?(reader)
      refute Reader.characters?(reader)

      reader = Reader.next(reader)
      assert Reader.characters?(reader)
      refute Reader.start_element?(reader)

      reader = Reader.next(reader)
      assert Reader.end_element?(reader)
      refute Reader.start_element?(reader)
    end

    test "location returns position tuple" do
      reader = Reader.new("<root/>") |> Reader.next()
      assert is_tuple(Reader.location(reader))
    end
  end

  describe "Reader attribute accessors" do
    test "attribute access by index and name" do
      reader = Reader.new("<root id=\"123\" class=\"main\"/>") |> Reader.next()

      assert Reader.attribute_count(reader) == 2
      # Parser returns attributes in reverse order
      assert Reader.attribute_value(reader, nil, "id") == "123"
      assert Reader.attribute_value(reader, nil, "class") == "main"
      # Index-based access returns in parser order (reversed)
      assert Reader.attribute_value(reader, 0) in ["123", "main"]
      assert Reader.attribute_name(reader, 0) in [{nil, "id"}, {nil, "class"}]
    end

    test "returns nil for missing or out-of-bounds attributes" do
      reader = Reader.new("<root id=\"1\"/>") |> Reader.next()

      assert Reader.attribute_value(reader, 99) == nil
      assert Reader.attribute_value(reader, nil, "missing") == nil
      assert Reader.attribute_name(reader, 99) == nil
    end

    test "returns 0/nil for non-element events" do
      reader = Reader.new("<root>text</root>") |> Reader.next() |> Reader.next()

      assert Reader.attribute_count(reader) == 0
      assert Reader.attribute_value(reader, 0) == nil
      assert Reader.attribute_value(reader, nil, "id") == nil
      assert Reader.attribute_name(reader, 0) == nil
    end
  end

  describe "Reader text accessors" do
    test "text returns content for character events" do
      reader = Reader.new("<root>Hello</root>") |> Reader.next() |> Reader.next()
      assert Reader.text(reader) == "Hello"
    end

    test "text returns nil for non-text events" do
      reader = Reader.new("<root/>") |> Reader.next()
      assert Reader.text(reader) == nil
    end

    test "whitespace? detects whitespace-only content" do
      reader = Reader.new("<root>  text  </root>") |> Reader.next() |> Reader.next()
      # Has non-whitespace
      refute Reader.whitespace?(reader)

      reader = Reader.new("<root/>") |> Reader.next()
      # Not a text event
      refute Reader.whitespace?(reader)
    end
  end

  describe "Reader.element_text/1" do
    test "reads all text content including nested elements" do
      reader = Reader.new("<root>Hello <b>World</b>!</root>") |> Reader.next()
      {text, reader} = Reader.element_text(reader)
      assert text == "Hello World!"
      assert Reader.end_element?(reader)
    end
  end

  describe "Reader.next_tag/1" do
    test "skips non-element events to next element" do
      reader = Reader.new("<root><!-- comment -->  <child/></root>") |> Reader.next()
      reader = Reader.next_tag(reader)
      assert Reader.local_name(reader) == "child"
    end
  end

  describe "Reader prolog and PI accessors" do
    test "prolog accessors return nil without prolog" do
      reader = Reader.new("<root/>") |> Reader.next()
      assert Reader.version(reader) == nil
      assert Reader.encoding(reader) == nil
      assert Reader.standalone?(reader) == nil
    end

    test "PI accessors return nil for non-PI events" do
      reader = Reader.new("<root/>") |> Reader.next()
      assert Reader.pi_target(reader) == nil
      assert Reader.pi_data(reader) == nil
    end
  end

  # Writer tests - keeping existing coverage
  describe "Writer basics" do
    test "creates empty writer" do
      assert Writer.to_string(Writer.new()) == ""
    end

    test "writes XML declaration" do
      xml = Writer.new() |> Writer.start_document() |> Writer.to_string()
      assert xml == "<?xml version=\"1.0\"?>"

      xml = Writer.new() |> Writer.start_document("1.0", "UTF-8") |> Writer.to_string()
      assert xml == "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    end
  end

  describe "Writer elements and attributes" do
    test "writes elements and attributes" do
      xml =
        Writer.new()
        |> Writer.start_element("root")
        |> Writer.attribute("id", "1")
        |> Writer.attribute("class", "main")
        |> Writer.start_element("child")
        |> Writer.end_element()
        |> Writer.end_element()
        |> Writer.to_string()

      assert xml =~ "id=\"1\""
      assert xml =~ "class=\"main\""
      assert xml =~ "<child/>"
    end

    test "escapes attribute values" do
      xml =
        Writer.new()
        |> Writer.start_element("root")
        |> Writer.attribute("value", "a<b&c\"d")
        |> Writer.end_element()
        |> Writer.to_string()

      assert xml =~ "value=\"a&lt;b&amp;c&quot;d\""
    end
  end

  describe "Writer content" do
    test "writes text content with escaping" do
      xml =
        Writer.new()
        |> Writer.start_element("root")
        |> Writer.characters("<>&")
        |> Writer.end_element()
        |> Writer.to_string()

      assert xml == "<root>&lt;&gt;&amp;</root>"
    end

    test "writes comment and CDATA" do
      xml =
        Writer.new()
        |> Writer.start_element("root")
        |> Writer.comment("comment")
        |> Writer.cdata("<special>")
        |> Writer.end_element()
        |> Writer.to_string()

      assert xml =~ "<!--comment-->"
      assert xml =~ "<![CDATA[<special>]]>"
    end

    test "writes processing instruction" do
      xml =
        Writer.new()
        |> Writer.processing_instruction("php", "echo 'hello';")
        |> Writer.to_string()

      assert xml == "<?php echo 'hello';?>"

      xml = Writer.new() |> Writer.processing_instruction("xml-stylesheet") |> Writer.to_string()
      assert xml == "<?xml-stylesheet?>"
    end

    test "writes empty element" do
      xml =
        Writer.new()
        |> Writer.start_element("root")
        |> Writer.empty_element("br")
        |> Writer.end_element()
        |> Writer.to_string()

      assert xml == "<root><br/></root>"
    end
  end

  describe "Writer namespaces" do
    test "writes namespace declarations" do
      xml =
        Writer.new()
        |> Writer.start_element("root")
        |> Writer.namespace("ex", "http://example.org")
        |> Writer.default_namespace("http://default.org")
        |> Writer.end_element()
        |> Writer.to_string()

      assert xml =~ "xmlns:ex=\"http://example.org\""
      assert xml =~ "xmlns=\"http://default.org\""
    end

    test "writes namespaced elements and attributes" do
      xml =
        Writer.new()
        |> Writer.start_element("ex", "root", "http://example.org")
        |> Writer.attribute("http://example.org", "attr", "value")
        |> Writer.end_element()
        |> Writer.to_string()

      assert xml =~ "ex:root"
      assert xml =~ "xmlns:ex="
      assert xml =~ "attr=\"value\""
    end
  end

  describe "Writer end_document and to_iodata" do
    test "end_document closes all open elements" do
      xml =
        Writer.new()
        |> Writer.start_element("a")
        |> Writer.start_element("b")
        |> Writer.start_element("c")
        |> Writer.end_document()
        |> Writer.to_string()

      assert xml =~ "</c>"
      assert xml =~ "</b>"
      assert xml =~ "</a>"
    end

    test "end_document handles empty document" do
      assert Writer.new() |> Writer.end_document() |> Writer.to_string() == ""
    end

    test "to_iodata returns iodata" do
      writer =
        Writer.new()
        |> Writer.start_element("root")
        |> Writer.characters("text")
        |> Writer.end_element()

      assert IO.iodata_to_binary(Writer.to_iodata(writer)) == "<root>text</root>"
    end
  end

  describe "StAX module constants" do
    test "event type constants and conversions" do
      assert StAX.start_element() == 1
      assert StAX.end_element() == 2
      assert StAX.characters() == 4
      assert StAX.comment() == 5
      assert StAX.cdata() == 12

      assert StAX.event_type_to_int(:start_element) == 1
      assert StAX.event_type_to_atom(1) == :start_element
    end

    test "factory functions" do
      assert %Reader{} = FnXML.Parser.parse("<root/>") |> StAX.reader()
      assert %Writer{} = StAX.create_writer()
    end
  end
end
