defmodule FnXML.Element do
  @moduledoc """
  This module provides functions for working with elements of an XML stream.

  All functions support two event formats:

  ## Parser Format (from `FnXML.Parser`)

  Events with explicit position info (line, line_start, byte_offset):

  - `{:start_document, nil}` - Document start marker
  - `{:end_document, nil}` - Document end marker
  - `{:start_element, tag, attrs, line, ls, pos}` - Opening tag with attributes
  - `{:end_element, tag, line, ls, pos}` - Closing tag
  - `{:characters, content, line, ls, pos}` - Text content
  - `{:space, content, line, ls, pos}` - Whitespace content
  - `{:comment, content, line, ls, pos}` - Comment
  - `{:cdata, content, line, ls, pos}` - CDATA section
  - `{:dtd, content, line, ls, pos}` - DOCTYPE declaration
  - `{:prolog, "xml", attrs, line, ls, pos}` - XML prolog
  - `{:processing_instruction, name, content, line, ls, pos}` - Processing instruction
  - `{:error, type, msg, line, ls, pos}` - Parse error

  ## Legacy Format (minimal)

  For backwards compatibility, some functions also accept events without position data:

  - `{:end_element, tag}` - Closing tag without position

  When no position is available, position functions return `{0, 0}`.
  """

  def id_list(),
    do: [
      :start_document,
      :end_document,
      :prolog,
      :start_element,
      :end_element,
      :characters,
      :space,
      :comment,
      :cdata,
      :dtd,
      :processing_instruction,
      :error
    ]

  @doc """
  Given a tag's open/close element, return the tag id as a tuple of
  the form {tag_id, namespace}.

  ## Examples

      iex> FnXML.Element.tag({:start_element, "foo", [], 1, 0, 1})
      {"foo", ""}

      iex> FnXML.Element.tag({:start_element, "matrix:foo", [], 1, 0, 1})
      {"foo", "matrix"}

      iex> FnXML.Element.tag({:end_element, "foo", 1, 0, 1})
      {"foo", ""}
  """
  def tag(id) when is_binary(id) do
    case String.split(id, ":", parts: 2) do
      [tag] -> {tag, ""}
      [ns, tag] -> {tag, ns}
    end
  end

  # 6-tuple format (from parser)
  def tag({:start_element, tag, _attrs, _line, _ls, _pos}), do: tag(tag)
  def tag({:end_element, tag, _line, _ls, _pos}), do: tag(tag)
  # 2-tuple format (no location)
  def tag({:end_element, tag}), do: tag(tag)

  @doc """
  Given a tag name tuple returned from the tag function,
  return a string representation of the tag name, which
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
  Given an open element, return the raw tag string.

  ## Examples

      iex> FnXML.Element.tag_string({:start_element, "foo", [], 1, 0, 1})
      "foo"

      iex> FnXML.Element.tag_string({:end_element, "bar", 1, 0, 1})
      "bar"
  """
  # 6-tuple format (from parser)
  def tag_string({:start_element, tag, _attrs, _line, _ls, _pos}), do: tag
  def tag_string({:end_element, tag, _line, _ls, _pos}), do: tag
  # 2-tuple format (no location)
  def tag_string({:end_element, tag}), do: tag

  @doc """
  Given an open element, return its list of attributes,
  or an empty list if there are none.

  ## Examples

      iex> FnXML.Element.attributes({:start_element, "foo", [{"bar", "baz"}, {"qux", "quux"}], 1, 0, 1})
      [{"bar", "baz"}, {"qux", "quux"}]

      iex> FnXML.Element.attributes({:start_element, "foo", [], 1, 0, 1})
      []
  """
  def attributes({:start_element, _tag, attrs, _line, _ls, _pos}), do: attrs
  def attributes({:prolog, _tag, attrs, _line, _ls, _pos}), do: attrs

  @doc """
  Same as attributes/1 but returns a map of the attributes instead
  of a list.

  ## Examples

      iex> FnXML.Element.attribute_map({:start_element, "foo", [{"bar", "baz"}, {"qux", "quux"}], 1, 0, 1})
      %{"bar" => "baz", "qux" => "quux"}
  """
  def attribute_map(element), do: attributes(element) |> Enum.into(%{})

  @doc """
  Given a text or comment element, retrieve the content.

  ## Examples

      iex> FnXML.Element.content({:characters, "hello world", 1, 0, 5})
      "hello world"

      iex> FnXML.Element.content({:comment, " a comment ", 1, 0, 1})
      " a comment "
  """
  def content({:characters, content, _line, _ls, _pos}), do: content
  def content({:space, content, _line, _ls, _pos}), do: content
  def content({:comment, content, _line, _ls, _pos}), do: content
  def content({:cdata, content, _line, _ls, _pos}), do: content
  def content({:processing_instruction, _name, content, _line, _ls, _pos}), do: content

  @doc """
  Given an element, return a tuple with `{line, column}` position
  of the element in the XML stream.

  ## Examples

      iex> FnXML.Element.position({:start_element, "foo", [], 2, 15, 19})
      {2, 4}

      iex> FnXML.Element.position({:characters, "hello", 1, 0, 5})
      {1, 5}
  """
  def position({:start_document, _}), do: {0, 0}
  def position({:end_document, _}), do: {0, 0}
  # 6-tuple format (from parser)
  def position({:start_element, _tag, _attrs, line, ls, pos}), do: {line, pos - ls}
  def position({:end_element, _tag, line, ls, pos}), do: {line, pos - ls}
  def position({:characters, _content, line, ls, pos}), do: {line, pos - ls}
  def position({:space, _content, line, ls, pos}), do: {line, pos - ls}
  def position({:comment, _content, line, ls, pos}), do: {line, pos - ls}
  def position({:cdata, _content, line, ls, pos}), do: {line, pos - ls}
  def position({:dtd, _content, line, ls, pos}), do: {line, pos - ls}
  def position({:prolog, _tag, _attrs, line, ls, pos}), do: {line, pos - ls}
  def position({:processing_instruction, _name, _content, line, ls, pos}), do: {line, pos - ls}
  def position({:error, _type, _msg, line, ls, pos}), do: {line, pos - ls}
  # 2-tuple format (no location)
  def position({:end_element, _tag}), do: {0, 0}

  @doc """
  Given an element, return the raw location tuple `{line, line_start, byte_offset}`.

  ## Examples

      iex> FnXML.Element.loc({:start_element, "foo", [], 2, 15, 19})
      {2, 15, 19}
  """
  def loc({:start_document, _}), do: nil
  def loc({:end_document, _}), do: nil
  # 6-tuple format (from parser)
  def loc({:start_element, _tag, _attrs, line, ls, pos}), do: {line, ls, pos}
  def loc({:end_element, _tag, line, ls, pos}), do: {line, ls, pos}
  def loc({:characters, _content, line, ls, pos}), do: {line, ls, pos}
  def loc({:space, _content, line, ls, pos}), do: {line, ls, pos}
  def loc({:comment, _content, line, ls, pos}), do: {line, ls, pos}
  def loc({:cdata, _content, line, ls, pos}), do: {line, ls, pos}
  def loc({:dtd, _content, line, ls, pos}), do: {line, ls, pos}
  def loc({:prolog, _tag, _attrs, line, ls, pos}), do: {line, ls, pos}
  def loc({:processing_instruction, _name, _content, line, ls, pos}), do: {line, ls, pos}
  def loc({:error, _type, _msg, line, ls, pos}), do: {line, ls, pos}
  # 2-tuple format (no location)
  def loc({:end_element, _tag}), do: nil
end
