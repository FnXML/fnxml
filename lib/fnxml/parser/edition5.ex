defmodule FnXML.Parser.Edition5 do
  @moduledoc """
  XML 1.0 Fifth Edition Parser.

  Uses the permissive Edition 5 character validation rules.
  All parsing code is shared via FnXML.ParserGenerator with
  Edition 5 character validation inlined at compile time.

  ## Performance

  This module has zero runtime edition dispatch - the character
  validation functions are resolved at compile time.

  ## Example

      iex> FnXML.Parser.Edition5.parse_name("element")
      {:ok, "element", ""}

      iex> FnXML.Parser.Edition5.valid_name?("foo:bar")
      true
  """

  use FnXML.ParserGenerator, edition: 5
end
