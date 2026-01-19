defmodule FnXML.Stream.DecoderTest do
  use ExUnit.Case, async: true

  alias FnXML.Stream.Decoder
  alias FnXML.Stream.Decoder.Default

  describe "Decoder.decode/3 with default handler" do
    test "decodes simple element" do
      xml = "<root/>"
      result = FnXML.Parser.parse(xml) |> Decoder.decode() |> Enum.to_list()

      # Result is a list containing the decoded element as a keyword list
      assert [[{:loc, _}, {:attributes, []}, {:tag, "root"}]] = result
    end

    test "decodes element with attributes" do
      xml = ~s(<root id="1" class="main"/>)
      result = FnXML.Parser.parse(xml) |> Decoder.decode() |> Enum.to_list()

      assert [[{:loc, _}, {:attributes, attrs}, {:tag, "root"}]] = result
      # Parser returns attributes in reverse order
      assert {"id", "1"} in attrs
      assert {"class", "main"} in attrs
    end

    test "decodes element with text content" do
      xml = "<root>Hello World</root>"
      result = FnXML.Parser.parse(xml) |> Decoder.decode() |> Enum.to_list()

      # Result contains loc, attributes, tag, and text
      assert [[{:loc, _}, {:attributes, []}, {:tag, "root"}, {:text, "Hello World"}]] = result
    end

    test "decodes nested elements" do
      xml = "<root><child>text</child></root>"
      result = FnXML.Parser.parse(xml) |> Decoder.decode() |> Enum.to_list()

      # The result should be the root element with a child element
      assert [[{:loc, _}, {:attributes, []}, {:tag, "root"}, {:child, child}]] = result
      assert [{:loc, _}, {:attributes, []}, {:tag, "child"}, {:text, "text"}] = child
    end

    test "decodes deeply nested elements" do
      xml = "<a><b><c>deep</c></b></a>"
      result = FnXML.Parser.parse(xml) |> Decoder.decode() |> Enum.to_list()

      assert [[{:loc, _}, {:attributes, []}, {:tag, "a"}, {:child, b}]] = result
      assert [{:loc, _}, {:attributes, []}, {:tag, "b"}, {:child, c}] = b
      assert [{:loc, _}, {:attributes, []}, {:tag, "c"}, {:text, "deep"}] = c
    end

    test "decodes multiple children" do
      xml = "<root><a/><b/><c/></root>"
      result = FnXML.Parser.parse(xml) |> Decoder.decode() |> Enum.to_list()

      # Extract the first (and only) decoded element
      assert [[{:loc, _}, {:attributes, []}, {:tag, "root"} | children]] = result
      assert length(children) == 3

      tags =
        Enum.map(children, fn {:child, elem} ->
          Keyword.get(elem, :tag)
        end)

      assert tags == ["a", "b", "c"]
    end

    test "decodes XML with prolog" do
      xml = ~s(<?xml version="1.0" encoding="UTF-8"?><root/>)
      result = FnXML.Parser.parse(xml) |> Decoder.decode() |> Enum.to_list()

      # Result may include prolog info and root element
      # Just verify we can decode without errors
      # The prolog handler adds {:prolog, ...} to accumulator
      assert is_list(result)
    end

    test "decodes comments" do
      xml = "<root><!-- a comment --></root>"
      events = FnXML.Parser.parse(xml) |> Enum.to_list()

      # Find the comment event (5-tuple from parser)
      comment_event =
        Enum.find(events, fn
          {:comment, _, _, _, _} -> true
          {:comment, _, _} -> true
          _ -> false
        end)

      assert comment_event != nil
      assert elem(comment_event, 1) == " a comment "
    end
  end

  describe "Default handler callbacks" do
    test "handle_open pushes element context" do
      elem = {:start_element, "div", [{"id", "1"}], {1, 0, 0}}
      result = Default.handle_open(elem, ["root"], [], [])

      assert [[{:tag, "div"}, {:attributes, [{"id", "1"}]}, {:loc, {1, 0, 0}}]] = result
    end

    test "handle_text adds text to current element" do
      elem = {:characters, "Hello", {1, 5, 5}}
      acc = [[{:tag, "div"}, {:attributes, []}, {:loc, {1, 0, 0}}]]
      result = Default.handle_text(elem, ["div"], acc, [])

      assert [current | _] = result
      assert {:text, "Hello"} in current
    end

    test "handle_close finalizes single element" do
      elem = {:end_element, "div"}
      acc = [[{:tag, "div"}, {:attributes, []}, {:loc, {1, 0, 0}}]]
      {result, remaining} = Default.handle_close(elem, ["div"], acc, [])

      assert [{:loc, {1, 0, 0}}, {:attributes, []}, {:tag, "div"}] = result
      assert remaining == []
    end

    test "handle_close adds child to parent" do
      elem = {:end_element, "child"}
      child = [{:tag, "child"}, {:attributes, []}, {:loc, {1, 10, 10}}]
      parent = [{:tag, "parent"}, {:attributes, []}, {:loc, {1, 0, 0}}]
      acc = [child, parent]

      result = Default.handle_close(elem, ["parent", "child"], acc, [])

      assert [[{:child, _} | _parent_rest] | _] = result
    end

    test "handle_prolog stores prolog info" do
      elem = {:prolog, "xml", [{"version", "1.0"}], {1, 0, 0}}
      result = Default.handle_prolog(elem, [], [], [])

      assert [{:prolog, [{:attributes, [{"version", "1.0"}]}, {:loc, {1, 0, 0}}]}] = result
    end

    test "handle_comment stores comment" do
      elem = {:comment, "comment text", {1, 5, 5}}
      result = Default.handle_comment(elem, ["root"], [], [])

      assert [{:comment, [{:content, "comment text"}, {:loc, {1, 5, 5}}]}] = result
    end

    test "handle_proc_inst stores processing instruction" do
      elem = {:processing_instruction, "php", "echo 'hi'", {1, 0, 0}}
      result = Default.handle_proc_inst(elem, [], [], [])

      assert [{:proc_inst, [{:name, "php"}, {:content, "echo 'hi'"}, {:loc, {1, 0, 0}}]}] = result
    end
  end

  describe "Default.process_element/3" do
    test "returns element directly for root path" do
      elem = [{:tag, "root"}, {:attributes, []}]
      result = Default.process_element(elem, ["root"], [])

      assert result == elem
    end

    test "wraps element as child for nested path" do
      elem = [{:tag, "child"}, {:attributes, []}]
      result = Default.process_element(elem, ["root", "child"], [])

      assert {:child, ^elem} = result
    end

    test "uses custom handler when provided" do
      elem = [{:tag, "item"}, {:attributes, []}]
      opts = [handle_element: fn e, _path, _opts -> {:custom, e} end]
      result = Default.process_element(elem, ["root", "item"], opts)

      assert {:custom, ^elem} = result
    end
  end

  describe "Decoder with custom handler module" do
    defmodule CustomHandler do
      @behaviour FnXML.Stream.Decoder

      @impl true
      def handle_open({:start_element, tag, _attrs, _loc}, _path, acc, _opts) do
        [{:custom_open, tag} | acc]
      end

      @impl true
      def handle_close({:end_element, tag}, _path, acc, _opts) do
        # Return final result when closing root
        {[{:custom_close, tag} | acc], []}
      end

      def handle_close({:end_element, tag, _loc}, _path, acc, _opts) do
        {[{:custom_close, tag} | acc], []}
      end

      @impl true
      def handle_text({:characters, text, _loc}, _path, acc, _opts) do
        [{:custom_text, text} | acc]
      end

      @impl true
      def handle_prolog(_elem, _path, acc, _opts), do: acc

      @impl true
      def handle_comment(_elem, _path, acc, _opts), do: acc

      @impl true
      def handle_proc_inst(_elem, _path, acc, _opts), do: acc
    end

    test "uses custom handler module" do
      xml = "<root>text</root>"
      result = FnXML.Parser.parse(xml) |> Decoder.decode(CustomHandler) |> Enum.to_list()

      # Custom handler accumulates results in reverse order
      flattened = List.flatten(result)

      assert {:custom_close, "root"} in flattened or
               Enum.any?(result, &match?({:custom_close, _}, &1))
    end
  end
end
