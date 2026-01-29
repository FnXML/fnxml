defmodule FnXML.Legacy.FastExBlkParserTest do
  use ExUnit.Case, async: true

  alias FnXML.Legacy.FastExBlkParser

  describe "parse/1" do
    test "parses simple element" do
      events = FastExBlkParser.parse("<root/>")
      assert [{:start_element, "root", [], nil}, {:end_element, "root"}] = events
    end

    test "parses nested elements" do
      events = FastExBlkParser.parse("<a><b/></a>")

      assert [
               {:start_element, "a", [], nil},
               {:start_element, "b", [], nil},
               {:end_element, "b"},
               {:end_element, "a"}
             ] = events
    end

    test "parses text content" do
      events = FastExBlkParser.parse("<root>hello world</root>")

      assert [
               {:start_element, "root", [], nil},
               {:characters, "hello world", nil},
               {:end_element, "root"}
             ] = events
    end

    test "parses attributes" do
      events = FastExBlkParser.parse(~s(<root id="1" class="main"/>))
      assert [{:start_element, "root", attrs, nil}, {:end_element, "root"}] = events
      assert {"id", "1"} in attrs
      assert {"class", "main"} in attrs
    end
  end

  describe "whitespace handling" do
    test "ignores whitespace between elements" do
      events = FastExBlkParser.parse("<root>  \n  <child/>  \n  </root>")
      # Should have no :space events
      refute Enum.any?(events, &match?({:space, _, _, _, _}, &1))

      assert [
               {:start_element, "root", [], nil},
               {:start_element, "child", [], nil},
               {:end_element, "child"},
               {:end_element, "root"}
             ] = events
    end

    test "preserves whitespace in text content" do
      events = FastExBlkParser.parse("<root>  hello  world  </root>")

      assert [
               {:start_element, "root", [], nil},
               {:characters, "  hello  world  ", nil},
               {:end_element, "root"}
             ] = events
    end

    test "preserves mixed content whitespace" do
      events = FastExBlkParser.parse("<p>Hello <b>world</b>!</p>")

      assert [
               {:start_element, "p", [], nil},
               {:characters, "Hello ", nil},
               {:start_element, "b", [], nil},
               {:characters, "world", nil},
               {:end_element, "b"},
               {:characters, "!", nil},
               {:end_element, "p"}
             ] = events
    end
  end

  describe "prolog" do
    test "parses prolog with version" do
      events = FastExBlkParser.parse(~s(<?xml version="1.0"?><root/>))
      assert [{:prolog, "xml", [{"version", "1.0"}], nil} | _] = events
    end

    test "parses prolog with encoding" do
      events = FastExBlkParser.parse(~s(<?xml version="1.0" encoding="UTF-8"?><root/>))
      assert [{:prolog, "xml", attrs, nil} | _] = events
      assert {"version", "1.0"} in attrs
      assert {"encoding", "UTF-8"} in attrs
    end
  end

  describe "comments" do
    test "parses comments" do
      events = FastExBlkParser.parse("<root><!-- comment --></root>")
      assert Enum.any?(events, &match?({:comment, " comment ", nil}, &1))
    end
  end

  describe "CDATA" do
    test "parses CDATA sections" do
      events = FastExBlkParser.parse("<root><![CDATA[<data>]]></root>")
      assert Enum.any?(events, &match?({:cdata, "<data>", nil}, &1))
    end
  end

  describe "processing instructions" do
    test "parses processing instructions" do
      events = FastExBlkParser.parse("<root><?target data?></root>")
      assert Enum.any?(events, &match?({:processing_instruction, "target", _, nil}, &1))
    end
  end

  describe "DOCTYPE" do
    test "parses DOCTYPE" do
      events = FastExBlkParser.parse("<!DOCTYPE html><root/>")
      assert Enum.any?(events, &match?({:dtd, _, nil}, &1))
    end
  end

  describe "no location tracking" do
    test "all events have nil location" do
      events =
        FastExBlkParser.parse(~s(<?xml version="1.0"?><root id="1">text<!-- comment --></root>))

      for event <- events do
        case event do
          {:start_element, _, _, loc} -> assert loc == nil
          # No location field
          {:end_element, _} -> :ok
          {:characters, _, loc} -> assert loc == nil
          {:comment, _, loc} -> assert loc == nil
          {:prolog, _, _, loc} -> assert loc == nil
          {:processing_instruction, _, _, loc} -> assert loc == nil
          {:dtd, _, loc} -> assert loc == nil
          {:cdata, _, loc} -> assert loc == nil
          {:error, _, _, loc} -> assert loc == nil
          _ -> :ok
        end
      end
    end
  end

  describe "streaming" do
    test "streams from list of chunks" do
      chunks = ["<root>", "<child/>", "</root>"]
      events = FastExBlkParser.stream(chunks) |> Enum.to_list()

      assert Enum.any?(events, &match?({:start_element, "root", _, _}, &1))
      assert Enum.any?(events, &match?({:start_element, "child", _, _}, &1))
    end

    test "handles element spanning chunks" do
      chunks = ["<root attr=\"val", "ue\"/>"]
      events = FastExBlkParser.stream(chunks) |> Enum.to_list()

      assert [{:start_element, "root", [{"attr", "value"}], nil}, {:end_element, "root"}] = events
    end
  end

  describe "comparison with ExBlkParser" do
    test "produces fewer events (no :space events)" do
      xml = "<root>\n  <child/>\n  <child/>\n</root>"

      ex_events = FnXML.Legacy.ExBlkParser.parse(xml)
      fast_events = FastExBlkParser.parse(xml)

      # FastExBlkParser should have fewer events (no :space)
      assert length(fast_events) < length(ex_events)

      # Should have same structure events
      ex_structure = Enum.reject(ex_events, &match?({:space, _, _, _, _}, &1))
      assert length(fast_events) == length(ex_structure)
    end
  end
end
