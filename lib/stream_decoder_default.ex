defmodule FnXML.Stream.Decoder.Default do
  @moduledoc """
  Default implementation of the stream decoder behaviour.
  """
  @behaviour FnXML.Stream.Decoder

  @impl true
  @doc """
  pushes the current element on to the accumulator
  """
  def handle_open(meta, _path, acc, _opts), do: [meta |> Enum.reverse() | acc]

  @impl true
  @doc """
  pushes the current text on to the top element of the accumulator
  """
  def handle_text(text, _path, [h | t], _opts), do: [[{:text, text} | h] | t]

  @impl true
  @doc """
  case 1: only one element on the stack, reverse the element and return it
  case 2: more than one element on the stack, reverse the top element and add it to the second element
  """
  def handle_close(_meta, path, [h], opts) do
    element = process_element(h |> Enum.reverse(), path, opts)
    {element, []}
  end

  def handle_close(_meta, path, [h, p | anc], opts) do
    element = process_element(h |> Enum.reverse(), path, opts)
    [[element | p] | anc]
  end

  def process_element(element, [_], []), do: element
  def process_element(element, _path, []), do: {:child, element}
  def process_element(element, path, opts) do
    handler = Keyword.get(opts, :handle_element, fn element, _path, _opts -> {:child, element} end)
    handler.(element, path, opts)
  end
  
  @impl true
  def handle_prolog(meta, _path, acc, _opts), do: [{:prolog, meta} |acc]

  @impl true
  def handle_comment(meta, _path, acc, _opts), do: [{:comment, meta} | acc]

  @impl true
  def handle_proc_inst(meta, _path, acc, _opts), do: [{:proc_inst, meta} | acc]
end
