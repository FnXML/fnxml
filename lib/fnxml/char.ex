defmodule FnXML.Char do
  @moduledoc """
  XML Name character validation with support for Edition 4 and Edition 5.

  ## Edition 5 (Default)
  Uses simplified, broad Unicode ranges from XML 1.0 Fifth Edition.
  More permissive - includes most Unicode characters.

  ## Edition 4
  Uses strict character class enumeration from XML 1.0 Fourth Edition Appendix B.
  Hybrid approach: inline checks for 1-byte chars, bitmap for 2-byte chars.

  ## Performance
  - Edition 5: O(1) with ~16 range comparisons
  - Edition 4: O(1) with inline checks (0x00-0xFF) or bitmap lookup (0x100-0xFFFF)
  """

  import Bitwise

  # ===========================================================================
  # Edition 4 Character Class Definitions (from Appendix B)
  # ===========================================================================

  # BaseChar 2-byte ranges (1-byte ranges are handled inline for performance)
  @edition4_base_char_2byte [
    {0x0100, 0x0131},
    {0x0134, 0x013E},
    {0x0141, 0x0148},
    {0x014A, 0x017E},
    {0x0180, 0x01C3},
    {0x01CD, 0x01F0},
    {0x01F4, 0x01F5},
    {0x01FA, 0x0217},
    {0x0250, 0x02A8},
    {0x02BB, 0x02C1},
    {0x0386, 0x0386},
    {0x0388, 0x038A},
    {0x038C, 0x038C},
    {0x038E, 0x03A1},
    {0x03A3, 0x03CE},
    {0x03D0, 0x03D6},
    {0x03DA, 0x03DA},
    {0x03DC, 0x03DC},
    {0x03DE, 0x03DE},
    {0x03E0, 0x03E0},
    {0x03E2, 0x03F3},
    {0x0401, 0x040C},
    {0x040E, 0x044F},
    {0x0451, 0x045C},
    {0x045E, 0x0481},
    {0x0490, 0x04C4},
    {0x04C7, 0x04C8},
    {0x04CB, 0x04CC},
    {0x04D0, 0x04EB},
    {0x04EE, 0x04F5},
    {0x04F8, 0x04F9},
    {0x0531, 0x0556},
    {0x0559, 0x0559},
    {0x0561, 0x0586},
    {0x05D0, 0x05EA},
    {0x05F0, 0x05F2},
    {0x0621, 0x063A},
    {0x0641, 0x064A},
    {0x0671, 0x06B7},
    {0x06BA, 0x06BE},
    {0x06C0, 0x06CE},
    {0x06D0, 0x06D3},
    {0x06D5, 0x06D5},
    {0x06E5, 0x06E6},
    {0x0905, 0x0939},
    {0x093D, 0x093D},
    {0x0958, 0x0961},
    {0x0985, 0x098C},
    {0x098F, 0x0990},
    {0x0993, 0x09A8},
    {0x09AA, 0x09B0},
    {0x09B2, 0x09B2},
    {0x09B6, 0x09B9},
    {0x09DC, 0x09DD},
    {0x09DF, 0x09E1},
    {0x09F0, 0x09F1},
    {0x0A05, 0x0A0A},
    {0x0A0F, 0x0A10},
    {0x0A13, 0x0A28},
    {0x0A2A, 0x0A30},
    {0x0A32, 0x0A33},
    {0x0A35, 0x0A36},
    {0x0A38, 0x0A39},
    {0x0A59, 0x0A5C},
    {0x0A5E, 0x0A5E},
    {0x0A72, 0x0A74},
    {0x0A85, 0x0A8B},
    {0x0A8D, 0x0A8D},
    {0x0A8F, 0x0A91},
    {0x0A93, 0x0AA8},
    {0x0AAA, 0x0AB0},
    {0x0AB2, 0x0AB3},
    {0x0AB5, 0x0AB9},
    {0x0ABD, 0x0ABD},
    {0x0AE0, 0x0AE0},
    {0x0B05, 0x0B0C},
    {0x0B0F, 0x0B10},
    {0x0B13, 0x0B28},
    {0x0B2A, 0x0B30},
    {0x0B32, 0x0B33},
    {0x0B36, 0x0B39},
    {0x0B3D, 0x0B3D},
    {0x0B5C, 0x0B5D},
    {0x0B5F, 0x0B61},
    {0x0B85, 0x0B8A},
    {0x0B8E, 0x0B90},
    {0x0B92, 0x0B95},
    {0x0B99, 0x0B9A},
    {0x0B9C, 0x0B9C},
    {0x0B9E, 0x0B9F},
    {0x0BA3, 0x0BA4},
    {0x0BA8, 0x0BAA},
    {0x0BAE, 0x0BB5},
    {0x0BB7, 0x0BB9},
    {0x0C05, 0x0C0C},
    {0x0C0E, 0x0C10},
    {0x0C12, 0x0C28},
    {0x0C2A, 0x0C33},
    {0x0C35, 0x0C39},
    {0x0C60, 0x0C61},
    {0x0C85, 0x0C8C},
    {0x0C8E, 0x0C90},
    {0x0C92, 0x0CA8},
    {0x0CAA, 0x0CB3},
    {0x0CB5, 0x0CB9},
    {0x0CDE, 0x0CDE},
    {0x0CE0, 0x0CE1},
    {0x0D05, 0x0D0C},
    {0x0D0E, 0x0D10},
    {0x0D12, 0x0D28},
    {0x0D2A, 0x0D39},
    {0x0D60, 0x0D61},
    {0x0E01, 0x0E2E},
    {0x0E30, 0x0E30},
    {0x0E32, 0x0E33},
    {0x0E40, 0x0E45},
    {0x0E81, 0x0E82},
    {0x0E84, 0x0E84},
    {0x0E87, 0x0E88},
    {0x0E8A, 0x0E8A},
    {0x0E8D, 0x0E8D},
    {0x0E94, 0x0E97},
    {0x0E99, 0x0E9F},
    {0x0EA1, 0x0EA3},
    {0x0EA5, 0x0EA5},
    {0x0EA7, 0x0EA7},
    {0x0EAA, 0x0EAB},
    {0x0EAD, 0x0EAE},
    {0x0EB0, 0x0EB0},
    {0x0EB2, 0x0EB3},
    {0x0EBD, 0x0EBD},
    {0x0EC0, 0x0EC4},
    {0x0F40, 0x0F47},
    {0x0F49, 0x0F69},
    {0x10A0, 0x10C5},
    {0x10D0, 0x10F6},
    {0x1100, 0x1100},
    {0x1102, 0x1103},
    {0x1105, 0x1107},
    {0x1109, 0x1109},
    {0x110B, 0x110C},
    {0x110E, 0x1112},
    {0x113C, 0x113C},
    {0x113E, 0x113E},
    {0x1140, 0x1140},
    {0x114C, 0x114C},
    {0x114E, 0x114E},
    {0x1150, 0x1150},
    {0x1154, 0x1155},
    {0x1159, 0x1159},
    {0x115F, 0x1161},
    {0x1163, 0x1163},
    {0x1165, 0x1165},
    {0x1167, 0x1167},
    {0x1169, 0x1169},
    {0x116D, 0x116E},
    {0x1172, 0x1173},
    {0x1175, 0x1175},
    {0x119E, 0x119E},
    {0x11A8, 0x11A8},
    {0x11AB, 0x11AB},
    {0x11AE, 0x11AF},
    {0x11B7, 0x11B8},
    {0x11BA, 0x11BA},
    {0x11BC, 0x11C2},
    {0x11EB, 0x11EB},
    {0x11F0, 0x11F0},
    {0x11F9, 0x11F9},
    {0x1E00, 0x1E9B},
    {0x1EA0, 0x1EF9},
    {0x1F00, 0x1F15},
    {0x1F18, 0x1F1D},
    {0x1F20, 0x1F45},
    {0x1F48, 0x1F4D},
    {0x1F50, 0x1F57},
    {0x1F59, 0x1F59},
    {0x1F5B, 0x1F5B},
    {0x1F5D, 0x1F5D},
    {0x1F5F, 0x1F7D},
    {0x1F80, 0x1FB4},
    {0x1FB6, 0x1FBC},
    {0x1FBE, 0x1FBE},
    {0x1FC2, 0x1FC4},
    {0x1FC6, 0x1FCC},
    {0x1FD0, 0x1FD3},
    {0x1FD6, 0x1FDB},
    {0x1FE0, 0x1FEC},
    {0x1FF2, 0x1FF4},
    {0x1FF6, 0x1FFC},
    {0x2126, 0x2126},
    {0x212A, 0x212B},
    {0x212E, 0x212E},
    {0x2180, 0x2182},
    {0x3041, 0x3094},
    {0x30A1, 0x30FA},
    {0x3105, 0x312C},
    {0xAC00, 0xD7A3}
  ]

  # Ideographic (all 2-byte)
  @edition4_ideographic [
    {0x4E00, 0x9FA5},
    {0x3007, 0x3007},
    {0x3021, 0x3029}
  ]

  # CombiningChar (all 2-byte, starts at 0x0300)
  @edition4_combining_char [
    {0x0300, 0x0345},
    {0x0360, 0x0361},
    {0x0483, 0x0486},
    {0x0591, 0x05A1},
    {0x05A3, 0x05B9},
    {0x05BB, 0x05BD},
    {0x05BF, 0x05BF},
    {0x05C1, 0x05C2},
    {0x05C4, 0x05C4},
    {0x064B, 0x0652},
    {0x0670, 0x0670},
    {0x06D6, 0x06DC},
    {0x06DD, 0x06DF},
    {0x06E0, 0x06E4},
    {0x06E7, 0x06E8},
    {0x06EA, 0x06ED},
    {0x0901, 0x0903},
    {0x093C, 0x093C},
    {0x093E, 0x094C},
    {0x094D, 0x094D},
    {0x0951, 0x0954},
    {0x0962, 0x0963},
    {0x0981, 0x0983},
    {0x09BC, 0x09BC},
    {0x09BE, 0x09BE},
    {0x09BF, 0x09BF},
    {0x09C0, 0x09C4},
    {0x09C7, 0x09C8},
    {0x09CB, 0x09CD},
    {0x09D7, 0x09D7},
    {0x09E2, 0x09E3},
    {0x0A02, 0x0A02},
    {0x0A3C, 0x0A3C},
    {0x0A3E, 0x0A3E},
    {0x0A3F, 0x0A3F},
    {0x0A40, 0x0A42},
    {0x0A47, 0x0A48},
    {0x0A4B, 0x0A4D},
    {0x0A70, 0x0A71},
    {0x0A81, 0x0A83},
    {0x0ABC, 0x0ABC},
    {0x0ABE, 0x0AC5},
    {0x0AC7, 0x0AC9},
    {0x0ACB, 0x0ACD},
    {0x0B01, 0x0B03},
    {0x0B3C, 0x0B3C},
    {0x0B3E, 0x0B43},
    {0x0B47, 0x0B48},
    {0x0B4B, 0x0B4D},
    {0x0B56, 0x0B57},
    {0x0B82, 0x0B83},
    {0x0BBE, 0x0BC2},
    {0x0BC6, 0x0BC8},
    {0x0BCA, 0x0BCD},
    {0x0BD7, 0x0BD7},
    {0x0C01, 0x0C03},
    {0x0C3E, 0x0C44},
    {0x0C46, 0x0C48},
    {0x0C4A, 0x0C4D},
    {0x0C55, 0x0C56},
    {0x0C82, 0x0C83},
    {0x0CBE, 0x0CC4},
    {0x0CC6, 0x0CC8},
    {0x0CCA, 0x0CCD},
    {0x0CD5, 0x0CD6},
    {0x0D02, 0x0D03},
    {0x0D3E, 0x0D43},
    {0x0D46, 0x0D48},
    {0x0D4A, 0x0D4D},
    {0x0D57, 0x0D57},
    {0x0E31, 0x0E31},
    {0x0E34, 0x0E3A},
    {0x0E47, 0x0E4E},
    {0x0EB1, 0x0EB1},
    {0x0EB4, 0x0EB9},
    {0x0EBB, 0x0EBC},
    {0x0EC8, 0x0ECD},
    {0x0F18, 0x0F19},
    {0x0F35, 0x0F35},
    {0x0F37, 0x0F37},
    {0x0F39, 0x0F39},
    {0x0F3E, 0x0F3E},
    {0x0F3F, 0x0F3F},
    {0x0F71, 0x0F84},
    {0x0F86, 0x0F8B},
    {0x0F90, 0x0F95},
    {0x0F97, 0x0F97},
    {0x0F99, 0x0FAD},
    {0x0FB1, 0x0FB7},
    {0x0FB9, 0x0FB9},
    {0x20D0, 0x20DC},
    {0x20E1, 0x20E1},
    {0x302A, 0x302F},
    {0x3099, 0x3099},
    {0x309A, 0x309A}
  ]

  # Digit - 1-byte and 2-byte
  @edition4_digit_2byte [
    {0x0660, 0x0669},
    {0x06F0, 0x06F9},
    {0x0966, 0x096F},
    {0x09E6, 0x09EF},
    {0x0A66, 0x0A6F},
    {0x0AE6, 0x0AEF},
    {0x0B66, 0x0B6F},
    {0x0BE7, 0x0BEF},
    {0x0C66, 0x0C6F},
    {0x0CE6, 0x0CEF},
    {0x0D66, 0x0D6F},
    {0x0E50, 0x0E59},
    {0x0ED0, 0x0ED9},
    {0x0F20, 0x0F29}
  ]

  # Extender - 2-byte only (0xB7 handled inline)
  @edition4_extender_2byte [
    {0x02D0, 0x02D0},
    {0x02D1, 0x02D1},
    {0x0387, 0x0387},
    {0x0640, 0x0640},
    {0x0E46, 0x0E46},
    {0x0EC6, 0x0EC6},
    {0x3005, 0x3005},
    {0x3031, 0x3035},
    {0x309D, 0x309E},
    {0x30FC, 0x30FE}
  ]

  # ===========================================================================
  # Compile-time bitmap generation for 2-byte characters (0x0100-0xFFFF)
  # ===========================================================================

  # Bitmap covers 0x0100-0xFFFF (65280 code points = 8160 bytes)
  @bitmap_offset 0x0100
  @bitmap_size 8160

  # Build bitmap at compile time using module attribute evaluation
  @edition4_letter_ranges @edition4_base_char_2byte ++ @edition4_ideographic
  @edition4_name_char_ranges @edition4_base_char_2byte ++
                               @edition4_ideographic ++
                               @edition4_combining_char ++
                               @edition4_digit_2byte ++
                               @edition4_extender_2byte

  # Generate bitmaps at compile time
  @edition4_letter_bitmap (
                            initial = :binary.copy(<<0>>, @bitmap_size)

                            Enum.reduce(@edition4_letter_ranges, initial, fn {lo, hi}, bitmap ->
                              Enum.reduce(lo..hi, bitmap, fn c, bmp ->
                                if c >= @bitmap_offset and c <= 0xFFFF do
                                  bit_index = c - @bitmap_offset
                                  byte_idx = div(bit_index, 8)
                                  bit_pos = 7 - rem(bit_index, 8)
                                  <<pre::binary-size(byte_idx), byte, post::binary>> = bmp
                                  <<pre::binary, byte ||| 1 <<< bit_pos, post::binary>>
                                else
                                  bmp
                                end
                              end)
                            end)
                          )

  @edition4_name_char_bitmap (
                               initial = :binary.copy(<<0>>, @bitmap_size)

                               Enum.reduce(@edition4_name_char_ranges, initial, fn {lo, hi},
                                                                                   bitmap ->
                                 Enum.reduce(lo..hi, bitmap, fn c, bmp ->
                                   if c >= @bitmap_offset and c <= 0xFFFF do
                                     bit_index = c - @bitmap_offset
                                     byte_idx = div(bit_index, 8)
                                     bit_pos = 7 - rem(bit_index, 8)
                                     <<pre::binary-size(byte_idx), byte, post::binary>> = bmp
                                     <<pre::binary, byte ||| 1 <<< bit_pos, post::binary>>
                                   else
                                     bmp
                                   end
                                 end)
                               end)
                             )

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
  # Edition 5 Implementation (inline range checks)
  # ===========================================================================

  # NameStartChar ::= ":" | [A-Z] | "_" | [a-z] | [#xC0-#xD6] | [#xD8-#xF6] |
  #                   [#xF8-#x2FF] | [#x370-#x37D] | [#x37F-#x1FFF] |
  #                   [#x200C-#x200D] | [#x2070-#x218F] | [#x2C00-#x2FEF] |
  #                   [#x3001-#xD7FF] | [#xF900-#xFDCF] | [#xFDF0-#xFFFD] |
  #                   [#x10000-#xEFFFF]

  defp edition5_name_start_char?(c) do
    # Ordered by frequency for typical XML (ASCII first)
    c in ?a..?z or
      c in ?A..?Z or
      c == ?_ or
      c == ?: or
      c in 0xC0..0xD6 or
      c in 0xD8..0xF6 or
      c in 0xF8..0x2FF or
      c in 0x370..0x37D or
      c in 0x37F..0x1FFF or
      c in 0x200C..0x200D or
      c in 0x2070..0x218F or
      c in 0x2C00..0x2FEF or
      c in 0x3001..0xD7FF or
      c in 0xF900..0xFDCF or
      c in 0xFDF0..0xFFFD or
      c in 0x10000..0xEFFFF
  end

  # NameChar ::= NameStartChar | "-" | "." | [0-9] | #xB7 |
  #              [#x0300-#x036F] | [#x203F-#x2040]

  defp edition5_name_char?(c) do
    # Check additional NameChar characters first (for chars that aren't NameStartChar)
    c == ?- or
      c == ?. or
      c in ?0..?9 or
      c == 0xB7 or
      c in 0x300..0x36F or
      c in 0x203F..0x2040 or
      edition5_name_start_char?(c)
  end

  # ===========================================================================
  # Edition 4 Implementation (hybrid: inline 1-byte + bitmap 2-byte)
  # ===========================================================================

  # NameStartChar = Letter | '_' | ':'
  # Letter = BaseChar | Ideographic

  defp edition4_name_start_char?(c) when c <= 0xFF do
    # 1-byte: inline range checks (most common path)
    c == ?_ or
      c == ?: or
      c in ?A..?Z or
      c in ?a..?z or
      c in 0xC0..0xD6 or
      c in 0xD8..0xF6 or
      c in 0xF8..0xFF
  end

  defp edition4_name_start_char?(c) when c in 0x100..0xFFFF do
    # 2-byte: bitmap lookup
    check_bitmap(@edition4_letter_bitmap, c - @bitmap_offset)
  end

  # Supplementary planes not in Ed4
  defp edition4_name_start_char?(_), do: false

  # NameChar = Letter | Digit | '.' | '-' | '_' | ':' | CombiningChar | Extender

  defp edition4_name_char?(c) when c <= 0xFF do
    # 1-byte: inline range checks
    # Digit
    # Extender (middle dot)
    # BaseChar
    c == ?- or
      c == ?. or
      c == ?_ or
      c == ?: or
      c in ?0..?9 or
      c == 0xB7 or
      c in ?A..?Z or
      c in ?a..?z or
      c in 0xC0..0xD6 or
      c in 0xD8..0xF6 or
      c in 0xF8..0xFF
  end

  defp edition4_name_char?(c) when c in 0x100..0xFFFF do
    # 2-byte: bitmap lookup (combined Letter + Combining + Digit + Extender)
    check_bitmap(@edition4_name_char_bitmap, c - @bitmap_offset)
  end

  # Supplementary planes not in Ed4
  defp edition4_name_char?(_), do: false

  # ===========================================================================
  # Bitmap lookup helper
  # ===========================================================================

  @compile {:inline, check_bitmap: 2}

  defp check_bitmap(bitmap, bit_index) when bit_index >= 0 and bit_index < @bitmap_size * 8 do
    byte_idx = div(bit_index, 8)
    bit_pos = 7 - rem(bit_index, 8)

    <<_::binary-size(byte_idx), byte, _::binary>> = bitmap
    (byte >>> bit_pos &&& 1) == 1
  end

  defp check_bitmap(_, _), do: false
end
