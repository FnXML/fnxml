defmodule FnXML.C14NTest do
  use ExUnit.Case, async: true

  alias FnXML.C14N
  alias FnXML.C14N.Serializer

  describe "canonicalize/2" do
    test "empty elements rendered as start/end pairs" do
      stream = FnXML.Parser.parse("<root/>")
      iodata = C14N.canonicalize(stream)
      result = IO.iodata_to_binary(iodata)
      assert result == "<root></root>"
    end

    test "nested empty elements" do
      stream = FnXML.Parser.parse("<root><child/></root>")
      iodata = C14N.canonicalize(stream)
      result = IO.iodata_to_binary(iodata)
      assert result == "<root><child></child></root>"
    end

    test "preserves text content" do
      stream = FnXML.Parser.parse("<root>Hello World</root>")
      iodata = C14N.canonicalize(stream)
      result = IO.iodata_to_binary(iodata)
      assert result == "<root>Hello World</root>"
    end

    test "escapes text content" do
      stream = FnXML.Parser.parse("<root>a &amp; b &lt; c</root>")
      iodata = C14N.canonicalize(stream)
      result = IO.iodata_to_binary(iodata)
      assert result == "<root>a &amp; b &lt; c</root>"
    end

    test "attributes sorted alphabetically by name" do
      stream = FnXML.Parser.parse(~s(<root c="3" a="1" b="2"/>))
      iodata = C14N.canonicalize(stream)
      result = IO.iodata_to_binary(iodata)
      assert result == ~s(<root a="1" b="2" c="3"></root>)
    end

    test "attribute values use double quotes" do
      stream = FnXML.Parser.parse("<root attr='value'/>")
      iodata = C14N.canonicalize(stream)
      result = IO.iodata_to_binary(iodata)
      assert result == ~s(<root attr="value"></root>)
    end

    test "namespace declarations sorted alphabetically by prefix" do
      stream = FnXML.Parser.parse(~s(<root xmlns:z="http://z" xmlns:a="http://a"/>))
      iodata = C14N.canonicalize(stream)
      result = IO.iodata_to_binary(iodata)
      assert result == ~s(<root xmlns:a="http://a" xmlns:z="http://z"></root>)
    end

    test "default namespace comes before prefixed" do
      stream = FnXML.Parser.parse(~s(<root xmlns:a="http://a" xmlns="http://default"/>))
      iodata = C14N.canonicalize(stream)
      result = IO.iodata_to_binary(iodata)
      assert result == ~s(<root xmlns="http://default" xmlns:a="http://a"></root>)
    end

    test "removes XML declaration" do
      stream = FnXML.Parser.parse(~s(<?xml version="1.0"?><root/>))
      iodata = C14N.canonicalize(stream)
      result = IO.iodata_to_binary(iodata)
      assert result == "<root></root>"
    end

    test "removes comments by default" do
      stream = FnXML.Parser.parse("<root><!-- comment --><child/></root>")
      iodata = C14N.canonicalize(stream)
      result = IO.iodata_to_binary(iodata)
      assert result == "<root><child></child></root>"
    end

    test "preserves comments with :c14n_with_comments algorithm" do
      stream = FnXML.Parser.parse("<root><!-- comment --><child/></root>")
      iodata = C14N.canonicalize(stream, algorithm: :c14n_with_comments)
      result = IO.iodata_to_binary(iodata)
      assert result == "<root><!-- comment --><child></child></root>"
    end

    test "preserves processing instructions" do
      stream = FnXML.Parser.parse("<root><?target data?><child/></root>")
      iodata = C14N.canonicalize(stream)
      result = IO.iodata_to_binary(iodata)
      assert result == "<root><?target data?><child></child></root>"
    end
  end

  describe "C14N test vectors from spec" do
    test "C14N-001: Basic canonicalization - empty elements and whitespace" do
      input = """
      <doc>
         <e1   />
         <e2   ></e2>
         <e3   name = "elem3"   id="elem3"   />
      </doc>
      """

      stream = FnXML.Parser.parse(input)
      iodata = C14N.canonicalize(stream)
      result = IO.iodata_to_binary(iodata)

      # Expected: empty elements as <e></e>, attributes sorted
      assert result =~ "<e1></e1>"
      assert result =~ "<e2></e2>"
      # id comes before name alphabetically
      assert result =~ ~s(<e3 id="elem3" name="elem3"></e3>)
    end

    test "attribute sorting with namespaced attributes" do
      input = ~s(<root xmlns:b="http://b" xmlns:a="http://a" b:y="2" a:x="1" z="3"/>)
      stream = FnXML.Parser.parse(input)
      iodata = C14N.canonicalize(stream)
      result = IO.iodata_to_binary(iodata)

      # Namespace declarations sorted by prefix: a before b
      # Attributes sorted by namespace URI then local name
      assert result =~ "xmlns:a="
      assert result =~ "xmlns:b="
    end
  end

  describe "exclusive C14N" do
    test "filters unused namespace declarations" do
      input = ~s(<root xmlns:unused="http://unused"><child/></root>)
      stream = FnXML.Parser.parse(input)

      # With regular C14N, namespace is preserved
      c14n_iodata = C14N.canonicalize(stream, algorithm: :c14n)
      c14n_result = IO.iodata_to_binary(c14n_iodata)
      assert c14n_result =~ "xmlns:unused"

      # With exclusive C14N, unused namespace is removed
      stream = FnXML.Parser.parse(input)
      exc_iodata = C14N.canonicalize(stream, algorithm: :exc_c14n)
      exc_result = IO.iodata_to_binary(exc_iodata)
      refute exc_result =~ "xmlns:unused"
    end

    test "preserves utilized namespace declarations" do
      input = ~s(<root xmlns:used="http://used"><used:child/></root>)
      stream = FnXML.Parser.parse(input)
      iodata = C14N.canonicalize(stream, algorithm: :exc_c14n)
      result = IO.iodata_to_binary(iodata)

      # Namespace used by child element should be preserved
      assert result =~ "xmlns:used"
    end

    test "inclusive namespaces list overrides filtering" do
      input = ~s(<root xmlns:keep="http://keep"><child/></root>)
      stream = FnXML.Parser.parse(input)
      iodata = C14N.canonicalize(stream, algorithm: :exc_c14n, inclusive_namespaces: ["keep"])
      result = IO.iodata_to_binary(iodata)

      # Namespace in inclusive list should be preserved even if not visibly used
      assert result =~ "xmlns:keep"
    end
  end

  describe "Serializer.escape_text/1" do
    test "escapes ampersand" do
      assert Serializer.escape_text("a & b") == "a &amp; b"
    end

    test "escapes less than" do
      assert Serializer.escape_text("a < b") == "a &lt; b"
    end

    test "escapes greater than" do
      assert Serializer.escape_text("a > b") == "a &gt; b"
    end

    test "multiple escapes" do
      assert Serializer.escape_text("<&>") == "&lt;&amp;&gt;"
    end
  end

  describe "Serializer.escape_attr/1" do
    test "escapes double quote" do
      assert Serializer.escape_attr(~s(a"b)) == "a&quot;b"
    end

    test "escapes tab" do
      assert Serializer.escape_attr("a\tb") == "a&#x9;b"
    end

    test "escapes newline" do
      assert Serializer.escape_attr("a\nb") == "a&#xA;b"
    end

    test "escapes carriage return" do
      assert Serializer.escape_attr("a\rb") == "a&#xD;b"
    end
  end

  describe "Serializer.sort_ns_decls/1" do
    test "sorts by prefix alphabetically" do
      decls = [{"xmlns:z", "http://z"}, {"xmlns:a", "http://a"}, {"xmlns:m", "http://m"}]
      sorted = Serializer.sort_ns_decls(decls)
      assert sorted == [{"xmlns:a", "http://a"}, {"xmlns:m", "http://m"}, {"xmlns:z", "http://z"}]
    end

    test "default namespace comes first" do
      decls = [{"xmlns:a", "http://a"}, {"xmlns", "http://default"}]
      sorted = Serializer.sort_ns_decls(decls)
      assert sorted == [{"xmlns", "http://default"}, {"xmlns:a", "http://a"}]
    end
  end

  describe "Serializer.sort_attrs/2" do
    test "sorts by local name when no namespaces" do
      attrs = [{"z", "1"}, {"a", "2"}, {"m", "3"}]
      sorted = Serializer.sort_attrs(attrs, %{})
      assert sorted == [{"a", "2"}, {"m", "3"}, {"z", "1"}]
    end

    test "unprefixed attributes come before prefixed" do
      attrs = [{"ns:b", "1"}, {"a", "2"}]
      ns_context = %{"ns" => "http://ns"}
      sorted = Serializer.sort_attrs(attrs, ns_context)
      # Empty namespace sorts before "http://ns"
      assert sorted == [{"a", "2"}, {"ns:b", "1"}]
    end
  end

  describe "algorithm_uri/1" do
    test "returns correct URIs" do
      assert C14N.algorithm_uri(:c14n) == "http://www.w3.org/TR/2001/REC-xml-c14n-20010315"
      assert C14N.algorithm_uri(:exc_c14n) == "http://www.w3.org/2001/10/xml-exc-c14n#"
    end
  end

  describe "algorithm_atom/1" do
    test "parses known URIs" do
      assert C14N.algorithm_atom("http://www.w3.org/TR/2001/REC-xml-c14n-20010315") ==
               {:ok, :c14n}

      assert C14N.algorithm_atom("http://www.w3.org/2001/10/xml-exc-c14n#") == {:ok, :exc_c14n}
    end

    test "returns error for unknown URIs" do
      assert C14N.algorithm_atom("unknown") == {:error, :unknown_algorithm}
    end
  end
end
