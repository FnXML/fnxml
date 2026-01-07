defmodule FnXML.Stream.NativeDataStruct.Decoder do
  @moduledoc """
  This Module is used to decode an XML stream to a Native Data Struct (NDS).

  Event formats:
  - `{:open, tag, attrs, loc}` - Opening tag with attributes
  - `{:close, tag}` or `{:close, tag, loc}` - Closing tag
  - `{:text, content, loc}` - Text content
  - `{:comment, content, loc}` - Comment
  - `{:prolog, "xml", attrs, loc}` - XML prolog
  - `{:proc_inst, name, content, loc}` - Processing instruction
  """

  alias FnXML.Element
  alias FnXML.Stream.NativeDataStruct, as: NDS

  @behaviour FnXML.Stream.Decoder

  def decode(stream, opts \\ []), do: stream |> FnXML.Stream.Decoder.decode(__MODULE__, opts)

  @doc """
  update the content list if an nds rec exists
  """
  # no NDS struct, so nothing to do this should only happen for the root tag
  def update_content([], _item), do: []
  def update_content([%NDS{} = h | t], item), do: [%{h | content: [item | h.content]} | t]

  @doc """
  Reverse generated lists so they are in the correct order
  """
  def finalize_nds(%NDS{} = nds), do: %{nds | content: Enum.reverse(nds.content)}

  @impl true
  def handle_prolog(_elem, _path, acc, _opts), do: acc

  @impl true
  @doc """
  creates an NDS struct from the open tag element
  pushes the struct on to the accumulator
  """
  def handle_open({:open, tag_str, attrs, _loc} = elem, _path, acc, _opts) do
    {tag, ns} = Element.tag(tag_str)
    {line, col} = Element.position(elem)

    nds_map = %{
      tag: tag,
      namespace: ns,
      attributes: attrs,
      source: [{line, col}]
    }

    [struct(NDS, nds_map) | acc]
  end

  @impl true
  @doc """
  case 1: only one element on the stack, finalize the NDS struct
  case 2: more than one element on the stack, finalize the NDS struct and add it as a child to the parent
  """
  # this case happens when we are closing the last tag on the stack.
  def handle_close(_elem, [_path], [nds], _opts), do: {finalize_nds(nds), []}
  # this case happens when we are closing a child tag on the stack
  def handle_close(_elem, _path, [child | acc], _opts),
    do: update_content(acc, finalize_nds(child))

  @impl true
  @doc """
  adds text to the current NDS struct
  """
  def handle_text({:text, content, _loc}, _path, acc, _opts), do: update_content(acc, content)

  @impl true
  def handle_comment(_elem, _path, acc, _opts), do: acc

  @impl true
  def handle_proc_inst(_elem, _path, acc, _opts), do: acc
end
