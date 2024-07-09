defmodule FnXML.Stream.ToMapTest do
  use ExUnit.Case
  alias FnXML.Stream.ToMap
  doctest FnXML.Stream.ToMap

  def parse_to_map(xml, opts \\ []) do
    xml
    |> FnXML.Parser.parse()
    |> FnXML.Stream.transform(ToMap.to_map_fn(private: opts))
    |> Enum.map(fn x -> x end)
  end

  test "test 1" do
    xml = "<ns:foo a='1'>bar</ns:foo>"
    result = parse_to_map(xml)

    assert result == [
             %{
               :_meta => %{tag: "foo", loc: {{1, 0}, 1}, order: [:_text]},
               :_namespace => "ns",
               :a => "1",
               :_text => ["bar"]
             }
           ]
  end

  test "test 2" do
    xml = "<ns:foo a='1'><bar a='1'>message</bar></ns:foo>"
    result = parse_to_map(xml)

    assert result == [
             %{
               :_meta => %{tag: "foo", loc: {{1, 0}, 1}, order: ["bar"]},
               :_namespace => "ns",
               :a => "1",
               "bar" => %{
                 :a => "1",
                 :_meta => %{tag: "bar", loc: {{1, 0}, 15}, order: [:_text]},
                 :_text => ["message"]
               }
             }
           ]
  end

  test "test 3" do
    xml = "<ns:foo a='1'><bar a='1'>message</bar><bar b='2'>other message</bar></ns:foo>"
    result = parse_to_map(xml)

    assert result == [
             %{
               :_meta => %{tag: "foo", loc: {{1, 0}, 1}, order: ["bar", "bar"]},
               :_namespace => "ns",
               :a => "1",
               "bar" => [
                 %{
                   :a => "1",
                   :_meta => %{tag: "bar", loc: {{1, 0}, 15}, order: [:_text]},
                   :_text => ["message"]
                 },
                 %{
                   :b => "2",
                   :_meta => %{tag: "bar", loc: {{1, 0}, 39}, order: [:_text]},
                   :_text => ["other message"]
                 }
               ]
             }
           ]
  end

  test "test 4" do
    xml =
      "<ns:foo a='1'>text0<bar a='1'>message</bar>text 1<bar b='2'>other message</bar> text 2</ns:foo>"

    result = parse_to_map(xml)

    assert result == [
             %{
               :_meta => %{
                 tag: "foo",
                 loc: {{1, 0}, 1},
                 order: [:_text, "bar", :_text, "bar", :_text]
               },
               :_namespace => "ns",
               :a => "1",
               :_text => ["text0", "text 1", " text 2"],
               "bar" => [
                 %{
                   :a => "1",
                   :_meta => %{tag: "bar", loc: {{1, 0}, 20}, order: [:_text]},
                   :_text => ["message"]
                 },
                 %{
                   :b => "2",
                   :_meta => %{tag: "bar", loc: {{1, 0}, 50}, order: [:_text]},
                   :_text => ["other message"]
                 }
               ]
             }
           ]
  end

  test "test 5" do
    xml =
      "<ns0:foo a='1'>text0<ns1:bar a='1'>message</ns1:bar>text 1<ns2:bar b='2'>other message</ns2:bar> text 2</ns:foo>"

    result = parse_to_map(xml, meta_enabled: false, namespace_enabled: false)

    assert result == [
             %{
               :a => "1",
               :_text => ["text0", "text 1", " text 2"],
               "bar" => [
                 %{
                   :a => "1",
                   :_text => ["message"]
                 },
                 %{
                   :b => "2",
                   :_text => ["other message"]
                 }
               ]
             }
           ]
  end

  test "test 6" do
    xml = "<ns0:foo>text0<ns1:bar>message</ns1:bar><ns2:baz>other message</ns2:baz></ns:foo>"
    result = parse_to_map(xml, meta_enabled: false, namespace_enabled: false)

    assert result == [
             %{
               :_text => ["text0"],
               "bar" => "message",
               "baz" => "other message"
             }
           ]
  end
end
