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
  # Validate + Resolve pipeline
  # ==========================================================================

  describe "validate + resolve pipeline" do
    test "validates and resolves when piped" do
      xml = ~s(<root xmlns="http://example.org"><child/></root>)

      events =
        FnXML.Parser.parse(xml)
        |> Namespaces.validate()
        |> Namespaces.resolve()
        |> Enum.to_list()

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

      events =
        FnXML.Parser.parse(xml)
        |> Namespaces.validate()
        |> Namespaces.resolve()
        |> Enum.to_list()

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

  # ==========================================================================
  # Track stream (namespace context events)
  # ==========================================================================

  describe "track/2" do
    test "emits ns_context event before each start_element" do
      xml = ~s(<root><child/></root>)
      events = FnXML.Parser.parse(xml) |> Namespaces.track() |> Enum.to_list()

      # Count ns_context events
      context_events = Enum.filter(events, &Namespaces.ns_context?/1)
      start_events = Enum.filter(events, &match?({:start_element, _, _, _, _, _}, &1))

      # Should have one context event per start element
      assert length(context_events) == length(start_events)
    end

    test "context event appears before corresponding start_element" do
      xml = ~s(<root xmlns="http://example.org"/>)
      events = FnXML.Parser.parse(xml) |> Namespaces.track() |> Enum.to_list()

      # Find positions
      context_pos = Enum.find_index(events, &Namespaces.ns_context?/1)
      start_pos = Enum.find_index(events, &match?({:start_element, _, _, _, _, _}, &1))

      assert context_pos < start_pos
    end

    test "context contains correct namespace bindings" do
      xml = ~s(<root xmlns="http://example.org" xmlns:ns="http://ns.org"><ns:child/></root>)
      events = FnXML.Parser.parse(xml) |> Namespaces.track() |> Enum.to_list()

      # Get the context before the root element
      root_ctx =
        events
        |> Enum.find(&Namespaces.ns_context?/1)
        |> Namespaces.extract_context()

      assert FnXML.Namespaces.Context.default_namespace(root_ctx) == "http://example.org"
      assert {:ok, "http://ns.org"} = FnXML.Namespaces.Context.resolve_prefix(root_ctx, "ns")
    end

    test "child elements inherit parent namespace context" do
      xml = ~s(<root xmlns:ns="http://ns.org"><child><grandchild/></child></root>)
      events = FnXML.Parser.parse(xml) |> Namespaces.track() |> Enum.to_list()

      # Get all contexts
      contexts =
        events
        |> Enum.filter(&Namespaces.ns_context?/1)
        |> Enum.map(&Namespaces.extract_context/1)

      # All contexts should be able to resolve ns prefix
      for ctx <- contexts do
        assert {:ok, "http://ns.org"} = FnXML.Namespaces.Context.resolve_prefix(ctx, "ns")
      end
    end

    test "inner namespace declaration overrides parent" do
      xml = ~s(<root xmlns="http://outer.org"><child xmlns="http://inner.org"/></root>)
      events = FnXML.Parser.parse(xml) |> Namespaces.track() |> Enum.to_list()

      # Get contexts in order
      contexts =
        events
        |> Enum.filter(&Namespaces.ns_context?/1)
        |> Enum.map(&Namespaces.extract_context/1)

      [root_ctx, child_ctx] = contexts

      assert FnXML.Namespaces.Context.default_namespace(root_ctx) == "http://outer.org"
      assert FnXML.Namespaces.Context.default_namespace(child_ctx) == "http://inner.org"
    end

    test "is idempotent - passes through existing ns_context events" do
      xml = ~s(<root/>)

      # Track twice
      events =
        FnXML.Parser.parse(xml)
        |> Namespaces.track()
        |> Namespaces.track()
        |> Enum.to_list()

      # Should still have only one context event per element
      context_events = Enum.filter(events, &Namespaces.ns_context?/1)
      assert length(context_events) == 1
    end

    test "only_changes option reduces context events" do
      # Document with no namespace changes after root
      xml = ~s(<root xmlns="http://example.org"><a><b><c/></b></a></root>)

      events_all = FnXML.Parser.parse(xml) |> Namespaces.track() |> Enum.to_list()

      events_changes =
        FnXML.Parser.parse(xml) |> Namespaces.track(only_changes: true) |> Enum.to_list()

      all_contexts = Enum.filter(events_all, &Namespaces.ns_context?/1)
      change_contexts = Enum.filter(events_changes, &Namespaces.ns_context?/1)

      # All contexts mode emits for every element (4: root, a, b, c)
      assert length(all_contexts) == 4

      # Only changes mode emits only when context changes (1: root)
      assert length(change_contexts) == 1
    end

    test "only_changes emits when namespace is added" do
      xml = ~s(<root><child xmlns="http://example.org"/></root>)

      events =
        FnXML.Parser.parse(xml) |> Namespaces.track(only_changes: true) |> Enum.to_list()

      contexts = Enum.filter(events, &Namespaces.ns_context?/1)

      # Only child has a different context (root has no declarations, same as initial)
      assert length(contexts) == 1

      # Verify the context is for the child element (has default namespace)
      [ctx_event] = contexts
      ctx = Namespaces.extract_context(ctx_event)
      assert FnXML.Namespaces.Context.default_namespace(ctx) == "http://example.org"
    end

    test "only_changes emits for root when it has declarations" do
      xml = ~s(<root xmlns="http://root.org"><child xmlns="http://child.org"/></root>)

      events =
        FnXML.Parser.parse(xml) |> Namespaces.track(only_changes: true) |> Enum.to_list()

      contexts = Enum.filter(events, &Namespaces.ns_context?/1)

      # Both root and child have namespace changes
      assert length(contexts) == 2
    end

    test "strip_declarations option removes xmlns attrs" do
      xml = ~s(<root xmlns="http://example.org" id="1"/>)

      events = FnXML.Parser.parse(xml) |> Namespaces.track(strip_declarations: true) |> Enum.to_list()

      # Find start element
      {:start_element, "root", attrs, _, _, _} =
        Enum.find(events, &match?({:start_element, _, _, _, _, _}, &1))

      # Should not have xmlns attribute
      assert not Enum.any?(attrs, fn {name, _} -> name == "xmlns" end)
      # Should still have id attribute
      assert {"id", "1"} in attrs
    end

    test "context event has location information" do
      xml = ~s(<root/>)
      events = FnXML.Parser.parse(xml) |> Namespaces.track() |> Enum.to_list()

      ctx_event = Enum.find(events, &Namespaces.ns_context?/1)

      assert {:ns_context, _ctx, line, ls, pos} = ctx_event
      assert is_integer(line)
      assert is_integer(ls)
      assert is_integer(pos)
    end
  end

  # ==========================================================================
  # Context event helpers
  # ==========================================================================

  describe "ns_context?/1" do
    test "returns true for context events with location" do
      ctx = Namespaces.new_context()
      assert Namespaces.ns_context?({:ns_context, ctx, 1, 0, 0}) == true
    end

    test "returns true for context events without location" do
      ctx = Namespaces.new_context()
      assert Namespaces.ns_context?({:ns_context, ctx}) == true
    end

    test "returns false for other events" do
      assert Namespaces.ns_context?({:start_element, "tag", [], 1, 0, 0}) == false
      assert Namespaces.ns_context?(:other) == false
    end
  end

  describe "extract_context/1" do
    test "extracts context from event with location" do
      ctx = Namespaces.new_context()
      assert Namespaces.extract_context({:ns_context, ctx, 1, 0, 0}) == ctx
    end

    test "extracts context from event without location" do
      ctx = Namespaces.new_context()
      assert Namespaces.extract_context({:ns_context, ctx}) == ctx
    end

    test "returns nil for non-context events" do
      assert Namespaces.extract_context({:start_element, "tag", [], 1, 0, 0}) == nil
    end
  end

  describe "find_context/1" do
    test "finds most recent context in event list" do
      xml = ~s(<root xmlns="http://example.org"><child xmlns="http://other.org"/></root>)
      events = FnXML.Parser.parse(xml) |> Namespaces.track() |> Enum.to_list()

      ctx = Namespaces.find_context(events)

      # Should be the child's context (most recent)
      assert FnXML.Namespaces.Context.default_namespace(ctx) == "http://other.org"
    end

    test "returns nil for event list without context" do
      events = [{:start_element, "tag", [], 1, 0, 0}]
      assert Namespaces.find_context(events) == nil
    end
  end
end
