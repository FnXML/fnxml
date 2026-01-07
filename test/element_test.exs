defmodule FnXML.ElementsTest do
  use ExUnit.Case

  alias FnXML.Element

  doctest Element

  describe "tag" do
    test "tag without namespace" do
      # New format: {:open, tag, attrs, loc}
      assert Element.tag({:open, "foo", [], {1, 0, 1}}) == {"foo", ""}
    end

    test "tag with namespace" do
      assert Element.tag({:open, "bar:foo", [], {1, 0, 1}}) == {"foo", "bar"}
    end

    test "tag from string" do
      assert Element.tag("foo") == {"foo", ""}
      assert Element.tag("bar:foo") == {"foo", "bar"}
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
      assert Element.attributes({:open, "foo", [], {1, 0, 1}}) == []
    end

    test "element with attributes" do
      assert Element.attributes({:open, "foo", [{"bar", "baz"}, {"a", "1"}], {1, 0, 1}}) ==
               [{"bar", "baz"}, {"a", "1"}]
    end
  end

  describe "attributes_map" do
    test "element without attributes" do
      assert Element.attribute_map({:open, "foo", [], {1, 0, 1}}) == %{}
    end

    test "element with attributes" do
      assert Element.attribute_map(
               {:open, "foo", [{"bar", "baz"}, {"a", "1"}], {1, 0, 1}}
             ) == %{"bar" => "baz", "a" => "1"}
    end
  end

  describe "content" do
    test "text element content" do
      # Content is extracted from text elements: {:text, content, loc}
      assert Element.content({:text, "hello world", {1, 0, 5}}) == "hello world"
    end

    test "comment element content" do
      assert Element.content({:comment, " a comment ", {1, 0, 1}}) == " a comment "
    end
  end

  describe "position" do
    test "element position" do
      # Position is calculated from loc: {line, line_start, abs_pos}
      # Result is {line, abs_pos - line_start}
      assert Element.position({:open, "foo", [], {2, 15, 19}}) == {2, 4}
    end

    test "text element position" do
      assert Element.position({:text, "hello", {1, 0, 5}}) == {1, 5}
    end

    test "close tag without loc" do
      assert Element.position({:close, "foo"}) == {0, 0}
    end
  end

  describe "loc" do
    test "open element loc" do
      assert Element.loc({:open, "foo", [], {2, 15, 19}}) == {2, 15, 19}
    end

    test "close element without loc" do
      assert Element.loc({:close, "foo"}) == nil
    end

    test "close element with loc" do
      assert Element.loc({:close, "foo", {1, 0, 10}}) == {1, 0, 10}
    end
  end

  describe "tag_string" do
    test "open element tag string" do
      assert Element.tag_string({:open, "foo", [], {1, 0, 1}}) == "foo"
      assert Element.tag_string({:open, "ns:bar", [], {1, 0, 1}}) == "ns:bar"
    end

    test "close element tag string" do
      assert Element.tag_string({:close, "foo"}) == "foo"
      assert Element.tag_string({:close, "ns:bar", {1, 0, 5}}) == "ns:bar"
    end
  end
end
