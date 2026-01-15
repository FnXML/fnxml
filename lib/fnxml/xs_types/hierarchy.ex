defmodule FnXML.XsTypes.Hierarchy do
  @moduledoc """
  XSD type hierarchy and relationships.

  This module models the XSD type derivation hierarchy, allowing queries
  about type relationships, base types, and type categories.

  ## Type Categories

  - **Primitive Types** - The 19 fundamental XSD types
  - **Derived Types** - Types derived by restriction from other types
  - **List Types** - Types whose values are space-separated lists
  - **Special Types** - anyType, anySimpleType

  ## Type Derivation

  All XSD types form a hierarchy rooted at `anyType`:

      anyType
      └── anySimpleType
          ├── string
          │   └── normalizedString
          │       └── token
          │           ├── language
          │           ├── NMTOKEN
          │           ├── Name
          │           │   └── NCName
          │           │       ├── ID
          │           │       ├── IDREF
          │           │       └── ENTITY
          │           └── ...
          ├── decimal
          │   └── integer
          │       ├── long → int → short → byte
          │       ├── nonPositiveInteger → negativeInteger
          │       └── nonNegativeInteger
          │           ├── unsignedLong → unsignedInt → ...
          │           └── positiveInteger
          ├── boolean
          ├── float
          ├── double
          ├── duration
          ├── dateTime
          └── ...
  """

  @primitive_types [
    :string,
    :boolean,
    :decimal,
    :float,
    :double,
    :duration,
    :dateTime,
    :time,
    :date,
    :gYearMonth,
    :gYear,
    :gMonthDay,
    :gDay,
    :gMonth,
    :hexBinary,
    :base64Binary,
    :anyURI,
    :QName,
    :NOTATION
  ]

  @derived_types [
    :normalizedString,
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
    :ENTITIES,
    :integer,
    :nonPositiveInteger,
    :negativeInteger,
    :long,
    :int,
    :short,
    :byte,
    :nonNegativeInteger,
    :unsignedLong,
    :unsignedInt,
    :unsignedShort,
    :unsignedByte,
    :positiveInteger,
    # XSD 1.1 / XPath 2.0+ duration subtypes
    :yearMonthDuration,
    :dayTimeDuration
  ]

  @special_types [:anyType, :anySimpleType]

  @list_types [:NMTOKENS, :IDREFS, :ENTITIES]

  @numeric_types [
    :decimal,
    :float,
    :double,
    :integer,
    :nonPositiveInteger,
    :negativeInteger,
    :long,
    :int,
    :short,
    :byte,
    :nonNegativeInteger,
    :unsignedLong,
    :unsignedInt,
    :unsignedShort,
    :unsignedByte,
    :positiveInteger
  ]

  @string_types [
    :string,
    :normalizedString,
    :token,
    :language,
    :NMTOKEN,
    :Name,
    :NCName,
    :ID,
    :IDREF,
    :ENTITY,
    :anyURI
  ]

  @date_time_types [
    :duration,
    :dateTime,
    :time,
    :date,
    :gYearMonth,
    :gYear,
    :gMonthDay,
    :gDay,
    :gMonth,
    # XSD 1.1 / XPath 2.0+ duration subtypes
    :yearMonthDuration,
    :dayTimeDuration
  ]

  @binary_types [:hexBinary, :base64Binary]

  # Type derivation hierarchy (child -> parent)
  @type_hierarchy %{
    # String-derived types
    normalizedString: :string,
    token: :normalizedString,
    language: :token,
    NMTOKEN: :token,
    NMTOKENS: :NMTOKEN,
    Name: :token,
    NCName: :Name,
    ID: :NCName,
    IDREF: :NCName,
    IDREFS: :IDREF,
    ENTITY: :NCName,
    ENTITIES: :ENTITY,

    # Decimal-derived types
    integer: :decimal,
    nonPositiveInteger: :integer,
    negativeInteger: :nonPositiveInteger,
    long: :integer,
    int: :long,
    short: :int,
    byte: :short,
    nonNegativeInteger: :integer,
    unsignedLong: :nonNegativeInteger,
    unsignedInt: :unsignedLong,
    unsignedShort: :unsignedInt,
    unsignedByte: :unsignedShort,
    positiveInteger: :nonNegativeInteger,

    # Duration-derived types (XSD 1.1 / XPath 2.0+)
    yearMonthDuration: :duration,
    dayTimeDuration: :duration
  }

  # ============================================================================
  # Type Category Checks
  # ============================================================================

  @doc """
  Check if a type is a built-in XSD type.

  ## Examples

      iex> FnXML.XsTypes.Hierarchy.builtin_type?(:integer)
      true

      iex> FnXML.XsTypes.Hierarchy.builtin_type?(:customType)
      false
  """
  @spec builtin_type?(atom()) :: boolean()
  def builtin_type?(type) when is_atom(type) do
    type in @primitive_types or type in @derived_types or type in @special_types
  end

  def builtin_type?(type) when is_binary(type) do
    builtin_type?(String.to_atom(type))
  end

  @doc """
  Check if a type is a primitive XSD type.

  ## Examples

      iex> FnXML.XsTypes.Hierarchy.primitive_type?(:string)
      true

      iex> FnXML.XsTypes.Hierarchy.primitive_type?(:integer)
      false
  """
  @spec primitive_type?(atom()) :: boolean()
  def primitive_type?(type) when is_atom(type), do: type in @primitive_types
  def primitive_type?(type) when is_binary(type), do: primitive_type?(String.to_atom(type))

  @doc """
  Check if a type is a derived XSD type.

  ## Examples

      iex> FnXML.XsTypes.Hierarchy.derived_type?(:integer)
      true

      iex> FnXML.XsTypes.Hierarchy.derived_type?(:string)
      false
  """
  @spec derived_type?(atom()) :: boolean()
  def derived_type?(type) when is_atom(type), do: type in @derived_types
  def derived_type?(type) when is_binary(type), do: derived_type?(String.to_atom(type))

  @doc """
  Check if a type is a numeric type.

  ## Examples

      iex> FnXML.XsTypes.Hierarchy.numeric_type?(:decimal)
      true

      iex> FnXML.XsTypes.Hierarchy.numeric_type?(:integer)
      true

      iex> FnXML.XsTypes.Hierarchy.numeric_type?(:string)
      false
  """
  @spec numeric_type?(atom()) :: boolean()
  def numeric_type?(type) when is_atom(type), do: type in @numeric_types
  def numeric_type?(type) when is_binary(type), do: numeric_type?(String.to_atom(type))

  @doc """
  Check if a type is a string-derived type.

  ## Examples

      iex> FnXML.XsTypes.Hierarchy.string_type?(:token)
      true

      iex> FnXML.XsTypes.Hierarchy.string_type?(:integer)
      false
  """
  @spec string_type?(atom()) :: boolean()
  def string_type?(type) when is_atom(type), do: type in @string_types
  def string_type?(type) when is_binary(type), do: string_type?(String.to_atom(type))

  @doc """
  Check if a type is a date/time type.

  ## Examples

      iex> FnXML.XsTypes.Hierarchy.date_time_type?(:dateTime)
      true

      iex> FnXML.XsTypes.Hierarchy.date_time_type?(:string)
      false
  """
  @spec date_time_type?(atom()) :: boolean()
  def date_time_type?(type) when is_atom(type), do: type in @date_time_types
  def date_time_type?(type) when is_binary(type), do: date_time_type?(String.to_atom(type))

  @doc """
  Check if a type is a binary type.

  ## Examples

      iex> FnXML.XsTypes.Hierarchy.binary_type?(:hexBinary)
      true

      iex> FnXML.XsTypes.Hierarchy.binary_type?(:string)
      false
  """
  @spec binary_type?(atom()) :: boolean()
  def binary_type?(type) when is_atom(type), do: type in @binary_types
  def binary_type?(type) when is_binary(type), do: binary_type?(String.to_atom(type))

  @doc """
  Check if a type is a list type (space-separated values).

  ## Examples

      iex> FnXML.XsTypes.Hierarchy.list_type?(:NMTOKENS)
      true

      iex> FnXML.XsTypes.Hierarchy.list_type?(:NMTOKEN)
      false
  """
  @spec list_type?(atom()) :: boolean()
  def list_type?(type) when is_atom(type), do: type in @list_types
  def list_type?(type) when is_binary(type), do: list_type?(String.to_atom(type))

  # ============================================================================
  # Type Hierarchy Queries
  # ============================================================================

  @doc """
  Get the base (parent) type of a derived type.

  Returns `nil` for primitive types.

  ## Examples

      iex> FnXML.XsTypes.Hierarchy.base_type(:integer)
      :decimal

      iex> FnXML.XsTypes.Hierarchy.base_type(:int)
      :long

      iex> FnXML.XsTypes.Hierarchy.base_type(:string)
      nil
  """
  @spec base_type(atom()) :: atom() | nil
  def base_type(type) when is_atom(type) do
    Map.get(@type_hierarchy, type)
  end

  def base_type(type) when is_binary(type), do: base_type(String.to_atom(type))

  @doc """
  Check if a type is derived from another type (directly or transitively).

  ## Examples

      iex> FnXML.XsTypes.Hierarchy.derived_from?(:int, :integer)
      true

      iex> FnXML.XsTypes.Hierarchy.derived_from?(:int, :decimal)
      true

      iex> FnXML.XsTypes.Hierarchy.derived_from?(:int, :string)
      false
  """
  @spec derived_from?(atom(), atom()) :: boolean()
  def derived_from?(type, ancestor) when is_atom(type) and is_atom(ancestor) do
    case base_type(type) do
      nil -> false
      ^ancestor -> true
      parent -> derived_from?(parent, ancestor)
    end
  end

  @doc """
  Get the primitive type that a type ultimately derives from.

  ## Examples

      iex> FnXML.XsTypes.Hierarchy.primitive_base(:int)
      :decimal

      iex> FnXML.XsTypes.Hierarchy.primitive_base(:NCName)
      :string

      iex> FnXML.XsTypes.Hierarchy.primitive_base(:string)
      :string
  """
  @spec primitive_base(atom()) :: atom()
  def primitive_base(type) when is_atom(type) do
    if primitive_type?(type) do
      type
    else
      case base_type(type) do
        nil -> type
        parent -> primitive_base(parent)
      end
    end
  end

  @doc """
  Get the derivation chain from a type up to its primitive base.

  ## Examples

      iex> FnXML.XsTypes.Hierarchy.derivation_chain(:int)
      [:int, :long, :integer, :decimal]

      iex> FnXML.XsTypes.Hierarchy.derivation_chain(:string)
      [:string]
  """
  @spec derivation_chain(atom()) :: [atom()]
  def derivation_chain(type) when is_atom(type) do
    do_derivation_chain(type, [type])
  end

  defp do_derivation_chain(type, acc) do
    case base_type(type) do
      nil -> Enum.reverse(acc)
      parent -> do_derivation_chain(parent, [parent | acc])
    end
  end

  @doc """
  Get the item type for a list type.

  ## Examples

      iex> FnXML.XsTypes.Hierarchy.item_type(:NMTOKENS)
      :NMTOKEN

      iex> FnXML.XsTypes.Hierarchy.item_type(:IDREFS)
      :IDREF

      iex> FnXML.XsTypes.Hierarchy.item_type(:string)
      nil
  """
  @spec item_type(atom()) :: atom() | nil
  def item_type(:NMTOKENS), do: :NMTOKEN
  def item_type(:IDREFS), do: :IDREF
  def item_type(:ENTITIES), do: :ENTITY
  def item_type(_), do: nil

  # ============================================================================
  # Type Lists
  # ============================================================================

  @doc """
  List all primitive types.
  """
  @spec primitive_types() :: [atom()]
  def primitive_types, do: @primitive_types

  @doc """
  List all derived types.
  """
  @spec derived_types() :: [atom()]
  def derived_types, do: @derived_types

  @doc """
  List all built-in types (primitive + derived + special).
  """
  @spec builtin_types() :: [atom()]
  def builtin_types, do: @primitive_types ++ @derived_types ++ @special_types

  @doc """
  List all list types.
  """
  @spec list_types() :: [atom()]
  def list_types, do: @list_types

  @doc """
  List all numeric types.
  """
  @spec numeric_types() :: [atom()]
  def numeric_types, do: @numeric_types

  @doc """
  List all string-derived types.
  """
  @spec string_types() :: [atom()]
  def string_types, do: @string_types

  @doc """
  List all date/time types.
  """
  @spec date_time_types() :: [atom()]
  def date_time_types, do: @date_time_types

  @doc """
  List all binary types.
  """
  @spec binary_types() :: [atom()]
  def binary_types, do: @binary_types
end
