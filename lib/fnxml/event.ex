defmodule FnXML.Event do
  @moduledoc """
  Serialize XML event streams to iodata.

  This module provides efficient event-to-XML serialization with support for
  multiple event formats and pretty printing.

  ## Event Formats

  Supports all FnXML event formats:

  ### Parser Format (6-tuple)
  ```elixir
  {:start_element, tag, attrs, line, ls, pos}
  {:end_element, tag, line, ls, pos}
  {:characters, content, line, ls, pos}
  {:comment, content, line, ls, pos}
  {:cdata, content, line, ls, pos}
  {:prolog, "xml", attrs, line, ls, pos}
  {:processing_instruction, target, data, line, ls, pos}
  ```

  ### Normalized Format (4-tuple)
  ```elixir
  {:start_element, tag, attrs, nil}
  {:end_element, tag, nil}
  {:characters, content, nil}
  ```

  ### Minimal Format (2-tuple)
  ```elixir
  {:end_element, tag}
  ```

  ## Options

  `to_iodata/2` supports the following options:

  - `:pretty` (boolean, default: false) - Format with indentation
  - `:indent` (integer | string, default: 2) - Indentation size or string

  ## Examples

      # Parse and serialize to string
      xml = FnXML.Parser.parse("<root><child/></root>")
      |> FnXML.Event.to_iodata()
      |> Enum.join()
      # => "<root><child/></root>"

      # Stream directly to file (efficient for large documents)
      File.open!("output.xml", [:write], fn file ->
        FnXML.Parser.parse(large_xml)
        |> FnXML.Event.to_iodata()
        |> Enum.each(&IO.binwrite(file, &1))
      end)

      # Collect to iodata for small documents
      iodata = FnXML.Parser.parse(xml)
      |> FnXML.Event.to_iodata()
      |> Enum.to_list()

      # Pretty print
      xml = FnXML.Parser.parse(xml)
      |> FnXML.Event.to_iodata(pretty: true, indent: 4)
      |> Enum.join()

      # DOM to XML
      doc = FnXML.API.DOM.parse("<root/>")
      xml = FnXML.API.DOM.to_event(doc)
      |> FnXML.Event.to_iodata()
      |> Enum.join()

      # Stream pipeline with validation to file
      File.open!("output.xml", [:write], fn file ->
        File.stream!("data.xml")
        |> FnXML.Parser.parse()
        |> FnXML.Event.Validate.well_formed()
        |> FnXML.Event.to_iodata()
        |> Enum.each(&IO.binwrite(file, &1))
      end)
  """

  @doc """
  Serialize event stream to iodata fragments.

  Returns a **lazy stream of iodata fragments** that can be consumed incrementally.
  This enables processing large XML documents without loading the entire
  serialized output into memory.

  ## Options

  - `:pretty` - Format with indentation (default: false)
  - `:indent` - Number of spaces or string for indentation (default: 2)

  ## Returns

  A lazy stream that emits iodata fragments (binaries or iolists). Each fragment
  is emitted as XML events are processed.

  ## Examples

      # Stream directly to file (efficient for large documents)
      File.open!("output.xml", [:write], fn file ->
        FnXML.Parser.parse(large_xml)
        |> FnXML.Event.to_iodata()
        |> Enum.each(&IO.binwrite(file, &1))
      end)

      # Collect to iodata for small documents
      iodata = FnXML.Parser.parse("<root><child/></root>")
      |> FnXML.Event.to_iodata()
      |> Enum.to_list()

      # Convert to string
      xml = FnXML.Parser.parse(xml)
      |> FnXML.Event.to_iodata()
      |> Enum.join()

      # Pretty print to string
      xml = FnXML.Parser.parse(xml)
      |> FnXML.Event.to_iodata(pretty: true, indent: 4)
      |> Enum.join()

      # Custom indent string
      xml = FnXML.Event.to_iodata(events, pretty: true, indent: "\\t")
      |> Enum.join()

      # Convert to binary blocks for network/file streaming
      FnXML.Parser.parse(large_xml)
      |> FnXML.Event.to_iodata()
      |> FnXML.Event.iodata_to_binary_block(8192)  # 8KB chunks
      |> Enum.each(&send_over_network/1)

      # Stream large file with transformations
      File.open!("output.xml", [:write], fn file ->
        File.stream!("input.xml")
        |> FnXML.Parser.parse()
        |> FnXML.Event.Validate.well_formed()
        |> FnXML.Event.to_iodata(pretty: true)
        |> Enum.each(&IO.binwrite(file, &1))
      end)
  """
  @spec to_iodata(Enumerable.t(), keyword()) :: Enumerable.t()
  def to_iodata(stream, opts \\ []) do
    pretty = Keyword.get(opts, :pretty, false)
    indent_size = Keyword.get(opts, :indent, 2)

    # Accumulator: pending state for self-closing detection
    # pending = nil | {tag, attrs_str, depth}
    initial_acc = nil

    stream
    |> transform(initial_acc, fn element, path, pending ->
      # Format event → {output_fragment, new_pending}
      {output, new_pending} = format(element, path, pending, pretty, indent_size)

      # Emit output if non-empty, otherwise just update accumulator
      if output == "" do
        new_pending
      else
        {output, new_pending}
      end
    end)
  end

  @doc """
  Convert an iodata fragment stream to binary chunks of approximately the specified size.

  Takes the lazy stream of iodata fragments from `to_iodata/2` and combines them
  into larger binary chunks. This is useful for:
  - Writing to files with controlled buffer sizes
  - Sending over network with specific packet sizes
  - Controlling memory usage when processing large documents

  ## Parameters

  - `iodata_stream` - Stream of iodata fragments (from `to_iodata/2`)
  - `chunk_size` - Target size in bytes (default: 65536 / 64KB)

  ## Returns

  A lazy stream that emits binary chunks of approximately `chunk_size` bytes.
  The final chunk may be smaller than `chunk_size`.

  ## Examples

      # Stream to file with 8KB chunks
      File.open!("output.xml", [:write], fn file ->
        FnXML.Parser.parse(large_xml)
        |> FnXML.Event.to_iodata()
        |> FnXML.Event.iodata_to_binary_block(8192)
        |> Enum.each(&IO.binwrite(file, &1))
      end)

      # Stream to file with File.stream! (default 64KB chunks)
      FnXML.Parser.parse(large_xml)
      |> FnXML.Event.to_iodata()
      |> FnXML.Event.iodata_to_binary_block()
      |> Stream.into(File.stream!("output.xml"))
      |> Stream.run()

      # Custom chunk size for network transmission
      FnXML.Parser.parse(xml)
      |> FnXML.Event.to_iodata()
      |> FnXML.Event.iodata_to_binary_block(1024)  # 1KB chunks
      |> Enum.each(&send_over_network/1)

      # Collect chunks into a list
      chunks = FnXML.Parser.parse(xml)
      |> FnXML.Event.to_iodata()
      |> FnXML.Event.iodata_to_binary_block(4096)
      |> Enum.to_list()

  ## Performance

  This function efficiently tracks the size of accumulated iodata fragments
  without materializing them until a chunk is ready to emit. It only converts
  to binary when emitting a chunk, minimizing allocations.
  """
  @spec iodata_to_binary_block(Enumerable.t(), pos_integer()) :: Enumerable.t()
  def iodata_to_binary_block(iodata_stream, chunk_size \\ 65536) do
    Stream.chunk_while(
      iodata_stream,
      # Accumulator: {list_of_fragments, accumulated_size}
      {[], 0},
      fn fragment, {acc_fragments, acc_size} ->
        # Calculate size of this fragment
        fragment_size = IO.iodata_length(fragment)
        new_fragments = [fragment | acc_fragments]
        new_size = acc_size + fragment_size

        # If we've accumulated enough, emit a chunk
        if new_size >= chunk_size do
          # Convert accumulated iodata to binary (reversing to maintain order)
          binary = IO.iodata_to_binary(Enum.reverse(new_fragments))
          {:cont, binary, {[], 0}}
        else
          # Keep accumulating
          {:cont, {new_fragments, new_size}}
        end
      end,
      # After function: emit any remaining accumulated data
      fn
        {[], 0} ->
          # No leftover data
          {:cont, {[], 0}}

        {fragments, _size} ->
          # Emit final chunk (may be smaller than chunk_size)
          binary = IO.iodata_to_binary(Enum.reverse(fragments))
          {:cont, binary, {[], 0}}
      end
    )
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  # Format a single event, handling self-closing tag detection
  defp format(element, path, pending, pretty, indent_size) do
    # Returns: {output_iodata, new_pending}
    # pending = nil | {tag, attrs_str, depth}

    case {element, pending} do
      # Self-closing tag: end_element matching pending start
      {{:end_element, tag}, {tag, attrs_str, depth}} ->
        output = format_self_closing(tag, attrs_str, depth, pretty, indent_size)
        {output, nil}

      {{:end_element, tag, _line, _ls, _pos}, {tag, attrs_str, depth}} ->
        output = format_self_closing(tag, attrs_str, depth, pretty, indent_size)
        {output, nil}

      # Regular end_element: flush pending, then emit close tag
      {{:end_element, _tag} = elem, pending} ->
        flushed = flush_pending(pending, pretty, indent_size)
        {depth, formatted} = format_element(elem, path, nil)
        output = format_output(flushed, formatted, depth, pretty, indent_size)
        {output, nil}

      {{:end_element, _tag, _line, _ls, _pos} = elem, pending} ->
        flushed = flush_pending(pending, pretty, indent_size)
        {depth, formatted} = format_element(elem, path, nil)
        output = format_output(flushed, formatted, depth, pretty, indent_size)
        {output, nil}

      # start_element: store as pending for self-closing detection
      {{:start_element, tag, attrs, nil}, pending} ->
        flushed = flush_pending(pending, pretty, indent_size)
        attrs_str = format_attributes(attrs)
        depth = length(path) - 1
        {flushed, {tag, attrs_str, depth}}

      {{:start_element, tag, attrs, _line, _ls, _pos}, pending} ->
        flushed = flush_pending(pending, pretty, indent_size)
        attrs_str = format_attributes(attrs)
        depth = length(path) - 1
        {flushed, {tag, attrs_str, depth}}

      # Other events: flush pending, then format current
      {element, pending} ->
        flushed = flush_pending(pending, pretty, indent_size)
        {depth, formatted} = format_element(element, path, nil)
        output = format_output(flushed, formatted, depth, pretty, indent_size)
        {output, nil}
    end
  end

  # Flush a pending start tag (emit opening tag)
  defp flush_pending(nil, _pretty, _indent_size), do: ""

  defp flush_pending({tag, attrs_str, depth}, pretty, indent_size) do
    if pretty do
      indent = build_indent(indent_size, depth)
      "#{indent}<#{tag}#{attrs_str}>\n"
    else
      "<#{tag}#{attrs_str}>"
    end
  end

  # Format a self-closing tag
  defp format_self_closing(tag, attrs_str, depth, pretty, indent_size) do
    if pretty do
      indent = build_indent(indent_size, depth)
      "#{indent}<#{tag}#{attrs_str}/>\n"
    else
      "<#{tag}#{attrs_str}/>"
    end
  end

  # Combine flushed output with formatted element
  defp format_output("", formatted, depth, pretty, indent_size) do
    if pretty do
      indent = build_indent(indent_size, depth)
      "#{indent}#{formatted}\n"
    else
      formatted
    end
  end

  defp format_output(flushed, formatted, depth, pretty, indent_size) do
    if pretty do
      indent = build_indent(indent_size, depth)
      "#{flushed}#{indent}#{formatted}\n"
    else
      "#{flushed}#{formatted}"
    end
  end

  # Build indentation string
  defp build_indent(indent_size, depth) when is_integer(indent_size) do
    String.duplicate(" ", indent_size * depth)
  end

  defp build_indent(indent_str, depth) when is_binary(indent_str) do
    String.duplicate(indent_str, depth)
  end

  defp build_indent(_, depth) do
    # Fallback for invalid indent (use 2 spaces)
    String.duplicate(" ", 2 * depth)
  end

  # Format attributes as string
  defp format_attributes([]), do: ""

  defp format_attributes(attrs) do
    attrs
    |> Enum.map(fn {k, v} -> "#{k}=\"#{escape_attr(v)}\"" end)
    |> Enum.join(" ")
    |> add_leading_space()
  end

  defp add_leading_space(""), do: ""
  defp add_leading_space(str), do: " " <> str

  # Escape special XML characters in text content
  defp escape_text(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  # Escape special XML characters in attribute values
  defp escape_attr(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  # Format individual elements based on event type

  # Document start/end markers emit nothing
  defp format_element({:start_document, _}, path, _acc), do: {length(path), ""}
  defp format_element({:end_document, _}, path, _acc), do: {length(path), ""}

  # 6-tuple format (from parser)
  defp format_element({:prolog, tag, attrs, _line, _ls, _pos}, path, _acc) do
    attrs_str = format_attributes(attrs)
    {length(path), "<?#{tag}#{attrs_str}?>"}
  end

  defp format_element({:start_element, tag, attrs, _line, _ls, _pos}, path, _acc) do
    attrs_str = format_attributes(attrs)
    {length(path) - 1, "<#{tag}#{attrs_str}>"}
  end

  defp format_element({:end_element, tag, _line, _ls, _pos}, path, _acc) do
    {length(path) - 1, "</#{tag}>"}
  end

  defp format_element({:characters, content, _line, _ls, _pos}, path, _acc) do
    {length(path), escape_text(content)}
  end

  defp format_element({:space, content, _line, _ls, _pos}, path, _acc) do
    {length(path), content}
  end

  defp format_element({:cdata, content, _line, _ls, _pos}, path, _acc) do
    {length(path), "<![CDATA[#{content}]]>"}
  end

  defp format_element({:comment, content, _line, _ls, _pos}, path, _acc) do
    {length(path), "<!--#{content}-->"}
  end

  defp format_element({:processing_instruction, name, nil, _line, _ls, _pos}, path, _acc) do
    {length(path), "<?#{name}?>"}
  end

  defp format_element({:processing_instruction, name, content, _line, _ls, _pos}, path, _acc) do
    {length(path), "<?#{name} #{content}?>"}
  end

  defp format_element({:dtd, content, _line, _ls, _pos}, path, _acc) do
    {length(path), content}
  end

  # 4-tuple and 3-tuple formats (with nil location)
  defp format_element({:start_element, tag, attrs, nil}, path, _acc) do
    attrs_str = format_attributes(attrs)
    {length(path) - 1, "<#{tag}#{attrs_str}>"}
  end

  defp format_element({:end_element, tag}, path, _acc) do
    {length(path) - 1, "</#{tag}>"}
  end

  defp format_element({:characters, content, nil}, path, _acc) do
    {length(path), escape_text(content)}
  end

  defp format_element({:space, content, nil}, path, _acc) do
    {length(path), content}
  end

  defp format_element({:cdata, content, nil}, path, _acc) do
    {length(path), "<![CDATA[#{content}]]>"}
  end

  defp format_element({:comment, content, nil}, path, _acc) do
    {length(path), "<!--#{content}-->"}
  end

  @doc """
  Apply a transform function to a stream of XML elements with path tracking.

  This function processes XML events while maintaining a stack of open tags (the path).
  The transform function receives each event, the current path, and an accumulator,
  enabling powerful stream transformations with structural context.

  ## Parameters

  - `stream` - The XML event stream
  - `acc` - Initial accumulator value (default: [])
  - `fun` - Transform function that receives:
    - `element` - Current event, e.g., `{:start_element, "foo", [], 1, 0, 1}`
    - `path` - Stack of open tags, e.g., `[{"bar", ""}, {"foo", ""}]`
    - `acc` - Current accumulator value

  ## Return Value

  The transform function should return:
  - `acc` - Continue without emitting anything downstream
  - `{element, acc}` - Emit element and continue with new accumulator

  ## Path Structure

  The path is a list of tuples where:
  - First element is the tag name
  - Second element is the namespace URI (empty string if none)

  ## Examples

      # Extract all text content from <item> elements
      FnXML.Parser.parse(xml)
      |> FnXML.Event.transform([], fn
        {:characters, content, _, _, _}, [{"item", _} | _], acc ->
          {content, acc}
        _, _, acc ->
          acc
      end)
      |> Enum.to_list()

      # Pass through all events unchanged
      FnXML.Parser.parse(xml)
      |> FnXML.Event.transform(fn element, _path, acc ->
        {element, acc}
      end)
      |> Enum.to_list()

  ## Validation

  This function validates XML structure as it processes events:
  - Ensures proper tag nesting
  - Detects mismatched closing tags
  - Validates text content is inside elements
  - Injects `{:error, :validation, message, ...}` events into the stream for structural errors

  Error events follow the same format as parser errors and include position information
  when available from the source event.

  See `FnXML.Event.Filter` for common filtering operations.
  """
  @valid_element_id FnXML.Element.id_list()

  @spec transform(Enumerable.t(), any(), function()) :: Enumerable.t()
  def transform(stream, acc \\ [], fun) do
    stream
    |> Stream.chunk_while(initial_acc(acc, fun), &process_item/2, &after_fn/1)
  end

  defp initial_acc(acc, fun), do: {[], acc, fun}

  # 6-element start_element: {:start_element, tag, attrs, line, ls, pos}
  defp process_item({:start_element, tag, _attrs, _line, _ls, _pos} = element, {stack, acc, fun}) do
    tag_tuple = FnXML.Element.tag(tag)
    new_stack = [tag_tuple | stack]
    fun.(element, new_stack, acc) |> next(new_stack, fun)
  end

  # 4-element start_element (no location): {:start_element, tag, attrs, nil}
  defp process_item({:start_element, tag, _attrs, nil} = element, {stack, acc, fun}) do
    tag_tuple = FnXML.Element.tag(tag)
    new_stack = [tag_tuple | stack]
    fun.(element, new_stack, acc) |> next(new_stack, fun)
  end

  # 5-element end_element: {:end_element, tag, line, ls, pos}
  defp process_item({:end_element, _tag, _line, _ls, _pos} = element, {[], acc, fun}) do
    tag_str = FnXML.Element.tag_string(element)
    error(element, "unexpected close tag #{tag_str}, missing open tag", [], acc, fun)
  end

  defp process_item(
         {:end_element, tag, _line, _ls, _pos} = element,
         {[head | new_stack] = stack, acc, fun}
       ) do
    tag_tuple = FnXML.Element.tag(tag)

    cond do
      tag_tuple == head ->
        fun.(element, stack, acc) |> next(new_stack, fun)

      tag_tuple != head ->
        error(
          element,
          "mis-matched close tag #{inspect(tag_tuple)}, expecting: #{FnXML.Element.tag_name(head)}",
          stack,
          acc,
          fun
        )
    end
  end

  # 2-element end_element (no location): {:end_element, tag}
  defp process_item({:end_element, tag} = element, {[], acc, fun}) do
    error(element, "unexpected close tag #{tag}, missing open tag", [], acc, fun)
  end

  defp process_item({:end_element, tag} = element, {[head | new_stack] = stack, acc, fun}) do
    tag_tuple = FnXML.Element.tag(tag)

    cond do
      tag_tuple == head ->
        fun.(element, stack, acc) |> next(new_stack, fun)

      tag_tuple != head ->
        error(
          element,
          "mis-matched close tag #{inspect(tag_tuple)}, expecting: #{FnXML.Element.tag_name(head)}",
          stack,
          acc,
          fun
        )
    end
  end

  # 5-element characters: {:characters, content, line, ls, pos}
  defp process_item({:characters, content, _line, _ls, _pos} = element, {[], acc, fun}) do
    if String.match?(content, ~r/^[\s\n]*$/) do
      acc |> next([], fun)
    else
      error(
        element,
        "Text element outside root element",
        [],
        acc,
        fun
      )
    end
  end

  # 5-element space: {:space, content, line, ls, pos}
  defp process_item({:space, _content, _line, _ls, _pos}, {[], acc, fun}) do
    # Whitespace outside root element is ignored
    acc |> next([], fun)
  end

  # Generic handlers for 3-element, 5-element, and 6-element events
  defp process_item({id, _, nil} = element, {stack, acc, fun}) when id in @valid_element_id do
    fun.(element, stack, acc) |> next(stack, fun)
  end

  defp process_item({id, _, _, _, _} = element, {stack, acc, fun}) when id in @valid_element_id do
    fun.(element, stack, acc) |> next(stack, fun)
  end

  defp process_item({id, _, _, _, _, _} = element, {stack, acc, fun})
       when id in @valid_element_id do
    fun.(element, stack, acc) |> next(stack, fun)
  end

  # Document start/end markers - pass through without modifying stack
  defp process_item({:start_document, _} = element, {stack, acc, fun}) do
    fun.(element, stack, acc) |> next(stack, fun)
  end

  defp process_item({:end_document, _} = element, {stack, acc, fun}) do
    fun.(element, stack, acc) |> next(stack, fun)
  end

  defp process_item(element, {stack, acc, fun}) do
    error(element, "unknown element type #{inspect(element)}", stack, acc, fun)
  end

  defp next({element, acc}, stack, fun), do: {:cont, element, {stack, acc, fun}}
  defp next(acc, stack, fun), do: {:cont, {stack, acc, fun}}

  defp after_fn([]), do: {:cont, []}
  defp after_fn(acc), do: {:cont, acc}

  defp error(element, msg, stack, acc, fun) do
    # Extract position information from the element if available
    error_event =
      case element do
        {_, _, _, line, ls, pos} ->
          {:error, :validation, msg, line, ls, pos}

        {_, _, line, ls, pos} ->
          {:error, :validation, msg, line, ls, pos}

        _ ->
          {:error, :validation, msg}
      end

    {:cont, error_event, {stack, acc, fun}}
  end

  @doc """
  Tap into a stream of XML elements for debugging or side effects.

  Allows inspection of events as they pass through the stream without
  modifying them. Useful for debugging, logging, or sending events to
  external systems.

  ## Parameters

  - `stream` - The XML event stream
  - `fun` - Optional inspection function (default: prints to console)
  - `opts` - Options:
    - `:label` - Label to prefix console output (default: "")

  ## Inspection Function

  If provided, `fun` must accept two arguments:
  - `element` - Current event, e.g., `{:start_element, "foo", [], 1, 0, 1}`
  - `path` - Stack of open tags, e.g., `[{"bar", ""}, {"foo", ""}]`

  The return value is discarded. The stream is not modified.

  ## Examples

      # Debug with default console output
      FnXML.Parser.parse(xml)
      |> FnXML.Event.tap(label: "debug")
      |> Enum.to_list()

      # Custom inspection function
      FnXML.Parser.parse(xml)
      |> FnXML.Event.tap(fn event, path ->
        IO.inspect({event, path}, label: "XML Event")
      end, label: "parser")
      |> Enum.to_list()

      # Send events to another process
      FnXML.Parser.parse(xml)
      |> FnXML.Event.tap(fn event, _path ->
        send(monitor_pid, {:xml_event, event})
      end, label: "monitor")
      |> Enum.to_list()
  """
  @spec tap(Enumerable.t(), function() | nil, keyword()) :: Enumerable.t()
  def tap(stream, fun \\ nil, opts) do
    label = Keyword.get(opts, :label, "")

    inspect_fun =
      fun ||
        fn element, path ->
          IO.puts("#{label}: #{inspect(element)}, path: #{inspect(path)}")
        end

    inspector = fn element, path, _ ->
      inspect_fun.(element, path)
      {element, []}
    end

    transform(stream, inspector)
  end

  @doc """
  Filter XML events based on a predicate function with path context.

  Filters events in the stream using a custom predicate. The predicate
  receives the event, current path, and an accumulator, enabling stateful
  filtering decisions based on document structure.

  ## Parameters

  - `stream` - The XML event stream
  - `fun` - Filter predicate function
  - `acc` - Initial accumulator value (default: [])

  ## Filter Function

  The predicate must accept three arguments and return `{boolean, acc}`:
  - `element` - Current event
  - `path` - Stack of open tags
  - `acc` - Current accumulator

  Return:
  - `{true, acc}` - Include the event, continue with new accumulator
  - `{false, acc}` - Exclude the event, continue with new accumulator

  Document start/end markers (`{:start_document, _}` and `{:end_document, _}`)
  are always passed through regardless of the filter predicate.

  ## Examples

      # Keep only <bar> elements and their contents
      stream = FnXML.Parser.parse("<foo><bar>1</bar><bar>2</bar></foo>")
      FnXML.Event.filter(stream, fn _, [{tag, ""} | _], _ ->
        {tag == "bar", []}
      end)
      |> Enum.to_list()

      # Filter with state - skip every other element
      FnXML.Event.filter(stream, fn _, _, count ->
        {rem(count, 2) == 0, count + 1}
      end, 0)
      |> Enum.to_list()

      # Remove specific characters events
      FnXML.Event.filter(stream, fn
        {:characters, "skip", _, _, _}, _, acc -> {false, acc}
        _, _, acc -> {true, acc}
      end)
      |> Enum.to_list()
  """
  @spec filter(Enumerable.t(), function(), any()) :: Enumerable.t()
  def filter(stream, fun, acc \\ []) do
    transform(
      stream,
      acc,
      fn
        # Pass through document start/end markers
        {:start_document, _} = element, _path, acc ->
          {element, acc}

        {:end_document, _} = element, _path, acc ->
          {element, acc}

        element, path, acc ->
          case fun.(element, path, acc) do
            {true, acc} -> {element, acc}
            {false, acc} -> acc
          end
      end
    )
  end
end
