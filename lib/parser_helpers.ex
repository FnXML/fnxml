defmodule FnXML.Parser.Helpers do
  @moduledoc """
  Helper functions to handle quoted strings
  """
  import NimbleParsec

  def maybe_escaped_char(combinator \\ empty(), char) do
    combinator
    |> choice([
      ignore(ascii_char([?\\])) |> ascii_char([char]),
      ascii_char([{:not, char}])
    ])
  end

  def quote_by_delimiter(combinator \\ empty(), char) do
    combinator
    |> ignore(ascii_char([char]))
    |> repeat(maybe_escaped_char(char))
    |> ignore(ascii_char([char]))
    |> reduce({List, :to_string, []})
  end
end

