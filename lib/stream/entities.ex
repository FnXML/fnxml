defmodule FnXML.Stream.Entities do
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
      |> FnXML.Stream.Entities.resolve()
      |> Enum.to_list()

  ## Options

  - `:entities` - Map of custom entity name => replacement
  - `:on_unknown` - How to handle unknown named entities:
    - `:raise` (default) - Raise FnXML.Error
    - `:emit` - Emit error token in stream
    - `:keep` - Keep the entity reference as-is
    - `:remove` - Remove the entity reference

  ## Examples

      # Basic entity resolution
      iex> "<a>Tom &amp; Jerry</a>"
      ...> |> FnXML.Parser.parse()
      ...> |> FnXML.Stream.Entities.resolve()
      ...> |> Enum.to_list()
      ...> |> Enum.find(&match?({:text, _}, &1))
      ...> |> elem(1)
      ...> |> Keyword.get(:content)
      "Tom & Jerry"

      # Custom entities
      iex> "<a>&copy;</a>"
      ...> |> FnXML.Parser.parse()
      ...> |> FnXML.Stream.Entities.resolve(entities: %{"copy" => "©"})
      ...> |> Enum.to_list()
      ...> |> Enum.find(&match?({:text, _}, &1))
      ...> |> elem(1)
      ...> |> Keyword.get(:content)
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
  """
  def resolve(stream, opts \\ []) do
    entities = Map.merge(@predefined, Keyword.get(opts, :entities, %{}))
    on_unknown = Keyword.get(opts, :on_unknown, :raise)

    Stream.flat_map(stream, fn
      {:text, meta} ->
        resolve_text_token(meta, entities, on_unknown)

      {:open, meta} ->
        resolve_open_token(meta, entities, on_unknown)

      elem ->
        [elem]
    end)
  end

  # Resolve entities in text content
  defp resolve_text_token(meta, entities, on_unknown) do
    content = Keyword.get(meta, :content, "")

    case resolve_text(content, entities, on_unknown) do
      {:ok, resolved} ->
        [{:text, Keyword.put(meta, :content, resolved)}]

      {:error, error} ->
        handle_resolution_error(error, on_unknown)
    end
  end

  # Resolve entities in attribute values
  defp resolve_open_token(meta, entities, on_unknown) do
    attrs = Keyword.get(meta, :attributes, [])

    case resolve_attrs(attrs, entities, on_unknown) do
      {:ok, resolved_attrs} ->
        [{:open, Keyword.put(meta, :attributes, resolved_attrs)}]

      {:error, error} ->
        handle_resolution_error(error, on_unknown)
    end
  end

  # Handle errors based on on_unknown setting
  defp handle_resolution_error(error, :raise), do: raise(error)
  defp handle_resolution_error(error, :emit), do: [{:error, error}]
  defp handle_resolution_error(_error, _), do: []

  @doc """
  Resolve entities in a text string.

  Returns `{:ok, resolved_string}` or `{:error, %FnXML.Error{}}`.
  """
  def resolve_text(text, entities \\ @predefined, on_unknown \\ :raise) do
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
  end

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

      iex> FnXML.Stream.Entities.encode("Tom & Jerry")
      "Tom &amp; Jerry"

      iex> FnXML.Stream.Entities.encode("<tag>")
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

      iex> FnXML.Stream.Entities.encode_attr("value with \\"quotes\\"")
      "value with &quot;quotes&quot;"
  """
  def encode_attr(text) when is_binary(text) do
    text
    |> encode()
    |> String.replace("\"", "&quot;")
  end
end
