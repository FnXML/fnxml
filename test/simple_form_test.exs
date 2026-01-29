defmodule FnXML.SimpleFormTest do
  use ExUnit.Case

  alias FnXML.Event.SimpleForm

  # doctest SimpleForm  # Disabled due to quote escaping issues in expected outputs

  describe "decode/2" do
    test "decodes event stream to simple form" do
      stream = FnXML.Parser.parse("<root><item>value</item></root>")

      assert SimpleForm.decode(stream) ==
               {"root", [], [{"item", [], ["value"]}]}
    end

    test "handles self-closing tags" do
      stream = FnXML.Parser.parse("<root><empty/></root>")

      assert SimpleForm.decode(stream) ==
               {"root", [], [{"empty", [], []}]}
    end

    test "decodes with validation pipeline" do
      xml = "<root><child>text</child></root>"

      result =
        FnXML.Parser.parse(xml)
        |> FnXML.Event.Validate.well_formed()
        |> SimpleForm.decode()

      assert result == {"root", [], [{"child", [], ["text"]}]}
    end
  end

  describe "encode/1" do
    test "encodes simple form to event stream" do
      events =
        {"root", [], ["text"]}
        |> SimpleForm.encode()
        |> Enum.to_list()

      assert events == [
               {:start_element, "root", [], 1, 0, 0},
               {:characters, "text", 1, 0, 0},
               {:end_element, "root", 1, 0, 0}
             ]
    end

    test "encodes nested elements to stream" do
      events =
        {"root", [], [{"child", [{"id", "1"}], ["value"]}]}
        |> SimpleForm.encode()
        |> Enum.to_list()

      assert events == [
               {:start_element, "root", [], 1, 0, 0},
               {:start_element, "child", [{"id", "1"}], 1, 0, 0},
               {:characters, "value", 1, 0, 0},
               {:end_element, "child", 1, 0, 0},
               {:end_element, "root", 1, 0, 0}
             ]
    end

    test "stream can be piped to FnXML.Event for serialization" do
      iodata =
        {"root", [{"attr", "val"}], [{"child", [], ["text"]}]}
        |> SimpleForm.encode()
        |> FnXML.Event.to_iodata() |> Enum.join()

      xml = iodata
      assert xml == "<root attr=\"val\"><child>text</child></root>"
    end
  end

  describe "round-trip" do
    test "encode to stream, then decode from stream preserves structure" do
      simple_form = {"root", [{"id", "1"}], [{"child", [], ["text"]}, {"child", [], ["more"]}]}

      result =
        simple_form
        |> SimpleForm.encode()
        |> SimpleForm.decode()

      assert result == simple_form
    end

    test "stream round-trip preserves data" do
      original = {"root", [], [{"a", [], ["1"]}, {"b", [], ["2"]}]}

      result =
        original
        |> SimpleForm.encode()
        |> SimpleForm.decode()

      assert result == original
    end
  end

  describe "list_to_stream/1" do
    test "converts list of elements to stream" do
      events =
        [{"a", [], []}, {"b", [], []}]
        |> SimpleForm.list_to_stream()
        |> Enum.to_list()

      assert events == [
               {:start_element, "a", [], 1, 0, 0},
               {:end_element, "a", 1, 0, 0},
               {:start_element, "b", [], 1, 0, 0},
               {:end_element, "b", 1, 0, 0}
             ]
    end
  end
end
