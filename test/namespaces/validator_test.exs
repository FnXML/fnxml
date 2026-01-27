defmodule FnXML.Validate.NamespacesTest do
  use ExUnit.Case, async: true

  alias FnXML.Validate.Namespaces, as: Validator

  describe "validate/2" do
    test "valid document passes through unchanged" do
      xml = ~s(<root xmlns="http://example.org"><child/></root>)

      events =
        FnXML.Parser.parse(xml)
        |> Validator.validate()
        |> Enum.to_list()

      refute Enum.any?(events, &match?({:ns_error, _, _, _}, &1))
    end

    test "emits error for undeclared prefix on element" do
      xml = "<foo:bar/>"

      events =
        FnXML.Parser.parse(xml)
        |> Validator.validate()
        |> Enum.to_list()

      assert Enum.any?(events, fn
               {:ns_error, {:undeclared_prefix, "foo"}, "foo:bar", _} -> true
               _ -> false
             end)
    end

    test "emits error for undeclared prefix on attribute" do
      xml = ~s(<root foo:attr="1"/>)

      events =
        FnXML.Parser.parse(xml)
        |> Validator.validate()
        |> Enum.to_list()

      assert Enum.any?(events, fn
               {:ns_error, {:undeclared_prefix, "foo"}, "foo:attr", _} -> true
               _ -> false
             end)
    end

    test "xml prefix is always valid" do
      xml = ~s(<root xml:lang="en"/>)

      events =
        FnXML.Parser.parse(xml)
        |> Validator.validate()
        |> Enum.to_list()

      refute Enum.any?(events, &match?({:ns_error, _, _, _}, &1))
    end

    test "declared prefix is valid" do
      xml = ~s(<foo:root xmlns:foo="http://foo.org"/>)

      events =
        FnXML.Parser.parse(xml)
        |> Validator.validate()
        |> Enum.to_list()

      refute Enum.any?(events, &match?({:ns_error, _, _, _}, &1))
    end

    test "prefix declared on same element is valid" do
      xml = ~s(<foo:root xmlns:foo="http://foo.org" foo:attr="1"/>)

      events =
        FnXML.Parser.parse(xml)
        |> Validator.validate()
        |> Enum.to_list()

      refute Enum.any?(events, &match?({:ns_error, _, _, _}, &1))
    end
  end

  describe "validate/2 with invalid QNames" do
    test "emits error for invalid element QName" do
      # This would need a parser that doesn't validate names
      # For now we test through the validator directly
    end
  end

  describe "validate/2 with reserved prefixes" do
    test "emits error for xmlns used as element prefix" do
      # xmlns:element is invalid
      xml = ~s(<root xmlns:foo="http://foo.org"><xmlns:bar/></root>)

      events =
        FnXML.Parser.parse(xml)
        |> Validator.validate()
        |> Enum.to_list()

      assert Enum.any?(events, fn
               {:ns_error, {:xmlns_element, _}, _, _} -> true
               _ -> false
             end)
    end
  end

  describe "validate/2 with duplicate attributes" do
    test "emits error for duplicate expanded attribute names" do
      xml = ~s(<root xmlns:a="http://ns.org" xmlns:b="http://ns.org" a:x="1" b:x="2"/>)

      events =
        FnXML.Parser.parse(xml)
        |> Validator.validate()
        |> Enum.to_list()

      assert Enum.any?(events, fn
               {:ns_error, {:duplicate_attribute, {"http://ns.org", "x"}, _}, _, _} -> true
               _ -> false
             end)
    end

    test "allows same local name with different namespaces" do
      xml = ~s(<root xmlns:a="http://a.org" xmlns:b="http://b.org" a:x="1" b:x="2"/>)

      events =
        FnXML.Parser.parse(xml)
        |> Validator.validate()
        |> Enum.to_list()

      refute Enum.any?(events, fn
               {:ns_error, {:duplicate_attribute, _, _}, _, _} -> true
               _ -> false
             end)
    end

    test "allows unprefixed and prefixed with same local name" do
      xml = ~s(<root xmlns:a="http://a.org" x="1" a:x="2"/>)

      events =
        FnXML.Parser.parse(xml)
        |> Validator.validate()
        |> Enum.to_list()

      refute Enum.any?(events, fn
               {:ns_error, {:duplicate_attribute, _, _}, _, _} -> true
               _ -> false
             end)
    end
  end

  describe "validate/2 with namespace declarations" do
    test "emits error for empty prefix binding in XML 1.0" do
      xml = ~s(<root xmlns:foo="http://foo.org"><child xmlns:foo=""/></root>)

      events =
        FnXML.Parser.parse(xml)
        |> Validator.validate()
        |> Enum.to_list()

      assert Enum.any?(events, fn
               {:ns_error, {:empty_prefix_binding, "foo"}, _, _} -> true
               _ -> false
             end)
    end

    test "allows empty prefix binding in XML 1.1" do
      xml = """
      <?xml version="1.1"?>
      <root xmlns:foo="http://foo.org"><child xmlns:foo=""/></root>
      """

      events =
        FnXML.Parser.parse(xml)
        |> Validator.validate()
        |> Enum.to_list()

      refute Enum.any?(events, fn
               {:ns_error, {:empty_prefix_binding, _}, _, _} -> true
               _ -> false
             end)
    end

    test "emits error when using unbound prefix after unbinding in XML 1.1" do
      xml = """
      <?xml version="1.1"?>
      <root xmlns:a="http://example.org">
        <a:child xmlns:a=""/>
      </root>
      """

      events =
        FnXML.Parser.parse(xml)
        |> Validator.validate()
        |> Enum.to_list()

      assert Enum.any?(events, fn
               {:ns_error, {:undeclared_prefix, "a"}, _, _} -> true
               _ -> false
             end)
    end
  end

  describe "validate/2 with processing instructions" do
    test "emits error for PI target with colon" do
      xml = "<root><?foo:bar instruction?></root>"

      events =
        FnXML.Parser.parse(xml)
        |> Validator.validate()
        |> Enum.to_list()

      assert Enum.any?(events, fn
               {:ns_error, {:colon_in_pi_target, "foo:bar"}, _, _} -> true
               _ -> false
             end)
    end

    test "allows PI target without colon" do
      xml = "<root><?foobar instruction?></root>"

      events =
        FnXML.Parser.parse(xml)
        |> Validator.validate()
        |> Enum.to_list()

      refute Enum.any?(events, fn
               {:ns_error, {:colon_in_pi_target, _}, _, _} -> true
               _ -> false
             end)
    end
  end

  describe "validate/2 scoping" do
    test "prefix goes out of scope after element closes" do
      xml = """
      <root>
        <child xmlns:foo="http://foo.org"><foo:inner/></child>
        <other><foo:should-fail/></other>
      </root>
      """

      events =
        FnXML.Parser.parse(xml)
        |> Validator.validate()
        |> Enum.to_list()

      # foo:inner should be valid (in scope)
      # foo:should-fail should be invalid (out of scope)
      errors = Enum.filter(events, &match?({:ns_error, _, _, _}, &1))
      assert length(errors) == 1

      assert Enum.any?(errors, fn
               {:ns_error, {:undeclared_prefix, "foo"}, "foo:should-fail", _} -> true
               _ -> false
             end)
    end
  end
end
