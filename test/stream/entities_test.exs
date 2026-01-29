defmodule FnXML.Event.Transform.EntitiesTest do
  use ExUnit.Case, async: true

  alias FnXML.Event.Transform.Entities, as: Entities
  alias FnXML.Error

  # Helper to extract text content from parsed XML
  # Token format: {:characters, content, line, ls, pos} (5-tuple from parser)
  defp extract_text(stream) do
    stream
    |> Enum.to_list()
    |> Enum.find_value(fn
      {:characters, content, _line, _ls, _pos} -> content
      {:characters, content, _loc} -> content
      _ -> nil
    end)
  end

  # Helper to extract first attribute value
  # Token format: {:start_element, tag, attrs, line, ls, pos} (6-tuple from parser)
  defp extract_attr(stream, attr_name) do
    stream
    |> Enum.to_list()
    |> Enum.find_value(fn
      {:start_element, _tag, attrs, _line, _ls, _pos} ->
        Enum.find_value(attrs, fn {name, val} -> if name == attr_name, do: val end)

      {:start_element, _tag, attrs, _loc} ->
        Enum.find_value(attrs, fn {name, val} -> if name == attr_name, do: val end)

      _ ->
        nil
    end)
  end

  describe "resolve/2 predefined entities" do
    test "resolves &amp;" do
      result =
        FnXML.Parser.parse("<a>Tom &amp; Jerry</a>")
        |> Entities.resolve()
        |> extract_text()

      assert result == "Tom & Jerry"
    end

    test "resolves &lt; and &gt;" do
      result =
        FnXML.Parser.parse("<a>&lt;tag&gt;</a>")
        |> Entities.resolve()
        |> extract_text()

      assert result == "<tag>"
    end

    test "resolves &quot;" do
      result =
        FnXML.Parser.parse("<a>&quot;quoted&quot;</a>")
        |> Entities.resolve()
        |> extract_text()

      assert result == "\"quoted\""
    end

    test "resolves &apos;" do
      result =
        FnXML.Parser.parse("<a>&apos;apostrophe&apos;</a>")
        |> Entities.resolve()
        |> extract_text()

      assert result == "'apostrophe'"
    end

    test "resolves multiple entities in one text node" do
      result =
        FnXML.Parser.parse("<a>&lt;&amp;&gt;</a>")
        |> Entities.resolve()
        |> extract_text()

      assert result == "<&>"
    end

    test "text without entities unchanged" do
      result =
        FnXML.Parser.parse("<a>plain text</a>")
        |> Entities.resolve()
        |> extract_text()

      assert result == "plain text"
    end

    test "resolves entities mixed with text" do
      result =
        FnXML.Parser.parse("<a>Hello &amp; goodbye &lt;world&gt;</a>")
        |> Entities.resolve()
        |> extract_text()

      assert result == "Hello & goodbye <world>"
    end
  end

  describe "resolve/2 numeric references" do
    test "resolves decimal reference &#60; (less than)" do
      result =
        FnXML.Parser.parse("<a>&#60;</a>")
        |> Entities.resolve()
        |> extract_text()

      assert result == "<"
    end

    test "resolves decimal reference &#62; (greater than)" do
      result =
        FnXML.Parser.parse("<a>&#62;</a>")
        |> Entities.resolve()
        |> extract_text()

      assert result == ">"
    end

    test "resolves hex reference &#x3C; (less than)" do
      result =
        FnXML.Parser.parse("<a>&#x3C;</a>")
        |> Entities.resolve()
        |> extract_text()

      assert result == "<"
    end

    test "resolves lowercase hex &#x3c;" do
      result =
        FnXML.Parser.parse("<a>&#x3c;</a>")
        |> Entities.resolve()
        |> extract_text()

      assert result == "<"
    end

    test "resolves uppercase hex &#x3E;" do
      result =
        FnXML.Parser.parse("<a>&#x3E;</a>")
        |> Entities.resolve()
        |> extract_text()

      assert result == ">"
    end

    test "resolves unicode decimal &#8364; (euro sign)" do
      result =
        FnXML.Parser.parse("<a>&#8364;</a>")
        |> Entities.resolve()
        |> extract_text()

      assert result == "€"
    end

    test "resolves unicode hex &#x20AC; (euro sign)" do
      result =
        FnXML.Parser.parse("<a>&#x20AC;</a>")
        |> Entities.resolve()
        |> extract_text()

      assert result == "€"
    end

    test "resolves unicode &#x1F600; (emoji)" do
      result =
        FnXML.Parser.parse("<a>&#x1F600;</a>")
        |> Entities.resolve()
        |> extract_text()

      assert result == "😀"
    end

    test "resolves multiple numeric references" do
      result =
        FnXML.Parser.parse("<a>&#60;&#62;&#38;</a>")
        |> Entities.resolve()
        |> extract_text()

      assert result == "<>&"
    end
  end

  describe "resolve/2 in attributes" do
    test "resolves &amp; in attribute value" do
      result =
        FnXML.Parser.parse(~s(<a href="foo&amp;bar"/>))
        |> Entities.resolve()
        |> extract_attr("href")

      assert result == "foo&bar"
    end

    test "resolves &quot; in attribute value" do
      result =
        FnXML.Parser.parse(~s(<a title="say &quot;hello&quot;"/>))
        |> Entities.resolve()
        |> extract_attr("title")

      assert result == "say \"hello\""
    end

    test "resolves numeric reference in attribute" do
      result =
        FnXML.Parser.parse(~s(<a data="&#60;value&#62;"/>))
        |> Entities.resolve()
        |> extract_attr("data")

      assert result == "<value>"
    end

    test "resolves multiple attributes" do
      tokens =
        FnXML.Parser.parse(~s(<a x="a&amp;b" y="c&lt;d"/>))
        |> Entities.resolve()
        |> Enum.to_list()

      open =
        Enum.find(tokens, fn
          {:start_element, _, _, _, _, _} -> true
          {:start_element, _, _, _} -> true
          _ -> false
        end)

      {_, _tag, attrs, _, _, _} = open

      assert Enum.find_value(attrs, fn {n, v} -> if n == "x", do: v end) == "a&b"
      assert Enum.find_value(attrs, fn {n, v} -> if n == "y", do: v end) == "c<d"
    end
  end

  describe "resolve/2 custom entities" do
    test "resolves custom named entity" do
      result =
        FnXML.Parser.parse("<a>&copy;</a>")
        |> Entities.resolve(entities: %{"copy" => "©"})
        |> extract_text()

      assert result == "©"
    end

    test "custom entity overrides predefined" do
      result =
        FnXML.Parser.parse("<a>&amp;</a>")
        |> Entities.resolve(entities: %{"amp" => "AMPERSAND"})
        |> extract_text()

      assert result == "AMPERSAND"
    end

    test "mix of custom and predefined" do
      result =
        FnXML.Parser.parse("<a>&copy; &amp; &reg;</a>")
        |> Entities.resolve(entities: %{"copy" => "©", "reg" => "®"})
        |> extract_text()

      assert result == "© & ®"
    end
  end

  describe "resolve/2 on_unknown option" do
    test "raises by default on unknown entity" do
      assert_raise Error, ~r/Unknown entity.*&unknown;/, fn ->
        FnXML.Parser.parse("<a>&unknown;</a>")
        |> Entities.resolve()
        |> Enum.to_list()
      end
    end

    test "on_unknown: :emit returns error token" do
      tokens =
        FnXML.Parser.parse("<a>&unknown;</a>")
        |> Entities.resolve(on_unknown: :emit)
        |> Enum.to_list()

      assert Enum.any?(tokens, fn
               {:error, %Error{type: :unknown_entity}} -> true
               _ -> false
             end)
    end

    test "on_unknown: :keep preserves entity reference" do
      result =
        FnXML.Parser.parse("<a>&unknown;</a>")
        |> Entities.resolve(on_unknown: :keep)
        |> extract_text()

      assert result == "&unknown;"
    end

    test "on_unknown: :remove removes entity reference" do
      result =
        FnXML.Parser.parse("<a>before&unknown;after</a>")
        |> Entities.resolve(on_unknown: :remove)
        |> extract_text()

      assert result == "beforeafter"
    end
  end

  describe "resolve/2 error handling" do
    test "invalid decimal reference" do
      assert_raise Error, ~r/Invalid decimal/, fn ->
        FnXML.Parser.parse("<a>&#abc;</a>")
        |> Entities.resolve()
        |> Enum.to_list()
      end
    end

    test "invalid hex reference" do
      assert_raise Error, ~r/Invalid hex/, fn ->
        FnXML.Parser.parse("<a>&#xGHI;</a>")
        |> Entities.resolve()
        |> Enum.to_list()
      end
    end

    test "invalid unicode codepoint (too large)" do
      assert_raise Error, ~r/Invalid Unicode codepoint/, fn ->
        FnXML.Parser.parse("<a>&#xFFFFFFFF;</a>")
        |> Entities.resolve()
        |> Enum.to_list()
      end
    end
  end

  describe "resolve/2 passthrough" do
    test "open and close tags pass through" do
      tokens =
        FnXML.Parser.parse("<root><child/></root>")
        |> Entities.resolve()
        |> Enum.to_list()

      # 6-tuple format: {:start_element, tag, attrs, line, ls, pos}
      assert Enum.count(tokens, &match?({:start_element, _, _, _, _, _}, &1)) == 2
      # Close tags can be {:end_element, tag} or {:end_element, tag, line, ls, pos}
      assert Enum.count(tokens, fn
               {:end_element, _} -> true
               {:end_element, _, _, _, _} -> true
               _ -> false
             end) == 2
    end

    test "comments pass through unchanged" do
      tokens =
        FnXML.Parser.parse("<a><!-- &amp; --></a>")
        |> Entities.resolve()
        |> Enum.to_list()

      # 5-tuple format: {:comment, content, line, ls, pos}
      comment = Enum.find(tokens, &match?({:comment, _, _, _, _}, &1))
      assert comment != nil
      {:comment, content, _, _, _} = comment
      # Comment content should NOT have entities resolved
      assert content =~ "&amp;"
    end

    test "prolog passes through" do
      tokens =
        FnXML.Parser.parse(~s(<?xml version="1.0"?><root/>))
        |> Entities.resolve()
        |> Enum.to_list()

      # 6-tuple format: {:prolog, "xml", attrs, line, ls, pos}
      assert Enum.any?(tokens, &match?({:prolog, _, _, _, _, _}, &1))
    end
  end

  describe "resolve_text/3" do
    test "returns ok tuple on success" do
      assert {:ok, "Tom & Jerry"} = Entities.resolve_text("Tom &amp; Jerry")
    end

    test "returns error tuple on unknown entity with raise" do
      assert {:error, %Error{type: :unknown_entity}} = Entities.resolve_text("&unknown;")
    end

    test "handles empty string" do
      assert {:ok, ""} = Entities.resolve_text("")
    end
  end

  describe "encode/1" do
    test "encodes ampersand" do
      assert Entities.encode("Tom & Jerry") == "Tom &amp; Jerry"
    end

    test "encodes less than" do
      assert Entities.encode("<tag>") == "&lt;tag&gt;"
    end

    test "encodes all special chars" do
      assert Entities.encode("<&>") == "&lt;&amp;&gt;"
    end

    test "plain text unchanged" do
      assert Entities.encode("hello world") == "hello world"
    end
  end

  describe "encode_attr/1" do
    test "encodes quotes" do
      assert Entities.encode_attr("say \"hello\"") == "say &quot;hello&quot;"
    end

    test "encodes all special chars including quotes" do
      assert Entities.encode_attr("<&\">") == "&lt;&amp;&quot;&gt;"
    end
  end

  describe "roundtrip" do
    test "decode then encode preserves special chars" do
      original = "Tom &amp; Jerry &lt;friends&gt;"

      decoded =
        FnXML.Parser.parse("<a>#{original}</a>")
        |> Entities.resolve()
        |> extract_text()

      assert decoded == "Tom & Jerry <friends>"
      assert Entities.encode(decoded) == original
    end
  end
end
