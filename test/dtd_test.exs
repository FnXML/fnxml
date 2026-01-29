defmodule FnXML.DTDTest do
  use ExUnit.Case, async: true

  alias FnXML.DTD

  describe "decode/2" do
    test "parses DTD with internal subset" do
      xml = """
      <!DOCTYPE note [
        <!ELEMENT note (#PCDATA)>
        <!ENTITY greeting "Hello">
      ]>
      <note>&greeting;</note>
      """

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.decode()

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

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.decode()

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

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.decode()

      assert model.root_element == "root"
      attrs = model.attributes["root"]
      assert length(attrs) == 2

      id_attr = Enum.find(attrs, fn %{name: name} -> name == "id" end)
      assert %{name: "id", type: :id, default: :required} = id_attr

      class_attr = Enum.find(attrs, fn %{name: name} -> name == "class" end)
      assert %{name: "class", type: :cdata, default: :implied} = class_attr
    end

    test "returns {:error, :no_dtd} when stream has no DOCTYPE" do
      xml = "<root>content</root>"

      result = FnXML.Parser.parse(xml) |> DTD.decode()

      assert result == {:error, :no_dtd}
    end

    test "parses external SYSTEM identifier" do
      # Without external resolver, only root_name is captured
      xml = """
      <!DOCTYPE root SYSTEM "root.dtd">
      <root/>
      """

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.decode()

      assert model.root_element == "root"
      # No elements since no resolver provided
      assert model.elements == %{}
    end

    test "parses external PUBLIC identifier" do
      xml = """
      <!DOCTYPE root PUBLIC "-//Example//DTD Root//EN" "root.dtd">
      <root/>
      """

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.decode()

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

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.decode(external_resolver: resolver)

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

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.decode(external_resolver: resolver)

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

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.decode(external_resolver: resolver)

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

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.decode()

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

      {:ok, model} = FnXML.Parser.parse(xml) |> DTD.decode()

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

  describe "resolve/2 pipeline function" do
    test "processes DTD entities in pipeline" do
      xml = """
      <!DOCTYPE note [<!ENTITY greeting "Hello">]>
      <note>&greeting;</note>
      """

      events =
        FnXML.Parser.parse(xml)
        |> DTD.resolve()
        |> Enum.to_list()

      text_event =
        Enum.find(events, fn
          {:characters, _, _, _, _} -> true
          {:characters, _, _} -> true
          _ -> false
        end)

      assert text_event != nil
      assert elem(text_event, 1) == "Hello"
    end

    test "handles XML without DTD" do
      xml = "<note>Hello</note>"

      events =
        FnXML.Parser.parse(xml)
        |> DTD.resolve()
        |> Enum.to_list()

      # Should have start_element for "note"
      assert Enum.any?(events, fn
               {:start_element, "note", _, _, _, _} -> true
               {:start_element, "note", _, _} -> true
               _ -> false
             end)

      # Should have text content
      text_event =
        Enum.find(events, fn
          {:characters, _, _, _, _} -> true
          {:characters, _, _} -> true
          _ -> false
        end)

      assert text_event != nil
      assert elem(text_event, 1) == "Hello"
    end

    test "resolves entities in attributes" do
      xml = """
      <!DOCTYPE doc [<!ENTITY val "test">]>
      <doc attr="&val;"/>
      """

      events =
        FnXML.Parser.parse(xml)
        |> DTD.resolve()
        |> Enum.to_list()

      start_event =
        Enum.find(events, fn
          {:start_element, "doc", _, _, _, _} -> true
          {:start_element, "doc", _, _} -> true
          _ -> false
        end)

      assert start_event != nil

      attrs =
        case start_event do
          {:start_element, _, attrs, _, _, _} -> attrs
          {:start_element, _, attrs, _} -> attrs
        end

      assert Enum.find(attrs, fn {name, _} -> name == "attr" end) == {"attr", "test"}
    end

    test "composes with other transforms" do
      xml = """
      <!DOCTYPE doc [<!ENTITY e "value">]>
      <doc><child>&e;</child></doc>
      """

      events =
        FnXML.Parser.parse(xml)
        |> DTD.resolve()
        |> FnXML.Event.Validate.well_formed()
        |> Stream.reject(fn
          {:characters, content, _, _, _} -> String.trim(content) == ""
          _ -> false
        end)
        |> Enum.to_list()

      # Should not have any error events
      refute Enum.any?(events, fn
               {:error, _, _, _, _, _} -> true
               {:error, _, _} -> true
               {:error, _} -> true
               _ -> false
             end)

      # Text should be resolved
      text_event =
        Enum.find(events, fn
          {:characters, _, _, _, _} -> true
          {:characters, _, _} -> true
          _ -> false
        end)

      assert text_event != nil
      assert elem(text_event, 1) == "value"
    end

    test "handles nested entity definitions" do
      xml = """
      <!DOCTYPE message [
        <!ENTITY hello "Hello">
        <!ENTITY world "World">
        <!ENTITY greeting "&hello;, &world;!">
      ]>
      <message>&greeting;</message>
      """

      events =
        FnXML.Parser.parse(xml)
        |> DTD.resolve()
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

    test "resolves both custom and predefined entities" do
      xml = """
      <!DOCTYPE doc [<!ENTITY custom "value">]>
      <doc>&custom; &amp; text</doc>
      """

      events =
        FnXML.Parser.parse(xml)
        |> DTD.resolve()
        |> Enum.to_list()

      text_event =
        Enum.find(events, fn
          {:characters, _, _, _, _} -> true
          {:characters, _, _} -> true
          _ -> false
        end)

      assert text_event != nil
      # Both custom and predefined entities resolved by DTD.resolve
      assert elem(text_event, 1) == "value & text"
    end

    test "on_unknown: :emit returns error for undefined entities" do
      xml = """
      <!DOCTYPE doc []>
      <doc>&undefined;</doc>
      """

      events =
        FnXML.Parser.parse(xml)
        |> DTD.resolve(on_unknown: :emit)
        |> Enum.to_list()

      # Should have an error event
      assert Enum.any?(events, fn
               {:error, _} -> true
               {:error, _, _} -> true
               {:error, _, _, _, _, _} -> true
               _ -> false
             end)
    end

    test "on_unknown: :keep preserves undefined entities" do
      xml = """
      <!DOCTYPE doc []>
      <doc>&undefined;</doc>
      """

      events =
        FnXML.Parser.parse(xml)
        |> DTD.resolve(on_unknown: :keep)
        |> Enum.to_list()

      text_event =
        Enum.find(events, fn
          {:characters, _, _, _, _} -> true
          {:characters, _, _} -> true
          _ -> false
        end)

      assert text_event != nil
      assert elem(text_event, 1) == "&undefined;"
    end

    test "buffers prolog and passes through" do
      xml = """
      <?xml version="1.0"?>
      <!DOCTYPE doc [<!ENTITY e "val">]>
      <doc>&e;</doc>
      """

      events =
        FnXML.Parser.parse(xml)
        |> DTD.resolve()
        |> Enum.to_list()

      # Prolog should be preserved
      assert Enum.any?(events, fn
               {:prolog, "xml", _, _, _, _} -> true
               {:prolog, "xml", _, _} -> true
               _ -> false
             end)

      # Entity should be resolved
      text_event =
        Enum.find(events, fn
          {:characters, _, _, _, _} -> true
          {:characters, _, _} -> true
          _ -> false
        end)

      assert text_event != nil
      assert elem(text_event, 1) == "val"
    end

    test "handles multiple text nodes with entities" do
      xml = """
      <!DOCTYPE doc [
        <!ENTITY a "A">
        <!ENTITY b "B">
      ]>
      <doc><x>&a;</x><y>&b;</y></doc>
      """

      events =
        FnXML.Parser.parse(xml)
        |> DTD.resolve()
        |> Enum.to_list()

      text_events =
        Enum.filter(events, fn
          {:characters, content, _, _, _} -> String.trim(content) != ""
          {:characters, content, _} -> String.trim(content) != ""
          _ -> false
        end)

      texts = Enum.map(text_events, &elem(&1, 1))
      assert "A" in texts
      assert "B" in texts
    end

    test "handles DTD with external resolver" do
      xml = """
      <!DOCTYPE doc SYSTEM "test.dtd" [
        <!ENTITY local "local-value">
      ]>
      <doc>&external; &local;</doc>
      """

      resolver = fn "test.dtd", nil ->
        {:ok, "<!ENTITY external \"external-value\">"}
      end

      events =
        FnXML.Parser.parse(xml)
        |> DTD.resolve(external_resolver: resolver, on_unknown: :keep)
        |> Enum.to_list()

      text_event =
        Enum.find(events, fn
          {:characters, _, _, _, _} -> true
          {:characters, _, _} -> true
          _ -> false
        end)

      assert text_event != nil
      content = elem(text_event, 1)
      assert content =~ "external-value"
      assert content =~ "local-value"
    end
  end
end
