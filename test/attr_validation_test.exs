defmodule FnXML.AttrValidationTest do
  use ExUnit.Case, async: true

  describe "< in attribute values" do
    # Note: The parser is lenient and accepts < in attribute values.
    # Per XML spec, < should be escaped as &lt; in attribute values,
    # but this parser does not enforce this constraint.
    test "parser accepts < in attribute value (lenient mode)" do
      result = FnXML.Parser.parse(~s(<a b="<"/>)) |> Enum.to_list()

      # Parser stores the < as-is in the attribute value
      assert Enum.any?(result, fn
               {:start_element, "a", [{"b", "<"}], _, _, _} -> true
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
