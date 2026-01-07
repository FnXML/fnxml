defmodule FnXML.Stream.Decoder.Default do
  @moduledoc """
  Default implementation of the stream decoder behaviour.

  Event formats:
  - `{:open, tag, attrs, loc}` - Opening tag with attributes
  - `{:close, tag}` or `{:close, tag, loc}` - Closing tag
  - `{:text, content, loc}` - Text content
  - `{:comment, content, loc}` - Comment
  - `{:prolog, "xml", attrs, loc}` - XML prolog
  - `{:proc_inst, name, content, loc}` - Processing instruction
  """
  @behaviour FnXML.Stream.Decoder

  @impl true
  @doc """
  Pushes a new element context onto the accumulator for the open tag.
  Stores tag, attributes and loc for later use when building the element.
  """
  def handle_open({:open, tag, attrs, loc}, _path, acc, _opts) do
    # Store element info as a list that will accumulate children/text
    [[{:tag, tag}, {:attributes, attrs}, {:loc, loc}] | acc]
  end

  @impl true
  @doc """
  Adds text content to the current element being built.
  """
  def handle_text({:text, content, _loc}, _path, [h | t], _opts) do
    [[{:text, content} | h] | t]
  end

  @impl true
  @doc """
  Finalizes an element when its close tag is encountered.
  case 1: only one element on the stack, finalize and return it
  case 2: more than one element on the stack, finalize and add as child to parent
  """
  def handle_close(_elem, path, [h], opts) do
    element = process_element(Enum.reverse(h), path, opts)
    {element, []}
  end

  def handle_close(_elem, path, [h, p | anc], opts) do
    element = process_element(Enum.reverse(h), path, opts)
    [[element | p] | anc]
  end

  def process_element(element, [_], []), do: element
  def process_element(element, _path, []), do: {:child, element}
  def process_element(element, path, opts) do
    handler = Keyword.get(opts, :handle_element, fn element, _path, _opts -> {:child, element} end)
    handler.(element, path, opts)
  end

  @impl true
  def handle_prolog({:prolog, _tag, attrs, loc}, _path, acc, _opts) do
    [{:prolog, [{:attributes, attrs}, {:loc, loc}]} | acc]
  end

  @impl true
  def handle_comment({:comment, content, loc}, _path, acc, _opts) do
    [{:comment, [{:content, content}, {:loc, loc}]} | acc]
  end

  @impl true
  def handle_proc_inst({:proc_inst, name, content, loc}, _path, acc, _opts) do
    [{:proc_inst, [{:name, name}, {:content, content}, {:loc, loc}]} | acc]
  end
end
