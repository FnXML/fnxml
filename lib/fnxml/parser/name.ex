defmodule FnXML.Parser.Name do
  @moduledoc """
  Facade for XML Name parsing with edition selection.

  Provides a convenient API that delegates to the appropriate
  edition-specific parser. For maximum performance in tight loops,
  use `FnXML.Parser.Edition5` or `FnXML.Parser.Edition4` directly.

  ## Example

      # Convenience API (resolves edition per call)
      FnXML.Parser.Name.parse("element", edition: 5)

      # Performance API (use directly, no dispatch)
      FnXML.Parser.Edition5.parse_name("element")

      # Get parser module once, use many times
      parser = FnXML.Parser.Name.parser(5)
      parser.parse_name("element")
  """

  @type edition :: 4 | 5

  @doc """
  Get the parser module for the specified edition.

  Returns the module that can be used for all parsing operations
  without per-call edition dispatch.

  ## Example

      parser = FnXML.Parser.Name.parser(5)
      parser.parse_name("foo")
      parser.parse_qname("ns:element")
      parser.valid_name?("test")
  """
  @spec parser(edition()) :: module()
  def parser(5), do: FnXML.Parser.Edition5
  def parser(4), do: FnXML.Parser.Edition4
  def parser(_), do: FnXML.Parser.Edition5

  @doc """
  Parse an XML Name using the specified edition.

  For repeated parsing, prefer getting the parser module once with
  `parser/1` and calling its functions directly.
  """
  @spec parse(binary(), keyword()) :: {:ok, String.t(), binary()} | {:error, term()}
  def parse(input, opts \\ []) do
    parser(Keyword.get(opts, :edition, 5)).parse_name(input)
  end

  @doc """
  Validate an XML Name using the specified edition.
  """
  @spec valid?(String.t(), keyword()) :: boolean()
  def valid?(name, opts \\ []) do
    parser(Keyword.get(opts, :edition, 5)).valid_name?(name)
  end

  @doc """
  Parse a QName (prefix:localpart) using the specified edition.
  """
  @spec parse_qname(binary(), keyword()) ::
          {:ok, {String.t() | nil, String.t()}, binary()} | {:error, term()}
  def parse_qname(input, opts \\ []) do
    parser(Keyword.get(opts, :edition, 5)).parse_qname(input)
  end

  @doc """
  Parse an NCName (name without colons) using the specified edition.
  """
  @spec parse_ncname(binary(), keyword()) :: {:ok, String.t(), binary()} | {:error, term()}
  def parse_ncname(input, opts \\ []) do
    parser(Keyword.get(opts, :edition, 5)).parse_ncname(input)
  end

  @doc """
  Check if a name is valid in BOTH Edition 4 and Edition 5.

  Useful for ensuring maximum interoperability.
  """
  @spec interoperable?(String.t()) :: boolean()
  def interoperable?(name) do
    FnXML.Parser.Edition4.valid_name?(name)
    # If valid in Ed4, automatically valid in Ed5 (Ed5 is superset)
  end
end
