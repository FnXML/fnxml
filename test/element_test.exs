defmodule FnXML.ElementsTest do
  use ExUnit.Case

  alias FnXML.Element

  doctest Element

  describe "tag" do
    test "tag without namespace" do
      # New format: {:start_element, tag, attrs, line, ls, pos}
      assert Element.tag({:start_element, "foo", [], 1, 0, 1}) == {"foo", ""}
    end

    test "tag with namespace" do
      assert Element.tag({:start_element, "bar:foo", [], 1, 0, 1}) == {"foo", "bar"}
    end

    test "tag from string" do
      assert Element.tag("foo") == {"foo", ""}
      assert Element.tag("bar:foo") == {"foo", "bar"}
    end

    test "tag from end_element" do
      assert Element.tag({:end_element, "foo", 1, 0, 1}) == {"foo", ""}
      assert Element.tag({:end_element, "ns:bar", 1, 0, 5}) == {"bar", "ns"}
    end
  end

  describe "tag name" do
    test "tag name without namespace" do
      assert Element.tag_name({"foo", nil}) == "foo"
      assert Element.tag_name({"foo", ""}) == "foo"
    end

    test "tag name with namespace" do
      assert Element.tag_name({"foo", "bar"}) == "bar:foo"
    end
  end

  describe "attributes" do
    test "element without attributes" do
      assert Element.attributes({:start_element, "foo", [], 1, 0, 1}) == []
    end

    test "element with attributes" do
      assert Element.attributes({:start_element, "foo", [{"bar", "baz"}, {"a", "1"}], 1, 0, 1}) ==
               [{"bar", "baz"}, {"a", "1"}]
    end
  end

  describe "attributes_map" do
    test "element without attributes" do
      assert Element.attribute_map({:start_element, "foo", [], 1, 0, 1}) == %{}
    end

    test "element with attributes" do
      assert Element.attribute_map({:start_element, "foo", [{"bar", "baz"}, {"a", "1"}], 1, 0, 1}) ==
               %{"bar" => "baz", "a" => "1"}
    end
  end

  describe "content" do
    test "text element content" do
      # Content is extracted from text elements: {:characters, content, line, ls, pos}
      assert Element.content({:characters, "hello world", 1, 0, 5}) == "hello world"
    end

    test "comment element content" do
      assert Element.content({:comment, " a comment ", 1, 0, 1}) == " a comment "
    end

    test "space element content" do
      assert Element.content({:space, "  ", 1, 0, 1}) == "  "
    end

    test "cdata element content" do
      assert Element.content({:cdata, "some data", 1, 0, 1}) == "some data"
    end
  end

  describe "position" do
    test "element position" do
      # Position is calculated from: {line, pos - ls}
      assert Element.position({:start_element, "foo", [], 2, 15, 19}) == {2, 4}
    end

    test "text element position" do
      assert Element.position({:characters, "hello", 1, 0, 5}) == {1, 5}
    end

    test "close tag position" do
      assert Element.position({:end_element, "foo", 1, 0, 10}) == {1, 10}
    end
  end

  describe "loc" do
    test "open element loc" do
      assert Element.loc({:start_element, "foo", [], 2, 15, 19}) == {2, 15, 19}
    end

    test "close element loc" do
      assert Element.loc({:end_element, "foo", 1, 0, 10}) == {1, 0, 10}
    end

    test "characters loc" do
      assert Element.loc({:characters, "text", 1, 0, 5}) == {1, 0, 5}
    end
  end

  describe "tag_string" do
    test "open element tag string" do
      assert Element.tag_string({:start_element, "foo", [], 1, 0, 1}) == "foo"
      assert Element.tag_string({:start_element, "ns:bar", [], 1, 0, 1}) == "ns:bar"
    end

    test "close element tag string" do
      assert Element.tag_string({:end_element, "foo", 1, 0, 5}) == "foo"
      assert Element.tag_string({:end_element, "ns:bar", 1, 0, 5}) == "ns:bar"
    end
  end

  describe "id_list" do
    test "returns all event type atoms" do
      ids = Element.id_list()
      assert :start_document in ids
      assert :end_document in ids
      assert :prolog in ids
      assert :start_element in ids
      assert :end_element in ids
      assert :characters in ids
      assert :space in ids
      assert :comment in ids
      assert :cdata in ids
      assert :dtd in ids
      assert :processing_instruction in ids
      assert :error in ids
    end
  end

  describe "attributes from prolog" do
    test "returns attributes from prolog element" do
      attrs = [{"version", "1.0"}, {"encoding", "UTF-8"}]
      assert Element.attributes({:prolog, "xml", attrs, 1, 0, 1}) == attrs
    end
  end

  describe "content from processing instruction" do
    test "returns content from PI" do
      assert Element.content({:processing_instruction, "php", "echo 'hi'", 1, 0, 1}) ==
               "echo 'hi'"
    end
  end

  describe "position for all event types" do
    test "start_document position" do
      assert Element.position({:start_document, nil}) == {0, 0}
    end

    test "end_document position" do
      assert Element.position({:end_document, nil}) == {0, 0}
    end

    test "comment position" do
      assert Element.position({:comment, "text", 1, 5, 10}) == {1, 5}
    end

    test "space position" do
      assert Element.position({:space, "  ", 1, 5, 10}) == {1, 5}
    end

    test "cdata position" do
      assert Element.position({:cdata, "data", 1, 5, 10}) == {1, 5}
    end

    test "dtd position" do
      assert Element.position({:dtd, "<!DOCTYPE>", 1, 0, 5}) == {1, 5}
    end

    test "prolog position" do
      assert Element.position({:prolog, "xml", [], 1, 0, 2}) == {1, 2}
    end

    test "processing_instruction position" do
      assert Element.position({:processing_instruction, "php", "", 2, 10, 15}) == {2, 5}
    end

    test "error position" do
      assert Element.position({:error, :syntax, "msg", 3, 20, 25}) == {3, 5}
    end

    test "end_element position" do
      assert Element.position({:end_element, "foo", 2, 10, 18}) == {2, 8}
    end
  end

  describe "loc for all event types" do
    test "start_document loc" do
      assert Element.loc({:start_document, nil}) == nil
    end

    test "end_document loc" do
      assert Element.loc({:end_document, nil}) == nil
    end

    test "characters loc" do
      assert Element.loc({:characters, "text", 1, 0, 5}) == {1, 0, 5}
    end

    test "space loc" do
      assert Element.loc({:space, "  ", 1, 0, 5}) == {1, 0, 5}
    end

    test "comment loc" do
      assert Element.loc({:comment, "text", 1, 5, 10}) == {1, 5, 10}
    end

    test "cdata loc" do
      assert Element.loc({:cdata, "data", 1, 5, 10}) == {1, 5, 10}
    end

    test "dtd loc" do
      assert Element.loc({:dtd, "<!DOCTYPE>", 1, 0, 5}) == {1, 0, 5}
    end

    test "prolog loc" do
      assert Element.loc({:prolog, "xml", [], 1, 0, 2}) == {1, 0, 2}
    end

    test "processing_instruction loc" do
      assert Element.loc({:processing_instruction, "php", "", 2, 10, 15}) == {2, 10, 15}
    end

    test "error loc" do
      assert Element.loc({:error, :syntax, "msg", 3, 20, 25}) == {3, 20, 25}
    end
  end
end
