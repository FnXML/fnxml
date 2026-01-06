defmodule FnXML.Parser.ErrorTransformTest do
  use ExUnit.Case, async: true

  alias FnXML.Parser.ErrorTransform

  describe "classify/2" do
    test "classifies element name errors from message" do
      raw = ~s(expected element name)
      # No context - falls back to message pattern
      {type, msg} = ErrorTransform.classify(raw, "valid")

      assert type == :invalid_tag_name
      assert msg =~ "tag name"
    end

    test "classifies invalid character from context" do
      raw = ~s(expected element name)
      # Context shows ! character - uses context-based classification
      {type, msg} = ErrorTransform.classify(raw, "!bad")

      assert type == :invalid_character
      assert msg =~ "!"
    end

    test "classifies digit at name start from context" do
      raw = ~s(expected letter, underscore, or colon)
      {type, msg} = ErrorTransform.classify(raw, "123")

      assert type == :invalid_name_start
      assert msg =~ "digit"
      assert msg =~ "1"
    end

    test "classifies unclosed bracket errors" do
      raw = ~s(expected '>')
      {type, msg} = ErrorTransform.classify(raw, "")

      assert type == :unclosed_bracket
      assert msg =~ ">"
    end

    test "classifies missing attribute value" do
      raw = ~s(expected attribute value)
      {type, msg} = ErrorTransform.classify(raw, "")

      assert type == :missing_attr_value
      assert msg =~ "attribute"
    end

    test "classifies unclosed CDATA" do
      raw = ~s(expected ']]>')
      {type, msg} = ErrorTransform.classify(raw, "")

      assert type == :unclosed_cdata
      assert msg =~ "CDATA"
    end

    test "classifies unclosed comment" do
      raw = ~s(expected '-->')
      {type, msg} = ErrorTransform.classify(raw, "")

      assert type == :unclosed_comment
      assert msg =~ "comment"
    end

    test "classifies unclosed processing instruction" do
      raw = ~s(expected '?>')
      {type, msg} = ErrorTransform.classify(raw, "")

      assert type == :unclosed_pi
      assert msg =~ "processing instruction"
    end

    test "unknown patterns get simplified fallback" do
      raw = "some unknown error format"
      {type, msg} = ErrorTransform.classify(raw, "")

      assert type == :parse_error
      assert is_binary(msg)
    end
  end

  describe "simplify_message/1" do
    test "simplifies ASCII character range descriptions" do
      raw = ~s(expected ASCII character in the range "a" to "z")
      simplified = ErrorTransform.simplify_message(raw)

      assert simplified =~ "a-z"
      refute simplified =~ "ASCII character in the range"
    end

    test "simplifies byte descriptions" do
      raw = ~s(expected byte equal to ?_)
      simplified = ErrorTransform.simplify_message(raw)

      assert simplified =~ "'_'"
      refute simplified =~ "byte equal to"
    end

    test "cleans up multiple 'or' chains" do
      raw = ~s(expected a or b or c or d)
      simplified = ErrorTransform.simplify_message(raw)

      assert simplified =~ "a, b, c, d"
      refute simplified =~ " or "
    end

    test "capitalizes expected" do
      raw = "expected something"
      simplified = ErrorTransform.simplify_message(raw)

      assert String.starts_with?(simplified, "Expected")
    end

    test "truncates overly long messages" do
      raw = String.duplicate("a", 200)
      simplified = ErrorTransform.simplify_message(raw)

      assert byte_size(simplified) <= 150
    end
  end

  describe "transform/4" do
    test "creates FnXML.Error struct" do
      # Use context that doesn't trigger context-based classification
      error = ErrorTransform.transform("expected element name", "valid_name", 5, 10)

      assert %FnXML.Error{} = error
      assert error.type == :invalid_tag_name
      assert error.line == 5
      assert error.column == 10
      assert is_map(error.context)
      assert error.context[:raw] == "expected element name"
    end

    test "creates error with context-based classification" do
      error = ErrorTransform.transform("expected element name", "!bad", 5, 10)

      assert %FnXML.Error{} = error
      assert error.type == :invalid_character
      assert error.message =~ "!"
      assert error.line == 5
      assert error.column == 10
    end

    test "extracts context from remaining input" do
      rest = "<remaining>content</remaining>"
      error = ErrorTransform.transform("expected something", rest, 1, 1)

      assert error.context[:near] =~ "<remaining>"
    end

    test "truncates long context" do
      rest = String.duplicate("x", 100)
      error = ErrorTransform.transform("expected something", rest, 1, 1)

      assert byte_size(error.context[:near]) <= 35
      assert error.context[:near] =~ "..."
    end
  end
end
