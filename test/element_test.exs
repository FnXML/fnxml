defmodule FnXML.ElementsTest do
  use ExUnit.Case

  alias FnXML.Element

  doctest Element

  describe "tag" do
    test "tag without namespace" do
      assert Element.tag({:open, [tag: "foo"]}) == {"foo", ""}
    end
    test "tag with namespace" do
      assert Element.tag({:open, [tag: "foo", namespace: "bar"]}) == {"foo", "bar"}
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
      assert Element.attributes({:open, [tag: "foo"]}) == []
    end
    test "element with attributes" do
      assert Element.attributes({:open, [tag: "foo", attributes: [{"bar", "baz"}, {"a", "1"}]]}) == [{"bar", "baz"}, {"a", "1"}]
    end
  end
  
  describe "attributes_map" do
    test "element without attributes" do
      assert Element.attribute_map({:open, [tag: "foo"]}) == %{}
    end
    test "element with attributes" do
      assert Element.attribute_map({:open, [tag: "foo", attributes: [{"bar", "baz"}, {"a", "1"}]]}) == %{"bar" => "baz", "a" => "1"}
    end
  end
        
  describe "position" do
    test "element without position" do
      assert Element.position({:open, [tag: "foo"]}) == {0, 0}
    end

    test "element with zero position" do
      assert Element.position({:open, [tag: "foo", position: 0]}) == {0, 0}
    end
  end

  describe "close?" do
    test "element is not closed" do
      assert Element.close?({:open, [tag: "foo"]}) == false
    end

    test "element is closed" do
      assert Element.close?({:open, [tag: "foo", close: true]}) == true
    end
  end
end
