defmodule FnXML.Event.Preprocess.Utf16Test do
  use ExUnit.Case, async: true

  alias FnXML.Event.Preprocess.Utf16

  describe "detect_encoding/1" do
    test "detects UTF-16 LE BOM" do
      assert {:utf16_le, <<0x3C, 0x00>>} = Utf16.detect_encoding(<<0xFF, 0xFE, 0x3C, 0x00>>)
    end

    test "detects UTF-16 BE BOM" do
      assert {:utf16_be, <<0x00, 0x3C>>} = Utf16.detect_encoding(<<0xFE, 0xFF, 0x00, 0x3C>>)
    end

    test "detects UTF-8 BOM" do
      assert {:utf8, "<"} = Utf16.detect_encoding(<<0xEF, 0xBB, 0xBF, 0x3C>>)
    end

    test "defaults to UTF-8 without BOM" do
      assert {:utf8, "<xml"} = Utf16.detect_encoding("<xml")
    end

    test "handles empty binary" do
      assert {:utf8, ""} = Utf16.detect_encoding("")
    end
  end

  describe "to_utf8/1 with binary input" do
    test "passes through UTF-8 unchanged" do
      assert Utf16.to_utf8("<root/>") == "<root/>"
    end

    test "strips UTF-8 BOM" do
      assert Utf16.to_utf8(<<0xEF, 0xBB, 0xBF, "<root/>">>) == "<root/>"
    end

    test "converts UTF-16 LE with BOM" do
      {:ok, utf16_le} = utf8_to_utf16("<a/>", :little)
      utf16_with_bom = <<0xFF, 0xFE>> <> utf16_le

      assert Utf16.to_utf8(utf16_with_bom) == "<a/>"
    end

    test "converts UTF-16 BE with BOM" do
      {:ok, utf16_be} = utf8_to_utf16("<a/>", :big)
      utf16_with_bom = <<0xFE, 0xFF>> <> utf16_be

      assert Utf16.to_utf8(utf16_with_bom) == "<a/>"
    end

    test "converts UTF-16 with non-ASCII characters" do
      {:ok, utf16_le} = utf8_to_utf16("<price>€100</price>", :little)
      utf16_with_bom = <<0xFF, 0xFE>> <> utf16_le

      assert Utf16.to_utf8(utf16_with_bom) == "<price>€100</price>"
    end
  end

  describe "to_utf8/2 with explicit encoding" do
    test "converts known UTF-16 LE without BOM" do
      {:ok, utf16_le} = utf8_to_utf16("<a/>", :little)

      assert Utf16.to_utf8(utf16_le, encoding: :utf16_le) == "<a/>"
    end

    test "converts known UTF-16 BE without BOM" do
      {:ok, utf16_be} = utf8_to_utf16("<a/>", :big)

      assert Utf16.to_utf8(utf16_be, encoding: :utf16_be) == "<a/>"
    end

    test "passes through with utf8 encoding" do
      assert Utf16.to_utf8("<root/>", encoding: :utf8) == "<root/>"
    end
  end

  describe "to_utf8/1 with stream input" do
    test "passes through UTF-8 unchanged" do
      chunks = ["<root>", "content", "</root>"]

      result =
        chunks
        |> Stream.map(& &1)
        |> Utf16.to_utf8()
        |> Enum.to_list()

      assert result == chunks
    end

    test "strips UTF-8 BOM from first chunk" do
      chunks = [<<0xEF, 0xBB, 0xBF, "<root>">>, "</root>"]

      result =
        chunks
        |> Stream.map(& &1)
        |> Utf16.to_utf8()
        |> Enum.to_list()

      assert result == ["<root>", "</root>"]
    end

    test "converts UTF-16 LE stream" do
      # BOM + "<a>" in UTF-16 LE
      utf16_chunk = <<0xFF, 0xFE, 0x3C, 0x00, 0x61, 0x00, 0x3E, 0x00>>

      result =
        [utf16_chunk]
        |> Stream.map(& &1)
        |> Utf16.to_utf8()
        |> Enum.to_list()

      assert result == ["<a>"]
    end

    test "converts UTF-16 BE stream" do
      # BOM + "<a>" in UTF-16 BE
      utf16_chunk = <<0xFE, 0xFF, 0x00, 0x3C, 0x00, 0x61, 0x00, 0x3E>>

      result =
        [utf16_chunk]
        |> Stream.map(& &1)
        |> Utf16.to_utf8()
        |> Enum.to_list()

      assert result == ["<a>"]
    end

    test "converts multiple UTF-16 LE chunks" do
      # BOM + "<root>" in UTF-16 LE
      chunk1 =
        <<0xFF, 0xFE, 0x3C, 0x00, 0x72, 0x00, 0x6F, 0x00, 0x6F, 0x00, 0x74, 0x00, 0x3E, 0x00>>

      # "</root>" in UTF-16 LE (no BOM)
      chunk2 =
        <<0x3C, 0x00, 0x2F, 0x00, 0x72, 0x00, 0x6F, 0x00, 0x6F, 0x00, 0x74, 0x00, 0x3E, 0x00>>

      result =
        [chunk1, chunk2]
        |> Stream.map(& &1)
        |> Utf16.to_utf8()
        |> Enum.to_list()

      assert result == ["<root>", "</root>"]
    end

    test "handles chunk boundary in middle of UTF-16 character" do
      # BOM + "<" split: first byte of 'a'
      chunk1 = <<0xFF, 0xFE, 0x3C, 0x00, 0x61>>
      # Second byte of 'a' + ">"
      chunk2 = <<0x00, 0x3E, 0x00>>

      result =
        [chunk1, chunk2]
        |> Stream.map(& &1)
        |> Utf16.to_utf8()
        |> Enum.to_list()

      assert Enum.join(result) == "<a>"
    end
  end

  describe "to_utf8/2 with stream and explicit encoding" do
    test "converts known UTF-16 LE stream without BOM" do
      # "<a>" in UTF-16 LE (no BOM)
      utf16_chunk = <<0x3C, 0x00, 0x61, 0x00, 0x3E, 0x00>>

      result =
        [utf16_chunk]
        |> Stream.map(& &1)
        |> Utf16.to_utf8(encoding: :utf16_le)
        |> Enum.to_list()

      assert result == ["<a>"]
    end

    test "converts known UTF-16 BE stream without BOM" do
      # "<a>" in UTF-16 BE (no BOM)
      utf16_chunk = <<0x00, 0x3C, 0x00, 0x61, 0x00, 0x3E>>

      result =
        [utf16_chunk]
        |> Stream.map(& &1)
        |> Utf16.to_utf8(encoding: :utf16_be)
        |> Enum.to_list()

      assert result == ["<a>"]
    end

    test "passes through UTF-8 stream unchanged" do
      chunks = ["<a>", "</a>"]

      result =
        chunks
        |> Stream.map(& &1)
        |> Utf16.to_utf8(encoding: :utf8)
        |> Enum.to_list()

      assert result == chunks
    end
  end

  describe "integration with FnXML.Parser (binary)" do
    test "parses UTF-16 LE XML" do
      {:ok, utf16_le} = utf8_to_utf16("<root>hello</root>", :little)
      utf16_with_bom = <<0xFF, 0xFE>> <> utf16_le

      events =
        utf16_with_bom
        |> Utf16.to_utf8()
        |> FnXML.Parser.parse()
        |> Enum.to_list()

      # Parser outputs 5-tuple: {:characters, content, line, ls, pos}
      assert Enum.any?(events, &match?({:characters, "hello", _, _, _}, &1))
    end

    test "parses UTF-16 with special characters" do
      {:ok, utf16_le} = utf8_to_utf16("<price>€100</price>", :little)
      utf16_with_bom = <<0xFF, 0xFE>> <> utf16_le

      events =
        utf16_with_bom
        |> Utf16.to_utf8()
        |> FnXML.Parser.parse()
        |> Enum.to_list()

      # Parser outputs 5-tuple: {:characters, content, line, ls, pos}
      text_event = Enum.find(events, &match?({:characters, _, _, _, _}, &1))
      assert {:characters, "€100", _, _, _} = text_event
    end
  end

  # Note: FnXML.ParserStream has been consolidated into FnXML.Parser
  # Stream parsing now uses FnXML.Parser.parse/1 directly

  describe "parser error on UTF-16 (without conversion)" do
    test "FnXML.Parser emits error for UTF-16 LE" do
      {:ok, utf16_le} = utf8_to_utf16("<root/>", :little)
      utf16_with_bom = <<0xFF, 0xFE>> <> utf16_le

      events = FnXML.Parser.parse(utf16_with_bom) |> Enum.to_list()
      assert Enum.any?(events, &match?({:error, :utf16, _, _, _, _}, &1))
    end

    test "FnXML.Parser emits error for UTF-16 BE" do
      {:ok, utf16_be} = utf8_to_utf16("<root/>", :big)
      utf16_with_bom = <<0xFE, 0xFF>> <> utf16_be

      events = FnXML.Parser.parse(utf16_with_bom) |> Enum.to_list()
      assert Enum.any?(events, &match?({:error, :utf16, _, _, _, _}, &1))
    end
  end

  # Helper to convert UTF-8 to UTF-16 for testing
  defp utf8_to_utf16(utf8_string, endianness) do
    encoding = {:utf16, endianness}

    case :unicode.characters_to_binary(utf8_string, :utf8, encoding) do
      result when is_binary(result) -> {:ok, result}
      _ -> {:error, "Conversion failed"}
    end
  end
end
