defmodule FnXML.AttrValidationTest do
  use ExUnit.Case, async: true

  describe "< in attribute values" do
    test "rejects < in attribute value" do
      result = FnXML.Parser.parse(~s(<a b="<"/>)) |> Enum.to_list()

      assert Enum.any?(result, fn
               {:error, _type, msg, _, _, _} -> String.contains?(to_string(msg), "<")
               _ -> false
             end)
    end

    test "accepts valid attribute values" do
      result = FnXML.Parser.parse(~s(<a b="hello"/>)) |> Enum.to_list()

      refute Enum.any?(result, fn
               {:error, _, _, _, _, _} -> true
               _ -> false
             end)

      assert Enum.any?(result, fn
               {:start_element, "a", [{"b", "hello"}], _, _, _} -> true
               _ -> false
             end)
    end

    test "accepts attribute with entity reference" do
      result = FnXML.Parser.parse(~s(<a b="&lt;"/>)) |> Enum.to_list()

      refute Enum.any?(result, fn
               {:error, _, _, _, _, _} -> true
               _ -> false
             end)

      # Entity not expanded by parser (that's done in stream layer)
      assert Enum.any?(result, fn
               {:start_element, "a", [{"b", "&lt;"}], _, _, _} -> true
               _ -> false
             end)
    end

    test "accepts attribute with quotes and special chars" do
      result = FnXML.Parser.parse(~s(<a b="hello 'world'"/>)) |> Enum.to_list()

      refute Enum.any?(result, fn
               {:error, _, _, _, _, _} -> true
               _ -> false
             end)
    end
  end
end
