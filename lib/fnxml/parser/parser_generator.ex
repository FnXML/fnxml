defmodule FnXML.Parser.Generator do
  @moduledoc """
  Macro-based XML block parser generator for Edition 4 and Edition 5.

  Generates edition-specific parsers from shared code, with character
  validation guards inlined at compile time for maximum performance.

  ## Usage

      # Generates parser with Edition 5 character validation
      use FnXML.Parser.Generator, edition: 5

      # Generates parser with Edition 4 character validation
      use FnXML.Parser.Generator, edition: 4

  ## Architecture

  The parser code is shared between editions. Only the character validation
  guards (`is_name_start/1` and `is_name_char/1`) differ:

  - Edition 5: 16 simple Unicode ranges (permissive)
  - Edition 4: ~200 enumerated ranges from Appendix B (strict)

  Both use guards for zero runtime dispatch overhead.
  """

  @doc """
  Generates an edition-specific block parser module.

  ## Options
  - `:edition` - Required. Either `4` or `5`.
  - `:disable` - Optional. List of event types to disable (compile-time filtering).
                 Valid values: `:space`, `:comment`, `:cdata`, `:prolog`, `:characters`,
                              `:start_element`, `:end_element`, `:error`
  - `:positions` - Optional. How to include position data in events.
                  - `:full` (default) - Include line, ls, abs_pos
                  - `:line_only` - Include only line number
                  - `:none` - No position data

  ## Examples

      # Full featured parser (default)
      use FnXML.Parser.Generator, edition: 5

      # Minimal parser - no whitespace, comments, or positions
      use FnXML.Parser.Generator, edition: 5,
        disable: [:space, :comment],
        positions: :none

      # Structure only - no text content
      use FnXML.Parser.Generator, edition: 5,
        disable: [:characters, :space, :comment, :cdata]
  """
  defmacro __using__(opts) do
    edition = Keyword.fetch!(opts, :edition)
    disabled = Keyword.get(opts, :disable, [])
    positions = Keyword.get(opts, :positions, :full)

    quote do
      @moduledoc """
      XML 1.0 Edition #{unquote(edition)} Block Parser.

      Auto-generated with edition-specific character validation inlined
      for maximum performance. No runtime edition dispatch.

      Disabled events: #{inspect(unquote(disabled))}
      Position mode: #{unquote(positions)}
      """

      # Inline frequently called helper functions
      @compile {:inline,
                utf8_size: 1,
                complete: 4,
                incomplete: 5,
                buf_start: 3,
                new_event: 6,
                new_event: 7,
                error: 6}

      # Store configuration for introspection
      @edition unquote(edition)
      @disabled unquote(disabled)
      @position_mode unquote(positions)

      def edition, do: @edition
      def disabled, do: @disabled
      def position_mode, do: @position_mode

      # ==================================================================
      # Character Guards (edition-specific, inlined at compile time)
      # ==================================================================

      unquote(generate_char_guards(edition))

      # ==================================================================
      # Event Helpers (with compile-time filtering)
      # ==================================================================

      unquote(generate_event_helpers(disabled, positions))

      # ==================================================================
      # Shared Parser Implementation
      # ==================================================================

      unquote(shared_parser_code())
    end
  end

  # ==================================================================
  # Edition 5 Guards (simple ranges)
  # ==================================================================

  defp generate_char_guards(5) do
    quote do
      # XML character guard per XML spec production [2]
      # Char ::= #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
      defguardp is_xml_char(c)
                when c == 0x9 or c == 0xA or c == 0xD or
                       c in 0x20..0xD7FF or c in 0xE000..0xFFFD or
                       c in 0x10000..0x10FFFF

      defguardp is_name_start_ascii(c)
                when c in ?a..?z or c in ?A..?Z or c == ?_ or c == ?:

      # Edition 5 NameStartChar
      # NameStartChar ::= ":" | [A-Z] | "_" | [a-z] | [#xC0-#xD6] | [#xD8-#xF6] |
      #                   [#xF8-#x2FF] | [#x370-#x37D] | [#x37F-#x1FFF] |
      #                   [#x200C-#x200D] | [#x2070-#x218F] | [#x2C00-#x2FEF] |
      #                   [#x3001-#xD7FF] | [#xF900-#xFDCF] | [#xFDF0-#xFFFD] |
      #                   [#x10000-#xEFFFF]
      defguardp is_name_start(c)
                when is_name_start_ascii(c) or
                       c in 0x00C0..0x00D6 or c in 0x00D8..0x00F6 or
                       c in 0x00F8..0x02FF or c in 0x0370..0x037D or
                       c in 0x037F..0x1FFF or c in 0x200C..0x200D or
                       c in 0x2070..0x218F or c in 0x2C00..0x2FEF or
                       c in 0x3001..0xD7FF or c in 0xF900..0xFDCF or
                       c in 0xFDF0..0xFFFD or c in 0x10000..0xEFFFF

      defguardp is_name_char_ascii(c)
                when is_name_start_ascii(c) or c == ?- or c == ?. or c in ?0..?9

      # Edition 5 NameChar
      # NameChar ::= NameStartChar | "-" | "." | [0-9] | #xB7 |
      #              [#x0300-#x036F] | [#x203F-#x2040]
      defguardp is_name_char(c)
                when is_name_start(c) or c == ?- or c == ?. or c in ?0..?9 or
                       c == 0x00B7 or c in 0x0300..0x036F or c in 0x203F..0x2040
    end
  end

  # ==================================================================
  # Edition 4 Guards (enumerated ranges from Appendix B)
  # ==================================================================

  defp generate_char_guards(4) do
    quote do
      # XML character guard (same for both editions)
      defguardp is_xml_char(c)
                when c == 0x9 or c == 0xA or c == 0xD or
                       c in 0x20..0xD7FF or c in 0xE000..0xFFFD or
                       c in 0x10000..0x10FFFF

      defguardp is_name_start_ascii(c)
                when c in ?a..?z or c in ?A..?Z or c == ?_ or c == ?:

      # Edition 4 NameStartChar = Letter | '_' | ':'
      # Letter = BaseChar | Ideographic
      # BaseChar and Ideographic from Appendix B
      defguardp is_name_start(c)
                # ASCII letters
                # BaseChar 1-byte
                # BaseChar 2-byte (from Appendix B)
                # Ideographic
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

      defguardp is_name_char_ascii(c)
                when is_name_start_ascii(c) or c == ?- or c == ?. or c in ?0..?9 or c == 0xB7

      # Edition 4 NameChar = Letter | Digit | '.' | '-' | '_' | ':' | CombiningChar | Extender
      defguardp is_name_char(c)
                # Additional NameChar characters
                # Digit 2-byte
                # CombiningChar
                # Extender 2-byte
                when is_name_start(c) or
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
                       c in 0x0BBE..0x0BC2 or
                       c in 0x0BC6..0x0BC8 or c in 0x0BCA..0x0BCD or c == 0x0BD7 or
                       c in 0x0C01..0x0C03 or
                       c in 0x0C3E..0x0C44 or c in 0x0C46..0x0C48 or c in 0x0C4A..0x0C4D or
                       c in 0x0C55..0x0C56 or
                       c in 0x0C82..0x0C83 or c in 0x0CBE..0x0CC4 or c in 0x0CC6..0x0CC8 or
                       c in 0x0CCA..0x0CCD or
                       c in 0x0CD5..0x0CD6 or c in 0x0D02..0x0D03 or c in 0x0D3E..0x0D43 or
                       c in 0x0D46..0x0D48 or
                       c in 0x0D4A..0x0D4D or c == 0x0D57 or c == 0x0E31 or c in 0x0E34..0x0E3A or
                       c in 0x0E47..0x0E4E or c == 0x0EB1 or c in 0x0EB4..0x0EB9 or
                       c in 0x0EBB..0x0EBC or
                       c in 0x0EC8..0x0ECD or c in 0x0F18..0x0F19 or c == 0x0F35 or c == 0x0F37 or
                       c == 0x0F39 or c == 0x0F3E or c == 0x0F3F or c in 0x0F71..0x0F84 or
                       c in 0x0F86..0x0F8B or c in 0x0F90..0x0F95 or c == 0x0F97 or
                       c in 0x0F99..0x0FAD or
                       c in 0x0FB1..0x0FB7 or c == 0x0FB9 or c in 0x20D0..0x20DC or c == 0x20E1 or
                       c in 0x302A..0x302F or c == 0x3099 or c == 0x309A or
                       c == 0x02D0 or c == 0x02D1 or c == 0x0387 or c == 0x0640 or
                       c == 0x0E46 or c == 0x0EC6 or c == 0x3005 or c in 0x3031..0x3035 or
                       c in 0x309D..0x309E or c in 0x30FC..0x30FE
    end
  end

  # ==================================================================
  # Event Helper Generation (with compile-time filtering)
  # ==================================================================

  defp generate_event_helpers(disabled, positions) do
    quote do
      # Generate new_event/6 (single data field)
      unquote(generate_new_event_6(disabled, positions))

      # Generate new_event/7 (two data fields)
      unquote(generate_new_event_7(disabled, positions))

      # Generate error/6
      unquote(generate_error_6(disabled, positions))
    end
  end

  # Map event types to their parameter count (data fields)
  # Single data parameter events use new_event/6
  @single_param_events [:end_element, :characters, :space, :comment, :cdata, :dtd]

  # Two data parameter events use new_event/7
  @double_param_events [:start_element, :prolog, :processing_instruction, :error]

  # Generate new_event/6 clauses (event_type, data, line, ls, abs_pos)
  defp generate_new_event_6(disabled, positions) do
    # Only generate drop clauses for disabled single-param events
    disabled_single = Enum.filter(disabled, &(&1 in @single_param_events))

    drop_clauses =
      for event_type <- disabled_single do
        quote do
          defp new_event(events, unquote(event_type), _data, _line, _ls, _abs_pos) do
            events
          end
        end
      end

    # Determine if we need a default clause for new_event/6
    # Only generate if there are enabled single-param events
    enabled_single = @single_param_events -- disabled

    default_clause =
      if enabled_single != [] do
        case positions do
          :full ->
            quote do
              defp new_event(events, event_type, data, line, ls, abs_pos) do
                [{event_type, data, line, ls, abs_pos} | events]
              end
            end

          :line_only ->
            quote do
              defp new_event(events, event_type, data, line, _ls, _abs_pos) do
                [{event_type, data, line} | events]
              end
            end

          :none ->
            quote do
              defp new_event(events, event_type, data, _line, _ls, _abs_pos) do
                [{event_type, data} | events]
              end
            end
        end
      else
        []
      end

    [drop_clauses, default_clause]
  end

  # Generate new_event/7 clauses (event_type, data1, data2, line, ls, abs_pos)
  defp generate_new_event_7(disabled, positions) do
    # Only generate drop clauses for disabled double-param events
    disabled_double = Enum.filter(disabled, &(&1 in @double_param_events))

    drop_clauses =
      for event_type <- disabled_double do
        quote do
          defp new_event(events, unquote(event_type), _data1, _data2, _line, _ls, _abs_pos) do
            events
          end
        end
      end

    # Determine if we need a default clause for new_event/7
    # Only generate if there are enabled double-param events
    enabled_double = @double_param_events -- disabled

    default_clause =
      if enabled_double != [] do
        case positions do
          :full ->
            quote do
              defp new_event(events, event_type, data1, data2, line, ls, abs_pos) do
                [{event_type, data1, data2, line, ls, abs_pos} | events]
              end
            end

          :line_only ->
            quote do
              defp new_event(events, event_type, data1, data2, line, _ls, _abs_pos) do
                [{event_type, data1, data2, line} | events]
              end
            end

          :none ->
            quote do
              defp new_event(events, event_type, data1, data2, _line, _ls, _abs_pos) do
                [{event_type, data1, data2} | events]
              end
            end
        end
      else
        []
      end

    [drop_clauses, default_clause]
  end

  # Generate error/6 clauses (error_type, message, line, ls, abs_pos)
  defp generate_error_6(disabled, positions) do
    # Check if :error is disabled (though this would be unusual)
    if :error in disabled do
      quote do
        defp error(events, _error_type, _message, _line, _ls, _abs_pos) do
          events
        end
      end
    else
      # Generate error clause based on position mode
      case positions do
        :full ->
          quote do
            defp error(events, error_type, message, line, ls, abs_pos) do
              [{:error, error_type, message, line, ls, abs_pos} | events]
            end
          end

        :line_only ->
          quote do
            defp error(events, error_type, message, line, _ls, _abs_pos) do
              [{:error, error_type, message, line} | events]
            end
          end

        :none ->
          quote do
            defp error(events, error_type, message, _line, _ls, _abs_pos) do
              [{:error, error_type, message} | events]
            end
          end
      end
    end
  end

  # ==================================================================
  # Shared Parser Code (injected into both editions)
  # ==================================================================

  defp shared_parser_code do
    quote do
      # UTF-8 codepoint byte size
      defp utf8_size(c) when c < 0x80, do: 1
      defp utf8_size(c) when c < 0x800, do: 2
      defp utf8_size(c) when c < 0x10000, do: 3
      defp utf8_size(_), do: 4

      # Return format helper - complete (no leftover)
      defp complete(events, line, ls, abs_pos) do
        {:lists.reverse(events), nil, line, ls, abs_pos}
      end

      # Return format helper - incomplete (has leftover starting at elem_start)
      defp incomplete(events, elem_start, line, ls, abs_pos) do
        {:lists.reverse(events), elem_start, line, ls, abs_pos}
      end

      # Calculate buffer start position from current and element positions
      defp buf_start(buf_pos, abs_pos, el_abs_pos) do
        buf_pos - (abs_pos - el_abs_pos)
      end

      # Note: new_event/6, new_event/7, and error/6 are generated by
      # generate_event_helpers/2 based on disabled events and position mode

      # ============================================================================
      # Public API
      # ============================================================================

      @doc """
      Parse complete XML (one-shot mode).
      Returns list of all events.
      """
      def parse(input) when is_binary(input) do
        stream([input]) |> Enum.to_list()
      end

      @doc """
      Stream XML from any enumerable source.
      Returns lazy stream of events (batched per block).
      """
      def stream(enumerable) do
        Stream.resource(
          fn -> init_stream(enumerable) end,
          &next_batch/1,
          fn _ -> :ok end
        )
      end

      @doc """
      Parse a single block of XML.
      """
      def parse_block(block, prev_block, prev_pos, line, ls, abs_pos)

      def parse_block(<<0xFE, 0xFF, _::binary>>, _, _, line, ls, abs_pos) do
        {[{:error, :utf16, nil, line, ls, abs_pos}], nil, line, ls, abs_pos}
      end

      def parse_block(<<0xFF, 0xFE, _::binary>>, _, _, line, ls, abs_pos) do
        {[{:error, :utf16, nil, line, ls, abs_pos}], nil, line, ls, abs_pos}
      end

      def parse_block(block, _, _, line, ls, abs_pos) do
        parse_content([], block, block, 0, abs_pos, line, ls)
      end

      # ============================================================================
      # Stream Helpers
      # ============================================================================

      defp init_stream(enumerable) do
        {enumerable, nil, 1, 0, 0, false}
      end

      defp next_batch({_source, _leftover, _line, _ls, _abs_pos, true} = state) do
        {:halt, state}
      end

      defp next_batch({source, leftover, line, ls, abs_pos, false}) do
        case get_chunk(source) do
          {:ok, chunk, rest} ->
            if leftover do
              handle_leftover(rest, leftover, chunk, line, ls, abs_pos)
            else
              handle_chunk(rest, chunk, line, ls, abs_pos)
            end

          :eof ->
            {:halt, {source, leftover, line, ls, abs_pos, true}}
        end
      end

      defp get_chunk([chunk | rest]) when is_binary(chunk), do: {:ok, chunk, rest}
      defp get_chunk([]), do: :eof

      defp get_chunk(stream) do
        case Enum.take(stream, 1) do
          [chunk] -> {:ok, chunk, Stream.drop(stream, 1)}
          [] -> :eof
        end
      end

      defp handle_chunk(rest, chunk, line, ls, abs_pos) do
        {events, leftover_pos, new_line, new_ls, new_abs_pos} =
          parse_block(chunk, nil, 0, line, ls, abs_pos)

        if leftover_pos do
          leftover = binary_part(chunk, leftover_pos, byte_size(chunk) - leftover_pos)
          {events, {rest, leftover, new_line, new_ls, new_abs_pos, false}}
        else
          {events, {rest, nil, new_line, new_ls, new_abs_pos, false}}
        end
      end

      defp handle_leftover(rest, leftover, chunk, line, ls, abs_pos) do
        case :binary.match(chunk, ">") do
          {pos, 1} ->
            mini = leftover <> binary_part(chunk, 0, pos + 1)

            {events, leftover_pos, new_line, new_ls, new_abs_pos} =
              parse_block(mini, nil, 0, line, ls, abs_pos)

            if leftover_pos do
              new_leftover = binary_part(mini, leftover_pos, byte_size(mini) - leftover_pos)

              handle_leftover_continue(
                rest,
                new_leftover,
                chunk,
                pos + 1,
                new_line,
                new_ls,
                new_abs_pos,
                events
              )
            else
              parse_rest_of_chunk(rest, chunk, pos + 1, new_line, new_ls, new_abs_pos, events)
            end

          :nomatch ->
            {[], {rest, leftover <> chunk, line, ls, abs_pos, false}}
        end
      end

      defp handle_leftover_continue(
             rest,
             leftover,
             chunk,
             search_start,
             line,
             ls,
             abs_pos,
             acc_events
           ) do
        remaining = byte_size(chunk) - search_start

        case :binary.match(chunk, ">", [{:scope, {search_start, remaining}}]) do
          {pos, 1} ->
            mini = leftover <> binary_part(chunk, search_start, pos - search_start + 1)

            {events, leftover_pos, new_line, new_ls, new_abs_pos} =
              parse_block(mini, nil, 0, line, ls, abs_pos)

            all_events = acc_events ++ events

            if leftover_pos do
              new_leftover = binary_part(mini, leftover_pos, byte_size(mini) - leftover_pos)

              handle_leftover_continue(
                rest,
                new_leftover,
                chunk,
                pos + 1,
                new_line,
                new_ls,
                new_abs_pos,
                all_events
              )
            else
              parse_rest_of_chunk(rest, chunk, pos + 1, new_line, new_ls, new_abs_pos, all_events)
            end

          :nomatch ->
            new_leftover = leftover <> binary_part(chunk, search_start, remaining)
            {acc_events, {rest, new_leftover, line, ls, abs_pos, false}}
        end
      end

      defp parse_rest_of_chunk(rest, chunk, start_pos, line, ls, abs_pos, acc_events) do
        chunk_remaining = byte_size(chunk) - start_pos

        if chunk_remaining > 0 do
          rest_chunk = binary_part(chunk, start_pos, chunk_remaining)

          {events, leftover_pos, new_line, new_ls, new_abs_pos} =
            parse_block(rest_chunk, nil, 0, line, ls, abs_pos)

          all_events = acc_events ++ events

          if leftover_pos do
            leftover = binary_part(rest_chunk, leftover_pos, byte_size(rest_chunk) - leftover_pos)
            {all_events, {rest, leftover, new_line, new_ls, new_abs_pos, false}}
          else
            {all_events, {rest, nil, new_line, new_ls, new_abs_pos, false}}
          end
        else
          {acc_events, {rest, nil, line, ls, abs_pos, false}}
        end
      end

      # ============================================================================
      # Content parsing - entry point
      # ============================================================================

      defp parse_content(events, <<>>, _xml, __buf_pos, abs_pos, line, ls) do
        complete(events, line, ls, abs_pos)
      end

      defp parse_content(events, <<"<", _::binary>> = rest, xml, buf_pos, abs_pos, line, ls) do
        parse_element(events, rest, xml, buf_pos, abs_pos, line, ls)
      end

      defp parse_content(events, <<c, _::binary>> = rest, xml, buf_pos, abs_pos, line, ls)
           when c in [?\s, ?\t, ?\n] do
        parse_ws(events, rest, xml, buf_pos, abs_pos, line, ls, line, ls, abs_pos)
      end

      defp parse_content(events, rest, xml, buf_pos, abs_pos, line, ls) do
        parse_text(events, rest, xml, buf_pos, abs_pos, line, ls, line, ls, abs_pos)
      end

      # ============================================================================
      # Text parsing
      # ============================================================================

      defp parse_ws(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos
           )
           when c in [?\s, ?\t] do
        parse_ws(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos
        )
      end

      defp parse_ws(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos
           ) do
        pos = abs_pos + 1
        parse_ws(events, rest, xml, buf_pos + 1, pos, line + 1, pos, el_line, el_ls, el_abs_pos)
      end

      defp parse_ws(
             events,
             <<"<", _::binary>> = rest,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos
           ) do
        start = buf_start(buf_pos, abs_pos, el_abs_pos)
        text = binary_part(xml, start, buf_pos - start)

        new_event(events, :space, text, el_line, el_ls, el_abs_pos)
        |> parse_element(rest, xml, buf_pos, abs_pos, line, ls)
      end

      defp parse_ws(events, <<>>, xml, buf_pos, abs_pos, line, ls, el_line, el_ls, el_abs_pos) do
        start = buf_start(buf_pos, abs_pos, el_abs_pos)
        text = binary_part(xml, start, buf_pos - start)

        events
        |> new_event(:space, text, el_line, el_ls, el_abs_pos)
        |> complete(line, ls, abs_pos)
      end

      # transition to characters if we find a non-space
      defp parse_ws(events, rest, xml, buf_pos, abs_pos, line, ls, el_line, el_ls, el_abs_pos) do
        parse_text(events, rest, xml, buf_pos, abs_pos, line, ls, el_line, el_ls, el_abs_pos)
      end

      # Match < before general character matching
      defp parse_text(
             events,
             <<"<", _::binary>> = rest,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos
           ) do
        start = buf_start(buf_pos, abs_pos, el_abs_pos)
        text = binary_part(xml, start, buf_pos - start)

        new_event(events, :characters, text, el_line, el_ls, el_abs_pos)
        |> parse_element(rest, xml, buf_pos, abs_pos, line, ls)
      end

      # Check for ]]> BEFORE general character matching (must come early!)
      # the string ]]> is not allowed in text
      defp parse_text(
             events,
             <<"]", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos
           ) do
        case rest do
          <<"]>", rest2::binary>> ->
            start = buf_start(buf_pos, abs_pos, el_abs_pos)
            text = binary_part(xml, start, buf_pos - start)

            new_event(events, :characters, text, el_line, el_ls, el_abs_pos)
            |> error(:text_cdata_end, "']]>' not allowed in text content", line, ls, abs_pos)
            |> parse_text(rest2, xml, buf_pos + 3, abs_pos + 3, line, ls, line, ls, abs_pos + 3)

          <<"]">> ->
            start = buf_start(buf_pos, abs_pos, el_abs_pos)
            text = binary_part(xml, start, buf_pos - start)
            incomplete(events, buf_pos, line, ls, abs_pos)

          _ ->
            parse_text(
              events,
              rest,
              xml,
              buf_pos + 1,
              abs_pos + 1,
              line,
              ls,
              el_line,
              el_ls,
              el_abs_pos
            )
        end
      end

      # ASCII fast path for valid XML chars (excludes <, ], control chars; newline/tab handled above)
      defp parse_text(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos
           )
           when c in 0x20..0x3B or c == 0x3D or c in 0x3F..0x5C or c in 0x5E..0x7F or c == 0x0D do
        parse_text(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos
        )
      end

      # Non-ASCII UTF-8: validate with is_xml_char guard
      defp parse_text(
             events,
             <<c::utf8, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos
           )
           when is_xml_char(c) do
        size = utf8_size(c)

        parse_text(
          events,
          rest,
          xml,
          buf_pos + size,
          abs_pos + size,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos
        )
      end

      defp parse_text(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos
           ) do
        pos = abs_pos + 1
        parse_text(events, rest, xml, buf_pos + 1, pos, line + 1, pos, el_line, el_ls, el_abs_pos)
      end

      defp parse_text(events, <<>>, xml, buf_pos, abs_pos, line, ls, el_line, el_ls, el_abs_pos) do
        start = buf_start(buf_pos, abs_pos, el_abs_pos)
        text = binary_part(xml, start, buf_pos - start)

        events
        |> new_event(:characters, text, el_line, el_ls, el_abs_pos)
        |> complete(line, ls, abs_pos)
      end

      # Invalid XML character - emit error and stop
      defp parse_text(
             events,
             <<c::utf8, _rest::binary>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _el_line,
             _el_ls,
             _el_abs_pos
           ) do
        error(
          events,
          :invalid_char,
          "Invalid XML character U+#{Integer.to_string(c, 16) |> String.pad_leading(4, "0")} in text content",
          line,
          ls,
          abs_pos
        )
        |> complete(line, ls, abs_pos)
      end

      # Malformed UTF-8 byte sequence - catch high bytes not matched by UTF-8 pattern
      defp parse_text(
             events,
             <<byte, _rest::binary>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _start
           )
           when byte >= 0x80 do
        error(
          events,
          :invalid_utf8,
          "Invalid UTF-8 byte sequence in text content",
          line,
          ls,
          abs_pos
        )
        |> complete(line, ls, abs_pos)
      end

      # ============================================================================
      # Element dispatch
      # ============================================================================

      defp parse_element(
             events,
             <<"<", rest2::binary>> = <<"<", c, _::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls
           )
           when is_name_start_ascii(c) do
        parse_open_tag_name(
          events,
          rest2,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          line,
          ls,
          abs_pos + 1,
          buf_pos
        )
      end

      defp parse_element(
             events,
             <<"<", rest2::binary>> = <<"<", c::utf8, _::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls
           )
           when is_name_start(c) do
        parse_open_tag_name(
          events,
          rest2,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          line,
          ls,
          abs_pos + 1,
          buf_pos
        )
      end

      defp parse_element(
             events,
             <<"</", rest2::binary>> = <<"</", c::utf8, _::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls
           )
           when is_name_start(c) do
        parse_close_tag_name(
          events,
          rest2,
          xml,
          buf_pos + 2,
          abs_pos + 2,
          line,
          ls,
          line,
          ls,
          abs_pos + 2,
          buf_pos
        )
      end

      defp parse_element(events, <<"</", _::binary>>, _xml, _buf_pos, abs_pos, line, ls) do
        error(
          events,
          :invalid_close_tag,
          "Close tag must start with a valid name character",
          line,
          ls,
          abs_pos + 2
        )
        |> complete(line, ls, abs_pos + 2)
      end

      defp parse_element(events, <<"<!--", rest::binary>>, xml, buf_pos, abs_pos, line, ls) do
        parse_comment(
          events,
          rest,
          xml,
          buf_pos + 4,
          abs_pos + 4,
          line,
          ls,
          line,
          ls,
          abs_pos + 4,
          false,
          buf_pos
        )
      end

      defp parse_element(events, <<"<![CDATA[", rest::binary>>, xml, buf_pos, abs_pos, line, ls) do
        parse_cdata(
          events,
          rest,
          xml,
          buf_pos + 9,
          abs_pos + 9,
          line,
          ls,
          line,
          ls,
          abs_pos + 9,
          buf_pos
        )
      end

      defp parse_element(events, <<"<!DOCTYPE", rest::binary>>, xml, buf_pos, abs_pos, line, ls) do
        parse_doctype(
          events,
          rest,
          xml,
          buf_pos + 9,
          abs_pos + 9,
          line,
          ls,
          line,
          ls,
          abs_pos + 1,
          buf_pos + 2,
          1,
          nil,
          buf_pos
        )
      end

      # Reject case variants of 'xml' as PI target (<?XML, <?Xml, etc.)
      # Must come before the valid <?xml clause
      defp parse_element(
             events,
             <<"<?", x, m, l, rest::binary>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls
           )
           when (x == ?X or x == ?x) and (m == ?M or m == ?m) and (l == ?L or l == ?l) and
                  not (x == ?x and m == ?m and l == ?l) do
        # This matches any case variant of 'xml' EXCEPT lowercase 'xml'
        # Check if followed by whitespace or ?> (PI syntax)
        case rest do
          <<ws, _::binary>> when ws in [?\s, ?\t, ?\n, ??] ->
            variant = <<x, m, l>>

            events
            |> error(
              :reserved_pi_target,
              "PI target '#{variant}' is reserved (case-insensitive match for 'xml')",
              line,
              ls,
              abs_pos
            )
            |> complete(line, ls, abs_pos)

          _ ->
            # Not followed by valid PI delimiter, let it fall through
            # to error as malformed PI
            events
            |> error(:invalid_pi, "Malformed processing instruction", line, ls, abs_pos)
            |> complete(line, ls, abs_pos)
        end
      end

      # XML declaration - only valid at document start (abs_pos == 0)
      defp parse_element(
             events,
             <<"<?xml", ws, rest::binary>>,
             xml,
             buf_pos,
             0 = abs_pos,
             line,
             ls
           )
           when ws in [?\s, ?\t] do
        parse_prolog(
          events,
          rest,
          xml,
          buf_pos + 6,
          abs_pos + 6,
          line,
          ls,
          line,
          ls,
          abs_pos + 1,
          buf_pos
        )
      end

      defp parse_element(
             events,
             <<"<?xml\n", rest::binary>>,
             xml,
             buf_pos,
             0 = abs_pos,
             line,
             _ls
           ) do
        parse_prolog(
          events,
          rest,
          xml,
          buf_pos + 6,
          abs_pos + 6,
          line + 1,
          abs_pos + 6,
          line,
          0,
          abs_pos + 1,
          buf_pos
        )
      end

      # Reject <?xml when it appears after document start (abs_pos != 0)
      # XML declaration is only valid at absolute position 0
      defp parse_element(
             events,
             <<"<?xml", ws, _rest::binary>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls
           )
           when abs_pos != 0 and ws in [?\s, ?\t, ?\n] do
        events
        |> error(
          :misplaced_xml_decl,
          "XML declaration is only valid at document start (found at position #{abs_pos})",
          line,
          ls,
          abs_pos
        )
        |> complete(line, ls, abs_pos)
      end

      # Malformed XML declaration at document start - missing whitespace after <?xml
      # Note: Excludes '-' and '.' to allow PI targets like "xml-stylesheet"
      defp parse_element(
             events,
             <<"<?xml", c, _::binary>>,
             _xml,
             _buf_pos,
             0 = abs_pos,
             line,
             ls
           )
           when c not in [?\s, ?\t, ?\n, ?\?, ?-, ?.] do
        error(
          events,
          :malformed_xml_decl,
          "Missing whitespace after '<?xml' in XML declaration",
          line,
          ls,
          abs_pos
        )
        |> complete(line, ls, abs_pos + 5)
      end

      defp parse_element(
             events,
             <<"<?", rest2::binary>> = <<"<?", c::utf8, _::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls
           )
           when is_name_start(c) do
        parse_pi_name(
          events,
          rest2,
          xml,
          buf_pos + 2,
          abs_pos + 2,
          line,
          ls,
          line,
          ls,
          abs_pos + 2,
          buf_pos
        )
      end

      defp parse_element(events, <<"<?", _::binary>>, _xml, _buf_pos, abs_pos, line, ls) do
        error(
          events,
          :invalid_pi_target,
          "PI target must start with a valid name character",
          line,
          ls,
          abs_pos + 2
        )
        |> complete(line, ls, abs_pos + 2)
      end

      defp parse_element(events, <<"<">>, _xml, buf_pos, abs_pos, line, ls) do
        incomplete(events, buf_pos, line, ls, abs_pos)
      end

      defp parse_element(events, <<"<!">>, _xml, buf_pos, abs_pos, line, ls) do
        incomplete(events, buf_pos, line, ls, abs_pos)
      end

      defp parse_element(events, <<"<!-">>, _xml, buf_pos, abs_pos, line, ls) do
        incomplete(events, buf_pos, line, ls, abs_pos)
      end

      defp parse_element(events, <<"<![">>, _xml, buf_pos, abs_pos, line, ls) do
        incomplete(events, buf_pos, line, ls, abs_pos)
      end

      defp parse_element(events, <<"<![C">>, _xml, buf_pos, abs_pos, line, ls) do
        incomplete(events, buf_pos, line, ls, abs_pos)
      end

      defp parse_element(events, <<"<![CD">>, _xml, buf_pos, abs_pos, line, ls) do
        incomplete(events, buf_pos, line, ls, abs_pos)
      end

      defp parse_element(events, <<"<![CDA">>, _xml, buf_pos, abs_pos, line, ls) do
        incomplete(events, buf_pos, line, ls, abs_pos)
      end

      defp parse_element(events, <<"<![CDAT">>, _xml, buf_pos, abs_pos, line, ls) do
        incomplete(events, buf_pos, line, ls, abs_pos)
      end

      defp parse_element(events, <<"<![CDATA">>, _xml, buf_pos, abs_pos, line, ls) do
        incomplete(events, buf_pos, line, ls, abs_pos)
      end

      defp parse_element(events, _, _xml, _buf_pos, abs_pos, line, ls) do
        new_events = error(events, :invalid_element, nil, line, ls, abs_pos)
        complete(new_events, line, ls, abs_pos)
      end

      # ============================================================================
      # Open tag name
      # ============================================================================

      defp parse_open_tag_name(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_open_tag_name(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           )
           when is_name_char_ascii(c) do
        parse_open_tag_name(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      defp parse_open_tag_name(
             events,
             <<c::utf8, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           )
           when is_name_char(c) do
        size = utf8_size(c)

        parse_open_tag_name(
          events,
          rest,
          xml,
          buf_pos + size,
          abs_pos + size,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      defp parse_open_tag_name(
             events,
             rest,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           ) do
        start = buf_start(buf_pos, abs_pos, el_abs_pos)
        name = binary_part(xml, start, buf_pos - start)

        finish_open_tag(
          events,
          rest,
          xml,
          buf_pos,
          abs_pos,
          line,
          ls,
          name,
          [],
          [],
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      # ============================================================================
      # Finish open tag (parse attributes)
      # ============================================================================

      defp finish_open_tag(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _name,
             _attrs,
             _seen,
             _el_line,
             _el_ls,
             _el_abs_pos,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp finish_open_tag(
             events,
             <<"/>", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             attrs,
             _seen,
             el_line,
             el_ls,
             el_abs_pos,
             _elem_start
           ) do
        new_events =
          new_event(
            new_event(events, :start_element, name, attrs, el_line, el_ls, el_abs_pos),
            :end_element,
            name,
            el_line,
            el_ls,
            el_abs_pos
          )

        parse_content(new_events, rest, xml, buf_pos + 2, abs_pos + 2, line, ls)
      end

      defp finish_open_tag(
             events,
             <<">", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             attrs,
             _seen,
             el_line,
             el_ls,
             el_abs_pos,
             _elem_start
           ) do
        new_events = new_event(events, :start_element, name, attrs, el_line, el_ls, el_abs_pos)
        parse_content(new_events, rest, xml, buf_pos + 1, abs_pos + 1, line, ls)
      end

      defp finish_open_tag(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           )
           when c in [?\s, ?\t] do
        finish_open_tag_ws(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          name,
          attrs,
          seen,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      defp finish_open_tag(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             _ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           ) do
        finish_open_tag_ws(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line + 1,
          abs_pos + 1,
          name,
          attrs,
          seen,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      defp finish_open_tag(
             events,
             <<c::utf8, _::binary>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _name,
             _attrs,
             _seen,
             _loc,
             _elem_start
           )
           when is_name_start(c) do
        new_events = error(events, :missing_whitespace_before_attr, nil, line, ls, abs_pos)
        complete(new_events, line, ls, abs_pos)
      end

      defp finish_open_tag(
             events,
             <<"/">>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _name,
             _attrs,
             _seen,
             _loc,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp finish_open_tag(
             events,
             _,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _name,
             _attrs,
             _seen,
             _loc,
             _elem_start
           ) do
        new_events = error(events, :expected_gt_or_attr, nil, line, ls, abs_pos)
        complete(new_events, line, ls, abs_pos)
      end

      defp finish_open_tag_ws(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _name,
             _attrs,
             _seen,
             _loc,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp finish_open_tag_ws(
             events,
             <<"/>", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             attrs,
             _seen,
             el_line,
             el_ls,
             el_abs_pos,
             _elem_start
           ) do
        events =
          new_event(
            new_event(events, :start_element, name, attrs, el_line, el_ls, el_abs_pos),
            :end_element,
            name,
            el_line,
            el_ls,
            el_abs_pos
          )

        parse_content(events, rest, xml, buf_pos + 2, abs_pos + 2, line, ls)
      end

      defp finish_open_tag_ws(
             events,
             <<">", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             attrs,
             _seen,
             el_line,
             el_ls,
             el_abs_pos,
             _elem_start
           ) do
        events
        |> new_event(:start_element, name, attrs, el_line, el_ls, el_abs_pos)
        |> parse_content(rest, xml, buf_pos + 1, abs_pos + 1, line, ls)
      end

      defp finish_open_tag_ws(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           )
           when c in [?\s, ?\t] do
        finish_open_tag_ws(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          name,
          attrs,
          seen,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      defp finish_open_tag_ws(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             _ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           ) do
        finish_open_tag_ws(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line + 1,
          abs_pos + 1,
          name,
          attrs,
          seen,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      defp finish_open_tag_ws(
             events,
             <<c::utf8, _::binary>> = rest,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           )
           when is_name_start(c) do
        parse_attr_name(
          events,
          rest,
          xml,
          buf_pos,
          abs_pos,
          line,
          ls,
          name,
          attrs,
          seen,
          line,
          ls,
          abs_pos,
          elem_start
        )
      end

      defp finish_open_tag_ws(
             events,
             <<"/">>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _name,
             _attrs,
             _seen,
             _loc,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp finish_open_tag_ws(
             events,
             _,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _name,
             _attrs,
             _seen,
             _loc,
             _elem_start
           ) do
        events
        |> error(:expected_gt_or_attr, nil, line, ls, abs_pos)
        |> complete(line, ls, abs_pos)
      end

      # ============================================================================
      # Attribute parsing
      # ============================================================================

      defp parse_attr_name(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _name,
             _attrs,
             _seen,
             _loc,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_attr_name(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           )
           when is_name_char_ascii(c) do
        parse_attr_name(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          name,
          attrs,
          seen,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      defp parse_attr_name(
             events,
             <<c::utf8, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           )
           when is_name_char(c) do
        size = utf8_size(c)

        parse_attr_name(
          events,
          rest,
          xml,
          buf_pos + size,
          abs_pos + size,
          line,
          ls,
          name,
          attrs,
          seen,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      defp parse_attr_name(
             events,
             rest,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           ) do
        start = buf_start(buf_pos, abs_pos, el_abs_pos)
        attr_name = binary_part(xml, start, buf_pos - start)

        parse_attr_eq(
          events,
          rest,
          xml,
          buf_pos,
          abs_pos,
          line,
          ls,
          name,
          attrs,
          seen,
          el_line,
          el_ls,
          el_abs_pos,
          attr_name,
          elem_start
        )
      end

      defp parse_attr_eq(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _name,
             _attrs,
             _seen,
             _loc,
             _attr_name,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_attr_eq(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             attr_name,
             elem_start
           )
           when c in [?\s, ?\t] do
        parse_attr_eq(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          name,
          attrs,
          seen,
          el_line,
          el_ls,
          el_abs_pos,
          attr_name,
          elem_start
        )
      end

      defp parse_attr_eq(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             _ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             attr_name,
             elem_start
           ) do
        parse_attr_eq(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line + 1,
          abs_pos + 1,
          name,
          attrs,
          seen,
          el_line,
          el_ls,
          el_abs_pos,
          attr_name,
          elem_start
        )
      end

      defp parse_attr_eq(
             events,
             <<"=", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             attr_name,
             elem_start
           ) do
        parse_attr_quote(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          name,
          attrs,
          seen,
          el_line,
          el_ls,
          el_abs_pos,
          attr_name,
          elem_start
        )
      end

      defp parse_attr_eq(
             events,
             _,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _name,
             _attrs,
             _seen,
             _loc,
             _attr_name,
             _elem_start
           ) do
        events
        |> error(:expected_eq, nil, line, ls, abs_pos)
        |> complete(line, ls, abs_pos)
      end

      defp parse_attr_quote(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _name,
             _attrs,
             _seen,
             _loc,
             _attr_name,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_attr_quote(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             attr_name,
             elem_start
           )
           when c in [?\s, ?\t] do
        parse_attr_quote(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          name,
          attrs,
          seen,
          el_line,
          el_ls,
          el_abs_pos,
          attr_name,
          elem_start
        )
      end

      defp parse_attr_quote(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             _ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             attr_name,
             elem_start
           ) do
        parse_attr_quote(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line + 1,
          abs_pos + 1,
          name,
          attrs,
          seen,
          el_line,
          el_ls,
          el_abs_pos,
          attr_name,
          elem_start
        )
      end

      defp parse_attr_quote(
             events,
             <<q, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             attr_name,
             elem_start
           )
           when q in [?", ?'] do
        parse_attr_value(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          name,
          attrs,
          seen,
          line,
          ls,
          abs_pos + 1,
          attr_name,
          q,
          elem_start
        )
      end

      defp parse_attr_quote(
             events,
             _,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _name,
             _attrs,
             _seen,
             _loc,
             _attr_name,
             _elem_start
           ) do
        events
        |> error(:expected_quote, nil, line, ls, abs_pos)
        |> complete(line, ls, abs_pos)
      end

      defp parse_attr_value(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _name,
             _attrs,
             _seen,
             _el_line,
             _el_ls,
             _el_abs_pos,
             _attr_name,
             _quote,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_attr_value(
             events,
             <<q, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             attr_name,
             q,
             elem_start
           ) do
        start = buf_start(buf_pos, abs_pos, el_abs_pos)
        value = binary_part(xml, start, buf_pos - start)

        {new_attrs, new_seen, events} =
          if attr_name in seen do
            events = error(events, :attr_unique, nil, el_line, el_ls, el_abs_pos)
            {[{attr_name, value} | attrs], seen, events}
          else
            {[{attr_name, value} | attrs], [attr_name | seen], events}
          end

        finish_open_tag(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          name,
          new_attrs,
          new_seen,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      defp parse_attr_value(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             _ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             attr_name,
             quote,
             elem_start
           ) do
        parse_attr_value(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line + 1,
          abs_pos + 1,
          name,
          attrs,
          seen,
          el_line,
          el_ls,
          el_abs_pos,
          attr_name,
          quote,
          elem_start
        )
      end

      defp parse_attr_value(
             events,
             <<"<", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             attr_name,
             quote,
             elem_start
           ) do
        events =
          error(events, :attr_lt, "'<' not allowed in attribute value", line, ls, abs_pos)

        parse_attr_value(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          name,
          attrs,
          seen,
          el_line,
          el_ls,
          el_abs_pos,
          attr_name,
          quote,
          elem_start
        )
      end

      # ASCII fast path for valid XML chars (excludes <, ", ', &, control chars; newline handled above)
      defp parse_attr_value(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             attr_name,
             quote,
             elem_start
           )
           when c in 0x20..0x21 or c in 0x23..0x25 or c in 0x28..0x3B or c == 0x3D or
                  c in 0x3F..0x7F or c == 0x09 or c == 0x0D do
        parse_attr_value(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          name,
          attrs,
          seen,
          el_line,
          el_ls,
          el_abs_pos,
          attr_name,
          quote,
          elem_start
        )
      end

      # Non-ASCII UTF-8: validate with is_xml_char guard
      defp parse_attr_value(
             events,
             <<c::utf8, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             attrs,
             seen,
             el_line,
             el_ls,
             el_abs_pos,
             attr_name,
             quote,
             elem_start
           )
           when is_xml_char(c) do
        size = utf8_size(c)

        parse_attr_value(
          events,
          rest,
          xml,
          buf_pos + size,
          abs_pos + size,
          line,
          ls,
          name,
          attrs,
          seen,
          el_line,
          el_ls,
          el_abs_pos,
          attr_name,
          quote,
          elem_start
        )
      end

      # Invalid XML character - emit error and stop
      defp parse_attr_value(
             events,
             <<c::utf8, _rest::binary>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _name,
             _attrs,
             _seen,
             _loc,
             _attr_name,
             _quote,
             _elem_start
           ) do
        events =
          error(
            events,
            :invalid_char,
            "Invalid XML character U+#{Integer.to_string(c, 16) |> String.pad_leading(4, "0")} in attribute value",
            line,
            ls,
            abs_pos
          )

        complete(events, line, ls, abs_pos)
      end

      # Malformed UTF-8 byte sequence - catch high bytes not matched by UTF-8 pattern
      defp parse_attr_value(
             events,
             <<byte, _rest::binary>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _name,
             _attrs,
             _seen,
             _loc,
             _attr_name,
             _quote,
             _elem_start
           )
           when byte >= 0x80 do
        events =
          error(
            events,
            :invalid_utf8,
            "Invalid UTF-8 byte sequence in attribute value",
            line,
            ls,
            abs_pos
          )

        complete(events, line, ls, abs_pos)
      end

      # ============================================================================
      # Close tag
      # ============================================================================

      defp parse_close_tag_name(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_close_tag_name(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           )
           when is_name_char_ascii(c) do
        parse_close_tag_name(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      defp parse_close_tag_name(
             events,
             <<c::utf8, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           )
           when is_name_char(c) do
        size = utf8_size(c)

        parse_close_tag_name(
          events,
          rest,
          xml,
          buf_pos + size,
          abs_pos + size,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      defp parse_close_tag_name(
             events,
             rest,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           ) do
        start = buf_start(buf_pos, abs_pos, el_abs_pos)
        name = binary_part(xml, start, buf_pos - start)

        parse_close_tag_end(
          events,
          rest,
          xml,
          buf_pos,
          abs_pos,
          line,
          ls,
          name,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      defp parse_close_tag_end(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _name,
             _loc,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_close_tag_end(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           )
           when c in [?\s, ?\t] do
        parse_close_tag_end(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          name,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      defp parse_close_tag_end(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             _ls,
             name,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           ) do
        parse_close_tag_end(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line + 1,
          abs_pos + 1,
          name,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      defp parse_close_tag_end(
             events,
             <<">", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             name,
             el_line,
             el_ls,
             el_abs_pos,
             _elem_start
           ) do
        events
        |> new_event(:end_element, name, el_line, el_ls, el_abs_pos)
        |> parse_content(rest, xml, buf_pos + 1, abs_pos + 1, line, ls)
      end

      defp parse_close_tag_end(
             events,
             _,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _name,
             _loc,
             _elem_start
           ) do
        events
        |> error(:expected_gt, nil, line, ls, abs_pos)
        |> complete(line, ls, abs_pos)
      end

      # ============================================================================
      # Comment
      # ============================================================================

      defp parse_comment(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _has_double_dash,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_comment(
             events,
             <<"-->", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             has_double_dash,
             _elem_start
           ) do
        start = buf_start(buf_pos, abs_pos, el_abs_pos)
        comment = binary_part(xml, start, buf_pos - start)

        events
        |> new_event(:comment, comment, el_line, el_ls, el_abs_pos)
        |> then(fn events ->
          if has_double_dash do
            error(events, :comment, nil, el_line, el_ls, el_abs_pos)
          else
            events
          end
        end)
        |> parse_content(rest, xml, buf_pos + 3, abs_pos + 3, line, ls)
      end

      defp parse_comment(
             events,
             <<"--->", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             _has_double_dash,
             _elem_start
           ) do
        start = buf_start(buf_pos, abs_pos, el_abs_pos)
        comment = binary_part(xml, start, buf_pos - start + 1)

        events
        |> new_event(:comment, comment, el_line, el_ls, el_abs_pos)
        |> error(:comment, nil, el_line, el_ls, el_abs_pos)
        |> parse_content(rest, xml, buf_pos + 4, abs_pos + 4, line, ls)
      end

      defp parse_comment(
             events,
             <<"--", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             _has_double_dash,
             elem_start
           ) do
        parse_comment(
          events,
          rest,
          xml,
          buf_pos + 2,
          abs_pos + 2,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          true,
          elem_start
        )
      end

      defp parse_comment(
             events,
             <<"-">>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _start,
             _has_double_dash,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_comment(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             _ls,
             el_line,
             el_ls,
             el_abs_pos,
             has_double_dash,
             elem_start
           ) do
        parse_comment(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line + 1,
          abs_pos + 1,
          el_line,
          el_ls,
          el_abs_pos,
          has_double_dash,
          elem_start
        )
      end

      # ASCII fast path for valid XML chars (excludes -, control chars; newline handled above)
      defp parse_comment(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             has_double_dash,
             elem_start
           )
           when c in 0x20..0x2C or c in 0x2E..0x7F or c == 0x09 or c == 0x0D do
        parse_comment(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          has_double_dash,
          elem_start
        )
      end

      # Handle single dash followed by non-dash (valid in comment)
      defp parse_comment(
             events,
             <<"-", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             has_double_dash,
             elem_start
           ) do
        parse_comment(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          has_double_dash,
          elem_start
        )
      end

      # Non-ASCII UTF-8: validate with is_xml_char guard
      defp parse_comment(
             events,
             <<c::utf8, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             has_double_dash,
             elem_start
           )
           when is_xml_char(c) do
        size = utf8_size(c)

        parse_comment(
          events,
          rest,
          xml,
          buf_pos + size,
          abs_pos + size,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          has_double_dash,
          elem_start
        )
      end

      # Invalid XML character - emit error and stop
      defp parse_comment(
             events,
             <<c::utf8, _rest::binary>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _has_double_dash,
             _elem_start
           ) do
        events =
          error(
            events,
            :invalid_char,
            "Invalid XML character U+#{Integer.to_string(c, 16) |> String.pad_leading(4, "0")} in comment",
            line,
            ls,
            abs_pos
          )

        complete(events, line, ls, abs_pos)
      end

      # Malformed UTF-8 byte sequence - catch high bytes not matched by UTF-8 pattern
      defp parse_comment(
             events,
             <<byte, _rest::binary>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _has_double_dash,
             _elem_start
           )
           when byte >= 0x80 do
        events =
          error(
            events,
            :invalid_utf8,
            "Invalid UTF-8 byte sequence in comment",
            line,
            ls,
            abs_pos
          )

        complete(events, line, ls, abs_pos)
      end

      # ============================================================================
      # CDATA
      # ============================================================================

      defp parse_cdata(events, <<>>, _xml, _buf_pos, abs_pos, line, ls, _loc, elem_start) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_cdata(
             events,
             <<"]]>", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             _elem_start
           ) do
        start = buf_start(buf_pos, abs_pos, el_abs_pos)
        cdata = binary_part(xml, start, buf_pos - start)

        events
        |> new_event(:cdata, cdata, el_line, el_ls, el_abs_pos)
        |> parse_content(rest, xml, buf_pos + 3, abs_pos + 3, line, ls)
      end

      defp parse_cdata(
             events,
             <<"]]">>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_cdata(
             events,
             <<"]">>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_cdata(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             _ls,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           ) do
        parse_cdata(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line + 1,
          abs_pos + 1,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      # ASCII fast path for valid XML chars (excludes ], control chars; newline handled above)
      defp parse_cdata(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           )
           when c in 0x20..0x5C or c in 0x5E..0x7F or c == 0x09 or c == 0x0D do
        parse_cdata(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      # Handle single ] (valid in CDATA until ]]>)
      defp parse_cdata(
             events,
             <<"]", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           ) do
        parse_cdata(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      # Non-ASCII UTF-8: validate with is_xml_char guard
      defp parse_cdata(
             events,
             <<c::utf8, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           )
           when is_xml_char(c) do
        size = utf8_size(c)

        parse_cdata(
          events,
          rest,
          xml,
          buf_pos + size,
          abs_pos + size,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      # Invalid XML character - emit error and stop
      defp parse_cdata(
             events,
             <<c::utf8, _rest::binary>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _elem_start
           ) do
        events =
          error(
            events,
            :invalid_char,
            "Invalid XML character U+#{Integer.to_string(c, 16) |> String.pad_leading(4, "0")} in CDATA",
            line,
            ls,
            abs_pos
          )

        complete(events, line, ls, abs_pos)
      end

      # Malformed UTF-8 byte sequence - catch high bytes not matched by UTF-8 pattern
      defp parse_cdata(
             events,
             <<byte, _rest::binary>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _elem_start
           )
           when byte >= 0x80 do
        events =
          error(events, :invalid_utf8, "Invalid UTF-8 byte sequence in CDATA", line, ls, abs_pos)

        complete(events, line, ls, abs_pos)
      end

      # ============================================================================
      # DOCTYPE
      # ============================================================================

      defp parse_doctype(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _el_line,
             _el_ls,
             _el_abs_pos,
             _start,
             _dtd_depth,
             _quote,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_doctype(
             events,
             <<">", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             start,
             1,
             nil,
             _elem_start
           ) do
        content = binary_part(xml, start, buf_pos - start)

        events
        |> new_event(:dtd, content, el_line, el_ls, el_abs_pos)
        |> parse_content(rest, xml, buf_pos + 1, abs_pos + 1, line, ls)
      end

      defp parse_doctype(
             events,
             <<">", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             start,
             dtd_depth,
             nil,
             elem_start
           ) do
        parse_doctype(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          start,
          dtd_depth - 1,
          nil,
          elem_start
        )
      end

      defp parse_doctype(
             events,
             <<">", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             start,
             dtd_depth,
             quote,
             elem_start
           ) do
        parse_doctype(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          start,
          dtd_depth,
          quote,
          elem_start
        )
      end

      # Comment inside DOCTYPE - enter comment mode to ignore quote characters
      # Only match when NOT inside a quoted string (quote == nil)
      defp parse_doctype(
             events,
             <<"<!--", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             start,
             dtd_depth,
             nil,
             elem_start
           ) do
        parse_doctype_comment(
          events,
          rest,
          xml,
          buf_pos + 4,
          abs_pos + 4,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          start,
          dtd_depth,
          elem_start
        )
      end

      defp parse_doctype(
             events,
             <<"<", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             start,
             dtd_depth,
             nil,
             elem_start
           ) do
        parse_doctype(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          start,
          dtd_depth + 1,
          nil,
          elem_start
        )
      end

      defp parse_doctype(
             events,
             <<"<", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             start,
             dtd_depth,
             quote,
             elem_start
           ) do
        parse_doctype(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          start,
          dtd_depth,
          quote,
          elem_start
        )
      end

      defp parse_doctype(
             events,
             <<"\"", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             start,
             dtd_depth,
             nil,
             elem_start
           ) do
        parse_doctype(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          start,
          dtd_depth,
          ?",
          elem_start
        )
      end

      defp parse_doctype(
             events,
             <<"\"", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             start,
             dtd_depth,
             ?",
             elem_start
           ) do
        parse_doctype(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          start,
          dtd_depth,
          nil,
          elem_start
        )
      end

      defp parse_doctype(
             events,
             <<"'", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             start,
             dtd_depth,
             nil,
             elem_start
           ) do
        parse_doctype(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          start,
          dtd_depth,
          ?',
          elem_start
        )
      end

      defp parse_doctype(
             events,
             <<"'", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             start,
             dtd_depth,
             ?',
             elem_start
           ) do
        parse_doctype(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          start,
          dtd_depth,
          nil,
          elem_start
        )
      end

      defp parse_doctype(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             _ls,
             el_line,
             el_ls,
             el_abs_pos,
             start,
             dtd_depth,
             quote,
             elem_start
           ) do
        parse_doctype(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line + 1,
          abs_pos + 1,
          el_line,
          el_ls,
          el_abs_pos,
          start,
          dtd_depth,
          quote,
          elem_start
        )
      end

      defp parse_doctype(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             start,
             dtd_depth,
             quote,
             elem_start
           )
           when c in 0x20..0x21 or c in 0x23..0x26 or c in 0x28..0x3B or c == 0x3D or
                  c in 0x3F..0x7F or c == 0x9 or c == 0xD do
        parse_doctype(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          start,
          dtd_depth,
          quote,
          elem_start
        )
      end

      defp parse_doctype(
             events,
             <<c::utf8, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             start,
             dtd_depth,
             quote,
             elem_start
           )
           when is_xml_char(c) do
        size = utf8_size(c)

        parse_doctype(
          events,
          rest,
          xml,
          buf_pos + size,
          abs_pos + size,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          start,
          dtd_depth,
          quote,
          elem_start
        )
      end

      defp parse_doctype(
             events,
             <<c::utf8, _rest::binary>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _el_line,
             _el_ls,
             _el_abs_pos,
             _start,
             _dtd_depth,
             _quote,
             _elem_start
           ) do
        events =
          error(
            events,
            :invalid_char,
            "Invalid XML character U+#{Integer.to_string(c, 16) |> String.pad_leading(4, "0")} in DOCTYPE",
            line,
            ls,
            abs_pos
          )

        complete(events, line, ls, abs_pos)
      end

      # ============================================================================
      # DOCTYPE Comment - skips comment content inside DOCTYPE
      # ============================================================================

      # Incomplete - waiting for more data
      defp parse_doctype_comment(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _el_line,
             _el_ls,
             _el_abs_pos,
             _start,
             _dtd_depth,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      # End of comment - return to normal DOCTYPE parsing
      defp parse_doctype_comment(
             events,
             <<"-->", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             start,
             dtd_depth,
             elem_start
           ) do
        parse_doctype(
          events,
          rest,
          xml,
          buf_pos + 3,
          abs_pos + 3,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          start,
          dtd_depth,
          nil,
          elem_start
        )
      end

      # Newline in comment - track line numbers
      defp parse_doctype_comment(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             _ls,
             el_line,
             el_ls,
             el_abs_pos,
             start,
             dtd_depth,
             elem_start
           ) do
        parse_doctype_comment(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line + 1,
          abs_pos + 1,
          el_line,
          el_ls,
          el_abs_pos,
          start,
          dtd_depth,
          elem_start
        )
      end

      # Skip any other character in comment
      defp parse_doctype_comment(
             events,
             <<_c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             start,
             dtd_depth,
             elem_start
           ) do
        parse_doctype_comment(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          start,
          dtd_depth,
          elem_start
        )
      end

      # Multi-byte UTF-8 characters in comment
      defp parse_doctype_comment(
             events,
             <<c::utf8, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             start,
             dtd_depth,
             elem_start
           ) do
        size = utf8_size(c)

        parse_doctype_comment(
          events,
          rest,
          xml,
          buf_pos + size,
          abs_pos + size,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          start,
          dtd_depth,
          elem_start
        )
      end

      # ============================================================================
      # Processing instruction
      # ============================================================================

      defp parse_pi_name(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _el_line,
             _el_ls,
             _el_abs_pos,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_pi_name(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           )
           when is_name_char_ascii(c) do
        parse_pi_name(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      defp parse_pi_name(
             events,
             <<c::utf8, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           )
           when is_name_char(c) do
        size = utf8_size(c)

        parse_pi_name(
          events,
          rest,
          xml,
          buf_pos + size,
          abs_pos + size,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      defp parse_pi_name(
             events,
             rest,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           ) do
        start = buf_start(buf_pos, abs_pos, el_abs_pos)
        target = binary_part(xml, start, buf_pos - start)

        # Check for reserved "xml" target (case-insensitive)
        # Per XML spec: "The target names 'XML', 'xml', and so on are reserved"
        if String.downcase(target) == "xml" do
          events =
            error(
              events,
              :reserved_pi_target,
              "PI target 'xml' is reserved",
              line,
              ls,
              abs_pos - byte_size(target)
            )

          complete(events, line, ls, abs_pos)
        else
          parse_pi_content(
            events,
            rest,
            xml,
            buf_pos,
            abs_pos,
            line,
            ls,
            el_line,
            el_ls,
            el_abs_pos,
            target,
            abs_pos,  # content_start_abs_pos - content starts after target name
            elem_start
          )
        end
      end

      defp parse_pi_content(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _el_line,
             _el_ls,
             _el_abs_pos,
             _target,
             _content_start_abs_pos,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_pi_content(
             events,
             <<"?>", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             target,
             content_start_abs_pos,
             _elem_start
           ) do
        start = buf_start(buf_pos, abs_pos, content_start_abs_pos)
        content = binary_part(xml, start, buf_pos - start)

        events
        |> new_event(:processing_instruction, target, content, el_line, el_ls, el_abs_pos)
        |> parse_content(rest, xml, buf_pos + 2, abs_pos + 2, line, ls)
      end

      defp parse_pi_content(
             events,
             <<"?">>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _el_line,
             _el_ls,
             _el_abs_pos,
             _target,
             _content_start_abs_pos,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_pi_content(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             _ls,
             el_line,
             el_ls,
             el_abs_pos,
             target,
             content_start_abs_pos,
             elem_start
           ) do
        parse_pi_content(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line + 1,
          abs_pos + 1,
          el_line,
          el_ls,
          el_abs_pos,
          target,
          content_start_abs_pos,
          elem_start
        )
      end

      # ASCII fast path for valid XML chars (excludes ?, control chars; newline handled above)
      defp parse_pi_content(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             target,
             content_start_abs_pos,
             elem_start
           )
           when c in 0x20..0x3E or c in 0x40..0x7F or c == 0x09 or c == 0x0D do
        parse_pi_content(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          target,
          content_start_abs_pos,
          elem_start
        )
      end

      # Handle single ? (valid in PI content until ?>)
      defp parse_pi_content(
             events,
             <<"?", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             target,
             content_start_abs_pos,
             elem_start
           ) do
        parse_pi_content(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          target,
          content_start_abs_pos,
          elem_start
        )
      end

      # Non-ASCII UTF-8: validate with is_xml_char guard
      defp parse_pi_content(
             events,
             <<c::utf8, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             target,
             content_start_abs_pos,
             elem_start
           )
           when is_xml_char(c) do
        size = utf8_size(c)

        parse_pi_content(
          events,
          rest,
          xml,
          buf_pos + size,
          abs_pos + size,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          target,
          content_start_abs_pos,
          elem_start
        )
      end

      # Invalid XML character - emit error and stop
      defp parse_pi_content(
             events,
             <<c::utf8, _rest::binary>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _el_line,
             _el_ls,
             _el_abs_pos,
             _target,
             _content_start_abs_pos,
             _elem_start
           ) do
        events =
          error(
            events,
            :invalid_char,
            "Invalid XML character U+#{Integer.to_string(c, 16) |> String.pad_leading(4, "0")} in processing instruction",
            line,
            ls,
            abs_pos
          )

        complete(events, line, ls, abs_pos)
      end

      # Malformed UTF-8 byte sequence - catch high bytes not matched by UTF-8 pattern
      defp parse_pi_content(
             events,
             <<byte, _rest::binary>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _el_line,
             _el_ls,
             _el_abs_pos,
             _target,
             _elem_start
           )
           when byte >= 0x80 do
        events =
          error(
            events,
            :invalid_utf8,
            "Invalid UTF-8 byte sequence in processing instruction",
            line,
            ls,
            abs_pos
          )

        complete(events, line, ls, abs_pos)
      end

      # ============================================================================
      # Prolog
      # ============================================================================

      defp parse_prolog(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _el_line,
             _el_ls,
             _el_abs_pos,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_prolog(
             events,
             <<"?>", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             _elem_start
           ) do
        events
        |> new_event(:prolog, "xml", [], el_line, el_ls, el_abs_pos)
        |> parse_content(rest, xml, buf_pos + 2, abs_pos + 2, line, ls)
      end

      defp parse_prolog(
             events,
             <<"?">>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _el_line,
             _el_ls,
             _el_abs_pos,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_prolog(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           )
           when c in [?\s, ?\t] do
        parse_prolog(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      defp parse_prolog(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             _ls,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           ) do
        parse_prolog(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line + 1,
          abs_pos + 1,
          el_line,
          el_ls,
          el_abs_pos,
          elem_start
        )
      end

      defp parse_prolog(
             events,
             <<c::utf8, _::binary>> = rest,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             elem_start
           )
           when is_name_start(c) do
        parse_prolog_attr_name(
          events,
          rest,
          xml,
          buf_pos,
          abs_pos,
          line,
          ls,
          line,
          ls,
          abs_pos,
          [],
          elem_start
        )
      end

      defp parse_prolog(
             events,
             _,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _el_line,
             _el_ls,
             _el_abs_pos,
             _elem_start
           ) do
        events
        |> error(:expected_pi_end_or_attr, nil, line, ls, abs_pos)
        |> complete(line, ls, abs_pos)
      end

      defp parse_prolog_attr_name(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _prolog_attrs,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_prolog_attr_name(
             events,
             <<"?>", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             _elem_start
           ) do
        events
        |> new_event(:prolog, "xml", Enum.reverse(prolog_attrs), el_line, el_ls, el_abs_pos)
        |> parse_content(rest, xml, buf_pos + 2, abs_pos + 2, line, ls)
      end

      defp parse_prolog_attr_name(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             elem_start
           )
           when is_name_char_ascii(c) do
        parse_prolog_attr_name(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          prolog_attrs,
          elem_start
        )
      end

      defp parse_prolog_attr_name(
             events,
             <<c::utf8, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             elem_start
           )
           when is_name_char(c) do
        size = utf8_size(c)

        parse_prolog_attr_name(
          events,
          rest,
          xml,
          buf_pos + size,
          abs_pos + size,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          prolog_attrs,
          elem_start
        )
      end

      defp parse_prolog_attr_name(
             events,
             rest,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             elem_start
           ) do
        start = buf_start(buf_pos, abs_pos, el_abs_pos)
        attr_name = binary_part(xml, start, buf_pos - start)

        parse_prolog_attr_eq(
          events,
          rest,
          xml,
          buf_pos,
          abs_pos,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          prolog_attrs,
          attr_name,
          elem_start
        )
      end

      defp parse_prolog_attr_eq(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _prolog_attrs,
             _attr_name,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_prolog_attr_eq(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             attr_name,
             elem_start
           )
           when c in [?\s, ?\t] do
        parse_prolog_attr_eq(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          prolog_attrs,
          attr_name,
          elem_start
        )
      end

      defp parse_prolog_attr_eq(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             _ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             attr_name,
             elem_start
           ) do
        parse_prolog_attr_eq(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line + 1,
          abs_pos + 1,
          el_line,
          el_ls,
          el_abs_pos,
          prolog_attrs,
          attr_name,
          elem_start
        )
      end

      defp parse_prolog_attr_eq(
             events,
             <<"=", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             attr_name,
             elem_start
           ) do
        parse_prolog_attr_quote(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          prolog_attrs,
          attr_name,
          elem_start
        )
      end

      defp parse_prolog_attr_eq(
             events,
             _,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _prolog_attrs,
             _attr_name,
             _elem_start
           ) do
        events
        |> error(:expected_eq, nil, line, ls, abs_pos)
        |> complete(line, ls, abs_pos)
      end

      defp parse_prolog_attr_quote(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _prolog_attrs,
             _attr_name,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_prolog_attr_quote(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             attr_name,
             elem_start
           )
           when c in [?\s, ?\t] do
        parse_prolog_attr_quote(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          prolog_attrs,
          attr_name,
          elem_start
        )
      end

      defp parse_prolog_attr_quote(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             _ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             attr_name,
             elem_start
           ) do
        parse_prolog_attr_quote(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line + 1,
          abs_pos + 1,
          el_line,
          el_ls,
          el_abs_pos,
          prolog_attrs,
          attr_name,
          elem_start
        )
      end

      defp parse_prolog_attr_quote(
             events,
             <<q, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             attr_name,
             elem_start
           )
           when q in [?", ?'] do
        parse_prolog_attr_value(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          line,
          ls,
          abs_pos + 1,
          prolog_attrs,
          attr_name,
          q,
          elem_start
        )
      end

      defp parse_prolog_attr_quote(
             events,
             _,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _prolog_attrs,
             _attr_name,
             _elem_start
           ) do
        events
        |> error(:expected_quote, nil, line, ls, abs_pos)
        |> complete(line, ls, abs_pos)
      end

      defp parse_prolog_attr_value(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _prolog_attrs,
             _attr_name,
             _quote,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_prolog_attr_value(
             events,
             <<q, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             attr_name,
             q,
             elem_start
           ) do
        start = buf_start(buf_pos, abs_pos, el_abs_pos)
        value = binary_part(xml, start, buf_pos - start)
        new_prolog_attrs = [{attr_name, value} | prolog_attrs]

        parse_prolog_after_attr(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          new_prolog_attrs,
          elem_start
        )
      end

      defp parse_prolog_attr_value(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             _ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             attr_name,
             quote,
             elem_start
           ) do
        parse_prolog_attr_value(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line + 1,
          abs_pos + 1,
          el_line,
          el_ls,
          el_abs_pos,
          prolog_attrs,
          attr_name,
          quote,
          elem_start
        )
      end

      # ASCII fast path for valid XML chars (excludes ", ', control chars; newline handled above)
      defp parse_prolog_attr_value(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             attr_name,
             quote,
             elem_start
           )
           when c in 0x20..0x21 or c in 0x23..0x26 or c in 0x28..0x7F or c == 0x09 or c == 0x0D do
        parse_prolog_attr_value(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          prolog_attrs,
          attr_name,
          quote,
          elem_start
        )
      end

      # Non-ASCII UTF-8: validate with is_xml_char guard
      defp parse_prolog_attr_value(
             events,
             <<c::utf8, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             attr_name,
             quote,
             elem_start
           )
           when is_xml_char(c) do
        size = utf8_size(c)

        parse_prolog_attr_value(
          events,
          rest,
          xml,
          buf_pos + size,
          abs_pos + size,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          prolog_attrs,
          attr_name,
          quote,
          elem_start
        )
      end

      # Invalid XML character - emit error and stop
      defp parse_prolog_attr_value(
             events,
             <<c::utf8, _rest::binary>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _prolog_attrs,
             _attr_name,
             _quote,
             _elem_start
           ) do
        events =
          error(
            events,
            :invalid_char,
            "Invalid XML character U+#{Integer.to_string(c, 16) |> String.pad_leading(4, "0")} in prolog attribute value",
            line,
            ls,
            abs_pos
          )

        complete(events, line, ls, abs_pos)
      end

      # Malformed UTF-8 byte sequence - catch high bytes not matched by UTF-8 pattern
      defp parse_prolog_attr_value(
             events,
             <<byte, _rest::binary>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _prolog_attrs,
             _attr_name,
             _quote,
             _elem_start
           )
           when byte >= 0x80 do
        events =
          error(
            events,
            :invalid_utf8,
            "Invalid UTF-8 byte sequence in prolog attribute value",
            line,
            ls,
            abs_pos
          )

        complete(events, line, ls, abs_pos)
      end

      defp parse_prolog_after_attr(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _prolog_attrs,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_prolog_after_attr(
             events,
             <<"?>", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             _elem_start
           ) do
        events
        |> new_event(:prolog, "xml", Enum.reverse(prolog_attrs), el_line, el_ls, el_abs_pos)
        |> parse_content(rest, xml, buf_pos + 2, abs_pos + 2, line, ls)
      end

      defp parse_prolog_after_attr(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             elem_start
           )
           when c in [?\s, ?\t] do
        parse_prolog_after_attr_ws(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          prolog_attrs,
          elem_start
        )
      end

      defp parse_prolog_after_attr(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             _ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             elem_start
           ) do
        parse_prolog_after_attr_ws(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line + 1,
          abs_pos + 1,
          el_line,
          el_ls,
          el_abs_pos,
          prolog_attrs,
          elem_start
        )
      end

      defp parse_prolog_after_attr(
             events,
             <<c::utf8, _::binary>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _prolog_attrs,
             _elem_start
           )
           when is_name_start(c) do
        events
        |> error(:missing_whitespace_before_attr, nil, line, ls, abs_pos)
        |> complete(line, ls, abs_pos)
      end

      defp parse_prolog_after_attr(
             events,
             _,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _prolog_attrs,
             _elem_start
           ) do
        events
        |> error(:expected_pi_end_or_attr, nil, line, ls, abs_pos)
        |> complete(line, ls, abs_pos)
      end

      defp parse_prolog_after_attr_ws(
             events,
             <<>>,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _prolog_attrs,
             elem_start
           ) do
        incomplete(events, elem_start, line, ls, abs_pos)
      end

      defp parse_prolog_after_attr_ws(
             events,
             <<"?>", rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             _elem_start
           ) do
        events
        |> new_event(:prolog, "xml", Enum.reverse(prolog_attrs), el_line, el_ls, el_abs_pos)
        |> parse_content(rest, xml, buf_pos + 2, abs_pos + 2, line, ls)
      end

      defp parse_prolog_after_attr_ws(
             events,
             <<c, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             elem_start
           )
           when c in [?\s, ?\t] do
        parse_prolog_after_attr_ws(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line,
          ls,
          el_line,
          el_ls,
          el_abs_pos,
          prolog_attrs,
          elem_start
        )
      end

      defp parse_prolog_after_attr_ws(
             events,
             <<?\n, rest::binary>>,
             xml,
             buf_pos,
             abs_pos,
             line,
             _ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             elem_start
           ) do
        parse_prolog_after_attr_ws(
          events,
          rest,
          xml,
          buf_pos + 1,
          abs_pos + 1,
          line + 1,
          abs_pos + 1,
          el_line,
          el_ls,
          el_abs_pos,
          prolog_attrs,
          elem_start
        )
      end

      defp parse_prolog_after_attr_ws(
             events,
             <<c::utf8, _::binary>> = rest,
             xml,
             buf_pos,
             abs_pos,
             line,
             ls,
             el_line,
             el_ls,
             el_abs_pos,
             prolog_attrs,
             elem_start
           )
           when is_name_start(c) do
        parse_prolog_attr_name(
          events,
          rest,
          xml,
          buf_pos,
          abs_pos,
          line,
          ls,
          line,
          ls,
          abs_pos,
          prolog_attrs,
          elem_start
        )
      end

      defp parse_prolog_after_attr_ws(
             events,
             _,
             _xml,
             _buf_pos,
             abs_pos,
             line,
             ls,
             _loc,
             _prolog_attrs,
             _elem_start
           ) do
        events
        |> error(:expected_pi_end_or_attr, nil, line, ls, abs_pos)
        |> complete(line, ls, abs_pos)
      end
    end
  end
end
