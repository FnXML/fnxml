defmodule FnXML.MacroBlkParser.Edition5 do
  @moduledoc """
  XML 1.0 Fifth Edition Block Parser.

  Uses the permissive Edition 5 character validation rules.
  All parsing code is shared via FnXML.MacroBlkParserGenerator with
  Edition 5 character validation inlined at compile time.

  ## Performance

  This module has zero runtime edition dispatch - the character
  validation guards are resolved at compile time.

  ## Example

      iex> FnXML.MacroBlkParser.Edition5.parse("<root>text</root>")
      [{:start_element, "root", [], 1, 0, 1}, {:characters, "text", 1, 0, 6},
       {:end_element, "root", 1, 0, 10}]
  """

  use FnXML.MacroBlkParserGenerator, edition: 5
end
