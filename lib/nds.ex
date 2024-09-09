defmodule FnXML.Stream.NativeDataStruct do

  alias FnXML.Stream.NativeDataStruct, as: NDS
  
  @moduledoc """
  Converts a native data type (NDS) such as a list or map to an FnXML.Stream representation and vice-versa.

  opts:

    - :ops_module - the module to use for the operations, this is what defines the structure of the NDS
  
    - :tag_from_parent - the tag to use if it is not specified in the data structure

    - :tag_id - the key to use for the tag             
    - :namespace_id - the key to use for the namespace 
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
    - :_namespace - the namespace
    - :_text - the text of the element

  any atoms as keys will be used as attributes
  any other keys will be used as elements
  """

  defstruct tag: "undef",
    namespace: "",
    attributes: [],
    content: [],
    private: %{}               # private data for the encoder/decoder

  @doc """
  convert native data type to an FnXML.Stream representation

  ## Examples

      iex> data = %{"a" => "hi", "b" => %{"_" => "info", a: 1, b: 1}, c: "hi", d: 4}
      iex> NDS.encode(data, [])
      [
        open: [tag: "root", attributes: [{"c", "hi"}, {"d", "4"}]],
        open: [tag: "a"],
        text: ["hi"],
        close: [tag: "a"],
        open: [tag: "b", attributes: [{"a", "1"}, {"b", "1"}]],
        open: [tag: "_"],
        text: ["info"],
        close: [tag: "_"],
        close: [tag: "b"],
        close: [tag: "root"]
      ]
  """
  def encode(map, opts \\ [])
  def encode(nil, opts), do: encode(%{}, opts)
  def encode(list, opts) when is_list(list), do: Enum.reduce(list, [], fn map, acc -> acc ++ encode(map, opts) end)
  def encode(map, opts) when is_map(map) do
    formatter = Keyword.get(opts, :formatter, NDS.Format.XML)

    NDS.Encoder.encode(map, opts) |> formatter.emit()
  end
  def encode(value, opts), do: encode(%{"text" => to_string(value)}, [{:text, fn map, _ -> map[:value] end} | opts])

  @doc """
  convert native data type to a map representation

  ## Examples

      iex> stream = [ open: [tag: "foo"], close: [tag: "foo"] ]
      iex> NDS.decode(stream, format_meta: &NDS.no_meta/1)
      [%{"foo" => %{}}]
  """
  def decode(xml_stream, opts \\ [])
  def decode(xml_stream, opts) do
    decoder = Keyword.get(opts, :decoder, NDS.Decoder)
    formatter = Keyword.get(opts, :formatter, NDS.Format.Map)
    decoder.decode(xml_stream, opts)
    |> Enum.map(fn x -> x end)
    |> formatter.emit(opts)
  end

  # various helper functions
  def no_meta(_), do: %{}
  def meta_ns_only(%NDS{namespace: ns}) do
    if ns != nil and ns != "", do: %{_meta: %{namespace: ns}}, else: %{}
  end

  def format_raw(map), do: map
end
