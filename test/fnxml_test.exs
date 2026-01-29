defmodule FnXMLTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  describe "parse/1 and parse/2" do
    test "delegates to FnXML.Parser.parse/1" do
      stream = FnXML.parse("<root/>")
      assert is_function(stream) or match?(%Stream{}, stream)
      events = Enum.to_list(stream)
      assert {:start_document, nil} in events
      assert {:end_document, nil} in events
      # Parser outputs 6-tuple format: {:start_element, tag, attrs, line, ls, pos}
      assert Enum.any?(events, &match?({:start_element, "root", [], _, _, _}, &1))
    end

    test "delegates with options" do
      stream = FnXML.parse("<root/>", parser: :default)
      events = Enum.to_list(stream)
      assert length(events) > 0
    end

    test "supports early termination on stream" do
      events = FnXML.parse("<root><a/><b/><c/></root>") |> Enum.take(3)
      assert length(events) == 3
    end
  end

  describe "halt_on_error/1" do
    test "passes through events until error" do
      events = [
        {:start_document, nil},
        {:start_element, "root", [], {1, 0, 1}},
        {:characters, "text", {1, 0, 6}}
      ]

      result = events |> FnXML.halt_on_error() |> Enum.to_list()
      assert result == events
    end

    test "halts after error event" do
      events = [
        {:start_document, nil},
        {:error, "bad", {1, 0, 5}},
        {:characters, "should not appear", {1, 0, 10}}
      ]

      result = events |> FnXML.halt_on_error() |> Enum.to_list()
      assert result == [{:start_document, nil}, {:error, "bad", {1, 0, 5}}]
    end
  end

  describe "log_on_error/2" do
    test "logs error events with default options" do
      events = [{:error, "test error", {3, 10, 25}}]

      log =
        capture_log(fn ->
          events |> FnXML.log_on_error() |> Enum.to_list()
        end)

      assert log =~ "XML parse error"
      assert log =~ "line 3"
      assert log =~ "column 15"
      assert log =~ "test error"
    end

    test "logs with custom level and prefix" do
      events = [{:error, "oops", {1, 0, 5}}]

      log =
        capture_log(fn ->
          events |> FnXML.log_on_error(level: :error, prefix: "Custom") |> Enum.to_list()
        end)

      assert log =~ "Custom"
      assert log =~ "oops"
    end

    test "passes through non-error events unchanged" do
      events = [{:start_element, "root", [], {1, 0, 1}}]
      result = events |> FnXML.log_on_error() |> Enum.to_list()
      assert result == events
    end
  end

  describe "check_errors/1" do
    test "returns {:ok, events} when no errors" do
      events = [
        {:start_document, nil},
        {:start_element, "root", [], {1, 0, 1}},
        {:end_element, "root", {1, 0, 7}},
        {:end_document, nil}
      ]

      assert {:ok, ^events} = FnXML.check_errors(events)
    end

    test "returns {:error, errors} when errors present" do
      events = [
        {:start_document, nil},
        {:error, "bad thing", {1, 0, 5}},
        {:error, "another bad", {2, 0, 15}}
      ]

      assert {:error, errors} = FnXML.check_errors(events)
      assert length(errors) == 2
    end

    test "works with non-list enumerables" do
      stream = Stream.map([{:start_element, "a", [], {1, 0, 1}}], & &1)
      assert {:ok, _} = FnXML.check_errors(stream)
    end
  end

  describe "position/1" do
    test "calculates column from location tuple" do
      assert {1, 0} = FnXML.position({1, 0, 0})
      assert {1, 5} = FnXML.position({1, 0, 5})
      assert {3, 10} = FnXML.position({3, 20, 30})
    end
  end
end
