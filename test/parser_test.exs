defmodule FnXML.ParserTest do
  use ExUnit.Case

  # These tests are for the NimbleParsec parser (legacy)
  alias FnXML.Parser.NimbleParsec, as: Parser
  doctest FnXML.Parser

  def parse_xml(xml) do
    xml
    |> Parser.parse()
    |> Enum.map(fn x -> x end)
  end

  def filter_loc(tag_list) do
    tag_list
    |> Enum.map(fn {id, list} ->
      {id,
       Enum.filter(list, fn
         {k, _v} -> k != :loc
         _ -> true
       end)}
    end)
  end

  describe "document prolog" do
    test "basic prolog" do
      {[prolog], _xml, _, _} =
        Parser.parse_prolog("<?xml version=\"1.0\" encoding=\"UTF-8\"?><a></a>")

      assert prolog ==
               {:prolog,
                [
                  tag: "xml",
                  attributes: [{"version", "1.0"}, {"encoding", "UTF-8"}],
                  loc: {1, 0, 1}
                ]}
    end

    test "prolog without encoding" do
      {[prolog], _xml, _, _} = Parser.parse_prolog("<?xml version=\"1.0\" ?><a></a>")
      assert prolog == {:prolog, [tag: "xml", attributes: [{"version", "1.0"}], loc: {1, 0, 1}]}
    end

    test "no prolog" do
      {_xml, _, _} = Parser.parse_prolog("<a></a>")
      assert true
    end
  end

  describe "next_element" do
    test "capture white space" do
      {:ok, element, "<a></a>", _, _, _} = Parser.next_element("  <a></a>")
      assert element == [text: [content: "  ", loc: {1, 0, 0}]]
    end

    test "open tag" do
      {:ok, element, _xml, _, _, _} = Parser.next_element("<a a='1'></a>")
      assert element == [open: [tag: "a", attributes: [{"a", "1"}], loc: {1, 0, 1}]]
    end

    test "close tag" do
      {:ok, element, _xml, _, _, _} = Parser.next_element("</a><!-- comment -->")
      assert element == [close: [tag: "a", loc: {1, 0, 1}]]
    end

    test "text" do
      {:ok, element, _xml, _, _, _} = Parser.next_element("test text<!-- comment -->")
      assert element == [text: [content: "test text", loc: {1, 0, 0}]]
    end

    test "cdata" do
      {:ok, element, _xml, _, _, _} =
        Parser.next_element("<![CDATA[<html><body>example</body></html>]]><!-- comment -->")

      assert element == [text: [content: "<html><body>example</body></html>", loc: {1, 0, 1}]]
    end

    test "comment" do
      {:ok, element, _xml, _, _, _} = Parser.next_element("<!-- comment -->")
      assert element == [comment: [content: " comment ", loc: {1, 0, 1}]]
    end
  end

  describe "parse" do
    test "basic element" do
      result = Parser.parse("<a></a>") |> Enum.map(fn x -> x end)
      assert result == [open: [tag: "a", loc: {1, 0, 1}], close: [tag: "a", loc: {1, 0, 4}]]
    end

    test "prolog followed by element" do
      result =
        Parser.parse("<?xml version='1.0' encoding='utf-8'?><a></a>") |> Enum.map(fn x -> x end)

      assert result == [
               prolog: [
                 tag: "xml",
                 attributes: [{"version", "1.0"}, {"encoding", "utf-8"}],
                 loc: {1, 0, 1}
               ],
               open: [tag: "a", loc: {1, 0, 39}],
               close: [tag: "a", loc: {1, 0, 42}]
             ]
    end
  end

  # tag tests; single tag with variations
  test "open and close tag" do
    result = parse_xml("<a></a>") |> filter_loc()
    assert result == [open: [tag: "a"], close: [tag: "a"]]
  end

  test "empty tag" do
    result = parse_xml("<a/>") |> filter_loc()
    assert result == [open: [tag: "a"], close: [tag: "a"]]
  end

  test "attributes" do
    result = parse_xml("<a b=\"c\" d=\"e\"/>") |> filter_loc()
    assert result == [open: [tag: "a", attributes: [{"b", "c"}, {"d", "e"}]], close: [tag: "a"]]
  end

  test "text" do
    result = parse_xml("<a>text</a>") |> filter_loc()
    assert result == [open: [tag: "a"], text: [content: "text"], close: [tag: "a"]]
  end

  test "tag with all meta" do
    result = parse_xml("<ns:a b=\"c\" d=\"e\">text</ns:a>") |> filter_loc()

    assert result == [
             open: [tag: "ns:a", attributes: [{"b", "c"}, {"d", "e"}]],
             text: [content: "text"],
             close: [tag: "ns:a"]
           ]
  end

  test "that '-', '_', '.' can be included in tags and namespaces" do
    input = "<my-env:fancy_tag.with-punc></my-env:fancy_tag.with-punc>"

    assert parse_xml(input) |> Enum.to_list() == [
             open: [tag: "my-env:fancy_tag.with-punc", loc: {1, 0, 1}],
             close: [tag: "my-env:fancy_tag.with-punc", loc: {1, 0, 29}]
           ]
  end

  # nested tag tests

  test "test 2" do
    result = parse_xml("<ns:foo a='1'><bar>message</bar></ns:foo>")

    assert result == [
             {:open, [tag: "ns:foo", attributes: [{"a", "1"}], loc: {1, 0, 1}]},
             {:open, [tag: "bar", loc: {1, 0, 15}]},
             {:text, [content: "message", loc: {1, 0, 19}]},
             {:close, [tag: "bar", loc: {1, 0, 27}]},
             {:close, [tag: "ns:foo", loc: {1, 0, 33}]}
           ]
  end

  test "single nested tag" do
    xml = "<a><b/></a>"
    result = parse_xml(xml) |> filter_loc()

    assert result == [
             open: [tag: "a"],
             open: [tag: "b"],
             close: [tag: "b"],
             close: [tag: "a"]
           ]
  end

  test "list of nested tags" do
    xml = "<a><b/><c/><d/></a>"
    result = parse_xml(xml) |> filter_loc()

    assert result == [
             open: [tag: "a"],
             open: [tag: "b"],
             close: [tag: "b"],
             open: [tag: "c"],
             close: [tag: "c"],
             open: [tag: "d"],
             close: [tag: "d"],
             close: [tag: "a"]
           ]
  end

  test "list of nested tags with text" do
    xml = "<a>b-text<b></b>c-text<c></c>d-text<d></d>post-text</a>"
    result = parse_xml(xml) |> filter_loc()

    assert result == [
             open: [tag: "a"],
             text: [content: "b-text"],
             open: [tag: "b"],
             close: [tag: "b"],
             text: [content: "c-text"],
             open: [tag: "c"],
             close: [tag: "c"],
             text: [content: "d-text"],
             open: [tag: "d"],
             close: [tag: "d"],
             text: [content: "post-text"],
             close: [tag: "a"]
           ]
  end

  describe "comments" do
    test "single line comment" do
      xml = "<!-- comment --><a></a>"
      result = parse_xml(xml) |> filter_loc()
      assert result == [comment: [content: " comment "], open: [tag: "a"], close: [tag: "a"]]
    end

    test "multi line comment" do
      xml = "<!-- comment\non\nmultiple\nlines --><a/>"
      result = parse_xml(xml) |> filter_loc()

      assert result == [
               comment: [content: " comment\non\nmultiple\nlines "],
               open: [tag: "a"],
               close: [tag: "a"]
             ]
    end

    test "comment with nested tags" do
      xml = "<!-- comment <a>inside</a> --><b/>"
      result = parse_xml(xml) |> filter_loc()

      assert result == [
               comment: [content: " comment <a>inside</a> "],
               open: [tag: "b"],
               close: [tag: "b"]
             ]
    end

    test "comment after tag" do
      xml = "<a/><!-- comment -->"
      result = parse_xml(xml) |> filter_loc()
      assert result == [open: [tag: "a"], close: [tag: "a"], comment: [content: " comment "]]
    end

    test "comment within tag" do
      xml = "<a><!-- comment --></a>"
      result = parse_xml(xml) |> filter_loc()
      assert result == [open: [tag: "a"], comment: [content: " comment "], close: [tag: "a"]]
    end

    test "comment within tag before text" do
      xml = "<a> <!-- comment -->abc</a>"
      result = parse_xml(xml) |> filter_loc()

      assert result == [
               open: [tag: "a"],
               text: [content: " "],
               comment: [content: " comment "],
               text: [content: "abc"],
               close: [tag: "a"]
             ]
    end

    test "comment within tag after text" do
      xml = "<a>abc <!-- comment --></a>"
      result = parse_xml(xml) |> filter_loc()

      assert result == [
               open: [tag: "a"],
               text: [content: "abc "],
               comment: [content: " comment "],
               close: [tag: "a"]
             ]
    end

    test "comment within tag within text" do
      xml = "<a>abc <!-- comment -->def</a>"
      result = parse_xml(xml) |> filter_loc()

      assert result == [
               open: [tag: "a"],
               text: [content: "abc "],
               comment: [content: " comment "],
               text: [content: "def"],
               close: [tag: "a"]
             ]
    end
  end

  describe "white space" do
    test "tag without ws" do
      result = parse_xml("<a></a>") |> filter_loc()
      assert result == [{:open, [tag: "a"]}, {:close, [tag: "a"]}]
    end

    test "tag with ws after name" do
      result = parse_xml("<a ></a >") |> filter_loc()
      assert result == [{:open, [tag: "a"]}, {:close, [tag: "a"]}]
    end

    test "tag with tab" do
      result = parse_xml("<a\t></a>") |> filter_loc()
      assert result == [{:open, [tag: "a"]}, {:close, [tag: "a"]}]
    end
  end

  describe "prolog" do
    test "no prolog" do
      result = parse_xml("<a></a>") |> filter_loc()
      assert result == [{:open, [tag: "a"]}, {:close, [tag: "a"]}]
    end

    test "prolog" do
      result = parse_xml("<?xml version=\"1.0\"?><a></a>") |> filter_loc()

      assert result == [
               {:prolog, [tag: "xml", attributes: [{"version", "1.0"}]]},
               {:open, [tag: "a"]},
               {:close, [tag: "a"]}
             ]
    end
  end
end
