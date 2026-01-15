defmodule FnXML.XsTypesTest do
  use ExUnit.Case, async: true

  alias FnXML.XsTypes
  alias FnXML.XsTypes.{Hierarchy, Facets}

  describe "validate/2" do
    test "validates string type" do
      assert :ok = XsTypes.validate("hello", :string)
      assert :ok = XsTypes.validate("", :string)
      assert :ok = XsTypes.validate("hello\nworld", :string)
    end

    test "validates boolean type" do
      assert :ok = XsTypes.validate("true", :boolean)
      assert :ok = XsTypes.validate("false", :boolean)
      assert :ok = XsTypes.validate("1", :boolean)
      assert :ok = XsTypes.validate("0", :boolean)
      assert {:error, _} = XsTypes.validate("yes", :boolean)
      assert {:error, _} = XsTypes.validate("TRUE", :boolean)
    end

    test "validates integer type" do
      assert :ok = XsTypes.validate("42", :integer)
      assert :ok = XsTypes.validate("-42", :integer)
      assert :ok = XsTypes.validate("0", :integer)
      assert {:error, _} = XsTypes.validate("3.14", :integer)
      assert {:error, _} = XsTypes.validate("abc", :integer)
    end

    test "validates bounded integer types" do
      assert :ok = XsTypes.validate("100", :byte)
      assert {:error, _} = XsTypes.validate("200", :byte)
      assert :ok = XsTypes.validate("30000", :short)
      assert {:error, _} = XsTypes.validate("40000", :short)
    end

    test "validates unsigned integer types" do
      assert :ok = XsTypes.validate("255", :unsignedByte)
      assert {:error, _} = XsTypes.validate("-1", :unsignedByte)
      assert :ok = XsTypes.validate("100", :positiveInteger)
      assert {:error, _} = XsTypes.validate("0", :positiveInteger)
    end

    test "validates decimal type" do
      assert :ok = XsTypes.validate("3.14159", :decimal)
      assert :ok = XsTypes.validate("-100.5", :decimal)
      assert :ok = XsTypes.validate("42", :decimal)
      assert {:error, _} = XsTypes.validate("abc", :decimal)
    end

    test "validates float/double types" do
      assert :ok = XsTypes.validate("3.14", :float)
      assert :ok = XsTypes.validate("INF", :float)
      assert :ok = XsTypes.validate("-INF", :float)
      assert :ok = XsTypes.validate("NaN", :float)
      assert :ok = XsTypes.validate("1.5e10", :double)
    end

    test "validates date type" do
      assert :ok = XsTypes.validate("2024-01-15", :date)
      assert :ok = XsTypes.validate("2024-01-15Z", :date)
      assert :ok = XsTypes.validate("2024-01-15+05:30", :date)
      assert {:error, _} = XsTypes.validate("01-15-2024", :date)
    end

    test "validates time type" do
      assert :ok = XsTypes.validate("14:30:00", :time)
      assert :ok = XsTypes.validate("14:30:00.123", :time)
      assert :ok = XsTypes.validate("14:30:00Z", :time)
      assert {:error, _} = XsTypes.validate("2:30 PM", :time)
    end

    test "validates dateTime type" do
      assert :ok = XsTypes.validate("2024-01-15T14:30:00", :dateTime)
      assert :ok = XsTypes.validate("2024-01-15T14:30:00Z", :dateTime)
      assert :ok = XsTypes.validate("2024-01-15T14:30:00+05:30", :dateTime)
      assert {:error, _} = XsTypes.validate("2024-01-15 14:30:00", :dateTime)
    end

    test "validates duration type" do
      assert :ok = XsTypes.validate("P1Y2M3D", :duration)
      assert :ok = XsTypes.validate("PT1H30M", :duration)
      assert :ok = XsTypes.validate("P1Y2M3DT4H5M6S", :duration)
      assert :ok = XsTypes.validate("-P1D", :duration)
      assert {:error, _} = XsTypes.validate("P", :duration)
    end

    test "validates hexBinary type" do
      assert :ok = XsTypes.validate("48656C6C6F", :hexBinary)
      assert :ok = XsTypes.validate("", :hexBinary)
      assert {:error, _} = XsTypes.validate("48656C6C6", :hexBinary)
    end

    test "validates base64Binary type" do
      assert :ok = XsTypes.validate("SGVsbG8=", :base64Binary)
      assert :ok = XsTypes.validate("", :base64Binary)
      assert {:error, _} = XsTypes.validate("not-valid-base64!", :base64Binary)
    end

    test "validates token type" do
      assert :ok = XsTypes.validate("hello world", :token)
      assert {:error, _} = XsTypes.validate(" hello", :token)
      assert {:error, _} = XsTypes.validate("hello ", :token)
      assert {:error, _} = XsTypes.validate("hello  world", :token)
    end

    test "validates NCName type" do
      assert :ok = XsTypes.validate("validName", :NCName)
      assert :ok = XsTypes.validate("_underscore", :NCName)
      assert {:error, _} = XsTypes.validate("invalid:name", :NCName)
      assert {:error, _} = XsTypes.validate("123invalid", :NCName)
    end
  end

  describe "parse/2" do
    test "parses string types" do
      assert {:ok, "hello"} = XsTypes.parse("hello", :string)
    end

    test "parses boolean type" do
      assert {:ok, true} = XsTypes.parse("true", :boolean)
      assert {:ok, true} = XsTypes.parse("1", :boolean)
      assert {:ok, false} = XsTypes.parse("false", :boolean)
      assert {:ok, false} = XsTypes.parse("0", :boolean)
    end

    test "parses integer types" do
      assert {:ok, 42} = XsTypes.parse("42", :integer)
      assert {:ok, -100} = XsTypes.parse("-100", :int)
      assert {:ok, 255} = XsTypes.parse("255", :unsignedByte)
    end

    test "parses float/double types" do
      assert {:ok, 3.14} = XsTypes.parse("3.14", :float)
      assert {:ok, :infinity} = XsTypes.parse("INF", :double)
      assert {:ok, :neg_infinity} = XsTypes.parse("-INF", :double)
      assert {:ok, :nan} = XsTypes.parse("NaN", :float)
    end

    test "parses date type" do
      assert {:ok, ~D[2024-01-15]} = XsTypes.parse("2024-01-15", :date)
    end

    test "parses time type" do
      assert {:ok, ~T[14:30:00]} = XsTypes.parse("14:30:00", :time)
    end

    test "parses dateTime type" do
      {:ok, result} = XsTypes.parse("2024-01-15T14:30:00", :dateTime)
      assert %NaiveDateTime{} = result

      {:ok, result_utc} = XsTypes.parse("2024-01-15T14:30:00Z", :dateTime)
      assert %DateTime{} = result_utc
    end

    test "parses duration type" do
      {:ok, result} = XsTypes.parse("P1Y2M3D", :duration)
      assert result[:years] == 1
      assert result[:months] == 2
      assert result[:days] == 3
    end

    test "parses hexBinary type" do
      assert {:ok, "Hello"} = XsTypes.parse("48656C6C6F", :hexBinary)
    end

    test "parses base64Binary type" do
      assert {:ok, "Hello"} = XsTypes.parse("SGVsbG8=", :base64Binary)
    end

    test "parses QName type" do
      assert {:ok, {"xs", "string"}} = XsTypes.parse("xs:string", :QName)
      assert {:ok, {nil, "localName"}} = XsTypes.parse("localName", :QName)
    end

    test "parses list types" do
      assert {:ok, ["a", "b", "c"]} = XsTypes.parse("a b c", :NMTOKENS)
      assert {:ok, ["id1", "id2"]} = XsTypes.parse("id1 id2", :IDREFS)
    end
  end

  describe "encode/2" do
    test "encodes string types" do
      assert {:ok, "hello"} = XsTypes.encode("hello", :string)
    end

    test "encodes boolean type" do
      assert {:ok, "true"} = XsTypes.encode(true, :boolean)
      assert {:ok, "false"} = XsTypes.encode(false, :boolean)
    end

    test "encodes integer types" do
      assert {:ok, "42"} = XsTypes.encode(42, :integer)
      assert {:ok, "-100"} = XsTypes.encode(-100, :int)
    end

    test "encodes float/double types" do
      assert {:ok, "INF"} = XsTypes.encode(:infinity, :double)
      assert {:ok, "-INF"} = XsTypes.encode(:neg_infinity, :double)
      assert {:ok, "NaN"} = XsTypes.encode(:nan, :float)
    end

    test "encodes date type" do
      assert {:ok, "2024-01-15"} = XsTypes.encode(~D[2024-01-15], :date)
    end

    test "encodes time type" do
      assert {:ok, "14:30:00"} = XsTypes.encode(~T[14:30:00], :time)
    end

    test "encodes hexBinary type" do
      assert {:ok, "48656C6C6F"} = XsTypes.encode("Hello", :hexBinary)
    end

    test "encodes base64Binary type" do
      assert {:ok, "SGVsbG8="} = XsTypes.encode("Hello", :base64Binary)
    end

    test "encodes QName type" do
      assert {:ok, "xs:string"} = XsTypes.encode({"xs", "string"}, :QName)
      assert {:ok, "localName"} = XsTypes.encode({nil, "localName"}, :QName)
    end

    test "encodes list types" do
      assert {:ok, "a b c"} = XsTypes.encode(["a", "b", "c"], :NMTOKENS)
    end

    test "encodes nil as empty string" do
      assert {:ok, ""} = XsTypes.encode(nil, :string)
      assert {:ok, ""} = XsTypes.encode(nil, :integer)
    end
  end

  describe "parse!/2 and encode!/2" do
    test "parse! returns value on success" do
      assert 42 = XsTypes.parse!("42", :integer)
    end

    test "parse! raises on error" do
      assert_raise ArgumentError, fn ->
        XsTypes.parse!("abc", :integer)
      end
    end

    test "encode! returns string on success" do
      assert "42" = XsTypes.encode!(42, :integer)
    end

    test "encode! raises on error" do
      assert_raise ArgumentError, fn ->
        XsTypes.encode!({:invalid}, :integer)
      end
    end
  end

  describe "infer_type/1" do
    test "infers string type" do
      assert :string = XsTypes.infer_type("hello")
    end

    test "infers boolean type" do
      assert :boolean = XsTypes.infer_type(true)
      assert :boolean = XsTypes.infer_type(false)
    end

    test "infers integer type" do
      assert :integer = XsTypes.infer_type(42)
    end

    test "infers double type" do
      assert :double = XsTypes.infer_type(3.14)
      assert :double = XsTypes.infer_type(:infinity)
      assert :double = XsTypes.infer_type(:nan)
    end

    test "infers date types" do
      assert :date = XsTypes.infer_type(~D[2024-01-15])
      assert :time = XsTypes.infer_type(~T[14:30:00])
      assert :dateTime = XsTypes.infer_type(~U[2024-01-15 14:30:00Z])
    end

    test "infers QName type" do
      assert :QName = XsTypes.infer_type({"xs", "string"})
      assert :QName = XsTypes.infer_type({nil, "local"})
    end

    test "infers anyURI type" do
      assert :anyURI = XsTypes.infer_type(%URI{})
    end
  end

  describe "normalize_whitespace/2" do
    test "preserves whitespace for string type" do
      assert "  hello\nworld  " = XsTypes.normalize_whitespace("  hello\nworld  ", :string)
    end

    test "replaces whitespace for normalizedString type" do
      assert "  hello world  " = XsTypes.normalize_whitespace("  hello\nworld  ", :normalizedString)
    end

    test "collapses whitespace for token type" do
      assert "hello world" = XsTypes.normalize_whitespace("  hello\n\nworld  ", :token)
    end
  end

  describe "normalize_type_name/1" do
    test "handles atoms" do
      assert :integer = XsTypes.normalize_type_name(:integer)
    end

    test "handles prefixed strings" do
      assert :integer = XsTypes.normalize_type_name("xs:integer")
      assert :string = XsTypes.normalize_type_name("xsd:string")
    end

    test "handles unprefixed strings" do
      assert :boolean = XsTypes.normalize_type_name("boolean")
    end
  end

  describe "validate_with_facets/3" do
    test "validates length facet" do
      assert :ok = XsTypes.validate_with_facets("hello", :string, [{:length, 5}])
      assert {:error, _} = XsTypes.validate_with_facets("hi", :string, [{:length, 5}])
    end

    test "validates minLength facet" do
      assert :ok = XsTypes.validate_with_facets("hello", :string, [{:minLength, 3}])
      assert {:error, _} = XsTypes.validate_with_facets("hi", :string, [{:minLength, 3}])
    end

    test "validates maxLength facet" do
      assert :ok = XsTypes.validate_with_facets("hi", :string, [{:maxLength, 5}])
      assert {:error, _} = XsTypes.validate_with_facets("hello world", :string, [{:maxLength, 5}])
    end

    test "validates pattern facet" do
      assert :ok = XsTypes.validate_with_facets("abc123", :string, [{:pattern, "[a-z]+[0-9]+"}])
      assert {:error, _} = XsTypes.validate_with_facets("123abc", :string, [{:pattern, "[a-z]+[0-9]+"}])
    end

    test "validates enumeration facet" do
      assert :ok = XsTypes.validate_with_facets("red", :string, [{:enumeration, ["red", "green", "blue"]}])
      assert {:error, _} = XsTypes.validate_with_facets("yellow", :string, [{:enumeration, ["red", "green", "blue"]}])
    end

    test "validates minInclusive facet" do
      assert :ok = XsTypes.validate_with_facets("50", :integer, [{:minInclusive, "0"}])
      assert {:error, _} = XsTypes.validate_with_facets("-1", :integer, [{:minInclusive, "0"}])
    end

    test "validates maxInclusive facet" do
      assert :ok = XsTypes.validate_with_facets("50", :integer, [{:maxInclusive, "100"}])
      assert {:error, _} = XsTypes.validate_with_facets("150", :integer, [{:maxInclusive, "100"}])
    end

    test "validates totalDigits facet" do
      assert :ok = XsTypes.validate_with_facets("123", :decimal, [{:totalDigits, 5}])
      assert {:error, _} = XsTypes.validate_with_facets("123456", :decimal, [{:totalDigits, 5}])
    end

    test "validates fractionDigits facet" do
      assert :ok = XsTypes.validate_with_facets("3.14", :decimal, [{:fractionDigits, 2}])
      assert {:error, _} = XsTypes.validate_with_facets("3.14159", :decimal, [{:fractionDigits, 2}])
    end

    test "validates multiple facets" do
      facets = [
        {:minLength, 1},
        {:maxLength, 10},
        {:pattern, "[a-z]+"}
      ]
      assert :ok = XsTypes.validate_with_facets("hello", :string, facets)
      assert {:error, _} = XsTypes.validate_with_facets("", :string, facets)
      assert {:error, _} = XsTypes.validate_with_facets("Hello123", :string, facets)
    end
  end

  describe "Hierarchy" do
    test "builtin_type?/1" do
      assert Hierarchy.builtin_type?(:string)
      assert Hierarchy.builtin_type?(:integer)
      refute Hierarchy.builtin_type?(:customType)
    end

    test "primitive_type?/1" do
      assert Hierarchy.primitive_type?(:string)
      assert Hierarchy.primitive_type?(:decimal)
      refute Hierarchy.primitive_type?(:integer)
    end

    test "derived_type?/1" do
      assert Hierarchy.derived_type?(:integer)
      assert Hierarchy.derived_type?(:token)
      refute Hierarchy.derived_type?(:string)
    end

    test "numeric_type?/1" do
      assert Hierarchy.numeric_type?(:decimal)
      assert Hierarchy.numeric_type?(:integer)
      assert Hierarchy.numeric_type?(:int)
      refute Hierarchy.numeric_type?(:string)
    end

    test "base_type/1" do
      assert :decimal = Hierarchy.base_type(:integer)
      assert :integer = Hierarchy.base_type(:long)
      assert :long = Hierarchy.base_type(:int)
      assert nil == Hierarchy.base_type(:string)
    end

    test "derived_from?/2" do
      assert Hierarchy.derived_from?(:int, :long)
      assert Hierarchy.derived_from?(:int, :integer)
      assert Hierarchy.derived_from?(:int, :decimal)
      refute Hierarchy.derived_from?(:int, :string)
    end

    test "primitive_base/1" do
      assert :decimal = Hierarchy.primitive_base(:int)
      assert :string = Hierarchy.primitive_base(:NCName)
      assert :string = Hierarchy.primitive_base(:string)
    end

    test "list_type?/1" do
      assert Hierarchy.list_type?(:NMTOKENS)
      assert Hierarchy.list_type?(:IDREFS)
      refute Hierarchy.list_type?(:NMTOKEN)
    end

    test "item_type/1" do
      assert :NMTOKEN = Hierarchy.item_type(:NMTOKENS)
      assert :IDREF = Hierarchy.item_type(:IDREFS)
      assert nil == Hierarchy.item_type(:string)
    end
  end

  describe "range/1" do
    test "returns correct ranges for bounded integer types" do
      assert {-128, 127} = XsTypes.range(:byte)
      assert {-32768, 32767} = XsTypes.range(:short)
      assert {0, 255} = XsTypes.range(:unsignedByte)
      assert {1, :infinity} = XsTypes.range(:positiveInteger)
    end

    test "returns nil for non-integer types" do
      assert nil == XsTypes.range(:string)
    end
  end

  describe "type_uri/1 and qualified_name/2" do
    test "type_uri returns full XSD URI" do
      assert "http://www.w3.org/2001/XMLSchema#integer" = XsTypes.type_uri(:integer)
    end

    test "qualified_name returns prefixed name" do
      assert "xs:integer" = XsTypes.qualified_name(:integer, "xs")
      assert "xsd:string" = XsTypes.qualified_name(:string, "xsd")
    end
  end

  describe "round-trip parsing and encoding" do
    test "integers round-trip correctly" do
      for value <- ["42", "-100", "0", "9999999999"] do
        assert {:ok, parsed} = XsTypes.parse(value, :integer)
        assert {:ok, ^value} = XsTypes.encode(parsed, :integer)
      end
    end

    test "booleans round-trip correctly" do
      assert {:ok, true} = XsTypes.parse("true", :boolean)
      assert {:ok, "true"} = XsTypes.encode(true, :boolean)
      assert {:ok, false} = XsTypes.parse("false", :boolean)
      assert {:ok, "false"} = XsTypes.encode(false, :boolean)
    end

    test "dates round-trip correctly" do
      assert {:ok, date} = XsTypes.parse("2024-01-15", :date)
      assert {:ok, "2024-01-15"} = XsTypes.encode(date, :date)
    end

    test "binary types round-trip correctly" do
      original = "Hello, World!"
      {:ok, hex} = XsTypes.encode(original, :hexBinary)
      {:ok, decoded} = XsTypes.parse(hex, :hexBinary)
      assert decoded == original

      {:ok, b64} = XsTypes.encode(original, :base64Binary)
      {:ok, decoded_b64} = XsTypes.parse(b64, :base64Binary)
      assert decoded_b64 == original
    end
  end

  # ===========================================================================
  # XPath Compatibility Tests
  # ===========================================================================

  describe "XPath type name normalization" do
    test "normalizes XPath underscore-style type names" do
      # Parse using XPath-style names
      assert {:ok, _} = XsTypes.parse("2024-01-15T14:30:00", :date_time)
      assert {:ok, _} = XsTypes.parse("http://example.com", :any_uri)
      assert {:ok, _} = XsTypes.parse("DEADBEEF", :hex_binary)
      assert {:ok, _} = XsTypes.parse("SGVsbG8=", :base64_binary)
      assert {:ok, _} = XsTypes.parse("2024-03", :g_year_month)
      assert {:ok, _} = XsTypes.parse("2024", :g_year)
      assert {:ok, _} = XsTypes.parse("--03", :g_month)
      assert {:ok, _} = XsTypes.parse("--03-15", :g_month_day)
      assert {:ok, _} = XsTypes.parse("---15", :g_day)
    end

    test "normalizes XPath-style duration subtype names" do
      assert {:ok, _} = XsTypes.parse("P1Y2M", :year_month_duration)
      assert {:ok, _} = XsTypes.parse("P1DT2H", :day_time_duration)
    end
  end

  describe "XPath infinity atom aliases" do
    test "infer_type recognizes both infinity conventions" do
      assert :double = XsTypes.infer_type(:infinity)
      assert :double = XsTypes.infer_type(:neg_infinity)
      assert :double = XsTypes.infer_type(:positive_infinity)
      assert :double = XsTypes.infer_type(:negative_infinity)
    end

    test "encode handles XPath infinity atoms" do
      assert {:ok, "INF"} = XsTypes.encode(:positive_infinity, :double)
      assert {:ok, "-INF"} = XsTypes.encode(:negative_infinity, :double)
      assert {:ok, "INF"} = XsTypes.encode(:infinity, :double)
      assert {:ok, "-INF"} = XsTypes.encode(:neg_infinity, :double)
    end
  end

  describe "yearMonthDuration type" do
    test "validates yearMonthDuration" do
      assert :ok = XsTypes.validate("P1Y", :yearMonthDuration)
      assert :ok = XsTypes.validate("P2M", :yearMonthDuration)
      assert :ok = XsTypes.validate("P1Y2M", :yearMonthDuration)
      assert :ok = XsTypes.validate("-P1Y2M", :yearMonthDuration)
      assert {:error, _} = XsTypes.validate("P", :yearMonthDuration)
      assert {:error, _} = XsTypes.validate("P1D", :yearMonthDuration)
      assert {:error, _} = XsTypes.validate("PT1H", :yearMonthDuration)
    end

    test "parses yearMonthDuration to map" do
      assert {:ok, %{years: 1}} = XsTypes.parse("P1Y", :yearMonthDuration)
      assert {:ok, %{months: 2}} = XsTypes.parse("P2M", :yearMonthDuration)
      assert {:ok, %{years: 1, months: 2}} = XsTypes.parse("P1Y2M", :yearMonthDuration)
      assert {:ok, %{negative: true, years: 1, months: 2}} = XsTypes.parse("-P1Y2M", :yearMonthDuration)
    end

    test "encodes yearMonthDuration from map" do
      assert {:ok, "P1Y"} = XsTypes.encode(%{years: 1}, :yearMonthDuration)
      assert {:ok, "P2M"} = XsTypes.encode(%{months: 2}, :yearMonthDuration)
      assert {:ok, "P1Y2M"} = XsTypes.encode(%{years: 1, months: 2}, :yearMonthDuration)
      assert {:ok, "-P1Y2M"} = XsTypes.encode(%{negative: true, years: 1, months: 2}, :yearMonthDuration)
    end
  end

  describe "dayTimeDuration type" do
    test "validates dayTimeDuration" do
      assert :ok = XsTypes.validate("P1D", :dayTimeDuration)
      assert :ok = XsTypes.validate("PT1H", :dayTimeDuration)
      assert :ok = XsTypes.validate("PT30M", :dayTimeDuration)
      assert :ok = XsTypes.validate("PT45S", :dayTimeDuration)
      assert :ok = XsTypes.validate("P1DT2H30M45S", :dayTimeDuration)
      assert :ok = XsTypes.validate("-P1DT2H", :dayTimeDuration)
      assert {:error, _} = XsTypes.validate("P", :dayTimeDuration)
      assert {:error, _} = XsTypes.validate("PT", :dayTimeDuration)
      assert {:error, _} = XsTypes.validate("P1Y", :dayTimeDuration)
      assert {:error, _} = XsTypes.validate("P1M", :dayTimeDuration)
    end

    test "parses dayTimeDuration to map" do
      assert {:ok, %{days: 1}} = XsTypes.parse("P1D", :dayTimeDuration)
      assert {:ok, %{hours: 2}} = XsTypes.parse("PT2H", :dayTimeDuration)
      assert {:ok, %{minutes: 30}} = XsTypes.parse("PT30M", :dayTimeDuration)
      assert {:ok, %{seconds: 45.0}} = XsTypes.parse("PT45S", :dayTimeDuration)
      assert {:ok, %{days: 1, hours: 2, minutes: 30, seconds: 45.0}} = XsTypes.parse("P1DT2H30M45S", :dayTimeDuration)
      assert {:ok, %{negative: true, days: 1, hours: 2}} = XsTypes.parse("-P1DT2H", :dayTimeDuration)
    end

    test "encodes dayTimeDuration from map" do
      assert {:ok, "P1D"} = XsTypes.encode(%{days: 1}, :dayTimeDuration)
      assert {:ok, "PT2H"} = XsTypes.encode(%{hours: 2}, :dayTimeDuration)
      assert {:ok, "P1DT2H30M45.0S"} = XsTypes.encode(%{days: 1, hours: 2, minutes: 30, seconds: 45.0}, :dayTimeDuration)
      assert {:ok, "-P1DT2H"} = XsTypes.encode(%{negative: true, days: 1, hours: 2}, :dayTimeDuration)
    end
  end

  describe "duration type hierarchy" do
    test "yearMonthDuration and dayTimeDuration are derived from duration" do
      assert Hierarchy.derived_type?(:yearMonthDuration)
      assert Hierarchy.derived_type?(:dayTimeDuration)
      assert :duration = Hierarchy.base_type(:yearMonthDuration)
      assert :duration = Hierarchy.base_type(:dayTimeDuration)
      assert Hierarchy.derived_from?(:yearMonthDuration, :duration)
      assert Hierarchy.derived_from?(:dayTimeDuration, :duration)
    end

    test "duration subtypes are classified as date_time_types" do
      assert Hierarchy.date_time_type?(:yearMonthDuration)
      assert Hierarchy.date_time_type?(:dayTimeDuration)
    end
  end

  describe "parse_to_map/2 for Gregorian types" do
    alias FnXML.XsTypes.Primitive

    test "parses gYearMonth to map" do
      assert {:ok, %{year: 2024, month: 3}} = Primitive.parse_to_map("2024-03", :gYearMonth)
      assert {:ok, %{year: -500, month: 1}} = Primitive.parse_to_map("-0500-01", :gYearMonth)
    end

    test "parses gYear to map" do
      assert {:ok, %{year: 2024}} = Primitive.parse_to_map("2024", :gYear)
      assert {:ok, %{year: -500}} = Primitive.parse_to_map("-0500", :gYear)
    end

    test "parses gMonthDay to map" do
      assert {:ok, %{month: 12, day: 25}} = Primitive.parse_to_map("--12-25", :gMonthDay)
      assert {:ok, %{month: 1, day: 1}} = Primitive.parse_to_map("--01-01", :gMonthDay)
    end

    test "parses gDay to map" do
      assert {:ok, %{day: 15}} = Primitive.parse_to_map("---15", :gDay)
      assert {:ok, %{day: 1}} = Primitive.parse_to_map("---01", :gDay)
    end

    test "parses gMonth to map" do
      assert {:ok, %{month: 3}} = Primitive.parse_to_map("--03", :gMonth)
      assert {:ok, %{month: 12}} = Primitive.parse_to_map("--12", :gMonth)
    end

    test "falls back to regular parse for primitive types" do
      # parse_to_map falls back to Primitive.parse for non-Gregorian primitives
      assert {:ok, "hello"} = Primitive.parse_to_map("hello", :string)
      assert {:ok, true} = Primitive.parse_to_map("true", :boolean)
      assert {:ok, :infinity} = Primitive.parse_to_map("INF", :double)
    end
  end
end
