defmodule FnXML.DTD do
  @moduledoc """
  Document Type Definition (DTD) processing from XML streams.

  This module provides functions to extract and parse DTD declarations
  from XML parser event streams, supporting both internal and external subsets.

  ## Specifications

  - W3C XML 1.0 DTD: https://www.w3.org/TR/xml/#dt-doctype
  - W3C DTD Declarations: https://www.w3.org/TR/xml/#sec-prolog-dtd

  ## Overview

  A Document Type Definition defines the legal building blocks of an XML document.
  It declares:
  - **Elements** - What elements can appear and their content models
  - **Attributes** - What attributes each element can have
  - **Entities** - Reusable content substitutions
  - **Notations** - External non-XML content references

  ## Use Cases

  ### Extract DTD from XML

      xml = \"\"\"
      <!DOCTYPE note [
        <!ELEMENT note (#PCDATA)>
        <!ATTLIST note date CDATA #REQUIRED>
      ]>
      <note date="2024-01-01">Hello</note>
      \"\"\"

      {:ok, model} = FnXML.Parser.parse(xml) |> FnXML.DTD.from_stream()
      model.elements["note"]   # => :pcdata
      model.attributes["note"] # => [{"date", :cdata, :required, nil}]

  ### Entity Resolution

      # Parse XML with entity definitions
      {:ok, model} = FnXML.Parser.parse(xml_with_dtd) |> FnXML.DTD.from_stream()

      # Resolve entity references using the model
      FnXML.Parser.parse(xml)
      |> FnXML.DTD.EntityResolver.resolve(model)
      |> Enum.to_list()

  ### External DTD Loading

      # Provide a resolver function for external DTDs
      resolver = fn system_id, _public_id ->
        {:ok, File.read!(system_id)}
      end

      FnXML.DTD.parse_doctype("DOCTYPE root SYSTEM \\"schema.dtd\\"",
        external_resolver: resolver)

  ## DTD Event Format

  The XML parser emits DTD events in the format:

      {:dtd, content, loc}

  Where `content` is the raw DOCTYPE declaration without the `<!` prefix
  and `>` suffix, e.g.:

      "DOCTYPE root [\\n  <!ELEMENT root EMPTY>\\n]"

  ## DTD Model Structure

  The `FnXML.DTD.Model` struct contains:
  - `root_element` - Name of the document root element
  - `elements` - Map of element name to content model
  - `attributes` - Map of element name to attribute definitions
  - `entities` - Map of general entity name to value
  - `param_entities` - Map of parameter entity name to value
  - `notations` - Map of notation name to external ID
  """

  alias FnXML.DTD.{Model, Parser}

  @doc """
  Extract and parse DTD from an XML event stream.

  Finds the first `:dtd` event in the stream, parses it, and returns
  the resulting `FnXML.DTD.Model`.

  ## Options

  - `:external_resolver` - Function to fetch external DTD content
  - `:edition` - XML 1.0 edition for name validation (4 or 5, default: 5)

  ## Examples

      iex> xml = \"""
      ...> <!DOCTYPE note [
      ...>   <!ELEMENT note (#PCDATA)>
      ...> ]>
      ...> <note>Hello</note>
      ...> \"""
      iex> {:ok, model} = FnXML.Parser.parse(xml) |> FnXML.DTD.decode()
      iex> model.elements["note"]
      :pcdata

  """
  @spec decode(Enumerable.t(), keyword()) ::
          {:ok, Model.t()} | {:error, term()}
  def decode(stream, opts \\ []) do
    stream
    |> Enum.find(fn
      {:dtd, _, _, _, _} -> true
      {:dtd, _, _} -> true
      _ -> false
    end)
    |> case do
      # 5-tuple from parser
      {:dtd, content, _line, _ls, _pos} ->
        parse_doctype(content, opts)

      # 3-tuple normalized
      {:dtd, content, _loc} ->
        parse_doctype(content, opts)

      nil ->
        {:error, :no_dtd}
    end
  end

  @doc deprecated: "Use decode/2 instead"
  def from_stream(stream, opts \\ []) do
    decode(stream, opts)
  end

  @doc """
  Parse a DOCTYPE declaration string.

  The string should be in the format emitted by the parser (without `<!` and `>`):

      "DOCTYPE root [...]"
      "DOCTYPE root SYSTEM \\"file.dtd\\""
      "DOCTYPE root PUBLIC \\"-//...//\\" \\"file.dtd\\" [...]"

  ## Options

  - `:external_resolver` - Function to fetch external DTD content
  - `:edition` - XML 1.0 edition for name validation (4 or 5, default: 5)

  ## Examples

      iex> FnXML.DTD.parse_doctype("DOCTYPE note [<!ELEMENT note (#PCDATA)>]")
      {:ok, %FnXML.DTD.Model{root_element: "note", elements: %{"note" => :pcdata}}}

  """
  @spec parse_doctype(String.t(), keyword()) :: {:ok, Model.t()} | {:error, String.t()}
  def parse_doctype(content, opts \\ []) do
    case parse_doctype_parts(content) do
      {:ok, root_name, external_id, internal_subset} ->
        model = Model.new() |> Model.set_root_element(root_name)

        # Parse external DTD if resolver provided
        model =
          case {external_id, Keyword.get(opts, :external_resolver)} do
            {nil, _} ->
              model

            {_, nil} ->
              model

            {{system_id, public_id}, resolver} ->
              case resolver.(system_id, public_id) do
                {:ok, external_content} ->
                  case Parser.parse(external_content, opts) do
                    {:ok, external_model} -> merge_models(model, external_model)
                    {:error, _} -> model
                  end

                {:error, _} ->
                  model
              end
          end

        # Parse internal subset (takes precedence over external)
        case internal_subset do
          nil ->
            {:ok, model}

          subset ->
            case Parser.parse(subset, opts) do
              {:ok, subset_model} -> {:ok, merge_models(model, subset_model)}
              {:error, _} = err -> err
            end
        end

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Check for circular entity references in a DTD model.

  Returns `{:ok, model}` if no cycles found, or `{:error, message}` if
  circular references are detected.

  ## Examples

      iex> model = %FnXML.DTD.Model{entities: %{"e1" => "&e2;", "e2" => "&e1;"}}
      iex> FnXML.DTD.check_circular_entities(model)
      {:error, "Circular entity reference: e1 -> e2 -> e1"}

  """
  @spec check_circular_entities(Model.t()) :: {:ok, Model.t()} | {:error, String.t()}
  def check_circular_entities(%Model{entities: entities} = model) do
    # Build reference graph: entity name -> list of referenced entity names
    refs = build_entity_refs(entities)

    # Check each entity for cycles
    case find_cycle(refs) do
      nil -> {:ok, model}
      cycle -> {:error, "Circular entity reference: #{Enum.join(cycle, " -> ")}"}
    end
  end

  # Build a map of entity name -> list of entity names it references
  defp build_entity_refs(entities) do
    entity_pattern = ~r/&([a-zA-Z_][a-zA-Z0-9._-]*);/

    entities
    |> Enum.map(fn {name, value} ->
      # Extract the string value from various entity storage formats
      str_value =
        case value do
          {:internal, v} when is_binary(v) -> v
          v when is_binary(v) -> v
          _ -> nil
        end

      refs =
        case str_value do
          nil ->
            []

          v ->
            Regex.scan(entity_pattern, v)
            |> Enum.map(fn [_, ref_name] -> ref_name end)
        end

      {name, refs}
    end)
    |> Map.new()
  end

  # Find a cycle in the entity reference graph using DFS
  defp find_cycle(refs) do
    entity_names = Map.keys(refs)

    Enum.find_value(entity_names, fn start ->
      find_cycle_from(start, refs, [start], MapSet.new([start]))
    end)
  end

  defp find_cycle_from(current, refs, path, visited) do
    referenced = Map.get(refs, current, [])

    Enum.find_value(referenced, fn ref ->
      cond do
        # Found a cycle back to an entity in our path
        ref in path ->
          cycle_start = Enum.find_index(path, &(&1 == ref))
          Enum.slice(path, cycle_start..-1//1) ++ [ref]

        # Already visited in another branch (not a cycle through our path)
        MapSet.member?(visited, ref) ->
          nil

        # Continue DFS
        true ->
          find_cycle_from(ref, refs, path ++ [ref], MapSet.put(visited, ref))
      end
    end)
  end

  @doc """
  Check for undefined entity references in a DTD model.

  Validates that all entity references in entity values point to either:
  - Predefined XML entities (amp, lt, gt, quot, apos)
  - Entities defined in the same DTD model

  Returns `{:ok, model}` if all references are valid, or `{:error, message}`
  if undefined entity references are found.
  """
  @predefined_entities MapSet.new(["amp", "lt", "gt", "quot", "apos"])

  @spec check_undefined_entities(Model.t()) :: {:ok, Model.t()} | {:error, String.t()}
  def check_undefined_entities(%Model{entities: entities, attributes: attributes} = model) do
    defined = entities |> Map.keys() |> MapSet.new()
    all_valid = MapSet.union(defined, @predefined_entities)

    # Check each entity value for undefined references
    undefined_in_entity =
      entities
      |> Enum.find_value(fn {entity_name, value} ->
        str_value =
          case value do
            {:internal, v} when is_binary(v) -> v
            v when is_binary(v) -> v
            _ -> nil
          end

        case str_value do
          nil ->
            nil

          v ->
            # Remove CDATA sections before checking - entity refs inside CDATA are literal text
            v_without_cdata = Regex.replace(~r/<!\[CDATA\[.*?\]\]>/s, v, "")

            # Find entity references that are not defined
            refs =
              Regex.scan(~r/&([a-zA-Z_][a-zA-Z0-9._-]*);/, v_without_cdata)
              |> Enum.map(fn [_, ref_name] -> ref_name end)

            bad_ref = Enum.find(refs, fn ref -> not MapSet.member?(all_valid, ref) end)
            if bad_ref, do: {:entity, entity_name, bad_ref}, else: nil
        end
      end)

    # Check ATTLIST default values for undefined entity references
    undefined_in_attlist =
      if undefined_in_entity == nil do
        attributes
        |> Enum.find_value(fn {_elem_name, attr_defs} ->
          Enum.find_value(attr_defs, fn attr_def ->
            default_value =
              case attr_def do
                %{default: {:default, v}} -> v
                %{default: {:value, v}} -> v
                %{default: {:fixed, v}} -> v
                {_name, _type, {:default, v}} -> v
                {_name, _type, {:value, v}} -> v
                {_name, _type, {:fixed, v}} -> v
                _ -> nil
              end

            case default_value do
              nil ->
                nil

              v ->
                refs =
                  Regex.scan(~r/&([a-zA-Z_][a-zA-Z0-9._-]*);/, v)
                  |> Enum.map(fn [_, ref_name] -> ref_name end)

                bad_ref = Enum.find(refs, fn ref -> not MapSet.member?(all_valid, ref) end)
                if bad_ref, do: {:attlist, bad_ref}, else: nil
            end
          end)
        end)
      else
        nil
      end

    case {undefined_in_entity, undefined_in_attlist} do
      {nil, nil} ->
        {:ok, model}

      {{:entity, entity_name, bad_ref}, _} ->
        {:error, "Entity '#{entity_name}' references undefined entity '&#{bad_ref};'"}

      {_, {:attlist, bad_ref}} ->
        {:error, "ATTLIST default value references undefined entity '&#{bad_ref};'"}
    end
  end

  @doc """
  Parse DOCTYPE parts: root name, external identifier, and internal subset.

  Returns `{:ok, root_name, external_id, internal_subset}` where:
  - `root_name` is the document element name
  - `external_id` is `nil` or `{system_id, public_id}`
  - `internal_subset` is `nil` or the string content between `[` and `]`
  """
  @spec parse_doctype_parts(String.t()) ::
          {:ok, String.t(), {String.t(), String.t() | nil} | nil, String.t() | nil}
          | {:error, String.t()}
  def parse_doctype_parts(content) do
    content = String.trim(content)

    # Remove "DOCTYPE " prefix
    case content do
      <<"DOCTYPE", rest::binary>> ->
        parse_after_doctype(String.trim(rest))

      _ ->
        {:error, "Expected DOCTYPE declaration"}
    end
  end

  # Parse after "DOCTYPE ": root_name [external_id] [internal_subset]
  defp parse_after_doctype(rest) do
    # Extract root element name
    case Regex.run(~r/^(\S+)(.*)$/s, rest) do
      [_, root_name, remainder] ->
        parse_external_and_subset(String.trim(remainder), root_name)

      nil ->
        {:error, "Expected root element name in DOCTYPE"}
    end
  end

  # Parse external identifier and/or internal subset
  defp parse_external_and_subset("", root_name) do
    {:ok, root_name, nil, nil}
  end

  defp parse_external_and_subset(<<"[", rest::binary>>, root_name) do
    # Internal subset only
    case extract_internal_subset(rest) do
      {:ok, subset, remainder} ->
        # Validate nothing significant after ]
        case validate_after_internal_subset(remainder) do
          :ok -> {:ok, root_name, nil, subset}
          {:error, _} = err -> err
        end

      {:error, _} = err ->
        err
    end
  end

  defp parse_external_and_subset(<<"SYSTEM", rest::binary>>, root_name) do
    # Must have whitespace after SYSTEM keyword
    if not starts_with_whitespace?(rest) do
      {:error, "Missing whitespace after SYSTEM keyword"}
    else
      rest = String.trim(rest)

      case extract_quoted_string(rest) do
        {:ok, system_id, remainder} ->
          parse_optional_subset(String.trim(remainder), root_name, {system_id, nil})

        {:error, _} = err ->
          err
      end
    end
  end

  defp parse_external_and_subset(<<"PUBLIC", rest::binary>>, root_name) do
    # Must have whitespace after PUBLIC keyword
    if not starts_with_whitespace?(rest) do
      {:error, "Missing whitespace after PUBLIC keyword"}
    else
      rest = String.trim(rest)

      case extract_quoted_string(rest) do
        {:ok, public_id, remainder} ->
          # Validate PUBLIC ID characters per XML spec
          case validate_public_id(public_id) do
            :ok ->
              # Must have whitespace between public ID and system ID
              if not starts_with_whitespace?(remainder) do
                {:error, "Missing whitespace between public and system identifiers"}
              else
                remainder = String.trim(remainder)

                case extract_quoted_string(remainder) do
                  {:ok, system_id, final_remainder} ->
                    parse_optional_subset(
                      String.trim(final_remainder),
                      root_name,
                      {system_id, public_id}
                    )

                  {:error, _} = err ->
                    err
                end
              end

            {:error, _} = err ->
              err
          end

        {:error, _} = err ->
          err
      end
    end
  end

  defp parse_external_and_subset(_, _root_name) do
    {:error, "Invalid DOCTYPE: expected SYSTEM, PUBLIC, or ["}
  end

  defp starts_with_whitespace?(<<c, _::binary>>) when c in [?\s, ?\t, ?\n, ?\r], do: true
  defp starts_with_whitespace?(_), do: false

  # Parse optional internal subset after external identifier
  defp parse_optional_subset("", root_name, external_id) do
    {:ok, root_name, external_id, nil}
  end

  defp parse_optional_subset(<<"[", rest::binary>>, root_name, external_id) do
    case extract_internal_subset(rest) do
      {:ok, subset, remainder} ->
        case validate_after_internal_subset(remainder) do
          :ok -> {:ok, root_name, external_id, subset}
          {:error, _} = err -> err
        end

      {:error, _} = err ->
        err
    end
  end

  defp parse_optional_subset(_, _root_name, _external_id) do
    {:error, "Invalid DOCTYPE: expected [ or end"}
  end

  # Extract content between [ and ]
  defp extract_internal_subset(content) do
    # Find matching ] - need to handle nested < > but not nested [ ]
    case find_closing_bracket(content, 0, 0) do
      {:ok, subset_end} ->
        subset = String.slice(content, 0, subset_end) |> String.trim()
        # Return remainder after ]
        remainder = String.slice(content, subset_end + 1, byte_size(content)) |> String.trim()
        {:ok, subset, remainder}

      :error ->
        {:error, "Unterminated internal subset"}
    end
  end

  # Validate nothing significant appears after the internal subset's closing ]
  defp validate_after_internal_subset(""), do: :ok

  defp validate_after_internal_subset(remainder) do
    # Only whitespace is allowed after ] and before closing >
    # PE references or other content is not allowed
    if String.match?(remainder, ~r/^[\s]*$/) do
      :ok
    else
      {:error, "Invalid content after internal subset: #{String.slice(remainder, 0, 30)}"}
    end
  end

  # Find the closing ] accounting for nested < > in declarations and quoted strings
  defp find_closing_bracket(content, pos, depth) do
    find_closing_bracket(content, pos, depth, nil)
  end

  # Found closing ] at depth 0, not in quotes
  defp find_closing_bracket(<<"]", _::binary>>, pos, 0, nil), do: {:ok, pos}

  # ] while in quotes - just skip it
  defp find_closing_bracket(<<"]", rest::binary>>, pos, depth, quote) when quote != nil,
    do: find_closing_bracket(rest, pos + 1, depth, quote)

  # ] not in quotes, depth > 0
  defp find_closing_bracket(<<"]", rest::binary>>, pos, depth, nil),
    do: find_closing_bracket(rest, pos + 1, depth - 1, nil)

  # Enter/exit double quote
  defp find_closing_bracket(<<"\"", rest::binary>>, pos, depth, nil),
    do: find_closing_bracket(rest, pos + 1, depth, ?")

  defp find_closing_bracket(<<"\"", rest::binary>>, pos, depth, ?"),
    do: find_closing_bracket(rest, pos + 1, depth, nil)

  # Enter/exit single quote
  defp find_closing_bracket(<<"'", rest::binary>>, pos, depth, nil),
    do: find_closing_bracket(rest, pos + 1, depth, ?')

  defp find_closing_bracket(<<"'", rest::binary>>, pos, depth, ?'),
    do: find_closing_bracket(rest, pos + 1, depth, nil)

  # Comment inside DTD - skip entire comment without tracking quotes
  defp find_closing_bracket(<<"<!--", rest::binary>>, pos, depth, nil) do
    case skip_comment(rest, pos + 4) do
      {:ok, new_pos, remaining} ->
        find_closing_bracket(remaining, new_pos, depth, nil)

      :error ->
        :error
    end
  end

  # < and > only count when not in quotes
  defp find_closing_bracket(<<"<", rest::binary>>, pos, depth, nil),
    do: find_closing_bracket(rest, pos + 1, depth + 1, nil)

  defp find_closing_bracket(<<">", rest::binary>>, pos, depth, nil),
    do: find_closing_bracket(rest, pos + 1, max(0, depth - 1), nil)

  # Any char while in quotes - just skip
  defp find_closing_bracket(<<_, rest::binary>>, pos, depth, quote) when quote != nil,
    do: find_closing_bracket(rest, pos + 1, depth, quote)

  # Any other char not in quotes
  defp find_closing_bracket(<<_, rest::binary>>, pos, depth, nil),
    do: find_closing_bracket(rest, pos + 1, depth, nil)

  defp find_closing_bracket(<<>>, _pos, _depth, _quote), do: :error

  # Skip comment content until -->
  defp skip_comment(<<"-->", rest::binary>>, pos), do: {:ok, pos + 3, rest}
  defp skip_comment(<<_, rest::binary>>, pos), do: skip_comment(rest, pos + 1)
  defp skip_comment(<<>>, _pos), do: :error

  # Extract a quoted string (single or double quotes)
  defp extract_quoted_string(<<?", rest::binary>>) do
    case :binary.match(rest, "\"") do
      {pos, 1} ->
        value = binary_part(rest, 0, pos)
        remainder = binary_part(rest, pos + 1, byte_size(rest) - pos - 1)
        {:ok, value, remainder}

      :nomatch ->
        {:error, "Unterminated quoted string"}
    end
  end

  defp extract_quoted_string(<<?\', rest::binary>>) do
    case :binary.match(rest, "'") do
      {pos, 1} ->
        value = binary_part(rest, 0, pos)
        remainder = binary_part(rest, pos + 1, byte_size(rest) - pos - 1)
        {:ok, value, remainder}

      :nomatch ->
        {:error, "Unterminated quoted string"}
    end
  end

  defp extract_quoted_string(_) do
    {:error, "Expected quoted string"}
  end

  # Validate PUBLIC identifier characters per XML spec
  # PubidChar ::= #x20 | #xD | #xA | [a-zA-Z0-9] | [-'()+,./:=?;!*#@$_%]
  defp validate_public_id(public_id) do
    # Check each character is a valid PubidChar
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

  # Valid PubidChar characters
  defp valid_pubid_char?(<<c>>) when c in [0x20, 0x0D, 0x0A], do: true
  defp valid_pubid_char?(<<c>>) when c in ?a..?z or c in ?A..?Z or c in ?0..?9, do: true
  defp valid_pubid_char?(<<c>>) when c in ~c[-'()+,./:=?;!*#@$_%], do: true
  defp valid_pubid_char?(_), do: false

  # Merge two models, second takes precedence
  defp merge_models(base, override) do
    %Model{
      elements: Map.merge(base.elements, override.elements),
      attributes: Map.merge(base.attributes, override.attributes),
      entities: Map.merge(base.entities, override.entities),
      param_entities: Map.merge(base.param_entities, override.param_entities),
      notations: Map.merge(base.notations, override.notations),
      root_element: override.root_element || base.root_element
    }
  end

  # ============================================================================
  # DTD Model Parsing (Emits State Event)
  # ============================================================================

  @doc """
  Parse DTD and emit model as a stream event.

  This function watches for `{:dtd, ...}` events, parses the DTD content,
  and emits a `{:dtd_model, %FnXML.DTD.Model{}}` event BEFORE the original
  `{:dtd, ...}` event. Downstream processors can use this model for
  validation and resolution without re-parsing.

  ## Idempotent Operation

  This function is idempotent - if a `{:dtd_model, ...}` event is already
  present in the stream (from an earlier call to `parse_model/2`), it will
  be passed through unchanged without re-parsing. This allows safe composition:

      FnXML.Parser.parse(xml)
      |> FnXML.Event.Validate.compliant()    # Calls parse_model internally
      |> FnXML.Event.resolve()                # Also calls parse_model - no re-parse
      |> Enum.to_list()

  ## Event Order

  When a DTD is found:
  1. `{:dtd_model, %Model{}}` - Parsed DTD model (emitted first)
  2. `{:dtd, content, ...}` - Original DTD event (passed through)

  ## Usage

      FnXML.Parser.parse(xml)
      |> FnXML.DTD.parse_model()              # Emits {:dtd_model, model}
      |> FnXML.Event.Validate.compliant()    # Uses model from stream
      |> FnXML.Event.resolve()                # Uses model from stream
      |> Enum.to_list()

  ## Pipeline Validation

  Downstream processors that require the DTD model should check:
  - If they see `{:dtd_model, model}`, store and use it
  - If they see `{:dtd, ...}` without prior `{:dtd_model, ...}`, emit error:
    `{:error, :no_dtd_model, "DTD parser missing from pipeline"}`

  ## Options

  - `:on_error` - How to handle DTD parse errors:
    - `:emit` (default) - Emit `{:error, ...}` event and continue
    - `:raise` - Raise exception
    - `:skip` - Skip model emission on error, pass DTD through

  ## Examples

      # Basic usage
      FnXML.Parser.parse(xml)
      |> FnXML.DTD.parse_model()
      |> Enum.to_list()
      # => [{:dtd_model, %Model{...}}, {:dtd, "...", ...}, ...]

      # With error handling
      FnXML.Parser.parse(xml)
      |> FnXML.DTD.parse_model(on_error: :emit)
      |> Enum.to_list()
  """
  @spec parse_model(Enumerable.t(), keyword()) :: Enumerable.t()
  def parse_model(stream, opts \\ []) do
    on_error = Keyword.get(opts, :on_error, :emit)

    # State: :waiting | :has_model
    # Idempotent: if we see {:dtd_model, ...} already in stream, pass through unchanged
    Stream.transform(stream, :waiting, fn
      # Already have model in stream - pass through everything
      event, :has_model ->
        {[event], :has_model}

      # Existing model found - mark as having model and pass through
      {:dtd_model, _} = event, :waiting ->
        {[event], :has_model}

      # DTD found, emit model before it
      {:dtd, content, line, ls, pos} = event, :waiting ->
        {emit_dtd_model(content, event, {line, ls, pos}, on_error), :has_model}

      {:dtd, content, loc} = event, :waiting ->
        {emit_dtd_model(content, event, loc, on_error), :has_model}

      {:dtd, content} = event, :waiting ->
        {emit_dtd_model(content, event, nil, on_error), :has_model}

      # Other events while waiting - pass through
      event, :waiting ->
        {[event], :waiting}
    end)
  end

  defp emit_dtd_model(content, dtd_event, loc, on_error) do
    case parse_doctype(content) do
      {:ok, model} ->
        [{:dtd_model, model}, dtd_event]

      {:error, reason} ->
        handle_dtd_parse_error(reason, dtd_event, loc, on_error)
    end
  end

  defp handle_dtd_parse_error(_reason, dtd_event, _loc, :skip) do
    [dtd_event]
  end

  defp handle_dtd_parse_error(reason, _dtd_event, loc, :raise) do
    raise "DTD parse error: #{inspect(reason)} at #{inspect(loc)}"
  end

  defp handle_dtd_parse_error(reason, dtd_event, loc, :emit) do
    error_event = {:error, :dtd_parse_error, "Failed to parse DTD: #{inspect(reason)}", loc}
    [error_event, dtd_event]
  end

  # ============================================================================
  # Pipeline-Friendly DTD Resolution
  # ============================================================================

  @doc """
  Resolve entities in a streaming pipeline.

  This function has two modes:

  1. **Single-pass mode** (recommended): Extracts DTD from stream and resolves entities in one pass
  2. **Two-pass mode**: Uses an explicit DTD model for entity resolution

  ## Single-Pass Mode (Stream Only)

  Buffers events until DTD is seen, extracts entity definitions, then flushes
  buffer with resolution applied. This is the recommended approach:

      FnXML.Parser.parse(xml)
      |> FnXML.DTD.resolve()
      |> FnXML.Event.Validate.well_formed()
      |> Enum.to_list()

  ## Two-Pass Mode (Stream with Model)

  Uses an explicitly extracted DTD model for entity resolution:

      {:ok, model} = FnXML.Parser.parse(xml) |> FnXML.DTD.decode()

      FnXML.Parser.parse(xml)
      |> FnXML.DTD.resolve(model)
      |> Enum.to_list()

  ## Options (Single-Pass Mode)

  - `:on_unknown` - How to handle unknown entities: `:raise` | `:emit` | `:keep` | `:remove` (default: `:keep`)
  - `:error_on_no_dtd` - Emit error event if no DTD found (default: `false`)
  - `:edition` - XML edition for re-parsing entity content with markup (default: 5)
  - `:max_expansion_depth` - Maximum entity nesting (default: 10)
  - `:max_total_expansion` - Maximum expanded size (default: 1_000_000)
  - `:external_resolver` - Function `(system_id, public_id) -> {:ok, content} | {:error, reason}`
    to fetch external DTD content (not external entity content)

  ## Options (Two-Pass Mode)

  - `:max_expansion_depth` - Maximum nesting depth (default: 10)
  - `:max_total_expansion` - Maximum expanded size (default: 1_000_000)
  - `:external_resolver` - Function to resolve external entities
  - `:on_unknown` - `:raise` | `:emit` | `:keep` | `:remove` (default: :raise)

  ## How Single-Pass Works

  Per XML spec, DTD must appear after the prolog but before the root element.
  This function buffers events until either a DTD or root element is seen:

  1. If DTD found: extract internal entities, flush buffer with resolution, continue resolving
  2. If root element found first: no DTD, flush buffer as-is (unless `:error_on_no_dtd` is true)

  When `:error_on_no_dtd` is false (default), the stream passes through unchanged if
  no DTD is present. Predefined XML entities (`&amp;`, `&lt;`, `&gt;`, `&apos;`, `&quot;`)
  and numeric character references are still resolved by the parser itself.

  The buffer only holds pre-root events (prolog, comments, PIs, whitespace),
  which is typically just a few events.
  """
  @spec resolve(Enumerable.t(), keyword() | Model.t()) :: Enumerable.t()
  @spec resolve(Enumerable.t(), Model.t(), keyword()) :: Enumerable.t()
  def resolve(stream, opts_or_model \\ [])

  # Single-pass mode: resolve(stream, opts)
  def resolve(stream, opts) when is_list(opts) do
    on_unknown = Keyword.get(opts, :on_unknown, :keep)
    edition = Keyword.get(opts, :edition, 5)
    error_on_no_dtd = Keyword.get(opts, :error_on_no_dtd, false)

    # Initial state: {buffer, model}
    # buffer = list of events before DTD (reversed for efficiency)
    # model = nil | {:ok, entities_map} | :no_dtd | {:error, reason}
    Stream.transform(stream, {[], nil}, fn event, {buffer, model} ->
      resolve_dtd_event(event, buffer, model, on_unknown, edition, error_on_no_dtd, opts)
    end)
  end

  # Two-pass mode: resolve(stream, model)
  def resolve(stream, %Model{} = model) do
    resolve(stream, model, [])
  end

  # Two-pass mode: resolve(stream, model, opts)
  def resolve(stream, %Model{} = model, opts) when is_list(opts) do
    alias FnXML.DTD.EntityResolver

    EntityResolver.resolve(stream, model, opts)
  end

  # State: waiting for DTD or root element
  defp resolve_dtd_event(event, buffer, nil, on_unknown, edition, error_on_no_dtd, opts) do
    case event do
      # Found DTD - extract entities and flush buffer with resolution
      {:dtd, content, _, _, _} = dtd_event ->
        handle_dtd_found(dtd_event, content, buffer, on_unknown, edition, opts)

      {:dtd, content, _} = dtd_event ->
        handle_dtd_found(dtd_event, content, buffer, on_unknown, edition, opts)

      # Found start_element before DTD - no DTD in document
      # Flush buffer and resolve this event (for predefined entities in attributes)
      {:start_element, _, _, _, _, _} = elem_event ->
        handle_no_dtd(elem_event, buffer, on_unknown, edition, error_on_no_dtd)

      {:start_element, _, _, _} = elem_event ->
        handle_no_dtd(elem_event, buffer, on_unknown, edition, error_on_no_dtd)

      # Error events - flush buffer and pass through error, set state to :no_dtd
      {:error, _, _, _, _, _} = error_event ->
        flushed = Enum.reverse(buffer)
        {flushed ++ [error_event], {[], :no_dtd}}

      {:error, _, _} = error_event ->
        flushed = Enum.reverse(buffer)
        {flushed ++ [error_event], {[], :no_dtd}}

      {:error, _} = error_event ->
        flushed = Enum.reverse(buffer)
        {flushed ++ [error_event], {[], :no_dtd}}

      # End document without root element (malformed) - flush buffer
      {:end_document, _} = end_event ->
        flushed = Enum.reverse(buffer)
        {flushed ++ [end_event], {[], :no_dtd}}

      # Other pre-root events (prolog, comments, PIs, whitespace) - buffer them
      _ ->
        {[], {[event | buffer], nil}}
    end
  end

  # State: have DTD - resolve entities in events
  defp resolve_dtd_event(event, [], {:ok, entities}, on_unknown, edition, _error_on_no_dtd, _opts) do
    {resolve_event(event, entities, on_unknown, edition), {[], {:ok, entities}}}
  end

  # State: no DTD in document - still resolve predefined entities
  defp resolve_dtd_event(event, [], :no_dtd, on_unknown, edition, _error_on_no_dtd, _opts) do
    # No DTD but still resolve predefined entities (&amp;, &lt;, etc.)
    {resolve_event(event, %{}, on_unknown, edition), {[], :no_dtd}}
  end

  # State: DTD had error - still resolve predefined entities
  defp resolve_dtd_event(
         event,
         [],
         {:error, _reason},
         on_unknown,
         edition,
         _error_on_no_dtd,
         _opts
       ) do
    # Even with a DTD error, we should still resolve predefined entities
    {resolve_event(event, %{}, on_unknown, edition), {[], {:error, :passthrough}}}
  end

  # Handle no DTD case - emit error if requested, otherwise be passive
  defp handle_no_dtd(elem_event, buffer, on_unknown, edition, error_on_no_dtd) do
    flushed = Enum.reverse(buffer)

    if error_on_no_dtd do
      # Emit error event when DTD is required but not found
      error_event = {:error, :no_dtd, "No DTD found in document", nil, nil, nil}
      resolved_elem = resolve_event(elem_event, %{}, on_unknown, edition)
      {flushed ++ [error_event] ++ resolved_elem, {[], :no_dtd}}
    else
      # Passive mode - still resolve predefined entities (&amp;, &lt;, etc.)
      # even without a DTD by passing empty entities map
      resolved_elem = resolve_event(elem_event, %{}, on_unknown, edition)
      {flushed ++ resolved_elem, {[], :no_dtd}}
    end
  end

  defp handle_dtd_found(dtd_event, content, buffer, on_unknown, edition, opts) do
    case extract_entities_from_content(content, opts) do
      {:ok, entities} ->
        # Flush buffer with resolution applied
        resolved_buffer =
          buffer
          |> Enum.reverse()
          |> Enum.flat_map(&resolve_event(&1, entities, on_unknown, edition))

        # Also resolve entities in the DTD event itself (though rare)
        resolved_dtd = resolve_event(dtd_event, entities, on_unknown, edition)
        {resolved_buffer ++ resolved_dtd, {[], {:ok, entities}}}

      {:error, reason} ->
        # DTD parse error - flush buffer as-is, emit error event
        flushed = Enum.reverse(buffer)
        error_event = {:error, :dtd_parse, "DTD parse error: #{inspect(reason)}", nil, nil, nil}
        {flushed ++ [error_event, dtd_event], {[], {:error, reason}}}
    end
  end

  defp extract_entities_from_content(content, opts) do
    # Use external_resolver for fetching external DTD content (parse_doctype)
    # but NOT for resolving external entity references (only internal entities)
    with {:ok, model} <- parse_doctype(content, opts) do
      # Don't pass external_resolver here - we only want internal entities
      # External entities will be kept as-is with on_unknown: :keep
      entity_opts = Keyword.delete(opts, :external_resolver)
      FnXML.DTD.EntityResolver.extract_and_expand_entities(model, entity_opts)
    end
  end

  # Predefined XML entities (always available)
  @predefined_entities %{
    "amp" => "&",
    "lt" => "<",
    "gt" => ">",
    "quot" => "\"",
    "apos" => "'"
  }

  # Merge predefined entities with DTD entities
  defp merge_entities(dtd_entities) do
    Map.merge(@predefined_entities, dtd_entities)
  end

  # Resolve entities in a single event
  defp resolve_event({:characters, text, line, ls, pos}, entities, on_unknown, edition) do
    # Always include predefined entities
    all_entities = merge_entities(entities)

    case FnXML.Event.Transform.Entities.resolve_text(text, all_entities, on_unknown) do
      {:ok, resolved} ->
        # Only reparse if:
        # 1. Resolved content starts with < (might be markup)
        # 2. Original text contained non-predefined entity references
        # This prevents reparsing &lt; (escaped less-than) as actual markup
        if String.starts_with?(resolved, "<") and has_non_predefined_entity_refs?(text, entities) do
          reparse_markup(resolved, edition)
        else
          [{:characters, resolved, line, ls, pos}]
        end

      {:error, error} ->
        # On error, emit both error and original
        [{:error, error}, {:characters, text, line, ls, pos}]
    end
  end

  defp resolve_event({:characters, text, loc}, entities, on_unknown, edition) do
    # Always include predefined entities
    all_entities = merge_entities(entities)

    case FnXML.Event.Transform.Entities.resolve_text(text, all_entities, on_unknown) do
      {:ok, resolved} ->
        # Only reparse if:
        # 1. Resolved content starts with < (might be markup)
        # 2. Original text contained non-predefined entity references
        # This prevents reparsing &lt; (escaped less-than) as actual markup
        if String.starts_with?(resolved, "<") and has_non_predefined_entity_refs?(text, entities) do
          reparse_markup(resolved, edition)
        else
          [{:characters, resolved, loc}]
        end

      {:error, error} ->
        [{:error, error}, {:characters, text, loc}]
    end
  end

  defp resolve_event({:start_element, tag, attrs, line, ls, pos}, entities, on_unknown, _edition) do
    {resolved_attrs, attr_errors} = resolve_attributes(attrs, entities, on_unknown)
    attr_errors ++ [{:start_element, tag, resolved_attrs, line, ls, pos}]
  end

  defp resolve_event({:start_element, tag, attrs, loc}, entities, on_unknown, _edition) do
    {resolved_attrs, attr_errors} = resolve_attributes(attrs, entities, on_unknown)
    attr_errors ++ [{:start_element, tag, resolved_attrs, loc}]
  end

  defp resolve_event(event, _entities, _on_unknown, _edition) do
    # Pass through other events unchanged (comments, PIs, end_element, etc.)
    [event]
  end

  # Check if text contains entity references that are NOT predefined entities.
  # Predefined entities (&lt; &gt; &amp; &quot; &apos;) are for escaping characters
  # and their resolved values should remain as character data, not be reparsed.
  @predefined_entity_names MapSet.new(["lt", "gt", "amp", "quot", "apos"])

  defp has_non_predefined_entity_refs?(text, dtd_entities) do
    # Find all entity references in the text
    Regex.scan(~r/&([a-zA-Z_][a-zA-Z0-9._-]*);/, text)
    |> Enum.any?(fn [_, name] ->
      # Check if this entity is defined in the DTD (not predefined)
      # and its value starts with < (contains markup)
      not MapSet.member?(@predefined_entity_names, name) and
        case Map.get(dtd_entities, name) do
          nil -> false
          value -> String.contains?(value, "<")
        end
    end)
  end

  # Returns {resolved_attrs, error_events}
  defp resolve_attributes(attrs, entities, on_unknown) do
    # Always include predefined entities
    all_entities = merge_entities(entities)

    {resolved, errors} =
      Enum.reduce(attrs, {[], []}, fn {name, value}, {acc_attrs, acc_errors} ->
        case FnXML.Event.Transform.Entities.resolve_text(value, all_entities, on_unknown) do
          {:ok, resolved} ->
            {[{name, resolved} | acc_attrs], acc_errors}

          {:error, error} ->
            # Emit error but keep original value
            {[{name, value} | acc_attrs], [{:error, error} | acc_errors]}
        end
      end)

    {Enum.reverse(resolved), Enum.reverse(errors)}
  end

  # Re-parse entity content that contains markup with edition-specific parser
  # This handles cases like <!ENTITY e "<&#x309a;></&#x309a;>"> where the entity
  # value contains XML elements that need edition-specific validation
  defp reparse_markup(content, edition) do
    # First, expand character references in the content
    expanded = expand_char_refs_in_string(content)

    # Re-parse with edition-specific parser
    parser = FnXML.Parser.generate(edition)

    events =
      [expanded]
      |> parser.stream()
      |> Enum.to_list()

    # Check for errors - if any error, return it
    case Enum.find(events, &match?({:error, _, _, _, _, _}, &1)) do
      nil -> events
      error -> [error]
    end
  end

  # Expand character references in a string (&#decimal; and &#xhex;)
  defp expand_char_refs_in_string(text) do
    text
    |> expand_hex_char_refs()
    |> expand_decimal_char_refs()
  end

  defp expand_hex_char_refs(text) do
    Regex.replace(~r/&#x([0-9a-fA-F]+);/, text, fn _, hex ->
      case Integer.parse(hex, 16) do
        {codepoint, ""} when codepoint >= 0 ->
          try do
            <<codepoint::utf8>>
          rescue
            _ -> "&#x#{hex};"
          end

        _ ->
          "&#x#{hex};"
      end
    end)
  end

  defp expand_decimal_char_refs(text) do
    Regex.replace(~r/&#([0-9]+);/, text, fn _, decimal ->
      case Integer.parse(decimal) do
        {codepoint, ""} when codepoint >= 0 ->
          try do
            <<codepoint::utf8>>
          rescue
            _ -> "&##{decimal};"
          end

        _ ->
          "&##{decimal};"
      end
    end)
  end
end
