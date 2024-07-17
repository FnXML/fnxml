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
    namespace: nil,
    attr_list: [],
    order_id_list: [],
    child_list: %{},
    data: %{},                 # original data structure, or in the case of a decode, this represents the known data
    private: %{}               # private data for the encoder/decoder

#  def update(nds, key, value), do: Map.put(nds, key, value)

  @doc """
  set the NDS tag
  """
  def tag(nds, tag) when is_binary(tag), do: %NDS{nds | tag: tag}
  def tag(nds, tag_fun) when is_function(tag_fun, 1), do: %NDS{nds | tag: tag_fun.(nds)}

  @doc """
  set the NDS namespace
  """
  def namespace(nds, namespace) when is_binary(namespace), do: %NDS{nds | namespace: namespace}
  def namespace(nds, namespace_fun) when is_function(namespace_fun, 1), do: %NDS{nds | namespace: namespace_fun.(nds)}

  
  @doc """
  set the attribute list for the NDS

  ## Examples
        
    iex> nds = %NDS{}
    iex> NDS.attr_list(nds, [a: 1, b: 2])
    %NDS{attr_list: [a: 1, b: 2]}

    iex> nds = %NDS{data: %{"a" => 1, b: 2, c: 3}}
    iex> NDS.attr_list(nds, fn nds -> Enum.filter(nds.data, fn {k, _} -> is_atom(k) end) |> Enum.sort() end)
    %NDS{attr_list: [b: 2, c: 3], data: %{"a" => 1, b: 2, c: 3}}
  """
  def attr_list(nds, attr_list) when is_list(attr_list), do: %NDS{nds | attr_list: attr_list}
  def attr_list(nds, attr_fun) when is_function(attr_fun, 1), do: %NDS{nds | attr_list: attr_fun.(nds)}

  @doc """
  set the child list for the NDS
  """
  def child_list(nds, child_list) when is_map(child_list), do: %NDS{nds | child_list: child_list}
  def child_list(nds, child_fun) when is_function(child_fun, 1), do: %NDS{nds | child_list: child_fun.(nds)}

  @doc """
  set the order_id_list for the NDS
  """
  def order_id_list(nds, order_id_list) when is_list(order_id_list), do: %NDS{nds | order_id_list: order_id_list}
  def order_id_list(nds, order_fun) when is_function(order_fun, 1), do: %NDS{nds | order_id_list: order_fun.(nds)}
  
  @doc """
  convert native data type to an FnXML.Stream representation

  ## Examples

      iex> data = %{"a" => "hi", "b" => %{"_" => "info", a: 1, b: 1}, c: "hi", d: 4}
      iex> NDS.encode(data, [])
      [
        open_tag: [tag: "root", attr_list: [c: "hi", d: 4]],
        text: ["hi"],
        open_tag: [tag: "b", attr_list: [a: 1, b: 1]],
        text: ["info"],
        close_tag: [tag: "b"],
        close_tag: [tag: "root"]
      ]
  """
  def encode(map, opts \\ [])
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

  ## Examples

      iex> stream = [ open_tag: [tag: "foo"], close_tag: [tag: "foo"] ]
      iex> NDS.decode(stream, decode_meta: &NDS.no_meta_decode/1)
      [%{"foo" => %{}}]
  """
  def decode(xml_stream, opts \\ [])
  def decode(xml_stream, opts) do
    decoder = Keyword.get(opts, :decoder, NDS.DecoderDefault)
    formatter = Keyword.get(opts, :formatter, NDS.Format.Map)
    decoder.decode(xml_stream, opts)
    |> Enum.map(fn x -> x end)
    |> formatter.emit(opts)
  end

  def no_meta_decode(_), do: %{}

end
