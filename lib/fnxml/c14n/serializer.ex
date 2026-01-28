defmodule FnXML.C14N.Serializer do
  @moduledoc """
  Canonical XML serialization functions.

  Implements W3C Canonical XML 1.0 serialization rules:
  - Namespace declarations sorted alphabetically by prefix
  - Attributes sorted by namespace URI, then local name
  - Empty elements rendered as start-tag/end-tag pairs
  - Specific character escaping for text and attributes

  ## Escaping Rules

  **Text content**: `&` `<` `>` are escaped

  **Attribute values**: `&` `<` `>` `"` plus whitespace characters
  `#x9` (tab), `#xA` (newline), `#xD` (carriage return) are escaped

  ## References

  - W3C Canonical XML 1.0: https://www.w3.org/TR/xml-c14n
  """

  @doc """
  Serialize an opening tag with sorted namespace declarations and attributes.

  Returns iodata: `<tag xmlns:... attr1="..." attr2="...">`
  """
  @spec serialize_start(String.t(), [{String.t(), String.t()}], map(), atom(), [String.t()]) ::
          iodata()
  def serialize_start(tag, attrs, ns_context, algorithm, inclusive_ns) do
    {ns_decls, regular_attrs} = partition_attrs(attrs)

    # Filter/augment namespace declarations based on algorithm
    final_ns_decls =
      case algorithm do
        alg when alg in [:exc_c14n, :exc_c14n_with_comments] ->
          # For Exclusive C14N, we need to:
          # 1. Include ns_decls from this element that are utilized
          # 2. Also include declarations from inherited scope that are utilized
          #    but not declared on this element
          utilized_prefixes = collect_utilized_prefixes(tag, regular_attrs, inclusive_ns)

          # Get declarations from this element that are utilized
          local_ns_decls =
            Enum.filter(ns_decls, fn
              {"xmlns", _} -> not String.contains?(tag, ":")
              {"xmlns:" <> prefix, _} -> prefix in utilized_prefixes
            end)

          # Get declarations from inherited scope for utilized prefixes
          # not declared on this element
          local_prefixes =
            MapSet.new(ns_decls, fn
              {"xmlns", _} -> ""
              {"xmlns:" <> prefix, _} -> prefix
            end)

          inherited_ns_decls =
            utilized_prefixes
            |> Enum.reject(&(&1 in local_prefixes))
            |> Enum.flat_map(fn prefix ->
              case Map.get(ns_context, prefix) do
                nil -> []
                uri -> [{"xmlns:#{prefix}", uri}]
              end
            end)

          # Handle default namespace from inherited scope
          default_inherited =
            if "" in utilized_prefixes and "" not in local_prefixes do
              case Map.get(ns_context, "") do
                nil -> []
                uri -> [{"xmlns", uri}]
              end
            else
              []
            end

          local_ns_decls ++ inherited_ns_decls ++ default_inherited

        _ ->
          # C14N 1.0: include all namespace declarations
          ns_decls
      end

    sorted_ns = sort_ns_decls(final_ns_decls)
    sorted_attrs = sort_attrs(regular_attrs, ns_context)

    [
      "<",
      tag,
      serialize_ns_decls(sorted_ns),
      serialize_attrs(sorted_attrs),
      ">"
    ]
  end

  @doc """
  Serialize an empty element as start-tag/end-tag pair.

  Per C14N spec, empty elements must be rendered as `<tag></tag>`, not `<tag/>`.
  """
  @spec serialize_empty(String.t(), [{String.t(), String.t()}], map(), atom(), [String.t()]) ::
          iodata()
  def serialize_empty(tag, attrs, ns_context, algorithm, inclusive_ns) do
    [
      serialize_start(tag, attrs, ns_context, algorithm, inclusive_ns),
      "</",
      tag,
      ">"
    ]
  end

  @doc """
  Serialize a closing tag.
  """
  @spec serialize_end(String.t()) :: iodata()
  def serialize_end(tag) do
    ["</", tag, ">"]
  end

  @doc """
  Serialize text content with C14N escaping.

  Escapes: `&` -> `&amp;`, `<` -> `&lt;`, `>` -> `&gt;`
  """
  @spec serialize_text(String.t()) :: iodata()
  def serialize_text(text) do
    escape_text(text)
  end

  @doc """
  Serialize a comment (only for WithComments variants).

  Per C14N, comments are omitted unless using a WithComments algorithm.
  """
  @spec serialize_comment(String.t()) :: iodata()
  def serialize_comment(content) do
    ["<!--", content, "-->"]
  end

  @doc """
  Serialize a processing instruction.

  Per C14N, PIs are rendered as `<?target data?>` with a single space
  between target and data.
  """
  @spec serialize_pi(String.t(), String.t() | nil) :: iodata()
  def serialize_pi(target, nil), do: ["<?", target, "?>"]
  def serialize_pi(target, ""), do: ["<?", target, "?>"]

  def serialize_pi(target, data) do
    # Trim leading/trailing whitespace from data, parser may include extra spaces
    trimmed = String.trim(data)

    if trimmed == "" do
      ["<?", target, "?>"]
    else
      ["<?", target, " ", trimmed, "?>"]
    end
  end

  # Partition attributes into namespace declarations and regular attributes
  @spec partition_attrs([{String.t(), String.t()}]) ::
          {[{String.t(), String.t()}], [{String.t(), String.t()}]}
  defp partition_attrs(attrs) do
    Enum.split_with(attrs, fn {name, _value} ->
      is_ns_decl?(name)
    end)
  end

  # Check if attribute is a namespace declaration
  defp is_ns_decl?("xmlns"), do: true
  defp is_ns_decl?("xmlns:" <> _), do: true
  defp is_ns_decl?(_), do: false

  @doc """
  Sort namespace declarations alphabetically by prefix.

  Default namespace (xmlns) comes first, then prefixed declarations
  sorted by prefix name.
  """
  @spec sort_ns_decls([{String.t(), String.t()}]) :: [{String.t(), String.t()}]
  def sort_ns_decls(ns_decls) do
    Enum.sort_by(ns_decls, fn
      {"xmlns", _} -> {"", ""}
      {"xmlns:" <> prefix, _} -> {prefix, prefix}
    end)
  end

  @doc """
  Sort attributes by namespace URI, then local name.

  Attributes without namespace prefix come before those with prefixes.
  Within each group, sort alphabetically by local name.
  """
  @spec sort_attrs([{String.t(), String.t()}], map()) :: [{String.t(), String.t()}]
  def sort_attrs(attrs, ns_context) do
    Enum.sort_by(attrs, fn {name, _value} ->
      case String.split(name, ":", parts: 2) do
        [local_name] ->
          # No namespace prefix - use empty string for namespace
          {"", local_name}

        [prefix, local_name] ->
          # Has namespace prefix - look up URI in context
          ns_uri = Map.get(ns_context, prefix, prefix)
          {ns_uri, local_name}
      end
    end)
  end

  # Collect all visibly utilized namespace prefixes
  # For exclusive C14N, returns a MapSet of prefixes used by the element and its attributes.
  # An empty string "" indicates the default namespace is utilized.
  defp collect_utilized_prefixes(tag, attrs, inclusive_ns) do
    # Start with inclusive namespace list
    prefixes = MapSet.new(inclusive_ns)

    # Add element's namespace prefix (or "" for default namespace)
    prefixes =
      case String.split(tag, ":", parts: 2) do
        # Element uses default namespace
        [_local] -> MapSet.put(prefixes, "")
        [prefix, _local] -> MapSet.put(prefixes, prefix)
      end

    # Add prefixes from attribute names (attributes without prefix don't use any namespace)
    Enum.reduce(attrs, prefixes, fn {name, _value}, acc ->
      case String.split(name, ":", parts: 2) do
        # Unprefixed attributes have no namespace
        [_local] -> acc
        [prefix, _local] -> MapSet.put(acc, prefix)
      end
    end)
  end

  # Serialize sorted namespace declarations
  defp serialize_ns_decls([]), do: []

  defp serialize_ns_decls(ns_decls) do
    Enum.map(ns_decls, fn {name, value} ->
      [" ", name, "=\"", escape_attr(value), "\""]
    end)
  end

  # Serialize sorted attributes
  defp serialize_attrs([]), do: []

  defp serialize_attrs(attrs) do
    Enum.map(attrs, fn {name, value} ->
      [" ", name, "=\"", escape_attr(value), "\""]
    end)
  end

  @doc """
  Escape text content per C14N rules.

  - `&` -> `&amp;`
  - `<` -> `&lt;`
  - `>` -> `&gt;`

  Note: If the input contains already-encoded entities (from a parser that doesn't
  decode), they will be decoded first to avoid double-escaping.
  """
  @spec escape_text(String.t()) :: String.t()
  def escape_text(text) do
    text
    |> decode_entities()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  # Decode XML entities that may be present in parser output
  defp decode_entities(text) do
    text
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&amp;", "&")
  end

  @doc """
  Escape attribute value per C14N rules.

  - `&` -> `&amp;`
  - `<` -> `&lt;`
  - `>` -> `&gt;` (only for compatibility, not strictly required)
  - `"` -> `&quot;`
  - `#x9` (tab) -> `&#x9;`
  - `#xA` (newline) -> `&#xA;`
  - `#xD` (carriage return) -> `&#xD;`
  """
  @spec escape_attr(String.t()) :: String.t()
  def escape_attr(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("\t", "&#x9;")
    |> String.replace("\n", "&#xA;")
    |> String.replace("\r", "&#xD;")
  end

  @doc """
  Extract namespace prefix from a qualified name.

  ## Examples

      iex> extract_prefix("foo:bar")
      "foo"

      iex> extract_prefix("bar")
      nil
  """
  @spec extract_prefix(String.t()) :: String.t() | nil
  def extract_prefix(name) do
    case String.split(name, ":", parts: 2) do
      [_local] -> nil
      [prefix, _local] -> prefix
    end
  end

  @doc """
  Extract local name from a qualified name.

  ## Examples

      iex> extract_local("foo:bar")
      "bar"

      iex> extract_local("bar")
      "bar"
  """
  @spec extract_local(String.t()) :: String.t()
  def extract_local(name) do
    case String.split(name, ":", parts: 2) do
      [local] -> local
      [_prefix, local] -> local
    end
  end
end
