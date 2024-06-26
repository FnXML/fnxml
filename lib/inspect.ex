defmodule XMLStreamTools.Inspector do
  @moduledoc """
  XML Inspector: This module is used to inspect the XML stream.

  # Example:
  #    This example is commented out because it writes to the console.

  #    xml = "<foo a='1'>first element<bar>nested element</bar></foo>"
  #    XMLStreamTools.Parser.parse(xml)
  #    |> XMLStreamTools.Transformer.transform(XMLStreamTools.Inspector.inspect_fn(label: "test_stream"))
  #    |> Enum.map(fn x -> x end)

  This will show the stream as it is processed (see below), `path` is a seperate list inserted by the Transformer,
  it shows the path from the root element.

  ```
  test_stream: {:open_tag, [tag: "foo", attr: [{"a", "1"}], loc: {{1, 0}, 1}]}, path: ["foo"]
  test_stream: {:text, ["first element", {:loc, {{1, 0}, 24}}]}, path: ["foo"]
  test_stream: {:open_tag, [tag: "bar", loc: {{1, 0}, 25}]}, path: ["bar", "foo"]
  test_stream: {:text, ["nested element", {:loc, {{1, 0}, 43}}]}, path: ["bar", "foo"]
  test_stream: {:close_tag, [tag: "bar", loc: {{1, 0}, 45}]}, path: ["bar", "foo"]
  test_stream: {:close_tag, [tag: "foo", loc: {{1, 0}, 51}]}, path: ["foo"]
  ```  
  """

  def inspect_fn(opts \\ []) do
    options = %{label: Keyword.get(opts, :label, nil)}
    fn element, path, acc -> inspect(element, path, acc, options) end
  end

  def inspect({type, meta} = element, path, _acc, %{label: label}) do
    label = if label != nil, do: "#{label}: ", else: ""
    IO.puts("#{label}{#{inspect(type)}, #{inspect(meta)}}, path: #{inspect(path)}")
    {element, []}  #always emit the element
  end
end
