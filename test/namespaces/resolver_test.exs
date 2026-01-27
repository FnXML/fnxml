defmodule FnXML.Namespaces.ResolverTest do
  use ExUnit.Case, async: true

  alias FnXML.Namespaces.Resolver

  describe "resolve/2 basic namespace expansion" do
    test "expands default and prefixed namespaces" do
      xml = ~s(<root xmlns="http://default" xmlns:ns="http://ns"><ns:child/></root>)
      events = FnXML.Parser.parse(xml) |> Resolver.resolve() |> Enum.to_list()

      assert Enum.any?(
               events,
               &match?({:start_element, {"http://default", "root"}, _, _, _, _}, &1)
             )

      assert Enum.any?(events, &match?({:start_element, {"http://ns", "child"}, _, _, _, _}, &1))
    end

    test "element without namespace has nil URI" do
      events = FnXML.Parser.parse("<root/>") |> Resolver.resolve() |> Enum.to_list()
      assert Enum.any?(events, &match?({:start_element, {nil, "root"}, _, _, _, _}, &1))
    end

    test "expands close tags" do
      xml = ~s(<ns:root xmlns:ns="http://ns"/>)
      events = FnXML.Parser.parse(xml) |> Resolver.resolve() |> Enum.to_list()

      assert Enum.any?(events, fn
               {:end_element, {"http://ns", "root"}, _, _, _} -> true
               {:end_element, {"http://ns", "root"}} -> true
               _ -> false
             end)
    end
  end

  describe "resolve/2 attribute namespace expansion" do
    test "expands prefixed attributes, unprefixed have nil namespace" do
      xml = ~s(<root xmlns:ns="http://ns" ns:attr="1" id="2"/>)
      events = FnXML.Parser.parse(xml) |> Resolver.resolve() |> Enum.to_list()

      {:start_element, _, attrs, _, _, _} =
        Enum.find(events, &match?({:start_element, _, _, _, _, _}, &1))

      assert Enum.any?(attrs, &match?({"http://ns", "attr", "1"}, &1))
      assert Enum.any?(attrs, &match?({nil, "id", "2"}, &1))
    end
  end

  describe "resolve/2 options" do
    test "strip_declarations removes xmlns attributes" do
      xml = ~s(<root xmlns="http://x" xmlns:ns="http://ns" id="1"/>)

      events =
        FnXML.Parser.parse(xml) |> Resolver.resolve(strip_declarations: true) |> Enum.to_list()

      {:start_element, _, attrs, _, _, _} =
        Enum.find(events, &match?({:start_element, _, _, _, _, _}, &1))

      assert length(attrs) == 1
      assert Enum.any?(attrs, &match?({nil, "id", "1"}, &1))
    end

    test "include_prefix adds prefix to expanded names" do
      xml = ~s(<ns:root xmlns:ns="http://ns" ns:attr="1"/>)
      events = FnXML.Parser.parse(xml) |> Resolver.resolve(include_prefix: true) |> Enum.to_list()

      assert Enum.any?(
               events,
               &match?({:start_element, {"http://ns", "root", "ns"}, _, _, _, _}, &1)
             )

      {:start_element, _, attrs, _, _, _} =
        Enum.find(events, &match?({:start_element, _, _, _, _, _}, &1))

      assert Enum.any?(attrs, &match?({"http://ns", "attr", "ns", "1"}, &1))
    end
  end

  describe "resolve/2 scoping" do
    test "default namespace resets in nested element" do
      xml = ~s(<root xmlns="http://outer"><child xmlns=""><inner/></child></root>)
      events = FnXML.Parser.parse(xml) |> Resolver.resolve() |> Enum.to_list()

      assert Enum.any?(events, &match?({:start_element, {nil, "inner"}, _, _, _, _}, &1))
    end

    test "prefix binding is scoped to element" do
      xml =
        ~s(<root xmlns:ns="http://outer"><child xmlns:ns="http://inner"><ns:x/></child><ns:y/></root>)

      events = FnXML.Parser.parse(xml) |> Resolver.resolve() |> Enum.to_list()

      assert Enum.any?(events, &match?({:start_element, {"http://inner", "x"}, _, _, _, _}, &1))
      assert Enum.any?(events, &match?({:start_element, {"http://outer", "y"}, _, _, _, _}, &1))
    end
  end

  describe "resolve/2 passthrough" do
    test "passes through non-element events unchanged" do
      events =
        FnXML.Parser.parse("<root>text<!-- comment --></root>")
        |> Resolver.resolve()
        |> Enum.to_list()

      assert Enum.any?(events, &match?({:characters, "text", _, _, _}, &1))
      assert Enum.any?(events, &match?({:comment, " comment ", _, _, _}, &1))
    end

    test "passes through prolog, error, and DTD events" do
      events1 =
        FnXML.Parser.parse(~s(<?xml version="1.0"?><root/>))
        |> Resolver.resolve()
        |> Enum.to_list()

      assert Enum.any?(events1, &match?({:prolog, "xml", _, _, _, _}, &1))

      # Test error passthrough with manually constructed stream (parser doesn't emit errors for malformed XML)
      error_stream = [
        {:start_document, nil},
        {:error, :syntax, "test error", 1, 0, 5},
        {:end_document, nil}
      ]

      events2 = error_stream |> Resolver.resolve() |> Enum.to_list()
      assert Enum.any?(events2, &match?({:error, _, _, _, _, _}, &1))

      events3 =
        FnXML.Parser.parse("<!DOCTYPE html><root/>") |> Resolver.resolve() |> Enum.to_list()

      assert Enum.any?(events3, &match?({:dtd, _, _, _, _}, &1))
    end
  end

  describe "resolve_event/3 direct calls" do
    test "handles dtd events with and without loc" do
      ctx = FnXML.Namespaces.Context.new()

      {[result1], _} = Resolver.resolve_event({:dtd, "html", {1, 0, 0}}, ctx, [])
      assert result1 == {:dtd, "html", {1, 0, 0}}

      {[result2], _} = Resolver.resolve_event({:dtd, "html"}, ctx, [])
      assert result2 == {:dtd, "html"}
    end
  end
end
