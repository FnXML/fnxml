defmodule FnXML.API.StAX.Writer do
  @moduledoc """
  StAX XMLStreamWriter - cursor-based XML writing.

  Build XML documents incrementally using a fluent API. The writer
  maintains state about open elements and ensures well-formed output.

  ## Usage

      # Build the document structure
      writer = FnXML.StAX.Writer.new()
      |> FnXML.StAX.Writer.start_document()
      |> FnXML.StAX.Writer.start_element("root")
      |> FnXML.StAX.Writer.attribute("id", "1")
      |> FnXML.StAX.Writer.start_element("child")
      |> FnXML.StAX.Writer.characters("Hello World")
      |> FnXML.StAX.Writer.end_element()
      |> FnXML.StAX.Writer.end_element()
      |> FnXML.StAX.Writer.end_document()

      # Get events for further processing
      events = FnXML.StAX.Writer.to_event(writer)
      # => [
      #   {:prolog, "xml", [{"version", "1.0"}], nil},
      #   {:start_element, "root", [{"id", "1"}], nil},
      #   {:start_element, "child", [], nil},
      #   {:characters, "Hello World", nil},
      #   {:end_element, "child"},
      #   {:end_element, "root"}
      # ]

      # Or serialize directly to iodata
      iodata = FnXML.StAX.Writer.to_iodata(writer)
      xml = IO.iodata_to_binary(iodata)
      # => "<?xml version=\"1.0\"?><root id=\"1\"><child>Hello World</child></root>"

  ## State Transitions

  The writer tracks state to ensure well-formed output:

  - After `start_element/2`: Can call `attribute/3`, `namespace/3`, or content methods
  - After `attribute/3`: Can call more attributes or content methods
  - After content: Cannot add attributes (tag is closed)

  ## Namespace Support

      writer
      |> FnXML.StAX.Writer.start_element("http://example.org", "root")
      |> FnXML.StAX.Writer.namespace("ex", "http://example.org")
      |> FnXML.StAX.Writer.attribute("http://example.org", "attr", "value")

  ## Output Formats

  The writer can output in two formats:

  - **Event stream** (`to_event/1`): Returns a list of events that can be further
    transformed, validated, or serialized using other FnXML modules
  - **iodata** (`to_iodata/1`): Convenience wrapper that serializes events to iodata

  Character escaping happens automatically during serialization for:
  - Text content: `&`, `<`, `>`
  - Attributes: `&`, `<`, `>`, `"`
  """

  defstruct [
    # Event accumulator (reversed)
    events: [],
    # Stack of open element names
    stack: [],
    # :initial | :prolog | :element | :content
    state: :initial,
    # Attributes waiting to be written
    pending_attrs: [],
    # Namespace declarations waiting to be written
    pending_ns: []
  ]

  @type t :: %__MODULE__{
          events: list(),
          stack: [String.t()],
          state: :initial | :prolog | :element | :content,
          pending_attrs: [{String.t(), String.t()}],
          pending_ns: [{String.t() | nil, String.t()}]
        }

  @doc """
  Create a new StAX writer.

  ## Examples

      writer = FnXML.StAX.Writer.new()
  """
  @spec new(keyword()) :: t()
  def new(_opts \\ []) do
    %__MODULE__{}
  end

  @doc """
  Get the XML output as an event stream.

  Returns a list of events that can be piped to `FnXML.Event.to_iodata/2`
  or `FnXML.C14N.canonicalize/2`.

  ## Examples

      events = writer |> FnXML.StAX.Writer.to_event()
      # => [
      #   {:start_element, "root", [{"id", "1"}], nil},
      #   {:characters, "text", nil},
      #   {:end_element, "root"}
      # ]

      # Serialize to XML
      iodata = events |> FnXML.Event.to_iodata()

      # Or canonicalize
      iodata = events |> FnXML.C14N.canonicalize()
  """
  @spec to_event(t()) :: [tuple()]
  def to_event(%__MODULE__{state: :element} = writer) do
    # Close any pending element tag
    writer = flush_start_tag(writer)
    Enum.reverse(writer.events)
  end

  def to_event(%__MODULE__{events: events}) do
    Enum.reverse(events)
  end

  @doc """
  Get the XML output as iodata.

  Convenience method that calls `to_event/1` then serializes with
  `FnXML.Event.to_iodata/2`.

  Use `IO.iodata_to_binary/1` to convert to a string if needed.

  ## Examples

      iodata = writer |> FnXML.StAX.Writer.to_iodata()
      xml = IO.iodata_to_binary(iodata)
  """
  @spec to_iodata(t()) :: iodata()
  def to_iodata(writer) do
    writer
    |> to_event()
    |> FnXML.Event.to_iodata()
    |> Enum.to_list()
  end

  @doc """
  Write XML declaration.

  ## Examples

      writer |> FnXML.StAX.Writer.start_document()
      # => <?xml version="1.0"?>

      writer |> FnXML.StAX.Writer.start_document("1.0", "UTF-8")
      # => <?xml version="1.0" encoding="UTF-8"?>
  """
  @spec start_document(t()) :: t()
  @spec start_document(t(), String.t()) :: t()
  @spec start_document(t(), String.t(), String.t() | nil) :: t()
  def start_document(writer, version \\ "1.0", encoding \\ nil)

  def start_document(%__MODULE__{state: :initial} = writer, version, nil) do
    event = {:prolog, "xml", [{"version", version}], nil, nil, nil}
    %{writer | events: [event | writer.events], state: :prolog}
  end

  def start_document(%__MODULE__{state: :initial} = writer, version, encoding) do
    event = {:prolog, "xml", [{"version", version}, {"encoding", encoding}], nil, nil, nil}
    %{writer | events: [event | writer.events], state: :prolog}
  end

  @doc """
  End the document, closing any open elements.
  """
  @spec end_document(t()) :: t()
  def end_document(%__MODULE__{stack: []} = writer) do
    flush_start_tag(writer)
  end

  def end_document(%__MODULE__{} = writer) do
    # Close all open elements
    writer
    |> flush_start_tag()
    |> close_all_elements()
  end

  defp close_all_elements(%__MODULE__{stack: []} = writer), do: writer

  defp close_all_elements(%__MODULE__{} = writer) do
    writer
    |> end_element()
    |> close_all_elements()
  end

  @doc """
  Start a new element.

  ## Examples

      writer |> FnXML.StAX.Writer.start_element("div")

      writer |> FnXML.StAX.Writer.start_element("http://example.org", "root")

      writer |> FnXML.StAX.Writer.start_element("ex", "root", "http://example.org")
  """
  @spec start_element(t(), String.t()) :: t()
  def start_element(%__MODULE__{} = writer, name) when is_binary(name) do
    writer = flush_start_tag(writer)

    %{writer | stack: [name | writer.stack], state: :element, pending_attrs: [], pending_ns: []}
  end

  @spec start_element(t(), String.t(), String.t()) :: t()
  def start_element(%__MODULE__{} = writer, namespace_uri, local_name)
      when is_binary(namespace_uri) and is_binary(local_name) do
    # Store namespace for later, use local name
    writer = flush_start_tag(writer)

    %{
      writer
      | stack: [local_name | writer.stack],
        state: :element,
        pending_attrs: [],
        pending_ns: [{nil, namespace_uri} | writer.pending_ns]
    }
  end

  @spec start_element(t(), String.t(), String.t(), String.t()) :: t()
  def start_element(%__MODULE__{} = writer, prefix, local_name, namespace_uri)
      when is_binary(prefix) and is_binary(local_name) and is_binary(namespace_uri) do
    writer = flush_start_tag(writer)
    qname = "#{prefix}:#{local_name}"

    %{
      writer
      | stack: [qname | writer.stack],
        state: :element,
        pending_attrs: [],
        pending_ns: [{prefix, namespace_uri} | writer.pending_ns]
    }
  end

  @doc """
  End the current element.
  """
  @spec end_element(t()) :: t()
  def end_element(%__MODULE__{state: :element, stack: [name | rest]} = writer) do
    # Self-closing tag - emit both start and end events
    # Build namespace declarations as attributes
    ns_attrs =
      writer.pending_ns
      |> Enum.reverse()
      |> Enum.map(fn
        {nil, uri} -> {"xmlns", uri}
        {prefix, uri} -> {"xmlns:#{prefix}", uri}
      end)

    # Combine all attributes
    attrs = Enum.reverse(writer.pending_attrs) ++ ns_attrs

    # Emit start_element followed by end_element (in reverse order since events are reversed)
    events = [
      {:end_element, name, nil, nil, nil},
      {:start_element, name, attrs, nil, nil, nil}
      | writer.events
    ]

    %{
      writer
      | events: events,
        stack: rest,
        state: :content,
        pending_attrs: [],
        pending_ns: []
    }
  end

  def end_element(%__MODULE__{stack: [name | rest]} = writer) do
    writer = flush_start_tag(writer)

    event = {:end_element, name, nil, nil, nil}
    %{writer | events: [event | writer.events], stack: rest, state: :content}
  end

  @doc """
  Write an empty element (self-closing).

  ## Examples

      writer |> FnXML.StAX.Writer.empty_element("br")
      # => <br/>
  """
  @spec empty_element(t(), String.t()) :: t()
  def empty_element(%__MODULE__{} = writer, name) do
    writer
    |> start_element(name)
    |> end_element()
  end

  @doc """
  Add an attribute to the current element.

  Must be called after `start_element/2` and before any content.

  ## Examples

      writer |> FnXML.StAX.Writer.attribute("id", "1")

      writer |> FnXML.StAX.Writer.attribute("http://example.org", "attr", "value")
  """
  @spec attribute(t(), String.t(), String.t()) :: t()
  def attribute(%__MODULE__{state: :element, pending_attrs: attrs} = writer, name, value) do
    %{writer | pending_attrs: [{name, value} | attrs]}
  end

  @spec attribute(t(), String.t(), String.t(), String.t()) :: t()
  def attribute(
        %__MODULE__{state: :element, pending_attrs: attrs} = writer,
        _namespace_uri,
        local_name,
        value
      ) do
    # For now, just use local name (full namespace support would require prefix management)
    %{writer | pending_attrs: [{local_name, value} | attrs]}
  end

  @doc """
  Add a namespace declaration to the current element.

  ## Examples

      writer |> FnXML.StAX.Writer.namespace("ex", "http://example.org")
      # => xmlns:ex="http://example.org"
  """
  @spec namespace(t(), String.t(), String.t()) :: t()
  def namespace(%__MODULE__{state: :element, pending_ns: ns} = writer, prefix, uri) do
    %{writer | pending_ns: [{prefix, uri} | ns]}
  end

  @doc """
  Set the default namespace for the current element.

  ## Examples

      writer |> FnXML.StAX.Writer.default_namespace("http://example.org")
      # => xmlns="http://example.org"
  """
  @spec default_namespace(t(), String.t()) :: t()
  def default_namespace(%__MODULE__{state: :element, pending_ns: ns} = writer, uri) do
    %{writer | pending_ns: [{nil, uri} | ns]}
  end

  @doc """
  Write text content.

  Special characters (`&`, `<`, `>`) are automatically escaped during serialization.

  ## Examples

      writer |> FnXML.StAX.Writer.characters("Hello <World>")
      # => Hello &lt;World&gt;
  """
  @spec characters(t(), String.t()) :: t()
  def characters(%__MODULE__{} = writer, text) do
    writer = flush_start_tag(writer)
    event = {:characters, text, nil, nil, nil}

    %{writer | events: [event | writer.events], state: :content}
  end

  @doc """
  Write a CDATA section.

  ## Examples

      writer |> FnXML.StAX.Writer.cdata("content with <special> chars")
      # => <![CDATA[content with <special> chars]]>
  """
  @spec cdata(t(), String.t()) :: t()
  def cdata(%__MODULE__{} = writer, text) do
    writer = flush_start_tag(writer)
    event = {:cdata, text, nil, nil, nil}

    %{writer | events: [event | writer.events], state: :content}
  end

  @doc """
  Write a comment.

  ## Examples

      writer |> FnXML.StAX.Writer.comment("This is a comment")
      # => <!--This is a comment-->
  """
  @spec comment(t(), String.t()) :: t()
  def comment(%__MODULE__{} = writer, text) do
    writer = flush_start_tag(writer)
    event = {:comment, text, nil, nil, nil}

    %{writer | events: [event | writer.events], state: :content}
  end

  @doc """
  Write a processing instruction.

  ## Examples

      writer |> FnXML.StAX.Writer.processing_instruction("php", "echo 'hello';")
      # => <?php echo 'hello';?>
  """
  @spec processing_instruction(t(), String.t()) :: t()
  @spec processing_instruction(t(), String.t(), String.t() | nil) :: t()
  def processing_instruction(writer, target, data \\ nil)

  def processing_instruction(%__MODULE__{} = writer, target, nil) do
    writer = flush_start_tag(writer)
    event = {:processing_instruction, target, nil, nil, nil, nil}

    %{writer | events: [event | writer.events], state: :content}
  end

  def processing_instruction(%__MODULE__{} = writer, target, data) do
    writer = flush_start_tag(writer)
    event = {:processing_instruction, target, data, nil, nil, nil}

    %{writer | events: [event | writer.events], state: :content}
  end

  @doc """
  Write a DOCTYPE declaration.

  ## Examples

      writer |> FnXML.StAX.Writer.dtd("html")
      # => <!DOCTYPE html>
  """
  @spec dtd(t(), String.t()) :: t()
  def dtd(%__MODULE__{} = writer, content) do
    writer = flush_start_tag(writer)
    event = {:dtd, content, nil, nil, nil}

    %{writer | events: [event | writer.events], state: :content}
  end

  @doc """
  Write an entity reference.

  ## Examples

      writer |> FnXML.StAX.Writer.entity_ref("nbsp")
      # => &nbsp;
  """
  @spec entity_ref(t(), String.t()) :: t()
  def entity_ref(%__MODULE__{} = writer, name) do
    writer = flush_start_tag(writer)
    event = {:entity_ref, name, nil, nil, nil}

    %{writer | events: [event | writer.events], state: :content}
  end

  # Flush pending start tag with attributes and namespaces
  defp flush_start_tag(%__MODULE__{state: :element, stack: [name | _]} = writer) do
    # Build namespace declarations as attributes
    ns_attrs =
      writer.pending_ns
      |> Enum.reverse()
      |> Enum.map(fn
        {nil, uri} -> {"xmlns", uri}
        {prefix, uri} -> {"xmlns:#{prefix}", uri}
      end)

    # Combine all attributes
    attrs = Enum.reverse(writer.pending_attrs) ++ ns_attrs

    event = {:start_element, name, attrs, nil, nil, nil}

    %{
      writer
      | events: [event | writer.events],
        state: :content,
        pending_attrs: [],
        pending_ns: []
    }
  end

  defp flush_start_tag(writer), do: writer
end
