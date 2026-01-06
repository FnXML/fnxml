defmodule FnXML.ErrorTest do
  use ExUnit.Case, async: true

  alias FnXML.Error

  describe "parse_error/5" do
    test "creates error with all fields" do
      error = Error.parse_error(:invalid_tag_name, "Bad tag", 5, 10, %{near: "..."})

      assert error.type == :invalid_tag_name
      assert error.message == "Bad tag"
      assert error.line == 5
      assert error.column == 10
      assert error.context == %{near: "..."}
    end

    test "creates error with minimal fields" do
      error = Error.parse_error(:parse_error, "Something went wrong")

      assert error.type == :parse_error
      assert error.message == "Something went wrong"
      assert error.line == nil
      assert error.column == nil
    end
  end

  describe "tag_mismatch/3" do
    test "creates tag mismatch error with tuple location" do
      error = Error.tag_mismatch("expected", "got", {5, 10})

      assert error.type == :tag_mismatch
      assert error.message == "Expected </expected>, got </got>"
      assert error.line == 5
      assert error.column == 10
      assert error.context == %{expected: "expected", got: "got"}
    end
  end

  describe "unexpected_close/2" do
    test "creates unexpected close error" do
      error = Error.unexpected_close("orphan", {3, 5})

      assert error.type == :unexpected_close
      assert error.message =~ "orphan"
      assert error.message =~ "no matching"
      assert error.line == 3
      assert error.column == 5
    end
  end

  describe "duplicate_attribute/2" do
    test "creates duplicate attribute error" do
      error = Error.duplicate_attribute("id", {7, 15})

      assert error.type == :duplicate_attr
      assert error.message =~ "Duplicate"
      assert error.message =~ "id"
      assert error.line == 7
      assert error.column == 15
    end
  end

  describe "undeclared_namespace/2" do
    test "creates undeclared namespace error" do
      error = Error.undeclared_namespace("ns", {2, 8})

      assert error.type == :undeclared_namespace
      assert error.message =~ "Undeclared"
      assert error.message =~ "ns"
      assert error.line == 2
      assert error.column == 8
    end
  end

  describe "format_context/4" do
    test "shows surrounding lines with pointer" do
      source = """
      <root>
        <child>
          <bad!tag/>
        </child>
      </root>
      """

      context = Error.format_context(source, 3, 8)

      assert context =~ ">> "
      assert context =~ "bad!tag"
      assert context =~ "^"
    end

    test "handles single line" do
      source = "<bad!>"
      context = Error.format_context(source, 1, 5)

      assert context =~ ">> "
      assert context =~ "^"
    end

    test "handles error at start of file" do
      source = "!invalid\n<root/>"
      context = Error.format_context(source, 1, 1)

      assert context =~ ">> "
      assert context =~ "!invalid"
    end
  end

  describe "format/2" do
    test "formats error without source" do
      error = Error.parse_error(:parse_error, "Something failed", 5, 10)
      formatted = Error.format(error)

      assert formatted =~ "[parse_error]"
      assert formatted =~ "Something failed"
      assert formatted =~ "line 5"
      assert formatted =~ "column 10"
    end

    test "formats error with source context" do
      source = "<root>\n  <bad!>\n</root>"
      error = Error.parse_error(:invalid_tag_name, "Bad tag", 2, 7)
      formatted = Error.format(error, source)

      assert formatted =~ "[invalid_tag_name]"
      assert formatted =~ "Bad tag"
      assert formatted =~ "<bad!>"
    end

    test "handles nil location" do
      error = Error.parse_error(:parse_error, "Error")
      formatted = Error.format(error)

      assert formatted =~ "[parse_error]"
      refute formatted =~ "line"
    end
  end

  describe "Exception.message/1" do
    test "works with raise" do
      error = Error.parse_error(:parse_error, "Test error", 1, 1)

      assert_raise FnXML.Error, ~r/Test error/, fn ->
        raise error
      end
    end
  end
end
