defmodule XMLStreamTools.XMLStream do
  alias XMLStreamTools.Transformer

  def to_xml(list, opts) when is_list(list) do
    pretty = Keyword.get(opts, :pretty, false)
    indent = Keyword.get(opts, :indent, 2)
    path = []

    Enum.reduce(list, {path, ""}, fn {type, parts} = element, {path, acc} ->
      [h|t] = if path == [], do: [ nil | []], else: path
      tag = Keyword.get(parts, :tag)
      path = case type do
               :open_tag -> [ tag | path]
               :close_tag -> t
               _ -> path
             end
      
      {depth, formatted_element} = format_element(element, path, acc)
      
      if pretty do
        indent = String.duplicate(" ", indent * depth)
        {path, "#{acc}#{indent}#{formatted_element}\n"}
      else
        {path, "#{acc}#{formatted_element}"}
      end
    end)
  end
  
  def to_xml(stream, opts) do
    pretty = Keyword.get(opts, :pretty, false)
    indent = Keyword.get(opts, :indent, 2)

    fun = fn element, path, acc -> to_xml_fn(element, path, acc, pretty, indent) end
    Transformer.transform(stream, fun, opts)
  end

  def to_xml_fn(element, path, acc, pretty, indent) do
    formatted_element = format_element(element, path, acc)
    if pretty do
      indent = String.duplicate(" ", indent * length(path))
      {"#{indent}#{formatted_element}\n", acc}
    else
      {formatted_element, acc}
    end
  end

  def format_element({:open_tag, parts}, path, acc) do
    tag = Keyword.get(parts, :tag)
    ns = Keyword.get(parts, :namespace)
    ns = if ns, do: "#{ns}:", else: ""
    close = if Keyword.get(parts, :close, false), do: "/", else: ""
    attrs = 
      Keyword.get(parts, :attr, [])
      |> Enum.map(fn {k, v} -> " #{k}=\"#{v}\"" end)
      |> Enum.join(" ")

    { length(path) - 1, "<#{ns}#{tag}#{attrs}#{close}>" }
  end

  def format_element({:text, [text]}, path, acc), do: { length(path), text }

  def format_element({:close_tag, parts}, path, acc) do
    tag = Keyword.get(parts, :tag)
    ns = Keyword.get(parts, :namespace)
    ns = if ns, do: "#{ns}:", else: ""

    { length(path), "</#{ns}#{tag}>" }
  end
end
