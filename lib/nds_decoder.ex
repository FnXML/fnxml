defmodule FnXML.Stream.NativeDataStruct.Decoder do
  @moduledoc """
  This Module is used to decode an XML stream to a Native Data Struct (NDS).
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
  def handle_prolog(_meta, _path, acc, _opts), do: acc

  @impl true
  @doc """
  creates an NDS struct copies any matching attributes from meta into the struct
  pushes the struct on to the accumulator
  """
  def handle_open(meta, _path, acc, _opts) do
    {tag, ns} = Element.tag(meta)
    loc = Element.position(meta)

    meta =
      [{:tag, tag}, {:namespace, ns}, {:source, [loc]} | Keyword.drop(meta, [:tag])]
      |> Enum.into(%{})

    [struct(NDS, meta) | acc]
  end

  @impl true
  @doc """
  case 1: only one element on the stack, finalize the NDS struct
  case 2: more than one element on the stack, finalize the NDS struct and add it as a child to the parent
  """
  # this case happens when we are closing the last tag on the stack.
  def handle_close(_meta, [_path], [nds], _opts), do: {finalize_nds(nds), []}
  # this case happens when we are closing a child tag on the stack
  def handle_close(_meta, _path, [child | acc], _opts),
    do: update_content(acc, finalize_nds(child))

  @impl true
  @doc """
  adds text to the current NDS struct
  """
  def handle_text(meta, _path, acc, _opts), do: update_content(acc, Element.content(meta))

  @impl true
  def handle_comment(_meta, _path, acc, _opts), do: acc

  @impl true
  def handle_proc_inst(_meta, _path, acc, _opts), do: acc
end
