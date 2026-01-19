defmodule FnXML.XsTypes.Elixir do
  @moduledoc """
  XSD to Elixir type mapping for code generation.

  This module provides utilities for generating Elixir typespecs and
  documentation from XSD types. It's primarily used by code generators
  like WSDL client generators.

  ## Examples

      iex> FnXML.XsTypes.Elixir.to_typespec(:string)
      quote(do: String.t())

      iex> FnXML.XsTypes.Elixir.to_typespec(:integer)
      quote(do: integer())

      iex> FnXML.XsTypes.Elixir.type_description(:dateTime)
      "ISO 8601 datetime"
  """

  @doc """
  Convert an XSD type to an Elixir typespec AST.

  Returns a quoted expression suitable for use in @spec or @type definitions.

  ## Examples

      iex> FnXML.XsTypes.Elixir.to_typespec(:string)
      quote(do: String.t())

      iex> FnXML.XsTypes.Elixir.to_typespec(:integer)
      quote(do: integer())

      iex> FnXML.XsTypes.Elixir.to_typespec(:double)
      quote(do: float() | :infinity | :neg_infinity | :nan)
  """
  @spec to_typespec(atom()) :: Macro.t()
  def to_typespec(:string), do: quote(do: String.t())
  def to_typespec(:normalizedString), do: quote(do: String.t())
  def to_typespec(:token), do: quote(do: String.t())
  def to_typespec(:language), do: quote(do: String.t())
  def to_typespec(:Name), do: quote(do: String.t())
  def to_typespec(:NCName), do: quote(do: String.t())
  def to_typespec(:ID), do: quote(do: String.t())
  def to_typespec(:IDREF), do: quote(do: String.t())
  def to_typespec(:ENTITY), do: quote(do: String.t())
  def to_typespec(:NMTOKEN), do: quote(do: String.t())
  def to_typespec(:anyURI), do: quote(do: String.t())

  def to_typespec(:NMTOKENS), do: quote(do: [String.t()])
  def to_typespec(:IDREFS), do: quote(do: [String.t()])
  def to_typespec(:ENTITIES), do: quote(do: [String.t()])

  def to_typespec(:boolean), do: quote(do: boolean())

  def to_typespec(:integer), do: quote(do: integer())
  def to_typespec(:nonPositiveInteger), do: quote(do: non_pos_integer())
  def to_typespec(:negativeInteger), do: quote(do: neg_integer())
  def to_typespec(:nonNegativeInteger), do: quote(do: non_neg_integer())
  def to_typespec(:positiveInteger), do: quote(do: pos_integer())
  def to_typespec(:long), do: quote(do: integer())
  def to_typespec(:int), do: quote(do: integer())
  def to_typespec(:short), do: quote(do: integer())
  def to_typespec(:byte), do: quote(do: integer())
  def to_typespec(:unsignedLong), do: quote(do: non_neg_integer())
  def to_typespec(:unsignedInt), do: quote(do: non_neg_integer())
  def to_typespec(:unsignedShort), do: quote(do: non_neg_integer())
  def to_typespec(:unsignedByte), do: quote(do: non_neg_integer())

  def to_typespec(:decimal) do
    if Code.ensure_loaded?(Decimal) do
      quote(do: Decimal.t() | float() | integer())
    else
      quote(do: float() | integer())
    end
  end

  def to_typespec(:float), do: quote(do: float() | :infinity | :neg_infinity | :nan)
  def to_typespec(:double), do: quote(do: float() | :infinity | :neg_infinity | :nan)

  def to_typespec(:dateTime), do: quote(do: DateTime.t() | NaiveDateTime.t())
  def to_typespec(:date), do: quote(do: Date.t())
  def to_typespec(:time), do: quote(do: Time.t())
  def to_typespec(:duration), do: quote(do: map() | String.t())
  def to_typespec(:gYearMonth), do: quote(do: String.t())
  def to_typespec(:gYear), do: quote(do: String.t())
  def to_typespec(:gMonthDay), do: quote(do: String.t())
  def to_typespec(:gDay), do: quote(do: String.t())
  def to_typespec(:gMonth), do: quote(do: String.t())

  def to_typespec(:hexBinary), do: quote(do: binary())
  def to_typespec(:base64Binary), do: quote(do: binary())

  def to_typespec(:QName), do: quote(do: {String.t() | nil, String.t()})
  def to_typespec(:NOTATION), do: quote(do: String.t())

  def to_typespec(:anyType), do: quote(do: term())
  def to_typespec(:anySimpleType), do: quote(do: term())

  def to_typespec(_), do: quote(do: term())

  @doc """
  Convert an XSD type to a typespec string.

  ## Examples

      iex> FnXML.XsTypes.Elixir.typespec_string(:string)
      "String.t()"

      iex> FnXML.XsTypes.Elixir.typespec_string(:integer)
      "integer()"
  """
  @spec typespec_string(atom()) :: String.t()
  def typespec_string(type) do
    type
    |> to_typespec()
    |> Macro.to_string()
  end

  @doc """
  Get a human-readable description of an XSD type.

  ## Examples

      iex> FnXML.XsTypes.Elixir.type_description(:dateTime)
      "ISO 8601 datetime"

      iex> FnXML.XsTypes.Elixir.type_description(:integer)
      "Integer with no range limit"
  """
  @spec type_description(atom()) :: String.t()
  def type_description(:string), do: "Unicode string"
  def type_description(:normalizedString), do: "String without CR/LF/Tab"

  def type_description(:token),
    do: "Normalized string without leading/trailing/consecutive spaces"

  def type_description(:language), do: "RFC 3066 language tag (e.g., 'en-US')"
  def type_description(:Name), do: "XML Name"
  def type_description(:NCName), do: "XML NCName (Name without colons)"
  def type_description(:ID), do: "Unique identifier within document"
  def type_description(:IDREF), do: "Reference to an ID"
  def type_description(:IDREFS), do: "Space-separated list of ID references"
  def type_description(:ENTITY), do: "Entity reference"
  def type_description(:ENTITIES), do: "Space-separated list of entity references"
  def type_description(:NMTOKEN), do: "XML name token"
  def type_description(:NMTOKENS), do: "Space-separated list of name tokens"
  def type_description(:anyURI), do: "URI reference"

  def type_description(:boolean), do: "Boolean (true/false/1/0)"

  def type_description(:integer), do: "Integer with no range limit"
  def type_description(:nonPositiveInteger), do: "Integer ≤ 0"
  def type_description(:negativeInteger), do: "Integer < 0"
  def type_description(:nonNegativeInteger), do: "Integer ≥ 0"
  def type_description(:positiveInteger), do: "Integer > 0"
  def type_description(:long), do: "64-bit signed integer (-2^63 to 2^63-1)"
  def type_description(:int), do: "32-bit signed integer (-2^31 to 2^31-1)"
  def type_description(:short), do: "16-bit signed integer (-32768 to 32767)"
  def type_description(:byte), do: "8-bit signed integer (-128 to 127)"
  def type_description(:unsignedLong), do: "64-bit unsigned integer (0 to 2^64-1)"
  def type_description(:unsignedInt), do: "32-bit unsigned integer (0 to 2^32-1)"
  def type_description(:unsignedShort), do: "16-bit unsigned integer (0 to 65535)"
  def type_description(:unsignedByte), do: "8-bit unsigned integer (0 to 255)"

  def type_description(:decimal), do: "Arbitrary precision decimal number"
  def type_description(:float), do: "32-bit IEEE 754 floating point (includes INF, -INF, NaN)"
  def type_description(:double), do: "64-bit IEEE 754 floating point (includes INF, -INF, NaN)"

  def type_description(:dateTime), do: "ISO 8601 datetime"
  def type_description(:date), do: "ISO 8601 date (YYYY-MM-DD)"
  def type_description(:time), do: "ISO 8601 time (HH:MM:SS)"
  def type_description(:duration), do: "ISO 8601 duration (PnYnMnDTnHnMnS)"
  def type_description(:gYearMonth), do: "Year and month (YYYY-MM)"
  def type_description(:gYear), do: "Year (YYYY)"
  def type_description(:gMonthDay), do: "Month and day (--MM-DD)"
  def type_description(:gDay), do: "Day of month (---DD)"
  def type_description(:gMonth), do: "Month (--MM)"

  def type_description(:hexBinary), do: "Hex-encoded binary data"
  def type_description(:base64Binary), do: "Base64-encoded binary data"

  def type_description(:QName), do: "Qualified name (prefix:localName)"
  def type_description(:NOTATION), do: "Notation reference"

  def type_description(:anyType), do: "Any XML content"
  def type_description(:anySimpleType), do: "Any simple type value"

  def type_description(_), do: "Unknown type"

  @doc """
  Get the default Elixir value for an XSD type.

  ## Examples

      iex> FnXML.XsTypes.Elixir.default_value(:string)
      ""

      iex> FnXML.XsTypes.Elixir.default_value(:integer)
      0

      iex> FnXML.XsTypes.Elixir.default_value(:boolean)
      false
  """
  @spec default_value(atom()) :: term()
  def default_value(:string), do: ""
  def default_value(:normalizedString), do: ""
  def default_value(:token), do: ""
  def default_value(:language), do: ""
  def default_value(:Name), do: ""
  def default_value(:NCName), do: ""
  def default_value(:ID), do: ""
  def default_value(:IDREF), do: ""
  def default_value(:ENTITY), do: ""
  def default_value(:NMTOKEN), do: ""
  def default_value(:anyURI), do: ""

  def default_value(:NMTOKENS), do: []
  def default_value(:IDREFS), do: []
  def default_value(:ENTITIES), do: []

  def default_value(:boolean), do: false

  def default_value(type)
      when type in [
             :integer,
             :nonPositiveInteger,
             :negativeInteger,
             :nonNegativeInteger,
             :positiveInteger,
             :long,
             :int,
             :short,
             :byte,
             :unsignedLong,
             :unsignedInt,
             :unsignedShort,
             :unsignedByte
           ] do
    0
  end

  def default_value(:decimal), do: 0
  def default_value(:float), do: 0.0
  def default_value(:double), do: 0.0

  def default_value(:dateTime), do: nil
  def default_value(:date), do: nil
  def default_value(:time), do: nil
  def default_value(:duration), do: %{}
  def default_value(:gYearMonth), do: ""
  def default_value(:gYear), do: ""
  def default_value(:gMonthDay), do: ""
  def default_value(:gDay), do: ""
  def default_value(:gMonth), do: ""

  def default_value(:hexBinary), do: <<>>
  def default_value(:base64Binary), do: <<>>

  def default_value(:QName), do: {nil, ""}
  def default_value(:NOTATION), do: ""

  def default_value(_), do: nil

  @doc """
  Check if a type maps to a nullable Elixir type.

  ## Examples

      iex> FnXML.XsTypes.Elixir.nullable?(:dateTime)
      true

      iex> FnXML.XsTypes.Elixir.nullable?(:string)
      false
  """
  @spec nullable?(atom()) :: boolean()
  def nullable?(type) when type in [:dateTime, :date, :time], do: true
  def nullable?(_), do: false

  @doc """
  Get the Elixir module associated with an XSD type, if any.

  ## Examples

      iex> FnXML.XsTypes.Elixir.type_module(:dateTime)
      DateTime

      iex> FnXML.XsTypes.Elixir.type_module(:string)
      nil
  """
  @spec type_module(atom()) :: module() | nil
  def type_module(:dateTime), do: DateTime
  def type_module(:date), do: Date
  def type_module(:time), do: Time

  def type_module(:decimal) do
    if Code.ensure_loaded?(Decimal), do: Decimal, else: nil
  end

  def type_module(_), do: nil
end
