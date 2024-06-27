# XML Stream Tools

This is an Elixir library of tools for manipulate XML with using Streams.  It also provides a way to encode/decode
"Native Data Structures" to/from an XML Stream.

```
 ----------------   ----------------
| Encoder        | | Decoder        |
 ----------------   ----------------
 -----------------------------------   -----------------  ----------------
|  Native Data Structures           | | XML Parser     | | XML Formatter  |
 -----------------------------------   -----------------  ----------------
 -------------------------------------------------------------------------
|                               XML Stream                                |
 -------------------------------------------------------------------------
```

# What is an XML Stream?

XML is difficult to stream as it is defined.  This is because valid
XML must end with a valid end tag to be correct.  Consequently in
order to ensure that the XML expression is valid the entire XML must
be consumed.  XML with a root tag, that contains 10Tb of data cannot
be confirmed to be correct unless the entire 10Tb is parsed.  This is
inconvenient.

This module makes one little assumption, and that is that the XML is
already correct, so we won't worry about that part.

This frees us to consume XML differently.  These tools treat XML as a
list of open, text, and close elements, which represent the elements
as they were encountered in the XML string/file.

## Example:

```xml
  <demo:root type="info">
    <description>some descriptive text</description>
    <address>
      <name>John Doe</name>
      <street>42 Main St.</street>
      <city>Ely</city>
      <state>MN</state>
      <zip>55731<zip>
    </address>
  </demo:root>
```

XML Stream Tools has a parser which can parse this XML and emit it to a Stream like:
(location data is omitted to simplify the example)

```elixir
[
  {:open_tag, [tag: "root", namespace: "demo", attr: [{"type", "info"}]},
  {:open_tag, [tag: "description"]},
  {:text, ["some descriptive text"]},
  {:close_tag, [tag: "description"]},
  {:open_tag, [tag: "address"},
  {:open_tag, [tag: "name"},
  {:text, ["John Doe"]},
  {:close_tag, [tag: "name"},
  {:open_tag, [tag: "street"},
  {:text, ["42 Main St."]

   ...

  {:close_tag, [tag: "zip"]},
  {:close_tag, [tag: "address"]},
  {:close_tag, [tag: "root", namespace: "demo"]}
]
```

In this format elements of the XML become a stream of XML parts, which
could be operated on and transformed through a stream.

Once in this format existing tools can be used to operate on the
stream, such as filter elements, convert it back to XML, format the
XML.

Additionally there are tools which can be used to take an "Native Data
Structure" and convert it to the XML Stream format.

## Example:

```elixir
defmodule Address
  defstruct [:name, :street, :city, :state, :zip]
end

address = %Address{name: "John Doe", street: "42 Main St.", city: "Ely", state: "MN", zip: 55731}

XMLStreamTools.NativeDataStruct.encode(address, [tag: "address"])
```

which would result in a list like:
```elixir
[
  {:open_tag, [tag: "address"},
  {:open_tag, [tag: "name"},
  {:text, ["John Doe"]},
  {:close_tag, [tag: "name"},
  {:open_tag, [tag: "street"},
  {:text, ["42 Main St."]
  {:close_tag, [tag: "street"},
  {:open_tag, [tag: "city"},
  {:text, ["Ely"]
  {:close_tag, [tag: "city"},
  {:open_tag, [tag: "state"},
  {:text, ["MN"]
  {:close_tag, [tag: "state"},
  {:open_tag, [tag: "zip"},
  {:text, ["55731"]
  {:close_tag, [tag: "zip"},
  {:close_tag, [tag: "address"},
]
```

From there it could be passed to several different tools:

XML Format:
```elixir
address
|> XMLStreamTools.XMLStream.Format()
```
```xml
<address><name>John Doe</name><street>42 Main St.</street><city>Ely</city><state>MN</state><zip>55731<zip><address>
```

or:

```elixir
address
|> XMLStreamTools.XMLStream.Format(pretty: true, indent: 4)
```

```xml
<address>
    <name>John Doe</name>
    <street>42 Main St.</street>
    <city>Ely</city>
    <state>MN</state>
    <zip>55731<zip>
</address>
```

The XML Stream could also be converted back to the same or a different Native Data Structure.

```elixir
address |> XMLStreamTools.NativeDataType.decode(%Address{})

%Address{name: "John Doe", street: "42 Main St.", city: "Ely", state: "MN", zip: 55731}
```    

(Disclaimer) This is very Alpha software at the moment, and definitely a work in progress, don't bet your business on it.

Implemented Tools:

- a NimbleParsec XML parser
- a transformer - this can be used to take the stream of XML elements and output another stream of
  modified elements or anything else really.
- an inspector, which will write stream elements to the console, as they are processed.
- add a filter which takes XPATH or something like it to include/exclude elements from the stream.
- a decoder this builds on the transformer and will convert XML to elixir Maps.  As part of this
  there is an Elixir Behaviour called Formatter which is defined to specify how to convert the
  XML to a Map.  New implementations of this behaviour can be defined to change how the XML is
  converted.  For example if your XML lends itself to going into an Explorer structure, that
  is possible to create with the Formatter.

ToDo:


## Contributions

Any contributions/suggestions are welcome.

## The dreaded To Do section:

- write some documentation, so other people can find this useful.
- update the parser so it reads from a stream, currently it just takes input as a binary.
- make an inspect that writes to Logger
- make a filter that takes XPath like input to select or exclude XML from the stream
- make an encoder protocol.  To encode Maps, Lists and Structs into XML


## Installation

If [available in Hex](https://hex.pm/docs/publish), (**Note** not yet available in hex) the package can be installed
by adding `xmlstreamtools` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:xmlstreamtools, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/xmlstreamtools>.

## My Use Case

I am requesting data from a service which return XML.  I use this to
parse the returned data and generate a stream of elements.  The
elements are filtered, then transformed into elixir maps/lists, and
ultimatly displayed as formatted JSON.
