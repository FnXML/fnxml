defmodule XMLStreamTools.NativeDataType.FormatterDefault do
  alias XMLStreamTools.NativeDataType.Meta, as: NDT_Meta

  @behaviour XMLStreamTools.NativeDataType.Formatter

  @impl XMLStreamTools.NativeDataType.Formatter
  @doc """
  Emit returns a list of XML stream elements.

  ## Examples

      iex> data = %{"a" => "hi", "b" => %{"info" => "info", a: 1, b: 1}, c: "hi", d: 4}
      iex> meta = NDT_MetaDefault.meta(data, [tag_from_parent: "foo"])
      iex> NDT_FormatterDefault.emit(meta)
      [
        open_tag: [tag: "foo", attr: [c: "hi", d: 4]],
        text: ["hi"],
        open_tag: [tag: "b", attr: [a: 1, b: 1]],
        text: ["info"],
        close_tag: [tag: "b"],
        close_tag: [tag: "foo"]
      ]      
  """
  def emit(%NDT_Meta{} = meta), do: [open_tag(meta)] ++ content_list(meta) ++ [close_tag(meta)]

  def open_tag(%NDT_Meta{tag: tag, namespace: "", attr_list: []}), do: {:open_tag, [tag: tag]}
  def open_tag(%NDT_Meta{tag: tag, namespace: "", attr_list: attrs}), do: {:open_tag, [tag: tag, attr: attrs]}
  def open_tag(%NDT_Meta{tag: tag, namespace: namespace, attr_list: []}), do: {:open_tag, [tag: tag, namespace: namespace]}
  def open_tag(%NDT_Meta{tag: tag, namespace: namespace, attr_list: attrs}),
    do: {:open_tag, [tag: tag, namespace: namespace, attrs: attrs]}

  def close_tag(%NDT_Meta{tag: tag, namespace: ""}), do: {:close_tag, [tag: tag]}
  def close_tag(%NDT_Meta{tag: tag, namespace: namespace}), do: {:close_tag, [tag: tag, namespace: namespace]}

  def content_list(meta) do
    Enum.reduce(meta.order_id_list, [], fn key, acc ->
      value = meta.child_list[key] || meta.data[key]
      acc ++ content(value)
    end)
  end

  def content(meta) when is_map(meta), do: emit(meta)
  def content(meta) when is_binary(meta), do: [{:text, [meta]}]
end
#
