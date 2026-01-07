defmodule FnXML.Element do
  @moduledoc """
  This module provides functions for working with elements of an XML stream.

  Event formats:
  - `{:doc_start, nil}` - Document start marker
  - `{:doc_end, nil}` - Document end marker
  - `{:open, tag, attrs, loc}` - Opening tag with attributes
  - `{:close, tag}` or `{:close, tag, loc}` - Closing tag
  - `{:text, content, loc}` - Text content
  - `{:comment, content, loc}` - Comment
  - `{:prolog, "xml", attrs, loc}` - XML prolog
  - `{:proc_inst, name, content, loc}` - Processing instruction
  - `{:error, message, loc}` - Parse error
  """

  def id_list(), do: [:doc_start, :doc_end, :prolog, :open, :close, :text, :comment, :proc_inst, :error]

  @doc """
  Given a tag's open/close element, return the tag id as a tuple of
  the form {tag_id, namespace}.

  ## Examples

      iex> FnXML.Element.tag({:open, "foo", [], {1, 0, 1}})
      {"foo", ""}

      iex> FnXML.Element.tag({:open, "matrix:foo", [], {1, 0, 1}})
      {"foo", "matrix"}

      iex> FnXML.Element.tag({:close, "foo"})
      {"foo", ""}
  """
  def tag(id) when is_binary(id) do
    case String.split(id, ":", parts: 2) do
      [tag] -> {tag, ""}
      [ns, tag] -> {tag, ns}
    end
  end

  def tag({:open, tag, _attrs, _loc}), do: tag(tag)
  def tag({:close, tag}), do: tag(tag)
  def tag({:close, tag, _loc}), do: tag(tag)

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

      iex> FnXML.Element.tag_string({:open, "foo", [], {1, 0, 1}})
      "foo"

      iex> FnXML.Element.tag_string({:close, "bar"})
      "bar"
  """
  def tag_string({:open, tag, _attrs, _loc}), do: tag
  def tag_string({:close, tag}), do: tag
  def tag_string({:close, tag, _loc}), do: tag

  @doc """
  Given an open element, return its list of attributes,
  or an empty list if there are none.

  ## Examples

      iex> FnXML.Element.attributes({:open, "foo", [{"bar", "baz"}, {"qux", "quux"}], {1, 0, 1}})
      [{"bar", "baz"}, {"qux", "quux"}]

      iex> FnXML.Element.attributes({:open, "foo", [], {1, 0, 1}})
      []
  """
  def attributes({:open, _tag, attrs, _loc}), do: attrs
  def attributes({:prolog, _tag, attrs, _loc}), do: attrs

  @doc """
  Same as attributes/1 but returns a map of the attributes instead
  of a list.

  ## Examples

      iex> FnXML.Element.attribute_map({:open, "foo", [{"bar", "baz"}, {"qux", "quux"}], {1, 0, 1}})
      %{"bar" => "baz", "qux" => "quux"}
  """
  def attribute_map(element), do: attributes(element) |> Enum.into(%{})

  @doc """
  Given a text or comment element, retrieve the content.

  ## Examples

      iex> FnXML.Element.content({:text, "hello world", {1, 0, 5}})
      "hello world"

      iex> FnXML.Element.content({:comment, " a comment ", {1, 0, 1}})
      " a comment "
  """
  def content({:text, content, _loc}), do: content
  def content({:comment, content, _loc}), do: content
  def content({:proc_inst, _name, content, _loc}), do: content

  @doc """
  Given an element, return a tuple with `{line, column}` position
  of the element in the XML stream.

  ## Examples

      iex> FnXML.Element.position({:open, "foo", [], {2, 15, 19}})
      {2, 4}

      iex> FnXML.Element.position({:text, "hello", {1, 0, 5}})
      {1, 5}
  """
  def position({:doc_start, _}), do: {0, 0}
  def position({:doc_end, _}), do: {0, 0}
  def position({:open, _tag, _attrs, loc}), do: loc_to_position(loc)
  def position({:close, _tag, loc}), do: loc_to_position(loc)
  def position({:close, _tag}), do: {0, 0}
  def position({:text, _content, loc}), do: loc_to_position(loc)
  def position({:comment, _content, loc}), do: loc_to_position(loc)
  def position({:prolog, _tag, _attrs, loc}), do: loc_to_position(loc)
  def position({:proc_inst, _name, _content, loc}), do: loc_to_position(loc)
  def position({:error, _msg, loc}), do: loc_to_position(loc)

  defp loc_to_position(nil), do: {0, 0}
  defp loc_to_position({line, line_start, abs_pos}), do: {line, abs_pos - line_start}

  @doc """
  Given an element, return the raw location tuple `{line, line_start, byte_offset}`.

  ## Examples

      iex> FnXML.Element.loc({:open, "foo", [], {2, 15, 19}})
      {2, 15, 19}
  """
  def loc({:doc_start, _}), do: nil
  def loc({:doc_end, _}), do: nil
  def loc({:open, _tag, _attrs, loc}), do: loc
  def loc({:close, _tag, loc}), do: loc
  def loc({:close, _tag}), do: nil
  def loc({:text, _content, loc}), do: loc
  def loc({:comment, _content, loc}), do: loc
  def loc({:prolog, _tag, _attrs, loc}), do: loc
  def loc({:proc_inst, _name, _content, loc}), do: loc
  def loc({:error, _msg, loc}), do: loc
end
