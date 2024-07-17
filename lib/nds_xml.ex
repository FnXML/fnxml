defmodule FnXML.Stream.NativeDataStruct.Format.XML do
  alias FnXML.Stream.NativeDataStruct, as: NDS

  @behaviour NDS.Formatter

  @doc """
  Emit returns a list of XML stream elements.

  ## Examples

      iex> data = %{"a" => "hi", "b" => %{"info" => "info", a: 1, b: 1}, c: "hi", d: 4}
      iex> nds = NDS.EncoderDefault.encode(data, [tag_from_parent: "foo"])
      iex> NDS.Format.XML.emit(nds)
      [
        open_tag: [tag: "foo", attr_list: [c: "hi", d: 4]],
        text: ["hi"],
        open_tag: [tag: "b", attr_list: [a: 1, b: 1]],
        text: ["info"],
        close_tag: [tag: "b"],
        close_tag: [tag: "foo"]
      ]      
  """
  @impl NDS.Formatter
  def emit(nds, opts \\ [])
  def emit(%NDS{order_id_list: []} = nds, _opts), do: [open_tag(nds) |> close()]
  def emit(%NDS{} = nds, _opts), do: [open_tag(nds)] ++ content_list(nds) ++ [close_tag(nds)]

  def open_tag(%NDS{tag: tag, namespace: "", attr_list: []}), do: {:open_tag, [tag: tag]}
  def open_tag(%NDS{tag: tag, namespace: "", attr_list: attrs}), do: {:open_tag, [tag: tag, attr_list: attrs]}
  def open_tag(%NDS{tag: tag, namespace: namespace, attr_list: []}), do: {:open_tag, [tag: tag, namespace: namespace]}
  def open_tag(%NDS{tag: tag, namespace: namespace, attr_list: attrs}),
    do: {:open_tag, [tag: tag, namespace: namespace, attr_list: attrs]}

  def close({el, [tag | rest]}), do: {el, [tag | [{:close, true} | rest]]}
  
  def close_tag(%NDS{tag: tag, namespace: ""}), do: {:close_tag, [tag: tag]}
  def close_tag(%NDS{tag: tag, namespace: namespace}), do: {:close_tag, [tag: tag, namespace: namespace]}

  @doc """
  this iterates over content and generates content elements.  It needs to track the order of the content
  using the order_id_list.  For text items which are lists, it needs to take the first element from the
  list each time that id is referenced.

  ## Examples

      iex> data = %{"a" => ["hello", "world"]}
      iex> nds = NDS.EncoderDefault.encode(data, [tag_from_parent: "foo"])
      iex> NDS.Format.XML.content_list(nds)
      [
        {:text, ["hello"]},
        {:text, ["world"]},
      ]
  """
  def content_list(%NDS{} = nds) do
    Enum.reduce(nds.order_id_list, {nds, []}, fn key, {nds, acc} ->
      cond do
        Map.has_key?(nds.child_list, key) -> child(nds, acc, key, nds.child_list[key])
        Map.has_key?(nds.data, key) -> content(nds, acc, key, nds.data[key])
        true -> raise "no key #{key} in child_list or data"
      end
    end)
    |> elem(1)  # return only the accumulator
  end

  def child(nds, acc, _key, child) when is_map(child), do: {nds, acc ++ emit(child) }
  def child(nds, acc, key, [child|rest]) do
    { %NDS{nds | child_list: Map.put(nds.child_list, key, rest)}, child(nds, acc, key, child) |> elem(1)}
  end
  
  def content(nds, acc, _key, value) when is_binary(value), do: {nds, acc ++ [{:text, [value]}]}
  def content(nds, acc, key, [value|rest]) do
    { %NDS{nds | data: Map.put(nds.data, key, rest)}, acc ++ [{:text, [value]}] }
  end
end
#
