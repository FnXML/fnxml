defmodule FnXML.ValidateCharsTest do
  use ExUnit.Case, async: true

  alias FnXML.Validate

  describe "comments/2" do
    test "passes valid comments through unchanged" do
      events = [
        {:start_document, nil},
        {:comment, " This is a valid comment ", 1, 0, 0},
        {:end_document, nil}
      ]

      result = events |> Validate.comments() |> Enum.to_list()

      assert result == events
    end

    test "allows single hyphens" do
      events = [
        {:start_document, nil},
        {:comment, " single - hyphen - ok ", 1, 0, 0},
        {:end_document, nil}
      ]

      result = events |> Validate.comments() |> Enum.to_list()

      refute Enum.any?(result, fn
               {:error, _, _} -> true
               _ -> false
             end)
    end

    test "detects double-hyphen in comment" do
      events = [
        {:start_document, nil},
        {:comment, " invalid -- comment ", 1, 0, 0},
        {:end_document, nil}
      ]

      result = events |> Validate.comments() |> Enum.to_list()

      assert Enum.any?(result, fn
               {:error, msg, _} -> String.contains?(msg, "--")
               _ -> false
             end)
    end

    test "detects double-hyphen at start" do
      events = [
        {:start_document, nil},
        {:comment, "-- at start", 1, 0, 0},
        {:end_document, nil}
      ]

      result = events |> Validate.comments() |> Enum.to_list()

      assert Enum.any?(result, fn
               {:error, msg, _} -> String.contains?(msg, "--")
               _ -> false
             end)
    end

    test "detects consecutive double-hyphens" do
      events = [
        {:start_document, nil},
        {:comment, " triple --- hyphen ", 1, 0, 0},
        {:end_document, nil}
      ]

      result = events |> Validate.comments() |> Enum.to_list()

      assert Enum.any?(result, fn
               {:error, msg, _} -> String.contains?(msg, "--")
               _ -> false
             end)
    end

    test "raise mode raises exception" do
      events = [
        {:start_document, nil},
        {:comment, " invalid -- comment ", 1, 0, 0},
        {:end_document, nil}
      ]

      assert_raise RuntimeError, ~r/--/, fn ->
        events |> Validate.comments(on_error: :raise) |> Enum.to_list()
      end
    end
  end
end
