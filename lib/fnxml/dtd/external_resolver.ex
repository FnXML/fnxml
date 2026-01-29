defmodule FnXML.DTD.ExternalResolver do
  @moduledoc """
  Resolves and parses external DTD entities.

  This module handles fetching and parsing external DTD subsets and
  external parsed entities referenced via SYSTEM or PUBLIC identifiers.

  ## Supported URI Schemes

  - `file://` - Local file system (relative to base path)
  - Relative paths - Resolved against base path

  ## Usage

      base_path = "/path/to/xml/file.xml"
      {:ok, content} = FnXML.DTD.ExternalResolver.fetch("external.dtd", base_path)

  ## Conditional Sections

  External DTDs may contain conditional sections:

      <![INCLUDE[
        <!ELEMENT doc (#PCDATA)>
      ]]>

      <![IGNORE[
        <!ELEMENT deprecated ANY>
      ]]>

  These are parsed and the INCLUDE sections are processed while IGNORE
  sections are skipped.
  """

  @doc """
  Fetch external entity content from a URI relative to a base path.

  ## Parameters

  - `uri` - SYSTEM identifier (file path or URI)
  - `base_path` - Base path for resolving relative URIs

  ## Returns

  - `{:ok, content}` - File content as string
  - `{:error, reason}` - Error description
  """
  @spec fetch(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def fetch(uri, base_path) do
    resolved_path = resolve_uri(uri, base_path)

    case File.read(resolved_path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, {:file_error, resolved_path, reason}}
    end
  end

  @doc """
  Parse external DTD content, handling conditional sections.

  ## Parameters

  - `content` - DTD content string
  - `opts` - Options (passed to DTD parser)

  ## Returns

  - `{:ok, model}` - Parsed DTD model
  - `{:error, reason}` - Parse error
  """
  @spec parse_external_dtd(String.t(), keyword()) ::
          {:ok, FnXML.DTD.Model.t()} | {:error, term()}
  def parse_external_dtd(content, opts \\ []) do
    # Get PE definitions from internal subset (if provided)
    # Per XML spec, internal subset PE definitions take precedence
    internal_pe_defs = Keyword.get(opts, :internal_pe_defs, %{})

    # Extract PE definitions from external DTD content
    external_pe_defs = FnXML.DTD.ParameterEntities.extract_definitions(content)

    # Check for partial markup in PE definitions (WFC: PE Boundary)
    case check_pe_boundaries(external_pe_defs) do
      :ok ->
        # Merge: internal subset takes precedence
        merged_pe_defs = Map.merge(external_pe_defs, internal_pe_defs)

        # Expand PEs in the external DTD content
        # This is necessary because conditional sections may use PE references
        # for the INCLUDE/IGNORE keyword, e.g., <![%MAYBE;[...]]>
        case FnXML.DTD.ParameterEntities.expand(content, merged_pe_defs) do
          {:ok, expanded} ->
            case process_conditional_sections(expanded) do
              {:ok, processed} ->
                # Always parse with external: true for external DTDs
                # This enables stricter validation (e.g., bare % not allowed in entity values)
                FnXML.DTD.Parser.parse(processed, Keyword.put(opts, :external, true))

              {:error, _} = err ->
                err
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Check that PE replacement text doesn't contain partial markup constructs
  # Per XML spec, PEs must be well-balanced with respect to markup
  defp check_pe_boundaries(pe_defs) do
    invalid =
      Enum.find(pe_defs, fn {_name, value} ->
        has_partial_markup?(value)
      end)

    case invalid do
      nil -> :ok
      {name, _} -> {:error, "PE '#{name}' contains partial markup (violates WFC: PE Boundary)"}
    end
  end

  defp has_partial_markup?(value) do
    # Check for partial comment: <!-- without -->
    # Check for partial declaration: <! without closing >
    has_partial_comment?(value) or
      has_partial_declaration?(value)
  end

  defp has_partial_comment?(value) do
    String.contains?(value, "<!--") and not String.contains?(value, "-->")
  end

  defp has_partial_declaration?(value) do
    # Check for declaration starts without corresponding close
    cond do
      # Starts with <!ELEMENT, <!ATTLIST, etc but doesn't end with >
      Regex.match?(~r/<!(?:ELEMENT|ATTLIST|ENTITY|NOTATION)\s/, value) ->
        not String.ends_with?(String.trim(value), ">")

      true ->
        false
    end
  end

  @doc """
  Process conditional sections in DTD content.

  Expands INCLUDE sections and removes IGNORE sections.

  ## Parameters

  - `content` - DTD content with conditional sections

  ## Returns

  - `{:ok, processed}` - Content with conditional sections processed
  - `{:error, reason}` - If conditional sections are malformed
  """
  @spec process_conditional_sections(String.t()) :: {:ok, String.t()} | {:error, term()}
  def process_conditional_sections(content) do
    process_conditionals(content, <<>>)
  end

  # Resolve URI against base path
  defp resolve_uri(uri, base_path) do
    cond do
      # Absolute file:// URI
      String.starts_with?(uri, "file://") ->
        String.trim_leading(uri, "file://")

      # Absolute path
      String.starts_with?(uri, "/") ->
        uri

      # Relative path - resolve against base directory
      true ->
        base_dir = Path.dirname(base_path)
        Path.join(base_dir, uri)
    end
  end

  # Process conditional sections recursively
  defp process_conditionals(<<>>, acc), do: {:ok, acc}

  # Error: ]]> outside of conditional section
  defp process_conditionals(<<"]]>", _rest::binary>>, _acc) do
    {:error, "Unmatched ']]>' - conditional section close without matching open"}
  end

  # Match INCLUDE section start
  defp process_conditionals(<<"<![", rest::binary>>, acc) do
    case parse_conditional_keyword(rest) do
      {:include, after_keyword} ->
        case extract_conditional_content(after_keyword) do
          {:ok, content, remaining} ->
            # Recursively process the included content
            case process_conditionals(content, <<>>) do
              {:ok, processed} ->
                process_conditionals(remaining, <<acc::binary, processed::binary>>)

              {:error, _} = err ->
                err
            end

          {:error, _} = err ->
            err
        end

      {:ignore, after_keyword} ->
        case skip_conditional_content(after_keyword) do
          {:ok, remaining} ->
            process_conditionals(remaining, acc)

          {:error, _} = err ->
            err
        end

      {:skip_pe, _content} ->
        # Parameter entity reference - we can't expand it, so we stop processing
        # and return what we have. This is a limitation but better than failing.
        {:ok, acc}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Regular character - pass through
  defp process_conditionals(<<c, rest::binary>>, acc) do
    process_conditionals(rest, <<acc::binary, c>>)
  end

  # Parse INCLUDE or IGNORE keyword after "<!"
  defp parse_conditional_keyword(content) do
    # Skip optional whitespace
    content = skip_whitespace(content)

    cond do
      String.starts_with?(content, "INCLUDE") ->
        rest = String.slice(content, 7..-1//1)
        rest = skip_whitespace(rest)

        if String.starts_with?(rest, "[") do
          {:include, String.slice(rest, 1..-1//1)}
        else
          {:error, "Expected '[' after INCLUDE"}
        end

      String.starts_with?(content, "IGNORE") ->
        rest = String.slice(content, 6..-1//1)
        rest = skip_whitespace(rest)

        if String.starts_with?(rest, "[") do
          {:ignore, String.slice(rest, 1..-1//1)}
        else
          {:error, "Expected '[' after IGNORE"}
        end

      # Parameter entity reference - can't expand, skip this conditional section
      String.starts_with?(content, "%") ->
        {:skip_pe, content}

      true ->
        {:error, "Expected INCLUDE or IGNORE after '<![' in conditional section"}
    end
  end

  # Extract content until matching ]]>
  defp extract_conditional_content(content) do
    extract_conditional_content(content, <<>>, 1)
  end

  defp extract_conditional_content(<<>>, _acc, _depth) do
    {:error, "Unterminated conditional section - missing ']]>'"}
  end

  defp extract_conditional_content(<<"]]>", rest::binary>>, acc, 1) do
    {:ok, acc, rest}
  end

  defp extract_conditional_content(<<"]]>", rest::binary>>, acc, depth) do
    extract_conditional_content(rest, <<acc::binary, "]]>"::binary>>, depth - 1)
  end

  defp extract_conditional_content(<<"<![", rest::binary>>, acc, depth) do
    # Nested conditional section
    extract_conditional_content(rest, <<acc::binary, "<!["::binary>>, depth + 1)
  end

  defp extract_conditional_content(<<c, rest::binary>>, acc, depth) do
    extract_conditional_content(rest, <<acc::binary, c>>, depth)
  end

  # Skip content until matching ]]> (for IGNORE sections)
  defp skip_conditional_content(content) do
    skip_conditional_content(content, 1)
  end

  defp skip_conditional_content(<<>>, _depth) do
    {:error, "Unterminated IGNORE section - missing ']]>'"}
  end

  defp skip_conditional_content(<<"]]>", rest::binary>>, 1) do
    {:ok, rest}
  end

  defp skip_conditional_content(<<"]]>", rest::binary>>, depth) do
    skip_conditional_content(rest, depth - 1)
  end

  defp skip_conditional_content(<<"<![", rest::binary>>, depth) do
    skip_conditional_content(rest, depth + 1)
  end

  defp skip_conditional_content(<<_, rest::binary>>, depth) do
    skip_conditional_content(rest, depth)
  end

  defp skip_whitespace(<<c, rest::binary>>) when c in [?\s, ?\t, ?\r, ?\n] do
    skip_whitespace(rest)
  end

  defp skip_whitespace(content), do: content
end
