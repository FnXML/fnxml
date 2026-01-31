defmodule FnXML.EventModeTest do
  use ExUnit.Case, async: true

  alias FnXML.Event

  describe "transform with event_mode option" do
    test "event_mode: :pass (default) passes unknown events to callback" do
      # Create a stream with a custom unknown event
      stream = [
        {:start_element, "root", [], 1, 0, 1},
        {:custom_event, "data", :metadata},
        {:end_element, "root", 1, 0, 15}
      ]

      result =
        Event.transform(stream, [], [event_mode: :pass], fn element, _path, acc ->
          {element, [element | acc]}
        end)
        |> Enum.to_list()

      # Should include the custom event in results
      assert Enum.any?(result, &match?({:custom_event, "data", :metadata}, &1))
    end

    test "event_mode: :discard silently discards unknown events" do
      stream = [
        {:start_element, "root", [], 1, 0, 1},
        {:custom_event, "data", :metadata},
        {:characters, "text", 1, 0, 7},
        {:end_element, "root", 1, 0, 15}
      ]

      result =
        Event.transform(stream, [], [event_mode: :discard], fn element, _path, acc ->
          {element, acc}
        end)
        |> Enum.to_list()

      # Should NOT include the custom event
      refute Enum.any?(result, &match?({:custom_event, "data", :metadata}, &1))

      # Should have start_element, characters, and end_element
      assert Enum.any?(result, &match?({:start_element, "root", _, _, _, _}, &1))
      assert Enum.any?(result, &match?({:characters, "text", _, _, _}, &1))
      assert Enum.any?(result, &match?({:end_element, "root", _, _, _}, &1))
    end

    test "event_mode: :strict emits error for unknown events" do
      stream = [
        {:start_element, "root", [], 1, 0, 1},
        {:custom_event, "data", :metadata},
        {:end_element, "root", 1, 0, 15}
      ]

      result =
        Event.transform(stream, [], [event_mode: :strict], fn element, _path, acc ->
          {element, acc}
        end)
        |> Enum.to_list()

      # Should emit an error event for the unknown event
      assert Enum.any?(result, fn
               {:error, :validation, msg} ->
                 String.contains?(msg, "unknown event type")

               _ ->
                 false
             end)
    end

    test "event_mode: :pass is the default when no option specified" do
      stream = [
        {:start_element, "root", [], 1, 0, 1},
        {:custom_event, "data", :metadata},
        {:end_element, "root", 1, 0, 15}
      ]

      # No event_mode option specified - should default to :pass
      result =
        Event.transform(stream, [], fn element, _path, acc ->
          {element, acc}
        end)
        |> Enum.to_list()

      # Should include the custom event (passes through to callback)
      assert Enum.any?(result, &match?({:custom_event, "data", :metadata}, &1))
    end

    test "known events are always processed regardless of event_mode" do
      stream = [
        {:start_element, "root", [], 1, 0, 1},
        {:characters, "text", 1, 0, 7},
        {:comment, "comment", 1, 0, 11},
        {:cdata, "data", 1, 0, 22},
        {:end_element, "root", 1, 0, 30}
      ]

      for mode <- [:pass, :discard, :strict] do
        result =
          Event.transform(stream, [], [event_mode: mode], fn element, _path, acc ->
            {element, acc}
          end)
          |> Enum.to_list()

        # All known events should be present
        assert Enum.any?(result, &match?({:start_element, "root", _, _, _, _}, &1)),
               "mode #{mode} should process start_element"

        assert Enum.any?(result, &match?({:characters, "text", _, _, _}, &1)),
               "mode #{mode} should process characters"

        assert Enum.any?(result, &match?({:comment, "comment", _, _, _}, &1)),
               "mode #{mode} should process comment"

        assert Enum.any?(result, &match?({:cdata, "data", _, _, _}, &1)),
               "mode #{mode} should process cdata"

        assert Enum.any?(result, &match?({:end_element, "root", _, _, _}, &1)),
               "mode #{mode} should process end_element"
      end
    end

    test "document markers are processed in all event_mode settings" do
      stream = [
        {:start_document, nil},
        {:start_element, "root", [], 1, 0, 1},
        {:end_element, "root", 1, 0, 7},
        {:end_document, nil}
      ]

      for mode <- [:pass, :discard, :strict] do
        result =
          Event.transform(stream, [], [event_mode: mode], fn element, _path, acc ->
            {element, acc}
          end)
          |> Enum.to_list()

        # Document markers should always pass through
        assert {:start_document, nil} in result, "mode #{mode} should process start_document"
        assert {:end_document, nil} in result, "mode #{mode} should process end_document"
      end
    end

    test "event_mode affects only unknown events, not validation errors" do
      # Mismatched closing tag should produce validation error regardless of mode
      stream = [
        {:start_element, "foo", [], 1, 0, 1},
        {:end_element, "bar", 1, 0, 10}
      ]

      for mode <- [:pass, :discard, :strict] do
        result =
          Event.transform(stream, [], [event_mode: mode], fn element, _path, acc ->
            {element, acc}
          end)
          |> Enum.to_list()

        # Should emit validation error in all modes
        assert Enum.any?(result, fn
                 {:error, :validation, msg, _, _, _} ->
                   String.contains?(msg, "mis-matched close tag")

                 _ ->
                   false
               end),
               "mode #{mode} should emit validation errors"
      end
    end

    test "event_mode: :discard does not call callback for unknown events" do
      test_pid = self()

      stream = [
        {:start_element, "root", [], 1, 0, 1},
        {:custom_event, "should_not_see", :metadata},
        {:end_element, "root", 1, 0, 15}
      ]

      Event.transform(stream, [], [event_mode: :discard], fn element, _path, acc ->
        send(test_pid, {:callback, element})
        {element, acc}
      end)
      |> Enum.to_list()

      # Should receive callbacks for known events
      assert_received {:callback, {:start_element, "root", _, _, _, _}}
      assert_received {:callback, {:end_element, "root", _, _, _}}

      # Should NOT receive callback for custom event
      refute_received {:callback, {:custom_event, "should_not_see", :metadata}}
    end
  end
end
