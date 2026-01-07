defmodule FnXML.Stream.NativeDataStruct.Format.XML do
  alias FnXML.Stream.NativeDataStruct, as: NDS

  @behaviour NDS.Formatter

  @doc """
  Emit returns a list of XML stream events in the new event format.

  Event formats:
  - `{:open, tag, attrs, loc}` - Opening tag with attributes
  - `{:close, tag}` - Closing tag
  - `{:text, content, loc}` - Text content

  ## Examples

      iex> data = %{"a" => "hi", "b" => %{"info" => "info", a: 1, b: 1}, c: "hi", d: 4}
      iex> nds = NDS.Encoder.encode(data, [tag_from_parent: "foo"])
      iex> NDS.Format.XML.emit(nds)
      [
        {:open, "foo", [{"c", "hi"}, {"d", "4"}], nil},
        {:open, "a", [], nil},
        {:text, "hi", nil},
        {:close, "a"},
        {:open, "b", [{"a", "1"}, {"b", "1"}], nil},
        {:open, "info", [], nil},
        {:text, "info", nil},
        {:close, "info"},
        {:close, "b"},
        {:close, "foo"}
      ]
  """
  @impl NDS.Formatter
  def emit(nds, opts \\ [])
  def emit(%NDS{content: []} = nds, _opts), do: [open_tag(nds), close_tag(nds)]

  def emit(%NDS{} = nds, _opts),
    do: [open_tag(nds)] ++ content_list(nds.content) ++ [close_tag(nds)]

  def open_tag(%NDS{tag: tag, namespace: "", attributes: attrs}),
    do: {:open, tag, attrs, nil}

  def open_tag(%NDS{tag: tag, namespace: namespace, attributes: attrs}),
    do: {:open, "#{namespace}:#{tag}", attrs, nil}

  def close_tag(%NDS{tag: tag, namespace: ""}), do: {:close, tag}
  def close_tag(%NDS{tag: tag, namespace: namespace}), do: {:close, "#{namespace}:#{tag}"}

  @doc """
  this iterates over content and generates content elements.  It needs to track the order of the content
  using the order_id_list.  For text items which are lists, it needs to take the first element from the
  list each time that id is referenced.

  ## Examples

      iex> data = %{"a" => ["hello", "world"]}
      iex> nds = [{:child, "a", NDS.Encoder.encode(data, [tag_from_parent: "foo"])}]
      iex> NDS.Format.XML.content_list(nds)
      [
        {:open, "foo", [], nil},
        {:open, "a", [], nil},
        {:text, "hello", nil},
        {:close, "a"},
        {:open, "a", [], nil},
        {:text, "world", nil},
        {:close, "a"},
        {:close, "foo"}
      ]
  """

  def content_list(list) do
    Enum.map(list, &content/1) |> List.flatten()
  end

  def content({:text, _k, text}), do: {:text, text, nil}
  def content({:child, _k, %NDS{} = nds}), do: emit(nds)
end
