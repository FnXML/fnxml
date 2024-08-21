defmodule FnXML.Stream.NativeDataStruct.DecoderDefault do
  @moduledoc """
  Decode an XML stream to a Native Data Struct (NDS).

  This expects an XML stream, and output an NDS structure.
  """

  alias FnXML.Stream.NativeDataStruct, as: NDS

  @behaviour NDS.Decoder

  @doc """
  Decode an XML stream to a Native Data Struct (NDS).
  """
  @impl NDS.Decoder
  def decode(stream, opts), do: stream |> FnXML.Stream.transform(decode_fn(opts))

  def decode_fn(opts \\ []) do
    fn element, path, acc -> decode_element(element, path, acc, opts) |> emit(element) end
  end

  def insert(nil, new_value), do: new_value
  def insert(existing_value, new_value) when is_list(existing_value), do: [new_value | existing_value]
  def insert(existing_value, new_value), do: [new_value, existing_value]

  def append(nil, new_value), do: new_value
  def append(existing_value, new_value) when is_list(existing_value), do:  existing_value ++ [new_value]
  def append(existing_value, new_value), do: [existing_value, new_value]

  def emit([h], {:close_tag, [{:tag, tag}|_]}) when h.tag == tag, do: {h, []}
  def emit([h] = acc, {:open_tag, [{:tag, tag}|rest]}) when h.tag == tag do
    if Keyword.get(rest, :close, false), do: {h, []}, else: acc
  end
  def emit(acc, _), do: acc

  def update_order([], _item), do: [] # no NDS struct, so nothing to do (should probably raise here)
  def update_order([h | t], item), do: [%NDS{h | order_id_list: [item | h.order_id_list]} | t]

  def append_text([], _text), do: [] # no NDS struct, so nothing to do (should probably raise here)
  def append_text([h|t], text), do: [%NDS{h | data: Map.put(h.data, "text", append_text_item(h.data["text"], text))} | t]

  def append_text_item(t, text), do: append(t, text)

  def update_child_map(child_map, child) do
    Map.put(child_map, child.tag, insert(child_map[child.tag], child))
  end

  def finalize_nds(nds) do
    %NDS{
      nds | child_list: nds.child_list |> Enum.map(fn
        {k, v} when is_list(v) -> {k, Enum.reverse(v)}
        item -> item
      end)
      |> Enum.into(%{})
    }
  end

  def open_close_tag(true, [child | [p | ancestors]]) do
    [%NDS{p | child_list: update_child_map(p.child_list, child)} | ancestors]
  end
  def open_close_tag(_, acc), do: acc

  def decode_element(element, path, acc \\ [], opts \\ [])

  def decode_element({:open_tag, meta}, _path, acc, _opts) do
    element = struct(NDS, meta |> Enum.into(%{}))
    element = %NDS{element | data: element.attr_list |> Enum.into(%{})}
    open_close_tag(Keyword.get(meta, :close), [ element | update_order(acc, element.tag) ])
  end

  def decode_element({:text, [text | _rest]}, _path, acc, _opts) do
    update_order(acc, "text")
    |> append_text(text)
  end

  def decode_element({:close_tag, [{:tag, tag} | _rest]}, [path_head|_], [nds | []], _opts)
  when tag == path_head do
    [finalize_nds(nds)]
  end
  def decode_element({:close_tag, [{:tag, tag} | _rest]}, [path_head|_], [child | [p | ancestors]], _opts)
  when tag == path_head do
    child = finalize_nds(child)
    [%NDS{p | child_list: update_child_map(p.child_list, child)} | ancestors]
  end
  def decode_element({:close_tag, [{:tag, tag} | _rest]}, [path_head|_], _, _) do
    raise "unexpected close tag, got '#{tag}', expected '#{path_head}'"
  end

  def emit(true, [obj | acc], module, opts, path), do: {module.finalize(obj, opts, path), acc}
  def emit(false, acc, _, _, _), do: acc
end
