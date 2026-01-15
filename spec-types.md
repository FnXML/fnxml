# FnXML.XsTypes Specification

A unified XSD type library for the Elixir XML ecosystem.

## Overview

This module consolidates XSD (XML Schema Definition) type handling across fnxml, fnsoap, fnxsd, and fnxpath into a single, comprehensive implementation.

## Design Goals

1. **Single Source of Truth** - One authoritative implementation of XSD types
2. **Bidirectional Conversion** - Parse strings to Elixir values and encode back
3. **Validation** - Validate string representations against type constraints
4. **Facet Support** - Apply constraining facets (length, pattern, min/max, etc.)
5. **Type Hierarchy** - Model XSD type derivation relationships
6. **Minimal Dependencies** - Optional Decimal library support with float fallback
7. **Composable API** - Functions that work well in pipelines

---

## Module Structure

```
FnXML.XsTypes
├── FnXML.XsTypes           # Main API module
├── FnXML.XsTypes.Primitive # Primitive type definitions
├── FnXML.XsTypes.Derived   # Derived type definitions
├── FnXML.XsTypes.Facets    # Facet validation
├── FnXML.XsTypes.Hierarchy # Type hierarchy and relationships
└── FnXML.XsTypes.Elixir    # Elixir type mapping for codegen
```

---

## Supported Types

### Primitive Types (19 types)

| Type | Elixir Representation | Notes |
|------|----------------------|-------|
| `string` | `String.t()` | Unicode string |
| `boolean` | `boolean()` | true/false/1/0 |
| `decimal` | `Decimal.t() \| float()` | Arbitrary precision |
| `float` | `float() \| :nan \| :infinity \| :neg_infinity` | 32-bit IEEE 754 |
| `double` | `float() \| :nan \| :infinity \| :neg_infinity` | 64-bit IEEE 754 |
| `duration` | `String.t()` | ISO 8601 duration |
| `dateTime` | `DateTime.t() \| NaiveDateTime.t()` | ISO 8601 |
| `time` | `Time.t()` | ISO 8601 time |
| `date` | `Date.t()` | ISO 8601 date |
| `gYearMonth` | `String.t()` | YYYY-MM |
| `gYear` | `String.t()` | YYYY |
| `gMonthDay` | `String.t()` | --MM-DD |
| `gDay` | `String.t()` | ---DD |
| `gMonth` | `String.t()` | --MM |
| `hexBinary` | `binary()` | Hex-encoded bytes |
| `base64Binary` | `binary()` | Base64-encoded bytes |
| `anyURI` | `String.t()` | URI reference |
| `QName` | `{namespace, local_name}` | Qualified name |
| `NOTATION` | `String.t()` | Notation reference |

### Derived Types (25 types)

| Type | Base Type | Constraints |
|------|-----------|-------------|
| `normalizedString` | string | No CR/LF/Tab |
| `token` | normalizedString | No leading/trailing spaces, no consecutive spaces |
| `language` | token | RFC 3066 language tag |
| `NMTOKEN` | token | XML name token |
| `NMTOKENS` | list of NMTOKEN | Space-separated |
| `Name` | token | XML name |
| `NCName` | Name | No colons |
| `ID` | NCName | Unique identifier |
| `IDREF` | NCName | Reference to ID |
| `IDREFS` | list of IDREF | Space-separated |
| `ENTITY` | NCName | Entity reference |
| `ENTITIES` | list of ENTITY | Space-separated |
| `integer` | decimal | No fractional part |
| `nonPositiveInteger` | integer | ≤ 0 |
| `negativeInteger` | nonPositiveInteger | < 0 |
| `long` | integer | -2^63 to 2^63-1 |
| `int` | long | -2^31 to 2^31-1 |
| `short` | int | -32768 to 32767 |
| `byte` | short | -128 to 127 |
| `nonNegativeInteger` | integer | ≥ 0 |
| `unsignedLong` | nonNegativeInteger | 0 to 2^64-1 |
| `unsignedInt` | unsignedLong | 0 to 2^32-1 |
| `unsignedShort` | unsignedInt | 0 to 65535 |
| `unsignedByte` | unsignedShort | 0 to 255 |
| `positiveInteger` | nonNegativeInteger | > 0 |

---

## Core API

### Type Validation

```elixir
@doc """
Validate a string value against an XSD type.

Returns `:ok` if valid, `{:error, reason}` otherwise.

## Examples

    iex> FnXML.XsTypes.valid?("42", :integer)
    true

    iex> FnXML.XsTypes.valid?("not_a_number", :integer)
    false

    iex> FnXML.XsTypes.validate("42", :integer)
    :ok

    iex> FnXML.XsTypes.validate("abc", :integer)
    {:error, {:invalid_value, :integer, "abc"}}
"""
@spec validate(String.t(), type_name()) :: :ok | {:error, reason()}
@spec valid?(String.t(), type_name()) :: boolean()
```

### Parsing (String → Elixir Value)

```elixir
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

    iex> FnXML.XsTypes.parse!("42", :integer)
    42
"""
@spec parse(String.t(), type_name()) :: {:ok, value()} | {:error, reason()}
@spec parse!(String.t(), type_name()) :: value() | no_return()
```

### Encoding (Elixir Value → String)

```elixir
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

    iex> FnXML.XsTypes.encode!(42, :integer)
    "42"
"""
@spec encode(value(), type_name()) :: {:ok, String.t()} | {:error, reason()}
@spec encode!(value(), type_name()) :: String.t() | no_return()
```

### Type Inference

```elixir
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
```

### Whitespace Normalization

```elixir
@doc """
Normalize whitespace according to type rules.

- `:preserve` - Keep all whitespace (string)
- `:replace` - Replace CR/LF/Tab with space (normalizedString)
- `:collapse` - Replace + trim + collapse consecutive spaces (token, etc.)

## Examples

    iex> FnXML.XsTypes.normalize_whitespace("  hello  world  ", :token)
    "hello world"

    iex> FnXML.XsTypes.normalize_whitespace("hello\nworld", :normalizedString)
    "hello world"

    iex> FnXML.XsTypes.normalize_whitespace("hello\nworld", :string)
    "hello\nworld"
"""
@spec normalize_whitespace(String.t(), type_name()) :: String.t()
@spec whitespace_mode(type_name()) :: :preserve | :replace | :collapse
```

---

## Facet Validation

```elixir
@doc """
Validate a value against constraining facets.

## Supported Facets

- `length` - Exact length
- `minLength` - Minimum length
- `maxLength` - Maximum length
- `pattern` - Regex pattern (XSD regex syntax)
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
    ...>   {:minInclusive, 0},
    ...>   {:maxInclusive, 100}
    ...> ])
    :ok

    iex> FnXML.XsTypes.validate_with_facets("abc123", :string, [
    ...>   {:pattern, "[a-z]+[0-9]+"}
    ...> ])
    :ok
"""
@spec validate_with_facets(String.t(), type_name(), [facet()]) :: :ok | {:error, reason()}

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
```

---

## Type Hierarchy

```elixir
@doc """
Query the XSD type hierarchy.

## Examples

    iex> FnXML.XsTypes.Hierarchy.builtin_type?("integer")
    true

    iex> FnXML.XsTypes.Hierarchy.primitive_type?("integer")
    false

    iex> FnXML.XsTypes.Hierarchy.base_type(:integer)
    :decimal

    iex> FnXML.XsTypes.Hierarchy.derived_from?(:int, :integer)
    true

    iex> FnXML.XsTypes.Hierarchy.numeric_type?(:decimal)
    true

    iex> FnXML.XsTypes.Hierarchy.list_types()
    [:NMTOKENS, :IDREFS, :ENTITIES]
"""
@spec builtin_type?(type_name()) :: boolean()
@spec primitive_type?(type_name()) :: boolean()
@spec derived_type?(type_name()) :: boolean()
@spec base_type(type_name()) :: type_name() | nil
@spec derived_from?(type_name(), type_name()) :: boolean()
@spec numeric_type?(type_name()) :: boolean()
@spec string_type?(type_name()) :: boolean()
@spec date_time_type?(type_name()) :: boolean()
@spec binary_type?(type_name()) :: boolean()
@spec list_types() :: [type_name()]
```

---

## Elixir Type Mapping (for Code Generation)

```elixir
@doc """
Map XSD types to Elixir types for code generation.

## Examples

    iex> FnXML.XsTypes.Elixir.to_typespec(:string)
    quote(do: String.t())

    iex> FnXML.XsTypes.Elixir.to_typespec(:integer)
    quote(do: integer())

    iex> FnXML.XsTypes.Elixir.to_typespec(:dateTime)
    quote(do: DateTime.t())

    iex> FnXML.XsTypes.Elixir.type_description(:dateTime)
    "ISO 8601 datetime"
"""
@spec to_typespec(type_name()) :: Macro.t()
@spec type_description(type_name()) :: String.t()
```

---

## Type Name Handling

```elixir
@type type_name :: atom() | String.t()

@doc """
Normalize type names (handle prefixes, atoms, strings).

## Examples

    iex> FnXML.XsTypes.normalize_type_name("xs:integer")
    :integer

    iex> FnXML.XsTypes.normalize_type_name("xsd:string")
    :string

    iex> FnXML.XsTypes.normalize_type_name(:integer)
    :integer

    iex> FnXML.XsTypes.type_uri(:integer)
    "http://www.w3.org/2001/XMLSchema#integer"

    iex> FnXML.XsTypes.qualified_name(:integer, "xs")
    "xs:integer"
"""
@spec normalize_type_name(type_name()) :: atom()
@spec type_uri(atom()) :: String.t()
@spec qualified_name(atom(), String.t()) :: String.t()
```

---

## Special Value Handling

### Float/Double Special Values

```elixir
# Parsing
FnXML.XsTypes.parse("INF", :double)    # {:ok, :infinity}
FnXML.XsTypes.parse("-INF", :double)   # {:ok, :neg_infinity}
FnXML.XsTypes.parse("NaN", :double)    # {:ok, :nan}

# Encoding
FnXML.XsTypes.encode(:infinity, :double)      # {:ok, "INF"}
FnXML.XsTypes.encode(:neg_infinity, :double)  # {:ok, "-INF"}
FnXML.XsTypes.encode(:nan, :double)           # {:ok, "NaN"}

# Comparison (for facets)
FnXML.XsTypes.compare(:nan, 0.0)  # :incomparable
```

### QName Handling

```elixir
# Parsing
FnXML.XsTypes.parse("xs:string", :QName)      # {:ok, {"xs", "string"}}
FnXML.XsTypes.parse("localOnly", :QName)      # {:ok, {nil, "localOnly"}}

# Encoding
FnXML.XsTypes.encode({"xs", "string"}, :QName)  # {:ok, "xs:string"}
FnXML.XsTypes.encode({nil, "local"}, :QName)    # {:ok, "local"}
```

### Duration Handling

```elixir
# Parsing - returns structured data
FnXML.XsTypes.parse("P1Y2M3DT4H5M6S", :duration)
# {:ok, %{years: 1, months: 2, days: 3, hours: 4, minutes: 5, seconds: 6}}

FnXML.XsTypes.parse("-P1D", :duration)
# {:ok, %{negative: true, days: 1}}
```

---

## Integer Range Constants

```elixir
@doc """
Integer type range boundaries.
"""
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
```

---

## Namespace Constants

```elixir
@xsd_namespace "http://www.w3.org/2001/XMLSchema"
@xsi_namespace "http://www.w3.org/2001/XMLSchema-instance"

def xsd_namespace, do: @xsd_namespace
def xsi_namespace, do: @xsi_namespace
```

---

## Error Types

```elixir
@type reason ::
  {:invalid_value, type_name(), String.t()}
  | {:out_of_range, type_name(), value()}
  | {:facet_violation, facet_type(), expected: term(), got: term()}
  | {:invalid_pattern, pattern: String.t(), value: String.t()}
  | {:invalid_length, expected: non_neg_integer(), got: non_neg_integer()}
  | {:whitespace_violation, expected: :replace | :collapse, got: String.t()}
  | {:unknown_type, String.t()}
```

---

## Usage Examples

### Basic Validation and Parsing

```elixir
alias FnXML.XsTypes

# Validate string representations
:ok = XsTypes.validate("42", :integer)
{:error, _} = XsTypes.validate("abc", :integer)

# Parse to Elixir values
{:ok, 42} = XsTypes.parse("42", :integer)
{:ok, true} = XsTypes.parse("1", :boolean)
{:ok, ~D[2024-01-15]} = XsTypes.parse("2024-01-15", :date)

# Encode back to strings
{:ok, "42"} = XsTypes.encode(42, :integer)
{:ok, "true"} = XsTypes.encode(true, :boolean)
```

### Type-Safe Conversion Pipeline

```elixir
# Parse, process, encode pipeline
"100"
|> XsTypes.parse!(:integer)
|> then(&(&1 * 2))
|> XsTypes.encode!(:integer)
# => "200"
```

### Facet Validation

```elixir
# Validate with constraints
:ok = XsTypes.validate_with_facets("hello", :string, [
  {:minLength, 1},
  {:maxLength, 100},
  {:pattern, "[a-z]+"}
])

# Integer with range
:ok = XsTypes.validate_with_facets("50", :integer, [
  {:minInclusive, "0"},
  {:maxInclusive, "100"}
])
```

### Code Generation Support

```elixir
alias FnXML.XsTypes.Elixir, as: XsElixir

# Generate typespec for XSD type
XsElixir.to_typespec(:integer)  # quote(do: integer())
XsElixir.to_typespec(:dateTime) # quote(do: DateTime.t())

# For WSDL/code generators
def generate_param_spec(xsd_type) do
  XsElixir.to_typespec(xsd_type)
end
```

---

## Integration Points

### FnXSD (Schema Validation)

```elixir
# FnXSD can use XsTypes for built-in type validation
defmodule FnXSD.Validator do
  def validate_simple_type(value, "xs:integer") do
    FnXML.XsTypes.validate(value, :integer)
  end
end
```

### FnSOAP (Encoding/Decoding)

```elixir
# FnSOAP can use XsTypes for type conversion
defmodule FnSOAP.Encoding do
  def decode_element(text, "xsd:int") do
    FnXML.XsTypes.parse(text, :int)
  end

  def encode_element(value, "xsd:int") do
    FnXML.XsTypes.encode(value, :int)
  end
end
```

### FnXPath (Atomic Types)

```elixir
# FnXPath can use XsTypes for type constructors
defmodule FnXPath.Functions do
  def xs_integer(value) when is_binary(value) do
    case FnXML.XsTypes.parse(value, :integer) do
      {:ok, int} -> {:ok, %Atomic{type: :integer, value: int}}
      error -> error
    end
  end
end
```

---

## Configuration

```elixir
# In config.exs (optional)
config :fnxml, :xs_types,
  # Use Decimal library for decimal type (default: true if available)
  use_decimal: true,

  # Strict mode - reject values that don't exactly match type
  strict: false,

  # Custom type extensions
  custom_types: []
```

---

## Testing Considerations

The module should include comprehensive tests covering:

1. All 44 built-in types
2. All facet types
3. Edge cases (empty strings, whitespace, special values)
4. Round-trip parsing/encoding
5. Error conditions
6. Performance with large values

---

## Migration Path

### From FnXSD.Types

```elixir
# Before
FnXSD.Types.validate(value, "integer")
FnXSD.Types.parse(value, "integer")

# After
FnXML.XsTypes.validate(value, :integer)
FnXML.XsTypes.parse(value, :integer)
```

### From FnSOAP.Encoding.Types

```elixir
# Before
FnSOAP.Encoding.Types.decode(text, :int)
FnSOAP.Encoding.Types.encode(value, :int)

# After
FnXML.XsTypes.parse(text, :int)
FnXML.XsTypes.encode(value, :int)
```

### From FnXPath.Types.Atomic

```elixir
# XPath atomic values will wrap XsTypes
# Internal implementation detail - API unchanged
```

---

## Version History

- **1.0.0** - Initial release with full XSD 1.0 type support
