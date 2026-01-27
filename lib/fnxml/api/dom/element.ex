defmodule FnXML.API.DOM.Element do
  @moduledoc """
  Represents an XML element in the DOM tree.

  An element has:
  - `tag` - The element's tag name (local name)
  - `attributes` - List of `{name, value}` tuples
  - `children` - List of child nodes (elements, text, comments)
  - `namespace_uri` - The element's namespace URI (if any)
  - `prefix` - The element's namespace prefix (if any)

  ## Examples

      %FnXML.API.DOM.Element{
        tag: "book",
        attributes: [{"id", "123"}],
        children: [
          %FnXML.API.DOM.Element{tag: "title", children: ["XML Guide"]},
          %FnXML.API.DOM.Element{tag: "author", children: ["Jane Doe"]}
        ],
        namespace_uri: "http://example.org/books",
        prefix: "bk"
      }

  ## Child Node Types

  Children can be:
  - `%FnXML.API.DOM.Element{}` - Child element
  - `String.t()` - Text content
  - `{:comment, String.t()}` - Comment node
  - `{:cdata, String.t()}` - CDATA section
  - `{:pi, target, data}` - Processing instruction
  """

  defstruct [
    :tag,
    attributes: [],
    children: [],
    namespace_uri: nil,
    prefix: nil
  ]

  @type child ::
          t()
          | String.t()
          | {:comment, String.t()}
          | {:cdata, String.t()}
          | {:pi, String.t(), String.t() | nil}

  @type t :: %__MODULE__{
          tag: String.t(),
          attributes: [{String.t(), String.t()}],
          children: [child()],
          namespace_uri: String.t() | nil,
          prefix: String.t() | nil
        }

  @doc """
  Create a new element.

  ## Examples

      iex> FnXML.API.DOM.Element.new("div")
      %FnXML.API.DOM.Element{tag: "div", attributes: [], children: []}

      iex> FnXML.API.DOM.Element.new("div", [{"class", "container"}])
      %FnXML.API.DOM.Element{tag: "div", attributes: [{"class", "container"}], children: []}

      iex> FnXML.API.DOM.Element.new("p", [], ["Hello"])
      %FnXML.API.DOM.Element{tag: "p", attributes: [], children: ["Hello"]}
  """
  @spec new(String.t(), [{String.t(), String.t()}], [child()]) :: t()
  def new(tag, attributes \\ [], children \\ []) do
    %__MODULE__{
      tag: tag,
      attributes: attributes,
      children: children
    }
  end

  @doc """
  Create an element with namespace.

  ## Examples

      iex> FnXML.API.DOM.Element.new_ns("http://www.w3.org/1999/xhtml", "div", "html")
      %FnXML.API.DOM.Element{
        tag: "div",
        namespace_uri: "http://www.w3.org/1999/xhtml",
        prefix: "html"
      }
  """
  @spec new_ns(String.t() | nil, String.t(), String.t() | nil) :: t()
  def new_ns(namespace_uri, tag, prefix \\ nil) do
    %__MODULE__{
      tag: tag,
      namespace_uri: namespace_uri,
      prefix: prefix
    }
  end

  @doc """
  Get an attribute value by name.

  Returns `nil` if the attribute doesn't exist.

  ## Examples

      iex> elem = FnXML.API.DOM.Element.new("div", [{"id", "main"}, {"class", "container"}])
      iex> FnXML.API.DOM.Element.get_attribute(elem, "id")
      "main"
      iex> FnXML.API.DOM.Element.get_attribute(elem, "style")
      nil
  """
  @spec get_attribute(t(), String.t()) :: String.t() | nil
  def get_attribute(%__MODULE__{attributes: attrs}, name) do
    case List.keyfind(attrs, name, 0) do
      {_, value} -> value
      nil -> nil
    end
  end

  @doc """
  Set an attribute value.

  If the attribute exists, it is updated. Otherwise, it is added.

  ## Examples

      iex> elem = FnXML.API.DOM.Element.new("div")
      iex> elem = FnXML.API.DOM.Element.set_attribute(elem, "id", "main")
      iex> FnXML.API.DOM.Element.get_attribute(elem, "id")
      "main"
  """
  @spec set_attribute(t(), String.t(), String.t()) :: t()
  def set_attribute(%__MODULE__{attributes: attrs} = elem, name, value) do
    new_attrs =
      case List.keyfind(attrs, name, 0) do
        nil -> attrs ++ [{name, value}]
        _ -> List.keyreplace(attrs, name, 0, {name, value})
      end

    %{elem | attributes: new_attrs}
  end

  @doc """
  Remove an attribute.

  ## Examples

      iex> elem = FnXML.API.DOM.Element.new("div", [{"id", "main"}])
      iex> elem = FnXML.API.DOM.Element.remove_attribute(elem, "id")
      iex> FnXML.API.DOM.Element.get_attribute(elem, "id")
      nil
  """
  @spec remove_attribute(t(), String.t()) :: t()
  def remove_attribute(%__MODULE__{attributes: attrs} = elem, name) do
    %{elem | attributes: List.keydelete(attrs, name, 0)}
  end

  @doc """
  Check if element has an attribute.

  ## Examples

      iex> elem = FnXML.API.DOM.Element.new("div", [{"id", "main"}])
      iex> FnXML.API.DOM.Element.has_attribute?(elem, "id")
      true
      iex> FnXML.API.DOM.Element.has_attribute?(elem, "class")
      false
  """
  @spec has_attribute?(t(), String.t()) :: boolean()
  def has_attribute?(%__MODULE__{attributes: attrs}, name) do
    List.keymember?(attrs, name, 0)
  end

  @doc """
  Append a child node.

  ## Examples

      iex> parent = FnXML.API.DOM.Element.new("div")
      iex> child = FnXML.API.DOM.Element.new("span")
      iex> parent = FnXML.API.DOM.Element.append_child(parent, child)
      iex> length(parent.children)
      1
  """
  @spec append_child(t(), child()) :: t()
  def append_child(%__MODULE__{children: children} = elem, child) do
    %{elem | children: children ++ [child]}
  end

  @doc """
  Prepend a child node.
  """
  @spec prepend_child(t(), child()) :: t()
  def prepend_child(%__MODULE__{children: children} = elem, child) do
    %{elem | children: [child | children]}
  end

  @doc """
  Get text content of element (concatenated text of all descendants).

  ## Examples

      iex> elem = FnXML.API.DOM.Element.new("p", [], ["Hello ", %FnXML.API.DOM.Element{tag: "b", children: ["world"]}])
      iex> FnXML.API.DOM.Element.text_content(elem)
      "Hello world"
  """
  @spec text_content(t()) :: String.t()
  def text_content(%__MODULE__{children: children}) do
    children
    |> Enum.map(&child_text_content/1)
    |> Enum.join()
  end

  defp child_text_content(text) when is_binary(text), do: text
  defp child_text_content(%__MODULE__{} = elem), do: text_content(elem)
  defp child_text_content({:cdata, text}), do: text
  defp child_text_content(_), do: ""

  @doc """
  Find child elements by tag name.

  ## Examples

      iex> parent = %FnXML.API.DOM.Element{
      ...>   tag: "ul",
      ...>   children: [
      ...>     %FnXML.API.DOM.Element{tag: "li", children: ["One"]},
      ...>     %FnXML.API.DOM.Element{tag: "li", children: ["Two"]}
      ...>   ]
      ...> }
      iex> FnXML.API.DOM.Element.get_elements_by_tag_name(parent, "li") |> length()
      2
  """
  @spec get_elements_by_tag_name(t(), String.t()) :: [t()]
  def get_elements_by_tag_name(%__MODULE__{children: children}, tag_name) do
    find_elements_by_tag(children, tag_name, [])
  end

  defp find_elements_by_tag([], _tag_name, acc), do: Enum.reverse(acc)

  defp find_elements_by_tag([%__MODULE__{tag: tag} = elem | rest], tag_name, acc) do
    new_acc = if tag == tag_name, do: [elem | acc], else: acc
    # Also search descendants
    descendants = find_elements_by_tag(elem.children, tag_name, [])
    find_elements_by_tag(rest, tag_name, Enum.reverse(descendants) ++ new_acc)
  end

  defp find_elements_by_tag([_ | rest], tag_name, acc) do
    find_elements_by_tag(rest, tag_name, acc)
  end

  @doc """
  Get the qualified name (prefix:local or just local).
  """
  @spec qualified_name(t()) :: String.t()
  def qualified_name(%__MODULE__{tag: tag, prefix: nil}), do: tag
  def qualified_name(%__MODULE__{tag: tag, prefix: prefix}), do: "#{prefix}:#{tag}"
end
