defmodule FnXML.MacroBlkParser do
  @moduledoc """
  Facade for XML Block parsing with edition selection.

  Provides a convenient API that delegates to the appropriate
  edition-specific parser. For maximum performance in tight loops,
  use `FnXML.MacroBlkParser.Edition5` or `FnXML.MacroBlkParser.Edition4` directly.

  ## Example

      # Convenience API (resolves edition per call)
      FnXML.MacroBlkParser.parse("<root/>", edition: 5)

      # Performance API (use directly, no dispatch)
      FnXML.MacroBlkParser.Edition5.parse("<root/>")

      # Get parser module once, use many times
      parser = FnXML.MacroBlkParser.parser(5)
      parser.parse("<root/>")
  """

  @type edition :: 4 | 5

  @doc """
  Get the parser module for the specified edition.

  Returns the module that can be used for all parsing operations
  without per-call edition dispatch.

  ## Example

      parser = FnXML.MacroBlkParser.parser(5)
      parser.parse("<root/>")
      parser.stream(File.stream!("large.xml"))
  """
  @spec parser(edition()) :: module()
  def parser(5), do: FnXML.MacroBlkParser.Edition5
  def parser(4), do: FnXML.MacroBlkParser.Edition4
  def parser(_), do: FnXML.MacroBlkParser.Edition5

  @doc """
  Parse complete XML using the specified edition.

  For repeated parsing, prefer getting the parser module once with
  `parser/1` and calling its functions directly.

  ## Options
  - `:edition` - XML 1.0 edition (4 or 5, default: 5)
  """
  @spec parse(binary(), keyword()) :: list()
  def parse(input, opts \\ []) do
    parser(Keyword.get(opts, :edition, 5)).parse(input)
  end

  @doc """
  Stream XML from any enumerable source using the specified edition.

  Returns lazy stream of events (batched per block).

  ## Options
  - `:edition` - XML 1.0 edition (4 or 5, default: 5)
  """
  @spec stream(Enumerable.t(), keyword()) :: Enumerable.t()
  def stream(enumerable, opts \\ []) do
    parser(Keyword.get(opts, :edition, 5)).stream(enumerable)
  end

  @doc """
  Parse a single block of XML using the specified edition.

  ## Options
  - `:edition` - XML 1.0 edition (4 or 5, default: 5)
  """
  @spec parse_block(
          binary(),
          binary() | nil,
          non_neg_integer(),
          pos_integer(),
          non_neg_integer(),
          non_neg_integer(),
          keyword()
        ) ::
          {list(), non_neg_integer() | nil, {pos_integer(), non_neg_integer(), non_neg_integer()}}
  def parse_block(block, prev_block, prev_pos, line, ls, abs_pos, opts \\ []) do
    parser(Keyword.get(opts, :edition, 5)).parse_block(
      block,
      prev_block,
      prev_pos,
      line,
      ls,
      abs_pos
    )
  end

  @doc """
  Check if a name is valid in BOTH Edition 4 and Edition 5.

  Useful for ensuring maximum interoperability when generating XML.
  """
  @spec interoperable_name?(String.t()) :: boolean()
  def interoperable_name?(name) do
    FnXML.Char.valid_name_ed4?(name)
    # If valid in Ed4, automatically valid in Ed5 (Ed5 is superset)
  end
end
