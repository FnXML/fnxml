defmodule FnXML.Namespaces.Context do
  @moduledoc """
  Namespace context management for XML Namespaces processing.

  The context tracks:
  - Current default namespace (applies to unprefixed elements)
  - Prefix-to-URI bindings
  - Scope stack for nested elements

  ## Scoping Rules (from W3C spec)

  The scope of a namespace declaration extends from the beginning of the
  start-tag to the end of the corresponding end-tag, excluding any inner
  declarations with the same NSAttName.

  ## Reserved Prefixes

  - `xml` is permanently bound to `http://www.w3.org/XML/1998/namespace`
  - `xmlns` is permanently bound to `http://www.w3.org/2000/xmlns/`
  """

  alias FnXML.Namespaces.QName

  @xml_namespace "http://www.w3.org/XML/1998/namespace"
  @xmlns_namespace "http://www.w3.org/2000/xmlns/"

  defstruct [
    # Default namespace: :unset, nil (explicitly undeclared), or URI string
    default: :unset,
    # %{prefix => uri}
    prefixes: %{},
    # Parent context (for scoping)
    parent: nil,
    # XML version ("1.0" or "1.1")
    xml_version: "1.0"
  ]

  @type t :: %__MODULE__{
          default: String.t() | nil | :unset,
          prefixes: %{String.t() => String.t()},
          parent: t() | nil,
          xml_version: String.t()
        }

  @doc """
  Create a new root namespace context.

  The root context has the `xml` prefix pre-bound.

  ## Examples

      iex> ctx = FnXML.Namespaces.Context.new()
      iex> FnXML.Namespaces.Context.resolve_prefix(ctx, "xml")
      {:ok, "http://www.w3.org/XML/1998/namespace"}
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      default: :unset,
      prefixes: %{"xml" => @xml_namespace},
      parent: nil,
      xml_version: Keyword.get(opts, :xml_version, "1.0")
    }
  end

  @doc """
  Set the XML version for this context.
  Accepts any 1.x version per XML 1.0 5th edition.
  Unknown 1.x versions are treated as "1.0" for namespace purposes.
  """
  @spec set_xml_version(t(), String.t()) :: t()
  def set_xml_version(ctx, version) when is_binary(version) do
    # Normalize unknown 1.x versions to "1.0" for internal handling
    normalized =
      case version do
        "1.0" -> "1.0"
        "1.1" -> "1.1"
        _ -> "1.0"
      end

    %{ctx | xml_version: normalized}
  end

  @doc """
  Get the XML version for this context.
  """
  @spec xml_version(t()) :: String.t()
  def xml_version(%__MODULE__{xml_version: version}), do: version

  @doc """
  Push a new scope onto the context stack.

  Extracts namespace declarations from attributes and creates a child context.
  Returns `{:ok, new_context, filtered_attrs}` or `{:error, reason}`.

  The filtered_attrs has namespace declarations removed (if strip_declarations option is true).

  ## Options

  - `:strip_declarations` - Remove xmlns attributes from returned attrs (default: false)

  ## Examples

      iex> ctx = FnXML.Namespaces.Context.new()
      iex> attrs = [{"xmlns", "http://example.org"}, {"xmlns:foo", "http://foo.org"}, {"id", "1"}]
      iex> {:ok, new_ctx, _} = FnXML.Namespaces.Context.push(ctx, attrs)
      iex> FnXML.Namespaces.Context.default_namespace(new_ctx)
      "http://example.org"
  """
  @spec push(t(), list({String.t(), String.t()}), keyword()) ::
          {:ok, t(), list({String.t(), String.t()})} | {:error, term()}
  def push(context, attrs, opts \\ []) do
    strip = Keyword.get(opts, :strip_declarations, false)

    case extract_declarations(attrs, context) do
      {:ok, new_default, new_prefixes, filtered_attrs} ->
        child = %__MODULE__{
          default: new_default,
          prefixes: new_prefixes,
          parent: context,
          xml_version: context.xml_version
        }

        attrs_out = if strip, do: filtered_attrs, else: attrs
        {:ok, child, attrs_out}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Pop the current scope, returning to parent context.

  Returns the parent context, or the same context if at root.
  """
  @spec pop(t()) :: t()
  def pop(%__MODULE__{parent: nil} = ctx), do: ctx
  def pop(%__MODULE__{parent: parent}), do: parent

  @doc """
  Resolve a prefix to its namespace URI.

  Returns `{:ok, uri}` or `{:error, :undeclared_prefix}`.

  ## Special cases

  - `xml` is always bound to `http://www.w3.org/XML/1998/namespace`
  - `xmlns` is always bound to `http://www.w3.org/2000/xmlns/`

  ## Examples

      iex> ctx = FnXML.Namespaces.Context.new()
      iex> {:ok, ctx, _} = FnXML.Namespaces.Context.push(ctx, [{"xmlns:foo", "http://foo.org"}])
      iex> FnXML.Namespaces.Context.resolve_prefix(ctx, "foo")
      {:ok, "http://foo.org"}

      iex> ctx = FnXML.Namespaces.Context.new()
      iex> FnXML.Namespaces.Context.resolve_prefix(ctx, "undeclared")
      {:error, :undeclared_prefix}
  """
  @spec resolve_prefix(t(), String.t()) :: {:ok, String.t()} | {:error, :undeclared_prefix}
  def resolve_prefix(_ctx, "xml"), do: {:ok, @xml_namespace}
  def resolve_prefix(_ctx, "xmlns"), do: {:ok, @xmlns_namespace}

  def resolve_prefix(%__MODULE__{prefixes: prefixes, parent: parent}, prefix) do
    case Map.fetch(prefixes, prefix) do
      # Empty string means prefix was unbound (NS 1.1) - treat as undeclared
      {:ok, ""} -> {:error, :undeclared_prefix}
      {:ok, uri} -> {:ok, uri}
      :error when parent != nil -> resolve_prefix(parent, prefix)
      :error -> {:error, :undeclared_prefix}
    end
  end

  @doc """
  Get the current default namespace URI.

  Returns the URI or nil if no default namespace is in scope.
  """
  @spec default_namespace(t()) :: String.t() | nil
  def default_namespace(%__MODULE__{default: default, parent: parent}) do
    case default do
      :unset when parent != nil -> default_namespace(parent)
      :unset -> nil
      # Explicitly undeclared (xmlns="")
      nil -> nil
      uri -> uri
    end
  end

  @doc """
  Expand an element name to its expanded name {uri, local}.

  For elements:
  - Prefixed names use the prefix binding
  - Unprefixed names use the default namespace (or nil if none)

  Returns `{:ok, {uri, local}}` or `{:error, reason}`.
  """
  @spec expand_element(t(), String.t()) ::
          {:ok, {String.t() | nil, String.t()}} | {:error, term()}
  def expand_element(ctx, name) do
    case QName.parse(name) do
      {nil, local} ->
        # Unprefixed element - use default namespace
        {:ok, {default_namespace(ctx), local}}

      {prefix, local} ->
        # Prefixed element - resolve prefix
        case resolve_prefix(ctx, prefix) do
          {:ok, uri} -> {:ok, {uri, local}}
          {:error, _} = error -> error
        end
    end
  end

  @doc """
  Expand an attribute name to its expanded name {uri, local}.

  For attributes:
  - Prefixed names use the prefix binding
  - Unprefixed names have NO namespace (not even default)
  - Namespace declarations are in the xmlns namespace

  Returns `{:ok, {uri, local}}` or `{:error, reason}`.
  """
  @spec expand_attribute(t(), String.t()) ::
          {:ok, {String.t() | nil, String.t()}} | {:error, term()}
  def expand_attribute(ctx, name) do
    case QName.namespace_declaration?(name) do
      {:default, _} ->
        # xmlns attribute
        {:ok, {@xmlns_namespace, name}}

      {:prefix, _} ->
        # xmlns:prefix attribute
        {:ok, {@xmlns_namespace, name}}

      false ->
        # Regular attribute
        case QName.parse(name) do
          {nil, local} ->
            # Unprefixed attribute - NO namespace
            {:ok, {nil, local}}

          {prefix, local} ->
            # Prefixed attribute - resolve prefix
            case resolve_prefix(ctx, prefix) do
              {:ok, uri} -> {:ok, {uri, local}}
              {:error, _} = error -> error
            end
        end
    end
  end

  @doc """
  Get all currently bound prefixes (including inherited).

  Returns a map of prefix => uri.
  """
  @spec all_prefixes(t()) :: %{String.t() => String.t()}
  def all_prefixes(%__MODULE__{prefixes: prefixes, parent: nil}) do
    Map.put(prefixes, "xml", @xml_namespace)
  end

  def all_prefixes(%__MODULE__{prefixes: prefixes, parent: parent}) do
    parent_prefixes = all_prefixes(parent)
    Map.merge(parent_prefixes, prefixes)
  end

  @doc """
  Check if a namespace URI is in scope.
  """
  @spec in_scope?(t(), String.t()) :: boolean()
  def in_scope?(ctx, uri) do
    uri == default_namespace(ctx) or
      uri in Map.values(all_prefixes(ctx))
  end

  @doc """
  Returns the XML namespace URI constant.
  """
  def xml_namespace, do: @xml_namespace

  @doc """
  Returns the XMLNS namespace URI constant.
  """
  def xmlns_namespace, do: @xmlns_namespace

  # Extract namespace declarations from attributes
  # Returns {:ok, default, prefixes, filtered_attrs} or {:error, reason}
  defp extract_declarations(attrs, parent_ctx) do
    # Start with parent's bindings
    initial_prefixes = if parent_ctx.parent, do: %{}, else: parent_ctx.prefixes
    # Will inherit from parent if not overridden
    initial_default = :unset

    result =
      Enum.reduce_while(attrs, {:ok, initial_default, initial_prefixes, []}, fn
        {name, value}, {:ok, default, prefixes, filtered} ->
          case QName.namespace_declaration?(name) do
            {:default, _} ->
              # xmlns="uri" or xmlns=""
              new_default = if value == "", do: nil, else: value
              {:cont, {:ok, new_default, prefixes, filtered}}

            {:prefix, prefix} ->
              # xmlns:prefix="uri"
              case validate_prefix_binding(prefix, value, parent_ctx.xml_version) do
                :ok ->
                  new_prefixes = Map.put(prefixes, prefix, value)
                  {:cont, {:ok, default, new_prefixes, filtered}}

                {:error, _} = error ->
                  {:halt, error}
              end

            false ->
              # Regular attribute
              {:cont, {:ok, default, prefixes, [{name, value} | filtered]}}
          end
      end)

    case result do
      {:ok, default, prefixes, filtered} ->
        {:ok, default, prefixes, Enum.reverse(filtered)}

      {:error, _} = error ->
        error
    end
  end

  # Validate prefix binding per NSC: Reserved Prefixes and Namespace Names
  # and NSC: No Prefix Undeclaring
  defp validate_prefix_binding(prefix, value, xml_version) do
    cond do
      # NSC: No Prefix Undeclaring - cannot bind prefix to empty string
      # BUT: In XML 1.1 / NS 1.1, prefix undeclaring IS allowed
      value == "" and xml_version != "1.1" ->
        {:error, {:empty_prefix_binding, prefix}}

      # Cannot bind anything to xml namespace except xml prefix
      value == @xml_namespace and prefix != "xml" ->
        {:error, {:reserved_namespace, @xml_namespace}}

      # Cannot bind xml prefix to anything else
      prefix == "xml" and value != @xml_namespace ->
        {:error, {:reserved_prefix, "xml"}}

      # Cannot bind anything to xmlns namespace
      value == @xmlns_namespace ->
        {:error, {:reserved_namespace, @xmlns_namespace}}

      # Cannot use xmlns as prefix
      prefix == "xmlns" ->
        {:error, {:reserved_prefix, "xmlns"}}

      true ->
        :ok
    end
  end
end
