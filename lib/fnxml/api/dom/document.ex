defmodule FnXML.API.DOM.Document do
  @moduledoc """
  Represents an XML document in the DOM tree.

  A document contains:
  - `root` - The root element
  - `prolog` - XML declaration attributes (version, encoding, standalone)
  - `doctype` - DOCTYPE declaration content (if present)

  ## Examples

      %FnXML.API.DOM.Document{
        root: %FnXML.API.DOM.Element{tag: "html", children: [...]},
        prolog: %{version: "1.0", encoding: "UTF-8"},
        doctype: nil
      }
  """

  alias FnXML.API.DOM.Element

  defstruct [
    :root,
    :prolog,
    :doctype
  ]

  @type prolog :: %{
          optional(:version) => String.t(),
          optional(:encoding) => String.t(),
          optional(:standalone) => String.t()
        }

  @type t :: %__MODULE__{
          root: Element.t() | nil,
          prolog: prolog() | nil,
          doctype: String.t() | nil
        }

  @doc """
  Create a new document with a root element.

  ## Examples

      iex> root = FnXML.API.DOM.Element.new("html")
      iex> doc = FnXML.API.DOM.Document.new(root)
      iex> doc.root.tag
      "html"
  """
  @spec new(Element.t()) :: t()
  def new(root) do
    %__MODULE__{root: root}
  end

  @doc """
  Create a new document with prolog information.

  ## Examples

      iex> root = FnXML.API.DOM.Element.new("root")
      iex> doc = FnXML.API.DOM.Document.new(root, version: "1.0", encoding: "UTF-8")
      iex> doc.prolog
      %{version: "1.0", encoding: "UTF-8"}
  """
  @spec new(Element.t(), keyword()) :: t()
  def new(root, opts) when is_list(opts) do
    prolog =
      opts
      |> Keyword.take([:version, :encoding, :standalone])
      |> Enum.into(%{})
      |> case do
        empty when map_size(empty) == 0 -> nil
        prolog -> prolog
      end

    doctype = Keyword.get(opts, :doctype)

    %__MODULE__{
      root: root,
      prolog: prolog,
      doctype: doctype
    }
  end

  @doc """
  Get the XML version from the prolog.
  """
  @spec version(t()) :: String.t() | nil
  def version(%__MODULE__{prolog: nil}), do: nil
  def version(%__MODULE__{prolog: prolog}), do: Map.get(prolog, :version)

  @doc """
  Get the encoding from the prolog.
  """
  @spec encoding(t()) :: String.t() | nil
  def encoding(%__MODULE__{prolog: nil}), do: nil
  def encoding(%__MODULE__{prolog: prolog}), do: Map.get(prolog, :encoding)

  @doc """
  Get the standalone declaration from the prolog.
  """
  @spec standalone(t()) :: String.t() | nil
  def standalone(%__MODULE__{prolog: nil}), do: nil
  def standalone(%__MODULE__{prolog: prolog}), do: Map.get(prolog, :standalone)

  @doc """
  Get the document element (root).
  """
  @spec document_element(t()) :: Element.t() | nil
  def document_element(%__MODULE__{root: root}), do: root

  @doc """
  Find elements by tag name in the entire document.
  """
  @spec get_elements_by_tag_name(t(), String.t()) :: [Element.t()]
  def get_elements_by_tag_name(%__MODULE__{root: nil}, _tag_name), do: []

  def get_elements_by_tag_name(%__MODULE__{root: root}, tag_name) do
    matches = if root.tag == tag_name, do: [root], else: []
    matches ++ Element.get_elements_by_tag_name(root, tag_name)
  end

  @doc """
  Get element by ID attribute.

  Searches for an element with the given `id` attribute value.
  """
  @spec get_element_by_id(t(), String.t()) :: Element.t() | nil
  def get_element_by_id(%__MODULE__{root: nil}, _id), do: nil

  def get_element_by_id(%__MODULE__{root: root}, id) do
    find_by_id(root, id)
  end

  defp find_by_id(%Element{} = elem, id) do
    if Element.get_attribute(elem, "id") == id do
      elem
    else
      Enum.find_value(elem.children, fn
        %Element{} = child -> find_by_id(child, id)
        _ -> nil
      end)
    end
  end
end
