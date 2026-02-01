defmodule FnXML.Parser.EOFHandlingTest do
  use ExUnit.Case, async: true

  # Define a test parser
  defmodule TestParser do
    use FnXML.Parser.Generator, edition: 5
  end

  describe "EOF in comments" do
    test "emits comment content and error on EOF" do
      events = TestParser.parse("<root><!-- partial comment") |> Enum.to_list()
      assert Enum.any?(events, &match?({:comment, " partial comment", _, _, _}, &1))
      assert Enum.any?(events, &match?({:error, :eof_in_comment, _, _, _, _}, &1))
    end

    test "emits comment with -- on EOF and both errors" do
      events = TestParser.parse("<root><!-- has -- inside") |> Enum.to_list()
      assert Enum.any?(events, &match?({:comment, " has -- inside", _, _, _}, &1))
      # Error for double-dash in comment
      assert Enum.any?(events, &match?({:error, :comment, _, _, _, _}, &1))
      # Error for EOF
      assert Enum.any?(events, &match?({:error, :eof_in_comment, _, _, _, _}, &1))
    end

    test "emits comment ending with -- on EOF" do
      events = TestParser.parse("<root><!-- ends with dash--") |> Enum.to_list()

      assert Enum.any?(events, fn
               {:comment, content, _, _, _} -> String.contains?(content, "ends with dash")
               _ -> false
             end)

      assert Enum.any?(events, &match?({:error, :eof_in_comment, _, _, _, _}, &1))
    end

    test "emits comment ending with single dash on EOF" do
      events = TestParser.parse("<root><!-- ends with dash-") |> Enum.to_list()

      assert Enum.any?(events, fn
               {:comment, content, _, _, _} -> String.contains?(content, "ends with dash-")
               _ -> false
             end)

      assert Enum.any?(events, &match?({:error, :eof_in_comment, _, _, _, _}, &1))
    end

    test "emits empty comment on EOF" do
      events = TestParser.parse("<root><!--") |> Enum.to_list()
      assert Enum.any?(events, &match?({:comment, "", _, _, _}, &1))
      assert Enum.any?(events, &match?({:error, :eof_in_comment, _, _, _, _}, &1))
    end

    test "emits multiline comment on EOF" do
      events = TestParser.parse("<root><!-- line1\nline2") |> Enum.to_list()

      assert Enum.any?(events, fn
               {:comment, content, _, _, _} -> String.contains?(content, "line1\nline2")
               _ -> false
             end)

      assert Enum.any?(events, &match?({:error, :eof_in_comment, _, _, _, _}, &1))
    end
  end

  describe "EOF in CDATA" do
    test "emits CDATA content and error on EOF" do
      events = TestParser.parse("<root><![CDATA[partial cdata") |> Enum.to_list()
      assert Enum.any?(events, &match?({:cdata, "partial cdata", _, _, _}, &1))
      assert Enum.any?(events, &match?({:error, :eof_in_cdata, _, _, _, _}, &1))
    end

    test "emits CDATA with partial ] on EOF" do
      events = TestParser.parse("<root><![CDATA[content]") |> Enum.to_list()
      assert Enum.any?(events, &match?({:cdata, "content]", _, _, _}, &1))
      assert Enum.any?(events, &match?({:error, :eof_in_cdata, _, _, _, _}, &1))
    end

    test "emits CDATA with partial ]] on EOF" do
      events = TestParser.parse("<root><![CDATA[content]]") |> Enum.to_list()
      assert Enum.any?(events, &match?({:cdata, "content]]", _, _, _}, &1))
      assert Enum.any?(events, &match?({:error, :eof_in_cdata, _, _, _, _}, &1))
    end

    test "emits empty CDATA on EOF" do
      events = TestParser.parse("<root><![CDATA[") |> Enum.to_list()
      assert Enum.any?(events, &match?({:cdata, "", _, _, _}, &1))
      assert Enum.any?(events, &match?({:error, :eof_in_cdata, _, _, _, _}, &1))
    end

    test "emits CDATA with XML-like content on EOF" do
      events = TestParser.parse("<root><![CDATA[<tag>data</tag>") |> Enum.to_list()
      assert Enum.any?(events, &match?({:cdata, "<tag>data</tag>", _, _, _}, &1))
      assert Enum.any?(events, &match?({:error, :eof_in_cdata, _, _, _, _}, &1))
    end

    test "emits multiline CDATA on EOF" do
      events = TestParser.parse("<root><![CDATA[line1\nline2") |> Enum.to_list()

      assert Enum.any?(events, fn
               {:cdata, content, _, _, _} -> String.contains?(content, "line1\nline2")
               _ -> false
             end)

      assert Enum.any?(events, &match?({:error, :eof_in_cdata, _, _, _, _}, &1))
    end
  end

  describe "EOF in processing instructions" do
    test "emits PI content and error on EOF" do
      events = TestParser.parse("<?target partial data") |> Enum.to_list()

      assert Enum.any?(events, fn
               {:processing_instruction, "target", content, _, _, _} ->
                 String.contains?(content, "partial data")

               _ ->
                 false
             end)

      assert Enum.any?(events, &match?({:error, :eof_in_pi, _, _, _, _}, &1))
    end

    test "emits PI with partial ? on EOF" do
      events = TestParser.parse("<?target content?") |> Enum.to_list()

      assert Enum.any?(events, fn
               {:processing_instruction, "target", content, _, _, _} ->
                 String.ends_with?(content, "?")

               _ ->
                 false
             end)

      assert Enum.any?(events, &match?({:error, :eof_in_pi, _, _, _, _}, &1))
    end

    test "returns incomplete when EOF occurs during PI target name" do
      # When EOF occurs while still parsing the target name (no whitespace yet),
      # this is an incomplete parse in streaming mode
      {events, leftover, _line, _ls, _abs_pos} =
        FnXML.Parser.EOFHandlingTest.TestParser.parse_block("<?target", nil, 0, 1, 0, 0)

      assert events == []
      # Points to start of incomplete element
      assert leftover == 0
    end

    test "emits PI with single space content on EOF" do
      events = TestParser.parse("<?target ") |> Enum.to_list()

      assert Enum.any?(events, fn
               {:processing_instruction, "target", " ", _, _, _} -> true
               _ -> false
             end)

      assert Enum.any?(events, &match?({:error, :eof_in_pi, _, _, _, _}, &1))
    end

    test "emits PI with whitespace content on EOF" do
      events = TestParser.parse("<?target  ") |> Enum.to_list()

      assert Enum.any?(events, fn
               {:processing_instruction, "target", "  ", _, _, _} -> true
               _ -> false
             end)

      assert Enum.any?(events, &match?({:error, :eof_in_pi, _, _, _, _}, &1))
    end

    test "emits multiline PI on EOF" do
      events = TestParser.parse("<?target line1\nline2") |> Enum.to_list()

      assert Enum.any?(events, fn
               {:processing_instruction, "target", content, _, _, _} ->
                 String.contains?(content, "line1\nline2")

               _ ->
                 false
             end)

      assert Enum.any?(events, &match?({:error, :eof_in_pi, _, _, _, _}, &1))
    end

    test "emits PI with hyphenated target on EOF" do
      events = TestParser.parse("<?xml-stylesheet type=text") |> Enum.to_list()

      assert Enum.any?(events, fn
               {:processing_instruction, "xml-stylesheet", content, _, _, _} ->
                 String.contains?(content, "type=text")

               _ ->
                 false
             end)

      assert Enum.any?(events, &match?({:error, :eof_in_pi, _, _, _, _}, &1))
    end
  end
end
