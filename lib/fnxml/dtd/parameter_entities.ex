defmodule FnXML.DTD.ParameterEntities do
  @moduledoc """
  Parameter entity expansion for DTD processing.

  Parameter entities (`%name;`) are used in DTDs to define reusable
  content. They must be expanded before parsing DTD declarations.

  ## Character Reference Expansion

  Character references in PE values are expanded first:
  - `&#60;` expands to `<`
  - `&#37;` expands to `%`

  This allows PEs to contain declaration syntax:

      <!ENTITY % foo '&#60;!ELEMENT doc (#PCDATA)>'>
      %foo;

  Expands to:

      <!ELEMENT doc (#PCDATA)>

  ## PE Reference Expansion

  PE references are expanded iteratively:

      <!ENTITY % zz '<!ENTITY tricky "value">'>
      <!ENTITY % xx '&#37;zz;'>
      %xx;

  First, char refs in %xx value expand: `&#37;zz;` -> `%zz;`
  Then, %xx; in the DTD expands to `%zz;`
  Then, %zz; expands to the entity declaration.
  """

  @doc """
  Extract parameter entity definitions from DTD content.

  Returns a map of PE names to their values (with character refs expanded).
  """
  @spec extract_definitions(String.t()) :: %{String.t() => String.t()}
  def extract_definitions(content) do
    # Match <!ENTITY % name "value"> or <!ENTITY % name 'value'>
    # Handles both single and double quotes, including empty values
    pattern = ~r/<!ENTITY\s+%\s+(\S+)\s+(["'])(.*?)\2\s*>/s

    Regex.scan(pattern, content)
    |> Enum.map(fn [_, name, _quote, value] ->
      # Expand character references in the value
      expanded = expand_char_refs(value)
      {name, expanded}
    end)
    |> Map.new()
  end

  @doc """
  Expand parameter entity references in DTD content.

  Iteratively expands PE references until no more changes occur,
  or max iterations reached (to prevent infinite loops).
  """
  @spec expand(String.t(), %{String.t() => String.t()}, keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def expand(content, pe_defs, opts \\ []) do
    max_iterations = Keyword.get(opts, :max_iterations, 100)
    expand_loop(content, pe_defs, 0, max_iterations)
  end

  defp expand_loop(_content, _pe_defs, iteration, max) when iteration >= max do
    {:error, "Maximum PE expansion iterations exceeded - possible circular reference"}
  end

  defp expand_loop(content, pe_defs, iteration, max) do
    # Find and expand all PE references
    expanded = expand_once(content, pe_defs)

    if expanded == content do
      # No more expansions - done
      {:ok, content}
    else
      # Continue expanding
      expand_loop(expanded, pe_defs, iteration + 1, max)
    end
  end

  # Expand PE references once
  defp expand_once(content, pe_defs) do
    # Match %name; pattern for PE references
    # Per XML spec, PE reference must be: % Name ;
    # with no whitespace between % and Name, or Name and ;
    Regex.replace(~r/%([a-zA-Z_][a-zA-Z0-9._-]*);/, content, fn _full, name ->
      case Map.get(pe_defs, name) do
        nil ->
          # Unknown PE - leave as-is (might be defined in external DTD)
          "%#{name};"

        value ->
          # Expand to value
          value
      end
    end)
  end

  @doc """
  Expand character references in a string.

  Handles:
  - `&#NN;` - decimal character reference
  - `&#xHH;` - hexadecimal character reference
  """
  @spec expand_char_refs(String.t()) :: String.t()
  def expand_char_refs(value) do
    Regex.replace(~r/&#x([0-9a-fA-F]+);|&#([0-9]+);/, value, fn
      _full, hex, "" ->
        case Integer.parse(hex, 16) do
          {cp, ""} when cp >= 0 ->
            try do
              <<cp::utf8>>
            rescue
              _ -> "&#x#{hex};"
            end

          _ ->
            "&#x#{hex};"
        end

      _full, "", decimal ->
        case Integer.parse(decimal) do
          {cp, ""} when cp >= 0 ->
            try do
              <<cp::utf8>>
            rescue
              _ -> "&##{decimal};"
            end

          _ ->
            "&##{decimal};"
        end
    end)
  end

  @doc """
  Process a DTD string with PE expansion.

  This is the main entry point for PE-aware DTD parsing:
  1. Extract PE definitions
  2. Expand character refs in PE values
  3. Expand PE references in DTD content
  4. Return the fully expanded DTD content

  ## Options

  - `:external` - If false (default), validates that PE references only appear
    between declarations, not within them (internal DTD subset constraint).
  """
  @spec process(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def process(dtd_content, opts \\ []) do
    external = Keyword.get(opts, :external, false)

    # Step 0: If internal subset, validate PE references are only between declarations
    if not external do
      case validate_pe_positions(dtd_content) do
        :ok -> do_process(dtd_content)
        {:error, _} = err -> err
      end
    else
      do_process(dtd_content)
    end
  end

  defp do_process(dtd_content) do
    # Step 1: Extract all PE definitions (with char refs expanded in values)
    pe_defs = extract_definitions(dtd_content)

    # Step 2: Expand PE references in the DTD content
    expand(dtd_content, pe_defs)
  end

  # Validate that PE references in internal subset only appear between declarations,
  # not within markup declarations. Per XML spec: "In the internal DTD subset,
  # parameter-entity references MUST NOT occur within markup declarations"
  defp validate_pe_positions(content) do
    # Find all PE reference positions
    pe_refs = Regex.scan(~r/%[a-zA-Z_][a-zA-Z0-9._-]*;/, content, return: :index)

    # Find all declaration boundaries
    decl_ranges = find_declaration_ranges(content)

    # Check if any PE reference is inside a declaration
    invalid_ref =
      Enum.find(pe_refs, fn [{start, _len}] ->
        Enum.any?(decl_ranges, fn {decl_start, decl_end} ->
          start > decl_start and start < decl_end
        end)
      end)

    case invalid_ref do
      nil ->
        :ok

      [{start, _len}] ->
        ref_text = extract_pe_ref_at(content, start)
        {:error, "PE reference '#{ref_text}' within markup declaration in internal subset"}
    end
  end

  # Extract the PE reference text at a given position
  defp extract_pe_ref_at(content, start) do
    rest = binary_part(content, start, byte_size(content) - start)

    case Regex.run(~r/^%[a-zA-Z_][a-zA-Z0-9._-]*;/, rest) do
      [ref] -> ref
      _ -> "%..."
    end
  end

  # Find the byte ranges of all declarations (excluding PE declarations)
  defp find_declaration_ranges(content) do
    # We need to find declaration start/end positions, accounting for:
    # 1. <!ELEMENT ...> - declarations can span multiple lines
    # 2. <!ATTLIST ...> - may contain quoted strings with >
    # 3. <!ENTITY ...> - may contain quoted values
    # 4. <!NOTATION ...>
    # 5. <!-- comments --> - not declarations, skip
    # 6. <?...?> - processing instructions, skip
    #
    # PE declarations (<!ENTITY % ...) should NOT be counted as declarations
    # where PE references are forbidden - the % after ENTITY is syntax, not a ref

    find_decls_impl(content, 0, [])
  end

  defp find_decls_impl("", _pos, acc), do: Enum.reverse(acc)

  # Skip comments
  defp find_decls_impl(<<"<!--", rest::binary>>, pos, acc) do
    case skip_comment(rest, pos + 4) do
      {:ok, new_pos, new_rest} -> find_decls_impl(new_rest, new_pos, acc)
      :error -> Enum.reverse(acc)
    end
  end

  # Skip processing instructions
  defp find_decls_impl(<<"<?", rest::binary>>, pos, acc) do
    case skip_pi(rest, pos + 2) do
      {:ok, new_pos, new_rest} -> find_decls_impl(new_rest, new_pos, acc)
      :error -> Enum.reverse(acc)
    end
  end

  # PE declaration - skip it (% after ENTITY is syntax, not reference)
  defp find_decls_impl(<<"<!ENTITY", rest::binary>>, pos, acc) do
    # Check if this is a PE declaration
    case Regex.run(~r/^\s+%\s+/, rest) do
      [_match] ->
        # It's a PE declaration, find closing > but don't add to ranges
        case find_decl_end(rest, pos + 8) do
          {:ok, _end_pos, remaining_pos, remaining} ->
            find_decls_impl(remaining, remaining_pos, acc)

          :error ->
            Enum.reverse(acc)
        end

      _ ->
        # Regular entity declaration
        decl_start = pos

        case find_decl_end(rest, pos + 8) do
          {:ok, end_pos, remaining_pos, remaining} ->
            find_decls_impl(remaining, remaining_pos, [{decl_start, end_pos} | acc])

          :error ->
            Enum.reverse(acc)
        end
    end
  end

  # Other declarations
  defp find_decls_impl(<<"<!", rest::binary>>, pos, acc) do
    decl_start = pos

    case find_decl_end(rest, pos + 2) do
      {:ok, end_pos, remaining_pos, remaining} ->
        find_decls_impl(remaining, remaining_pos, [{decl_start, end_pos} | acc])

      :error ->
        Enum.reverse(acc)
    end
  end

  defp find_decls_impl(<<_, rest::binary>>, pos, acc) do
    find_decls_impl(rest, pos + 1, acc)
  end

  # Skip over comment content until -->
  defp skip_comment(<<"-->", rest::binary>>, pos), do: {:ok, pos + 3, rest}
  defp skip_comment(<<_, rest::binary>>, pos), do: skip_comment(rest, pos + 1)
  defp skip_comment("", _pos), do: :error

  # Skip over PI content until ?>
  defp skip_pi(<<"?>", rest::binary>>, pos), do: {:ok, pos + 2, rest}
  defp skip_pi(<<_, rest::binary>>, pos), do: skip_pi(rest, pos + 1)
  defp skip_pi("", _pos), do: :error

  # Find the end of a declaration, handling quoted strings
  defp find_decl_end(content, pos), do: find_decl_end_impl(content, pos, nil)

  defp find_decl_end_impl(<<">", rest::binary>>, pos, nil) do
    {:ok, pos, pos + 1, rest}
  end

  defp find_decl_end_impl(<<q, rest::binary>>, pos, nil) when q in [?", ?'] do
    find_decl_end_impl(rest, pos + 1, q)
  end

  defp find_decl_end_impl(<<q, rest::binary>>, pos, q) do
    # End of quoted string
    find_decl_end_impl(rest, pos + 1, nil)
  end

  defp find_decl_end_impl(<<_, rest::binary>>, pos, quote_char) do
    find_decl_end_impl(rest, pos + 1, quote_char)
  end

  defp find_decl_end_impl("", _pos, _quote_char), do: :error
end
