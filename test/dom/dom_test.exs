defmodule FnXML.DOMTest do
  use ExUnit.Case, async: true

  alias FnXML.API.DOM
  alias FnXML.API.DOM.{Document, Element}

  # ==========================================================================
  # Node Type Constants
  # ==========================================================================

  describe "node type constants" do
    test "element_node returns 1" do
      assert DOM.element_node() == 1
    end

    test "text_node returns 3" do
      assert DOM.text_node() == 3
    end

    test "cdata_node returns 4" do
      assert DOM.cdata_node() == 4
    end

    test "comment_node returns 8" do
      assert DOM.comment_node() == 8
    end

    test "document_node returns 9" do
      assert DOM.document_node() == 9
    end

    test "document_fragment_node returns 11" do
      assert DOM.document_fragment_node() == 11
    end
  end

  # ==========================================================================
  # DOM.element/3 and DOM.document/2
  # ==========================================================================

  describe "element/3" do
    test "creates element with just tag" do
      elem = DOM.element("div")
      assert elem.tag == "div"
      assert elem.attributes == []
      assert elem.children == []
    end

    test "creates element with attributes" do
      elem = DOM.element("div", [{"class", "container"}])
      assert elem.tag == "div"
      assert elem.attributes == [{"class", "container"}]
    end

    test "creates element with children" do
      elem = DOM.element("div", [], ["Hello"])
      assert elem.children == ["Hello"]
    end
  end

  describe "document/2" do
    test "creates document with root element" do
      root = DOM.element("html")
      doc = DOM.document(root)
      assert doc.root.tag == "html"
    end

    test "creates document with prolog options" do
      root = DOM.element("html")
      doc = DOM.document(root, version: "1.0", encoding: "UTF-8")
      assert Document.version(doc) == "1.0"
      assert Document.encoding(doc) == "UTF-8"
    end
  end

  # ==========================================================================
  # DOM.build/2
  # ==========================================================================

  describe "build/2" do
    test "builds DOM from parser stream" do
      doc = FnXML.Parser.parse("<root>text</root>") |> DOM.build()
      assert doc.root.tag == "root"
      assert doc.root.children == ["text"]
    end

    test "builds DOM with nested elements from stream" do
      doc = FnXML.Parser.parse("<a><b><c/></b></a>") |> DOM.build()
      assert doc.root.tag == "a"
      [b] = doc.root.children
      assert b.tag == "b"
    end
  end

  # ==========================================================================
  # Serialization via FnXML.Stream
  # ==========================================================================

  describe "serialization to iodata via FnXML.Stream" do
    test "converts document to iodata" do
      doc = FnXML.Parser.parse("<root><child/></root>") |> DOM.build()
      iodata = DOM.to_event(doc) |> FnXML.Event.to_iodata()
      assert IO.iodata_to_binary(iodata) == "<root><child/></root>"
    end

    test "converts element to iodata" do
      elem = DOM.element("div", [{"id", "1"}], ["text"])
      iodata = DOM.to_event(elem) |> FnXML.Event.to_iodata()
      assert IO.iodata_to_binary(iodata) == "<div id=\"1\">text</div>"
    end
  end

  # ==========================================================================
  # Parse tests
  # ==========================================================================

  describe "parse/2" do
    test "parses simple element" do
      doc = FnXML.Parser.parse("<root/>") |> DOM.build()
      assert doc.root.tag == "root"
      assert doc.root.children == []
    end

    test "parses element with attributes" do
      doc = FnXML.Parser.parse("<root id=\"1\" class=\"main\"/>") |> DOM.build()
      assert doc.root.tag == "root"
      assert Element.get_attribute(doc.root, "id") == "1"
      assert Element.get_attribute(doc.root, "class") == "main"
    end

    test "parses nested elements" do
      doc = FnXML.Parser.parse("<root><child><grandchild/></child></root>") |> DOM.build()
      assert doc.root.tag == "root"
      [child] = doc.root.children
      assert child.tag == "child"
      [grandchild] = child.children
      assert grandchild.tag == "grandchild"
    end

    test "parses text content" do
      doc = FnXML.Parser.parse("<root>Hello World</root>") |> DOM.build()
      assert doc.root.children == ["Hello World"]
    end

    test "parses mixed content" do
      doc = FnXML.Parser.parse("<root>Hello <b>World</b>!</root>") |> DOM.build()
      assert length(doc.root.children) == 3
      assert Enum.at(doc.root.children, 0) == "Hello "
      assert Enum.at(doc.root.children, 1).tag == "b"
      assert Enum.at(doc.root.children, 2) == "!"
    end

    test "parses XML declaration" do
      doc = FnXML.Parser.parse("<?xml version=\"1.0\" encoding=\"UTF-8\"?><root/>") |> DOM.build()
      assert Document.version(doc) == "1.0"
      assert Document.encoding(doc) == "UTF-8"
    end

    test "parses comments when enabled" do
      doc =
        FnXML.Parser.parse("<root><!-- comment --></root>") |> DOM.build(include_comments: true)

      assert [{:comment, " comment "}] = doc.root.children
    end

    test "ignores comments by default" do
      doc = FnXML.Parser.parse("<root><!-- comment --><child/></root>") |> DOM.build()
      assert [%Element{tag: "child"}] = doc.root.children
    end
  end

  describe "serialization to string via FnXML.Stream" do
    test "serializes simple element" do
      doc = FnXML.Parser.parse("<root/>") |> DOM.build()
      iodata = DOM.to_event(doc) |> FnXML.Event.to_iodata()
      assert IO.iodata_to_binary(iodata) == "<root/>"
    end

    test "serializes element with attributes" do
      doc = FnXML.Parser.parse("<root id=\"1\"/>") |> DOM.build()
      iodata = DOM.to_event(doc) |> FnXML.Event.to_iodata()
      assert IO.iodata_to_binary(iodata) == "<root id=\"1\"/>"
    end

    test "serializes nested elements" do
      doc = FnXML.Parser.parse("<root><child/></root>") |> DOM.build()
      iodata = DOM.to_event(doc) |> FnXML.Event.to_iodata()
      assert IO.iodata_to_binary(iodata) == "<root><child/></root>"
    end

    test "serializes text content" do
      doc = FnXML.Parser.parse("<root>Hello</root>") |> DOM.build()
      iodata = DOM.to_event(doc) |> FnXML.Event.to_iodata()
      assert IO.iodata_to_binary(iodata) == "<root>Hello</root>"
    end

    test "escapes special characters" do
      elem = Element.new("root", [], ["<>&"])
      iodata = DOM.to_event(elem) |> FnXML.Event.to_iodata()
      assert IO.iodata_to_binary(iodata) == "<root>&lt;&gt;&amp;</root>"
    end

    test "pretty prints when enabled" do
      doc = FnXML.Parser.parse("<root><child/></root>") |> DOM.build()
      iodata = DOM.to_event(doc) |> FnXML.Event.to_iodata(pretty: true)
      result = IO.iodata_to_binary(iodata)
      assert result =~ "\n"
      assert result =~ "  <child/>"
    end
  end

  describe "to_event/1" do
    test "converts element to event stream" do
      elem = Element.new("root", [{"id", "1"}], ["text"])
      events = DOM.to_event(elem) |> Enum.to_list()

      assert [
               {:start_element, "root", [{"id", "1"}], nil},
               {:characters, "text", nil},
               {:end_element, "root"}
             ] = events
    end

    test "converts document to event stream" do
      doc = FnXML.Parser.parse("<root><child/></root>") |> DOM.build()
      events = DOM.to_event(doc) |> Enum.to_list()

      assert [
               {:start_element, "root", [], nil},
               {:start_element, "child", [], nil},
               {:end_element, "child"},
               {:end_element, "root"}
             ] = events
    end
  end

  describe "round-trip" do
    test "parse and serialize produce equivalent output" do
      original = "<root id=\"1\"><child>text</child></root>"
      doc = FnXML.Parser.parse(original) |> DOM.build()
      iodata = DOM.to_event(doc) |> FnXML.Event.to_iodata()
      result = IO.iodata_to_binary(iodata)
      assert result == original
    end
  end

  # ==========================================================================
  # Builder-specific tests for coverage
  # ==========================================================================

  describe "Builder CDATA handling" do
    test "parses CDATA sections" do
      doc = FnXML.Parser.parse("<root><![CDATA[<data>]]></root>") |> DOM.build()
      # Parser may emit CDATA as characters or cdata tuple
      assert is_list(doc.root.children)
      assert length(doc.root.children) == 1
    end
  end

  describe "Builder processing instructions" do
    test "parses PI inside element" do
      doc = FnXML.Parser.parse("<root><?php echo 'hi'; ?></root>") |> DOM.build()
      assert [{:pi, "php", _}] = doc.root.children
    end

    test "ignores PI outside elements" do
      doc = FnXML.Parser.parse("<?xml-stylesheet type='text/xsl'?><root/>") |> DOM.build()
      assert doc.root.tag == "root"
    end
  end

  describe "Builder DOCTYPE handling" do
    test "captures DOCTYPE" do
      doc = FnXML.Parser.parse("<!DOCTYPE html><root/>") |> DOM.build()
      assert doc.doctype != nil
    end
  end

  describe "Builder namespace handling" do
    test "captures default namespace" do
      doc = FnXML.Parser.parse("<root xmlns=\"http://example.org\"/>") |> DOM.build()
      assert doc.root.namespace_uri == "http://example.org"
    end

    test "captures prefixed namespace" do
      doc = FnXML.Parser.parse("<ex:root xmlns:ex=\"http://example.org\"/>") |> DOM.build()
      assert doc.root.tag == "root"
      assert doc.root.prefix == "ex"
      assert doc.root.namespace_uri == "http://example.org"
    end

    test "handles empty default namespace" do
      doc = FnXML.Parser.parse("<root xmlns=\"\"/>") |> DOM.build()
      assert doc.root.namespace_uri == nil
    end
  end

  describe "Builder error handling" do
    test "handles errors in stream" do
      # Parser errors are ignored by builder
      doc = FnXML.Parser.parse("<root><unclosed") |> DOM.build()
      # Builder should still produce a result
      assert is_struct(doc, Document)
    end
  end

  describe "Builder include_prolog option" do
    test "excludes prolog when include_prolog is false" do
      doc =
        FnXML.Parser.parse("<?xml version=\"1.0\"?><root/>")
        |> FnXML.API.DOM.Builder.from_stream(include_prolog: false)

      assert doc.prolog == nil
    end
  end

  describe "Builder with multiple root children (malformed XML)" do
    test "handles empty stream" do
      doc = [] |> FnXML.API.DOM.Builder.from_stream()
      assert doc.root == nil
    end
  end

  # ==========================================================================
  # Document tests
  # ==========================================================================

  describe "Document.new/2" do
    test "creates document with root only" do
      root = Element.new("html")
      doc = Document.new(root)
      assert doc.root == root
      assert doc.prolog == nil
    end

    test "creates document with prolog" do
      root = Element.new("html")
      doc = Document.new(root, version: "1.0", encoding: "UTF-8", standalone: "yes")
      assert doc.prolog == %{version: "1.0", encoding: "UTF-8", standalone: "yes"}
    end

    test "creates document with doctype" do
      root = Element.new("html")
      doc = Document.new(root, doctype: "html")
      assert doc.doctype == "html"
    end

    test "creates document with empty prolog options" do
      root = Element.new("html")
      doc = Document.new(root, [])
      assert doc.prolog == nil
    end
  end

  describe "Document.version/1" do
    test "returns version from prolog" do
      root = Element.new("root")
      doc = Document.new(root, version: "1.1")
      assert Document.version(doc) == "1.1"
    end

    test "returns nil when no prolog" do
      root = Element.new("root")
      doc = Document.new(root)
      assert Document.version(doc) == nil
    end
  end

  describe "Document.encoding/1" do
    test "returns encoding from prolog" do
      root = Element.new("root")
      doc = Document.new(root, encoding: "ISO-8859-1")
      assert Document.encoding(doc) == "ISO-8859-1"
    end

    test "returns nil when no encoding" do
      root = Element.new("root")
      doc = Document.new(root, version: "1.0")
      assert Document.encoding(doc) == nil
    end
  end

  describe "Document.standalone/1" do
    test "returns standalone from prolog" do
      root = Element.new("root")
      doc = Document.new(root, standalone: "yes")
      assert Document.standalone(doc) == "yes"
    end

    test "returns nil when no standalone" do
      root = Element.new("root")
      doc = Document.new(root)
      assert Document.standalone(doc) == nil
    end
  end

  describe "Document.document_element/1" do
    test "returns root element" do
      root = Element.new("html")
      doc = Document.new(root)
      assert Document.document_element(doc) == root
    end
  end

  describe "Document.get_elements_by_tag_name/2" do
    test "finds elements by tag name" do
      doc = FnXML.Parser.parse("<root><item/><item/><other/></root>") |> DOM.build()
      items = Document.get_elements_by_tag_name(doc, "item")
      assert length(items) == 2
    end

    test "finds root if it matches" do
      doc = FnXML.Parser.parse("<root/>") |> DOM.build()
      roots = Document.get_elements_by_tag_name(doc, "root")
      assert length(roots) == 1
    end

    test "finds nested elements" do
      doc = FnXML.Parser.parse("<root><a><item/></a><item/></root>") |> DOM.build()
      items = Document.get_elements_by_tag_name(doc, "item")
      assert length(items) == 2
    end

    test "returns empty list for nil root" do
      doc = %Document{root: nil}
      assert Document.get_elements_by_tag_name(doc, "any") == []
    end
  end

  describe "Document.get_element_by_id/2" do
    test "finds element by id attribute" do
      doc = FnXML.Parser.parse("<root><child id=\"target\">found</child></root>") |> DOM.build()
      elem = Document.get_element_by_id(doc, "target")
      assert elem.tag == "child"
    end

    test "finds nested element by id" do
      doc = FnXML.Parser.parse("<root><a><b id=\"deep\"/></a></root>") |> DOM.build()
      elem = Document.get_element_by_id(doc, "deep")
      assert elem.tag == "b"
    end

    test "returns nil when id not found" do
      doc = FnXML.Parser.parse("<root><child/></root>") |> DOM.build()
      assert Document.get_element_by_id(doc, "nonexistent") == nil
    end

    test "returns nil for nil root" do
      doc = %Document{root: nil}
      assert Document.get_element_by_id(doc, "any") == nil
    end

    test "finds root element by id" do
      doc = FnXML.Parser.parse("<root id=\"main\"/>") |> DOM.build()
      elem = Document.get_element_by_id(doc, "main")
      assert elem.tag == "root"
    end
  end

  # ==========================================================================
  # Element tests
  # ==========================================================================

  describe "Element.new/3" do
    test "creates element with tag only" do
      elem = Element.new("div")
      assert elem.tag == "div"
      assert elem.attributes == []
      assert elem.children == []
    end

    test "creates element with attributes and children" do
      elem = Element.new("p", [{"class", "intro"}], ["Hello"])
      assert elem.attributes == [{"class", "intro"}]
      assert elem.children == ["Hello"]
    end
  end

  describe "Element.new_ns/3" do
    test "creates namespaced element" do
      elem = Element.new_ns("http://example.org", "item", "ex")
      assert elem.tag == "item"
      assert elem.namespace_uri == "http://example.org"
      assert elem.prefix == "ex"
    end

    test "creates namespaced element without prefix" do
      elem = Element.new_ns("http://example.org", "item")
      assert elem.namespace_uri == "http://example.org"
      assert elem.prefix == nil
    end
  end

  describe "Element.get_attribute/2" do
    test "gets existing attribute" do
      elem = Element.new("div", [{"id", "main"}, {"class", "container"}])
      assert Element.get_attribute(elem, "id") == "main"
      assert Element.get_attribute(elem, "class") == "container"
    end

    test "returns nil for missing attribute" do
      elem = Element.new("div")
      assert Element.get_attribute(elem, "id") == nil
    end
  end

  describe "Element.set_attribute/3" do
    test "adds new attribute" do
      elem = Element.new("div")
      elem = Element.set_attribute(elem, "id", "main")
      assert Element.get_attribute(elem, "id") == "main"
    end

    test "updates existing attribute" do
      elem = Element.new("div", [{"id", "old"}])
      elem = Element.set_attribute(elem, "id", "new")
      assert Element.get_attribute(elem, "id") == "new"
    end
  end

  describe "Element.remove_attribute/2" do
    test "removes existing attribute" do
      elem = Element.new("div", [{"id", "main"}, {"class", "container"}])
      elem = Element.remove_attribute(elem, "id")
      assert Element.get_attribute(elem, "id") == nil
      assert Element.get_attribute(elem, "class") == "container"
    end

    test "handles removing non-existent attribute" do
      elem = Element.new("div")
      elem = Element.remove_attribute(elem, "id")
      assert elem.attributes == []
    end
  end

  describe "Element.has_attribute?/2" do
    test "returns true for existing attribute" do
      elem = Element.new("div", [{"id", "main"}])
      assert Element.has_attribute?(elem, "id") == true
    end

    test "returns false for missing attribute" do
      elem = Element.new("div")
      assert Element.has_attribute?(elem, "id") == false
    end
  end

  describe "Element.append_child/2" do
    test "appends child to empty element" do
      parent = Element.new("div")
      child = Element.new("span")
      parent = Element.append_child(parent, child)
      assert length(parent.children) == 1
      assert hd(parent.children).tag == "span"
    end

    test "appends child to existing children" do
      parent = Element.new("div", [], [Element.new("a")])
      child = Element.new("b")
      parent = Element.append_child(parent, child)
      assert length(parent.children) == 2
      assert List.last(parent.children).tag == "b"
    end

    test "appends text child" do
      parent = Element.new("p")
      parent = Element.append_child(parent, "Hello")
      assert parent.children == ["Hello"]
    end
  end

  describe "Element.prepend_child/2" do
    test "prepends child" do
      parent = Element.new("div", [], [Element.new("b")])
      child = Element.new("a")
      parent = Element.prepend_child(parent, child)
      assert length(parent.children) == 2
      assert hd(parent.children).tag == "a"
    end
  end

  describe "Element.text_content/1" do
    test "returns text from element" do
      elem = Element.new("p", [], ["Hello World"])
      assert Element.text_content(elem) == "Hello World"
    end

    test "concatenates text from nested elements" do
      elem =
        Element.new("p", [], [
          "Hello ",
          Element.new("b", [], ["World"]),
          "!"
        ])

      assert Element.text_content(elem) == "Hello World!"
    end

    test "includes CDATA content" do
      elem = Element.new("p", [], [{:cdata, "CDATA text"}])
      assert Element.text_content(elem) == "CDATA text"
    end

    test "ignores comments" do
      elem = Element.new("p", [], ["text", {:comment, "ignored"}])
      assert Element.text_content(elem) == "text"
    end
  end

  describe "Element.get_elements_by_tag_name/2" do
    test "finds direct children" do
      elem =
        Element.new("ul", [], [
          Element.new("li", [], ["One"]),
          Element.new("li", [], ["Two"])
        ])

      items = Element.get_elements_by_tag_name(elem, "li")
      assert length(items) == 2
    end

    test "finds nested elements" do
      elem =
        Element.new("root", [], [
          Element.new("a", [], [
            Element.new("item")
          ]),
          Element.new("item")
        ])

      items = Element.get_elements_by_tag_name(elem, "item")
      assert length(items) == 2
    end

    test "returns empty list when no matches" do
      elem = Element.new("div")
      assert Element.get_elements_by_tag_name(elem, "span") == []
    end
  end

  describe "Element.qualified_name/1" do
    test "returns tag for unprefixed element" do
      elem = Element.new("div")
      assert Element.qualified_name(elem) == "div"
    end

    test "returns prefix:tag for prefixed element" do
      elem = Element.new_ns("http://example.org", "item", "ex")
      assert Element.qualified_name(elem) == "ex:item"
    end
  end
end
