defmodule FnXML.DTDTest do
  use ExUnit.Case, async: true

  alias FnXML.DTD

  describe "from_stream/2" do
    test "parses DTD with internal subset" do
      xml = """
      <!DOCTYPE note [
        <!ELEMENT note (#PCDATA)>
        <!ENTITY greeting "Hello">
      ]>
      <note>&greeting;</note>
      """

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.from_stream()

      assert model.root_element == "note"
      assert model.elements["note"] == :pcdata
      assert model.entities["greeting"] == {:internal, "Hello"}
    end

    test "parses DTD with multiple element declarations" do
      xml = """
      <!DOCTYPE root [
        <!ELEMENT root (child1, child2)>
        <!ELEMENT child1 (#PCDATA)>
        <!ELEMENT child2 EMPTY>
      ]>
      <root><child1>text</child1><child2/></root>
      """

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.from_stream()

      assert model.root_element == "root"
      assert model.elements["root"] == {:seq, ["child1", "child2"]}
      assert model.elements["child1"] == :pcdata
      assert model.elements["child2"] == :empty
    end

    test "parses DTD with attribute declarations" do
      xml = """
      <!DOCTYPE root [
        <!ELEMENT root EMPTY>
        <!ATTLIST root
          id ID #REQUIRED
          class CDATA #IMPLIED>
      ]>
      <root id="r1"/>
      """

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.from_stream()

      assert model.root_element == "root"
      attrs = model.attributes["root"]
      assert length(attrs) == 2

      id_attr = Enum.find(attrs, fn %{name: name} -> name == "id" end)
      assert %{name: "id", type: :id, default: :required} = id_attr

      class_attr = Enum.find(attrs, fn %{name: name} -> name == "class" end)
      assert %{name: "class", type: :cdata, default: :implied} = class_attr
    end

    test "returns :no_dtd when stream has no DOCTYPE" do
      xml = "<root>content</root>"

      result = FnXML.Parser.parse(xml) |> DTD.from_stream()

      assert result == :no_dtd
    end

    test "parses external SYSTEM identifier" do
      # Without external resolver, only root_name is captured
      xml = """
      <!DOCTYPE root SYSTEM "root.dtd">
      <root/>
      """

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.from_stream()

      assert model.root_element == "root"
      # No elements since no resolver provided
      assert model.elements == %{}
    end

    test "parses external PUBLIC identifier" do
      xml = """
      <!DOCTYPE root PUBLIC "-//Example//DTD Root//EN" "root.dtd">
      <root/>
      """

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.from_stream()

      assert model.root_element == "root"
    end

    test "uses external resolver to fetch DTD" do
      xml = """
      <!DOCTYPE root SYSTEM "test.dtd">
      <root/>
      """

      resolver = fn "test.dtd", nil ->
        {:ok, "<!ELEMENT root EMPTY>"}
      end

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.from_stream(external_resolver: resolver)

      assert model.root_element == "root"
      assert model.elements["root"] == :empty
    end

    test "internal subset takes precedence over external" do
      xml = """
      <!DOCTYPE root SYSTEM "test.dtd" [
        <!ELEMENT root (#PCDATA)>
      ]>
      <root>text</root>
      """

      resolver = fn "test.dtd", nil ->
        {:ok, "<!ELEMENT root EMPTY>"}
      end

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.from_stream(external_resolver: resolver)

      assert model.root_element == "root"
      # Internal subset (#PCDATA) should override external (EMPTY)
      assert model.elements["root"] == :pcdata
    end

    test "merges external and internal subset declarations" do
      xml = """
      <!DOCTYPE root SYSTEM "test.dtd" [
        <!ELEMENT child (#PCDATA)>
      ]>
      <root><child>text</child></root>
      """

      resolver = fn "test.dtd", nil ->
        {:ok, "<!ELEMENT root (child)>"}
      end

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.from_stream(external_resolver: resolver)

      # Single-item groups are unwrapped to just the element name
      assert model.elements["root"] == "child"
      assert model.elements["child"] == :pcdata
    end
  end

  describe "parse_doctype/2" do
    test "parses DOCTYPE with internal subset only" do
      content = "DOCTYPE root [<!ELEMENT root EMPTY>]"

      {:ok, model} = DTD.parse_doctype(content)

      assert model.root_element == "root"
      assert model.elements["root"] == :empty
    end

    test "parses DOCTYPE with SYSTEM identifier" do
      content = ~s[DOCTYPE root SYSTEM "file.dtd"]

      {:ok, model} = DTD.parse_doctype(content)

      assert model.root_element == "root"
    end

    test "parses DOCTYPE with PUBLIC identifier" do
      content = ~s[DOCTYPE root PUBLIC "-//Example//DTD//EN" "file.dtd"]

      {:ok, model} = DTD.parse_doctype(content)

      assert model.root_element == "root"
    end

    test "parses DOCTYPE with SYSTEM and internal subset" do
      content = ~s|DOCTYPE root SYSTEM "file.dtd" [<!ELEMENT root EMPTY>]|

      {:ok, model} = DTD.parse_doctype(content)

      assert model.root_element == "root"
      assert model.elements["root"] == :empty
    end

    test "parses DOCTYPE with PUBLIC and internal subset" do
      content = ~s|DOCTYPE root PUBLIC "-//Example//EN" "file.dtd" [<!ELEMENT root (#PCDATA)>]|

      {:ok, model} = DTD.parse_doctype(content)

      assert model.root_element == "root"
      assert model.elements["root"] == :pcdata
    end

    test "returns error for invalid DOCTYPE" do
      content = "INVALID"

      result = DTD.parse_doctype(content)

      assert {:error, _} = result
    end
  end

  describe "parse_doctype_parts/1" do
    test "parses root name only" do
      content = "DOCTYPE root"

      {:ok, root, external_id, internal} = DTD.parse_doctype_parts(content)

      assert root == "root"
      assert external_id == nil
      assert internal == nil
    end

    test "parses with internal subset" do
      content = "DOCTYPE root [<!ELEMENT root EMPTY>]"

      {:ok, root, external_id, internal} = DTD.parse_doctype_parts(content)

      assert root == "root"
      assert external_id == nil
      assert internal == "<!ELEMENT root EMPTY>"
    end

    test "parses SYSTEM identifier" do
      content = ~s[DOCTYPE root SYSTEM "file.dtd"]

      {:ok, root, external_id, internal} = DTD.parse_doctype_parts(content)

      assert root == "root"
      assert external_id == {"file.dtd", nil}
      assert internal == nil
    end

    test "parses PUBLIC identifier" do
      content = ~s[DOCTYPE root PUBLIC "-//Example//EN" "file.dtd"]

      {:ok, root, external_id, internal} = DTD.parse_doctype_parts(content)

      assert root == "root"
      assert external_id == {"file.dtd", "-//Example//EN"}
      assert internal == nil
    end

    test "parses single-quoted strings" do
      content = "DOCTYPE root SYSTEM 'file.dtd'"

      {:ok, root, external_id, _internal} = DTD.parse_doctype_parts(content)

      assert root == "root"
      assert external_id == {"file.dtd", nil}
    end

    test "handles nested angle brackets in internal subset" do
      content = "DOCTYPE root [<!ELEMENT root (a|b)><!ATTLIST root id ID #REQUIRED>]"

      {:ok, root, external_id, internal} = DTD.parse_doctype_parts(content)

      assert root == "root"
      assert external_id == nil
      assert internal =~ "<!ELEMENT root (a|b)>"
      assert internal =~ "<!ATTLIST root id ID #REQUIRED>"
    end

    test "returns error for missing DOCTYPE keyword" do
      content = "root [<!ELEMENT root EMPTY>]"

      result = DTD.parse_doctype_parts(content)

      assert {:error, _} = result
    end

    test "returns error for missing root name" do
      content = "DOCTYPE"

      result = DTD.parse_doctype_parts(content)

      assert {:error, _} = result
    end

    test "returns error for unterminated internal subset" do
      content = "DOCTYPE root [<!ELEMENT root EMPTY>"

      result = DTD.parse_doctype_parts(content)

      assert {:error, _} = result
    end
  end

  describe "integration with EntityResolver" do
    test "full pipeline: parse stream, extract DTD, resolve entities" do
      xml = """
      <!DOCTYPE message [
        <!ELEMENT message (#PCDATA)>
        <!ENTITY hello "Hello">
        <!ENTITY world "World">
        <!ENTITY greeting "&hello;, &world;!">
      ]>
      <message>&greeting;</message>
      """

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.from_stream()

      events =
        FnXML.Parser.parse(xml)
        |> FnXML.DTD.EntityResolver.resolve(model)
        |> Enum.to_list()

      text_event =
        Enum.find(events, fn
          {:characters, _, _, _, _} -> true
          {:characters, _, _} -> true
          _ -> false
        end)

      assert text_event != nil
      assert elem(text_event, 1) == "Hello, World!"
    end

    test "entity resolution with DTD from stream" do
      xml = """
      <!DOCTYPE doc [
        <!ENTITY copy "&#169;">
        <!ENTITY tm "&#8482;">
      ]>
      <doc>Copyright &copy; Trademark &tm;</doc>
      """

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.from_stream()

      events =
        FnXML.Parser.parse(xml)
        |> FnXML.DTD.EntityResolver.resolve(model, on_unknown: :keep)
        |> Enum.to_list()

      text_event =
        Enum.find(events, fn
          {:characters, _, _, _, _} -> true
          {:characters, _, _} -> true
          _ -> false
        end)

      assert text_event != nil
      # Character references are preserved for FnXML.Entities
      content = elem(text_event, 1)
      assert content =~ "Copyright"
      assert content =~ "Trademark"
    end
  end
end
