defmodule FnXML.DTD.Model do
  @moduledoc """
  Data structures representing DTD (Document Type Definition) components.

  A DTD defines the legal building blocks of an XML document. This module
  provides structs for representing:

  - Element declarations (`<!ELEMENT>`)
  - Attribute list declarations (`<!ATTLIST>`)
  - Entity declarations (`<!ENTITY>`)
  - Notation declarations (`<!NOTATION>`)

  ## Content Models

  Element content models specify what an element can contain:

  - `:empty` - Element cannot have content (`<!ELEMENT name EMPTY>`)
  - `:any` - Element can contain any content (`<!ELEMENT name ANY>`)
  - `:pcdata` - Element contains only text (`<!ELEMENT name (#PCDATA)>`)
  - `{:seq, items}` - Sequence of child elements (`(a, b, c)`)
  - `{:choice, items}` - Choice of child elements (`(a | b | c)`)
  - `{:mixed, elements}` - Mixed content with text and elements (`(#PCDATA | a | b)*`)

  Content model items can have occurrence indicators:
  - `{:one, item}` - Exactly one (default)
  - `{:optional, item}` - Zero or one (`?`)
  - `{:zero_or_more, item}` - Zero or more (`*`)
  - `{:one_or_more, item}` - One or more (`+`)

  ## Attribute Types

  - `:cdata` - Character data
  - `:id` - Unique identifier
  - `:idref` - Reference to an ID
  - `:idrefs` - Space-separated list of IDREFs
  - `:entity` - Name of an unparsed entity
  - `:entities` - Space-separated list of entity names
  - `:nmtoken` - Name token
  - `:nmtokens` - Space-separated list of name tokens
  - `{:enum, values}` - Enumeration of allowed values
  - `{:notation, names}` - One of the named notations

  ## Attribute Defaults

  - `:required` - Attribute must be specified
  - `:implied` - Attribute is optional with no default
  - `{:fixed, value}` - Attribute has fixed value
  - `{:default, value}` - Default value if not specified
  """

  defstruct elements: %{},
            attributes: %{},
            entities: %{},
            param_entities: %{},
            notations: %{},
            root_element: nil

  @type content_model ::
          :empty
          | :any
          | :pcdata
          | {:seq, [content_item]}
          | {:choice, [content_item]}
          | {:mixed, [String.t()]}

  @type content_item ::
          String.t()
          | {:one, content_model}
          | {:optional, content_model}
          | {:zero_or_more, content_model}
          | {:one_or_more, content_model}

  @type attr_type ::
          :cdata
          | :id
          | :idref
          | :idrefs
          | :entity
          | :entities
          | :nmtoken
          | :nmtokens
          | {:enum, [String.t()]}
          | {:notation, [String.t()]}

  @type attr_default ::
          :required
          | :implied
          | {:fixed, String.t()}
          | {:default, String.t()}

  @type attr_def :: %{
          name: String.t(),
          type: attr_type(),
          default: attr_default()
        }

  @type entity_def ::
          {:internal, String.t()}
          | {:external, String.t() | nil, String.t() | nil}
          | {:external_unparsed, String.t() | nil, String.t() | nil, String.t()}

  @type notation_def :: {String.t() | nil, String.t() | nil}

  @type t :: %__MODULE__{
          elements: %{String.t() => content_model()},
          attributes: %{String.t() => [attr_def()]},
          entities: %{String.t() => entity_def()},
          param_entities: %{String.t() => String.t()},
          notations: %{String.t() => notation_def()},
          root_element: String.t() | nil
        }

  @doc """
  Creates a new empty DTD model.
  """
  def new, do: %__MODULE__{}

  @doc """
  Adds an element declaration to the model.

  ## Examples

      iex> model = FnXML.DTD.Model.new()
      iex> model = FnXML.DTD.Model.add_element(model, "note", {:seq, ["to", "from", "body"]})
      iex> model.elements["note"]
      {:seq, ["to", "from", "body"]}

  """
  def add_element(%__MODULE__{} = model, name, content_model) do
    %{model | elements: Map.put(model.elements, name, content_model)}
  end

  @doc """
  Adds attribute definitions for an element.

  ## Examples

      iex> model = FnXML.DTD.Model.new()
      iex> attrs = [%{name: "id", type: :id, default: :required}]
      iex> model = FnXML.DTD.Model.add_attributes(model, "note", attrs)
      iex> model.attributes["note"]
      [%{name: "id", type: :id, default: :required}]

  """
  def add_attributes(%__MODULE__{} = model, element_name, attr_defs) do
    existing = Map.get(model.attributes, element_name, [])
    %{model | attributes: Map.put(model.attributes, element_name, existing ++ attr_defs)}
  end

  @doc """
  Adds a general entity declaration to the model.

  ## Examples

      iex> model = FnXML.DTD.Model.new()
      iex> model = FnXML.DTD.Model.add_entity(model, "copyright", {:internal, "(c) 2024"})
      iex> model.entities["copyright"]
      {:internal, "(c) 2024"}

  """
  def add_entity(%__MODULE__{} = model, name, definition) do
    %{model | entities: Map.put(model.entities, name, definition)}
  end

  @doc """
  Adds a parameter entity declaration to the model.
  """
  def add_param_entity(%__MODULE__{} = model, name, value) do
    %{model | param_entities: Map.put(model.param_entities, name, value)}
  end

  @doc """
  Adds a notation declaration to the model.
  """
  def add_notation(%__MODULE__{} = model, name, system_id, public_id \\ nil) do
    %{model | notations: Map.put(model.notations, name, {system_id, public_id})}
  end

  @doc """
  Sets the root element name from DOCTYPE declaration.
  """
  def set_root_element(%__MODULE__{} = model, name) do
    %{model | root_element: name}
  end

  @doc """
  Looks up an element declaration.
  """
  def get_element(%__MODULE__{} = model, name) do
    Map.get(model.elements, name)
  end

  @doc """
  Looks up attribute definitions for an element.
  """
  def get_attributes(%__MODULE__{} = model, element_name) do
    Map.get(model.attributes, element_name, [])
  end

  @doc """
  Looks up a general entity.
  """
  def get_entity(%__MODULE__{} = model, name) do
    Map.get(model.entities, name)
  end

  @doc """
  Looks up a parameter entity.
  """
  def get_param_entity(%__MODULE__{} = model, name) do
    Map.get(model.param_entities, name)
  end

  @doc """
  Looks up a notation.
  """
  def get_notation(%__MODULE__{} = model, name) do
    Map.get(model.notations, name)
  end
end
