defmodule FnXML.Stream.ToMap do
  @moduledoc """
  
  """
  def to_map_fn(opts \\ []) do
    fn element, path, acc -> xml_map(element, path, acc, opts |> valid_opts()) end
  end

  def valid_opts(opts) do
    private = Keyword.get(opts, :private, [])

    %{
      formatter: Keyword.get(opts, :formatter, FnXML.Stream.ToMap.FormatterDefault),
      private:
        Keyword.get(opts, :private, [])
        |> Enum.into(%{})
        |> Map.merge(%{
          attr_enabled: Keyword.get(private, :attr_enabled, true),
          attr_reduce:
            Keyword.get(private, :attr_reduce, fn attr_list ->
              Enum.map(attr_list, fn {k, v} -> {String.to_atom(k), v} end)
            end),
          meta_enabled: Keyword.get(private, :meta_enabled, true),
          namespace_enabled: Keyword.get(private, :namespace_enabled, true),
          text_enabled: Keyword.get(private, :text_enabled, true),
          text_reduce: Keyword.get(private, :text_reduce, fn text_list -> text_list end)
        })
    }
  end

  # no parent, so nothing to do
  def update_order([], _), do: []
  def update_order([h], item), do: [%{h | order: [item | h[:order]]}]
  def update_order([h | t], item), do: [%{h | order: [item | h[:order]]} | t]

  def update_text([h], text), do: [%{h | text: [text | h[:text]]}]
  def update_text([h | t], text), do: [%{h | text: [text | h[:text]]} | t]

  def xml_map(element, path, acc \\ [], opts \\ [])

  def xml_map({:open_tag, [{:tag, name} | rest]}, _path, acc, _opts) do
    [Enum.into(rest, %{tag: name, order: [], text: []}) | update_order(acc, name)]
  end

  def xml_map({:text, [text | _rest]}, _path, acc, _opts) do
    update_order(acc, :_text)
    |> update_text(text)
  end

  def xml_map({:close_tag, [{:tag, _} | _rest]}, path, [_h | _] = acc, opts) do
    module = opts.formatter

    acc =
      module.close(acc, opts.private, path)
      |> module.reduce(opts.private, path)

    emit(module.emit?(acc, opts.private, path), acc, module, opts.private, path)
  end

  def emit(true, [obj | acc], module, opts, path), do: {module.finalize(obj, opts, path), acc}
  def emit(false, acc, _, _, _), do: acc
end

defmodule FnXML.Stream.ToMap.Formatter do
  # called whant a close tag is encountered
  @callback close(acc :: list, opts :: list, path :: list) :: list

  # called immediately after closing an object, it can be used to combine the object into the parent
  @callback reduce(acc :: list, opts :: list, path :: list) :: list

  # returns true if the accumulator has something to emit
  @callback emit?(acc :: list, opts :: list, path :: list) :: boolean

  # called immediately before emitting an object
  @callback finalize(obj :: term, opts :: list, path :: list) :: term
end

defmodule FnXML.Stream.ToMap.FormatterDefault do
  @behaviour FnXML.Stream.ToMap.Formatter

  @impl true
  def close([obj], opts, _path), do: [close_obj(obj, opts)]
  def close([obj | t], opts, _path), do: [close_obj(obj, opts) | t]

  def close_obj(obj, opts) do
    []
    |> attr(obj, opts)
    |> meta(obj, opts)
    |> namespace(obj, opts)
    |> text(obj, opts)
    |> tags(obj, opts)
    |> List.flatten()
    |> Enum.into(%{})
  end

  def attr(acc, %{attr_list: attr}, %{attr_enabled: true, attr_reduce: fun}), do: [fun.(attr) | acc]
  def attr(acc, _, _), do: acc

  def meta(acc, %{loc: loc, order: order, tag: tag}, %{meta_enabled: true}),
    do: [{:_meta, %{loc: loc, order: order, tag: tag}} | acc]

  def meta(acc, _, _), do: acc

  def namespace(acc, %{namespace: ns}, %{namespace_enabled: true}), do: [{:_namespace, ns} | acc]
  def namespace(acc, _, _), do: acc

  def text(acc, %{text: []}, _), do: acc

  def text(acc, %{text: text}, %{text_enabled: true, text_reduce: fun}),
    do: [{:_text, Enum.reverse(text) |> fun.()} | acc]

  def text(acc, _, _), do: acc

  def tags(acc, %{order: order} = obj, _), do: tag_reduce(order, obj, acc)

  def tag_reduce(order, obj, acc) do
    order
    |> Enum.filter(fn
      v when is_binary(v) -> true
      _ -> false
    end)
    |> Enum.reduce(acc, fn tag, acc -> [{tag, obj[tag]} | acc] end)
  end

  @impl true
  def reduce([acc], _opts, _path), do: [reduce_obj(acc)]
  def reduce([obj | [parent | acc]], _opts, [tag, _]), do: [reduce_obj(obj, tag, parent) | acc]

  def reduce_obj(%{:_text => [text]} = obj) when map_size(obj) == 1, do: text

  def reduce_obj(obj) do
    for {key, value} <- obj, into: %{} do
      {
        key,
        cond do
          is_binary(key) and is_list(value) -> Enum.reverse(value)
          true -> value
        end
      }
    end
  end

  def reduce_obj(obj, tag, parent) do
    obj
    |> reduce_obj()
    |> insert_obj(tag, parent, parent[tag])
  end

  def insert_obj(obj, tag, parent, nil), do: Map.put(parent, tag, obj)

  def insert_obj(obj, tag, parent, [_ | _] = parent_obj),
    do: Map.put(parent, tag, [obj | parent_obj])

  def insert_obj(obj, tag, parent, parent_obj), do: Map.put(parent, tag, [obj | [parent_obj]])

  @impl true
  def finalize(obj, _opts, _path), do: obj

  @impl true
  def emit?(_, _, [_]), do: true
  def emit?(_, _, _), do: false
end
