defmodule FnXML.NamespacesTest do
  use ExUnit.Case
  doctest FnXML.Namespaces

  alias FnXML.Namespaces

  # ==========================================================================
  # Constants
  # ==========================================================================

  describe "constants" do
    test "xml_namespace returns correct URI" do
      assert Namespaces.xml_namespace() == "http://www.w3.org/XML/1998/namespace"
    end

    test "xmlns_namespace returns correct URI" do
      assert Namespaces.xmlns_namespace() == "http://www.w3.org/2000/xmlns/"
    end
  end

  # ==========================================================================
  # QName utilities
  # ==========================================================================

  describe "valid_ncname?/1" do
    test "returns true for valid NCNames" do
      assert Namespaces.valid_ncname?("foo") == true
      assert Namespaces.valid_ncname?("_underscore") == true
      assert Namespaces.valid_ncname?("name123") == true
    end

    test "returns false for invalid NCNames" do
      assert Namespaces.valid_ncname?("foo:bar") == false
      assert Namespaces.valid_ncname?("123start") == false
      assert Namespaces.valid_ncname?("") == false
    end
  end

  describe "valid_qname?/1" do
    test "returns true for valid QNames" do
      assert Namespaces.valid_qname?("foo") == true
      assert Namespaces.valid_qname?("ns:local") == true
    end

    test "returns false for invalid QNames" do
      assert Namespaces.valid_qname?("") == false
      assert Namespaces.valid_qname?(":noprefix") == false
    end
  end

  describe "parse_qname/1" do
    test "parses prefixed name" do
      assert Namespaces.parse_qname("ns:local") == {"ns", "local"}
    end

    test "parses unprefixed name" do
      assert Namespaces.parse_qname("local") == {nil, "local"}
    end
  end

  describe "namespace_declaration?/1" do
    test "detects default namespace declaration" do
      assert Namespaces.namespace_declaration?("xmlns") == {:default, nil}
    end

    test "detects prefixed namespace declaration" do
      assert Namespaces.namespace_declaration?("xmlns:foo") == {:prefix, "foo"}
    end

    test "returns false for regular attributes" do
      assert Namespaces.namespace_declaration?("id") == false
      assert Namespaces.namespace_declaration?("foo:bar") == false
    end
  end

  # ==========================================================================
  # Context
  # ==========================================================================

  describe "new_context/0" do
    test "creates a new context with xml prefix bound" do
      ctx = Namespaces.new_context()
      assert ctx != nil
    end
  end

  describe "expand_element/2" do
    test "expands unprefixed element with default namespace" do
      ctx = Namespaces.new_context()

      {:ok, ctx, _} =
        FnXML.Namespaces.Context.push(ctx, [{"xmlns", "http://example.org"}])

      assert {:ok, {"http://example.org", "elem"}} = Namespaces.expand_element(ctx, "elem")
    end

    test "expands prefixed element" do
      ctx = Namespaces.new_context()

      {:ok, ctx, _} =
        FnXML.Namespaces.Context.push(ctx, [{"xmlns:ex", "http://example.org"}])

      assert {:ok, {"http://example.org", "elem"}} = Namespaces.expand_element(ctx, "ex:elem")
    end

    test "returns error for undeclared prefix" do
      ctx = Namespaces.new_context()
      assert {:error, _} = Namespaces.expand_element(ctx, "unknown:elem")
    end
  end

  describe "expand_attribute/2" do
    test "unprefixed attributes have no namespace" do
      ctx = Namespaces.new_context()

      {:ok, ctx, _} =
        FnXML.Namespaces.Context.push(ctx, [{"xmlns", "http://example.org"}])

      # Unprefixed attributes do NOT inherit default namespace
      assert {:ok, {nil, "attr"}} = Namespaces.expand_attribute(ctx, "attr")
    end

    test "expands prefixed attribute" do
      ctx = Namespaces.new_context()

      {:ok, ctx, _} =
        FnXML.Namespaces.Context.push(ctx, [{"xmlns:ex", "http://example.org"}])

      assert {:ok, {"http://example.org", "attr"}} = Namespaces.expand_attribute(ctx, "ex:attr")
    end
  end

  # ==========================================================================
  # Validate stream
  # ==========================================================================

  describe "validate/2" do
    test "passes through valid XML without errors" do
      xml = ~s(<root xmlns="http://example.org"><child/></root>)
      events = FnXML.Parser.parse(xml) |> Namespaces.validate() |> Enum.to_list()

      errors = Namespaces.errors(events)
      assert errors == []
    end

    test "emits error for undeclared prefix" do
      xml = ~s(<foo:bar/>)
      events = FnXML.Parser.parse(xml) |> Namespaces.validate() |> Enum.to_list()

      errors = Namespaces.errors(events)
      assert length(errors) > 0
      assert {:ns_error, {:undeclared_prefix, "foo"}, _, _} = hd(errors)
    end

    test "validates nested elements" do
      xml = ~s(<root xmlns:ns="http://example.org"><ns:child/></root>)
      events = FnXML.Parser.parse(xml) |> Namespaces.validate() |> Enum.to_list()

      errors = Namespaces.errors(events)
      assert errors == []
    end
  end

  # ==========================================================================
  # Resolve stream
  # ==========================================================================

  describe "resolve/2" do
    test "resolves default namespace" do
      xml = ~s(<root xmlns="http://example.org"><child/></root>)
      events = FnXML.Parser.parse(xml) |> Namespaces.resolve() |> Enum.to_list()

      start_events = Enum.filter(events, &match?({:start_element, _, _, _, _, _}, &1))

      # Find root element
      root_event =
        Enum.find(start_events, fn {:start_element, name, _, _, _, _} ->
          case name do
            {_, "root"} -> true
            _ -> false
          end
        end)

      assert {:start_element, {"http://example.org", "root"}, _, _, _, _} = root_event

      # Find child element
      child_event =
        Enum.find(start_events, fn {:start_element, name, _, _, _, _} ->
          case name do
            {_, "child"} -> true
            _ -> false
          end
        end)

      assert {:start_element, {"http://example.org", "child"}, _, _, _, _} = child_event
    end

    test "resolves prefixed namespace" do
      xml = ~s(<ns:root xmlns:ns="http://example.org"/>)
      events = FnXML.Parser.parse(xml) |> Namespaces.resolve() |> Enum.to_list()

      start_event = Enum.find(events, &match?({:start_element, _, _, _, _, _}, &1))
      assert {:start_element, {"http://example.org", "root"}, _, _, _, _} = start_event
    end

    test "unprefixed element without default namespace has nil URI" do
      xml = ~s(<root/>)
      events = FnXML.Parser.parse(xml) |> Namespaces.resolve() |> Enum.to_list()

      start_event = Enum.find(events, &match?({:start_element, _, _, _, _, _}, &1))
      assert {:start_element, {nil, "root"}, _, _, _, _} = start_event
    end
  end

  # ==========================================================================
  # Process stream (validate + resolve)
  # ==========================================================================

  describe "process/2" do
    test "validates and resolves in single pass" do
      xml = ~s(<root xmlns="http://example.org"><child/></root>)
      events = FnXML.Parser.parse(xml) |> Namespaces.process() |> Enum.to_list()

      # Should have no errors
      assert Namespaces.errors?(events) == false

      # Should have resolved names
      start_event =
        Enum.find(events, fn
          {:start_element, {_, "root"}, _, _, _, _} -> true
          _ -> false
        end)

      assert {:start_element, {"http://example.org", "root"}, _, _, _, _} = start_event
    end

    test "includes validation errors in output" do
      xml = ~s(<foo:bar/>)
      events = FnXML.Parser.parse(xml) |> Namespaces.process() |> Enum.to_list()

      assert Namespaces.errors?(events) == true
    end
  end

  # ==========================================================================
  # Error helpers
  # ==========================================================================

  describe "ns_error?/1" do
    test "returns true for namespace errors" do
      assert Namespaces.ns_error?({:ns_error, :reason, "name", {1, 0, 0}}) == true
    end

    test "returns false for other events" do
      assert Namespaces.ns_error?({:start_element, "tag", [], 1, 0, 0}) == false
      assert Namespaces.ns_error?(:other) == false
    end
  end

  describe "errors/1" do
    test "extracts error events from list" do
      events = [
        {:start_element, "tag", [], 1, 0, 0},
        {:ns_error, :reason1, "name1", {1, 0, 0}},
        {:characters, "text", 1, 0, 5},
        {:ns_error, :reason2, "name2", {2, 0, 0}}
      ]

      errors = Namespaces.errors(events)
      assert length(errors) == 2
    end

    test "returns empty list when no errors" do
      events = [{:start_element, "tag", [], 1, 0, 0}, {:end_element, "tag", 1, 0, 10}]
      assert Namespaces.errors(events) == []
    end
  end

  describe "errors?/1" do
    test "returns true when errors exist" do
      events = [{:ns_error, :reason, "name", {1, 0, 0}}]
      assert Namespaces.errors?(events) == true
    end

    test "returns false when no errors" do
      events = [{:start_element, "tag", [], 1, 0, 0}]
      assert Namespaces.errors?(events) == false
    end
  end
end
