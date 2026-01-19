defmodule FnXML.SAXTest do
  use ExUnit.Case, async: true

  alias FnXML.SAX

  defmodule CollectHandler do
    @behaviour FnXML.SAX

    @impl true
    def start_document(state), do: {:ok, Map.put(state, :started, true)}

    @impl true
    def end_document(state), do: {:ok, Map.put(state, :ended, true)}

    @impl true
    def start_element(_uri, local, _qname, attrs, state) do
      elem = {local, attrs}
      {:ok, Map.update(state, :elements, [elem], &[elem | &1])}
    end

    @impl true
    def end_element(_uri, _local, _qname, state), do: {:ok, state}

    @impl true
    def characters(text, state) do
      {:ok, Map.update(state, :text, text, &(&1 <> text))}
    end
  end

  defmodule HaltHandler do
    @behaviour FnXML.SAX

    @impl true
    def start_document(state), do: {:ok, state}

    @impl true
    def end_document(state), do: {:ok, state}

    @impl true
    def start_element(_uri, local, _qname, _attrs, state) do
      if local == "stop" do
        {:halt, Map.put(state, :halted, true)}
      else
        {:ok, state}
      end
    end

    @impl true
    def end_element(_uri, _local, _qname, state), do: {:ok, state}

    @impl true
    def characters(_text, state), do: {:ok, state}
  end

  defmodule ErrorHandler do
    @behaviour FnXML.SAX

    @impl true
    def start_document(state), do: {:ok, state}

    @impl true
    def end_document(state), do: {:ok, state}

    @impl true
    def start_element(_uri, _local, _qname, _attrs, _state) do
      {:error, "handler error"}
    end

    @impl true
    def end_element(_uri, _local, _qname, state), do: {:ok, state}

    @impl true
    def characters(_text, state), do: {:ok, state}
  end

  defmodule StartDocErrorHandler do
    @behaviour FnXML.SAX

    @impl true
    def start_document(_state), do: {:error, "start error"}

    @impl true
    def end_document(state), do: {:ok, state}

    @impl true
    def start_element(_uri, _local, _qname, _attrs, state), do: {:ok, state}

    @impl true
    def end_element(_uri, _local, _qname, state), do: {:ok, state}

    @impl true
    def characters(_text, state), do: {:ok, state}
  end

  defmodule FullHandler do
    @behaviour FnXML.SAX

    @impl true
    def start_document(state), do: {:ok, state}

    @impl true
    def end_document(state), do: {:ok, state}

    @impl true
    def start_element(_uri, _local, _qname, _attrs, state), do: {:ok, state}

    @impl true
    def end_element(_uri, _local, _qname, state), do: {:ok, state}

    @impl true
    def characters(_text, state), do: {:ok, state}

    @impl true
    def comment(text, state) do
      {:ok, Map.update(state, :comments, [text], &[text | &1])}
    end

    @impl true
    def processing_instruction(target, data, state) do
      {:ok, Map.update(state, :pis, [{target, data}], &[{target, data} | &1])}
    end

    @impl true
    def error(reason, loc, state) do
      {:ok, Map.update(state, :errors, [{reason, loc}], &[{reason, loc} | &1])}
    end
  end

  describe "parse/4" do
    test "parses simple XML" do
      {:ok, state} = SAX.parse("<root/>", CollectHandler, %{})
      assert state.started == true
      assert state.ended == true
      assert [{"root", []}] = state.elements
    end

    test "collects element attributes" do
      {:ok, state} = SAX.parse("<root id=\"1\"/>", CollectHandler, %{})
      [{"root", attrs}] = state.elements
      # Namespace resolver changes attrs to {uri, name, value} format
      assert Enum.any?(attrs, fn
               {nil, "id", "1"} -> true
               {"id", "1"} -> true
               _ -> false
             end)
    end

    test "collects nested elements" do
      {:ok, state} = SAX.parse("<a><b/><c/></a>", CollectHandler, %{})
      names = Enum.map(state.elements, fn {name, _} -> name end)
      assert "a" in names
      assert "b" in names
      assert "c" in names
    end

    test "collects text content" do
      {:ok, state} = SAX.parse("<root>hello world</root>", CollectHandler, %{})
      assert state.text =~ "hello"
    end

    test "supports halt return" do
      {:ok, state} = SAX.parse("<root><stop/><after/></root>", HaltHandler, %{})
      assert state.halted == true
    end

    test "returns error from handler" do
      result = SAX.parse("<root/>", ErrorHandler, %{})
      assert {:error, "handler error"} = result
    end

    test "returns error from start_document" do
      result = SAX.parse("<root/>", StartDocErrorHandler, %{})
      assert {:error, "start error"} = result
    end
  end

  describe "parse/4 without namespaces" do
    test "passes raw tag names" do
      {:ok, state} = SAX.parse("<ns:root/>", CollectHandler, %{}, namespaces: false)
      [{"root", _}] = state.elements
    end

    test "handles end element without loc" do
      xml = "<root/>"
      {:ok, state} = SAX.parse(xml, CollectHandler, %{}, namespaces: false)
      assert length(state.elements) >= 1
    end
  end

  describe "parse/4 with namespaces" do
    test "resolves namespace URIs" do
      xml = "<root xmlns=\"http://example.org\"/>"
      {:ok, state} = SAX.parse(xml, CollectHandler, %{})
      assert length(state.elements) >= 1
    end
  end

  describe "optional callbacks" do
    test "calls comment callback when defined" do
      {:ok, state} = SAX.parse("<root><!-- test --></root>", FullHandler, %{})
      assert [" test "] = state.comments
    end

    test "calls processing_instruction callback when defined" do
      {:ok, state} = SAX.parse("<?php echo 'hi'; ?><root/>", FullHandler, %{})
      assert [{"php", _}] = state.pis
    end

    test "calls error callback when defined" do
      # Use malformed XML that triggers parser error events
      {:ok, state} = SAX.parse("<root><<</root>", FullHandler, %{})
      assert length(state.errors) >= 1
    end
  end

  describe "parse/4 with stream input" do
    test "accepts event stream" do
      stream = FnXML.Parser.parse("<root/>")
      {:ok, state} = SAX.parse(stream, CollectHandler, %{})
      assert state.started == true
    end
  end

  describe "CDATA handling" do
    test "treats CDATA as characters" do
      {:ok, state} = SAX.parse("<root><![CDATA[text]]></root>", CollectHandler, %{})
      assert state.text =~ "text"
    end
  end
end
