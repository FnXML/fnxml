defmodule FnXML.Parser.SaxyAdapter do
  @moduledoc """
  Converts Saxy parse events to ExBlkParser event format.

  Saxy is a callback-based SAX parser. This adapter collects Saxy events
  and converts them to the stream event format used by ExBlkParser.

  **Note:** This module requires the optional `saxy` dependency. When Saxy
  is not available, the `parse/2` and `stream/2` functions will return an error.

  ## Limitations

  - No location tracking (all locations are `nil`)
  - Saxy doesn't emit DOCTYPE declarations
  - Saxy doesn't emit processing instructions (except xml declaration)
  - Comments require Saxy 1.6+ with `emit_comments: true` option

  ## Usage

      # Parse string
      events = FnXML.Parser.SaxyAdapter.parse("<root/>")

      # Stream from chunks
      events = FnXML.Parser.SaxyAdapter.stream(chunks) |> Enum.to_list()
  """

  # Only declare behaviour when Saxy is available (it's an optional dev dependency)
  @saxy_available Code.ensure_loaded?(Saxy)

  if @saxy_available do
    @behaviour Saxy.Handler
  end

  @doc """
  Parse XML string and return list of events in ExBlkParser format.

  Returns `[{:error, :saxy_not_available, nil, nil}]` if Saxy is not installed.
  """
  def parse(xml, opts \\ [])

  if @saxy_available do
    def parse(xml, _opts) do
      saxy_opts = [
        cdata_as_characters: false
      ]

      case Saxy.parse_string(xml, __MODULE__, [], saxy_opts) do
        {:ok, events} -> Enum.reverse(events)
        {:error, reason} -> [{:error, reason, nil, nil}]
      end
    end
  else
    def parse(_xml, _opts) do
      [{:error, :saxy_not_available, nil, nil}]
    end
  end

  @doc """
  Stream XML from enumerable and return stream of events in ExBlkParser format.

  Returns a stream with `{:error, :saxy_not_available, nil, nil}` if Saxy is not installed.
  """
  def stream(enumerable, opts \\ [])

  if @saxy_available do
    def stream(enumerable, _opts) do
      saxy_opts = [
        cdata_as_characters: false
      ]

      Stream.resource(
        fn -> init_stream(enumerable, saxy_opts) end,
        &next_events/1,
        fn _ -> :ok end
      )
    end

    defp init_stream(enumerable, saxy_opts) do
      case Saxy.parse_stream(enumerable, __MODULE__, [], saxy_opts) do
        {:ok, events} -> {Enum.reverse(events), :done}
        {:error, reason} -> {[{:error, reason, nil, nil}], :done}
      end
    end
  else
    def stream(_enumerable, _opts) do
      Stream.resource(
        fn -> {[{:error, :saxy_not_available, nil, nil}], :done} end,
        &next_events/1,
        fn _ -> :ok end
      )
    end
  end

  defp next_events({[], :done}), do: {:halt, :done}
  defp next_events({events, :done}), do: {events, {[], :done}}
  defp next_events(:done), do: {:halt, :done}

  # ============================================================================
  # Saxy.Handler callbacks (only defined when Saxy is available)
  # ============================================================================

  if @saxy_available do
    @doc false
    def handle_event(:start_document, prolog, events) do
      # Saxy prolog is keyword list: [version: "1.0", encoding: "UTF-8"]
      # ExBlkParser format: {:prolog, "xml", [{"version", "1.0"}, ...], location}
      attrs =
        prolog
        |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)

      event = {:prolog, "xml", attrs, nil}
      {:ok, [event | events]}
    end

    @doc false
    def handle_event(:end_document, _data, events) do
      # ExBlkParser doesn't emit end_document, skip it
      {:ok, events}
    end

    @doc false
    def handle_event(:start_element, {name, attributes}, events) do
      # Saxy format: {"name", [{"attr", "value"}, ...]}
      # ExBlkParser format: {:start_element, "name", [{"attr", "value"}], location}
      event = {:start_element, name, attributes, nil}
      {:ok, [event | events]}
    end

    @doc false
    def handle_event(:end_element, name, events) do
      # Saxy format: "name"
      # ExBlkParser format: {:end_element, "name", location}
      event = {:end_element, name, nil}
      {:ok, [event | events]}
    end

    @doc false
    def handle_event(:characters, chars, events) do
      # Saxy format: "text"
      # ExBlkParser format: {:characters, "text", location} or {:space, "  ", location}
      # Emit as :characters (no :space distinction without parsing original)
      event = {:characters, chars, nil}
      {:ok, [event | events]}
    end

    @doc false
    def handle_event(:cdata, cdata, events) do
      # Saxy format: "cdata content" (only with cdata_as_characters: false)
      # ExBlkParser format: {:cdata, "content", location}
      event = {:cdata, cdata, nil}
      {:ok, [event | events]}
    end

    @doc false
    def handle_event(:comment, comment, events) do
      # Saxy format: "comment text"
      # ExBlkParser format: {:comment, "comment text", location}
      event = {:comment, comment, nil}
      {:ok, [event | events]}
    end
  end
end
