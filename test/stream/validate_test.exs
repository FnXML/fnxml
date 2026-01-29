defmodule FnXML.ValidateTest do
  use ExUnit.Case, async: true

  alias FnXML.Event.Validate

  describe "well_formed/2" do
    test "valid nested tags pass" do
      tokens =
        FnXML.Parser.parse("<a><b></b></a>")
        |> Validate.well_formed()
        |> Enum.to_list()

      assert length(tokens) == 6
      # Parser outputs 6-tuple: {:start_element, tag, attrs, line, ls, pos}
      assert Enum.any?(tokens, &match?({:start_element, _, _, _, _, _}, &1))

      assert Enum.any?(tokens, fn
               {:end_element, _} -> true
               {:end_element, _, _} -> true
               {:end_element, _, _, _, _} -> true
               _ -> false
             end)
    end

    test "mismatched tags raise error with and without loc" do
      assert_raise FnXML.Error, ~r/Expected.*<\/a>.*got.*<\/b>/i, fn ->
        FnXML.Parser.parse("<a></b>")
        |> Validate.well_formed()
        |> Enum.to_list()
      end

      # With explicit loc in stream
      stream = [
        {:start_document, nil},
        {:start_element, "a", [], 1, 0, 0},
        {:end_element, "b", 1, 0, 5},
        {:end_document, nil}
      ]

      assert_raise FnXML.Error, ~r/Expected.*<\/a>.*got.*<\/b>/i, fn ->
        stream |> Validate.well_formed() |> Enum.to_list()
      end
    end

    test "unexpected close tag raises error with and without loc" do
      assert_raise FnXML.Error, ~r/unexpected.*close/i, fn ->
        FnXML.Parser.parse("</a>")
        |> Validate.well_formed()
        |> Enum.to_list()
      end

      # With explicit loc
      stream = [
        {:start_document, nil},
        {:end_element, "a", 1, 0, 5},
        {:end_document, nil}
      ]

      assert_raise FnXML.Error, ~r/unexpected.*close/i, fn ->
        stream |> Validate.well_formed() |> Enum.to_list()
      end
    end

    test "self-closing tags handled correctly" do
      tokens =
        FnXML.Parser.parse("<a><b/></a>")
        |> Validate.well_formed()
        |> Enum.to_list()

      assert length(tokens) >= 4
    end

    test "deeply nested valid structure passes" do
      tokens =
        FnXML.Parser.parse("<a><b><c><d></d></c></b></a>")
        |> Validate.well_formed()
        |> Enum.to_list()

      assert length(tokens) == 10
    end

    test "on_error: :emit returns error tuple" do
      tokens =
        FnXML.Parser.parse("<a></b>")
        |> Validate.well_formed(on_error: :emit)
        |> Enum.to_list()

      assert Enum.any?(tokens, fn
               {:error, %FnXML.Error{}} -> true
               _ -> false
             end)
    end

    test "on_error: :skip passes invalid elements through" do
      # Unexpected close tag
      result1 =
        [{:start_document, nil}, {:end_element, "a"}, {:end_document, nil}]
        |> Validate.well_formed(on_error: :skip)
        |> Enum.to_list()

      assert Enum.any?(result1, &match?({:end_element, "a"}, &1))

      # Mismatched close tag
      result2 =
        [
          {:start_document, nil},
          {:start_element, "a", [], {1, 0, 0}},
          {:end_element, "b"},
          {:end_document, nil}
        ]
        |> Validate.well_formed(on_error: :skip)
        |> Enum.to_list()

      assert Enum.any?(result2, &match?({:start_element, "a", _, _}, &1)) or
               Enum.any?(result2, &match?({:start_element, "a", _, _, _, _}, &1))

      assert Enum.any?(result2, &match?({:end_element, "b"}, &1))
    end

    test "text, comments, and prolog pass through" do
      tokens =
        FnXML.Parser.parse(~s(<?xml version="1.0"?><root>text<!-- comment --></root>))
        |> Validate.well_formed()
        |> Enum.to_list()

      # Parser outputs 5-tuple for characters/comments, 6-tuple for prolog
      assert Enum.any?(tokens, &match?({:characters, _, _, _, _}, &1))
      assert Enum.any?(tokens, &match?({:comment, _, _, _, _}, &1))
      assert Enum.any?(tokens, &match?({:prolog, _, _, _, _, _}, &1))
    end
  end

  describe "attributes/2" do
    test "unique attributes pass" do
      tokens =
        FnXML.Parser.parse(~s(<a x="1" y="2"/>))
        |> Validate.attributes()
        |> Enum.to_list()

      assert Enum.any?(tokens, &match?({:start_element, _, _, _, _, _}, &1))
    end

    test "duplicate attributes raise error" do
      assert_raise FnXML.Error, ~r/[Dd]uplicate.*x/i, fn ->
        FnXML.Parser.parse(~s(<a x="1" x="2"/>))
        |> Validate.attributes()
        |> Enum.to_list()
      end
    end

    test "on_error: :emit returns error tuple" do
      tokens =
        FnXML.Parser.parse(~s(<a x="1" x="2"/>))
        |> Validate.attributes(on_error: :emit)
        |> Enum.to_list()

      assert Enum.any?(tokens, fn
               {:error, %FnXML.Error{type: :duplicate_attr}} -> true
               _ -> false
             end)
    end

    test "close and text elements pass through unchanged" do
      tokens =
        FnXML.Parser.parse("<a>text</a>")
        |> Validate.attributes()
        |> Enum.to_list()

      assert Enum.any?(tokens, &match?({:characters, _, _, _, _}, &1))

      assert Enum.any?(tokens, fn
               {:end_element, _} -> true
               {:end_element, _, _} -> true
               {:end_element, _, _, _, _} -> true
               _ -> false
             end)
    end
  end

  describe "namespaces/2" do
    test "declared namespace passes" do
      tokens =
        FnXML.Parser.parse(~s(<root xmlns:ns="http://example.com"><ns:child/></root>))
        |> Validate.namespaces()
        |> Enum.to_list()

      assert length(tokens) >= 4
    end

    test "undeclared prefix raises error" do
      assert_raise FnXML.Error, ~r/[Uu]ndeclared.*ns/i, fn ->
        FnXML.Parser.parse("<ns:root/>")
        |> Validate.namespaces()
        |> Enum.to_list()
      end
    end

    test "xml and xmlns prefixes always valid" do
      tokens1 =
        FnXML.Parser.parse(~s(<root xml:lang="en"/>))
        |> Validate.namespaces()
        |> Enum.to_list()

      assert Enum.any?(tokens1, &match?({:start_element, _, _, _, _, _}, &1))

      tokens2 =
        FnXML.Parser.parse(~s(<root xmlns:foo="http://example.com"/>))
        |> Validate.namespaces()
        |> Enum.to_list()

      assert Enum.any?(tokens2, &match?({:start_element, _, _, _, _, _}, &1))
    end

    test "default namespace works" do
      tokens =
        FnXML.Parser.parse(~s(<root xmlns="http://example.com"><child/></root>))
        |> Validate.namespaces()
        |> Enum.to_list()

      assert length(tokens) >= 4
    end

    test "namespace scope is local to element" do
      tokens =
        FnXML.Parser.parse(~s(<root><inner xmlns:ns="http://x"><ns:child/></inner></root>))
        |> Validate.namespaces()
        |> Enum.to_list()

      assert length(tokens) >= 6
    end

    test "on_error: :emit returns error tuple" do
      tokens =
        FnXML.Parser.parse("<ns:root/>")
        |> Validate.namespaces(on_error: :emit)
        |> Enum.to_list()

      assert Enum.any?(tokens, fn
               {:error, %FnXML.Error{type: :undeclared_namespace}} -> true
               _ -> false
             end)
    end

    test "attribute namespace prefix validated" do
      # Undeclared prefix in attribute raises error
      assert_raise FnXML.Error, ~r/[Uu]ndeclared.*ns/i, fn ->
        FnXML.Parser.parse(~s(<root ns:attr="value"/>))
        |> Validate.namespaces()
        |> Enum.to_list()
      end

      # Declared attribute prefix passes
      tokens =
        FnXML.Parser.parse(~s(<root xmlns:ns="http://x" ns:attr="value"/>))
        |> Validate.namespaces()
        |> Enum.to_list()

      assert Enum.any?(tokens, &match?({:start_element, _, _, _, _, _}, &1))
    end

    test "handles end_element with empty stack" do
      # With and without loc - both should pass through
      stream1 = [{:start_document, nil}, {:end_element, "root"}, {:end_document, nil}]
      result1 = Validate.namespaces(stream1) |> Enum.to_list()
      assert length(result1) >= 1

      stream2 = [{:start_document, nil}, {:end_element, "root", {1, 0, 10}}, {:end_document, nil}]
      result2 = Validate.namespaces(stream2) |> Enum.to_list()
      assert length(result2) >= 1
    end
  end

  describe "all/2" do
    test "applies all validators by default" do
      tokens =
        FnXML.Parser.parse(~s(<root xmlns:ns="http://x"><ns:child id="1"/></root>))
        |> Validate.all()
        |> Enum.to_list()

      assert length(tokens) >= 4
    end

    test "applies selected validators" do
      tokens =
        FnXML.Parser.parse("<a><b></b></a>")
        |> Validate.all(validators: [:structure])
        |> Enum.to_list()

      assert length(tokens) == 6
    end

    test "catches structure, attribute, and namespace errors" do
      # Structure error
      assert_raise FnXML.Error, fn ->
        FnXML.Parser.parse("<a></b>")
        |> Validate.all(validators: [:structure])
        |> Enum.to_list()
      end

      # Attribute error
      assert_raise FnXML.Error, fn ->
        FnXML.Parser.parse(~s(<a x="1" x="2"/>))
        |> Validate.all(validators: [:attributes])
        |> Enum.to_list()
      end

      # Namespace error
      assert_raise FnXML.Error, fn ->
        FnXML.Parser.parse("<ns:root/>")
        |> Validate.all(validators: [:namespaces])
        |> Enum.to_list()
      end
    end
  end

  describe "integration with full pipeline" do
    test "validates complex valid XML" do
      xml = """
      <?xml version="1.0"?>
      <root xmlns:ns="http://example.com">
        <ns:item id="1" name="test">
          <ns:child/>
        </ns:item>
      </root>
      """

      tokens =
        FnXML.Parser.parse(xml)
        |> Validate.well_formed()
        |> Validate.attributes()
        |> Validate.namespaces()
        |> Enum.to_list()

      assert Enum.any?(tokens, &match?({:prolog, _, _, _, _, _}, &1))
      assert Enum.count(tokens, &match?({:start_element, _, _, _, _, _}, &1)) >= 2
    end
  end
end
