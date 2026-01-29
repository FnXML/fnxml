defmodule FnXML.Event.SimpleForm do
  @moduledoc """
  Converts between XML stream events and Saxy SimpleForm format.

  This module provides interoperability with the
  [Saxy](https://hexdocs.pm/saxy) XML library by supporting its SimpleForm
  data structure. SimpleForm represents XML as nested tuples:

      {tag_name, attributes, content}

  Where:
  - `tag_name` - Element name as a string
  - `attributes` - List of `{name, value}` tuples
  - `content` - List containing text strings and child element tuples

  ## Functions

  - `decode/2` - Convert event stream to SimpleForm
  - `encode/1` - Convert SimpleForm to event stream

  ## Examples

      # Decode event stream to SimpleForm
      iex> FnXML.Parser.parse("<a>text</a>")
      ...> |> FnXML.Event.SimpleForm.decode()
      {"a", [], ["text"]}

      # Encode SimpleForm to event stream
      iex> {"a", [], ["text"]}
      ...> |> FnXML.Event.SimpleForm.encode()
      ...> |> Enum.to_list()
      [{:start_element, "a", [], 1, 0, 0}, {:characters, "text", 1, 0, 0}, {:end_element, "a", 1, 0, 0}]

      # Use in pipelines with validation
      iex> FnXML.Parser.parse(xml)
      ...> |> FnXML.Event.Validate.well_formed()
      ...> |> FnXML.Event.SimpleForm.decode()

      # Encode and serialize
      iex> simple_form
      ...> |> FnXML.Event.SimpleForm.encode()
      ...> |> FnXML.Event.to_iodata()
      ...> |> IO.iodata_to_binary()

  ## See Also

  For new code, consider using `FnXML.API.DOM` instead, which provides:
  - Struct-based representation with `%FnXML.API.DOM.Element{}`
  - Document-level metadata with `%FnXML.API.DOM.Document{}`
  - Standard DOM-style API

  Conversion functions `to_dom/1` and `from_dom/1` are available to
  convert between SimpleForm and DOM formats.

  ## Credit

  The SimpleForm format was designed by the Saxy project
  (https://github.com/qcam/saxy) by Cẩm Huỳnh. This module is provided
  for interoperability with codebases using Saxy's data structures.

  ## When to Use

  Use this module when:
  - Migrating from Saxy to FnXML
  - Integrating with libraries that expect Saxy SimpleForm
  - You prefer the tuple-based representation for certain operations
  """

  alias FnXML.API.DOM
  alias FnXML.API.DOM.Element

  @doc """
  Decode an FnXML event stream to SimpleForm format.

  Takes a stream of FnXML parser events and builds the nested SimpleForm
  tuple structure. This is the primary decoding function that enables
  validation and transformation pipelines before converting to SimpleForm.

  ## Options

  - `:include_comments` - Include comments as `{:comment, content}` tuples (default: false)
  - `:include_prolog` - Return `{:prolog, attrs, simple_form}` if XML prolog present (default: false)

  ## Examples

      # Basic decoding
      iex> FnXML.Parser.parse("<a><b>text</b></a>")
      ...> |> FnXML.Event.SimpleForm.decode()
      {"a", [], [{"b", [], ["text"]}]}

      # With validation pipeline
      iex> FnXML.Parser.parse(xml)
      ...> |> FnXML.Event.Validate.well_formed()
      ...> |> FnXML.Namespaces.resolve()
      ...> |> FnXML.Event.SimpleForm.decode()

      # Include comments
      iex> FnXML.Parser.parse("<root><!-- comment --><child/></root>")
      ...> |> FnXML.Event.SimpleForm.decode(include_comments: true)
      {"root", [], [{:comment, " comment "}, {"child", [], []}]}

  """
  def decode(stream, opts \\ []) do
    include_comments = Keyword.get(opts, :include_comments, false)
    include_prolog = Keyword.get(opts, :include_prolog, false)

    {result, prolog} =
      Enum.reduce(stream, {[], nil}, fn event, {stack, prolog} ->
        handle_event(event, stack, prolog, include_comments)
      end)

    simple_form =
      case result do
        [root] -> root
        [] -> nil
        roots -> roots
      end

    if include_prolog and prolog != nil do
      {:prolog, prolog, simple_form}
    else
      simple_form
    end
  end

  @doc """
  Encode a SimpleForm tuple to an FnXML event stream.

  Takes a SimpleForm tuple and produces a stream of FnXML parser events.
  This is the primary encoding function that enables piping SimpleForm data
  through FnXML stream transformations and validation.

  ## Examples

      # Basic encoding
      iex> {"root", [], ["text"]}
      ...> |> FnXML.Event.SimpleForm.encode()
      ...> |> Enum.to_list()
      [{:start_element, "root", [], 1, 0, 0}, {:characters, "text", 1, 0, 0}, {:end_element, "root", 1, 0, 0}]

      # Encode and validate
      iex> simple_form
      ...> |> FnXML.Event.SimpleForm.encode()
      ...> |> FnXML.Event.Validate.well_formed()
      ...> |> FnXML.Event.to_iodata()
      ...> |> IO.iodata_to_binary()

      # Encode with nested elements
      iex> {"div", [{"id", "main"}], [{"span", [], ["hello"]}]}
      ...> |> FnXML.Event.SimpleForm.encode()
      ...> |> Enum.to_list()
      [
        {:start_element, "div", [{"id", "main"}], 1, 0, 0},
        {:start_element, "span", [], 1, 0, 0},
        {:characters, "hello", 1, 0, 0},
        {:end_element, "span", 1, 0, 0},
        {:end_element, "div", 1, 0, 0}
      ]

  """
  def encode(simple_form) do
    Stream.resource(
      fn -> [simple_form] end,
      &emit_next/1,
      fn _ -> :ok end
    )
  end

  # Handle open tag - push new element onto stack (6-tuple from parser)
  defp handle_event(
         {:start_element, tag, attrs, _line, _ls, _pos},
         stack,
         prolog,
         _include_comments
       ) do
    {[{tag, attrs, []} | stack], prolog}
  end

  # Handle open tag - 4-tuple normalized format
  defp handle_event({:start_element, tag, attrs, _loc}, stack, prolog, _include_comments) do
    {[{tag, attrs, []} | stack], prolog}
  end

  # Handle close tag - pop element (5-tuple from parser)
  defp handle_event(
         {:end_element, _tag, _line, _ls, _pos},
         [current | rest],
         prolog,
         _include_comments
       ) do
    handle_close(current, rest, prolog)
  end

  # Handle close tag - 3-tuple normalized format
  defp handle_event({:end_element, _tag, _loc}, [current | rest], prolog, _include_comments) do
    handle_close(current, rest, prolog)
  end

  # Handle close tag - 2-tuple legacy format
  defp handle_event({:end_element, _tag}, [current | rest], prolog, _include_comments) do
    handle_close(current, rest, prolog)
  end

  # Handle text - add to current element's content (5-tuple from parser)
  defp handle_event(
         {:characters, content, _line, _ls, _pos},
         [{tag, attrs, children} | rest],
         prolog,
         _include_comments
       ) do
    {[{tag, attrs, children ++ [content]} | rest], prolog}
  end

  # Handle text - 3-tuple normalized format
  defp handle_event(
         {:characters, content, _loc},
         [{tag, attrs, children} | rest],
         prolog,
         _include_comments
       ) do
    {[{tag, attrs, children ++ [content]} | rest], prolog}
  end

  # Handle text outside of elements (5-tuple from parser)
  defp handle_event({:characters, content, _line, _ls, _pos}, [], prolog, _include_comments) do
    if String.match?(content, ~r/^\s*$/) do
      {[], prolog}
    else
      {[content], prolog}
    end
  end

  # Handle text outside of elements (3-tuple normalized)
  defp handle_event({:characters, content, _loc}, [], prolog, _include_comments) do
    if String.match?(content, ~r/^\s*$/) do
      {[], prolog}
    else
      {[content], prolog}
    end
  end

  # Handle space events (5-tuple from parser)
  defp handle_event({:space, _content, _line, _ls, _pos}, stack, prolog, _include_comments) do
    {stack, prolog}
  end

  # Handle space events (3-tuple normalized)
  defp handle_event({:space, _content, _loc}, stack, prolog, _include_comments) do
    {stack, prolog}
  end

  # Handle comment (5-tuple from parser) - when including
  defp handle_event(
         {:comment, content, _line, _ls, _pos},
         stack,
         prolog,
         true = _include_comments
       ) do
    handle_comment_include(content, stack, prolog)
  end

  # Handle comment (3-tuple normalized) - when including
  defp handle_event({:comment, content, _loc}, stack, prolog, true = _include_comments) do
    handle_comment_include(content, stack, prolog)
  end

  # Handle comment (5-tuple from parser) - not including
  defp handle_event(
         {:comment, _content, _line, _ls, _pos},
         stack,
         prolog,
         false = _include_comments
       ) do
    {stack, prolog}
  end

  # Handle comment (3-tuple normalized) - not including
  defp handle_event({:comment, _content, _loc}, stack, prolog, false = _include_comments) do
    {stack, prolog}
  end

  # Handle CDATA (5-tuple from parser) - treat as text
  defp handle_event(
         {:cdata, content, _line, _ls, _pos},
         [{tag, attrs, children} | rest],
         prolog,
         _include_comments
       ) do
    {[{tag, attrs, children ++ [content]} | rest], prolog}
  end

  # Handle CDATA (3-tuple normalized) - treat as text
  defp handle_event(
         {:cdata, content, _loc},
         [{tag, attrs, children} | rest],
         prolog,
         _include_comments
       ) do
    {[{tag, attrs, children ++ [content]} | rest], prolog}
  end

  defp handle_event({:cdata, content, _line, _ls, _pos}, [], prolog, _include_comments) do
    {[content], prolog}
  end

  defp handle_event({:cdata, content, _loc}, [], prolog, _include_comments) do
    {[content], prolog}
  end

  # Handle prolog (6-tuple from parser)
  defp handle_event({:prolog, _name, attrs, _line, _ls, _pos}, stack, _prolog, _include_comments) do
    {stack, attrs}
  end

  # Handle prolog (4-tuple normalized)
  defp handle_event({:prolog, _name, attrs, _loc}, stack, _prolog, _include_comments) do
    {stack, attrs}
  end

  # Handle processing instructions (6-tuple from parser)
  defp handle_event(
         {:processing_instruction, _name, _content, _line, _ls, _pos},
         stack,
         prolog,
         _include_comments
       ) do
    {stack, prolog}
  end

  # Handle processing instructions (4-tuple normalized)
  defp handle_event(
         {:processing_instruction, _name, _content, _loc},
         stack,
         prolog,
         _include_comments
       ) do
    {stack, prolog}
  end

  # Handle DTD (5-tuple from parser)
  defp handle_event({:dtd, _content, _line, _ls, _pos}, stack, prolog, _include_comments) do
    {stack, prolog}
  end

  # Handle DTD (3-tuple normalized)
  defp handle_event({:dtd, _content, _loc}, stack, prolog, _include_comments) do
    {stack, prolog}
  end

  # Handle errors (6-tuple from parser)
  defp handle_event({:error, _type, _msg, _line, _ls, _pos}, stack, prolog, _include_comments) do
    {stack, prolog}
  end

  # Handle errors (3-tuple normalized)
  defp handle_event({:error, _msg, _loc}, stack, prolog, _include_comments) do
    {stack, prolog}
  end

  # Handle document start/end markers (ignore for SimpleForm compatibility)
  defp handle_event({:start_document, _}, stack, prolog, _include_comments) do
    {stack, prolog}
  end

  defp handle_event({:end_document, _}, stack, prolog, _include_comments) do
    {stack, prolog}
  end

  # Helper for including comments
  defp handle_comment_include(content, stack, prolog) do
    case stack do
      [{tag, attrs, children} | rest] ->
        {[{tag, attrs, children ++ [{:comment, content}]} | rest], prolog}

      [] ->
        {[{:comment, content}], prolog}
    end
  end

  # Close element and add to parent or return as root
  defp handle_close({tag, attrs, children}, [], prolog) do
    {[{tag, attrs, children}], prolog}
  end

  defp handle_close(
         {tag, attrs, children},
         [{parent_tag, parent_attrs, parent_children} | rest],
         prolog
       ) do
    completed = {tag, attrs, children}
    {[{parent_tag, parent_attrs, parent_children ++ [completed]} | rest], prolog}
  end

  # Nothing left to emit
  defp emit_next([]), do: {:halt, []}

  # Emit element - open tag, then queue content and close
  defp emit_next([{tag, attrs, content} | rest]) do
    open = {:start_element, tag, attrs, 1, 0, 0}
    # Queue: content items, then close tag, then rest
    new_queue = content ++ [{:close_tag, tag}] ++ rest
    {[open], new_queue}
  end

  # Emit close tag marker
  defp emit_next([{:close_tag, tag} | rest]) do
    {[{:end_element, tag, 1, 0, 0}], rest}
  end

  # Emit text content
  defp emit_next([text | rest]) when is_binary(text) do
    {[{:characters, text, 1, 0, 0}], rest}
  end

  # Emit comment
  defp emit_next([{:comment, content} | rest]) do
    {[{:comment, content, 1, 0, 0}], rest}
  end

  # Skip nil values
  defp emit_next([nil | rest]) do
    emit_next(rest)
  end

  @doc """
  Convert a list of SimpleForm elements to an FnXML event stream.

  Useful when you have multiple root elements or document fragments.

  ## Examples

      iex> [{"a", [], []}, {"b", [], []}]
      ...> |> FnXML.Event.SimpleForm.list_to_stream()
      ...> |> Enum.to_list()
      [{:start_element, "a", [], 1, 0, 0}, {:end_element, "a", 1, 0, 0}, {:start_element, "b", [], 1, 0, 0}, {:end_element, "b", 1, 0, 0}]

  """
  def list_to_stream(simple_forms) when is_list(simple_forms) do
    Stream.resource(
      fn -> simple_forms end,
      &emit_next/1,
      fn _ -> :ok end
    )
  end

  @doc """
  Convert a SimpleForm tuple to a DOM Element.

  ## Examples

      iex> {"root", [{"id", "1"}], ["text"]}
      ...> |> FnXML.Event.SimpleForm.to_dom()
      %FnXML.API.DOM.Element{tag: "root", attributes: [{"id", "1"}], children: ["text"]}

  """
  def to_dom({tag, attrs, content}) do
    children = Enum.map(content, &convert_child_to_dom/1)
    %Element{tag: tag, attributes: attrs, children: children}
  end

  defp convert_child_to_dom({tag, attrs, content}) when is_binary(tag) do
    to_dom({tag, attrs, content})
  end

  defp convert_child_to_dom({:comment, text}) do
    {:comment, text}
  end

  defp convert_child_to_dom(text) when is_binary(text) do
    text
  end

  @doc """
  Convert a DOM Element to SimpleForm tuple format.

  ## Examples

      iex> %FnXML.API.DOM.Element{tag: "root", attributes: [{"id", "1"}], children: ["text"]}
      ...> |> FnXML.Event.SimpleForm.from_dom()
      {"root", [{"id", "1"}], ["text"]}

  """
  def from_dom(%Element{tag: tag, attributes: attrs, children: children}) do
    content = Enum.map(children, &convert_child_from_dom/1)
    {tag, attrs, content}
  end

  def from_dom(%DOM.Document{root: root}) do
    from_dom(root)
  end

  defp convert_child_from_dom(%Element{} = elem) do
    from_dom(elem)
  end

  defp convert_child_from_dom({:comment, text}) do
    {:comment, text}
  end

  defp convert_child_from_dom(text) when is_binary(text) do
    text
  end
end
