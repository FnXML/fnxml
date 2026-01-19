defmodule FnXML.XsTypes do
  @moduledoc """
  Unified XSD type library for the Elixir XML ecosystem.

  This module consolidates XSD (XML Schema Definition) type handling
  into a single, comprehensive implementation for use across fnxml,
  fnsoap, fnxsd, and fnxpath.

  ## Features

  - **Validation** - Validate string representations against XSD types
  - **Parsing** - Convert XSD string values to Elixir types
  - **Encoding** - Convert Elixir values to XSD string representations
  - **Type Inference** - Infer XSD types from Elixir values
  - **Facet Support** - Apply constraining facets (length, pattern, etc.)
  - **Type Hierarchy** - Query XSD type derivation relationships

  ## Examples

      iex> FnXML.XsTypes.parse("42", :integer)
      {:ok, 42}

      iex> FnXML.XsTypes.encode(42, :integer)
      {:ok, "42"}

      iex> FnXML.XsTypes.validate("true", :boolean)
      :ok

      iex> FnXML.XsTypes.infer_type(~D[2024-01-15])
      :date
  """

  alias FnXML.XsTypes.{Primitive, Derived, Facets, Hierarchy}

  @xsd_namespace "http://www.w3.org/2001/XMLSchema"
  @xsi_namespace "http://www.w3.org/2001/XMLSchema-instance"

  @type type_name :: atom() | String.t()
  @type value :: term()
  @type facet ::
          {:length, non_neg_integer()}
          | {:minLength, non_neg_integer()}
          | {:maxLength, non_neg_integer()}
          | {:pattern, String.t()}
          | {:enumeration, [String.t()]}
          | {:minInclusive, String.t()}
          | {:maxInclusive, String.t()}
          | {:minExclusive, String.t()}
          | {:maxExclusive, String.t()}
          | {:totalDigits, pos_integer()}
          | {:fractionDigits, non_neg_integer()}
          | {:whiteSpace, :preserve | :replace | :collapse}

  @type reason ::
          {:invalid_value, type_name(), String.t()}
          | {:out_of_range, type_name(), value()}
          | {:facet_violation, atom(), term()}
          | {:unknown_type, String.t()}

  # ============================================================================
  # Namespace Constants
  # ============================================================================

  @doc """
  Returns the XSD namespace URI.

  ## Example

      iex> FnXML.XsTypes.xsd_namespace()
      "http://www.w3.org/2001/XMLSchema"
  """
  @spec xsd_namespace() :: String.t()
  def xsd_namespace, do: @xsd_namespace

  @doc """
  Returns the XSI (XML Schema Instance) namespace URI.

  ## Example

      iex> FnXML.XsTypes.xsi_namespace()
      "http://www.w3.org/2001/XMLSchema-instance"
  """
  @spec xsi_namespace() :: String.t()
  def xsi_namespace, do: @xsi_namespace

  # ============================================================================
  # Type Validation
  # ============================================================================

  @doc """
  Validate a string value against an XSD type.

  Returns `:ok` if the value is valid for the type, or `{:error, reason}` otherwise.

  ## Examples

      iex> FnXML.XsTypes.validate("42", :integer)
      :ok

      iex> FnXML.XsTypes.validate("abc", :integer)
      {:error, {:invalid_value, :integer, "abc"}}

      iex> FnXML.XsTypes.validate("true", :boolean)
      :ok
  """
  @spec validate(String.t(), type_name()) :: :ok | {:error, reason()}
  def validate(value, type) when is_binary(value) do
    normalized_type = normalize_type_name(type)

    cond do
      Hierarchy.primitive_type?(normalized_type) ->
        Primitive.validate(value, normalized_type)

      Hierarchy.derived_type?(normalized_type) ->
        Derived.validate(value, normalized_type)

      normalized_type in [:anyType, :anySimpleType] ->
        :ok

      true ->
        {:error, {:unknown_type, to_string(type)}}
    end
  end

  @doc """
  Check if a string value is valid for an XSD type.

  ## Examples

      iex> FnXML.XsTypes.valid?("42", :integer)
      true

      iex> FnXML.XsTypes.valid?("abc", :integer)
      false
  """
  @spec valid?(String.t(), type_name()) :: boolean()
  def valid?(value, type), do: validate(value, type) == :ok

  # ============================================================================
  # Parsing (String -> Elixir Value)
  # ============================================================================

  @doc """
  Parse a string value to its Elixir representation.

  ## Examples

      iex> FnXML.XsTypes.parse("42", :integer)
      {:ok, 42}

      iex> FnXML.XsTypes.parse("true", :boolean)
      {:ok, true}

      iex> FnXML.XsTypes.parse("2024-01-15", :date)
      {:ok, ~D[2024-01-15]}

      iex> FnXML.XsTypes.parse("INF", :double)
      {:ok, :infinity}
  """
  @spec parse(String.t(), type_name()) :: {:ok, value()} | {:error, reason()}
  def parse(value, type) when is_binary(value) do
    normalized_type = normalize_type_name(type)
    normalized_value = normalize_whitespace(value, normalized_type)

    cond do
      Hierarchy.primitive_type?(normalized_type) ->
        Primitive.parse(normalized_value, normalized_type)

      Hierarchy.derived_type?(normalized_type) ->
        Derived.parse(normalized_value, normalized_type)

      normalized_type in [:anyType, :anySimpleType] ->
        {:ok, normalized_value}

      true ->
        {:error, {:unknown_type, to_string(type)}}
    end
  end

  @doc """
  Parse a string value to its Elixir representation, raising on error.

  ## Examples

      iex> FnXML.XsTypes.parse!("42", :integer)
      42

      iex> FnXML.XsTypes.parse!("abc", :integer)
      ** (ArgumentError) Failed to parse "abc" as integer
  """
  @spec parse!(String.t(), type_name()) :: value() | no_return()
  def parse!(value, type) do
    case parse(value, type) do
      {:ok, result} -> result
      {:error, _reason} -> raise ArgumentError, "Failed to parse #{inspect(value)} as #{type}"
    end
  end

  # ============================================================================
  # Encoding (Elixir Value -> String)
  # ============================================================================

  @doc """
  Encode an Elixir value to its XSD string representation.

  ## Examples

      iex> FnXML.XsTypes.encode(42, :integer)
      {:ok, "42"}

      iex> FnXML.XsTypes.encode(true, :boolean)
      {:ok, "true"}

      iex> FnXML.XsTypes.encode(~D[2024-01-15], :date)
      {:ok, "2024-01-15"}

      iex> FnXML.XsTypes.encode(:infinity, :double)
      {:ok, "INF"}
  """
  @spec encode(value(), type_name()) :: {:ok, String.t()} | {:error, reason()}
  def encode(nil, _type), do: {:ok, ""}

  def encode(value, type) do
    normalized_type = normalize_type_name(type)

    cond do
      Hierarchy.primitive_type?(normalized_type) ->
        Primitive.encode(value, normalized_type)

      Hierarchy.derived_type?(normalized_type) ->
        Derived.encode(value, normalized_type)

      normalized_type in [:anyType, :anySimpleType] ->
        {:ok, to_string(value)}

      true ->
        {:error, {:unknown_type, to_string(type)}}
    end
  end

  @doc """
  Encode an Elixir value to its XSD string representation, raising on error.

  ## Examples

      iex> FnXML.XsTypes.encode!(42, :integer)
      "42"
  """
  @spec encode!(value(), type_name()) :: String.t() | no_return()
  def encode!(value, type) do
    case encode(value, type) do
      {:ok, result} -> result
      {:error, _reason} -> raise ArgumentError, "Failed to encode #{inspect(value)} as #{type}"
    end
  end

  # ============================================================================
  # Type Inference
  # ============================================================================

  @doc """
  Infer the XSD type from an Elixir value.

  ## Examples

      iex> FnXML.XsTypes.infer_type("hello")
      :string

      iex> FnXML.XsTypes.infer_type(42)
      :integer

      iex> FnXML.XsTypes.infer_type(3.14)
      :double

      iex> FnXML.XsTypes.infer_type(~D[2024-01-15])
      :date

      iex> FnXML.XsTypes.infer_type(%DateTime{})
      :dateTime
  """
  @spec infer_type(value()) :: type_name()
  def infer_type(value) when is_binary(value), do: :string
  def infer_type(value) when is_boolean(value), do: :boolean
  def infer_type(value) when is_integer(value), do: :integer
  def infer_type(value) when is_float(value), do: :double
  def infer_type(%DateTime{}), do: :dateTime
  def infer_type(%NaiveDateTime{}), do: :dateTime
  def infer_type(%Date{}), do: :date
  def infer_type(%Time{}), do: :time
  def infer_type(%URI{}), do: :anyURI
  def infer_type(:infinity), do: :double
  def infer_type(:neg_infinity), do: :double
  # XPath alias
  def infer_type(:positive_infinity), do: :double
  # XPath alias
  def infer_type(:negative_infinity), do: :double
  def infer_type(:nan), do: :double
  def infer_type({prefix, _local}) when is_binary(prefix) or is_nil(prefix), do: :QName
  def infer_type(nil), do: nil
  def infer_type(value) when is_list(value), do: :anyType
  def infer_type(value) when is_map(value), do: :anyType

  def infer_type(value) do
    if Code.ensure_loaded?(Decimal) and is_struct(value, Decimal) do
      :decimal
    else
      :anyType
    end
  end

  # ============================================================================
  # Whitespace Normalization
  # ============================================================================

  @doc """
  Normalize whitespace according to type rules.

  - `:preserve` - Keep all whitespace (string)
  - `:replace` - Replace CR/LF/Tab with space (normalizedString)
  - `:collapse` - Replace + trim + collapse consecutive spaces (token, etc.)

  ## Examples

      iex> FnXML.XsTypes.normalize_whitespace("  hello  world  ", :token)
      "hello world"

      iex> FnXML.XsTypes.normalize_whitespace("hello\\nworld", :normalizedString)
      "hello world"

      iex> FnXML.XsTypes.normalize_whitespace("hello\\nworld", :string)
      "hello\\nworld"
  """
  @spec normalize_whitespace(String.t(), type_name()) :: String.t()
  def normalize_whitespace(value, type) when is_binary(value) do
    case whitespace_mode(normalize_type_name(type)) do
      :preserve -> value
      :replace -> replace_whitespace(value)
      :collapse -> collapse_whitespace(value)
    end
  end

  @doc """
  Get the whitespace handling mode for a type.

  ## Examples

      iex> FnXML.XsTypes.whitespace_mode(:string)
      :preserve

      iex> FnXML.XsTypes.whitespace_mode(:normalizedString)
      :replace

      iex> FnXML.XsTypes.whitespace_mode(:token)
      :collapse
  """
  @spec whitespace_mode(type_name()) :: :preserve | :replace | :collapse
  def whitespace_mode(:string), do: :preserve
  def whitespace_mode(:normalizedString), do: :replace

  def whitespace_mode(type)
      when type in [
             :token,
             :language,
             :NMTOKEN,
             :NMTOKENS,
             :Name,
             :NCName,
             :ID,
             :IDREF,
             :IDREFS,
             :ENTITY,
             :ENTITIES
           ] do
    :collapse
  end

  def whitespace_mode(_type), do: :collapse

  defp replace_whitespace(value) do
    String.replace(value, ~r/[\t\n\r]/, " ")
  end

  defp collapse_whitespace(value) do
    value
    |> String.replace(~r/[\t\n\r]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # ============================================================================
  # Facet Validation
  # ============================================================================

  @doc """
  Validate a value against a type with constraining facets.

  ## Supported Facets

  - `length` - Exact length
  - `minLength` - Minimum length
  - `maxLength` - Maximum length
  - `pattern` - Regex pattern
  - `enumeration` - List of allowed values
  - `minInclusive` - Minimum value (inclusive)
  - `maxInclusive` - Maximum value (inclusive)
  - `minExclusive` - Minimum value (exclusive)
  - `maxExclusive` - Maximum value (exclusive)
  - `totalDigits` - Maximum total digits
  - `fractionDigits` - Maximum fraction digits
  - `whiteSpace` - Whitespace handling

  ## Examples

      iex> FnXML.XsTypes.validate_with_facets("hello", :string, [
      ...>   {:minLength, 1},
      ...>   {:maxLength, 10}
      ...> ])
      :ok

      iex> FnXML.XsTypes.validate_with_facets("42", :integer, [
      ...>   {:minInclusive, "0"},
      ...>   {:maxInclusive, "100"}
      ...> ])
      :ok
  """
  @spec validate_with_facets(String.t(), type_name(), [facet()]) :: :ok | {:error, reason()}
  def validate_with_facets(value, type, facets) when is_binary(value) and is_list(facets) do
    normalized_type = normalize_type_name(type)

    with :ok <- validate(value, normalized_type) do
      Facets.validate(value, normalized_type, facets)
    end
  end

  # ============================================================================
  # Type Name Handling
  # ============================================================================

  @doc """
  Normalize a type name, handling prefixes and converting to atom.

  ## Examples

      iex> FnXML.XsTypes.normalize_type_name("xs:integer")
      :integer

      iex> FnXML.XsTypes.normalize_type_name("xsd:string")
      :string

      iex> FnXML.XsTypes.normalize_type_name(:integer)
      :integer
  """
  @spec normalize_type_name(type_name()) :: atom()
  def normalize_type_name(type) when is_atom(type), do: normalize_xpath_type(type)

  def normalize_type_name(type) when is_binary(type) do
    case String.split(type, ":", parts: 2) do
      [_prefix, local] -> normalize_xpath_type(String.to_atom(local))
      [local] -> normalize_xpath_type(String.to_atom(local))
    end
  end

  # Normalize XPath underscore-style type names to XSD camelCase
  defp normalize_xpath_type(:date_time), do: :dateTime
  defp normalize_xpath_type(:any_uri), do: :anyURI
  defp normalize_xpath_type(:year_month_duration), do: :yearMonthDuration
  defp normalize_xpath_type(:day_time_duration), do: :dayTimeDuration
  defp normalize_xpath_type(:hex_binary), do: :hexBinary
  defp normalize_xpath_type(:base64_binary), do: :base64Binary
  defp normalize_xpath_type(:g_year), do: :gYear
  defp normalize_xpath_type(:g_year_month), do: :gYearMonth
  defp normalize_xpath_type(:g_month), do: :gMonth
  defp normalize_xpath_type(:g_month_day), do: :gMonthDay
  defp normalize_xpath_type(:g_day), do: :gDay
  defp normalize_xpath_type(:any_type), do: :anyType
  defp normalize_xpath_type(:any_simple_type), do: :anySimpleType
  defp normalize_xpath_type(type), do: type

  @doc """
  Get the full XSD URI for a type.

  ## Example

      iex> FnXML.XsTypes.type_uri(:integer)
      "http://www.w3.org/2001/XMLSchema#integer"
  """
  @spec type_uri(atom()) :: String.t()
  def type_uri(type) when is_atom(type) do
    "#{@xsd_namespace}##{type}"
  end

  @doc """
  Get the qualified name for a type with a prefix.

  ## Example

      iex> FnXML.XsTypes.qualified_name(:integer, "xs")
      "xs:integer"
  """
  @spec qualified_name(atom(), String.t()) :: String.t()
  def qualified_name(type, prefix) when is_atom(type) and is_binary(prefix) do
    "#{prefix}:#{type}"
  end

  # ============================================================================
  # Integer Range Constants
  # ============================================================================

  @doc """
  Get the valid range for an integer type.

  Returns a tuple of `{min, max}` where `:infinity` or `:neg_infinity`
  indicates unbounded.

  ## Examples

      iex> FnXML.XsTypes.range(:byte)
      {-128, 127}

      iex> FnXML.XsTypes.range(:unsignedInt)
      {0, 4_294_967_295}

      iex> FnXML.XsTypes.range(:positiveInteger)
      {1, :infinity}
  """
  @spec range(atom()) :: {integer() | :neg_infinity, integer() | :infinity} | nil
  def range(:byte), do: {-128, 127}
  def range(:short), do: {-32768, 32767}
  def range(:int), do: {-2_147_483_648, 2_147_483_647}
  def range(:long), do: {-9_223_372_036_854_775_808, 9_223_372_036_854_775_807}
  def range(:unsignedByte), do: {0, 255}
  def range(:unsignedShort), do: {0, 65535}
  def range(:unsignedInt), do: {0, 4_294_967_295}
  def range(:unsignedLong), do: {0, 18_446_744_073_709_551_615}
  def range(:positiveInteger), do: {1, :infinity}
  def range(:nonNegativeInteger), do: {0, :infinity}
  def range(:negativeInteger), do: {:neg_infinity, -1}
  def range(:nonPositiveInteger), do: {:neg_infinity, 0}
  def range(:integer), do: {:neg_infinity, :infinity}
  def range(_), do: nil

  # ============================================================================
  # Convenience Type Checks
  # ============================================================================

  @doc """
  Check if a type name is a built-in XSD type.

  ## Example

      iex> FnXML.XsTypes.builtin_type?(:integer)
      true

      iex> FnXML.XsTypes.builtin_type?(:customType)
      false
  """
  @spec builtin_type?(type_name()) :: boolean()
  defdelegate builtin_type?(type), to: Hierarchy

  @doc """
  Check if a type is a numeric type.

  ## Example

      iex> FnXML.XsTypes.numeric_type?(:decimal)
      true

      iex> FnXML.XsTypes.numeric_type?(:string)
      false
  """
  @spec numeric_type?(type_name()) :: boolean()
  defdelegate numeric_type?(type), to: Hierarchy

  @doc """
  Get the base type of a derived type.

  ## Example

      iex> FnXML.XsTypes.base_type(:int)
      :long

      iex> FnXML.XsTypes.base_type(:string)
      nil
  """
  @spec base_type(type_name()) :: type_name() | nil
  defdelegate base_type(type), to: Hierarchy
end
