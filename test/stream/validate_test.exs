defmodule FnXML.Stream.ValidateTest do
  use ExUnit.Case, async: true

  alias FnXML.Stream.Validate

  # Helper to match open/close tags in new format
  defp is_open?({:open, _, _, _}), do: true
  defp is_open?(_), do: false

  defp is_close?({:close, _}), do: true
  defp is_close?({:close, _, _}), do: true
  defp is_close?(_), do: false

  defp is_text?({:text, _, _}), do: true
  defp is_text?(_), do: false

  defp is_comment?({:comment, _, _}), do: true
  defp is_comment?(_), do: false

  defp is_prolog?({:prolog, _, _, _}), do: true
  defp is_prolog?(_), do: false

  describe "well_formed/2" do
    test "valid nested tags pass" do
      tokens =
        FnXML.Parser.parse("<a><b></b></a>")
        |> Validate.well_formed()
        |> Enum.to_list()

      # +2 for doc_start and doc_end events
      assert length(tokens) == 6
      assert Enum.any?(tokens, &is_open?/1)
      assert Enum.any?(tokens, &is_close?/1)
    end

    test "mismatched tags raise error" do
      assert_raise FnXML.Error, ~r/Expected.*<\/a>.*got.*<\/b>/i, fn ->
        FnXML.Parser.parse("<a></b>")
        |> Validate.well_formed()
        |> Enum.to_list()
      end
    end

    test "unexpected close tag raises error" do
      assert_raise FnXML.Error, ~r/unexpected.*close/i, fn ->
        FnXML.Parser.parse("</a>")
        |> Validate.well_formed()
        |> Enum.to_list()
      end
    end

    test "self-closing tags handled correctly" do
      tokens =
        FnXML.Parser.parse("<a><b/></a>")
        |> Validate.well_formed()
        |> Enum.to_list()

      # Self-closing <b/> becomes {:open, [close: true]} + {:close, ...}
      assert length(tokens) >= 4
    end

    test "deeply nested valid structure passes" do
      tokens =
        FnXML.Parser.parse("<a><b><c><d></d></c></b></a>")
        |> Validate.well_formed()
        |> Enum.to_list()

      # +2 for doc_start and doc_end events
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
      tokens =
        FnXML.Parser.parse("<a></b>")
        |> Validate.well_formed(on_error: :skip)
        |> Enum.to_list()

      # Should have all elements, no error
      refute Enum.any?(tokens, &match?({:error, _}, &1))
    end

    test "text and comments pass through" do
      tokens =
        FnXML.Parser.parse("<root>text<!-- comment --></root>")
        |> Validate.well_formed()
        |> Enum.to_list()

      assert Enum.any?(tokens, &is_text?/1)
      assert Enum.any?(tokens, &is_comment?/1)
    end

    test "prolog passes through" do
      tokens =
        FnXML.Parser.parse(~s(<?xml version="1.0"?><root/>))
        |> Validate.well_formed()
        |> Enum.to_list()

      assert Enum.any?(tokens, &is_prolog?/1)
    end
  end

  describe "attributes/2" do
    test "unique attributes pass" do
      tokens =
        FnXML.Parser.parse(~s(<a x="1" y="2"/>))
        |> Validate.attributes()
        |> Enum.to_list()

      assert Enum.any?(tokens, &is_open?/1)
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

      assert Enum.any?(tokens, &is_text?/1)
      assert Enum.any?(tokens, &is_close?/1)
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

    test "xml prefix always valid" do
      tokens =
        FnXML.Parser.parse(~s(<root xml:lang="en"/>))
        |> Validate.namespaces()
        |> Enum.to_list()

      assert Enum.any?(tokens, &is_open?/1)
    end

    test "xmlns prefix always valid" do
      tokens =
        FnXML.Parser.parse(~s(<root xmlns:foo="http://example.com"/>))
        |> Validate.namespaces()
        |> Enum.to_list()

      assert Enum.any?(tokens, &is_open?/1)
    end

    test "default namespace works" do
      tokens =
        FnXML.Parser.parse(~s(<root xmlns="http://example.com"><child/></root>))
        |> Validate.namespaces()
        |> Enum.to_list()

      assert length(tokens) >= 4
    end

    test "namespace scope is local to element" do
      # ns declared in inner, used in inner - OK
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
      assert_raise FnXML.Error, ~r/[Uu]ndeclared.*ns/i, fn ->
        FnXML.Parser.parse(~s(<root ns:attr="value"/>))
        |> Validate.namespaces()
        |> Enum.to_list()
      end
    end

    test "declared attribute prefix passes" do
      tokens =
        FnXML.Parser.parse(~s(<root xmlns:ns="http://x" ns:attr="value"/>))
        |> Validate.namespaces()
        |> Enum.to_list()

      assert Enum.any?(tokens, &is_open?/1)
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

      # +2 for doc_start and doc_end events
      assert length(tokens) == 6
    end

    test "catches structure errors" do
      assert_raise FnXML.Error, fn ->
        FnXML.Parser.parse("<a></b>")
        |> Validate.all(validators: [:structure])
        |> Enum.to_list()
      end
    end

    test "catches attribute errors" do
      assert_raise FnXML.Error, fn ->
        FnXML.Parser.parse(~s(<a x="1" x="2"/>))
        |> Validate.all(validators: [:attributes])
        |> Enum.to_list()
      end
    end

    test "catches namespace errors" do
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

      assert Enum.any?(tokens, &is_prolog?/1)
      assert Enum.count(tokens, &is_open?/1) >= 2
    end
  end
end
