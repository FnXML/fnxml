defmodule FnXML.Parser.Edition4 do
  @moduledoc """
  XML 1.0 Fourth Edition Parser.

  Uses the strict Edition 4 character validation rules from Appendix B.
  All parsing code is shared via FnXML.ParserGenerator with
  Edition 4 character validation inlined at compile time.

  ## Performance

  This module has zero runtime edition dispatch - the character
  validation functions are resolved at compile time.

  ## Use Cases

  - Validating XML for compatibility with older parsers
  - Conformance testing against Edition 4 test suites
  - Strict interoperability checking

  ## Example

      iex> FnXML.Parser.Edition4.parse_name("element")
      {:ok, "element", ""}

      iex> FnXML.Parser.Edition4.valid_name?("foo:bar")
      true
  """

  use FnXML.ParserGenerator, edition: 4
end
