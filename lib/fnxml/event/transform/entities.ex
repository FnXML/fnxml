defmodule FnXML.Event.Transform.Entities do
  @moduledoc """
  Resolves XML entities in text content and attribute values.

  Can be included or excluded from the processing pipeline based on needs.
  For trusted XML that never contains entities, skip for performance.

  ## Supported Entities

  - Predefined XML entities: `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`
  - Decimal character references: `&#60;`, `&#8364;`
  - Hexadecimal character references: `&#x3C;`, `&#x20AC;`
  - Custom named entities via `:entities` option

  ## Usage

      FnXML.Parser.parse(xml)
      |> FnXML.Event.Transform.Entities.resolve()
      |> Enum.to_list()

  ## Options

  - `:entities` - Map of custom entity name => replacement
  - `:on_unknown` - How to handle unknown named entities:
    - `:raise` (default) - Raise FnXML.Error
    - `:emit` - Emit error event in stream
    - `:keep` - Keep the entity reference as-is
    - `:remove` - Remove the entity reference

  ## Examples

      # Basic entity resolution
      iex> "<a>Tom &amp; Jerry</a>"
      ...> |> FnXML.Parser.parse()
      ...> |> FnXML.Event.Transform.Entities.resolve()
      ...> |> Enum.to_list()
      ...> |> Enum.find(&match?({:characters, _, _, _, _}, &1))
      ...> |> elem(1)
      "Tom & Jerry"

      # Custom entities
      iex> "<a>&copy;</a>"
      ...> |> FnXML.Parser.parse()
      ...> |> FnXML.Event.Transform.Entities.resolve(entities: %{"copy" => "©"})
      ...> |> Enum.to_list()
      ...> |> Enum.find(&match?({:characters, _, _, _, _}, &1))
      ...> |> elem(1)
      "©"
  """

  alias FnXML.Error

  @predefined %{
    "amp" => "&",
    "lt" => "<",
    "gt" => ">",
    "quot" => "\"",
    "apos" => "'"
  }

  # Regex to match entity references: &name; or &#decimal; or &#xhex;
  @entity_pattern ~r/&(#x?)?([^;]+);/

  @doc """
  Resolve entities in the stream.

  Processes text content and attribute values, replacing entity references
  with their resolved values.

  ## Options

  - `:entities` - Map of custom entity name => replacement (merged with predefined)
  - `:on_unknown` - `:raise` | `:emit` | `:keep` | `:remove` (default: :raise)
  - `:edition` - XML 1.0 edition (4 or 5) for re-parsing entity values with markup
  """
  def resolve(stream, opts \\ []) do
    entities = Map.merge(@predefined, Keyword.get(opts, :entities, %{}))
    on_unknown = Keyword.get(opts, :on_unknown, :raise)
    edition = Keyword.get(opts, :edition, 5)

    Stream.flat_map(stream, fn
      # 5-tuple format from parser
      {:characters, content, line, ls, pos} ->
        resolve_text_event_5(content, line, ls, pos, entities, on_unknown, edition)

      # 4-tuple normalized format
      {:characters, content, loc} ->
        resolve_text_event(content, loc, entities, on_unknown, edition)

      # 6-tuple format from parser
      {:start_element, tag, attrs, line, ls, pos} ->
        resolve_open_event_6(tag, attrs, line, ls, pos, entities, on_unknown)

      # 4-tuple normalized format
      {:start_element, tag, attrs, loc} ->
        resolve_open_event(tag, attrs, loc, entities, on_unknown)

      elem ->
        [elem]
    end)
  end

  # Resolve entities in text content (5-tuple format from parser)
  defp resolve_text_event_5(content, line, ls, pos, entities, on_unknown, edition) do
    # First check if any DTD-defined entities with markup are referenced
    has_markup_entities = has_entities_with_markup?(content, entities)

    case resolve_text(content, entities, on_unknown) do
      {:ok, resolved} ->
        # Only re-parse if we know a markup-containing entity was expanded
        if has_markup_entities do
          reparse_markup(resolved, edition)
        else
          [{:characters, resolved, line, ls, pos}]
        end

      {:error, error} ->
        handle_resolution_error(error, on_unknown)
    end
  end

  # Resolve entities in text content (4-tuple normalized format)
  defp resolve_text_event(content, loc, entities, on_unknown, edition) do
    has_markup_entities = has_entities_with_markup?(content, entities)

    case resolve_text(content, entities, on_unknown) do
      {:ok, resolved} ->
        if has_markup_entities do
          reparse_markup(resolved, edition)
        else
          [{:characters, resolved, loc}]
        end

      {:error, error} ->
        handle_resolution_error(error, on_unknown)
    end
  end

  # Check if any entity references in content point to entities with markup values
  # Only checks DTD-defined entities (not predefined amp, lt, gt, quot, apos)
  defp has_entities_with_markup?(content, entities) do
    # Find all named entity references (not character refs)
    Regex.scan(~r/&([a-zA-Z_:][a-zA-Z0-9._:-]*);/, content)
    |> Enum.any?(fn [_, name] ->
      # Skip predefined entities
      if name in ["amp", "lt", "gt", "quot", "apos"] do
        false
      else
        case Map.get(entities, name) do
          nil -> false
          value -> String.contains?(value, "<")
        end
      end
    end)
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

  # Resolve entities in attribute values (6-tuple format from parser)
  defp resolve_open_event_6(tag, attrs, line, ls, pos, entities, on_unknown) do
    case resolve_attrs(attrs, entities, on_unknown) do
      {:ok, resolved_attrs} ->
        [{:start_element, tag, resolved_attrs, line, ls, pos}]

      {:error, error} ->
        handle_resolution_error(error, on_unknown)
    end
  end

  # Resolve entities in attribute values (4-tuple normalized format)
  defp resolve_open_event(tag, attrs, loc, entities, on_unknown) do
    case resolve_attrs(attrs, entities, on_unknown) do
      {:ok, resolved_attrs} ->
        [{:start_element, tag, resolved_attrs, loc}]

      {:error, error} ->
        handle_resolution_error(error, on_unknown)
    end
  end

  # Handle errors based on on_unknown setting
  # Bare ampersand errors (invalid_entity with "Bare '&'") are always emitted
  defp handle_resolution_error(%Error{type: :invalid_entity, message: "Bare '&'" <> _} = error, _) do
    [{:error, error}]
  end

  defp handle_resolution_error(error, :raise), do: raise(error)
  defp handle_resolution_error(error, :emit), do: [{:error, error}]
  defp handle_resolution_error(_error, _), do: []

  @doc """
  Resolve entities in a text string.

  Returns `{:ok, resolved_string}` or `{:error, %FnXML.Error{}}`.

  ## Options (via on_unknown parameter)

  - `:raise` (default) - Raise on unknown entities or bare ampersands
  - `:emit` - Return error tuple
  - `:keep` - Keep entity reference as-is
  - `:remove` - Remove the entity reference
  """
  def resolve_text(text, entities \\ @predefined, on_unknown \\ :raise) do
    # First check for bare ampersands (& not followed by valid entity ref)
    # Bare ampersands are always an error regardless of on_unknown setting
    case validate_ampersands(text) do
      :ok ->
        try do
          resolved =
            Regex.replace(@entity_pattern, text, fn full, prefix, ref ->
              case resolve_ref(prefix, ref, entities, on_unknown) do
                {:ok, value} -> value
                {:keep, _} -> full
                {:remove, _} -> ""
                {:error, error} -> throw({:entity_error, error})
              end
            end)

          {:ok, resolved}
        catch
          {:entity_error, error} -> {:error, error}
        end

      {:error, error} ->
        # Bare ampersands are always an error - they indicate malformed XML
        {:error, error}
    end
  end

  # Validate that all & characters are part of valid entity references
  defp validate_ampersands(text) do
    case find_bare_ampersand(text, 0) do
      nil ->
        :ok

      offset ->
        {:error,
         Error.parse_error(
           :invalid_entity,
           "Bare '&' not allowed in text content; use '&amp;' instead",
           nil,
           nil,
           %{offset: offset}
         )}
    end
  end

  # Find the first bare ampersand that isn't part of a valid entity reference
  defp find_bare_ampersand(<<>>, _offset), do: nil

  defp find_bare_ampersand(<<"&", rest::binary>>, offset) do
    if valid_entity_start?(rest) do
      # Skip past this valid entity reference
      case :binary.match(rest, ";") do
        {pos, 1} ->
          find_bare_ampersand(
            binary_part(rest, pos + 1, byte_size(rest) - pos - 1),
            offset + pos + 2
          )

        :nomatch ->
          # Unterminated entity reference
          offset
      end
    else
      # Bare ampersand
      offset
    end
  end

  defp find_bare_ampersand(<<_::utf8, rest::binary>>, offset) do
    find_bare_ampersand(rest, offset + 1)
  end

  # Check if the text after & starts a valid entity reference
  # For character references, be lenient here - let resolution code validate content
  defp valid_entity_start?(<<"#x", rest::binary>>) do
    # Hex character reference attempt: just check for non-empty content ending in ;
    case :binary.match(rest, ";") do
      {pos, 1} -> pos > 0
      :nomatch -> false
    end
  end

  defp valid_entity_start?(<<"#", rest::binary>>) do
    # Decimal character reference attempt: just check for non-empty content ending in ;
    case :binary.match(rest, ";") do
      {pos, 1} -> pos > 0
      :nomatch -> false
    end
  end

  defp valid_entity_start?(<<first::utf8, _rest::binary>> = text) do
    # Named entity: must start with valid name start char
    if valid_name_start_char?(first) do
      case :binary.match(text, ";") do
        {pos, 1} ->
          name = binary_part(text, 0, pos)
          valid_xml_name?(name)

        :nomatch ->
          false
      end
    else
      false
    end
  end

  defp valid_entity_start?(_), do: false

  # XML Name validation
  defp valid_xml_name?(<<>>), do: false

  defp valid_xml_name?(<<first::utf8, rest::binary>>) do
    valid_name_start_char?(first) and valid_name_chars?(rest)
  end

  defp valid_name_start_char?(c) when c == ?: or c in ?A..?Z or c == ?_ or c in ?a..?z, do: true
  defp valid_name_start_char?(c) when c >= 0xC0 and c <= 0xD6, do: true
  defp valid_name_start_char?(c) when c >= 0xD8 and c <= 0xF6, do: true
  defp valid_name_start_char?(c) when c >= 0xF8 and c <= 0x2FF, do: true
  defp valid_name_start_char?(c) when c >= 0x370 and c <= 0x37D, do: true
  defp valid_name_start_char?(c) when c >= 0x37F and c <= 0x1FFF, do: true
  defp valid_name_start_char?(c) when c >= 0x200C and c <= 0x200D, do: true
  defp valid_name_start_char?(c) when c >= 0x2070 and c <= 0x218F, do: true
  defp valid_name_start_char?(c) when c >= 0x2C00 and c <= 0x2FEF, do: true
  defp valid_name_start_char?(c) when c >= 0x3001 and c <= 0xD7FF, do: true
  defp valid_name_start_char?(c) when c >= 0xF900 and c <= 0xFDCF, do: true
  defp valid_name_start_char?(c) when c >= 0xFDF0 and c <= 0xFFFD, do: true
  defp valid_name_start_char?(c) when c >= 0x10000 and c <= 0xEFFFF, do: true
  defp valid_name_start_char?(_), do: false

  defp valid_name_chars?(<<>>), do: true

  defp valid_name_chars?(<<c::utf8, rest::binary>>) do
    valid_name_char?(c) and valid_name_chars?(rest)
  end

  defp valid_name_char?(c) when c == ?- or c == ?. or c in ?0..?9 or c == 0xB7, do: true
  defp valid_name_char?(c) when c >= 0x0300 and c <= 0x036F, do: true
  defp valid_name_char?(c) when c >= 0x203F and c <= 0x2040, do: true
  defp valid_name_char?(c), do: valid_name_start_char?(c)

  @doc """
  Resolve entities in attribute name-value pairs.

  Returns `{:ok, resolved_attrs}` or `{:error, %FnXML.Error{}}`.
  """
  def resolve_attrs(attrs, entities \\ @predefined, on_unknown \\ :raise) do
    Enum.reduce_while(attrs, {:ok, []}, fn {name, value}, {:ok, acc} ->
      case resolve_text(value, entities, on_unknown) do
        {:ok, resolved} -> {:cont, {:ok, [{name, resolved} | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, attrs} -> {:ok, Enum.reverse(attrs)}
      error -> error
    end
  end

  # Resolve a single entity reference
  defp resolve_ref("", name, entities, on_unknown) do
    # Named entity: &name;
    case Map.get(entities, name) do
      nil -> handle_unknown(name, on_unknown)
      value -> {:ok, value}
    end
  end

  defp resolve_ref("#", decimal, _entities, _on_unknown) do
    # Decimal character reference: &#60;
    case Integer.parse(decimal) do
      {codepoint, ""} when codepoint >= 0 ->
        {:ok, <<codepoint::utf8>>}

      _ ->
        {:error,
         Error.parse_error(
           :invalid_entity,
           "Invalid decimal character reference: &##{decimal};",
           nil,
           nil,
           %{entity: "&##{decimal};"}
         )}
    end
  rescue
    ArgumentError ->
      {:error,
       Error.parse_error(
         :invalid_entity,
         "Invalid Unicode codepoint in &##{decimal};",
         nil,
         nil,
         %{entity: "&##{decimal};"}
       )}
  end

  defp resolve_ref("#x", hex, _entities, _on_unknown) do
    # Hex character reference: &#x3C;
    case Integer.parse(hex, 16) do
      {codepoint, ""} when codepoint >= 0 ->
        {:ok, <<codepoint::utf8>>}

      _ ->
        {:error,
         Error.parse_error(
           :invalid_entity,
           "Invalid hex character reference: &#x#{hex};",
           nil,
           nil,
           %{entity: "&#x#{hex};"}
         )}
    end
  rescue
    ArgumentError ->
      {:error,
       Error.parse_error(
         :invalid_entity,
         "Invalid Unicode codepoint in &#x#{hex};",
         nil,
         nil,
         %{entity: "&#x#{hex};"}
       )}
  end

  # Handle unknown named entities based on on_unknown setting
  defp handle_unknown(name, :raise) do
    {:error,
     Error.parse_error(
       :unknown_entity,
       "Unknown entity: &#{name};",
       nil,
       nil,
       %{entity: "&#{name};"}
     )}
  end

  defp handle_unknown(name, :emit) do
    {:error,
     Error.parse_error(
       :unknown_entity,
       "Unknown entity: &#{name};",
       nil,
       nil,
       %{entity: "&#{name};"}
     )}
  end

  defp handle_unknown(_name, :keep), do: {:keep, nil}
  defp handle_unknown(_name, :remove), do: {:remove, nil}

  @doc """
  Returns the map of predefined XML entities.
  """
  def predefined_entities, do: @predefined

  @doc """
  Encode text for XML output by escaping special characters.

  This is the inverse of entity resolution - use when generating XML.

  ## Examples

      iex> FnXML.Event.Transform.Entities.encode("Tom & Jerry")
      "Tom &amp; Jerry"

      iex> FnXML.Event.Transform.Entities.encode("<tag>")
      "&lt;tag&gt;"
  """
  def encode(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  @doc """
  Encode text for use in XML attribute values.

  Escapes quotes in addition to the standard characters.

  ## Examples

      iex> FnXML.Event.Transform.Entities.encode_attr("value with \"quotes\"")
      "value with &quot;quotes&quot;"
  """
  def encode_attr(text) when is_binary(text) do
    text
    |> encode()
    |> String.replace("\"", "&quot;")
  end
end
