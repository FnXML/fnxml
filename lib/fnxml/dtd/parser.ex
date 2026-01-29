defmodule FnXML.DTD.Parser do
  @moduledoc """
  Parse DTD (Document Type Definition) declarations.

  This module provides functions to parse DTD declarations from strings,
  producing structured data that can be added to a `FnXML.DTD.Model`.

  ## Supported Declarations

  ### Element Declarations

      <!ELEMENT name EMPTY>
      <!ELEMENT name ANY>
      <!ELEMENT name (#PCDATA)>
      <!ELEMENT name (child1, child2)>
      <!ELEMENT name (child1 | child2)>
      <!ELEMENT name (#PCDATA | child)*>

  ### Entity Declarations

      <!ENTITY name "value">
      <!ENTITY name SYSTEM "uri">
      <!ENTITY name PUBLIC "pubid" "uri">
      <!ENTITY % name "value">

  ### Attribute List Declarations

      <!ATTLIST element attr CDATA #REQUIRED>
      <!ATTLIST element attr (a|b|c) "default">

  ## Examples

      iex> FnXML.DTD.Parser.parse_element("<!ELEMENT note EMPTY>")
      {:ok, {"note", :empty}}

      iex> FnXML.DTD.Parser.parse_element("<!ELEMENT note (to, from, body)>")
      {:ok, {"note", {:seq, ["to", "from", "body"]}}}

  """

  alias FnXML.DTD.Model

  @type parse_result :: {:ok, term()} | {:error, String.t()}

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Parse a complete DTD string into a Model.

  ## Options

  - `:edition` - XML 1.0 edition for name validation (4 or 5, default: 5)

  ## Examples

      iex> dtd = \"\"\"
      ...> <!ELEMENT note (to, from, body)>
      ...> <!ELEMENT to (#PCDATA)>
      ...> <!ELEMENT from (#PCDATA)>
      ...> <!ELEMENT body (#PCDATA)>
      ...> \"\"\"
      iex> {:ok, model} = FnXML.DTD.Parser.parse(dtd)
      iex> model.elements["note"]
      {:seq, ["to", "from", "body"]}

  """
  @spec parse(String.t(), keyword()) :: {:ok, Model.t()} | {:error, String.t()}
  def parse(dtd_string, opts \\ [])

  def parse(dtd_string, opts) when is_binary(dtd_string) do
    edition = Keyword.get(opts, :edition, 5)
    external = Keyword.get(opts, :external, false)

    # First, expand parameter entity references in the DTD
    # This handles cases like:
    #   <!ENTITY % xx '&#37;zz;'>
    #   <!ENTITY % zz '<!ENTITY tricky "error-prone">'>
    #   %xx;
    # which expands to define the "tricky" entity
    # Note: In internal subset (external: false), PE references can only appear
    # between declarations, not within them.
    case FnXML.DTD.ParameterEntities.process(dtd_string, external: external) do
      {:ok, expanded} ->
        parse_expanded(expanded, edition, external)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_expanded(dtd_string, edition, external) do
    result =
      dtd_string
      |> extract_declarations(external: external, edition: edition)
      |> Enum.reduce_while({:ok, Model.new()}, fn
        # Handle error from extract_declarations (e.g., conditional sections)
        {:error, msg}, _acc ->
          {:halt, {:error, msg}}

        decl, {:ok, model} ->
          # Check for PE references inside declarations in internal subset
          # Per XML spec: "In the internal DTD subset, parameter-entity references
          # MUST NOT occur within markup declarations"
          if not external and contains_pe_reference_in_decl?(decl) do
            {:halt, {:error, "PE reference within markup declaration in internal subset"}}
          else
            # Check if this is a redeclaration of an existing entity
            # Per XML spec, only the first declaration is used (redeclarations are ignored)
            case check_redeclaration(decl, model) do
              :skip_redeclaration ->
                {:cont, {:ok, model}}

              :continue ->
                case parse_declaration(decl, edition: edition, external: external) do
                  {:ok, {:element, name, content_model}} ->
                    {:cont, {:ok, Model.add_element(model, name, content_model)}}

                  {:ok, {:entity, name, definition}} ->
                    {:cont, {:ok, Model.add_entity(model, name, definition)}}

                  {:ok, {:param_entity, name, value}} ->
                    {:cont, {:ok, Model.add_param_entity(model, name, value)}}

                  {:ok, {:attlist, element_name, attr_defs}} ->
                    {:cont, {:ok, Model.add_attributes(model, element_name, attr_defs)}}

                  {:ok, {:notation, name, system_id, public_id}} ->
                    {:cont, {:ok, Model.add_notation(model, name, system_id, public_id)}}

                  {:ok, :skip} ->
                    {:cont, {:ok, model}}

                  {:error, _} = err ->
                    {:halt, err}
                end
            end
          end
      end)

    # Note: Notation reference validation is a Validity Constraint (VC), not a
    # Well-Formedness Constraint (WFC), so we don't validate it here. A non-validating
    # parser should accept documents with undefined notation references.
    result
  end

  # Check if a declaration is a redeclaration of an existing entity
  # Per XML spec, only the first entity/parameter entity declaration is binding
  defp check_redeclaration(decl, model) do
    trimmed = String.trim(decl)

    cond do
      # General entity redeclaration: <!ENTITY name ...>
      match = Regex.run(~r/^<!ENTITY\s+([^%\s]\S*)\s/, trimmed) ->
        [_, name] = match

        if Map.has_key?(model.entities, name) do
          :skip_redeclaration
        else
          :continue
        end

      # Parameter entity redeclaration: <!ENTITY % name ...>
      match = Regex.run(~r/^<!ENTITY\s+%\s+(\S+)\s/, trimmed) ->
        [_, name] = match

        if Map.has_key?(model.param_entities, name) do
          :skip_redeclaration
        else
          :continue
        end

      true ->
        :continue
    end
  end

  # Check if a declaration contains a PE reference (%name;) in the internal subset
  # PE references may only appear BETWEEN declarations in the internal subset,
  # not within markup declarations.
  # Note: <!ENTITY % name ...> is NOT a PE reference, it's a PE declaration syntax
  defp contains_pe_reference_in_decl?(decl) do
    # First, remove the PE declaration syntax pattern to avoid false positives
    # <!ENTITY % name "value"> - the "% name" is syntax, not a reference
    cleaned = Regex.replace(~r/<!ENTITY\s+%\s+\S+/, decl, "<!ENTITY __PE_DECL__")

    # Now check for any remaining %name; patterns (PE references)
    # A PE reference is %Name; where Name is a valid XML name
    Regex.match?(~r/%[A-Za-z_][A-Za-z0-9._-]*;/, cleaned)
  end

  @doc """
  Parse a single DTD declaration.

  Returns a tagged tuple indicating the declaration type:
  - `{:element, name, content_model}`
  - `{:entity, name, definition}`
  - `{:param_entity, name, value}`
  - `{:attlist, element_name, [attr_def]}`
  - `{:notation, name, system_id, public_id}`

  ## Options

  - `:edition` - XML 1.0 edition for name validation (4 or 5, default: 5)
  """
  @spec parse_declaration(String.t(), keyword()) :: {:ok, term()} | {:error, String.t()}
  def parse_declaration(decl, opts \\ [])

  def parse_declaration(decl, opts) when is_binary(decl) do
    trimmed = String.trim(decl)

    cond do
      String.starts_with?(trimmed, "<!ELEMENT") ->
        parse_element(trimmed)

      String.starts_with?(trimmed, "<!ENTITY") ->
        parse_entity(trimmed, opts)

      String.starts_with?(trimmed, "<!ATTLIST") ->
        parse_attlist(trimmed)

      String.starts_with?(trimmed, "<!NOTATION") ->
        parse_notation(trimmed)

      trimmed == "" or String.starts_with?(trimmed, "<!--") ->
        {:ok, :skip}

      # XML declaration not allowed in DTD internal subset
      String.starts_with?(trimmed, "<?xml") ->
        {:error, "XML declaration not allowed in internal subset"}

      true ->
        {:error, "Unknown declaration: #{String.slice(trimmed, 0, 50)}..."}
    end
  end

  @doc """
  Parse an ELEMENT declaration.

  ## Examples

      iex> FnXML.DTD.Parser.parse_element("<!ELEMENT br EMPTY>")
      {:ok, {:element, "br", :empty}}

      iex> FnXML.DTD.Parser.parse_element("<!ELEMENT container ANY>")
      {:ok, {:element, "container", :any}}

      iex> FnXML.DTD.Parser.parse_element("<!ELEMENT p (#PCDATA)>")
      {:ok, {:element, "p", :pcdata}}

      iex> FnXML.DTD.Parser.parse_element("<!ELEMENT note (to, from)>")
      {:ok, {:element, "note", {:seq, ["to", "from"]}}}

      iex> FnXML.DTD.Parser.parse_element("<!ELEMENT choice (a | b | c)>")
      {:ok, {:element, "choice", {:choice, ["a", "b", "c"]}}}

  """
  @spec parse_element(String.t()) ::
          {:ok, {:element, String.t(), Model.content_model()}} | {:error, String.t()}
  def parse_element(decl) do
    # Remove <!ELEMENT and trailing >
    case Regex.run(~r/^<!ELEMENT\s+(\S+)\s+(.+)>$/s, String.trim(decl)) do
      [_, name, content_spec] ->
        # Check for SGML-isms not allowed in XML
        cond do
          # SGML multiple element type: <!ELEMENT (a|b) ...>
          String.starts_with?(name, "(") ->
            {:error, "SGML shorthand for multiple element types not allowed in XML: #{name}"}

          # SGML exception spec: <!ELEMENT name (...) -exception> or +exception
          # Pattern matches ) followed by - or + and a name (with optional parens)
          Regex.match?(~r/\)\s*[-+]\s*\(?\s*\w/, content_spec) ->
            {:error, "SGML inclusion/exclusion exception not allowed in XML"}

          true ->
            case parse_content_model(String.trim(content_spec)) do
              {:ok, model} -> {:ok, {:element, name, model}}
              {:error, _} = err -> err
            end
        end

      nil ->
        {:error, "Invalid ELEMENT declaration: #{decl}"}
    end
  end

  @doc """
  Parse a content model specification.

  ## Examples

      iex> FnXML.DTD.Parser.parse_content_model("EMPTY")
      {:ok, :empty}

      iex> FnXML.DTD.Parser.parse_content_model("ANY")
      {:ok, :any}

      iex> FnXML.DTD.Parser.parse_content_model("(#PCDATA)")
      {:ok, :pcdata}

      iex> FnXML.DTD.Parser.parse_content_model("(a, b, c)")
      {:ok, {:seq, ["a", "b", "c"]}}

      iex> FnXML.DTD.Parser.parse_content_model("(a | b)")
      {:ok, {:choice, ["a", "b"]}}

      iex> FnXML.DTD.Parser.parse_content_model("(a, b)*")
      {:ok, {:zero_or_more, {:seq, ["a", "b"]}}}

  """
  @spec parse_content_model(String.t()) :: {:ok, Model.content_model()} | {:error, String.t()}
  def parse_content_model("EMPTY"), do: {:ok, :empty}
  def parse_content_model("ANY"), do: {:ok, :any}

  def parse_content_model(spec) do
    spec = String.trim(spec)

    # First, validate the content model syntax
    with :ok <- validate_content_model_syntax(spec) do
      cond do
        spec == "(#PCDATA)" ->
          {:ok, :pcdata}

        spec == "(#PCDATA)*" ->
          # Valid per XML spec 3.2.2 - mixed content with zero elements
          {:ok, :pcdata}

        String.starts_with?(spec, "(#PCDATA") and String.ends_with?(spec, ")*") ->
          # Mixed content: (#PCDATA | a | b)*
          parse_mixed_content(spec)

        String.starts_with?(spec, "(") ->
          parse_group(spec)

        true ->
          {:error, "Invalid content model: #{spec}"}
      end
    end
  end

  # Validate content model syntax before parsing
  defp validate_content_model_syntax(spec) do
    cond do
      # SGML keywords not allowed in XML
      spec == "CDATA" or spec == "RCDATA" ->
        {:error, "Invalid content model '#{spec}' - use (#PCDATA) instead"}

      # SGML minimization markers not allowed
      String.contains?(spec, "- -") or Regex.match?(~r/^-\s+-/, spec) ->
        {:error, "SGML minimization markers not allowed in XML"}

      # SGML inclusion/exclusion not allowed: +(foo) or -(foo)
      Regex.match?(~r/\)\s*[+-]\s*\(/, spec) ->
        {:error, "SGML inclusion/exclusion not allowed in XML"}

      # Empty content model
      spec == "()" or Regex.match?(~r/^\(\s*\)/, spec) ->
        {:error, "Empty content model not allowed"}

      # #PCDATA with invalid modifiers
      spec == "(#PCDATA)+" ->
        {:error, "Invalid modifier '+' on #PCDATA - use (#PCDATA) or (#PCDATA|...)*"}

      spec == "(#PCDATA)?" ->
        {:error, "Invalid modifier '?' on #PCDATA - use (#PCDATA) or (#PCDATA|...)*"}

      # Note: (#PCDATA)* IS valid per XML spec 3.2.2 - it's mixed content with zero elements

      # #PCDATA nested in extra parens
      Regex.match?(~r/\(\s*\(\s*#PCDATA/, spec) ->
        {:error, "#PCDATA cannot be nested in parentheses"}

      # #PCDATA not first in mixed content
      Regex.match?(~r/\([^#]*\|\s*#PCDATA/, spec) ->
        {:error, "#PCDATA must be first in mixed content declaration"}

      # Space between element/group and modifier
      Regex.match?(~r/[\w)]\s+[?*+]/, spec) ->
        {:error, "No space allowed before occurrence modifier"}

      # Multiple modifiers on same element (e.g., doc*? or foo+*)
      Regex.match?(~r/[?*+][?*+]/, spec) ->
        {:error, "Multiple occurrence modifiers not allowed"}

      # & used as connector (SGML feature, not allowed in XML)
      Regex.match?(~r/\w\s*&\s*\w/, spec) ->
        {:error, "Invalid connector '&' - use '|' for choice or ',' for sequence"}

      # Unbalanced parentheses
      not balanced_parens?(spec) ->
        {:error, "Unbalanced parentheses in content model"}

      # Mixed content with modifiers on elements: (#PCDATA | foo*)*
      String.starts_with?(spec, "(#PCDATA") and
          Regex.match?(~r/\|\s*\w+[?*+]/, spec) ->
        {:error, "Occurrence modifiers not allowed on elements in mixed content"}

      # Mixed content with nested groups: (#PCDATA | (foo))*
      # Alternatives must be simple names, not grouped content
      String.starts_with?(spec, "(#PCDATA") and
          Regex.match?(~r/\|\s*\(/, spec) ->
        {:error, "Nested groups not allowed in mixed content - use simple element names"}

      # Mixed content with alternatives MUST end with )*
      # (#PCDATA | a) is invalid, must be (#PCDATA | a)*
      # Handle optional spaces: ( #PCDATA | a )
      Regex.match?(~r/^\(\s*#PCDATA/, spec) and
        String.contains?(spec, "|") and
          not Regex.match?(~r/\)\s*\*\s*$/, spec) ->
        {:error, "Mixed content with alternatives must end with ')*'"}

      true ->
        :ok
    end
  end

  # Check if parentheses are balanced
  defp balanced_parens?(str), do: count_parens(str, 0)

  defp count_parens("", 0), do: true
  defp count_parens("", _), do: false
  defp count_parens(<<"(", rest::binary>>, n), do: count_parens(rest, n + 1)
  defp count_parens(<<")", _::binary>>, 0), do: false
  defp count_parens(<<")", rest::binary>>, n), do: count_parens(rest, n - 1)
  defp count_parens(<<_, rest::binary>>, n), do: count_parens(rest, n)

  @doc """
  Parse an ENTITY declaration.

  ## Options

  - `:edition` - XML 1.0 edition for name validation (4 or 5, default: 5)

  ## Examples

      iex> FnXML.DTD.Parser.parse_entity("<!ENTITY copyright \\"(c) 2024\\">")
      {:ok, {:entity, "copyright", {:internal, "(c) 2024"}}}

      iex> FnXML.DTD.Parser.parse_entity("<!ENTITY logo SYSTEM \\"logo.gif\\">")
      {:ok, {:entity, "logo", {:external, "logo.gif", nil}}}

      iex> FnXML.DTD.Parser.parse_entity("<!ENTITY % colors \\"red | green | blue\\">")
      {:ok, {:param_entity, "colors", "red | green | blue"}}

  """
  @spec parse_entity(String.t(), keyword()) :: {:ok, term()} | {:error, String.t()}
  def parse_entity(decl, opts \\ [])

  def parse_entity(decl, opts) do
    trimmed = String.trim(decl)
    edition = Keyword.get(opts, :edition, 5)
    external = Keyword.get(opts, :external, false)

    cond do
      # External SYSTEM parameter entity: <!ENTITY % name SYSTEM "uri">
      match = Regex.run(~r/^<!ENTITY\s+%\s+(\S+)\s+SYSTEM\s+["']([^"']*)["']\s*>$/s, trimmed) ->
        [_, name, system_id] = match

        with :ok <- validate_name(name, "parameter entity", edition) do
          {:ok, {:param_entity, name, {:external, system_id, nil}}}
        end

      # External PUBLIC parameter entity: <!ENTITY % name PUBLIC "pubid" "uri">
      match =
          Regex.run(
            ~r/^<!ENTITY\s+%\s+(\S+)\s+PUBLIC\s+["']([^"']+)["']\s+["']([^"']*)["']\s*>$/s,
            trimmed
          ) ->
        [_, name, public_id, system_id] = match

        with :ok <- validate_name(name, "parameter entity", edition),
             :ok <- validate_public_id(public_id) do
          {:ok, {:param_entity, name, {:external, system_id, public_id}}}
        end

      # Internal parameter entity: <!ENTITY % name "value">
      match = Regex.run(~r/^<!ENTITY\s+%\s+(\S+)\s+["'](.*)["']\s*>$/s, trimmed) ->
        [_, name, value] = match

        with :ok <- validate_name(name, "parameter entity", edition),
             :ok <- validate_param_entity_value(value) do
          {:ok, {:param_entity, name, value}}
        end

      # Internal entity: <!ENTITY name "value">
      match = Regex.run(~r/^<!ENTITY\s+(\S+)\s+["'](.*)["']\s*>$/s, trimmed) ->
        [_, name, value] = match

        with :ok <- validate_name(name, "entity", edition),
             :ok <- validate_entity_value(value, external: external) do
          {:ok, {:entity, name, {:internal, value}}}
        end

      # External SYSTEM entity: <!ENTITY name SYSTEM "uri">
      match = Regex.run(~r/^<!ENTITY\s+(\S+)\s+SYSTEM\s+["']([^"']*)["']\s*>$/s, trimmed) ->
        [_, name, system_id] = match

        with :ok <- validate_name(name, "entity", edition) do
          {:ok, {:entity, name, {:external, system_id, nil}}}
        end

      # External PUBLIC entity: <!ENTITY name PUBLIC "pubid" "uri">
      match =
          Regex.run(
            ~r/^<!ENTITY\s+(\S+)\s+PUBLIC\s+["']([^"']+)["']\s+["']([^"']*)["']\s*>$/s,
            trimmed
          ) ->
        [_, name, public_id, system_id] = match

        with :ok <- validate_name(name, "entity", edition),
             :ok <- validate_public_id(public_id) do
          {:ok, {:entity, name, {:external, system_id, public_id}}}
        end

      # External SYSTEM entity with NDATA: <!ENTITY name SYSTEM "uri" NDATA notation>
      match =
          Regex.run(
            ~r/^<!ENTITY\s+(\S+)\s+SYSTEM\s+["']([^"']*)["']\s+NDATA\s+(\S+)\s*>$/s,
            trimmed
          ) ->
        [_, name, system_id, notation] = match

        with :ok <- validate_name(name, "entity", edition) do
          {:ok, {:entity, name, {:external_unparsed, system_id, nil, notation}}}
        end

      # External PUBLIC entity with NDATA: <!ENTITY name PUBLIC "pubid" "uri" NDATA notation>
      match =
          Regex.run(
            ~r/^<!ENTITY\s+(\S+)\s+PUBLIC\s+["']([^"']+)["']\s+["']([^"']*)["']\s+NDATA\s+(\S+)\s*>$/s,
            trimmed
          ) ->
        [_, name, public_id, system_id, notation] = match

        with :ok <- validate_name(name, "entity", edition),
             :ok <- validate_public_id(public_id) do
          {:ok, {:entity, name, {:external_unparsed, system_id, public_id, notation}}}
        end

      true ->
        {:error, "Invalid ENTITY declaration: #{decl}"}
    end
  end

  @doc """
  Parse an ATTLIST declaration.

  ## Examples

      iex> FnXML.DTD.Parser.parse_attlist("<!ATTLIST note id ID #REQUIRED>")
      {:ok, {:attlist, "note", [%{name: "id", type: :id, default: :required}]}}

      iex> FnXML.DTD.Parser.parse_attlist("<!ATTLIST img src CDATA #REQUIRED alt CDATA #IMPLIED>")
      {:ok, {:attlist, "img", [%{name: "src", type: :cdata, default: :required}, %{name: "alt", type: :cdata, default: :implied}]}}

  """
  @spec parse_attlist(String.t()) ::
          {:ok, {:attlist, String.t(), [Model.attr_def()]}} | {:error, String.t()}
  def parse_attlist(decl) do
    # Remove <!ATTLIST and trailing >
    trimmed = String.trim(decl)

    cond do
      # Empty ATTLIST: <!ATTLIST element>
      match = Regex.run(~r/^<!ATTLIST\s+(\S+)\s*>$/s, trimmed) ->
        [_, element_name] = match

        with :ok <- validate_attlist_element_name(element_name) do
          {:ok, {:attlist, element_name, []}}
        end

      # ATTLIST with attributes
      match = Regex.run(~r/^<!ATTLIST\s+(\S+)\s+(.+)>$/s, trimmed) ->
        [_, element_name, attr_specs] = match

        with :ok <- validate_attlist_element_name(element_name),
             {:ok, attrs} <- parse_attr_defs(String.trim(attr_specs)) do
          {:ok, {:attlist, element_name, attrs}}
        end

      true ->
        {:error, "Invalid ATTLIST declaration: #{decl}"}
    end
  end

  # Validate ATTLIST element name for SGML-isms not allowed in XML
  defp validate_attlist_element_name(element_name) do
    cond do
      # SGML multiple element ATTLIST: <!ATTLIST (a|b) ...>
      String.starts_with?(element_name, "(") ->
        {:error,
         "SGML shorthand for multiple element ATTLIST not allowed in XML: #{element_name}"}

      # SGML global ATTLIST: <!ATTLIST #ALL ...>
      element_name == "#ALL" ->
        {:error, "SGML global ATTLIST (#ALL) not allowed in XML"}

      true ->
        :ok
    end
  end

  @doc """
  Parse a NOTATION declaration.
  """
  @spec parse_notation(String.t()) ::
          {:ok, {:notation, String.t(), String.t() | nil, String.t() | nil}}
          | {:error, String.t()}
  def parse_notation(decl) do
    trimmed = String.trim(decl)

    cond do
      # SYSTEM notation
      match = Regex.run(~r/^<!NOTATION\s+(\S+)\s+SYSTEM\s+["']([^"']*)["']\s*>$/s, trimmed) ->
        [_, name, system_id] = match
        {:ok, {:notation, name, system_id, nil}}

      # PUBLIC notation with SYSTEM
      match =
          Regex.run(
            ~r/^<!NOTATION\s+(\S+)\s+PUBLIC\s+["']([^"']+)["']\s+["']([^"']*)["']\s*>$/s,
            trimmed
          ) ->
        [_, name, public_id, system_id] = match

        with :ok <- validate_public_id(public_id) do
          {:ok, {:notation, name, system_id, public_id}}
        end

      # PUBLIC notation without SYSTEM
      match = Regex.run(~r/^<!NOTATION\s+(\S+)\s+PUBLIC\s+["']([^"']+)["']\s*>$/s, trimmed) ->
        [_, name, public_id] = match

        with :ok <- validate_public_id(public_id) do
          {:ok, {:notation, name, nil, public_id}}
        end

      true ->
        {:error, "Invalid NOTATION declaration: #{decl}"}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  # Extract individual declarations from a DTD string
  # Handles quoted strings containing > characters
  defp extract_declarations(dtd_string, opts) do
    external = Keyword.get(opts, :external, false)
    edition = Keyword.get(opts, :edition, 5)
    extract_declarations_impl(dtd_string, [], external, edition)
  end

  defp extract_declarations_impl("", acc, _external, _edition), do: Enum.reverse(acc)

  defp extract_declarations_impl(<<"<![", _rest::binary>>, acc, _external, _edition) do
    # Conditional section (INCLUDE/IGNORE) - not allowed in internal subset
    # For external DTDs, these should already be processed by ExternalResolver
    [{:error, "Conditional sections (INCLUDE/IGNORE) not allowed in internal DTD subset"} | acc]
    |> Enum.reverse()
  end

  defp extract_declarations_impl(<<"<?xml", _rest::binary>>, acc, false, _edition) do
    # XML declaration not allowed in internal subset (can only appear at document start)
    [{:error, "XML declaration not allowed in internal DTD subset"} | acc]
    |> Enum.reverse()
  end

  defp extract_declarations_impl(<<"<?xml", rest::binary>>, acc, true, edition) do
    # Text declaration is allowed in external DTD, but must validate content
    # TextDecl ::= '<?xml' VersionInfo? EncodingDecl S? '?>'
    # Text declarations MUST appear at the beginning of the external entity
    # Text declarations MUST have encoding declaration
    # Text declarations MUST NOT include standalone declaration (only documents can have it)
    case extract_text_decl_content(rest) do
      {:ok, content, remaining} ->
        content_lower = String.downcase(content)

        cond do
          # Text declaration must be at the beginning (acc should be empty)
          acc != [] ->
            [{:error, "Text declaration must appear at the beginning of external entity"} | acc]
            |> Enum.reverse()

          String.contains?(content_lower, "standalone") ->
            [{:error, "Text declaration in external entity must not include 'standalone'"} | acc]
            |> Enum.reverse()

          not String.contains?(content_lower, "encoding") ->
            [{:error, "Text declaration in external entity must include 'encoding'"} | acc]
            |> Enum.reverse()

          true ->
            extract_declarations_impl(remaining, acc, true, edition)
        end

      :error ->
        [{:error, "Unterminated text declaration in external DTD"} | acc]
        |> Enum.reverse()
    end
  end

  defp extract_declarations_impl(<<"<?", rest::binary>>, acc, external, edition) do
    # Validate PI target in DTD internal subset with edition-specific char validation
    case validate_pi_in_dtd(rest, edition) do
      {:ok, remaining} ->
        # PI is valid, continue processing
        extract_declarations_impl(remaining, acc, external, edition)

      {:error, reason} ->
        # Invalid PI target
        [{:error, reason} | acc] |> Enum.reverse()
    end
  end

  defp extract_declarations_impl(<<"<!--", rest::binary>>, acc, external, edition) do
    # Comment - skip until --> without processing quotes
    # Comments can contain any characters including ' and " without issues
    case skip_to_comment_end(rest) do
      {:ok, remaining} ->
        extract_declarations_impl(remaining, acc, external, edition)

      :not_found ->
        # Unterminated comment - return what we have
        Enum.reverse(acc)
    end
  end

  defp extract_declarations_impl(<<"<!", rest::binary>>, acc, external, edition) do
    # Found start of a declaration, extract it respecting quotes
    case extract_single_declaration(rest, "<!") do
      {:ok, decl, remaining} ->
        extract_declarations_impl(remaining, [decl | acc], external, edition)

      :not_found ->
        # Skip this <! and continue
        extract_declarations_impl(rest, acc, external, edition)
    end
  end

  # Element-like tag without ! (e.g., <NOTATION instead of <!NOTATION)
  defp extract_declarations_impl(<<"<", c, _rest::binary>>, acc, _external, _edition)
       when c in ?a..?z or c in ?A..?Z do
    [{:error, "Invalid declaration in DTD - missing '!' after '<'"} | acc]
    |> Enum.reverse()
  end

  # PE reference: must be %Name; with no whitespace
  defp extract_declarations_impl(<<"%", rest::binary>>, acc, external, edition) do
    case validate_pe_reference_syntax(rest) do
      {:ok, remaining} ->
        # Valid PE reference syntax (we don't expand, just skip)
        extract_declarations_impl(remaining, acc, external, edition)

      {:error, reason} ->
        [{:error, reason} | acc] |> Enum.reverse()
    end
  end

  # General entity reference in DTD - not allowed
  # General entity references can only appear in element content and attribute values
  defp extract_declarations_impl(<<"&", rest::binary>>, acc, _external, _edition) do
    # Check if this looks like an entity reference (& followed by name char)
    case rest do
      <<c, _::binary>> when c in ?a..?z or c in ?A..?Z or c == ?_ or c == ?# ->
        [{:error, "General entity reference not allowed in DTD declarations"} | acc]
        |> Enum.reverse()

      _ ->
        # Just a bare &, which will be caught by other validation
        [{:error, "Invalid '&' in DTD declarations"} | acc]
        |> Enum.reverse()
    end
  end

  defp extract_declarations_impl(<<_, rest::binary>>, acc, external, edition) do
    extract_declarations_impl(rest, acc, external, edition)
  end

  # Validate PE reference syntax: %Name;
  # Name must start immediately after %, semicolon must follow name immediately
  defp validate_pe_reference_syntax(<<c, _rest::binary>>) when c in [?\s, ?\t, ?\r, ?\n] do
    {:error, "Invalid PE reference: space not allowed after '%'"}
  end

  defp validate_pe_reference_syntax(<<c, rest::binary>>)
       when c in ?a..?z or c in ?A..?Z or c == ?_ or c == ?: do
    # Valid name start char, collect the rest of the name
    collect_pe_name(rest, <<c>>)
  end

  defp validate_pe_reference_syntax(_) do
    {:error, "Invalid PE reference: expected name after '%'"}
  end

  defp collect_pe_name(<<";", rest::binary>>, _name) do
    {:ok, rest}
  end

  defp collect_pe_name(<<c, _rest::binary>>, name) when c in [?\s, ?\t, ?\r, ?\n] do
    {:error, "Invalid PE reference '%#{name}': whitespace not allowed before ';'"}
  end

  defp collect_pe_name(<<c, rest::binary>>, name)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?: or c == ?- or
              c == ?. do
    collect_pe_name(rest, <<name::binary, c>>)
  end

  defp collect_pe_name(<<>>, name) do
    {:error, "Unterminated PE reference '%#{name}'"}
  end

  defp collect_pe_name(_, name) do
    {:error, "Invalid character in PE reference '%#{name}'"}
  end

  # Extract a single declaration, respecting quoted strings
  defp extract_single_declaration(<<">", rest::binary>>, acc) do
    {:ok, acc <> ">", rest}
  end

  defp extract_single_declaration(<<"\"", rest::binary>>, acc) do
    # Start of double-quoted string, find end quote
    case skip_quoted_string(rest, "\"", "\"") do
      {:ok, quoted, remaining} ->
        extract_single_declaration(remaining, acc <> quoted)

      :not_found ->
        :not_found
    end
  end

  defp extract_single_declaration(<<"'", rest::binary>>, acc) do
    # Start of single-quoted string, find end quote
    case skip_quoted_string(rest, "'", "'") do
      {:ok, quoted, remaining} ->
        extract_single_declaration(remaining, acc <> quoted)

      :not_found ->
        :not_found
    end
  end

  defp extract_single_declaration(<<c, rest::binary>>, acc) do
    extract_single_declaration(rest, acc <> <<c>>)
  end

  defp extract_single_declaration("", _acc), do: :not_found

  # Skip over a quoted string until closing quote
  defp skip_quoted_string(<<quote, rest::binary>>, <<quote>>, acc) do
    {:ok, acc <> <<quote>>, rest}
  end

  defp skip_quoted_string(<<c, rest::binary>>, quote, acc) do
    skip_quoted_string(rest, quote, acc <> <<c>>)
  end

  defp skip_quoted_string("", _quote, _acc), do: :not_found

  # Skip to end of comment (-->)
  defp skip_to_comment_end(<<"-->", rest::binary>>), do: {:ok, rest}
  defp skip_to_comment_end(<<_, rest::binary>>), do: skip_to_comment_end(rest)
  defp skip_to_comment_end(<<>>), do: :not_found

  # Parse mixed content: (#PCDATA | a | b | c)*
  defp parse_mixed_content(spec) do
    # Remove outer parens and trailing *
    inner =
      spec
      |> String.trim_leading("(")
      |> String.trim_trailing(")*")
      |> String.trim()

    # Split by | and extract element names (skip #PCDATA)
    elements =
      inner
      |> String.split("|")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "#PCDATA"))

    if Enum.empty?(elements) do
      {:ok, :pcdata}
    else
      {:ok, {:mixed, elements}}
    end
  end

  # Parse a parenthesized group: (a, b, c) or (a | b | c) with optional occurrence
  defp parse_group(spec) do
    # Check for occurrence indicator at end
    case extract_occurrence(spec) do
      {:error, _} = err ->
        err

      {inner, occurrence} ->
        parse_group_content(inner, occurrence)
    end
  end

  defp parse_group_content(inner, occurrence) do
    # Remove exactly one pair of outer parens (not all leading/trailing parens)
    inner = remove_outer_parens(inner)

    # Find top-level separators (not nested in parens)
    has_top_comma = has_top_level_separator?(inner, ?,)
    has_top_bar = has_top_level_separator?(inner, ?|)

    # Determine if sequence or choice
    result =
      cond do
        has_top_comma and not has_top_bar ->
          case parse_group_items(inner, ",") do
            {:error, {:invalid_name, name}} ->
              {:error, "Invalid element name in content model: '#{name}' - missing separator?"}

            {:error, reason} ->
              {:error, "Invalid content model: #{inspect(reason)}"}

            items ->
              {:ok, {:seq, items}}
          end

        has_top_bar and not has_top_comma ->
          case parse_group_items(inner, "|") do
            {:error, {:invalid_name, name}} ->
              {:error, "Invalid element name in content model: '#{name}' - missing separator?"}

            {:error, reason} ->
              {:error, "Invalid content model: #{inspect(reason)}"}

            items ->
              {:ok, {:choice, items}}
          end

        not has_top_comma and not has_top_bar ->
          # Single item
          item = String.trim(inner)

          case parse_item(item) do
            {:error, {:invalid_name, name}} ->
              {:error, "Invalid element name in content model: '#{name}'"}

            {:error, reason} ->
              {:error, "Invalid content model: #{inspect(reason)}"}

            parsed_item ->
              {:ok, parsed_item}
          end

        true ->
          # Mixed operators at top level - error per XML spec
          {:error, "Cannot mix ',' and '|' at the same level in content model"}
      end

    case result do
      {:ok, model} when occurrence != nil ->
        {:ok, {occurrence, model}}

      other ->
        other
    end
  end

  # Remove exactly one pair of outer parentheses
  defp remove_outer_parens(<<"(", rest::binary>>) do
    # Remove leading ( and trailing )
    if String.ends_with?(rest, ")") do
      String.slice(rest, 0..-2//1)
    else
      rest
    end
  end

  defp remove_outer_parens(str), do: str

  # Check if a separator exists at the top level (depth 0)
  defp has_top_level_separator?(string, sep_char) do
    check_top_level_separator(string, sep_char, 0)
  end

  defp check_top_level_separator(<<>>, _sep, _depth), do: false

  defp check_top_level_separator(<<?(, rest::binary>>, sep, depth),
    do: check_top_level_separator(rest, sep, depth + 1)

  defp check_top_level_separator(<<?), rest::binary>>, sep, depth),
    do: check_top_level_separator(rest, sep, max(depth - 1, 0))

  defp check_top_level_separator(<<c, _rest::binary>>, sep, 0) when c == sep, do: true

  defp check_top_level_separator(<<_, rest::binary>>, sep, depth),
    do: check_top_level_separator(rest, sep, depth)

  # Extract occurrence indicator (?, *, +) from end of spec
  # Returns {inner, occurrence} or {:error, reason}
  defp extract_occurrence(spec) do
    spec = String.trim(spec)

    cond do
      String.ends_with?(spec, ")?") ->
        {String.trim_trailing(spec, "?"), :optional}

      String.ends_with?(spec, ")*") ->
        {String.trim_trailing(spec, "*"), :zero_or_more}

      String.ends_with?(spec, ")+") ->
        {String.trim_trailing(spec, "+"), :one_or_more}

      # Check for invalid occurrence indicator after )
      Regex.match?(~r/\)[^)]+$/, spec) ->
        {:error, "Invalid occurrence indicator in content model: #{spec}"}

      true ->
        {spec, nil}
    end
  end

  # Split group items, respecting nested parens
  # Returns list of items or {:error, reason} if any item is invalid
  defp parse_group_items(inner, separator) do
    items =
      inner
      |> split_respecting_parens(separator)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&parse_item/1)

    # Check if any item is an error
    case Enum.find(items, &match?({:error, _}, &1)) do
      {:error, _} = err -> err
      nil -> items
    end
  end

  # Parse a single item which may have occurrence indicator
  defp parse_item(item) do
    item = String.trim(item)

    cond do
      # #PCDATA keyword in mixed content
      item == "#PCDATA" ->
        :pcdata

      # Check for nested groups FIRST (with or without occurrence indicator)
      # e.g., "(a,b)", "(a|b)+", "(a,b)*", "(a|b)?"
      String.starts_with?(item, "(") ->
        # Nested group - propagate any errors
        case parse_group(item) do
          {:ok, model} -> model
          {:error, _} = err -> err
        end

      # Simple element with occurrence indicator
      String.ends_with?(item, "?") ->
        name = String.trim_trailing(item, "?")
        validate_content_element_name(name, {:optional, name})

      String.ends_with?(item, "*") ->
        name = String.trim_trailing(item, "*")
        validate_content_element_name(name, {:zero_or_more, name})

      String.ends_with?(item, "+") ->
        name = String.trim_trailing(item, "+")
        validate_content_element_name(name, {:one_or_more, name})

      true ->
        validate_content_element_name(item, item)
    end
  end

  # Validate that an element name in content model is a valid XML name
  defp validate_content_element_name(name, result) do
    cond do
      # Empty name
      name == "" ->
        {:error, :empty_name}

      # Name contains whitespace (missing separator)
      String.contains?(name, " ") or String.contains?(name, "\t") ->
        {:error, {:invalid_name, name}}

      # Name starts with digit or invalid char
      not valid_name_start_char?(String.first(name)) ->
        {:error, {:invalid_name, name}}

      # Name contains invalid characters
      not valid_name?(name) ->
        {:error, {:invalid_name, name}}

      true ->
        result
    end
  end

  defp valid_name_start_char?(nil), do: false

  defp valid_name_start_char?(char) do
    <<c::utf8>> = char
    c in ?a..?z or c in ?A..?Z or c == ?_ or c == ?:
  end

  # Check if all characters in the name are valid XML name characters
  defp valid_name?(name) do
    # XML name: starts with letter/underscore/colon, followed by letters/digits/hyphens/underscores/colons/periods
    Regex.match?(~r/^[a-zA-Z_:][a-zA-Z0-9._:-]*$/, name)
  end

  # Split a string by separator, but respect nested parentheses
  defp split_respecting_parens(string, separator) do
    do_split(string, separator, 0, "", [])
  end

  defp do_split("", _sep, _depth, current, acc) do
    Enum.reverse([current | acc])
  end

  defp do_split(<<?(, rest::binary>>, sep, depth, current, acc) do
    do_split(rest, sep, depth + 1, current <> "(", acc)
  end

  defp do_split(<<?), rest::binary>>, sep, depth, current, acc) do
    do_split(rest, sep, depth - 1, current <> ")", acc)
  end

  defp do_split(<<c, rest::binary>>, sep, 0, current, acc) when <<c>> == sep do
    do_split(rest, sep, 0, "", [current | acc])
  end

  defp do_split(<<c, rest::binary>>, sep, depth, current, acc) do
    do_split(rest, sep, depth, current <> <<c>>, acc)
  end

  # Parse attribute definitions from the spec after element name
  defp parse_attr_defs(spec) do
    # Simple tokenizer for attribute definitions
    parse_attr_defs_impl(String.trim(spec), [])
  end

  defp parse_attr_defs_impl("", acc), do: {:ok, Enum.reverse(acc)}

  defp parse_attr_defs_impl(spec, acc) do
    case parse_single_attr_def(spec) do
      {:ok, attr_def, rest} ->
        parse_attr_defs_impl(String.trim(rest), [attr_def | acc])

      {:error, _} = err ->
        err
    end
  end

  # Parse a single attribute definition: name type default
  defp parse_single_attr_def(spec) do
    # Extract attribute name
    case Regex.run(~r/^(\S+)\s+(.+)$/s, spec) do
      [_, name, rest] ->
        case parse_attr_type_and_default(String.trim(rest)) do
          {:ok, type, default, remaining} ->
            {:ok, %{name: name, type: type, default: default}, remaining}

          {:error, _} = err ->
            err
        end

      nil ->
        {:error, "Invalid attribute definition: #{spec}"}
    end
  end

  # Parse attribute type and default value
  defp parse_attr_type_and_default(spec) do
    cond do
      # Enumeration type: (a|b|c) ...
      String.starts_with?(spec, "(") ->
        parse_enum_attr(spec)

      # NOTATION type
      String.starts_with?(spec, "NOTATION") ->
        parse_notation_attr(spec)

      # Keyword types
      true ->
        parse_keyword_attr(spec)
    end
  end

  # Parse enumeration attribute: (a|b|c) default
  defp parse_enum_attr(spec) do
    # Check for empty enumeration () first
    if String.starts_with?(spec, "()") do
      {:error, "Empty enumeration not allowed"}
    else
      # Use a regex that captures what's immediately after )
      case Regex.run(~r/^\(([^)]*)\)(.*)$/s, spec) do
        [_, values, after_paren] ->
          values_trimmed = String.trim(values)

          cond do
            # Empty enumeration
            values_trimmed == "" ->
              {:error, "Empty enumeration not allowed"}

            # Check for invalid comma separator (should be | per XML spec)
            String.contains?(values, ",") ->
              {:error, "Enumeration uses comma instead of '|': (#{values})"}

            # Missing whitespace after enumeration (but empty is OK if at end)
            after_paren != "" and not String.match?(after_paren, ~r/^\s/) ->
              {:error, "Missing whitespace after enumeration"}

            # Check for quoted values (not allowed in XML enumerations)
            String.contains?(values, "\"") or String.contains?(values, "'") ->
              {:error, "Quoted values not allowed in enumeration: (#{values})"}

            true ->
              enum_values = values |> String.split("|") |> Enum.map(&String.trim/1)

              # Check for empty values in enumeration
              if Enum.any?(enum_values, &(&1 == "")) do
                {:error, "Empty value in enumeration: (#{values})"}
              else
                rest = String.trim(after_paren)

                case parse_attr_default(rest) do
                  {:ok, default, remaining} ->
                    {:ok, {:enum, enum_values}, default, remaining}

                  {:error, _} = err ->
                    err
                end
              end
          end

        nil ->
          {:error, "Invalid enumeration attribute: #{spec}"}
      end
    end
  end

  # Parse NOTATION attribute
  defp parse_notation_attr(spec) do
    # Check for empty NOTATION list
    if Regex.match?(~r/^NOTATION\s+\(\s*\)/, spec) do
      {:error, "Empty NOTATION list not allowed"}
    else
      case Regex.run(~r/^NOTATION\s+\(([^)]*)\)(.*)$/s, spec) do
        [_, notations, after_paren] ->
          notations_trimmed = String.trim(notations)

          cond do
            # Empty notation list
            notations_trimmed == "" ->
              {:error, "Empty NOTATION list not allowed"}

            # Check for comma separator (should be | per XML spec)
            String.contains?(notations, ",") ->
              {:error, "NOTATION list uses comma instead of '|': (#{notations})"}

            # Check for quoted names (not allowed in XML)
            String.contains?(notations, "\"") or String.contains?(notations, "'") ->
              {:error, "Quoted names not allowed in NOTATION list: (#{notations})"}

            # Missing whitespace after notation list
            after_paren != "" and not String.match?(after_paren, ~r/^\s/) ->
              {:error, "Missing whitespace after NOTATION list"}

            true ->
              notation_names = notations |> String.split("|") |> Enum.map(&String.trim/1)

              # Check for empty values
              if Enum.any?(notation_names, &(&1 == "")) do
                {:error, "Empty value in NOTATION list"}
              else
                rest = String.trim(after_paren)

                case parse_attr_default(rest) do
                  {:ok, default, remaining} ->
                    {:ok, {:notation, notation_names}, default, remaining}

                  {:error, _} = err ->
                    err
                end
              end
          end

        nil ->
          {:error, "Invalid NOTATION attribute: #{spec}"}
      end
    end
  end

  # Parse keyword type attribute: CDATA, ID, IDREF, etc.
  defp parse_keyword_attr(spec) do
    type_keywords = [
      {"IDREFS", :idrefs},
      {"IDREF", :idref},
      {"ID", :id},
      {"ENTITIES", :entities},
      {"ENTITY", :entity},
      {"NMTOKENS", :nmtokens},
      {"NMTOKEN", :nmtoken},
      {"CDATA", :cdata}
    ]

    Enum.find_value(type_keywords, {:error, "Unknown attribute type: #{spec}"}, fn {keyword, type} ->
      if String.starts_with?(spec, keyword) do
        after_keyword = String.slice(spec, String.length(keyword)..-1//1)

        # Must have whitespace after keyword (XML spec requirement)
        if after_keyword == "" or not String.match?(after_keyword, ~r/^\s/) do
          {:error, "Missing whitespace after attribute type '#{keyword}'"}
        else
          rest = String.trim(after_keyword)

          case parse_attr_default(rest) do
            {:ok, default, remaining} ->
              {:ok, type, default, remaining}

            {:error, _} = err ->
              err
          end
        end
      end
    end)
  end

  # Parse attribute default: #REQUIRED, #IMPLIED, #FIXED "value", or "default"
  defp parse_attr_default(spec) do
    cond do
      String.starts_with?(spec, "#REQUIRED") ->
        {:ok, :required, String.trim_leading(spec, "#REQUIRED") |> String.trim()}

      String.starts_with?(spec, "#IMPLIED") ->
        {:ok, :implied, String.trim_leading(spec, "#IMPLIED") |> String.trim()}

      String.starts_with?(spec, "#FIXED") ->
        after_fixed = String.slice(spec, 6..-1//1)

        # XML spec requires whitespace between #FIXED and the value
        if after_fixed == "" or not String.match?(after_fixed, ~r/^\s/) do
          {:error, "Missing whitespace after #FIXED"}
        else
          rest = String.trim(after_fixed)

          case extract_quoted_value(rest) do
            {:ok, value, remaining} -> {:ok, {:fixed, value}, remaining}
            {:error, _} = err -> err
          end
        end

      String.starts_with?(spec, "\"") or String.starts_with?(spec, "'") ->
        case extract_quoted_value(spec) do
          {:ok, value, remaining} -> {:ok, {:default, value}, remaining}
          {:error, _} = err -> err
        end

      true ->
        {:error, "Invalid attribute default: #{spec}"}
    end
  end

  # Extract a quoted value from the beginning of a string
  defp extract_quoted_value(spec) do
    case Regex.run(~r/^["']([^"']*)["'](.*)$/s, spec) do
      [_, value, rest] ->
        {:ok, value, String.trim(rest)}

      nil ->
        {:error, "Expected quoted value: #{spec}"}
    end
  end

  # Validate XML Name (for entity, element, attribute, notation names)
  # Uses FnXML.Char for edition-specific character validation
  defp validate_name(name, context, edition) do
    case name do
      "" ->
        {:error, "Empty #{context} name"}

      _ ->
        if FnXML.Char.valid_name?(name, edition: edition) do
          :ok
        else
          {:error, "Invalid #{context} name '#{name}' - contains invalid characters"}
        end
    end
  end

  # Validate entity value for general entities
  # Must not contain bare & or % that isn't part of a valid reference
  # Per XML spec Production [9] EntityValue, the content must be:
  #   [^%&"] | PEReference | Reference
  # This means bare % and & are NOT allowed - they must be part of references.
  #
  # In internal DTD subset, PEs are not recognized in literal entity values,
  # so %name; patterns are still invalid (they're not recognized as PEReferences).
  # In external DTDs, %name; is recognized and expanded as a PE reference.
  defp validate_entity_value(value, _opts) do
    # Check for bare % first (required in both internal and external DTDs)
    case find_bare_percent(value) do
      nil ->
        validate_entity_value_content(value)

      pos ->
        {:error, "Entity value contains bare '%' at position #{pos}"}
    end
  end

  # Common validation logic for entity values (ampersand and content checks)
  defp validate_entity_value_content(value) do
    case find_bare_ampersand(value) do
      nil ->
        # Expand character references and validate the result
        case expand_char_refs(value) do
          {:ok, expanded} ->
            # Check if expanded value contains bare ampersands
            # (e.g., &#38; expands to & which is a bare ampersand)
            cond do
              String.contains?(expanded, "&") and not_escaped_ampersand?(expanded) ->
                {:error,
                 "Entity replacement text produces bare '&' after character reference expansion"}

              # Check if the replacement text is well-formed as content
              not well_formed_content?(expanded) ->
                {:error, "Entity replacement text is not well-formed"}

              # Check for reserved PI target "xml" (case-insensitive)
              # Per XML spec: PI targets matching [Xx][Mm][Ll] are reserved
              has_reserved_pi_target?(expanded) ->
                {:error, "Entity replacement text contains reserved PI target 'xml'"}

              true ->
                :ok
            end

          {:error, reason} ->
            {:error, reason}
        end

      pos ->
        {:error, "Entity value contains bare '&' at position #{pos}"}
    end
  end

  # Check if content is well-formed (balanced tags)
  # Per XML spec Section 4.3.2, entity replacement text must match the
  # `content` production, meaning all elements must be complete (balanced).
  defp well_formed_content?(content) do
    cond do
      # Content can't start with an end tag
      Regex.match?(~r/^\s*<\//, content) ->
        false

      # Check for unclosed tags (< followed by name but no >)
      # Pattern: < followed by name chars but NOT followed by > before another < or end
      has_unclosed_tag?(content) ->
        false

      true ->
        # Extract all tags in order with their positions
        # We need to check proper nesting, not just counts
        validate_tag_structure(content)
    end
  end

  # Check if content contains a PI with reserved target "xml" (case-insensitive)
  # Per XML spec: "The target names 'XML', 'xml', and so on are reserved"
  defp has_reserved_pi_target?(content) do
    # Match <?xml followed by whitespace or ?>
    # This catches <?xml?>, <?xml ...?>, etc.
    Regex.match?(~r/<\?[Xx][Mm][Ll](\s|\?>|$)/, content)
  end

  # Check for unclosed tags like "<foo" without closing ">"
  defp has_unclosed_tag?(content) do
    # Find all occurrences of < followed by name characters
    # Each should have a > before the next < or end of string
    check_unclosed_tags(content)
  end

  defp check_unclosed_tags(<<>>), do: false

  defp check_unclosed_tags(<<?<, rest::binary>>) do
    # Found <, now look for > before next < or end
    case find_tag_end(rest) do
      :found -> check_unclosed_tags(rest)
      :unclosed -> true
    end
  end

  defp check_unclosed_tags(<<_, rest::binary>>), do: check_unclosed_tags(rest)

  defp find_tag_end(<<>>), do: :unclosed
  defp find_tag_end(<<?>, _rest::binary>>), do: :found
  defp find_tag_end(<<?<, _rest::binary>>), do: :unclosed
  defp find_tag_end(<<_, rest::binary>>), do: find_tag_end(rest)

  # Validate that tags are properly nested using a stack
  defp validate_tag_structure(content) do
    # Find all tags with their types and positions
    tags = extract_all_tags(content)

    # Use a stack to validate proper nesting
    validate_tag_stack(tags, [])
  end

  # Extract all tags (start, end, self-closing) in order
  defp extract_all_tags(content) do
    # Pattern matches all tags
    pattern = ~r/<(\/?)([a-zA-Z_][a-zA-Z0-9._:-]*)(?:\s[^>]*)?(\/?)>/

    Regex.scan(pattern, content, return: :index)
    |> Enum.map(fn [{start, len} | _] ->
      tag_str = binary_part(content, start, len)

      cond do
        String.starts_with?(tag_str, "</") ->
          # End tag
          [_, name] = Regex.run(~r/<\/([a-zA-Z_][a-zA-Z0-9._:-]*)/, tag_str)
          {:end, name}

        String.ends_with?(tag_str, "/>") ->
          # Self-closing tag - no stack change needed
          :self_closing

        true ->
          # Start tag
          [_, name] = Regex.run(~r/<([a-zA-Z_][a-zA-Z0-9._:-]*)/, tag_str)
          {:start, name}
      end
    end)
    |> Enum.reject(&(&1 == :self_closing))
  end

  # Validate tags using a stack - returns true if balanced
  defp validate_tag_stack([], []), do: true
  defp validate_tag_stack([], _stack), do: false

  defp validate_tag_stack([{:start, name} | rest], stack) do
    validate_tag_stack(rest, [name | stack])
  end

  defp validate_tag_stack([{:end, name} | rest], [name | stack]) do
    validate_tag_stack(rest, stack)
  end

  # End tag doesn't match top of stack
  defp validate_tag_stack([{:end, _name} | _rest], _stack), do: false

  # Check if ampersand in expanded text is not part of an entity reference
  defp not_escaped_ampersand?(text) do
    # After char ref expansion, any & must be followed by a valid entity ref pattern
    # Otherwise it's a bare ampersand
    case :binary.match(text, "&") do
      :nomatch ->
        false

      {pos, _} ->
        rest = binary_part(text, pos + 1, byte_size(text) - pos - 1)
        not valid_entity_ref_follows?(rest)
    end
  end

  defp valid_entity_ref_follows?(rest) do
    cond do
      Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9._-]*;/, rest) -> true
      Regex.match?(~r/^#[0-9]+;/, rest) -> true
      Regex.match?(~r/^#x[0-9a-fA-F]+;/, rest) -> true
      true -> false
    end
  end

  # Expand character references in entity value
  # Returns {:ok, expanded} or {:error, reason}
  defp expand_char_refs(value) do
    try do
      expanded =
        Regex.replace(~r/&#x([0-9a-fA-F]+);|&#([0-9]+);/, value, fn
          full, hex, "" ->
            case Integer.parse(hex, 16) do
              {cp, ""} when cp >= 0 ->
                try do
                  <<cp::utf8>>
                rescue
                  _ -> throw({:invalid_char_ref, full})
                end

              _ ->
                throw({:invalid_char_ref, full})
            end

          full, "", decimal ->
            case Integer.parse(decimal) do
              {cp, ""} when cp >= 0 ->
                try do
                  <<cp::utf8>>
                rescue
                  _ -> throw({:invalid_char_ref, full})
                end

              _ ->
                throw({:invalid_char_ref, full})
            end
        end)

      {:ok, expanded}
    catch
      {:invalid_char_ref, ref} -> {:error, "Invalid character reference: #{ref}"}
    end
  end

  # Validate parameter entity value
  # Must not contain bare & or % that aren't part of valid references
  defp validate_param_entity_value(value) do
    case find_bare_ampersand(value) do
      nil ->
        case find_bare_percent(value) do
          nil -> :ok
          pos -> {:error, "Parameter entity value contains bare '%' at position #{pos}"}
        end

      pos ->
        {:error, "Parameter entity value contains bare '&' at position #{pos}"}
    end
  end

  # Find bare & that isn't followed by a valid entity reference pattern
  # Valid patterns: &name; or &#digits; or &#xhex;
  defp find_bare_ampersand(value) do
    find_bare_ampersand(value, 0)
  end

  defp find_bare_ampersand(<<>>, _pos), do: nil

  defp find_bare_ampersand(<<"&", rest::binary>>, pos) do
    # Check if followed by valid entity reference pattern
    cond do
      # Character reference: &#digits; or &#xhex;
      Regex.match?(~r/^#[0-9]+;/, rest) ->
        find_bare_ampersand(skip_until_semicolon(rest), pos + 1)

      Regex.match?(~r/^#x[0-9a-fA-F]+;/, rest) ->
        find_bare_ampersand(skip_until_semicolon(rest), pos + 1)

      # Entity reference: &name;
      Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9._-]*;/, rest) ->
        find_bare_ampersand(skip_until_semicolon(rest), pos + 1)

      # Bare &
      true ->
        pos
    end
  end

  defp find_bare_ampersand(<<_, rest::binary>>, pos) do
    find_bare_ampersand(rest, pos + 1)
  end

  # Find bare % that isn't followed by a valid PE reference pattern
  defp find_bare_percent(value) do
    find_bare_percent(value, 0)
  end

  defp find_bare_percent(<<>>, _pos), do: nil

  defp find_bare_percent(<<"%", rest::binary>>, pos) do
    # Check if followed by valid PE reference pattern: %name;
    if Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9._-]*;/, rest) do
      find_bare_percent(skip_until_semicolon(rest), pos + 1)
    else
      pos
    end
  end

  defp find_bare_percent(<<_, rest::binary>>, pos) do
    find_bare_percent(rest, pos + 1)
  end

  defp skip_until_semicolon(<<";", rest::binary>>), do: rest
  defp skip_until_semicolon(<<_, rest::binary>>), do: skip_until_semicolon(rest)
  defp skip_until_semicolon(<<>>), do: <<>>

  # Validate PUBLIC identifier characters per XML spec
  # PubidChar ::= #x20 | #xD | #xA | [a-zA-Z0-9] | [-'()+,./:=?;!*#@$_%]
  @doc false
  def validate_public_id(public_id) do
    invalid_char =
      public_id
      |> String.graphemes()
      |> Enum.find(fn char ->
        not valid_pubid_char?(char)
      end)

    case invalid_char do
      nil -> :ok
      char -> {:error, "Invalid character '#{char}' in PUBLIC identifier"}
    end
  end

  defp valid_pubid_char?(<<c>>) when c in [0x20, 0x0D, 0x0A], do: true
  defp valid_pubid_char?(<<c>>) when c in ?a..?z or c in ?A..?Z or c in ?0..?9, do: true
  defp valid_pubid_char?(<<c>>) when c in ~c[-'()+,./:=?;!*#@$_%], do: true
  defp valid_pubid_char?(_), do: false

  # ============================================================================
  # PI validation in DTD internal subset
  # ============================================================================

  # Validate a PI inside DTD, return {:ok, remaining} or {:error, reason}
  # Uses edition-specific character validation
  defp validate_pi_in_dtd(rest, edition) do
    case extract_pi_target(rest, edition) do
      {:ok, target, after_target} ->
        # Use edition-specific name validation
        if FnXML.Char.valid_name?(target, edition: edition) do
          # Skip to end of PI
          case skip_to_pi_end(after_target) do
            {:ok, remaining} -> {:ok, remaining}
            :error -> {:error, "Unterminated PI in DTD internal subset"}
          end
        else
          {:error,
           "Invalid PI target '#{target}' in DTD - contains invalid name characters for Edition #{edition}"}
        end

      {:error, :empty} ->
        {:error, "Empty PI target in DTD internal subset"}

      {:error, :invalid_start} ->
        {:error, "PI target must start with a valid name character"}

      {:error, {:invalid_name_char, char}} ->
        {:error, "Invalid character '#{char}' in PI target name"}
    end
  end

  # Extract PI target name (characters before whitespace or ?>)
  # Uses edition-specific character validation
  defp extract_pi_target(binary, edition), do: extract_pi_target_impl(binary, <<>>, edition)

  defp extract_pi_target_impl(<<"?>", rest::binary>>, acc, _edition) when byte_size(acc) > 0 do
    {:ok, acc, <<"?>", rest::binary>>}
  end

  defp extract_pi_target_impl(<<"?>", _rest::binary>>, <<>>, _edition) do
    {:error, :empty}
  end

  defp extract_pi_target_impl(<<c, rest::binary>>, acc, _edition)
       when c in [?\s, ?\t, ?\r, ?\n] and byte_size(acc) > 0 do
    {:ok, acc, <<c, rest::binary>>}
  end

  defp extract_pi_target_impl(<<c::utf8, rest::binary>>, <<>>, edition) do
    if FnXML.Char.name_start_char?(c, edition: edition) do
      extract_pi_target_impl(rest, <<c::utf8>>, edition)
    else
      {:error, :invalid_start}
    end
  end

  defp extract_pi_target_impl(<<c::utf8, rest::binary>>, acc, edition) do
    cond do
      FnXML.Char.name_char?(c, edition: edition) ->
        extract_pi_target_impl(rest, <<acc::binary, c::utf8>>, edition)

      # If the next char is not a valid name char and not whitespace,
      # the PI target is malformed (e.g., "_)" where ) is invalid)
      c not in [?\s, ?\t, ?\r, ?\n] ->
        {:error, {:invalid_name_char, <<c::utf8>>}}

      true ->
        {:ok, acc, <<c::utf8, rest::binary>>}
    end
  end

  defp extract_pi_target_impl(<<>>, _acc, _edition), do: {:error, :empty}

  # Skip to end of PI (?>)
  defp skip_to_pi_end(<<"?>", rest::binary>>), do: {:ok, rest}
  defp skip_to_pi_end(<<_, rest::binary>>), do: skip_to_pi_end(rest)
  defp skip_to_pi_end(<<>>), do: :error

  # Extract text declaration content (between <?xml and ?>)
  defp extract_text_decl_content(binary), do: extract_text_decl_content(binary, <<>>)
  defp extract_text_decl_content(<<"?>", rest::binary>>, acc), do: {:ok, acc, rest}

  defp extract_text_decl_content(<<c, rest::binary>>, acc),
    do: extract_text_decl_content(rest, <<acc::binary, c>>)

  defp extract_text_decl_content(<<>>, _acc), do: :error
end
