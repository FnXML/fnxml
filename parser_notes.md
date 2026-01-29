⏺ Parser Code Review: Shared Code Analysis

  After reviewing both files, here are the key findings:

  Identical/Near-Identical Code
  ┌───────────────────────┬───────────┬──────────────────┬───────┐
  │         Code          │ parser.ex │ parser_stream.ex │ Lines │
  ├───────────────────────┼───────────┼──────────────────┼───────┤
  │ is_name_start/1 guard │ 233-240   │ 22-29            │ ~8    │
  ├───────────────────────┼───────────┼──────────────────┼───────┤
  │ is_name_char/1 guard  │ 242-244   │ 31-33            │ ~3    │
  ├───────────────────────┼───────────┼──────────────────┼───────┤
  │ utf8_size/1 function  │ 247-250   │ 38-41            │ 4     │
  ├───────────────────────┼───────────┼──────────────────┼───────┤
  │ check_encoding!/1     │ 293-315   │ 175-199          │ ~23   │
  ├───────────────────────┼───────────┼──────────────────┼───────┤
  │ Entity resolution     │ N/A       │ 2178-2192        │ 15    │
  └───────────────────────┴───────────┴──────────────────┴───────┘
  Key Observations

  1. Guards are duplicated verbatim - The XML name character guards (is_name_start, is_name_char) are identical. These implement W3C XML spec character classes.
  2. UTF-8 size calculation - Identical helper function for calculating codepoint byte sizes.
  3. UTF-16 BOM detection - Nearly identical, only differs in error message (mentions different module name).
  4. Entity resolution - parser_stream.ex has explicit resolve_entity/1 function. parser.ex doesn't resolve entities internally (defers to downstream processing).
  5. parser.ex has ~1000 lines of duplicated logic - It maintains both callback-based (parse_*) and accumulator-based (parse_*_acc) versions of nearly every parsing function. The _acc variants are structurally identical but return tuples instead of calling emit.

  Shareable Code Candidates

  1. Guards - Can be extracted to a macro module (guards can't be shared via regular imports)
  2. utf8_size/1 - Simple function, easily shared
  3. check_encoding!/1 - Can be parameterized by module name
  4. Entity resolution - resolve_entity/1 can be shared (parser.ex could use it too)
  5. Whitespace check - is_whitespace/1 guard (parser_stream.ex line 35)

  Architecture Differences (Not Shareable)

  - parser.ex: Continuation-passing style, direct tail calls, emit function passed through all calls
  - parser_stream.ex: State machine with halt/resume for chunked streaming, emit stored in state map

  Would you like me to create a shared module (FnXML.Parser.Common or similar) to extract the duplicated code?


--- parsing updates


defmodule fnXML.StreamStepper do
  @doc """
  Starts pulling from a stream one item at a time.
  Returns `{item, continuation_fn}` or `nil` if the stream is empty.
  """
  def next(enum) do
    # We use a special reducer that immediately suspends 
    # as soon as it receives a single item.
    reducer = fn x, _acc -> {:suspend, x} end
    
    # Start the reduction in suspend mode
    step_result = Enumerable.reduce(enum, {:suspend, nil}, reducer)
    
    handle(step_result)
  end

  # Handle the result of the reduction
  defp handle({:suspended, item, continuation_fn}) do
    # Return the item and a lambda that resumes the existing continuation
    {item, fn -> resume(continuation_fn) end}
  end

  defp handle({:done, _acc}), do: nil
  defp handle({:halted, _acc}), do: nil

  # Helper to resume the continuation function
  defp resume(continuation_fn) do
    # We call the continuation with {:suspend, nil} to ask for ONE more item
    # and then suspend again.
    step_result = continuation_fn.({:suspend, nil})
    handle(step_result)
  end
end

defmodule FnXML.Parser do
  def parse(stream, emit) do
     {xml, next_fn} = FnXML.Event.Transform.StreamStepper.next(stream)

     emit.({:start_document, nil})
     result = do_parse_all(xml, xml, 0, 1, 0, emit, next_fn)
     emit.({:end_document, nil})
     result
  end

  then, futher down where we get to a place where there is an empty buffer (see parse_element(<<>>, ... ))
  
  # === Element dispatch ===

  defp parse_element(<<"<!--", rest::binary>>, xml, pos, line, ls, emit, next_fn) do
    parse_comment(rest, xml, pos + 4, line, ls, {line, ls, pos + 1}, pos + 4, emit, next_fn)
  end

  defp parse_element(<<"<![CDATA[", rest::binary>>, xml, pos, line, ls, emit, next_fn) do
    parse_cdata(rest, xml, pos + 9, line, ls, {line, ls, pos + 1}, pos + 9, emit, next_fn)
  end

  defp parse_element(<<"<!DOCTYPE", rest::binary>>, xml, pos, line, ls, emit, next_fn) do
    parse_doctype(rest, xml, pos + 9, line, ls, {line, ls, pos + 1}, pos + 2, 1, nil, emit, next_fn)
  end

  defp parse_element(<<"</", rest::binary>>, xml, pos, line, ls, emit, next_fn) do
    parse_close_tag_name(rest, xml, pos + 2, line, ls, {line, ls, pos + 1}, pos + 2, emit, cton)
  end

  defp parse_element(<<"<?", rest::binary>>, xml, pos, line, ls, emit, next_fn) do
    parse_pi_name(rest, xml, pos + 2, line, ls, {line, ls, pos + 1}, pos + 2, emit, next_fn)
  end

  defp parse_element(<<"<", c::utf8, _::binary>> = rest, xml, pos, line, ls, emit, next_fn)
       when is_name_start(c) do
    <<"<", rest2::binary>> = rest
    parse_open_tag_name(rest2, xml, pos + 1, line, ls, {line, ls, pos + 1}, pos + 1, emit, next_fn)
  end

  defp parse_element(<<>>, xml, pos, line, ls, emit, next_fn) when is_func(next_fn) do
    {new_xml, new_next_fn} = next_fn()

    # we have to do a bit of work to track the position in the blcok here, because we are spanning two blocks
    # this would be a bit different in each case, we may have to backtack some amount in the previous buffer
    # we may also need to add a buffer_pos parameters for tracking where in the buffer we are at.

    parse_element(new_xml, new_xml, pos, line, ls, emit, new_next_fn)
  end

  defp parse_element(_, _xml, pos, line, ls, emit) do
    emit.({:error, "Invalid element", {line, ls, pos}})
    {pos, line, ls}
  end
