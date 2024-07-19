defmodule FnXML.Map do
  @moduledoc """
  This module provides functions for working with maps to/from XML.
  """

  alias FnXML.Stream.NativeDataStruct, as: NDS

  @doc """
  Returns an XML string from the given map.

  `opts` can be used to adjust encoder.

  `tag_from_parent` can be used to specify the tag to use if it is not specified in the data structure.

  `encoder_meta` can be used to specify a function that will be called to collect the meta data for the encoded map.
  See `NDS.EncoderDefault.encode/2` for more information.
  """

  def encode(map, opts \\ []) do
    NDS.encode(map, opts)
    |> FnXML.Stream.to_xml(opts)
    |> Enum.join()
  end

  @doc """
  Returns a map from the given XML string.

  `opts` can be used to adjust the decoder.

  the `decode_meta` option can be used to specify a function that will be called to generate the meta data for the decoded map.
  The function should take the NDS struct as an argument and return a map.  The resulting map is merged with the resulting map
  from the decoder.

  ## Examples

      # default behavior
      iex> FnXML.Map.decode("<ns:foo>content</ns:foo>")
      [%{"foo" => %{ "text" => "content", _meta: %{tag: "foo", namespace: "ns", order: ["text"]}}}]

      # do not produce meta data
      iex> FnXML.Map.decode("<ns:foo>content</ns:foo>", format_meta: &NDS.no_meta/1)
      [%{"foo" => "content"}]

      # only namespace in main map
      iex> FnXML.Map.decode("<ns:foo>content</ns:foo>", format_meta: fn nds -> %{namespace: nds.namespace} end)
      [%{"foo" => %{ "text" => "content", namespace: "ns"}}]
  """
  def decode(xml, opts \\ []) do
    FnXML.Parser.parse(xml)
    |> NDS.decode(opts)
    |> Enum.to_list()
  end
end
