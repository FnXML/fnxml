defmodule FnXML.Char do
  @moduledoc """
  XML Name character validation with support for Edition 4 and Edition 5.

  This module provides both guards (for use in pattern matching) and functions
  (for runtime validation) for XML character validation.

  ## Edition 5 (Default)
  Uses simplified, broad Unicode ranges from XML 1.0 Fifth Edition.
  More permissive - includes most Unicode characters.

  ## Edition 4
  Uses strict character class enumeration from XML 1.0 Fourth Edition Appendix B.
  Hybrid approach: inline checks for 1-byte chars, bitmap for 2-byte chars.

  ## Guards vs Functions

  Guards (`defguard`) can be used in pattern matching and function heads:

      import FnXML.Char

      defp parse_name(<<c::utf8, rest::binary>>) when is_name_start_ed5(c) do
        # ...
      end

  Functions are used for runtime validation:

      if FnXML.Char.name_start_char?(c, edition: 5) do
        # ...
      end

  ## Performance
  - Edition 5: O(1) with ~16 range comparisons
  - Edition 4: O(1) with enumerated range checks from XML 1.0 Fourth Edition Appendix B
  """

  # ===========================================================================
  # Public Guards - Importable for use in pattern matching
  # ===========================================================================

  @doc """
  Guard for valid XML character (same for both editions).

  Per XML spec production [2]:
  Char ::= #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
  """
  defguard is_xml_char(c)
           when c == 0x9 or c == 0xA or c == 0xD or
                  c in 0x20..0xD7FF or c in 0xE000..0xFFFD or
                  c in 0x10000..0x10FFFF

  @doc """
  Guard for ASCII name start characters (same for both editions).

  Matches: A-Z, a-z, underscore, colon
  """
  defguard is_name_start_ascii(c)
           when c in ?a..?z or c in ?A..?Z or c == ?_ or c == ?:

  @doc """
  Guard for Edition 5 NameStartChar.

  NameStartChar ::= ":" | [A-Z] | "_" | [a-z] | [#xC0-#xD6] | [#xD8-#xF6] |
                    [#xF8-#x2FF] | [#x370-#x37D] | [#x37F-#x1FFF] |
                    [#x200C-#x200D] | [#x2070-#x218F] | [#x2C00-#x2FEF] |
                    [#x3001-#xD7FF] | [#xF900-#xFDCF] | [#xFDF0-#xFFFD] |
                    [#x10000-#xEFFFF]
  """
  defguard is_name_start_ed5(c)
           when is_name_start_ascii(c) or
                  c in 0x00C0..0x00D6 or c in 0x00D8..0x00F6 or
                  c in 0x00F8..0x02FF or c in 0x0370..0x037D or
                  c in 0x037F..0x1FFF or c in 0x200C..0x200D or
                  c in 0x2070..0x218F or c in 0x2C00..0x2FEF or
                  c in 0x3001..0xD7FF or c in 0xF900..0xFDCF or
                  c in 0xFDF0..0xFFFD or c in 0x10000..0xEFFFF

  @doc """
  Guard for Edition 5 NameChar.

  NameChar ::= NameStartChar | "-" | "." | [0-9] | #xB7 |
               [#x0300-#x036F] | [#x203F-#x2040]
  """
  defguard is_name_char_ed5(c)
           when is_name_start_ed5(c) or c == ?- or c == ?. or c in ?0..?9 or
                  c == 0x00B7 or c in 0x0300..0x036F or c in 0x203F..0x2040

  @doc """
  Guard for Edition 4 NameStartChar.

  NameStartChar = Letter | '_' | ':'
  Letter = BaseChar | Ideographic (from Appendix B)
  """
  defguard is_name_start_ed4(c)
           when is_name_start_ascii(c) or
                  c in 0xC0..0xD6 or c in 0xD8..0xF6 or c in 0xF8..0xFF or
                  c in 0x0100..0x0131 or c in 0x0134..0x013E or c in 0x0141..0x0148 or
                  c in 0x014A..0x017E or
                  c in 0x0180..0x01C3 or c in 0x01CD..0x01F0 or c in 0x01F4..0x01F5 or
                  c in 0x01FA..0x0217 or
                  c in 0x0250..0x02A8 or c in 0x02BB..0x02C1 or c == 0x0386 or
                  c in 0x0388..0x038A or
                  c == 0x038C or c in 0x038E..0x03A1 or c in 0x03A3..0x03CE or
                  c in 0x03D0..0x03D6 or
                  c == 0x03DA or c == 0x03DC or c == 0x03DE or c == 0x03E0 or
                  c in 0x03E2..0x03F3 or c in 0x0401..0x040C or c in 0x040E..0x044F or
                  c in 0x0451..0x045C or
                  c in 0x045E..0x0481 or c in 0x0490..0x04C4 or c in 0x04C7..0x04C8 or
                  c in 0x04CB..0x04CC or
                  c in 0x04D0..0x04EB or c in 0x04EE..0x04F5 or c in 0x04F8..0x04F9 or
                  c in 0x0531..0x0556 or
                  c == 0x0559 or c in 0x0561..0x0586 or c in 0x05D0..0x05EA or
                  c in 0x05F0..0x05F2 or
                  c in 0x0621..0x063A or c in 0x0641..0x064A or c in 0x0671..0x06B7 or
                  c in 0x06BA..0x06BE or
                  c in 0x06C0..0x06CE or c in 0x06D0..0x06D3 or c == 0x06D5 or
                  c in 0x06E5..0x06E6 or
                  c in 0x0905..0x0939 or c == 0x093D or c in 0x0958..0x0961 or
                  c in 0x0985..0x098C or
                  c in 0x098F..0x0990 or c in 0x0993..0x09A8 or c in 0x09AA..0x09B0 or
                  c == 0x09B2 or
                  c in 0x09B6..0x09B9 or c in 0x09DC..0x09DD or c in 0x09DF..0x09E1 or
                  c in 0x09F0..0x09F1 or
                  c in 0x0A05..0x0A0A or c in 0x0A0F..0x0A10 or c in 0x0A13..0x0A28 or
                  c in 0x0A2A..0x0A30 or
                  c in 0x0A32..0x0A33 or c in 0x0A35..0x0A36 or c in 0x0A38..0x0A39 or
                  c in 0x0A59..0x0A5C or
                  c == 0x0A5E or c in 0x0A72..0x0A74 or c in 0x0A85..0x0A8B or c == 0x0A8D or
                  c in 0x0A8F..0x0A91 or c in 0x0A93..0x0AA8 or c in 0x0AAA..0x0AB0 or
                  c in 0x0AB2..0x0AB3 or
                  c in 0x0AB5..0x0AB9 or c == 0x0ABD or c == 0x0AE0 or c in 0x0B05..0x0B0C or
                  c in 0x0B0F..0x0B10 or c in 0x0B13..0x0B28 or c in 0x0B2A..0x0B30 or
                  c in 0x0B32..0x0B33 or
                  c in 0x0B36..0x0B39 or c == 0x0B3D or c in 0x0B5C..0x0B5D or
                  c in 0x0B5F..0x0B61 or
                  c in 0x0B85..0x0B8A or c in 0x0B8E..0x0B90 or c in 0x0B92..0x0B95 or
                  c in 0x0B99..0x0B9A or
                  c == 0x0B9C or c in 0x0B9E..0x0B9F or c in 0x0BA3..0x0BA4 or
                  c in 0x0BA8..0x0BAA or
                  c in 0x0BAE..0x0BB5 or c in 0x0BB7..0x0BB9 or c in 0x0C05..0x0C0C or
                  c in 0x0C0E..0x0C10 or
                  c in 0x0C12..0x0C28 or c in 0x0C2A..0x0C33 or c in 0x0C35..0x0C39 or
                  c in 0x0C60..0x0C61 or
                  c in 0x0C85..0x0C8C or c in 0x0C8E..0x0C90 or c in 0x0C92..0x0CA8 or
                  c in 0x0CAA..0x0CB3 or
                  c in 0x0CB5..0x0CB9 or c == 0x0CDE or c in 0x0CE0..0x0CE1 or
                  c in 0x0D05..0x0D0C or
                  c in 0x0D0E..0x0D10 or c in 0x0D12..0x0D28 or c in 0x0D2A..0x0D39 or
                  c in 0x0D60..0x0D61 or
                  c in 0x0E01..0x0E2E or c == 0x0E30 or c in 0x0E32..0x0E33 or
                  c in 0x0E40..0x0E45 or
                  c in 0x0E81..0x0E82 or c == 0x0E84 or c in 0x0E87..0x0E88 or c == 0x0E8A or
                  c == 0x0E8D or c in 0x0E94..0x0E97 or c in 0x0E99..0x0E9F or
                  c in 0x0EA1..0x0EA3 or
                  c == 0x0EA5 or c == 0x0EA7 or c in 0x0EAA..0x0EAB or c in 0x0EAD..0x0EAE or
                  c == 0x0EB0 or c in 0x0EB2..0x0EB3 or c == 0x0EBD or c in 0x0EC0..0x0EC4 or
                  c in 0x0F40..0x0F47 or c in 0x0F49..0x0F69 or c in 0x10A0..0x10C5 or
                  c in 0x10D0..0x10F6 or
                  c == 0x1100 or c in 0x1102..0x1103 or c in 0x1105..0x1107 or c == 0x1109 or
                  c in 0x110B..0x110C or c in 0x110E..0x1112 or c == 0x113C or c == 0x113E or
                  c == 0x1140 or c == 0x114C or c == 0x114E or c == 0x1150 or
                  c in 0x1154..0x1155 or c == 0x1159 or c in 0x115F..0x1161 or c == 0x1163 or
                  c == 0x1165 or c == 0x1167 or c == 0x1169 or c in 0x116D..0x116E or
                  c in 0x1172..0x1173 or c == 0x1175 or c == 0x119E or c == 0x11A8 or
                  c == 0x11AB or c in 0x11AE..0x11AF or c in 0x11B7..0x11B8 or c == 0x11BA or
                  c in 0x11BC..0x11C2 or c == 0x11EB or c == 0x11F0 or c == 0x11F9 or
                  c in 0x1E00..0x1E9B or c in 0x1EA0..0x1EF9 or c in 0x1F00..0x1F15 or
                  c in 0x1F18..0x1F1D or
                  c in 0x1F20..0x1F45 or c in 0x1F48..0x1F4D or c in 0x1F50..0x1F57 or
                  c == 0x1F59 or
                  c == 0x1F5B or c == 0x1F5D or c in 0x1F5F..0x1F7D or c in 0x1F80..0x1FB4 or
                  c in 0x1FB6..0x1FBC or c == 0x1FBE or c in 0x1FC2..0x1FC4 or
                  c in 0x1FC6..0x1FCC or
                  c in 0x1FD0..0x1FD3 or c in 0x1FD6..0x1FDB or c in 0x1FE0..0x1FEC or
                  c in 0x1FF2..0x1FF4 or
                  c in 0x1FF6..0x1FFC or c == 0x2126 or c in 0x212A..0x212B or c == 0x212E or
                  c in 0x2180..0x2182 or c in 0x3041..0x3094 or c in 0x30A1..0x30FA or
                  c in 0x3105..0x312C or
                  c in 0xAC00..0xD7A3 or
                  c in 0x4E00..0x9FA5 or c == 0x3007 or c in 0x3021..0x3029

  @doc """
  Guard for Edition 4 NameChar.

  NameChar = Letter | Digit | '.' | '-' | '_' | ':' | CombiningChar | Extender
  """
  defguard is_name_char_ed4(c)
           when is_name_start_ed4(c) or
                  c == ?- or c == ?. or c in ?0..?9 or c == 0xB7 or
                  c in 0x0660..0x0669 or c in 0x06F0..0x06F9 or c in 0x0966..0x096F or
                  c in 0x09E6..0x09EF or
                  c in 0x0A66..0x0A6F or c in 0x0AE6..0x0AEF or c in 0x0B66..0x0B6F or
                  c in 0x0BE7..0x0BEF or
                  c in 0x0C66..0x0C6F or c in 0x0CE6..0x0CEF or c in 0x0D66..0x0D6F or
                  c in 0x0E50..0x0E59 or
                  c in 0x0ED0..0x0ED9 or c in 0x0F20..0x0F29 or
                  c in 0x0300..0x0345 or c in 0x0360..0x0361 or c in 0x0483..0x0486 or
                  c in 0x0591..0x05A1 or
                  c in 0x05A3..0x05B9 or c in 0x05BB..0x05BD or c == 0x05BF or
                  c in 0x05C1..0x05C2 or
                  c == 0x05C4 or c in 0x064B..0x0652 or c == 0x0670 or c in 0x06D6..0x06DC or
                  c in 0x06DD..0x06DF or c in 0x06E0..0x06E4 or c in 0x06E7..0x06E8 or
                  c in 0x06EA..0x06ED or
                  c in 0x0901..0x0903 or c == 0x093C or c in 0x093E..0x094C or c == 0x094D or
                  c in 0x0951..0x0954 or c in 0x0962..0x0963 or c in 0x0981..0x0983 or
                  c == 0x09BC or
                  c == 0x09BE or c == 0x09BF or c in 0x09C0..0x09C4 or c in 0x09C7..0x09C8 or
                  c in 0x09CB..0x09CD or c == 0x09D7 or c in 0x09E2..0x09E3 or c == 0x0A02 or
                  c == 0x0A3C or c == 0x0A3E or c == 0x0A3F or c in 0x0A40..0x0A42 or
                  c in 0x0A47..0x0A48 or c in 0x0A4B..0x0A4D or c in 0x0A70..0x0A71 or
                  c in 0x0A81..0x0A83 or
                  c == 0x0ABC or c in 0x0ABE..0x0AC5 or c in 0x0AC7..0x0AC9 or
                  c in 0x0ACB..0x0ACD or
                  c in 0x0B01..0x0B03 or c == 0x0B3C or c in 0x0B3E..0x0B43 or
                  c in 0x0B47..0x0B48 or
                  c in 0x0B4B..0x0B4D or c in 0x0B56..0x0B57 or c in 0x0B82..0x0B83 or
                  c in 0x0BBE..0x0BC2 or c in 0x0BC6..0x0BC8 or c in 0x0BCA..0x0BCD or
                  c == 0x0BD7 or
                  c in 0x0C01..0x0C03 or c in 0x0C3E..0x0C44 or c in 0x0C46..0x0C48 or
                  c in 0x0C4A..0x0C4D or
                  c in 0x0C55..0x0C56 or c in 0x0C82..0x0C83 or c in 0x0CBE..0x0CC4 or
                  c in 0x0CC6..0x0CC8 or
                  c in 0x0CCA..0x0CCD or c in 0x0CD5..0x0CD6 or c in 0x0D02..0x0D03 or
                  c in 0x0D3E..0x0D43 or
                  c in 0x0D46..0x0D48 or c in 0x0D4A..0x0D4D or c == 0x0D57 or c == 0x0E31 or
                  c in 0x0E34..0x0E3A or c in 0x0E47..0x0E4E or c == 0x0EB1 or c in 0x0EB4..0x0EB9 or
                  c in 0x0EBB..0x0EBC or c in 0x0EC8..0x0ECD or c in 0x0F18..0x0F19 or
                  c == 0x0F35 or
                  c == 0x0F37 or c == 0x0F39 or c == 0x0F3E or c == 0x0F3F or c in 0x0F71..0x0F84 or
                  c in 0x0F86..0x0F8B or c in 0x0F90..0x0F95 or c == 0x0F97 or c in 0x0F99..0x0FAD or
                  c in 0x0FB1..0x0FB7 or c == 0x0FB9 or c in 0x20D0..0x20DC or c == 0x20E1 or
                  c in 0x302A..0x302F or c == 0x3099 or c == 0x309A or
                  c == 0x02D0 or c == 0x02D1 or c == 0x0387 or c == 0x0640 or c == 0x0E46 or
                  c == 0x0EC6 or c == 0x3005 or c in 0x3031..0x3035 or c in 0x309D..0x309E or
                  c in 0x30FC..0x30FE

  # ===========================================================================
  # Public API - Edition-specific direct functions (no dispatch overhead)
  # ===========================================================================

  # These are the fast-path functions for use in tight loops.
  # Call these directly when you know the edition upfront.

  @doc """
  Check if character is valid NameStartChar per Edition 5 (XML 1.0 Fifth Edition).
  Use this for maximum performance when edition is known.
  """
  @spec name_start_char_ed5?(non_neg_integer()) :: boolean()
  def name_start_char_ed5?(c), do: edition5_name_start_char?(c)

  @doc """
  Check if character is valid NameStartChar per Edition 4 (XML 1.0 Fourth Edition).
  Use this for maximum performance when edition is known.
  """
  @spec name_start_char_ed4?(non_neg_integer()) :: boolean()
  def name_start_char_ed4?(c), do: edition4_name_start_char?(c)

  @doc """
  Check if character is valid NameChar per Edition 5.
  """
  @spec name_char_ed5?(non_neg_integer()) :: boolean()
  def name_char_ed5?(c), do: edition5_name_char?(c)

  @doc """
  Check if character is valid NameChar per Edition 4.
  """
  @spec name_char_ed4?(non_neg_integer()) :: boolean()
  def name_char_ed4?(c), do: edition4_name_char?(c)

  @doc """
  Validate XML Name per Edition 5. No dispatch overhead.
  """
  @spec valid_name_ed5?(String.t()) :: boolean()
  def valid_name_ed5?(""), do: false

  def valid_name_ed5?(<<first::utf8, rest::binary>>) do
    edition5_name_start_char?(first) and valid_name_chars_ed5?(rest)
  end

  defp valid_name_chars_ed5?(<<>>), do: true

  defp valid_name_chars_ed5?(<<c::utf8, rest::binary>>) do
    edition5_name_char?(c) and valid_name_chars_ed5?(rest)
  end

  @doc """
  Validate XML Name per Edition 4. No dispatch overhead.
  """
  @spec valid_name_ed4?(String.t()) :: boolean()
  def valid_name_ed4?(""), do: false

  def valid_name_ed4?(<<first::utf8, rest::binary>>) do
    edition4_name_start_char?(first) and valid_name_chars_ed4?(rest)
  end

  defp valid_name_chars_ed4?(<<>>), do: true

  defp valid_name_chars_ed4?(<<c::utf8, rest::binary>>) do
    edition4_name_char?(c) and valid_name_chars_ed4?(rest)
  end

  # ===========================================================================
  # Function Capture API - Resolve edition once, use captured functions
  # ===========================================================================

  @type validator_fun :: (non_neg_integer() -> boolean())
  @type name_validator_fun :: (String.t() -> boolean())

  @doc """
  Get validator functions for the specified edition.

  Returns a tuple of `{name_start_char?, name_char?, valid_name?}` functions
  that can be called without edition dispatch overhead.

  ## Example

      {start?, char?, valid?} = FnXML.Char.validators(5)

      # Now use in tight loop - no dispatch overhead
      Enum.all?(chars, start?)
  """
  @spec validators(4 | 5) :: {validator_fun(), validator_fun(), name_validator_fun()}
  def validators(5), do: {&name_start_char_ed5?/1, &name_char_ed5?/1, &valid_name_ed5?/1}
  def validators(4), do: {&name_start_char_ed4?/1, &name_char_ed4?/1, &valid_name_ed4?/1}
  def validators(_), do: validators(5)

  # ===========================================================================
  # Public API - Convenience functions with edition option
  # ===========================================================================

  @doc """
  Check if character is valid as the first character of an XML Name.

  For tight loops, prefer `name_start_char_ed5?/1` or `name_start_char_ed4?/1`
  to avoid per-call option checking.

  ## Options
  - `edition: 4` - Use XML 1.0 Fourth Edition rules (strict)
  - `edition: 5` - Use XML 1.0 Fifth Edition rules (default, permissive)

  ## Examples

      iex> FnXML.Char.name_start_char?(?A)
      true

      iex> FnXML.Char.name_start_char?(?1)
      false

      iex> FnXML.Char.name_start_char?(0x00D7, edition: 5)  # × multiplication sign
      false

      iex> FnXML.Char.name_start_char?(0x0100, edition: 4)  # Ā Latin Extended
      true
  """
  @spec name_start_char?(non_neg_integer(), keyword()) :: boolean()
  def name_start_char?(c, opts \\ [])

  def name_start_char?(c, opts) do
    case Keyword.get(opts, :edition, 5) do
      5 -> edition5_name_start_char?(c)
      4 -> edition4_name_start_char?(c)
      _ -> edition5_name_start_char?(c)
    end
  end

  @doc """
  Check if character is valid within an XML Name (not first position).

  For tight loops, prefer `name_char_ed5?/1` or `name_char_ed4?/1`.

  ## Options
  - `edition: 4` - Use XML 1.0 Fourth Edition rules (strict)
  - `edition: 5` - Use XML 1.0 Fifth Edition rules (default, permissive)
  """
  @spec name_char?(non_neg_integer(), keyword()) :: boolean()
  def name_char?(c, opts \\ [])

  def name_char?(c, opts) do
    case Keyword.get(opts, :edition, 5) do
      5 -> edition5_name_char?(c)
      4 -> edition4_name_char?(c)
      _ -> edition5_name_char?(c)
    end
  end

  @doc """
  Validate an entire XML Name string.

  For repeated validation, prefer `valid_name_ed5?/1` or `valid_name_ed4?/1`.

  ## Examples

      iex> FnXML.Char.valid_name?("foo")
      true

      iex> FnXML.Char.valid_name?("123")
      false

      iex> FnXML.Char.valid_name?("foo:bar")
      true
  """
  @spec valid_name?(String.t(), keyword()) :: boolean()
  def valid_name?(name, opts \\ [])

  def valid_name?("", _opts), do: false

  def valid_name?(name, opts) do
    case Keyword.get(opts, :edition, 5) do
      5 -> valid_name_ed5?(name)
      4 -> valid_name_ed4?(name)
      _ -> valid_name_ed5?(name)
    end
  end

  # ===========================================================================
  # Edition 5 Implementation (uses public guards)
  # ===========================================================================

  defp edition5_name_start_char?(c) when is_name_start_ed5(c), do: true
  defp edition5_name_start_char?(_), do: false

  defp edition5_name_char?(c) when is_name_char_ed5(c), do: true
  defp edition5_name_char?(_), do: false

  # ===========================================================================
  # Edition 4 Implementation (uses public guards)
  # ===========================================================================

  defp edition4_name_start_char?(c) when is_name_start_ed4(c), do: true
  defp edition4_name_start_char?(_), do: false

  defp edition4_name_char?(c) when is_name_char_ed4(c), do: true
  defp edition4_name_char?(_), do: false
end
