defmodule FnXML.Parser.Debug do
  @moduledoc """
  Debugging helpers for the parser.
  """

  import NimbleParsec

  alias FnXML.Parser.Debug

  def inspect(combinator, opts) do
    combinator
    |> reduce({Debug, :__inspect__, opts})
  end

  def __inspect__(info, opts), do: IO.inspect(info, [opts])
end

defmodule FnXML.Parser.Constructs do
  @moduledoc """
  Helper functions to handle quoted strings
  """

  import NimbleParsec

  def ws() do
    times(ascii_char([0x20, 0x9, 0xD, 0xA]), min: 1)
    |> reduce({List, :to_string, []})
  end

  def open_bracket(combinator \\ empty()), do: combinator |> ignore(ascii_char([?<]))

  def close_bracket(combinator \\ empty()), do: combinator |> ignore(ascii_char([?>]))

  def ignore_opt_ws(combinator \\ empty()), do: combinator |> ignore(optional(ws()))

  def name do
    start_char = [
      ?a..?z, ?A..?Z, ?:, ?_,
      0x00C0..0x00D6, 0x00D8..0x00F6, 0x00F8..0x02FF, 0x0370..0x037D, 0x037F..0x1FFF,
      0x200C..0x200D
    ]
    name_char = [ ?-, ?., ?0..?9, 0x00B7, 0x0300..0x036F, 0x203F..0x2040 | start_char]
    ascii_char(start_char)
    |> ascii_string(name_char, min: 0)
    |> reduce({List, :to_string, []})
  end

  def tag_name do
    name()
    |> unwrap_and_tag(:tag)
  end

  def sort_components(list, key_order \\ [:tag, :close, :attributes, :loc]) do
    list = List.flatten(list)
    index = fn list, item -> Enum.find_index(list, &Kernel.==(&1, item)) end
    Enum.sort_by(list, fn {k, _} -> index.(key_order, k) end)
    |> Enum.filter(fn {_, v} -> v != nil and v != "" and v != [] end)
  end
end

defmodule FnXML.Parser.Quoted do
  @moduledoc """
  Parser for quoted strings
  """
  import NimbleParsec

  def string(char) do
    ignore(ascii_char([char]))
    |> repeat(ascii_char([not: char]))
    |> ignore(ascii_char([char]))
    |> reduce({List, :to_string, []})
  end
end

defmodule FnXML.Parser.Position do
  @moduledoc """
  get parse position
  """
  import NimbleParsec

  alias FnXML.Parser.Position

  def get(combinator \\ empty()) do
    combinator
    |> line()
    |> byte_offset()
    |> reduce({Position, :format, []})
  end

  def format([{[{context, {line, line_char}}], abs_pos}]), do: [{:loc, {line, line_char, abs_pos}} | context]
end


defmodule FnXML.Parser.Attributes do
  @moduledoc """
  Helper functions for parsing attributes
  """

  import NimbleParsec

  alias FnXML.Parser.Attributes
  alias FnXML.Parser.Constructs, as: C
  alias FnXML.Parser.Quoted

  def attribute() do
    C.ignore_opt_ws()
    |> concat(C.name())
    |> C.ignore_opt_ws()
    |> ignore(string("="))
    |> C.ignore_opt_ws()
    |> choice([Quoted.string(?"), Quoted.string(?')])
    |> reduce({Attributes, :into_keyword, []})
  end
  
  def attributes() do
    repeat(attribute())
    |> tag(:attributes)
  end

  def into_keyword([k | [v]]), do: {k, v}
end

defmodule FnXML.Parser.Element do
  @moduledoc """
  Helper functions for parsing elements
  """

  import NimbleParsec

  alias FnXML.Parser.Element
  alias FnXML.Parser.Constructs, as: C
  alias FnXML.Parser.Attributes, as: Attr
  alias FnXML.Parser.Position, as: Pos

  def open_tag() do
    Pos.get(empty())
    |> concat(C.tag_name())
    |> optional(Attr.attributes())
    |> C.ignore_opt_ws()
    |> optional(string("/") |> tag(:close) |> reduce({Element, :set_true, []}))
    |> reduce({C, :sort_components, []})
    |> unwrap_and_tag(:open)
    |> C.ignore_opt_ws()
    |> label("open_tag '<tag name=\"...\">'")
  end

  def close_tag() do
    Pos.get(empty())
    |> ignore(string("/"))
    |> concat(C.tag_name())
    |> reduce({C, :sort_components, []})
    |> unwrap_and_tag(:close)
    |> C.ignore_opt_ws()
    |> label("close_tag '</tag>'")
  end

  def comment() do
    Pos.get(empty())
    |> ignore(string("!--"))
    |> repeat(lookahead_not(string("--")) |> ascii_char([]))
    |> ignore(string("--"))
    |> reduce({Element, :format_content, []})
    |> unwrap_and_tag(:comment)
    |> label("comment '<!-- text -->'")
  end

  def processing_instruction do
    Pos.get(empty())
    |> ignore(string("?"))
    |> concat(C.tag_name())
    |> C.ignore_opt_ws()
    |> repeat(lookahead_not(string("?")) |> ascii_char([]))
    |> ignore(string("?"))
    |> reduce({Element, :format_content, []})
    |> unwrap_and_tag(:proc_inst)
    |> label("processing_instruction '<?tag text?>'")
  end

  def prolog do
    C.open_bracket()
    |> Pos.get()
    |> ignore(string("?"))
    |> concat(C.tag_name())
    |> concat(Attr.attributes())
    |> C.ignore_opt_ws()
    |> ignore(string("?"))
    |> reduce({C, :sort_components, [[:tag, :attributes, :loc]]})
    |> unwrap_and_tag(:prolog)
    |> label("prolog '<?tag version=\"...\", encoding=\"...\">'")
    |> C.close_bracket()
    |> C.ignore_opt_ws()
  end

  def text do
    Pos.get(empty())
    |> ascii_string([not: ?<], min: 1)
    |> reduce({Element, :format_content, []})
    |> unwrap_and_tag(:text)
    |> label("text")
  end

  def cdata do
    Pos.get(empty())
    |> ignore(string("![CDATA["))
    |> repeat(lookahead_not(string("]]")) |> ascii_char([]))
    |> ignore(string("]]"))
    |> reduce({Element, :format_content, []})
    |> unwrap_and_tag(:text)
    |> label("cdata '![CDATA[ text ]]'")
  end

  def element do
    C.open_bracket()
    |> choice([
      Element.open_tag(),
      Element.close_tag(),
      Element.cdata(),
      Element.comment(),
      Element.processing_instruction()
    ])
    |> C.close_bracket()
  end

  def next(), do: choice([text(), element()])

  def set_true([{:close, _}]), do: {:close, true}
  
  def format_content([[{:loc, _}] = loc, {:tag, _} = tag | comment]), do: [tag, {:content, to_string(comment)} | loc]
  def format_content([[{:loc, _}] = loc | comment]), do: [{:content, to_string(comment)} | loc]
end
