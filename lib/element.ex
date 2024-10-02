defmodule FnXML.Element do
  @moduledoc """
  This module provides functions for working with elements of an XML stream
  """

  def id_list(), do: [:prolog, :open, :close, :text, :comment, :proc_inst]

  @doc """
  given a tags open/close meta data return the tag id as a tuple of
  the form {tag_id, namespace}

  this function can take an element of the form {:open, [ <meta> ]} or
  just the meta list for the element.

  ## Examples

  iex> FnXML.Element.tag({:open, [tag: "foo"]})
  {"foo", ""}

  iex> FnXML.Element.tag({:open, [tag: "matrix:foo"]})
  {"foo", "matrix"}
  """
  def tag(id) when is_binary(id) do
    ns_tag = id |> String.split(":", parts: 2)

    if length(ns_tag) == 1 do
      {Enum.at(ns_tag, 0), ""}
    else
      {Enum.at(ns_tag, 1), Enum.at(ns_tag, 0)}
    end
  end

  def tag(meta) when is_list(meta), do: tag(Keyword.get(meta, :tag, ""))

  def tag({_element, meta}) when is_list(meta), do: tag(meta)
  
  @doc """
  given a tag name tuple returned from the tag function
  (above). return a string representation of the tag name, which
  includes the namespace.

  ## Examples

  iex> FnXML.Element.tag_name({"foo", ""})
  "foo"

  iex> FnXML.Element.tag_name({"foo", "matrix"})
  "matrix:foo"
  """
  def tag_name({tag, ""}), do: tag
  def tag_name({tag, nil}), do: tag
  def tag_name({tag, namespace}), do: namespace <> ":" <> tag

  @doc """
  given an open element, return true/false if it is an open/close element with no content.

  ## Examples

  iex> FnXML.Element.close?([namespace: "", close: true])
  true

  iex> FnXML.Element.close?([namespace: ""])
  false
  """
  def close?(meta) when is_list(meta), do: Keyword.get(meta, :close, false)
  def close?({:open, meta}) when is_list(meta), do: close?(meta)

  @doc """
  given an open element or its meta data return a list of attributes,
  or an empty list if there are none.

  this function can take an element of the form {:open, [ <meta> ]} or
  just the meta list for the element.

  this function will fail with a bad match if given a close or text
  element.

  ## Example

  iex> FnXML.Element.attributes({:open, [tag: "foo", namespace: "matrix", attributes: [{"bar", "baz"}, {"qux", "quux"}]]})
  [{"bar", "baz"}, {"qux", "quux"}]
  """
  def attributes(meta) when is_list(meta), do: Keyword.get(meta, :attributes, [])
  def attributes({:open, meta}) when is_list(meta), do: attributes(meta)

  @doc """
  the same as attributes/1 but returns a map of the attributes instead
  of a list.

  ## Example

  iex> FnXML.Element.attribute_map({:open, [tag: "foo", namespace: "matrix", attributes: [{"bar", "baz"}, {"qux", "quux"}]]})
  %{"bar" => "baz", "qux" => "quux"}
  """
  def attribute_map(meta) when is_list(meta), do: attributes(meta) |> Enum.into(%{})
  def attribute_map({:open, meta}) when is_list(meta), do: attribute_map(meta)

  @doc """
  given a text or comment element, retrieve the content

  ## Example
  iex> FnXML.Element.content({:text, [content: "foo"]})
  "foo"
  """

  def content(meta) when is_list(meta), do: Keyword.get(meta, :content, "")
  def content({_, meta}) when is_list(meta), do: content(meta)

  @doc """
  given an elements meta data return a tuple with `{line position,
  character position}` of the element in the XML stream

  this function can take an element of the form {:open, [ <meta> ]} or
  just the meta list for the element.

  ## Examples

  iex> FnXML.Element.position({:open, [tag: "foo", loc: {2, 15, 19}]})
  {2, 4}
  """
  def position(meta) when is_list(meta) do
    {line, line_start, abs_pos} = Keyword.get(meta, :loc, {0, 0, 0})
    {line, abs_pos - line_start}
  end

  def position({_element, meta}) when is_list(meta), do: position(meta)
end
