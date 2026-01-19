defmodule FnXML.ParserGenerator do
  @moduledoc """
  Macro-based parser generator for XML 1.0 Edition 4 and Edition 5.

  Generates two parser modules from shared code, with edition-specific
  character validation inlined at compile time for maximum performance.

  ## Usage

      # Generates FnXML.Parser.Edition5 with Edition 5 char validation
      use FnXML.ParserGenerator, edition: 5

      # Generates FnXML.Parser.Edition4 with Edition 4 char validation
      use FnXML.ParserGenerator, edition: 4

  ## Architecture

  ```
  ┌─────────────────────────────────────────────────────────────┐
  │              FnXML.ParserGenerator (macro)                  │
  │  - Defines shared parsing logic                             │
  │  - Injects edition-specific char validation at compile time │
  └─────────────────────────────────────────────────────────────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
  ┌─────────────────────┐   ┌─────────────────────┐
  │ FnXML.Parser.Ed5    │   │ FnXML.Parser.Ed4    │
  │ - name_start_char?  │   │ - name_start_char?  │
  │   calls ed5 version │   │   calls ed4 version │
  │ - Identical logic   │   │ - Identical logic   │
  │ - Zero dispatch     │   │ - Zero dispatch     │
  └─────────────────────┘   └─────────────────────┘
  ```
  """

  @doc """
  Generates an edition-specific parser module.

  ## Options
  - `:edition` - Required. Either `4` or `5`.
  """
  defmacro __using__(opts) do
    edition = Keyword.fetch!(opts, :edition)

    # Select the character validation functions based on edition
    {name_start_char_fn, name_char_fn} =
      case edition do
        5 -> {:name_start_char_ed5?, :name_char_ed5?}
        4 -> {:name_start_char_ed4?, :name_char_ed4?}
      end

    quote do
      @moduledoc """
      XML 1.0 Edition #{unquote(edition)} Parser.

      Auto-generated with edition-specific character validation inlined
      for maximum performance. No runtime edition dispatch.
      """

      import Bitwise
      alias FnXML.Char

      # Store edition for introspection
      @edition unquote(edition)
      def edition, do: @edition

      # ==================================================================
      # Inlined Character Validation (zero dispatch overhead)
      # ==================================================================

      # These delegate to FnXML.Char but could be fully inlined if needed
      @compile {:inline, name_start_char?: 1, name_char?: 1}

      defp name_start_char?(c), do: Char.unquote(name_start_char_fn)(c)
      defp name_char?(c), do: Char.unquote(name_char_fn)(c)

      # ==================================================================
      # Shared Parser Implementation
      # ==================================================================

      unquote(shared_parser_code())
    end
  end

  # ==================================================================
  # Shared Parser Code (injected into both editions)
  # ==================================================================

  defp shared_parser_code do
    quote do
      @type parse_result :: {:ok, term()} | {:error, term()}

      @doc """
      Parse an XML Name (element name, attribute name, etc.)

      Returns `{:ok, name, rest}` or `{:error, reason}`.
      """
      @spec parse_name(binary()) :: {:ok, String.t(), binary()} | {:error, atom()}
      def parse_name(<<c::utf8, rest::binary>> = input) when c != 0 do
        if name_start_char?(c) do
          parse_name_rest(rest, [c])
        else
          {:error, {:invalid_name_start_char, c}}
        end
      end

      def parse_name(<<>>), do: {:error, :unexpected_end}
      def parse_name(_), do: {:error, :invalid_input}

      defp parse_name_rest(<<c::utf8, rest::binary>>, acc) do
        if name_char?(c) do
          parse_name_rest(rest, [c | acc])
        else
          name = acc |> Enum.reverse() |> List.to_string()
          {:ok, name, <<c::utf8, rest::binary>>}
        end
      end

      defp parse_name_rest(<<>>, acc) do
        name = acc |> Enum.reverse() |> List.to_string()
        {:ok, name, <<>>}
      end

      @doc """
      Validate that a string is a valid XML Name.
      """
      @spec valid_name?(String.t()) :: boolean()
      def valid_name?(<<c::utf8, rest::binary>>) do
        name_start_char?(c) and valid_name_rest?(rest)
      end

      def valid_name?(_), do: false

      defp valid_name_rest?(<<>>), do: true

      defp valid_name_rest?(<<c::utf8, rest::binary>>) do
        name_char?(c) and valid_name_rest?(rest)
      end

      @doc """
      Parse an XML NCName (Name without colons, used in namespaces).
      """
      @spec parse_ncname(binary()) :: {:ok, String.t(), binary()} | {:error, atom()}
      def parse_ncname(<<c::utf8, rest::binary>>) when c != ?: do
        if name_start_char?(c) do
          parse_ncname_rest(rest, [c])
        else
          {:error, {:invalid_ncname_start_char, c}}
        end
      end

      def parse_ncname(<<?:, _::binary>>), do: {:error, :ncname_cannot_start_with_colon}
      def parse_ncname(<<>>), do: {:error, :unexpected_end}

      defp parse_ncname_rest(<<?:, _::binary>> = rest, acc) do
        # Colon terminates NCName
        name = acc |> Enum.reverse() |> List.to_string()
        {:ok, name, rest}
      end

      defp parse_ncname_rest(<<c::utf8, rest::binary>>, acc) do
        if name_char?(c) do
          parse_ncname_rest(rest, [c | acc])
        else
          name = acc |> Enum.reverse() |> List.to_string()
          {:ok, name, <<c::utf8, rest::binary>>}
        end
      end

      defp parse_ncname_rest(<<>>, acc) do
        name = acc |> Enum.reverse() |> List.to_string()
        {:ok, name, <<>>}
      end

      @doc """
      Parse a QName (qualified name: prefix:localpart or just localpart).
      """
      @spec parse_qname(binary()) ::
              {:ok, {String.t() | nil, String.t()}, binary()} | {:error, atom()}
      def parse_qname(input) do
        case parse_ncname(input) do
          {:ok, first_part, <<?:, rest::binary>>} ->
            # Has prefix, parse local part
            case parse_ncname(rest) do
              {:ok, local_part, remaining} ->
                {:ok, {first_part, local_part}, remaining}

              {:error, _} = err ->
                err
            end

          {:ok, name, rest} ->
            # No prefix
            {:ok, {nil, name}, rest}

          {:error, _} = err ->
            err
        end
      end

      @doc """
      Parse an Nmtoken (name token - can start with any name char).
      """
      @spec parse_nmtoken(binary()) :: {:ok, String.t(), binary()} | {:error, atom()}
      def parse_nmtoken(<<c::utf8, rest::binary>>) do
        if name_char?(c) do
          parse_nmtoken_rest(rest, [c])
        else
          {:error, {:invalid_nmtoken_char, c}}
        end
      end

      def parse_nmtoken(<<>>), do: {:error, :unexpected_end}

      defp parse_nmtoken_rest(<<c::utf8, rest::binary>>, acc) do
        if name_char?(c) do
          parse_nmtoken_rest(rest, [c | acc])
        else
          token = acc |> Enum.reverse() |> List.to_string()
          {:ok, token, <<c::utf8, rest::binary>>}
        end
      end

      defp parse_nmtoken_rest(<<>>, acc) do
        token = acc |> Enum.reverse() |> List.to_string()
        {:ok, token, <<>>}
      end

      # ==================================================================
      # Additional shared parsing functions can be added here
      # ==================================================================

      # Example: Parse whitespace
      @spec skip_whitespace(binary()) :: binary()
      def skip_whitespace(<<c, rest::binary>>) when c in [?\s, ?\t, ?\r, ?\n] do
        skip_whitespace(rest)
      end

      def skip_whitespace(input), do: input

      # Example: Parse required whitespace
      @spec parse_whitespace(binary()) :: {:ok, binary()} | {:error, atom()}
      def parse_whitespace(<<c, rest::binary>>) when c in [?\s, ?\t, ?\r, ?\n] do
        {:ok, skip_whitespace(rest)}
      end

      def parse_whitespace(_), do: {:error, :expected_whitespace}
    end
  end
end
