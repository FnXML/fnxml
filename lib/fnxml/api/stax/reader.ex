defmodule FnXML.API.StAX.Reader do
  @moduledoc """
  StAX XMLStreamReader - cursor-based pull parsing.

  The Reader provides low-level, cursor-based access to XML documents.
  You control when to advance through the document by calling `next/1`,
  and query the current event using accessor functions.

  ## Lazy Stream Processing

  The Reader uses lazy evaluation - events are pulled from the underlying
  parser stream one at a time as you call `next/1`. This provides O(1) memory
  usage regardless of document size, making it suitable for processing large
  XML files.

  ## Usage

      # From parser stream (recommended)
      reader = FnXML.Parser.parse("<root attr='val'><child>text</child></root>")
               |> FnXML.API.StAX.Reader.new()

      # With validation pipeline
      reader = File.stream!("data.xml")
               |> FnXML.Parser.parse()
               |> FnXML.Event.Validate.well_formed()
               |> FnXML.API.StAX.Reader.new()

      # Quick create from string (convenience)
      reader = FnXML.API.StAX.Reader.new("<root attr='val'><child>text</child></root>")

      # Advance to first event
      reader = FnXML.API.StAX.Reader.next(reader)
      FnXML.API.StAX.Reader.event_type(reader)     # => :start_element
      FnXML.API.StAX.Reader.local_name(reader)     # => "root"
      FnXML.API.StAX.Reader.attribute_value(reader, 0)  # => "val"

      # Continue advancing
      reader = FnXML.API.StAX.Reader.next(reader)
      FnXML.API.StAX.Reader.local_name(reader)     # => "child"

      reader = FnXML.API.StAX.Reader.next(reader)
      FnXML.API.StAX.Reader.event_type(reader)     # => :characters
      FnXML.API.StAX.Reader.text(reader)           # => "text"

  ## Valid Methods by Event Type

  | Event | Valid Accessors |
  |-------|-----------------|
  | `:start_element` | `local_name`, `name`, `prefix`, `namespace_uri`, `attribute_*`, `namespace_*` |
  | `:end_element` | `local_name`, `name`, `prefix`, `namespace_uri` |
  | `:characters`, `:cdata`, `:comment` | `text`, `whitespace?` |
  | `:start_document` | `version`, `encoding`, `standalone?` |
  | `:processing_instruction` | `pi_target`, `pi_data` |
  | All events | `event_type`, `has_next?`, `location` |

  ## Iteration Pattern

      reader = FnXML.Parser.parse(xml) |> FnXML.API.StAX.Reader.new()

      defp process(reader) do
        if FnXML.API.StAX.Reader.has_next?(reader) do
          reader = FnXML.API.StAX.Reader.next(reader)
          # Process current event...
          process(reader)
        else
          reader
        end
      end
  """

  defstruct [
    # {:stream, stream} | {:cont, continuation} | :done
    :stream_state,
    # Current event
    :current,
    # Current event type atom
    :event_type,
    # Current location
    :location,
    # Document prolog info
    :prolog
  ]

  @type t :: %__MODULE__{
          stream_state: {:stream, Enumerable.t()} | {:cont, function()} | :done,
          current: tuple() | nil,
          event_type: atom() | nil,
          location: {integer(), integer()} | nil,
          prolog: map() | nil
        }

  @doc """
  Create a new StAX reader for the given source.

  ## Parameters

  - `source` - Either an XML string (binary) or an event stream from `FnXML.Parser.parse/1`

  ## Options

  - `:namespaces` - Enable namespace resolution (default: false for raw names)

  ## Examples

      # From parser stream (recommended)
      reader = FnXML.Parser.parse("<root/>")
               |> FnXML.API.StAX.Reader.new()

      # With transforms/validators
      reader = FnXML.Parser.parse(xml)
               |> FnXML.Event.Validate.well_formed()
               |> FnXML.Namespaces.resolve()
               |> FnXML.API.StAX.Reader.new()

      # From string (convenience)
      reader = FnXML.API.StAX.Reader.new("<root/>")
  """
  @spec new(String.t() | Enumerable.t(), keyword()) :: t()
  def new(source, opts \\ [])

  def new(source, opts) when is_binary(source) do
    resolve_namespaces = Keyword.get(opts, :namespaces, false)

    stream = FnXML.Parser.parse(source)

    stream =
      if resolve_namespaces do
        FnXML.Namespaces.resolve(stream)
      else
        stream
      end

    # Keep stream lazy, filter synthetic events on-the-fly
    filtered_stream = Stream.reject(stream, &synthetic_event?/1)

    %__MODULE__{
      stream_state: {:stream, filtered_stream},
      current: nil,
      event_type: nil,
      location: nil,
      prolog: nil
    }
  end

  def new(stream, _opts) do
    # Keep stream lazy, filter synthetic events on-the-fly
    filtered_stream = Stream.reject(stream, &synthetic_event?/1)

    %__MODULE__{
      stream_state: {:stream, filtered_stream},
      current: nil,
      event_type: nil,
      location: nil,
      prolog: nil
    }
  end

  # Check if event is synthetic (doc_start/doc_end)
  defp synthetic_event?({:start_document, _}), do: true
  defp synthetic_event?({:end_document, _}), do: true
  defp synthetic_event?(_), do: false

  @doc """
  Close the reader and release resources.
  """
  @spec close(t()) :: :ok
  def close(%__MODULE__{}), do: :ok

  @doc """
  Advance to the next event.

  Returns the updated reader positioned at the next event.
  Uses lazy evaluation - only pulls one event from the stream at a time.
  """
  @spec next(t()) :: t()
  def next(%__MODULE__{stream_state: :done} = reader) do
    %{reader | current: nil, event_type: :end_document}
  end

  def next(%__MODULE__{stream_state: {:stream, stream}} = reader) do
    # First pull from a fresh stream
    pull_and_update(reader, stream)
  end

  def next(%__MODULE__{stream_state: {:cont, continuation}} = reader) do
    # Continue from suspended stream
    case continuation.({:cont, :no_element}) do
      {:suspended, {:element, event}, new_cont} ->
        {event_type, location, prolog} = parse_event(event, reader.prolog)

        %{
          reader
          | stream_state: {:cont, new_cont},
            current: event,
            event_type: event_type,
            location: location,
            prolog: prolog
        }

      {:done, _} ->
        %{reader | stream_state: :done, current: nil, event_type: :end_document}

      {:halted, _} ->
        %{reader | stream_state: :done, current: nil, event_type: :end_document}
    end
  end

  # Pull one element from a stream using Enumerable.reduce with suspend
  defp pull_and_update(reader, stream) do
    result =
      Enumerable.reduce(stream, {:cont, :no_element}, fn elem, _acc ->
        {:suspend, {:element, elem}}
      end)

    case result do
      {:suspended, {:element, event}, continuation} ->
        {event_type, location, prolog} = parse_event(event, reader.prolog)

        %{
          reader
          | stream_state: {:cont, continuation},
            current: event,
            event_type: event_type,
            location: location,
            prolog: prolog
        }

      {:done, _} ->
        %{reader | stream_state: :done, current: nil, event_type: :end_document}

      {:halted, _} ->
        %{reader | stream_state: :done, current: nil, event_type: :end_document}
    end
  end

  @doc """
  Check if there are more events.

  Note: For lazy streams, this performs a peek operation which may
  trigger parsing of the next event.
  """
  @spec has_next?(t()) :: boolean()
  def has_next?(%__MODULE__{stream_state: :done}), do: false

  def has_next?(%__MODULE__{stream_state: {:stream, stream}}) do
    # Peek at the stream to check if there are elements
    case Enumerable.reduce(stream, {:cont, :empty}, fn _elem, _acc ->
           {:halt, :has_elements}
         end) do
      {:halted, :has_elements} -> true
      {:done, :empty} -> false
    end
  end

  def has_next?(%__MODULE__{stream_state: {:cont, continuation}}) do
    # Peek at continuation to check if there are more elements
    case continuation.({:cont, :empty}) do
      {:suspended, _, _} -> true
      {:done, _} -> false
      {:halted, _} -> false
    end
  end

  @doc """
  Skip to the next element (START_ELEMENT or END_ELEMENT).

  Skips whitespace, comments, and processing instructions.
  """
  @spec next_tag(t()) :: t()
  def next_tag(reader) do
    reader = next(reader)

    case reader.event_type do
      type when type in [:start_element, :end_element, :end_document] ->
        reader

      :characters ->
        if whitespace?(reader) do
          next_tag(reader)
        else
          reader
        end

      _ ->
        next_tag(reader)
    end
  end

  @doc """
  Get the current event type.
  """
  @spec event_type(t()) :: atom() | nil
  def event_type(%__MODULE__{event_type: type}), do: type

  @doc """
  Check if current event is START_ELEMENT.
  """
  @spec start_element?(t()) :: boolean()
  def start_element?(%__MODULE__{event_type: :start_element}), do: true
  def start_element?(_), do: false

  @doc """
  Check if current event is END_ELEMENT.
  """
  @spec end_element?(t()) :: boolean()
  def end_element?(%__MODULE__{event_type: :end_element}), do: true
  def end_element?(_), do: false

  @doc """
  Check if current event is CHARACTERS.
  """
  @spec characters?(t()) :: boolean()
  def characters?(%__MODULE__{event_type: :characters}), do: true
  def characters?(_), do: false

  @doc """
  Get the local name of the current element.

  Valid for START_ELEMENT and END_ELEMENT events.
  """
  @spec local_name(t()) :: String.t() | nil
  # 6-tuple from parser with expanded name
  def local_name(%__MODULE__{current: {:start_element, {_uri, local}, _, _, _, _}}), do: local
  # 6-tuple from parser with string tag
  def local_name(%__MODULE__{current: {:start_element, tag, _, _, _, _}}) when is_binary(tag),
    do: parse_local(tag)

  # 4-tuple with expanded name
  def local_name(%__MODULE__{current: {:start_element, {_uri, local}, _, _}}), do: local
  # 4-tuple with string tag
  def local_name(%__MODULE__{current: {:start_element, tag, _, _}}) when is_binary(tag),
    do: parse_local(tag)

  # 5-tuple from parser with expanded name
  def local_name(%__MODULE__{current: {:end_element, {_uri, local}, _, _, _}}), do: local
  # 5-tuple from parser with string tag
  def local_name(%__MODULE__{current: {:end_element, tag, _, _, _}}) when is_binary(tag),
    do: parse_local(tag)

  # 3-tuple with expanded name
  def local_name(%__MODULE__{current: {:end_element, {_uri, local}, _}}), do: local
  # 3-tuple with string tag
  def local_name(%__MODULE__{current: {:end_element, tag, _}}) when is_binary(tag),
    do: parse_local(tag)

  # 2-tuple legacy format (no position)
  def local_name(%__MODULE__{current: {:end_element, {_uri, local}}}), do: local

  def local_name(%__MODULE__{current: {:end_element, tag}}) when is_binary(tag),
    do: parse_local(tag)

  def local_name(_), do: nil

  @doc """
  Get the namespace URI of the current element.

  Valid for START_ELEMENT and END_ELEMENT events.
  """
  @spec namespace_uri(t()) :: String.t() | nil
  # 6-tuple from parser
  def namespace_uri(%__MODULE__{current: {:start_element, {uri, _local}, _, _, _, _}}), do: uri
  # 4-tuple
  def namespace_uri(%__MODULE__{current: {:start_element, {uri, _local}, _, _}}), do: uri
  # 5-tuple from parser
  def namespace_uri(%__MODULE__{current: {:end_element, {uri, _local}, _, _, _}}), do: uri
  # 3-tuple
  def namespace_uri(%__MODULE__{current: {:end_element, {uri, _local}, _}}), do: uri
  # 2-tuple legacy (no position)
  def namespace_uri(%__MODULE__{current: {:end_element, {uri, _local}}}), do: uri
  def namespace_uri(_), do: nil

  @doc """
  Get the prefix of the current element.

  Valid for START_ELEMENT and END_ELEMENT events.
  """
  @spec prefix(t()) :: String.t() | nil
  # 6-tuple from parser
  def prefix(%__MODULE__{current: {:start_element, tag, _, _, _, _}}) when is_binary(tag),
    do: parse_prefix(tag)

  # 4-tuple
  def prefix(%__MODULE__{current: {:start_element, tag, _, _}}) when is_binary(tag),
    do: parse_prefix(tag)

  # 5-tuple from parser
  def prefix(%__MODULE__{current: {:end_element, tag, _, _, _}}) when is_binary(tag),
    do: parse_prefix(tag)

  # 3-tuple
  def prefix(%__MODULE__{current: {:end_element, tag, _}}) when is_binary(tag),
    do: parse_prefix(tag)

  # 2-tuple legacy (no position)
  def prefix(%__MODULE__{current: {:end_element, tag}}) when is_binary(tag), do: parse_prefix(tag)
  def prefix(_), do: nil

  @doc """
  Get the name as `{namespace_uri, local_name}` tuple.

  Valid for START_ELEMENT and END_ELEMENT events.
  """
  @spec name(t()) :: {String.t() | nil, String.t()} | nil
  # 6-tuple from parser with expanded name
  def name(%__MODULE__{current: {:start_element, {uri, local}, _, _, _, _}}), do: {uri, local}
  # 6-tuple from parser with string tag
  def name(%__MODULE__{current: {:start_element, tag, _, _, _, _}}) when is_binary(tag),
    do: {nil, parse_local(tag)}

  # 4-tuple with expanded name
  def name(%__MODULE__{current: {:start_element, {uri, local}, _, _}}), do: {uri, local}
  # 4-tuple with string tag
  def name(%__MODULE__{current: {:start_element, tag, _, _}}) when is_binary(tag),
    do: {nil, parse_local(tag)}

  # 5-tuple from parser with expanded name
  def name(%__MODULE__{current: {:end_element, {uri, local}, _, _, _}}), do: {uri, local}
  # 5-tuple from parser with string tag
  def name(%__MODULE__{current: {:end_element, tag, _, _, _}}) when is_binary(tag),
    do: {nil, parse_local(tag)}

  # 3-tuple with expanded name
  def name(%__MODULE__{current: {:end_element, {uri, local}, _}}), do: {uri, local}
  # 3-tuple with string tag
  def name(%__MODULE__{current: {:end_element, tag, _}}) when is_binary(tag),
    do: {nil, parse_local(tag)}

  # 2-tuple legacy formats (no position)
  def name(%__MODULE__{current: {:end_element, {uri, local}}}), do: {uri, local}

  def name(%__MODULE__{current: {:end_element, tag}}) when is_binary(tag),
    do: {nil, parse_local(tag)}

  def name(_), do: nil

  @doc """
  Get the text content of the current event.

  Valid for CHARACTERS, COMMENT, CDATA, and DTD events.
  """
  @spec text(t()) :: String.t() | nil
  # 5-tuple from parser format
  def text(%__MODULE__{current: {:characters, content, _, _, _}}), do: content
  def text(%__MODULE__{current: {:comment, content, _, _, _}}), do: content
  def text(%__MODULE__{current: {:cdata, content, _, _, _}}), do: content
  def text(%__MODULE__{current: {:dtd, content, _, _, _}}), do: content
  # 3-tuple format
  def text(%__MODULE__{current: {:characters, content, _}}), do: content
  def text(%__MODULE__{current: {:comment, content, _}}), do: content
  def text(%__MODULE__{current: {:cdata, content, _}}), do: content
  def text(%__MODULE__{current: {:dtd, content, _}}), do: content
  def text(_), do: nil

  @doc """
  Read all text content within the current element.

  Must be positioned on START_ELEMENT. Advances reader to END_ELEMENT.
  """
  @spec element_text(t()) :: {String.t(), t()}
  def element_text(%__MODULE__{event_type: :start_element} = reader) do
    collect_text(reader, [], 1)
  end

  defp collect_text(reader, acc, depth) do
    reader = next(reader)

    case reader.event_type do
      :end_element when depth == 1 ->
        {acc |> Enum.reverse() |> Enum.join(), reader}

      :end_element ->
        collect_text(reader, acc, depth - 1)

      :start_element ->
        collect_text(reader, acc, depth + 1)

      :characters ->
        collect_text(reader, [text(reader) | acc], depth)

      :cdata ->
        collect_text(reader, [text(reader) | acc], depth)

      _ ->
        collect_text(reader, acc, depth)
    end
  end

  @doc """
  Check if current text is all whitespace.
  """
  @spec whitespace?(t()) :: boolean()
  # 5-tuple from parser format
  def whitespace?(%__MODULE__{current: {:characters, content, _, _, _}}) do
    String.trim(content) == ""
  end

  # 3-tuple format
  def whitespace?(%__MODULE__{current: {:characters, content, _}}) do
    String.trim(content) == ""
  end

  def whitespace?(_), do: false

  @doc """
  Get the number of attributes on current element.

  Valid for START_ELEMENT events.
  """
  @spec attribute_count(t()) :: non_neg_integer()
  # 6-tuple from parser format
  def attribute_count(%__MODULE__{current: {:start_element, _, attrs, _, _, _}}),
    do: length(attrs)

  # 4-tuple format
  def attribute_count(%__MODULE__{current: {:start_element, _, attrs, _}}), do: length(attrs)
  def attribute_count(_), do: 0

  @doc """
  Get attribute name at index as `{namespace_uri, local_name}`.
  """
  @spec attribute_name(t(), non_neg_integer()) :: {String.t() | nil, String.t()} | nil
  # 6-tuple from parser format
  def attribute_name(%__MODULE__{current: {:start_element, _, attrs, _, _, _}}, index) do
    get_attr_name(attrs, index)
  end

  # 4-tuple format
  def attribute_name(%__MODULE__{current: {:start_element, _, attrs, _}}, index) do
    get_attr_name(attrs, index)
  end

  def attribute_name(_, _), do: nil

  defp get_attr_name(attrs, index) do
    case Enum.at(attrs, index) do
      {name, _value} -> {nil, parse_local(name)}
      {uri, local, _value} -> {uri, local}
      nil -> nil
    end
  end

  @doc """
  Get attribute value at index.
  """
  @spec attribute_value(t(), non_neg_integer()) :: String.t() | nil
  # 6-tuple from parser format
  def attribute_value(%__MODULE__{current: {:start_element, _, attrs, _, _, _}}, index)
      when is_integer(index) do
    get_attr_value_by_index(attrs, index)
  end

  # 4-tuple format
  def attribute_value(%__MODULE__{current: {:start_element, _, attrs, _}}, index)
      when is_integer(index) do
    get_attr_value_by_index(attrs, index)
  end

  def attribute_value(_, index) when is_integer(index), do: nil

  defp get_attr_value_by_index(attrs, index) do
    case Enum.at(attrs, index) do
      {_name, value} -> value
      {_uri, _local, value} -> value
      nil -> nil
    end
  end

  @doc """
  Get attribute value by namespace URI and local name.
  """
  @spec attribute_value(t(), String.t() | nil, String.t()) :: String.t() | nil
  # 6-tuple from parser format
  def attribute_value(
        %__MODULE__{current: {:start_element, _, attrs, _, _, _}},
        ns_uri,
        local_name
      ) do
    get_attr_value_by_name(attrs, ns_uri, local_name)
  end

  # 4-tuple format
  def attribute_value(%__MODULE__{current: {:start_element, _, attrs, _}}, ns_uri, local_name) do
    get_attr_value_by_name(attrs, ns_uri, local_name)
  end

  def attribute_value(_, _, _), do: nil

  defp get_attr_value_by_name(attrs, ns_uri, local_name) do
    Enum.find_value(attrs, fn
      {^local_name, value} when is_nil(ns_uri) ->
        value

      {name, value} when is_nil(ns_uri) ->
        if parse_local(name) == local_name, do: value, else: nil

      {^ns_uri, ^local_name, value} ->
        value

      _ ->
        nil
    end)
  end

  @doc """
  Get the current location as `{line, column}`.
  """
  @spec location(t()) :: {integer(), integer()} | nil
  def location(%__MODULE__{location: loc}), do: loc

  @doc """
  Get the XML version from the prolog.
  """
  @spec version(t()) :: String.t() | nil
  def version(%__MODULE__{prolog: %{version: v}}), do: v
  def version(_), do: nil

  @doc """
  Get the encoding from the prolog.
  """
  @spec encoding(t()) :: String.t() | nil
  def encoding(%__MODULE__{prolog: %{encoding: e}}), do: e
  def encoding(_), do: nil

  @doc """
  Check if standalone is set in the prolog.
  """
  @spec standalone?(t()) :: boolean() | nil
  def standalone?(%__MODULE__{prolog: %{standalone: "yes"}}), do: true
  def standalone?(%__MODULE__{prolog: %{standalone: "no"}}), do: false
  def standalone?(_), do: nil

  @doc """
  Get the processing instruction target.
  """
  @spec pi_target(t()) :: String.t() | nil
  # 6-tuple from parser format
  def pi_target(%__MODULE__{current: {:processing_instruction, target, _, _, _, _}}), do: target
  # 4-tuple format
  def pi_target(%__MODULE__{current: {:processing_instruction, target, _, _}}), do: target
  def pi_target(_), do: nil

  @doc """
  Get the processing instruction data.
  """
  @spec pi_data(t()) :: String.t() | nil
  # 6-tuple from parser format
  def pi_data(%__MODULE__{current: {:processing_instruction, _, data, _, _, _}}), do: data
  # 4-tuple format
  def pi_data(%__MODULE__{current: {:processing_instruction, _, data, _}}), do: data
  def pi_data(_), do: nil

  # Parse event to determine type and location
  # 6-tuple from parser: {:start_element, tag, attrs, line, ls, pos}
  defp parse_event({:start_element, _, _, line, ls, pos}, prolog),
    do: {:start_element, {line, pos - ls}, prolog}

  # 4-tuple: {:start_element, tag, attrs, loc}
  defp parse_event({:start_element, _, _, loc}, prolog),
    do: {:start_element, loc_to_tuple(loc), prolog}

  # 5-tuple from parser: {:end_element, tag, line, ls, pos}
  defp parse_event({:end_element, _, line, ls, pos}, prolog),
    do: {:end_element, {line, pos - ls}, prolog}

  defp parse_event({:end_element, _}, prolog), do: {:end_element, nil, prolog}
  defp parse_event({:end_element, _, loc}, prolog), do: {:end_element, loc_to_tuple(loc), prolog}

  # 5-tuple from parser: {:characters, content, line, ls, pos}
  defp parse_event({:characters, _, line, ls, pos}, prolog),
    do: {:characters, {line, pos - ls}, prolog}

  # 3-tuple: {:characters, content, loc}
  defp parse_event({:characters, _, loc}, prolog), do: {:characters, loc_to_tuple(loc), prolog}

  # 5-tuple from parser: {:comment, content, line, ls, pos}
  defp parse_event({:comment, _, line, ls, pos}, prolog),
    do: {:comment, {line, pos - ls}, prolog}

  # 3-tuple: {:comment, content, loc}
  defp parse_event({:comment, _, loc}, prolog), do: {:comment, loc_to_tuple(loc), prolog}

  # 5-tuple from parser: {:cdata, content, line, ls, pos}
  defp parse_event({:cdata, _, line, ls, pos}, prolog),
    do: {:cdata, {line, pos - ls}, prolog}

  # 3-tuple: {:cdata, content, loc}
  defp parse_event({:cdata, _, loc}, prolog), do: {:cdata, loc_to_tuple(loc), prolog}

  # 5-tuple from parser: {:dtd, content, line, ls, pos}
  defp parse_event({:dtd, _, line, ls, pos}, prolog),
    do: {:dtd, {line, pos - ls}, prolog}

  # 3-tuple: {:dtd, content, loc}
  defp parse_event({:dtd, _, loc}, prolog), do: {:dtd, loc_to_tuple(loc), prolog}

  # 6-tuple from parser: {:processing_instruction, target, data, line, ls, pos}
  defp parse_event({:processing_instruction, _, _, line, ls, pos}, prolog),
    do: {:processing_instruction, {line, pos - ls}, prolog}

  # 4-tuple: {:processing_instruction, target, data, loc}
  defp parse_event({:processing_instruction, _, _, loc}, prolog),
    do: {:processing_instruction, loc_to_tuple(loc), prolog}

  # 6-tuple from parser: {:prolog, name, attrs, line, ls, pos}
  defp parse_event({:prolog, _, attrs, line, ls, pos}, _prolog) do
    prolog_map =
      attrs
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Enum.into(%{})

    {:start_document, {line, pos - ls}, prolog_map}
  end

  # 4-tuple: {:prolog, name, attrs, loc}
  defp parse_event({:prolog, _, attrs, loc}, _prolog) do
    prolog_map =
      attrs
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Enum.into(%{})

    {:start_document, loc_to_tuple(loc), prolog_map}
  end

  defp parse_event({:start_document, _}, prolog), do: {:start_document, nil, prolog}
  defp parse_event({:end_document, _}, prolog), do: {:end_document, nil, prolog}

  # 6-tuple from parser: {:error, type, msg, line, ls, pos}
  defp parse_event({:error, _, _, line, ls, pos}, prolog),
    do: {:error, {line, pos - ls}, prolog}

  # 4-tuple: {:error, type, msg, loc}
  defp parse_event({:error, _, _, loc}, prolog), do: {:error, loc_to_tuple(loc), prolog}
  defp parse_event(_, prolog), do: {nil, nil, prolog}

  defp loc_to_tuple({line, line_start, byte_offset}) do
    {line, byte_offset - line_start}
  end

  defp loc_to_tuple(nil), do: nil

  defp parse_local(qname) when is_binary(qname) do
    case String.split(qname, ":", parts: 2) do
      [local] -> local
      [_prefix, local] -> local
    end
  end

  defp parse_prefix(qname) when is_binary(qname) do
    case String.split(qname, ":", parts: 2) do
      [_local] -> nil
      [prefix, _local] -> prefix
    end
  end
end
