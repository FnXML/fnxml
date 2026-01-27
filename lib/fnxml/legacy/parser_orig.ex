defmodule FnXML.Legacy.ParserOrig do
  @moduledoc """
  Legacy streaming XML parser using recursive descent with continuation-passing style.

  **Note**: This parser is kept for benchmarking and historical comparison only.
  It is a dead code candidate and may be removed in future versions.
  For production use, prefer `FnXML.Parser` instead.

  Parses XML into a stream of events (SAX-style). Each event represents a
  structural element of the XML document, emitted as the parser encounters it.

  ## Specifications

  - W3C XML 1.0 (Fifth Edition): https://www.w3.org/TR/xml/

  ## Basic Usage

  ### Stream Mode (Lazy Evaluation)

  The most common way to use the parser. Events are generated lazily as you
  consume the stream:

      # Parse and inspect all events
      FnXML.Parser.parse("<root><item>Hello</item></root>")
      |> Enum.each(&IO.inspect/1)

      # Extract specific data
      FnXML.Parser.parse(xml)
      |> Enum.filter(fn {:characters, _, _} -> true; _ -> false end)
      |> Enum.map(fn {:characters, content, _} -> content end)

      # Take only the first N events (efficient - stops parsing early)
      FnXML.Parser.parse(large_xml)
      |> Enum.take(10)

      # Pipe through stream transformations
      FnXML.Parser.parse(xml)
      |> FnXML.Transform.Stream.filter_ws()           # Remove whitespace-only text
      |> FnXML.Transform.Stream.resolve_entities()    # Expand &amp; etc.
      |> Enum.to_list()

  ### Callback Mode (Eager, Zero Allocation)

  For maximum performance when processing the entire document. The callback
  receives each event directly with no intermediate data structures:

      # Send events to a process
      FnXML.Parser.parse(xml, fn event -> send(pid, event) end)

      # Collect in an agent (building result in reverse for efficiency)
      {:ok, agent} = Agent.start_link(fn -> [] end)
      FnXML.Parser.parse(xml, fn event -> Agent.update(agent, &[event | &1]) end)
      events = Agent.get(agent, &Enum.reverse/1)

      # Direct processing with side effects
      FnXML.Parser.parse(xml, fn
        {:start_element, "target", attrs, _} -> handle_target(attrs)
        {:characters, content, _} -> accumulate_text(content)
        _ -> :ok
      end)

  ## Event Types

  The parser emits these event types:

  ### Document Start: `{:start_document, nil}`

  Emitted as the very first event when parsing begins. Useful for
  initialization in stream consumers.

  ### Document End: `{:end_document, nil}`

  Emitted as the very last event when parsing completes. Useful for
  finalization in stream consumers.

  ### Open Tag: `{:start_element, tag, attrs, loc}`

  Emitted when an opening tag is encountered. Self-closing tags like `<br/>`
  emit both a `:start_element` and `:end_element` event.

      {:start_element, "div", [{"class", "container"}], {1, 0, 0}}
      {:start_element, "ns:element", [{"attr", "value"}], {2, 15, 20}}

  - `tag` - The tag name as a string (includes namespace prefix if present)
  - `attrs` - List of `{name, value}` tuples (both strings)
  - `loc` - Position tuple (see Position Information below)

  ### Close Tag: `{:end_element, tag}` or `{:end_element, tag, loc}`

  Emitted when a closing tag is encountered. Self-closing tags emit `{:end_element, tag}`
  without location. Explicit closing tags include location.

      {:end_element, "div"}                        # From self-closing <div/>
      {:end_element, "div", {1, 0, 25}}            # From explicit </div>

  ### Text: `{:characters, content, loc}`

  Emitted for text content between tags. CDATA sections are also emitted as
  text events (the CDATA markers are stripped).

      {:characters, "Hello, World!", {1, 0, 5}}
      {:characters, "  whitespace  ", {2, 20, 25}}

  Note: Whitespace-only text between elements is preserved. Use
  `FnXML.Transform.Stream.filter_ws/1` to remove it.

  ### Comment: `{:comment, content, loc}`

  Emitted for XML comments. The `<!--` and `-->` delimiters are stripped.

      {:comment, " This is a comment ", {1, 0, 0}}

  ### Prolog: `{:prolog, "xml", attrs, loc}`

  Emitted for the XML declaration at the start of a document.

      {:prolog, "xml", [{"version", "1.0"}, {"encoding", "UTF-8"}], {1, 0, 1}}

  ### Processing Instruction: `{:processing_instruction, target, content, loc}`

  Emitted for processing instructions like `<?target content?>`.

      {:processing_instruction, "xml-stylesheet", "type=\"text/xsl\" href=\"style.xsl\"", {1, 0, 1}}

  ### Error: `{:error, message, loc}`

  Emitted when the parser encounters malformed XML. See Error Handling below.

      {:error, "Expected '>'", {3, 45, 67}}

  ## Position Information

  Every event includes a location tuple `{line, line_start, byte_offset}`:

  | Field | Description |
  |-------|-------------|
  | `line` | 1-based line number |
  | `line_start` | Byte offset where the current line begins |
  | `byte_offset` | Absolute byte position from document start |

  The position points to the **start** of each event:
  - For tags: the `<` character
  - For text: the first character of content
  - For comments: the `<` of `<!--`

  To calculate the column number:

      {line, line_start, byte_offset} = loc
      column = byte_offset - line_start    # 0-based column

  Use `FnXML.Element.position/1` to get `{line, column}` directly:

      FnXML.Element.position({:start_element, "div", [], {2, 15, 20}})
      # => {2, 5}

  ## Error Handling

  The parser handles errors by emitting `{:error, message, loc}` events.
  Unlike exception-based parsers, this allows:

  - **Partial processing**: Extract valid data even from malformed documents
  - **Error collection**: Gather all errors in a single pass
  - **Graceful degradation**: Continue processing after recoverable errors

  Common error messages:

  | Error | Cause |
  |-------|-------|
  | `"Expected '?>'"` | Unterminated XML declaration |
  | `"Expected '>' "` | Unclosed tag |
  | `"Expected quoted value"` | Attribute value not quoted |
  | `"Unterminated comment"` | Missing `-->` |
  | `"Unterminated CDATA"` | Missing `]]>` |
  | `"Invalid element"` | Malformed tag syntax |

  Example error handling:

      events = FnXML.Parser.parse(xml) |> Enum.to_list()

      errors = Enum.filter(events, fn {:error, _, _} -> true; _ -> false end)
      if errors != [] do
        Enum.each(errors, fn {:error, msg, {line, _, _}} ->
          IO.puts("Line \#{line}: \#{msg}")
        end)
      end

  ## Performance Optimizations

  This parser is designed for high throughput and low memory usage:

  ### Memory Efficiency

  - **Single binary reference**: The original XML string is kept as one binary.
    Content is extracted using `binary_part/3` which creates sub-binary
    references, not copies. This means parsing a 100MB file uses ~100MB, not
    multiples thereof.

  - **Position tracking over sub-binaries**: Instead of creating new "rest"
    binaries at each step (which would copy), the parser tracks position as
    an integer offset into the original binary.

  - **No intermediate AST**: Events are emitted directly without building a
    tree structure. This enables processing documents larger than available
    memory via streaming.

  ### Speed Optimizations

  - **Continuation-passing style (CPS)**: Parsing state flows through function
    arguments rather than return values, enabling tail-call optimization and
    reducing stack frame allocation.

  - **Inlined name scanning**: Tag and attribute name parsing is inlined at
    each call site, avoiding function call overhead for the most frequent
    operations.

  - **Dual code paths**: Stream mode uses accumulator-based functions optimized
    for batch collection. Callback mode avoids accumulator overhead entirely.

  - **Binary pattern matching**: The BEAM's optimized binary matching is used
    throughout. Multi-byte patterns like `<!--` are matched directly.

  - **Whitespace skipping**: Whitespace between elements is skipped without
    creating events, reducing downstream processing.

  - **Guard-based dispatch**: Character class checks use guards and ranges,
    which the BEAM optimizes into efficient jump tables.

  ### Benchmarks

  Typical performance on modern hardware (2024):

  - **~500+ MB/s** throughput for simple documents
  - **~100,000+ elements/s** for typical XML structures
  - **Constant memory** regardless of document size (streaming mode)
  """

  defguardp is_name_start(c)
            when c in ?a..?z or c in ?A..?Z or c == ?_ or c == ?: or
                   c in 0x00C0..0x00D6 or c in 0x00D8..0x00F6 or
                   c in 0x00F8..0x02FF or c in 0x0370..0x037D or
                   c in 0x037F..0x1FFF or c in 0x200C..0x200D or
                   c in 0x2070..0x218F or c in 0x2C00..0x2FEF or
                   c in 0x3001..0xD7FF or c in 0xF900..0xFDCF or
                   c in 0xFDF0..0xFFFD or c in 0x10000..0xEFFFF

  defguardp is_name_char(c)
            when is_name_start(c) or c == ?- or c == ?. or c in ?0..?9 or
                   c == 0x00B7 or c in 0x0300..0x036F or c in 0x203F..0x2040

  # Calculate byte size of a UTF-8 codepoint
  defp utf8_size(c) when c < 0x80, do: 1
  defp utf8_size(c) when c < 0x800, do: 2
  defp utf8_size(c) when c < 0x10000, do: 3
  defp utf8_size(_), do: 4

  @doc """
  Parse XML into a lazy stream of events.

  Returns an `Enumerable` that emits events as they are consumed. Parsing
  happens on-demand, making this memory-efficient for large documents and
  allowing early termination with functions like `Enum.take/2`.

  ## Parameters

  - `xml` - The XML document as a binary string

  ## Returns

  A `Stream` of events. See module documentation for event types.

  ## Examples

      iex> FnXML.Parser.parse("<root>Hello</root>") |> Enum.to_list()
      [
        {:start_document, nil},
        {:start_element, "root", [], {1, 0, 1}},
        {:characters, "Hello", {1, 0, 6}},
        {:end_element, "root", {1, 0, 12}},
        {:end_document, nil}
      ]

      iex> FnXML.Parser.parse("<a><b/></a>") |> Enum.take(3)
      [{:start_document, nil}, {:start_element, "a", [], {1, 0, 1}}, {:start_element, "b", [], {1, 0, 4}}]

  """
  def parse(xml) when is_binary(xml) do
    check_encoding!(xml)

    Stream.resource(
      fn -> {:start, xml, 0, 1, 0} end,
      &next_event/1,
      fn _ -> :ok end
    )
  end

  # Detect UTF-16 BOM and raise helpful error
  defp check_encoding!(<<0xFF, 0xFE, _::binary>>) do
    raise ArgumentError, """
    UTF-16 Little Endian encoding detected (BOM: 0xFF 0xFE).

    FnXML.Parser expects UTF-8 input. Convert first:

        xml = File.read!("file.xml") |> FnXML.Transform.Utf16.to_utf8()
        FnXML.Parser.parse(xml)
    """
  end

  defp check_encoding!(<<0xFE, 0xFF, _::binary>>) do
    raise ArgumentError, """
    UTF-16 Big Endian encoding detected (BOM: 0xFE 0xFF).

    FnXML.Parser expects UTF-8 input. Convert first:

        xml = File.read!("file.xml") |> FnXML.Transform.Utf16.to_utf8()
        FnXML.Parser.parse(xml)
    """
  end

  defp check_encoding!(_), do: :ok

  @doc """
  Parse XML with a custom emit callback for maximum performance.

  This is the fastest way to parse XML when you need to process the entire
  document. Each event is passed directly to your callback with zero
  intermediate allocations.

  ## Parameters

  - `xml` - The XML document as a binary string
  - `emit` - A function that receives each event as it's parsed

  ## Returns

  `{:ok, final_pos, final_line, final_line_start}` on successful completion,
  where these values represent the parser's final position in the document.

  ## Examples

      # Count elements
      counter = :counters.new(1, [:atomics])
      FnXML.Parser.parse(xml, fn
        {:start_element, _, _, _} -> :counters.add(counter, 1, 1)
        _ -> :ok
      end)
      :counters.get(counter, 1)

      # Send events to a process
      FnXML.Parser.parse(xml, fn event -> send(pid, event) end)

      # Build a result (note: prepend for efficiency, reverse at end)
      {:ok, agent} = Agent.start_link(fn -> [] end)
      FnXML.Parser.parse(xml, fn event ->
        Agent.update(agent, &[event | &1])
      end)
      events = Agent.get(agent, &Enum.reverse/1)

  ## When to Use

  Use callback mode when:
  - Processing very large documents where stream overhead matters
  - You need to process every event (no early termination)
  - Building custom accumulators or sending to other processes
  - Maximum throughput is critical

  Use `parse/1` (stream mode) when:
  - You want lazy evaluation
  - You might terminate early (`Enum.take`, `Enum.find`, etc.)
  - You want to compose with other stream operations
  - Code readability is prioritized over raw performance

  """
  def parse(xml, emit) when is_binary(xml) and is_function(emit, 1) do
    check_encoding!(xml)
    emit.({:start_document, nil})
    result = do_parse_all(xml, xml, 0, 1, 0, emit)
    emit.({:end_document, nil})
    result
  end

  # === Stream interface (fast accumulator path) ===

  # Emit :start_document as the first event
  defp next_event({:start, xml, pos, line, ls}) do
    {[{:start_document, nil}], {xml, pos, line, ls}}
  end

  # End of document - emit :end_document and halt
  defp next_event({xml, pos, _line, _ls}) when pos >= byte_size(xml) do
    {[{:end_document, nil}], :done}
  end

  # Already done - halt the stream
  defp next_event(:done) do
    {:halt, nil}
  end

  defp next_event({xml, pos, line, ls}) do
    rest = binary_part(xml, pos, byte_size(xml) - pos)
    {events, pos, line, ls} = do_parse_one_acc(rest, xml, pos, line, ls, [])
    {Enum.reverse(events), {xml, pos, line, ls}}
  end

  # Fast accumulator-based parsing for streams (no callback overhead)
  defp do_parse_one_acc(<<>>, _xml, pos, line, ls, acc), do: {acc, pos, line, ls}

  # XML declaration must be followed by whitespace - <?xml without whitespace is a PI
  defp do_parse_one_acc(<<"<?xml ", rest::binary>>, xml, pos, line, ls, acc) do
    parse_prolog_acc(rest, xml, pos + 6, line, ls, {line, ls, pos + 1}, acc)
  end

  defp do_parse_one_acc(<<"<?xml\t", rest::binary>>, xml, pos, line, ls, acc) do
    parse_prolog_acc(rest, xml, pos + 6, line, ls, {line, ls, pos + 1}, acc)
  end

  defp do_parse_one_acc(<<"<?xml\r", rest::binary>>, xml, pos, line, ls, acc) do
    parse_prolog_acc(rest, xml, pos + 6, line, ls, {line, ls, pos + 1}, acc)
  end

  defp do_parse_one_acc(<<"<?xml\n", rest::binary>>, xml, pos, line, _ls, acc) do
    parse_prolog_acc(rest, xml, pos + 6, line + 1, pos + 6, {line, pos + 6 - 6, pos + 1}, acc)
  end

  defp do_parse_one_acc(<<"<", _::binary>> = rest, xml, pos, line, ls, acc) do
    parse_element_acc(rest, xml, pos, line, ls, acc)
  end

  defp do_parse_one_acc(<<c, rest::binary>>, xml, pos, line, ls, acc) when c in [?\s, ?\t, ?\r] do
    do_parse_one_acc(rest, xml, pos + 1, line, ls, acc)
  end

  defp do_parse_one_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, acc) do
    do_parse_one_acc(rest, xml, pos + 1, line + 1, pos + 1, acc)
  end

  defp do_parse_one_acc(rest, xml, pos, line, ls, acc) do
    parse_text_acc(rest, xml, pos, line, ls, {line, ls, pos}, pos, acc)
  end

  # === Full parse with callback (no stream) ===

  defp do_parse_all(<<>>, _xml, pos, line, ls, _emit) do
    {:ok, pos, line, ls}
  end

  defp do_parse_all(rest, xml, pos, line, ls, emit) do
    {pos, line, ls} = do_parse_one(rest, xml, pos, line, ls, emit)
    new_rest = binary_part(xml, pos, byte_size(xml) - pos)
    do_parse_all(new_rest, xml, pos, line, ls, emit)
  end

  # === Main dispatch - parse one event ===

  defp do_parse_one(<<>>, _xml, pos, line, ls, _emit) do
    {pos, line, ls}
  end

  # XML declaration must be followed by whitespace - <?xml without whitespace is a PI
  defp do_parse_one(<<"<?xml ", rest::binary>>, xml, pos, line, ls, emit) do
    parse_prolog(rest, xml, pos + 6, line, ls, {line, ls, pos + 1}, emit)
  end

  defp do_parse_one(<<"<?xml\t", rest::binary>>, xml, pos, line, ls, emit) do
    parse_prolog(rest, xml, pos + 6, line, ls, {line, ls, pos + 1}, emit)
  end

  defp do_parse_one(<<"<?xml\r", rest::binary>>, xml, pos, line, ls, emit) do
    parse_prolog(rest, xml, pos + 6, line, ls, {line, ls, pos + 1}, emit)
  end

  defp do_parse_one(<<"<?xml\n", rest::binary>>, xml, pos, line, _ls, emit) do
    parse_prolog(rest, xml, pos + 6, line + 1, pos + 6, {line, pos + 6 - 6, pos + 1}, emit)
  end

  defp do_parse_one(<<"<", _::binary>> = rest, xml, pos, line, ls, emit) do
    parse_element(rest, xml, pos, line, ls, emit)
  end

  defp do_parse_one(<<c, rest::binary>>, xml, pos, line, ls, emit) when c in [?\s, ?\t, ?\r] do
    do_parse_one(rest, xml, pos + 1, line, ls, emit)
  end

  defp do_parse_one(<<?\n, rest::binary>>, xml, pos, line, _ls, emit) do
    do_parse_one(rest, xml, pos + 1, line + 1, pos + 1, emit)
  end

  defp do_parse_one(rest, xml, pos, line, ls, emit) do
    parse_text(rest, xml, pos, line, ls, {line, ls, pos}, pos, emit)
  end

  # === Prolog ===

  defp parse_prolog(<<"?>", _::binary>>, _xml, pos, line, ls, loc, emit) do
    emit.({:prolog, "xml", [], loc})
    {pos + 2, line, ls}
  end

  defp parse_prolog(<<c, rest::binary>>, xml, pos, line, ls, loc, emit)
       when c in [?\s, ?\t, ?\r] do
    parse_prolog(rest, xml, pos + 1, line, ls, loc, emit)
  end

  defp parse_prolog(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, emit) do
    parse_prolog(rest, xml, pos + 1, line + 1, pos + 1, loc, emit)
  end

  defp parse_prolog(<<c::utf8, _::binary>> = rest, xml, pos, line, ls, loc, emit)
       when is_name_start(c) do
    parse_prolog_attr_name(rest, xml, pos, line, ls, loc, [], pos, emit)
  end

  defp parse_prolog(_, _xml, pos, line, ls, _loc, emit) do
    emit.({:error, "Expected '?>' or attribute", {line, ls, pos}})
    {pos, line, ls}
  end

  # Prolog with attrs
  defp parse_prolog_attrs(<<"?>", _::binary>>, _xml, pos, line, ls, loc, attrs, emit) do
    emit.({:prolog, "xml", Enum.reverse(attrs), loc})
    {pos + 2, line, ls}
  end

  defp parse_prolog_attrs(<<c, rest::binary>>, xml, pos, line, ls, loc, attrs, emit)
       when c in [?\s, ?\t, ?\r] do
    parse_prolog_attrs(rest, xml, pos + 1, line, ls, loc, attrs, emit)
  end

  defp parse_prolog_attrs(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, attrs, emit) do
    parse_prolog_attrs(rest, xml, pos + 1, line + 1, pos + 1, loc, attrs, emit)
  end

  defp parse_prolog_attrs(<<c::utf8, _::binary>> = rest, xml, pos, line, ls, loc, attrs, emit)
       when is_name_start(c) do
    parse_prolog_attr_name(rest, xml, pos, line, ls, loc, attrs, pos, emit)
  end

  defp parse_prolog_attrs(_, _xml, pos, line, ls, _loc, _attrs, emit) do
    emit.({:error, "Expected '?>' or attribute", {line, ls, pos}})
    {pos, line, ls}
  end

  # === Element dispatch ===

  defp parse_element(<<"<!--", rest::binary>>, xml, pos, line, ls, emit) do
    parse_comment(rest, xml, pos + 4, line, ls, {line, ls, pos + 1}, pos + 4, emit)
  end

  defp parse_element(<<"<![CDATA[", rest::binary>>, xml, pos, line, ls, emit) do
    parse_cdata(rest, xml, pos + 9, line, ls, {line, ls, pos + 1}, pos + 9, emit)
  end

  defp parse_element(<<"<!DOCTYPE", rest::binary>>, xml, pos, line, ls, emit) do
    parse_doctype(rest, xml, pos + 9, line, ls, {line, ls, pos + 1}, pos + 2, 1, nil, emit)
  end

  defp parse_element(<<"</", rest::binary>>, xml, pos, line, ls, emit) do
    parse_close_tag_name(rest, xml, pos + 2, line, ls, {line, ls, pos + 1}, pos + 2, emit)
  end

  defp parse_element(<<"<?", rest::binary>>, xml, pos, line, ls, emit) do
    parse_pi_name(rest, xml, pos + 2, line, ls, {line, ls, pos + 1}, pos + 2, emit)
  end

  defp parse_element(<<"<", c::utf8, _::binary>> = rest, xml, pos, line, ls, emit)
       when is_name_start(c) do
    <<"<", rest2::binary>> = rest
    parse_open_tag_name(rest2, xml, pos + 1, line, ls, {line, ls, pos + 1}, pos + 1, emit)
  end

  defp parse_element(_, _xml, pos, line, ls, emit) do
    emit.({:error, "Invalid element", {line, ls, pos}})
    {pos, line, ls}
  end

  # === Open tag name scanning (inlined) ===

  defp parse_open_tag_name(<<c::utf8, rest::binary>>, xml, pos, line, ls, loc, start, emit)
       when is_name_char(c) do
    parse_open_tag_name(rest, xml, pos + utf8_size(c), line, ls, loc, start, emit)
  end

  defp parse_open_tag_name(rest, xml, pos, line, ls, loc, start, emit) do
    name = binary_part(xml, start, pos - start)
    finish_open_tag(rest, xml, pos, line, ls, name, [], loc, emit)
  end

  # === Open tag finish ===

  defp finish_open_tag(<<"/>", _::binary>>, _xml, pos, line, ls, name, attrs, loc, emit) do
    emit.({:start_element, name, Enum.reverse(attrs), loc})
    emit.({:end_element, name})
    {pos + 2, line, ls}
  end

  defp finish_open_tag(<<">", _::binary>>, _xml, pos, line, ls, name, attrs, loc, emit) do
    emit.({:start_element, name, Enum.reverse(attrs), loc})
    {pos + 1, line, ls}
  end

  defp finish_open_tag(<<c, rest::binary>>, xml, pos, line, ls, name, attrs, loc, emit)
       when c in [?\s, ?\t, ?\r] do
    finish_open_tag(rest, xml, pos + 1, line, ls, name, attrs, loc, emit)
  end

  defp finish_open_tag(<<?\n, rest::binary>>, xml, pos, line, _ls, name, attrs, loc, emit) do
    finish_open_tag(rest, xml, pos + 1, line + 1, pos + 1, name, attrs, loc, emit)
  end

  defp finish_open_tag(<<c::utf8, _::binary>> = rest, xml, pos, line, ls, name, attrs, loc, emit)
       when is_name_start(c) do
    parse_attr_name(rest, xml, pos, line, ls, name, attrs, loc, pos, emit)
  end

  defp finish_open_tag(_, _xml, pos, line, ls, _name, _attrs, _loc, emit) do
    emit.({:error, "Expected '>', '/>', or attribute", {line, ls, pos}})
    {pos, line, ls}
  end

  # === Close tag name scanning (inlined) ===

  defp parse_close_tag_name(<<c::utf8, rest::binary>>, xml, pos, line, ls, loc, start, emit)
       when is_name_char(c) do
    parse_close_tag_name(rest, xml, pos + utf8_size(c), line, ls, loc, start, emit)
  end

  defp parse_close_tag_name(rest, xml, pos, line, ls, loc, start, emit) do
    name = binary_part(xml, start, pos - start)
    finish_close_tag(rest, xml, pos, line, ls, name, loc, emit)
  end

  defp finish_close_tag(<<">", _::binary>>, _xml, pos, line, ls, name, loc, emit) do
    emit.({:end_element, name, loc})
    {pos + 1, line, ls}
  end

  defp finish_close_tag(<<c, rest::binary>>, xml, pos, line, ls, name, loc, emit)
       when c in [?\s, ?\t, ?\r] do
    finish_close_tag(rest, xml, pos + 1, line, ls, name, loc, emit)
  end

  defp finish_close_tag(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, emit) do
    finish_close_tag(rest, xml, pos + 1, line + 1, pos + 1, name, loc, emit)
  end

  defp finish_close_tag(_, _xml, pos, line, ls, _name, _loc, emit) do
    emit.({:error, "Expected '>'", {line, ls, pos}})
    {pos, line, ls}
  end

  # === Comment ===

  defp parse_comment(<<"-->", _::binary>>, xml, pos, line, ls, loc, start, emit) do
    content = binary_part(xml, start, pos - start)
    emit.({:comment, content, loc})
    {pos + 3, line, ls}
  end

  defp parse_comment(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, emit) do
    parse_comment(rest, xml, pos + 1, line + 1, pos + 1, loc, start, emit)
  end

  defp parse_comment(<<_, rest::binary>>, xml, pos, line, ls, loc, start, emit) do
    parse_comment(rest, xml, pos + 1, line, ls, loc, start, emit)
  end

  defp parse_comment(<<>>, _xml, pos, line, ls, _loc, _start, emit) do
    emit.({:error, "Unterminated comment", {line, ls, pos}})
    {pos, line, ls}
  end

  # === CDATA ===

  defp parse_cdata(<<"]]>", _::binary>>, xml, pos, line, ls, loc, start, emit) do
    content = binary_part(xml, start, pos - start)
    emit.({:characters, content, loc})
    {pos + 3, line, ls}
  end

  defp parse_cdata(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, emit) do
    parse_cdata(rest, xml, pos + 1, line + 1, pos + 1, loc, start, emit)
  end

  defp parse_cdata(<<_, rest::binary>>, xml, pos, line, ls, loc, start, emit) do
    parse_cdata(rest, xml, pos + 1, line, ls, loc, start, emit)
  end

  defp parse_cdata(<<>>, _xml, pos, line, ls, _loc, _start, emit) do
    emit.({:error, "Unterminated CDATA", {line, ls, pos}})
    {pos, line, ls}
  end

  # === DOCTYPE ===
  # The quote parameter tracks if we're inside a quoted string (nil, ?", or ?')
  # When inside quotes, < and > are not counted for depth tracking

  defp parse_doctype(<<">", _::binary>>, xml, pos, line, ls, loc, start, 1, nil, emit) do
    content = binary_part(xml, start, pos - start)
    emit.({:dtd, content, loc})
    {pos + 1, line, ls}
  end

  defp parse_doctype(<<">", rest::binary>>, xml, pos, line, ls, loc, start, depth, nil, emit) do
    parse_doctype(rest, xml, pos + 1, line, ls, loc, start, depth - 1, nil, emit)
  end

  # Handle comments inside DOCTYPE - skip to end of comment without tracking quotes
  defp parse_doctype(<<"<!--", rest::binary>>, xml, pos, line, ls, loc, start, depth, nil, emit) do
    skip_doctype_comment(rest, xml, pos + 4, line, ls, loc, start, depth, emit)
  end

  defp parse_doctype(<<"<", rest::binary>>, xml, pos, line, ls, loc, start, depth, nil, emit) do
    parse_doctype(rest, xml, pos + 1, line, ls, loc, start, depth + 1, nil, emit)
  end

  # Enter quoted string
  defp parse_doctype(<<q, rest::binary>>, xml, pos, line, ls, loc, start, depth, nil, emit)
       when q in [?", ?'] do
    parse_doctype(rest, xml, pos + 1, line, ls, loc, start, depth, q, emit)
  end

  # Exit quoted string (matching quote)
  defp parse_doctype(<<q, rest::binary>>, xml, pos, line, ls, loc, start, depth, q, emit) do
    parse_doctype(rest, xml, pos + 1, line, ls, loc, start, depth, nil, emit)
  end

  # Inside quoted string - skip any character (including < and >) without counting
  defp parse_doctype(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, depth, quote, emit)
       when quote != nil do
    parse_doctype(rest, xml, pos + 1, line + 1, pos + 1, loc, start, depth, quote, emit)
  end

  defp parse_doctype(<<_, rest::binary>>, xml, pos, line, ls, loc, start, depth, quote, emit)
       when quote != nil do
    parse_doctype(rest, xml, pos + 1, line, ls, loc, start, depth, quote, emit)
  end

  # Outside quotes - handle newlines
  defp parse_doctype(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, depth, nil, emit) do
    parse_doctype(rest, xml, pos + 1, line + 1, pos + 1, loc, start, depth, nil, emit)
  end

  # Outside quotes - any other character
  defp parse_doctype(<<_, rest::binary>>, xml, pos, line, ls, loc, start, depth, nil, emit) do
    parse_doctype(rest, xml, pos + 1, line, ls, loc, start, depth, nil, emit)
  end

  defp parse_doctype(<<>>, _xml, pos, line, ls, _loc, _start, _depth, _quote, emit) do
    emit.({:error, "Unterminated DOCTYPE", {line, ls, pos}})
    {pos, line, ls}
  end

  # Skip over comment content inside DOCTYPE
  defp skip_doctype_comment(<<"-->", rest::binary>>, xml, pos, line, ls, loc, start, depth, emit) do
    parse_doctype(rest, xml, pos + 3, line, ls, loc, start, depth, nil, emit)
  end

  defp skip_doctype_comment(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, depth, emit) do
    skip_doctype_comment(rest, xml, pos + 1, line + 1, pos + 1, loc, start, depth, emit)
  end

  defp skip_doctype_comment(<<_, rest::binary>>, xml, pos, line, ls, loc, start, depth, emit) do
    skip_doctype_comment(rest, xml, pos + 1, line, ls, loc, start, depth, emit)
  end

  defp skip_doctype_comment(<<>>, _xml, pos, line, ls, _loc, _start, _depth, emit) do
    emit.({:error, "Unterminated comment in DOCTYPE", {line, ls, pos}})
    {pos, line, ls}
  end

  # === Processing Instruction name scanning (inlined) ===

  defp parse_pi_name(<<c::utf8, rest::binary>>, xml, pos, line, ls, loc, start, emit)
       when is_name_char(c) do
    parse_pi_name(rest, xml, pos + utf8_size(c), line, ls, loc, start, emit)
  end

  defp parse_pi_name(rest, xml, pos, line, ls, loc, start, emit) do
    name = binary_part(xml, start, pos - start)
    skip_ws_then_pi(rest, xml, pos, line, ls, name, loc, emit)
  end

  defp skip_ws_then_pi(<<c, rest::binary>>, xml, pos, line, ls, name, loc, emit)
       when c in [?\s, ?\t, ?\r] do
    skip_ws_then_pi(rest, xml, pos + 1, line, ls, name, loc, emit)
  end

  defp skip_ws_then_pi(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, emit) do
    skip_ws_then_pi(rest, xml, pos + 1, line + 1, pos + 1, name, loc, emit)
  end

  defp skip_ws_then_pi(rest, xml, pos, line, ls, name, loc, emit) do
    parse_pi_content(rest, xml, pos, line, ls, name, loc, pos, emit)
  end

  defp parse_pi_content(<<"?>", _::binary>>, xml, pos, line, ls, name, loc, start, emit) do
    content = binary_part(xml, start, pos - start) |> String.trim()
    emit.({:processing_instruction, name, content, loc})
    {pos + 2, line, ls}
  end

  defp parse_pi_content(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, start, emit) do
    parse_pi_content(rest, xml, pos + 1, line + 1, pos + 1, name, loc, start, emit)
  end

  defp parse_pi_content(<<_, rest::binary>>, xml, pos, line, ls, name, loc, start, emit) do
    parse_pi_content(rest, xml, pos + 1, line, ls, name, loc, start, emit)
  end

  defp parse_pi_content(<<>>, _xml, pos, line, ls, _name, _loc, _start, emit) do
    emit.({:error, "Unterminated PI", {line, ls, pos}})
    {pos, line, ls}
  end

  # === Text ===

  defp parse_text(<<"<", _::binary>>, xml, pos, line, ls, loc, start, emit) do
    content = binary_part(xml, start, pos - start)
    emit.({:characters, content, loc})
    {pos, line, ls}
  end

  defp parse_text(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, emit) do
    parse_text(rest, xml, pos + 1, line + 1, pos + 1, loc, start, emit)
  end

  defp parse_text(<<_, rest::binary>>, xml, pos, line, ls, loc, start, emit) do
    parse_text(rest, xml, pos + 1, line, ls, loc, start, emit)
  end

  defp parse_text(<<>>, xml, pos, line, ls, loc, start, emit) do
    content = binary_part(xml, start, pos - start)
    emit.({:characters, content, loc})
    {pos, line, ls}
  end

  # === Attribute name scanning (inlined) ===

  defp parse_attr_name(
         <<c::utf8, rest::binary>>,
         xml,
         pos,
         line,
         ls,
         tag,
         attrs,
         loc,
         start,
         emit
       )
       when is_name_char(c) do
    parse_attr_name(rest, xml, pos + utf8_size(c), line, ls, tag, attrs, loc, start, emit)
  end

  defp parse_attr_name(rest, xml, pos, line, ls, tag, attrs, loc, start, emit) do
    name = binary_part(xml, start, pos - start)
    parse_attr_eq(rest, xml, pos, line, ls, tag, name, attrs, loc, emit)
  end

  # === Attribute parsing ===

  defp parse_attr_eq(<<"=", rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, emit) do
    parse_attr_value_start(rest, xml, pos + 1, line, ls, tag, name, attrs, loc, emit)
  end

  defp parse_attr_eq(<<c, rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, emit)
       when c in [?\s, ?\t, ?\r] do
    parse_attr_eq(rest, xml, pos + 1, line, ls, tag, name, attrs, loc, emit)
  end

  defp parse_attr_eq(<<?\n, rest::binary>>, xml, pos, line, _ls, tag, name, attrs, loc, emit) do
    parse_attr_eq(rest, xml, pos + 1, line + 1, pos + 1, tag, name, attrs, loc, emit)
  end

  defp parse_attr_eq(_, _xml, pos, line, ls, _tag, _name, _attrs, _loc, emit) do
    emit.({:error, "Expected '='", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_attr_value_start(
         <<c, rest::binary>>,
         xml,
         pos,
         line,
         ls,
         tag,
         name,
         attrs,
         loc,
         emit
       )
       when c in [?\s, ?\t, ?\r] do
    parse_attr_value_start(rest, xml, pos + 1, line, ls, tag, name, attrs, loc, emit)
  end

  defp parse_attr_value_start(
         <<?\n, rest::binary>>,
         xml,
         pos,
         line,
         _ls,
         tag,
         name,
         attrs,
         loc,
         emit
       ) do
    parse_attr_value_start(rest, xml, pos + 1, line + 1, pos + 1, tag, name, attrs, loc, emit)
  end

  defp parse_attr_value_start(
         <<"\"", rest::binary>>,
         xml,
         pos,
         line,
         ls,
         tag,
         name,
         attrs,
         loc,
         emit
       ) do
    parse_attr_value(rest, xml, pos + 1, line, ls, ?", tag, name, attrs, loc, pos + 1, emit)
  end

  defp parse_attr_value_start(
         <<"'", rest::binary>>,
         xml,
         pos,
         line,
         ls,
         tag,
         name,
         attrs,
         loc,
         emit
       ) do
    parse_attr_value(rest, xml, pos + 1, line, ls, ?', tag, name, attrs, loc, pos + 1, emit)
  end

  defp parse_attr_value_start(_, _xml, pos, line, ls, _tag, _name, _attrs, _loc, emit) do
    emit.({:error, "Expected quoted value", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_attr_value(
         <<"\"", rest::binary>>,
         xml,
         pos,
         line,
         ls,
         ?",
         tag,
         name,
         attrs,
         loc,
         start,
         emit
       ) do
    value = binary_part(xml, start, pos - start)
    finish_open_tag(rest, xml, pos + 1, line, ls, tag, [{name, value} | attrs], loc, emit)
  end

  defp parse_attr_value(
         <<"'", rest::binary>>,
         xml,
         pos,
         line,
         ls,
         ?',
         tag,
         name,
         attrs,
         loc,
         start,
         emit
       ) do
    value = binary_part(xml, start, pos - start)
    finish_open_tag(rest, xml, pos + 1, line, ls, tag, [{name, value} | attrs], loc, emit)
  end

  defp parse_attr_value(
         <<?\n, rest::binary>>,
         xml,
         pos,
         line,
         _ls,
         q,
         tag,
         name,
         attrs,
         loc,
         start,
         emit
       ) do
    parse_attr_value(rest, xml, pos + 1, line + 1, pos + 1, q, tag, name, attrs, loc, start, emit)
  end

  # WFC: No < in Attribute Values - advance to end of document to stop parsing
  defp parse_attr_value(
         <<"<", _::binary>>,
         xml,
         pos,
         line,
         ls,
         _q,
         _tag,
         _name,
         _attrs,
         _loc,
         _start,
         emit
       ) do
    emit.({:error, "Character '<' not allowed in attribute value", {line, ls, pos}})
    {byte_size(xml), line, ls}
  end

  defp parse_attr_value(
         <<_, rest::binary>>,
         xml,
         pos,
         line,
         ls,
         q,
         tag,
         name,
         attrs,
         loc,
         start,
         emit
       ) do
    parse_attr_value(rest, xml, pos + 1, line, ls, q, tag, name, attrs, loc, start, emit)
  end

  defp parse_attr_value(<<>>, _xml, pos, line, ls, _q, _tag, _name, _attrs, _loc, _start, emit) do
    emit.({:error, "Unterminated attribute value", {line, ls, pos}})
    {pos, line, ls}
  end

  # === Prolog attribute name scanning (inlined) ===

  defp parse_prolog_attr_name(
         <<c::utf8, rest::binary>>,
         xml,
         pos,
         line,
         ls,
         loc,
         attrs,
         start,
         emit
       )
       when is_name_char(c) do
    parse_prolog_attr_name(rest, xml, pos + utf8_size(c), line, ls, loc, attrs, start, emit)
  end

  defp parse_prolog_attr_name(rest, xml, pos, line, ls, loc, attrs, start, emit) do
    name = binary_part(xml, start, pos - start)
    parse_prolog_attr_eq(rest, xml, pos, line, ls, name, loc, attrs, emit)
  end

  # === Prolog attribute ===

  defp parse_prolog_attr_eq(<<"=", rest::binary>>, xml, pos, line, ls, name, loc, attrs, emit) do
    parse_prolog_attr_value_start(rest, xml, pos + 1, line, ls, name, loc, attrs, emit)
  end

  defp parse_prolog_attr_eq(<<c, rest::binary>>, xml, pos, line, ls, name, loc, attrs, emit)
       when c in [?\s, ?\t, ?\r] do
    parse_prolog_attr_eq(rest, xml, pos + 1, line, ls, name, loc, attrs, emit)
  end

  defp parse_prolog_attr_eq(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, attrs, emit) do
    parse_prolog_attr_eq(rest, xml, pos + 1, line + 1, pos + 1, name, loc, attrs, emit)
  end

  defp parse_prolog_attr_eq(_, _xml, pos, line, ls, _name, _loc, _attrs, emit) do
    emit.({:error, "Expected '='", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_prolog_attr_value_start(
         <<c, rest::binary>>,
         xml,
         pos,
         line,
         ls,
         name,
         loc,
         attrs,
         emit
       )
       when c in [?\s, ?\t, ?\r] do
    parse_prolog_attr_value_start(rest, xml, pos + 1, line, ls, name, loc, attrs, emit)
  end

  defp parse_prolog_attr_value_start(
         <<?\n, rest::binary>>,
         xml,
         pos,
         line,
         _ls,
         name,
         loc,
         attrs,
         emit
       ) do
    parse_prolog_attr_value_start(rest, xml, pos + 1, line + 1, pos + 1, name, loc, attrs, emit)
  end

  defp parse_prolog_attr_value_start(
         <<"\"", rest::binary>>,
         xml,
         pos,
         line,
         ls,
         name,
         loc,
         attrs,
         emit
       ) do
    parse_prolog_attr_value(rest, xml, pos + 1, line, ls, ?", name, loc, attrs, pos + 1, emit)
  end

  defp parse_prolog_attr_value_start(
         <<"'", rest::binary>>,
         xml,
         pos,
         line,
         ls,
         name,
         loc,
         attrs,
         emit
       ) do
    parse_prolog_attr_value(rest, xml, pos + 1, line, ls, ?', name, loc, attrs, pos + 1, emit)
  end

  defp parse_prolog_attr_value_start(_, _xml, pos, line, ls, _name, _loc, _attrs, emit) do
    emit.({:error, "Expected quoted value", {line, ls, pos}})
    {pos, line, ls}
  end

  defp parse_prolog_attr_value(
         <<"\"", rest::binary>>,
         xml,
         pos,
         line,
         ls,
         ?",
         name,
         loc,
         attrs,
         start,
         emit
       ) do
    value = binary_part(xml, start, pos - start)
    parse_prolog_attrs(rest, xml, pos + 1, line, ls, loc, [{name, value} | attrs], emit)
  end

  defp parse_prolog_attr_value(
         <<"'", rest::binary>>,
         xml,
         pos,
         line,
         ls,
         ?',
         name,
         loc,
         attrs,
         start,
         emit
       ) do
    value = binary_part(xml, start, pos - start)
    parse_prolog_attrs(rest, xml, pos + 1, line, ls, loc, [{name, value} | attrs], emit)
  end

  defp parse_prolog_attr_value(
         <<?\n, rest::binary>>,
         xml,
         pos,
         line,
         _ls,
         q,
         name,
         loc,
         attrs,
         start,
         emit
       ) do
    parse_prolog_attr_value(
      rest,
      xml,
      pos + 1,
      line + 1,
      pos + 1,
      q,
      name,
      loc,
      attrs,
      start,
      emit
    )
  end

  defp parse_prolog_attr_value(
         <<_, rest::binary>>,
         xml,
         pos,
         line,
         ls,
         q,
         name,
         loc,
         attrs,
         start,
         emit
       ) do
    parse_prolog_attr_value(rest, xml, pos + 1, line, ls, q, name, loc, attrs, start, emit)
  end

  defp parse_prolog_attr_value(<<>>, _xml, pos, line, ls, _q, _name, _loc, _attrs, _start, emit) do
    emit.({:error, "Unterminated attribute value", {line, ls, pos}})
    {pos, line, ls}
  end

  # ============================================================
  # ACCUMULATOR-BASED FUNCTIONS (fast path for streams)
  # ============================================================

  # === Prolog (acc) ===

  defp parse_prolog_acc(<<"?>", _::binary>>, _xml, pos, line, ls, loc, acc) do
    {[{:prolog, "xml", [], loc} | acc], pos + 2, line, ls}
  end

  defp parse_prolog_acc(<<c, rest::binary>>, xml, pos, line, ls, loc, acc)
       when c in [?\s, ?\t, ?\r] do
    parse_prolog_acc(rest, xml, pos + 1, line, ls, loc, acc)
  end

  defp parse_prolog_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, acc) do
    parse_prolog_acc(rest, xml, pos + 1, line + 1, pos + 1, loc, acc)
  end

  defp parse_prolog_acc(<<c::utf8, _::binary>> = rest, xml, pos, line, ls, loc, acc)
       when is_name_start(c) do
    parse_prolog_attr_name_acc(rest, xml, pos, line, ls, loc, [], pos, acc)
  end

  defp parse_prolog_acc(_, _xml, pos, line, ls, _loc, acc) do
    {[{:error, "Expected '?>' or attribute", {line, ls, pos}} | acc], pos, line, ls}
  end

  defp parse_prolog_attrs_acc(<<"?>", _::binary>>, _xml, pos, line, ls, loc, attrs, acc) do
    {[{:prolog, "xml", Enum.reverse(attrs), loc} | acc], pos + 2, line, ls}
  end

  defp parse_prolog_attrs_acc(<<c, rest::binary>>, xml, pos, line, ls, loc, attrs, acc)
       when c in [?\s, ?\t, ?\r] do
    parse_prolog_attrs_acc(rest, xml, pos + 1, line, ls, loc, attrs, acc)
  end

  defp parse_prolog_attrs_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, attrs, acc) do
    parse_prolog_attrs_acc(rest, xml, pos + 1, line + 1, pos + 1, loc, attrs, acc)
  end

  defp parse_prolog_attrs_acc(<<c::utf8, _::binary>> = rest, xml, pos, line, ls, loc, attrs, acc)
       when is_name_start(c) do
    parse_prolog_attr_name_acc(rest, xml, pos, line, ls, loc, attrs, pos, acc)
  end

  defp parse_prolog_attrs_acc(_, _xml, pos, line, ls, _loc, _attrs, acc) do
    {[{:error, "Expected '?>' or attribute", {line, ls, pos}} | acc], pos, line, ls}
  end

  # === Element dispatch (acc) ===

  defp parse_element_acc(<<"<!--", rest::binary>>, xml, pos, line, ls, acc) do
    parse_comment_acc(rest, xml, pos + 4, line, ls, {line, ls, pos + 1}, pos + 4, acc)
  end

  defp parse_element_acc(<<"<![CDATA[", rest::binary>>, xml, pos, line, ls, acc) do
    parse_cdata_acc(rest, xml, pos + 9, line, ls, {line, ls, pos + 1}, pos + 9, acc)
  end

  defp parse_element_acc(<<"<!DOCTYPE", rest::binary>>, xml, pos, line, ls, acc) do
    parse_doctype_acc(rest, xml, pos + 9, line, ls, {line, ls, pos + 1}, pos + 2, 1, nil, acc)
  end

  defp parse_element_acc(<<"</", rest::binary>>, xml, pos, line, ls, acc) do
    parse_close_tag_name_acc(rest, xml, pos + 2, line, ls, {line, ls, pos + 1}, pos + 2, acc)
  end

  defp parse_element_acc(<<"<?", rest::binary>>, xml, pos, line, ls, acc) do
    parse_pi_name_acc(rest, xml, pos + 2, line, ls, {line, ls, pos + 1}, pos + 2, acc)
  end

  defp parse_element_acc(<<"<", c::utf8, _::binary>> = rest, xml, pos, line, ls, acc)
       when is_name_start(c) do
    <<"<", rest2::binary>> = rest
    parse_open_tag_name_acc(rest2, xml, pos + 1, line, ls, {line, ls, pos + 1}, pos + 1, acc)
  end

  defp parse_element_acc(_, _xml, pos, line, ls, acc) do
    {[{:error, "Invalid element", {line, ls, pos}} | acc], pos, line, ls}
  end

  # === Open tag name scanning (acc, inlined) ===

  defp parse_open_tag_name_acc(<<c::utf8, rest::binary>>, xml, pos, line, ls, loc, start, acc)
       when is_name_char(c) do
    parse_open_tag_name_acc(rest, xml, pos + utf8_size(c), line, ls, loc, start, acc)
  end

  defp parse_open_tag_name_acc(rest, xml, pos, line, ls, loc, start, acc) do
    name = binary_part(xml, start, pos - start)
    finish_open_tag_acc(rest, xml, pos, line, ls, name, [], loc, acc)
  end

  # === Open tag (acc) ===

  defp finish_open_tag_acc(<<"/>", _::binary>>, _xml, pos, line, ls, name, attrs, loc, acc) do
    acc = [{:end_element, name} | [{:start_element, name, Enum.reverse(attrs), loc} | acc]]
    {acc, pos + 2, line, ls}
  end

  defp finish_open_tag_acc(<<">", _::binary>>, _xml, pos, line, ls, name, attrs, loc, acc) do
    {[{:start_element, name, Enum.reverse(attrs), loc} | acc], pos + 1, line, ls}
  end

  defp finish_open_tag_acc(<<c, rest::binary>>, xml, pos, line, ls, name, attrs, loc, acc)
       when c in [?\s, ?\t, ?\r] do
    finish_open_tag_acc(rest, xml, pos + 1, line, ls, name, attrs, loc, acc)
  end

  defp finish_open_tag_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, name, attrs, loc, acc) do
    finish_open_tag_acc(rest, xml, pos + 1, line + 1, pos + 1, name, attrs, loc, acc)
  end

  defp finish_open_tag_acc(
         <<c::utf8, _::binary>> = rest,
         xml,
         pos,
         line,
         ls,
         name,
         attrs,
         loc,
         acc
       )
       when is_name_start(c) do
    parse_attr_name_acc(rest, xml, pos, line, ls, name, attrs, loc, pos, acc)
  end

  defp finish_open_tag_acc(_, _xml, pos, line, ls, _name, _attrs, _loc, acc) do
    {[{:error, "Expected '>', '/>', or attribute", {line, ls, pos}} | acc], pos, line, ls}
  end

  # === Close tag name scanning (acc, inlined) ===

  defp parse_close_tag_name_acc(<<c::utf8, rest::binary>>, xml, pos, line, ls, loc, start, acc)
       when is_name_char(c) do
    parse_close_tag_name_acc(rest, xml, pos + utf8_size(c), line, ls, loc, start, acc)
  end

  defp parse_close_tag_name_acc(rest, xml, pos, line, ls, loc, start, acc) do
    name = binary_part(xml, start, pos - start)
    finish_close_tag_acc(rest, xml, pos, line, ls, name, loc, acc)
  end

  # === Close tag (acc) ===

  defp finish_close_tag_acc(<<">", _::binary>>, _xml, pos, line, ls, name, loc, acc) do
    {[{:end_element, name, loc} | acc], pos + 1, line, ls}
  end

  defp finish_close_tag_acc(<<c, rest::binary>>, xml, pos, line, ls, name, loc, acc)
       when c in [?\s, ?\t, ?\r] do
    finish_close_tag_acc(rest, xml, pos + 1, line, ls, name, loc, acc)
  end

  defp finish_close_tag_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, acc) do
    finish_close_tag_acc(rest, xml, pos + 1, line + 1, pos + 1, name, loc, acc)
  end

  defp finish_close_tag_acc(_, _xml, pos, line, ls, _name, _loc, acc) do
    {[{:error, "Expected '>'", {line, ls, pos}} | acc], pos, line, ls}
  end

  # === Comment (acc) ===

  defp parse_comment_acc(<<"-->", _::binary>>, xml, pos, line, ls, loc, start, acc) do
    content = binary_part(xml, start, pos - start)
    {[{:comment, content, loc} | acc], pos + 3, line, ls}
  end

  defp parse_comment_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, acc) do
    parse_comment_acc(rest, xml, pos + 1, line + 1, pos + 1, loc, start, acc)
  end

  defp parse_comment_acc(<<_, rest::binary>>, xml, pos, line, ls, loc, start, acc) do
    parse_comment_acc(rest, xml, pos + 1, line, ls, loc, start, acc)
  end

  defp parse_comment_acc(<<>>, _xml, pos, line, ls, _loc, _start, acc) do
    {[{:error, "Unterminated comment", {line, ls, pos}} | acc], pos, line, ls}
  end

  # === CDATA (acc) ===

  defp parse_cdata_acc(<<"]]>", _::binary>>, xml, pos, line, ls, loc, start, acc) do
    content = binary_part(xml, start, pos - start)
    {[{:characters, content, loc} | acc], pos + 3, line, ls}
  end

  defp parse_cdata_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, acc) do
    parse_cdata_acc(rest, xml, pos + 1, line + 1, pos + 1, loc, start, acc)
  end

  defp parse_cdata_acc(<<_, rest::binary>>, xml, pos, line, ls, loc, start, acc) do
    parse_cdata_acc(rest, xml, pos + 1, line, ls, loc, start, acc)
  end

  defp parse_cdata_acc(<<>>, _xml, pos, line, ls, _loc, _start, acc) do
    {[{:error, "Unterminated CDATA", {line, ls, pos}} | acc], pos, line, ls}
  end

  # === DOCTYPE (acc) ===
  # The quote parameter tracks if we're inside a quoted string (nil, ?", or ?')
  # When inside quotes, < and > are not counted for depth tracking

  defp parse_doctype_acc(<<">", _::binary>>, xml, pos, line, ls, loc, start, 1, nil, acc) do
    content = binary_part(xml, start, pos - start)
    {[{:dtd, content, loc} | acc], pos + 1, line, ls}
  end

  defp parse_doctype_acc(<<">", rest::binary>>, xml, pos, line, ls, loc, start, depth, nil, acc) do
    parse_doctype_acc(rest, xml, pos + 1, line, ls, loc, start, depth - 1, nil, acc)
  end

  # Handle comments inside DOCTYPE - skip to end of comment without tracking quotes
  defp parse_doctype_acc(
         <<"<!--", rest::binary>>,
         xml,
         pos,
         line,
         ls,
         loc,
         start,
         depth,
         nil,
         acc
       ) do
    skip_doctype_comment_acc(rest, xml, pos + 4, line, ls, loc, start, depth, acc)
  end

  defp parse_doctype_acc(<<"<", rest::binary>>, xml, pos, line, ls, loc, start, depth, nil, acc) do
    parse_doctype_acc(rest, xml, pos + 1, line, ls, loc, start, depth + 1, nil, acc)
  end

  # Enter quoted string
  defp parse_doctype_acc(<<q, rest::binary>>, xml, pos, line, ls, loc, start, depth, nil, acc)
       when q in [?", ?'] do
    parse_doctype_acc(rest, xml, pos + 1, line, ls, loc, start, depth, q, acc)
  end

  # Exit quoted string (matching quote)
  defp parse_doctype_acc(<<q, rest::binary>>, xml, pos, line, ls, loc, start, depth, q, acc) do
    parse_doctype_acc(rest, xml, pos + 1, line, ls, loc, start, depth, nil, acc)
  end

  # Inside quoted string - skip any character (including < and >) without counting
  defp parse_doctype_acc(
         <<?\n, rest::binary>>,
         xml,
         pos,
         line,
         _ls,
         loc,
         start,
         depth,
         quote,
         acc
       )
       when quote != nil do
    parse_doctype_acc(rest, xml, pos + 1, line + 1, pos + 1, loc, start, depth, quote, acc)
  end

  defp parse_doctype_acc(<<_, rest::binary>>, xml, pos, line, ls, loc, start, depth, quote, acc)
       when quote != nil do
    parse_doctype_acc(rest, xml, pos + 1, line, ls, loc, start, depth, quote, acc)
  end

  # Outside quotes - handle newlines
  defp parse_doctype_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, depth, nil, acc) do
    parse_doctype_acc(rest, xml, pos + 1, line + 1, pos + 1, loc, start, depth, nil, acc)
  end

  # Outside quotes - any other character
  defp parse_doctype_acc(<<_, rest::binary>>, xml, pos, line, ls, loc, start, depth, nil, acc) do
    parse_doctype_acc(rest, xml, pos + 1, line, ls, loc, start, depth, nil, acc)
  end

  defp parse_doctype_acc(<<>>, _xml, pos, line, ls, _loc, _start, _depth, _quote, acc) do
    {[{:error, "Unterminated DOCTYPE", {line, ls, pos}} | acc], pos, line, ls}
  end

  # Skip over comment content inside DOCTYPE (acc version)
  defp skip_doctype_comment_acc(
         <<"-->", rest::binary>>,
         xml,
         pos,
         line,
         ls,
         loc,
         start,
         depth,
         acc
       ) do
    parse_doctype_acc(rest, xml, pos + 3, line, ls, loc, start, depth, nil, acc)
  end

  defp skip_doctype_comment_acc(
         <<?\n, rest::binary>>,
         xml,
         pos,
         line,
         _ls,
         loc,
         start,
         depth,
         acc
       ) do
    skip_doctype_comment_acc(rest, xml, pos + 1, line + 1, pos + 1, loc, start, depth, acc)
  end

  defp skip_doctype_comment_acc(<<_, rest::binary>>, xml, pos, line, ls, loc, start, depth, acc) do
    skip_doctype_comment_acc(rest, xml, pos + 1, line, ls, loc, start, depth, acc)
  end

  defp skip_doctype_comment_acc(<<>>, _xml, pos, line, ls, _loc, _start, _depth, acc) do
    {[{:error, "Unterminated comment in DOCTYPE", {line, ls, pos}} | acc], pos, line, ls}
  end

  # === PI name scanning (acc, inlined) ===

  defp parse_pi_name_acc(<<c::utf8, rest::binary>>, xml, pos, line, ls, loc, start, acc)
       when is_name_char(c) do
    parse_pi_name_acc(rest, xml, pos + utf8_size(c), line, ls, loc, start, acc)
  end

  defp parse_pi_name_acc(rest, xml, pos, line, ls, loc, start, acc) do
    name = binary_part(xml, start, pos - start)
    skip_ws_then_pi_acc(rest, xml, pos, line, ls, name, loc, acc)
  end

  defp skip_ws_then_pi_acc(<<c, rest::binary>>, xml, pos, line, ls, name, loc, acc)
       when c in [?\s, ?\t, ?\r] do
    skip_ws_then_pi_acc(rest, xml, pos + 1, line, ls, name, loc, acc)
  end

  defp skip_ws_then_pi_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, acc) do
    skip_ws_then_pi_acc(rest, xml, pos + 1, line + 1, pos + 1, name, loc, acc)
  end

  defp skip_ws_then_pi_acc(rest, xml, pos, line, ls, name, loc, acc) do
    parse_pi_content_acc(rest, xml, pos, line, ls, name, loc, pos, acc)
  end

  defp parse_pi_content_acc(<<"?>", _::binary>>, xml, pos, line, ls, name, loc, start, acc) do
    content = binary_part(xml, start, pos - start) |> String.trim()
    {[{:processing_instruction, name, content, loc} | acc], pos + 2, line, ls}
  end

  defp parse_pi_content_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, start, acc) do
    parse_pi_content_acc(rest, xml, pos + 1, line + 1, pos + 1, name, loc, start, acc)
  end

  defp parse_pi_content_acc(<<_, rest::binary>>, xml, pos, line, ls, name, loc, start, acc) do
    parse_pi_content_acc(rest, xml, pos + 1, line, ls, name, loc, start, acc)
  end

  defp parse_pi_content_acc(<<>>, _xml, pos, line, ls, _name, _loc, _start, acc) do
    {[{:error, "Unterminated PI", {line, ls, pos}} | acc], pos, line, ls}
  end

  # === Text (acc) ===

  defp parse_text_acc(<<"<", _::binary>>, xml, pos, line, ls, loc, start, acc) do
    content = binary_part(xml, start, pos - start)
    {[{:characters, content, loc} | acc], pos, line, ls}
  end

  defp parse_text_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, loc, start, acc) do
    parse_text_acc(rest, xml, pos + 1, line + 1, pos + 1, loc, start, acc)
  end

  defp parse_text_acc(<<_, rest::binary>>, xml, pos, line, ls, loc, start, acc) do
    parse_text_acc(rest, xml, pos + 1, line, ls, loc, start, acc)
  end

  defp parse_text_acc(<<>>, xml, pos, line, ls, loc, start, acc) do
    content = binary_part(xml, start, pos - start)
    {[{:characters, content, loc} | acc], pos, line, ls}
  end

  # === Attribute name scanning (acc, inlined) ===

  defp parse_attr_name_acc(
         <<c::utf8, rest::binary>>,
         xml,
         pos,
         line,
         ls,
         tag,
         attrs,
         loc,
         start,
         acc
       )
       when is_name_char(c) do
    parse_attr_name_acc(rest, xml, pos + utf8_size(c), line, ls, tag, attrs, loc, start, acc)
  end

  defp parse_attr_name_acc(rest, xml, pos, line, ls, tag, attrs, loc, start, acc) do
    name = binary_part(xml, start, pos - start)
    parse_attr_eq_acc(rest, xml, pos, line, ls, tag, name, attrs, loc, acc)
  end

  # === Attribute parsing (acc) ===

  defp parse_attr_eq_acc(<<"=", rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, acc) do
    parse_attr_value_start_acc(rest, xml, pos + 1, line, ls, tag, name, attrs, loc, acc)
  end

  defp parse_attr_eq_acc(<<c, rest::binary>>, xml, pos, line, ls, tag, name, attrs, loc, acc)
       when c in [?\s, ?\t, ?\r] do
    parse_attr_eq_acc(rest, xml, pos + 1, line, ls, tag, name, attrs, loc, acc)
  end

  defp parse_attr_eq_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, tag, name, attrs, loc, acc) do
    parse_attr_eq_acc(rest, xml, pos + 1, line + 1, pos + 1, tag, name, attrs, loc, acc)
  end

  defp parse_attr_eq_acc(_, _xml, pos, line, ls, _tag, _name, _attrs, _loc, acc) do
    {[{:error, "Expected '='", {line, ls, pos}} | acc], pos, line, ls}
  end

  defp parse_attr_value_start_acc(
         <<c, rest::binary>>,
         xml,
         pos,
         line,
         ls,
         tag,
         name,
         attrs,
         loc,
         acc
       )
       when c in [?\s, ?\t, ?\r] do
    parse_attr_value_start_acc(rest, xml, pos + 1, line, ls, tag, name, attrs, loc, acc)
  end

  defp parse_attr_value_start_acc(
         <<?\n, rest::binary>>,
         xml,
         pos,
         line,
         _ls,
         tag,
         name,
         attrs,
         loc,
         acc
       ) do
    parse_attr_value_start_acc(rest, xml, pos + 1, line + 1, pos + 1, tag, name, attrs, loc, acc)
  end

  defp parse_attr_value_start_acc(
         <<"\"", rest::binary>>,
         xml,
         pos,
         line,
         ls,
         tag,
         name,
         attrs,
         loc,
         acc
       ) do
    parse_attr_value_acc(rest, xml, pos + 1, line, ls, ?", tag, name, attrs, loc, pos + 1, acc)
  end

  defp parse_attr_value_start_acc(
         <<"'", rest::binary>>,
         xml,
         pos,
         line,
         ls,
         tag,
         name,
         attrs,
         loc,
         acc
       ) do
    parse_attr_value_acc(rest, xml, pos + 1, line, ls, ?', tag, name, attrs, loc, pos + 1, acc)
  end

  defp parse_attr_value_start_acc(_, _xml, pos, line, ls, _tag, _name, _attrs, _loc, acc) do
    {[{:error, "Expected quoted value", {line, ls, pos}} | acc], pos, line, ls}
  end

  defp parse_attr_value_acc(
         <<"\"", rest::binary>>,
         xml,
         pos,
         line,
         ls,
         ?",
         tag,
         name,
         attrs,
         loc,
         start,
         acc
       ) do
    value = binary_part(xml, start, pos - start)
    finish_open_tag_acc(rest, xml, pos + 1, line, ls, tag, [{name, value} | attrs], loc, acc)
  end

  defp parse_attr_value_acc(
         <<"'", rest::binary>>,
         xml,
         pos,
         line,
         ls,
         ?',
         tag,
         name,
         attrs,
         loc,
         start,
         acc
       ) do
    value = binary_part(xml, start, pos - start)
    finish_open_tag_acc(rest, xml, pos + 1, line, ls, tag, [{name, value} | attrs], loc, acc)
  end

  defp parse_attr_value_acc(
         <<?\n, rest::binary>>,
         xml,
         pos,
         line,
         _ls,
         q,
         tag,
         name,
         attrs,
         loc,
         start,
         acc
       ) do
    parse_attr_value_acc(
      rest,
      xml,
      pos + 1,
      line + 1,
      pos + 1,
      q,
      tag,
      name,
      attrs,
      loc,
      start,
      acc
    )
  end

  # WFC: No < in Attribute Values - advance to end of document to stop parsing
  defp parse_attr_value_acc(
         <<"<", _::binary>>,
         xml,
         pos,
         line,
         ls,
         _q,
         _tag,
         _name,
         _attrs,
         _loc,
         _start,
         acc
       ) do
    {[{:error, "Character '<' not allowed in attribute value", {line, ls, pos}} | acc],
     byte_size(xml), line, ls}
  end

  defp parse_attr_value_acc(
         <<_, rest::binary>>,
         xml,
         pos,
         line,
         ls,
         q,
         tag,
         name,
         attrs,
         loc,
         start,
         acc
       ) do
    parse_attr_value_acc(rest, xml, pos + 1, line, ls, q, tag, name, attrs, loc, start, acc)
  end

  defp parse_attr_value_acc(<<>>, _xml, pos, line, ls, _q, _tag, _name, _attrs, _loc, _start, acc) do
    {[{:error, "Unterminated attribute value", {line, ls, pos}} | acc], pos, line, ls}
  end

  # === Prolog attribute name scanning (acc, inlined) ===

  defp parse_prolog_attr_name_acc(
         <<c::utf8, rest::binary>>,
         xml,
         pos,
         line,
         ls,
         loc,
         attrs,
         start,
         acc
       )
       when is_name_char(c) do
    parse_prolog_attr_name_acc(rest, xml, pos + utf8_size(c), line, ls, loc, attrs, start, acc)
  end

  defp parse_prolog_attr_name_acc(rest, xml, pos, line, ls, loc, attrs, start, acc) do
    name = binary_part(xml, start, pos - start)
    parse_prolog_attr_eq_acc(rest, xml, pos, line, ls, name, loc, attrs, acc)
  end

  # === Prolog attribute (acc) ===

  defp parse_prolog_attr_eq_acc(<<"=", rest::binary>>, xml, pos, line, ls, name, loc, attrs, acc) do
    parse_prolog_attr_value_start_acc(rest, xml, pos + 1, line, ls, name, loc, attrs, acc)
  end

  defp parse_prolog_attr_eq_acc(<<c, rest::binary>>, xml, pos, line, ls, name, loc, attrs, acc)
       when c in [?\s, ?\t, ?\r] do
    parse_prolog_attr_eq_acc(rest, xml, pos + 1, line, ls, name, loc, attrs, acc)
  end

  defp parse_prolog_attr_eq_acc(<<?\n, rest::binary>>, xml, pos, line, _ls, name, loc, attrs, acc) do
    parse_prolog_attr_eq_acc(rest, xml, pos + 1, line + 1, pos + 1, name, loc, attrs, acc)
  end

  defp parse_prolog_attr_eq_acc(_, _xml, pos, line, ls, _name, _loc, _attrs, acc) do
    {[{:error, "Expected '='", {line, ls, pos}} | acc], pos, line, ls}
  end

  defp parse_prolog_attr_value_start_acc(
         <<c, rest::binary>>,
         xml,
         pos,
         line,
         ls,
         name,
         loc,
         attrs,
         acc
       )
       when c in [?\s, ?\t, ?\r] do
    parse_prolog_attr_value_start_acc(rest, xml, pos + 1, line, ls, name, loc, attrs, acc)
  end

  defp parse_prolog_attr_value_start_acc(
         <<?\n, rest::binary>>,
         xml,
         pos,
         line,
         _ls,
         name,
         loc,
         attrs,
         acc
       ) do
    parse_prolog_attr_value_start_acc(
      rest,
      xml,
      pos + 1,
      line + 1,
      pos + 1,
      name,
      loc,
      attrs,
      acc
    )
  end

  defp parse_prolog_attr_value_start_acc(
         <<"\"", rest::binary>>,
         xml,
         pos,
         line,
         ls,
         name,
         loc,
         attrs,
         acc
       ) do
    parse_prolog_attr_value_acc(rest, xml, pos + 1, line, ls, ?", name, loc, attrs, pos + 1, acc)
  end

  defp parse_prolog_attr_value_start_acc(
         <<"'", rest::binary>>,
         xml,
         pos,
         line,
         ls,
         name,
         loc,
         attrs,
         acc
       ) do
    parse_prolog_attr_value_acc(rest, xml, pos + 1, line, ls, ?', name, loc, attrs, pos + 1, acc)
  end

  defp parse_prolog_attr_value_start_acc(_, _xml, pos, line, ls, _name, _loc, _attrs, acc) do
    {[{:error, "Expected quoted value", {line, ls, pos}} | acc], pos, line, ls}
  end

  defp parse_prolog_attr_value_acc(
         <<"\"", rest::binary>>,
         xml,
         pos,
         line,
         ls,
         ?",
         name,
         loc,
         attrs,
         start,
         acc
       ) do
    value = binary_part(xml, start, pos - start)
    parse_prolog_attrs_acc(rest, xml, pos + 1, line, ls, loc, [{name, value} | attrs], acc)
  end

  defp parse_prolog_attr_value_acc(
         <<"'", rest::binary>>,
         xml,
         pos,
         line,
         ls,
         ?',
         name,
         loc,
         attrs,
         start,
         acc
       ) do
    value = binary_part(xml, start, pos - start)
    parse_prolog_attrs_acc(rest, xml, pos + 1, line, ls, loc, [{name, value} | attrs], acc)
  end

  defp parse_prolog_attr_value_acc(
         <<?\n, rest::binary>>,
         xml,
         pos,
         line,
         _ls,
         q,
         name,
         loc,
         attrs,
         start,
         acc
       ) do
    parse_prolog_attr_value_acc(
      rest,
      xml,
      pos + 1,
      line + 1,
      pos + 1,
      q,
      name,
      loc,
      attrs,
      start,
      acc
    )
  end

  defp parse_prolog_attr_value_acc(
         <<_, rest::binary>>,
         xml,
         pos,
         line,
         ls,
         q,
         name,
         loc,
         attrs,
         start,
         acc
       ) do
    parse_prolog_attr_value_acc(rest, xml, pos + 1, line, ls, q, name, loc, attrs, start, acc)
  end

  defp parse_prolog_attr_value_acc(
         <<>>,
         _xml,
         pos,
         line,
         ls,
         _q,
         _name,
         _loc,
         _attrs,
         _start,
         acc
       ) do
    {[{:error, "Unterminated attribute value", {line, ls, pos}} | acc], pos, line, ls}
  end
end
