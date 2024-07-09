defmodule FnXML.Stream.NativeDataStruct do

  alias FnXML.Stream.NativeDataStruct, as: NDS
  
  @moduledoc """
  Converts a native data type (NDS) such as a list or map to an FnXML.Stream representation and vice-versa.

  opts:

    - :ops_module - the module to use for the operations, this is what defines the structure of the NDS
  
    - :tag_from_parent - the tag to use if it is not specified in the data structure

    - :meta_id - the key to use for the meta data      (defaults to :_meta)
    - :tag_id - the key to use for the tag             (defaults to [:_meta, :tag])
    - :namespace_id - the key to use for the namespace (defaults to [:_meta, :namespace])
    - :text_id - the key to use for the text           (defaults to :_text)

    - :namespace - namespace for element, or a function which returns the namespace
    - :tag - tag for element, or a function which returns the tag
    - :order - a list of elements in the order they should appear or a function which returns a list of elements
    - :attr - a list of attributes in the map, or a function which returns a list of attributes
    - :children - a list of children in the map, or a function which returns a list of children

       functions defined for :order, :attr, :children should take the following arguments:
         - the map
         - the meta data
         - a key which may or may not be in map
         It should return true if the key should be included in the list, false otherwise
         
    - :text - a list of text elements to add to the map, or a function returns the text

       functions defined for :text should take the following arguments:
         - the map
         - the meta data
         It should return a list of the text to insert into the resulting encoding.
         If there is no text, it should return an empty list

  special keys:
    - :_meta - metadata about the map
    - :_namespace - the namespace
    - :_text - the text of the element

  any atoms as keys will be used as attributes
  any other keys will be used as elements
  """

  defstruct meta_id: :_meta, tag: "undef", namespace: nil, tag_from_parent: nil,
    attr_list: [], order_id_list: [], child_list: %{},
    data: %{}, opts: nil

  def update(meta, key, value), do: Map.put(meta, key, value)


  @doc """
  convert native data type to an FnXML.Stream representation

  ## Examples

      iex> data = %{"a" => "hi", "b" => %{"_" => "info", a: 1, b: 1}, c: "hi", d: 4}
      iex> NDS.encode(data, [])
      [
        open_tag: [tag: "undef", attr_list: [c: "hi", d: 4]],
        text: ["hi"],
        open_tag: [tag: "b", attr_list: [a: 1, b: 1]],
        text: ["info"],
        close_tag: [tag: "b"],
        close_tag: [tag: "undef"]
      ]
  """
  def encode(map, opts)
  def encode(nil, opts), do: encode(%{}, opts)
  def encode(list, opts) when is_list(list), do: Enum.reduce(list, [], fn map, acc -> acc ++ encode(map, opts) end)
  def encode(map, opts) when is_map(map) do
    encoder = Keyword.get(opts, :encoder, NDS.EncoderDefault)
    formatter = Keyword.get(opts, :formatter, NDS.Format.XML)

    encoder.encode(map, opts) |> formatter.emit()
  end
  def encode(value, opts), do: encode(%{"value" => to_string(value)}, [{:text, fn map, _ -> map[:value] end} | opts])

  @doc """
  convert native data type to a map representation
  """
  def decode(xml_stream, opts)
  def decode(nil, opts), do: decode([], opts)
end
