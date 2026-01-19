defmodule FnXML.MacroBlkParser.Edition4 do
  @moduledoc """
  XML 1.0 Fourth Edition Block Parser.

  Uses the strict Edition 4 character validation rules from Appendix B.
  All parsing code is shared via FnXML.MacroBlkParserGenerator with
  Edition 4 character validation inlined at compile time.

  ## Performance

  This module has zero runtime edition dispatch - the character
  validation guards are resolved at compile time.

  ## Use Cases

  - Validating XML for compatibility with older parsers
  - Conformance testing against Edition 4 test suites
  - Strict interoperability checking

  ## Example

      iex> FnXML.MacroBlkParser.Edition4.parse("<root>text</root>")
      [{:start_element, "root", [], 1, 0, 1}, {:characters, "text", 1, 0, 6},
       {:end_element, "root", 1, 0, 10}]
  """

  use FnXML.MacroBlkParserGenerator, edition: 4
end
