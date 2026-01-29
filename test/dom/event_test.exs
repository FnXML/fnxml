defmodule FnXML.DOM.EventTest do
  use ExUnit.Case, async: true

  alias FnXML.API.DOM
  alias FnXML.API.DOM.{Document, Element}

  describe "to_event/1" do
    test "generates element events including special types" do
      elem =
        Element.new("root", [], [
          "text",
          {:comment, "c"},
          {:cdata, "d"},
          {:pi, "t", "d"},
          Element.new("child", [], [])
        ])

      events = DOM.to_event(elem) |> Enum.to_list()

      assert {:start_element, "root", [], nil} in events
      assert {:characters, "text", nil} in events
      assert {:comment, "c", nil} in events
      assert {:cdata, "d", nil} in events
      assert {:processing_instruction, "t", "d", nil} in events
      assert {:start_element, "child", [], nil} in events
      assert {:end_element, "root"} in events
    end

    test "handles document and nil root" do
      doc = %Document{root: Element.new("root", [], [])}
      events = DOM.to_event(doc) |> Enum.to_list()
      assert {:start_element, "root", [], nil} in events

      assert DOM.to_event(%Document{root: nil}) |> Enum.to_list() == []
    end

    test "skips nil children" do
      elem = Element.new("root", [], [nil, "text", nil])
      events = DOM.to_event(elem) |> Enum.to_list()
      text_events = Enum.filter(events, &match?({:characters, _, _}, &1))
      assert length(text_events) == 1
    end
  end
end
