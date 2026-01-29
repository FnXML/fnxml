defmodule FnXML.Namespaces do
  @moduledoc """
  XML Namespaces 1.0 (Third Edition) implementation for FnXML streams.

  This module provides namespace processing for XML event streams, implementing
  the W3C Namespaces in XML 1.0 specification.

  ## Overview

  XML Namespaces provide a mechanism for qualifying element and attribute names
  through URI-based namespace identification, enabling safe reuse of markup
  vocabularies without naming collisions.

  ## Key Concepts

  ### Expanded Names
  A pair consisting of:
  - **Namespace name** (URI reference) - provides universal uniqueness
  - **Local name** - the vocabulary-specific part

  ### Qualified Names (QNames)
  Element and attribute names that undergo namespace interpretation:
  - `prefix:localname` - prefixed form
  - `localname` - unprefixed form

  ### Namespace Declarations
  Declared using reserved attributes:
  - `xmlns="uri"` - default namespace (applies to unprefixed elements)
  - `xmlns:prefix="uri"` - prefixed namespace

  ## Usage

      # Validate namespace constraints (emits error events)
      FnXML.Parser.parse(xml)
      |> FnXML.Namespaces.validate()
      |> Enum.to_list()

      # Resolve to expanded names
      FnXML.Parser.parse(xml)
      |> FnXML.Namespaces.resolve()
      |> Enum.to_list()

      # Both validate and resolve
      FnXML.Parser.parse(xml)
      |> FnXML.Namespaces.validate()
      |> FnXML.Namespaces.resolve()
      |> Enum.to_list()

  ## Event Transformation

  After resolution, events have expanded names:

      # Input:
      {:start_element, "ns:element", [{"xmlns:ns", "http://example.org"}, {"id", "1"}], loc}

      # Output:
      {:start_element, {"http://example.org", "element"}, [{nil, "id", "1"}], loc}

  ## Reserved Prefixes

  - `xml` - permanently bound to `http://www.w3.org/XML/1998/namespace`
  - `xmlns` - bound to `http://www.w3.org/2000/xmlns/`

  ## Namespace Constraints (from W3C spec)

  1. **NSC: Prefix Declared** - All prefixes except `xml` must be declared
  2. **NSC: No Prefix Undeclaring** - Cannot bind prefix to empty string
  3. **NSC: Attributes Unique** - No two attributes with same expanded name
  4. **NSC: Reserved Prefixes** - Cannot rebind `xml` or `xmlns` incorrectly

  ## References

  - W3C Namespaces in XML 1.0: https://www.w3.org/TR/xml-names/
  """

  alias FnXML.Namespaces.{Context, QName, Resolver}
  alias FnXML.Event.Validate.Namespaces, as: Validator

  @xml_namespace "http://www.w3.org/XML/1998/namespace"
  @xmlns_namespace "http://www.w3.org/2000/xmlns/"
  @xsd_namespace "http://www.w3.org/2001/XMLSchema"
  @xsi_namespace "http://www.w3.org/2001/XMLSchema-instance"

  # ============================================================================
  # Stream Processing
  # ============================================================================

  @doc """
  Validate namespace constraints in an FnXML event stream.

  Returns a stream that includes error events for any namespace violations.
  The original events are passed through unchanged.

  Error events have the form:
      {:ns_error, reason, name, location}

  ## Options

  None currently.

  ## Examples

      FnXML.Parser.parse("<foo:bar/>")
      |> FnXML.Namespaces.validate()
      |> Enum.to_list()
      # => [{:ns_error, {:undeclared_prefix, "foo"}, "foo:bar", loc}, {:start_element, ...}, ...]
  """
  @spec validate(Enumerable.t(), keyword()) :: Enumerable.t()
  defdelegate validate(stream, opts \\ []), to: Validator

  @doc """
  Resolve namespace prefixes to expanded names in an FnXML event stream.

  Returns a stream with element and attribute names expanded to
  `{namespace_uri, local_name}` tuples.

  ## Options

  - `:strip_declarations` - Remove xmlns attributes from output (default: false)
  - `:include_prefix` - Include original prefix in output as third element (default: false)

  ## Examples

      FnXML.Parser.parse(~s(<root xmlns="http://example.org"><child/></root>))
      |> FnXML.Namespaces.resolve()
      |> Enum.to_list()

      # Elements become {uri, local}:
      # {:start_element, {"http://example.org", "root"}, [...], loc}
      # {:start_element, {"http://example.org", "child"}, [], loc}
  """
  @spec resolve(Enumerable.t(), keyword()) :: Enumerable.t()
  defdelegate resolve(stream, opts \\ []), to: Resolver

  # ============================================================================
  # Utility Functions
  # ============================================================================

  @doc """
  Check if a string is a valid NCName (non-colonized name).

  NCName is an XML Name that contains no colons.
  """
  @spec valid_ncname?(String.t()) :: boolean()
  defdelegate valid_ncname?(name), to: QName

  @doc """
  Check if a string is a valid QName (qualified name).

  A QName is either an NCName or prefix:NCName.
  """
  @spec valid_qname?(String.t()) :: boolean()
  defdelegate valid_qname?(name), to: QName

  @doc """
  Parse a qualified name into {prefix, local_part}.

  Returns `{nil, name}` for unprefixed names.
  """
  @spec parse_qname(String.t()) :: {String.t() | nil, String.t()}
  defdelegate parse_qname(name), to: QName, as: :parse

  @doc """
  Check if an attribute name is a namespace declaration.

  Returns:
  - `{:default, nil}` for "xmlns"
  - `{:prefix, prefix}` for "xmlns:prefix"
  - `false` for other names
  """
  @spec namespace_declaration?(String.t()) :: {:default, nil} | {:prefix, String.t()} | false
  defdelegate namespace_declaration?(name), to: QName

  @doc """
  Create a new namespace context.

  The context tracks namespace bindings and supports scoping.
  """
  @spec new_context() :: Context.t()
  defdelegate new_context(), to: Context, as: :new

  @doc """
  Expand an element name using the given context.

  Returns `{:ok, {uri, local}}` or `{:error, reason}`.
  """
  @spec expand_element(Context.t(), String.t()) ::
          {:ok, {String.t() | nil, String.t()}} | {:error, term()}
  defdelegate expand_element(ctx, name), to: Context

  @doc """
  Expand an attribute name using the given context.

  Note: Unprefixed attributes have no namespace (nil), not the default namespace.
  """
  @spec expand_attribute(Context.t(), String.t()) ::
          {:ok, {String.t() | nil, String.t()}} | {:error, term()}
  defdelegate expand_attribute(ctx, name), to: Context

  # ============================================================================
  # Constants
  # ============================================================================

  @doc """
  Returns the predefined XML namespace URI.

  `http://www.w3.org/XML/1998/namespace`
  """
  @spec xml_namespace() :: String.t()
  def xml_namespace, do: @xml_namespace

  @doc """
  Returns the predefined xmlns namespace URI.

  `http://www.w3.org/2000/xmlns/`
  """
  @spec xmlns_namespace() :: String.t()
  def xmlns_namespace, do: @xmlns_namespace

  @doc """
  Returns the XML Schema Definition namespace URI.

  `http://www.w3.org/2001/XMLSchema`
  """
  @spec xsd_namespace() :: String.t()
  def xsd_namespace, do: @xsd_namespace

  @doc """
  Returns the XML Schema Instance namespace URI.

  `http://www.w3.org/2001/XMLSchema-instance`
  """
  @spec xsi_namespace() :: String.t()
  def xsi_namespace, do: @xsi_namespace

  @doc """
  Get the local part of a name (strips prefix if present).

  This is a convenience function for extracting just the local name
  from a potentially prefixed QName.

  ## Examples

      iex> FnXML.Namespaces.local_part("foo")
      "foo"

      iex> FnXML.Namespaces.local_part("ns:element")
      "element"

      iex> FnXML.Namespaces.local_part("xs:string")
      "string"
  """
  @spec local_part(String.t()) :: String.t()
  defdelegate local_part(name), to: QName

  @doc """
  Get the prefix of a name (nil if unprefixed).

  ## Examples

      iex> FnXML.Namespaces.prefix("foo")
      nil

      iex> FnXML.Namespaces.prefix("ns:element")
      "ns"
  """
  @spec prefix(String.t()) :: String.t() | nil
  defdelegate prefix(name), to: QName

  @doc """
  Check if a name is prefixed.

  ## Examples

      iex> FnXML.Namespaces.prefixed?("foo")
      false

      iex> FnXML.Namespaces.prefixed?("ns:element")
      true
  """
  @spec prefixed?(String.t()) :: boolean()
  defdelegate prefixed?(name), to: QName

  # ============================================================================
  # Error Checking Helpers
  # ============================================================================

  @doc """
  Check if an event is a namespace error.
  """
  @spec ns_error?(term()) :: boolean()
  def ns_error?({:ns_error, _, _, _}), do: true
  def ns_error?(_), do: false

  @doc """
  Extract all namespace errors from a list of events.
  """
  @spec errors(list(term())) :: list(term())
  def errors(events) when is_list(events) do
    Enum.filter(events, &ns_error?/1)
  end

  @doc """
  Check if any namespace errors exist in a list of events.
  """
  @spec errors?(list(term())) :: boolean()
  def errors?(events) when is_list(events) do
    Enum.any?(events, &ns_error?/1)
  end
end
