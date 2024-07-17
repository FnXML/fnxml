defmodule FnXML.Parser.Helpers do
  @moduledoc """
  Helper functions to handle quoted strings
  """
#  import NimbleParsec
  alias NimbleParsec, as: NP

  def maybe_escaped_char(combinator \\ NP.empty(), char) do
    combinator
    |> NP.choice([
      NP.ignore(NP.ascii_char([?\\])) |> NP.ascii_char([char]),
      NP.ascii_char([{:not, char}])
    ])
  end

  def quote_by_delimiter(combinator \\ NP.empty(), char) do
    combinator
    |> NP.ignore(NP.ascii_char([char]))
    |> NP.repeat(maybe_escaped_char(char))
    |> NP.ignore(NP.ascii_char([char]))
    |> NP.reduce({List, :to_string, []})
  end
end

