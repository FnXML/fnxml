defmodule FnXML.API.StAX do
  @moduledoc """
  StAX-style pull-based XML streaming.

  StAX (Streaming API for XML) is a pull-based API where the application
  controls when to advance the parser and retrieve events. This contrasts
  with SAX's push-based model where the parser drives event delivery.

  ## Specifications

  - JSR-173 (StAX): https://jcp.org/en/jsr/detail?id=173
  - W3C XML 1.0: https://www.w3.org/TR/xml/

  ## Memory Characteristics

  StAX uses O(1) memory with lazy streaming - events are pulled one at a time.
  This makes it suitable for very large documents while giving you control
  over the parse loop (unlike SAX which pushes events to you).

  ## APIs

  StAX provides two complementary APIs:

  ### Cursor API (`FnXML.API.StAX.Reader` / `FnXML.API.StAX.Writer`)

  Low-level, position-based access. The reader maintains a cursor that
  can be advanced through the document, with accessor functions to
  query the current event.

      # Pipeline style (recommended)
      reader = FnXML.Parser.parse("<root><child>text</child></root>")
               |> FnXML.API.StAX.reader()

      reader = FnXML.API.StAX.Reader.next(reader)  # Advance to first event
      FnXML.API.StAX.Reader.event_type(reader)     # => :start_element
      FnXML.API.StAX.Reader.local_name(reader)     # => "root"

      reader = FnXML.API.StAX.Reader.next(reader)
      FnXML.API.StAX.Reader.local_name(reader)     # => "child"

      # Quick create (convenience)
      reader = FnXML.API.StAX.create_reader("<root/>")

  ### Writer API

  Build XML documents incrementally:

      xml = FnXML.API.StAX.Writer.new()
      |> FnXML.API.StAX.Writer.start_document()
      |> FnXML.API.StAX.Writer.start_element("root")
      |> FnXML.API.StAX.Writer.characters("Hello")
      |> FnXML.API.StAX.Writer.end_element()
      |> FnXML.API.StAX.Writer.end_document()
      |> FnXML.API.StAX.Writer.to_string()

      # => "<?xml version=\"1.0\"?><root>Hello</root>"

  ## Event Types

  StAX defines these event types (compatible with JSR-173):

  - `:start_element` (1) - Element start tag
  - `:end_element` (2) - Element end tag
  - `:characters` (4) - Text content
  - `:comment` (5) - Comment
  - `:space` (6) - Ignorable whitespace
  - `:start_document` (7) - Document start
  - `:end_document` (8) - Document end
  - `:processing_instruction` (3) - Processing instruction
  - `:dtd` (11) - DOCTYPE declaration
  - `:cdata` (12) - CDATA section
  - `:namespace` (13) - Namespace declaration
  - `:entity_reference` (9) - Entity reference
  - `:attribute` (10) - Attribute (for attribute-centric parsing)

  ## Comparison with SAX

  | Aspect | SAX | StAX |
  |--------|-----|------|
  | Model | Push (parser calls you) | Pull (you call parser) |
  | Control | Parser-driven | Application-driven |
  | Early stop | Throw exception | Just stop calling next |
  | State management | In handler callbacks | In application code |
  | Memory | Very low | Very low |

  ## When to Use StAX

  - Processing XML where you need control over the parse loop
  - State-machine style parsing
  - Parsing multiple documents with shared code
  - When you want to stop parsing early easily
  - Building XML documents incrementally
  """

  # Event type constants (JSR-173 compatible)
  @start_element 1
  @end_element 2
  @processing_instruction 3
  @characters 4
  @comment 5
  @space 6
  @start_document 7
  @end_document 8
  @entity_reference 9
  @attribute 10
  @dtd 11
  @cdata 12
  @namespace 13
  @notation_declaration 14
  @entity_declaration 15

  @doc "Event type constant for start element (1)"
  def start_element, do: @start_element

  @doc "Event type constant for end element (2)"
  def end_element, do: @end_element

  @doc "Event type constant for processing instruction (3)"
  def processing_instruction, do: @processing_instruction

  @doc "Event type constant for characters/text (4)"
  def characters, do: @characters

  @doc "Event type constant for comment (5)"
  def comment, do: @comment

  @doc "Event type constant for ignorable whitespace (6)"
  def space, do: @space

  @doc "Event type constant for start document (7)"
  def start_document, do: @start_document

  @doc "Event type constant for end document (8)"
  def end_document, do: @end_document

  @doc "Event type constant for entity reference (9)"
  def entity_reference, do: @entity_reference

  @doc "Event type constant for attribute (10)"
  def attribute, do: @attribute

  @doc "Event type constant for DTD (11)"
  def dtd, do: @dtd

  @doc "Event type constant for CDATA (12)"
  def cdata, do: @cdata

  @doc "Event type constant for namespace (13)"
  def namespace, do: @namespace

  @doc "Event type constant for notation declaration (14)"
  def notation_declaration, do: @notation_declaration

  @doc "Event type constant for entity declaration (15)"
  def entity_declaration, do: @entity_declaration

  @doc """
  Create a StAX reader from an event stream.

  This is the primary way to create a StAX reader with FnXML's pipeline style,
  taking a pre-parsed event stream as input.

  ## Options

  - `:namespaces` - Enable namespace resolution (default: false)

  ## Examples

      # Pipeline style (recommended)
      reader = FnXML.Parser.parse("<root><child>text</child></root>")
               |> FnXML.API.StAX.reader()

      reader = FnXML.API.StAX.Reader.next(reader)
      FnXML.API.StAX.Reader.local_name(reader)  # => "root"

      # With validation
      reader = FnXML.Parser.parse(xml)
               |> FnXML.Validate.well_formed()
               |> FnXML.API.StAX.reader()
  """
  @spec reader(Enumerable.t(), keyword()) :: FnXML.API.StAX.Reader.t()
  def reader(stream, opts \\ []) do
    FnXML.API.StAX.Reader.new(stream, opts)
  end

  @doc """
  Create a new StAX writer.

  ## Examples

      writer = FnXML.API.StAX.create_writer()
  """
  @spec create_writer(keyword()) :: FnXML.API.StAX.Writer.t()
  defdelegate create_writer(opts \\ []), to: FnXML.API.StAX.Writer, as: :new

  @doc """
  Convert event type atom to integer constant.
  """
  @spec event_type_to_int(atom()) :: integer()
  def event_type_to_int(:start_element), do: @start_element
  def event_type_to_int(:end_element), do: @end_element
  def event_type_to_int(:processing_instruction), do: @processing_instruction
  def event_type_to_int(:characters), do: @characters
  def event_type_to_int(:comment), do: @comment
  def event_type_to_int(:space), do: @space
  def event_type_to_int(:start_document), do: @start_document
  def event_type_to_int(:end_document), do: @end_document
  def event_type_to_int(:entity_reference), do: @entity_reference
  def event_type_to_int(:attribute), do: @attribute
  def event_type_to_int(:dtd), do: @dtd
  def event_type_to_int(:cdata), do: @cdata
  def event_type_to_int(:namespace), do: @namespace

  @doc """
  Convert event type integer to atom.
  """
  @spec event_type_to_atom(integer()) :: atom()
  def event_type_to_atom(@start_element), do: :start_element
  def event_type_to_atom(@end_element), do: :end_element
  def event_type_to_atom(@processing_instruction), do: :processing_instruction
  def event_type_to_atom(@characters), do: :characters
  def event_type_to_atom(@comment), do: :comment
  def event_type_to_atom(@space), do: :space
  def event_type_to_atom(@start_document), do: :start_document
  def event_type_to_atom(@end_document), do: :end_document
  def event_type_to_atom(@entity_reference), do: :entity_reference
  def event_type_to_atom(@attribute), do: :attribute
  def event_type_to_atom(@dtd), do: :dtd
  def event_type_to_atom(@cdata), do: :cdata
  def event_type_to_atom(@namespace), do: :namespace
end
