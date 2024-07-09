defmodule FnXML.Stream.NativeDataStruct.Format.XML do
  alias FnXML.Stream.NativeDataStruct, as: NDS

  @behaviour NDS.Formatter

  @doc """
  Emit returns a list of XML stream elements.

  ## Examples

      iex> data = %{"a" => "hi", "b" => %{"info" => "info", a: 1, b: 1}, c: "hi", d: 4}
      iex> meta = NDS.EncoderDefault.encode(data, [tag_from_parent: "foo"])
      iex> NDS.Format.XML.emit(meta)
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
  def emit(%NDS{} = meta, _opts \\ []), do: [open_tag(meta)] ++ content_list(meta) ++ [close_tag(meta)]

  def open_tag(%NDS{tag: tag, namespace: "", attr_list: []}), do: {:open_tag, [tag: tag]}
  def open_tag(%NDS{tag: tag, namespace: "", attr_list: attrs}), do: {:open_tag, [tag: tag, attr_list: attrs]}
  def open_tag(%NDS{tag: tag, namespace: namespace, attr_list: []}), do: {:open_tag, [tag: tag, namespace: namespace]}
  def open_tag(%NDS{tag: tag, namespace: namespace, attr_list: attrs}),
    do: {:open_tag, [tag: tag, namespace: namespace, attr_list: attrs]}

  def close_tag(%NDS{tag: tag, namespace: ""}), do: {:close_tag, [tag: tag]}
  def close_tag(%NDS{tag: tag, namespace: namespace}), do: {:close_tag, [tag: tag, namespace: namespace]}

  @doc """
  this iterates over content and generates content elements.  It needs to track the order of the content
  using the order_id_list.  For text items which are lists, it needs to take the first element from the
  list each time that id is referenced.

  ## Examples

      iex> data = %{"a" => ["hello", "world"]}
      iex> meta = NDS.EncoderDefault.encode(data, [tag_from_parent: "foo"])
      iex> NDS.Format.XML.content_list(meta)
      [
        {:text, ["hello"]},
        {:text, ["world"]},
      ]
  """
  def content_list(%NDS{} = meta) do
    Enum.reduce(meta.order_id_list, {meta, []}, fn key, {meta, acc} ->
      cond do
        Map.has_key?(meta.child_list, key) -> child(meta, acc, key, meta.child_list[key])
        Map.has_key?(meta.data, key) -> content(meta, acc, key, meta.data[key])
      end
    end)
    |> elem(1)  # return only the accumulator
  end

  def child(meta, acc, _key, child) when is_map(child), do: {meta, acc ++ emit(child) }
  def child(meta, acc, key, [child|rest]) do
    { %NDS{meta | child_list: Map.put(meta.child_list, key, rest)}, child(meta, acc, key, child) |> elem(1)}
  end
  
  def content(meta, acc, _key, value) when is_binary(value), do: {meta, acc ++ [{:text, [value]}]}
  def content(meta, acc, key, [value|rest]) do
    { %NDS{meta | data: Map.put(meta.data, key, rest)}, acc ++ [{:text, [value]}] }
  end
end
#
