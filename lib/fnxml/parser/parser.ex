# Check if Zig/Zigler is available at compile time
# The entire module definition is conditional to avoid macro expansion issues
if Code.ensure_loaded?(Zig) and FnXML.MixProject.nif_enabled?() do
  defmodule FnXML.Parser do
    @moduledoc """
    High-performance XML parser with NIF acceleration and pure Elixir fallback.

    Automatically selects between Zig NIF (for large blocks) and pure Elixir
    (for small blocks) based on the 60KB threshold where their performance crosses.

    ## Options

    - `:parser` - Force parser selection: `:nif`, `:elixir`, or `:auto` (default)
    - `:threshold` - Cutoff size in bytes for auto-selection (default: 60KB).
      Inputs smaller than this use Elixir; larger inputs use NIF.
    - `:block_size` - For stream inputs: specify your chunk size in bytes.
      Since streams can't be inspected, this tells auto-selection what size
      to compare against the threshold. If omitted, defaults to threshold (selecting NIF).
    - `:max_join_count` - Maximum chunk joins before error (default: 10)

    ## Usage

        # Auto-select parser (default)
        events = FnXML.Parser.stream("<root/>") |> Enum.to_list()

        # Force NIF parser
        events = FnXML.Parser.stream(xml, parser: :nif) |> Enum.to_list()

        # Force Elixir parser
        events = FnXML.Parser.stream(xml, parser: :elixir) |> Enum.to_list()

        # Stream from file with auto-selection
        events = File.stream!("large.xml", [], 65536)
                 |> FnXML.Parser.stream(block_size: 65536)
                 |> Enum.to_list()
    """

    use Zig,
      otp_app: :fnxml,
      zig_code_path: "NifParser.zig",
      nifs: [nif_parse: [:dirty_cpu]]

    # Threshold for auto-selecting NIF vs Elixir (bytes)
    # Below this, Elixir is faster due to NIF call overhead
    # Based on binary search benchmarking: crossover at ~64KB
    @auto_threshold 61_440

    @doc """
    Returns true if NIF acceleration is available.
    """
    def nif_enabled?, do: true

    @doc """
    Stream XML from a file or enumerable, parsing in chunks.
    """
    def stream(source, opts \\ [])

    def stream(source, opts) when is_binary(source) do
      delegate_stream =
        case select_parser(byte_size(source), opts) do
          :nif -> nif_stream([source], opts)
          :elixir -> FnXML.ExBlkParser.stream([source])
        end

      wrap_with_document_events(delegate_stream)
    end

    def stream(source, opts) do
      delegate_stream =
        case select_parser_for_stream(opts) do
          :nif -> nif_stream(source, opts)
          :elixir -> FnXML.ExBlkParser.stream(source)
        end

      wrap_with_document_events(delegate_stream)
    end

    defp wrap_with_document_events(delegate_stream) do
      Stream.concat([
        [{:start_document, nil}],
        delegate_stream,
        [{:end_document, nil}]
      ])
    end

    @doc """
    Parse XML and return all events as a list.
    """
    def parse(source, opts \\ []) do
      stream(source, opts) |> Enum.to_list()
    end

    @doc """
    Low-level: parse a single block using the NIF.

    Returns `{events, leftover_pos, new_state}` where:
    - `events` - List of parsed event tuples
    - `leftover_pos` - Position where parsing stopped, or `nil` if complete
    - `new_state` - Updated `{line, column, byte_offset}` state
    """
    def parse_block(block, prev_block, prev_pos, {line, col, byte}) do
      {events, leftover_pos, new_state} = nif_parse(block, prev_block, prev_pos, line, col, byte)
      flattened_events = Enum.map(events, &flatten_event/1)
      {flattened_events, leftover_pos, new_state}
    end

    # ============================================================================
    # Parser Selection
    # ============================================================================

    defp select_parser(size, opts) do
      case Keyword.get(opts, :parser, :auto) do
        :auto ->
          threshold = Keyword.get(opts, :threshold, @auto_threshold)
          if size < threshold, do: :elixir, else: :nif
        :nif -> :nif
        :elixir -> :elixir
      end
    end

    defp select_parser_for_stream(opts) do
      case Keyword.get(opts, :parser, :auto) do
        :auto ->
          threshold = Keyword.get(opts, :threshold, @auto_threshold)
          block_size = Keyword.get(opts, :block_size, threshold)
          if block_size < threshold, do: :elixir, else: :nif
        :nif -> :nif
        :elixir -> :elixir
      end
    end

    # ============================================================================
    # NIF Streaming Implementation
    # ============================================================================

    defp nif_stream(source, opts) do
      max_join_count = Keyword.get(opts, :max_join_count, 10)

      Stream.resource(
        fn -> init_stream_state(source) end,
        fn state -> next_events(state, max_join_count) end,
        fn _state -> :ok end
      )
    end

    defp init_stream_state(source) when is_binary(source) do
      %{
        source: [source],
        prev_block: nil,
        prev_pos: 0,
        parser_state: {1, 0, 0},
        join_count: 0
      }
    end

    defp init_stream_state(source) do
      %{
        source: source,
        prev_block: nil,
        prev_pos: 0,
        parser_state: {1, 0, 0},
        join_count: 0
      }
    end

    defp next_events(%{source: source} = state, max_join_count) do
      case get_next_chunk(source) do
        {:ok, chunk, rest_source} -> handle_chunk(state, chunk, rest_source, max_join_count)
        :eof -> handle_eof(state)
      end
    end

    defp handle_chunk(state, chunk, rest_source, max_join_count) do
      {events, leftover_pos, new_parser_state} =
        nif_parse_with_prev(chunk, state.prev_block, state.prev_pos, state.parser_state)

      case find_advance_error(events) do
        nil ->
          emit_events(state, events, leftover_pos, new_parser_state, chunk, rest_source)

        _error when state.join_count >= max_join_count ->
          {[{:error, :advance, "Element exceeds maximum chunk span", {0, 0, 0}}],
           %{state | source: []}}

        _error ->
          retry_with_joined_chunk(state, chunk, rest_source, max_join_count)
      end
    end

    defp nif_parse_with_prev(chunk, prev_block, prev_pos, {line, col, byte}) do
      nif_parse(chunk, prev_block, prev_pos, line, col, byte)
    end

    defp emit_events(state, events, leftover_pos, new_parser_state, chunk, rest_source) do
      {new_prev_block, new_prev_pos} =
        compute_leftover_state(leftover_pos, state.prev_block, state.prev_pos, chunk)

      new_state = %{
        state
        | source: rest_source,
          prev_block: new_prev_block,
          prev_pos: new_prev_pos,
          parser_state: new_parser_state,
          join_count: 0
      }

      flattened_events = events |> filter_advance_errors() |> Enum.map(&flatten_event/1)
      {flattened_events, new_state}
    end

    defp compute_leftover_state(nil, _prev_block, _prev_pos, _chunk), do: {nil, 0}

    defp compute_leftover_state(0, prev, prev_pos, chunk) when prev != nil do
      combined = binary_part(prev, prev_pos, byte_size(prev) - prev_pos) <> chunk
      {combined, 0}
    end

    defp compute_leftover_state(pos, _prev_block, _prev_pos, chunk), do: {chunk, pos}

    defp retry_with_joined_chunk(state, chunk, rest_source, max_join_count) do
      joined = join_with_previous(state.prev_block, state.prev_pos, chunk)

      new_state = %{
        state
        | source: [joined | rest_source],
          prev_block: nil,
          prev_pos: 0,
          join_count: state.join_count + 1
      }

      next_events(new_state, max_join_count)
    end

    defp join_with_previous(nil, _prev_pos, chunk), do: chunk

    defp join_with_previous(prev_block, prev_pos, chunk) do
      binary_part(prev_block, prev_pos, byte_size(prev_block) - prev_pos) <> chunk
    end

    defp handle_eof(%{prev_block: nil} = state), do: {:halt, state}

    defp handle_eof(state) do
      remaining =
        binary_part(
          state.prev_block,
          state.prev_pos,
          byte_size(state.prev_block) - state.prev_pos
        )

      if byte_size(remaining) > 0 do
        # Parse remaining data, looping if NIF hits MAX_EVENTS
        {all_events, _final_state} = parse_remaining(remaining, state.parser_state, [])
        flattened_events = Enum.map(all_events, &flatten_event/1)
        {flattened_events, %{state | source: [], prev_block: nil}}
      else
        {:halt, state}
      end
    end

    # Handle the case where NIF needs multiple iterations to parse remaining data
    # Pass data as block (not prev_block) so leftover_pos is relative to it
    defp parse_remaining(data, parser_state, acc_events) do
      {events, leftover_pos, new_parser_state} =
        nif_parse_with_prev(data, nil, 0, parser_state)

      filtered_events = filter_advance_errors(events)
      all_events = acc_events ++ filtered_events

      case leftover_pos do
        nil ->
          # Done parsing
          {all_events, new_parser_state}

        pos when pos > 0 ->
          # More data remains, continue parsing from pos
          remaining = binary_part(data, pos, byte_size(data) - pos)
          if byte_size(remaining) > 0 do
            parse_remaining(remaining, new_parser_state, all_events)
          else
            {all_events, new_parser_state}
          end

        0 ->
          # leftover_pos = 0 means no progress was made, avoid infinite loop
          {all_events, new_parser_state}
      end
    end

    defp get_next_chunk([chunk | rest]) when is_binary(chunk), do: {:ok, chunk, rest}
    defp get_next_chunk([]), do: :eof

    defp get_next_chunk(stream) do
      case Enum.take(stream, 1) do
        [chunk] -> {:ok, chunk, Stream.drop(stream, 1)}
        [] -> :eof
      end
    end

    defp find_advance_error(events) do
      Enum.find(events, fn
        {:error, :advance, _, _} -> true
        _ -> false
      end)
    end

    defp filter_advance_errors(events) do
      Enum.reject(events, fn
        {:error, :advance, _, _} -> true
        _ -> false
      end)
    end

    # Convert NIF events with tuple locations to flattened format
    defp flatten_event({:start_element, tag, attrs, {line, ls, pos}}),
      do: {:start_element, tag, attrs, line, ls, pos}

    defp flatten_event({:end_element, tag, {line, ls, pos}}),
      do: {:end_element, tag, line, ls, pos}

    defp flatten_event({:characters, text, {line, ls, pos}}),
      do: {:characters, text, line, ls, pos}

    defp flatten_event({:space, text, {line, ls, pos}}),
      do: {:space, text, line, ls, pos}

    defp flatten_event({:comment, text, {line, ls, pos}}),
      do: {:comment, text, line, ls, pos}

    defp flatten_event({:cdata, text, {line, ls, pos}}),
      do: {:cdata, text, line, ls, pos}

    defp flatten_event({:dtd, content, {line, ls, pos}}),
      do: {:dtd, content, line, ls, pos}

    defp flatten_event({:prolog, name, attrs, {line, ls, pos}}),
      do: {:prolog, name, attrs, line, ls, pos}

    defp flatten_event({:processing_instruction, target, data, {line, ls, pos}}),
      do: {:processing_instruction, target, data, line, ls, pos}

    defp flatten_event({:error, type, msg, {line, ls, pos}}),
      do: {:error, type, msg, line, ls, pos}

    # Pass through already flat or unknown events
    defp flatten_event(event), do: event
  end
else
  defmodule FnXML.Parser do
    @moduledoc """
    XML parser (pure Elixir mode - NIF not available).

    This module provides the same API as the NIF-accelerated parser but uses
    pure Elixir implementation. It is used when:

    1. Zig/Zigler is not installed
    2. `FNXML_NIF=false` environment variable is set
    3. Parent project specifies `{:fnxml, "~> x.x", nif: false}` in deps

    All parsing is delegated to `FnXML.ExBlkParser`.
    """

    @doc """
    Returns true if NIF acceleration is available.
    """
    def nif_enabled?, do: false

    @doc """
    Stream XML from a file or enumerable.

    Options are accepted for API compatibility but `:parser` is ignored
    since only Elixir mode is available.
    """
    def stream(source, _opts \\ [])

    def stream(source, _opts) when is_binary(source) do
      wrap_with_document_events(FnXML.ExBlkParser.stream([source]))
    end

    def stream(source, _opts) do
      wrap_with_document_events(FnXML.ExBlkParser.stream(source))
    end

    defp wrap_with_document_events(delegate_stream) do
      Stream.concat([
        [{:start_document, nil}],
        delegate_stream,
        [{:end_document, nil}]
      ])
    end

    @doc """
    Parse XML and return all events as a list.
    """
    def parse(source, opts \\ []) do
      stream(source, opts) |> Enum.to_list()
    end

    @doc """
    Low-level: parse a single block.

    Delegates to `FnXML.ExBlkParser.parse_block/6`.
    """
    def parse_block(block, prev_block, prev_pos, {line, ls, abs_pos}) do
      FnXML.ExBlkParser.parse_block(block, prev_block, prev_pos, line, ls, abs_pos)
    end
  end
end
