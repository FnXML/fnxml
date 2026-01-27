defmodule FnXML.Namespaces.QName do
  @moduledoc """
  QName (Qualified Name) parsing and validation for XML Namespaces.

  From the W3C spec:
  - [7]  QName     ::= PrefixedName | UnprefixedName
  - [8]  PrefixedName ::= Prefix ':' LocalPart
  - [9]  UnprefixedName ::= LocalPart
  - [10] Prefix    ::= NCName
  - [11] LocalPart ::= NCName
  - [4]  NCName    ::= Name - (Char* ':' Char*)  ; Name without colons
  """

  @type t :: {prefix :: String.t() | nil, local :: String.t()}

  @doc """
  Parse a qualified name into {prefix, local_part}.

  Returns `{nil, name}` for unprefixed names, `{prefix, local}` for prefixed names.

  ## Examples

      iex> FnXML.Namespaces.QName.parse("foo")
      {nil, "foo"}

      iex> FnXML.Namespaces.QName.parse("ns:element")
      {"ns", "element"}

      iex> FnXML.Namespaces.QName.parse("xmlns:foo")
      {"xmlns", "foo"}
  """
  @spec parse(String.t()) :: t()
  def parse(name) when is_binary(name) do
    case :binary.split(name, ":") do
      [local] -> {nil, local}
      [prefix, local] -> {prefix, local}
    end
  end

  @doc """
  Check if a name is a valid NCName (Non-Colonized Name).

  NCName is an XML Name that contains no colons. This is used for:
  - Local parts of qualified names
  - Prefixes
  - Entity names, PI targets, notation names

  ## Examples

      iex> FnXML.Namespaces.QName.valid_ncname?("foo")
      true

      iex> FnXML.Namespaces.QName.valid_ncname?("foo:bar")
      false

      iex> FnXML.Namespaces.QName.valid_ncname?("")
      false
  """
  @spec valid_ncname?(String.t()) :: boolean()
  def valid_ncname?(name) when is_binary(name) do
    name != "" and
      not String.contains?(name, ":") and
      valid_ncname_start?(name) and
      valid_ncname_chars?(name)
  end

  @doc """
  Check if a name is a valid QName.

  A QName is either:
  - An unprefixed NCName
  - A prefixed name where both prefix and local part are valid NCNames

  ## Examples

      iex> FnXML.Namespaces.QName.valid_qname?("foo")
      true

      iex> FnXML.Namespaces.QName.valid_qname?("ns:element")
      true

      iex> FnXML.Namespaces.QName.valid_qname?("ns:")
      false

      iex> FnXML.Namespaces.QName.valid_qname?(":element")
      false

      iex> FnXML.Namespaces.QName.valid_qname?("a:b:c")
      false
  """
  @spec valid_qname?(String.t()) :: boolean()
  def valid_qname?(name) when is_binary(name) do
    case String.split(name, ":", parts: :infinity) do
      [local] ->
        # Unprefixed name - must be valid NCName
        valid_ncname?(local)

      [prefix, local] ->
        # Prefixed name - both parts must be valid NCNames
        valid_ncname?(prefix) and valid_ncname?(local)

      _ ->
        # More than one colon - invalid
        false
    end
  end

  @doc """
  Check if a name is a namespace declaration attribute name.

  Returns:
  - `{:default, nil}` for "xmlns"
  - `{:prefix, prefix}` for "xmlns:prefix"
  - `false` for other names

  ## Examples

      iex> FnXML.Namespaces.QName.namespace_declaration?("xmlns")
      {:default, nil}

      iex> FnXML.Namespaces.QName.namespace_declaration?("xmlns:foo")
      {:prefix, "foo"}

      iex> FnXML.Namespaces.QName.namespace_declaration?("foo")
      false
  """
  @spec namespace_declaration?(String.t()) :: {:default, nil} | {:prefix, String.t()} | false
  def namespace_declaration?("xmlns"), do: {:default, nil}

  def namespace_declaration?("xmlns:" <> prefix) when prefix != "" do
    if valid_ncname?(prefix) do
      {:prefix, prefix}
    else
      false
    end
  end

  def namespace_declaration?(_), do: false

  @doc """
  Get the local part of a name (strips prefix if present).

  ## Examples

      iex> FnXML.Namespaces.QName.local_part("foo")
      "foo"

      iex> FnXML.Namespaces.QName.local_part("ns:element")
      "element"
  """
  @spec local_part(String.t()) :: String.t()
  def local_part(name) do
    {_, local} = parse(name)
    local
  end

  @doc """
  Get the prefix of a name (nil if unprefixed).

  ## Examples

      iex> FnXML.Namespaces.QName.prefix("foo")
      nil

      iex> FnXML.Namespaces.QName.prefix("ns:element")
      "ns"
  """
  @spec prefix(String.t()) :: String.t() | nil
  def prefix(name) do
    {prefix, _} = parse(name)
    prefix
  end

  @doc """
  Check if a name is prefixed.

  ## Examples

      iex> FnXML.Namespaces.QName.prefixed?("foo")
      false

      iex> FnXML.Namespaces.QName.prefixed?("ns:element")
      true
  """
  @spec prefixed?(String.t()) :: boolean()
  def prefixed?(name), do: String.contains?(name, ":")

  # NCName start character validation
  # Per XML spec, NameStartChar minus ':'
  # NameStartChar ::= ":" | [A-Z] | "_" | [a-z] | [#xC0-#xD6] | [#xD8-#xF6] | ...
  defp valid_ncname_start?(<<char::utf8, _rest::binary>>) do
    ncname_start_char?(char)
  end

  defp valid_ncname_start?(_), do: false

  # NCName character validation (all chars after first)
  defp valid_ncname_chars?(name) do
    name
    |> String.to_charlist()
    |> Enum.all?(&ncname_char?/1)
  end

  # NameStartChar (excluding ':')
  # [A-Z] | "_" | [a-z] | [#xC0-#xD6] | [#xD8-#xF6] | [#xF8-#x2FF] |
  # [#x370-#x37D] | [#x37F-#x1FFF] | [#x200C-#x200D] | [#x2070-#x218F] |
  # [#x2C00-#x2FEF] | [#x3001-#xD7FF] | [#xF900-#xFDCF] | [#xFDF0-#xFFFD] |
  # [#x10000-#xEFFFF]
  defp ncname_start_char?(char) do
    (char >= ?A and char <= ?Z) or
      char == ?_ or
      (char >= ?a and char <= ?z) or
      (char >= 0xC0 and char <= 0xD6) or
      (char >= 0xD8 and char <= 0xF6) or
      (char >= 0xF8 and char <= 0x2FF) or
      (char >= 0x370 and char <= 0x37D) or
      (char >= 0x37F and char <= 0x1FFF) or
      (char >= 0x200C and char <= 0x200D) or
      (char >= 0x2070 and char <= 0x218F) or
      (char >= 0x2C00 and char <= 0x2FEF) or
      (char >= 0x3001 and char <= 0xD7FF) or
      (char >= 0xF900 and char <= 0xFDCF) or
      (char >= 0xFDF0 and char <= 0xFFFD) or
      (char >= 0x10000 and char <= 0xEFFFF)
  end

  # NameChar (excluding ':')
  # NameStartChar | "-" | "." | [0-9] | #xB7 | [#x0300-#x036F] | [#x203F-#x2040]
  defp ncname_char?(char) do
    ncname_start_char?(char) or
      char == ?- or
      char == ?. or
      (char >= ?0 and char <= ?9) or
      char == 0xB7 or
      (char >= 0x0300 and char <= 0x036F) or
      (char >= 0x203F and char <= 0x2040)
  end
end
