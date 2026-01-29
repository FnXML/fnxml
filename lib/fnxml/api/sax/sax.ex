defmodule FnXML.API.SAX do
  @moduledoc """
  SAX-style callback-based XML processing.

  SAX (Simple API for XML) is a push-based, event-driven API where
  the parser calls handler methods as it encounters XML constructs.
  SAX uses O(1) memory - events stream through without building a tree.

  ## Specifications

  - SAX 2.0: http://www.saxproject.org/
  - W3C XML 1.0: https://www.w3.org/TR/xml/

  ## Memory Characteristics

  SAX maintains constant O(1) memory regardless of document size, making it
  ideal for processing very large XML files. The tradeoff is that you cannot
  navigate backwards - you process elements as they stream through.

  ## Usage

  Define a handler module that implements the `FnXML.API.SAX` behaviour:

      defmodule MyHandler do
        @behaviour FnXML.API.SAX

        @impl true
        def start_document(state), do: {:ok, state}

        @impl true
        def end_document(state), do: {:ok, state}

        @impl true
        def start_element(_uri, local_name, _qname, _attrs, state) do
          {:ok, Map.update(state, :elements, [local_name], &[local_name | &1])}
        end

        @impl true
        def end_element(_uri, _local_name, _qname, state), do: {:ok, state}

        @impl true
        def characters(text, state) do
          {:ok, Map.update(state, :characters, text, &(&1 <> text))}
        end
      end

      # Pipeline style (recommended)
      {:ok, result} = FnXML.Parser.parse("<root><child>text</child></root>")
                      |> FnXML.API.SAX.dispatch(MyHandler, %{})
      # result.elements => ["child", "root"]

      # Quick parse (convenience)
      {:ok, result} = FnXML.API.SAX.parse("<root><child>text</child></root>", MyHandler, %{})

  ## Using the Default Handler

  For simpler cases, use `FnXML.SAX.Handler` which provides defaults:

      defmodule CountHandler do
        use FnXML.SAX.Handler

        @impl true
        def start_element(_uri, _local, _qname, _attrs, state) do
          {:ok, Map.update(state, :count, 1, &(&1 + 1))}
        end
      end

      {:ok, %{count: 3}} = FnXML.API.SAX.parse("<a><b/><c/></a>", CountHandler, %{count: 0})

  ## Return Values

  Handler callbacks can return:
  - `{:ok, new_state}` - Continue parsing with new state
  - `{:halt, final_state}` - Stop parsing early, return state
  - `{:error, reason}` - Stop parsing with error

  ## Namespace Support

  By default, namespace resolution is enabled. Element and attribute
  names include namespace URIs:

      # With namespaces (default)
      start_element("http://example.org", "child", "ex:child", attrs, state)

      # Without namespaces
      FnXML.API.SAX.parse(xml, Handler, state, namespaces: false)
      # start_element(nil, "ex:child", "ex:child", attrs, state)
  """

  # Required callbacks
  @doc """
  Called when document parsing begins.
  """
  @callback start_document(state :: term()) ::
              {:ok, state :: term()} | {:error, term()}

  @doc """
  Called when document parsing ends successfully.
  """
  @callback end_document(state :: term()) ::
              {:ok, state :: term()} | {:error, term()}

  @doc """
  Called when an element start tag is encountered.

  ## Parameters

  - `uri` - Namespace URI (or nil if no namespace)
  - `local_name` - Local name without prefix
  - `qname` - Qualified name (prefix:local or just local)
  - `attributes` - List of `{name, value}` tuples
  - `state` - Current handler state
  """
  @callback start_element(
              uri :: String.t() | nil,
              local_name :: String.t(),
              qname :: String.t(),
              attributes :: [{String.t(), String.t()}],
              state :: term()
            ) :: {:ok, state :: term()} | {:halt, state :: term()} | {:error, term()}

  @doc """
  Called when an element end tag is encountered.
  """
  @callback end_element(
              uri :: String.t() | nil,
              local_name :: String.t(),
              qname :: String.t(),
              state :: term()
            ) :: {:ok, state :: term()} | {:error, term()}

  @doc """
  Called when character data is encountered.

  Note: The parser may split text into multiple `characters` calls.
  """
  @callback characters(chars :: String.t(), state :: term()) ::
              {:ok, state :: term()} | {:error, term()}

  # Optional callbacks

  @doc """
  Called when a namespace prefix mapping begins scope.
  """
  @callback start_prefix_mapping(
              prefix :: String.t(),
              uri :: String.t(),
              state :: term()
            ) :: {:ok, state :: term()} | {:error, term()}

  @doc """
  Called when a namespace prefix mapping ends scope.
  """
  @callback end_prefix_mapping(prefix :: String.t(), state :: term()) ::
              {:ok, state :: term()} | {:error, term()}

  @doc """
  Called when a processing instruction is encountered.
  """
  @callback processing_instruction(
              target :: String.t(),
              data :: String.t() | nil,
              state :: term()
            ) :: {:ok, state :: term()} | {:error, term()}

  @doc """
  Called when a comment is encountered.
  """
  @callback comment(text :: String.t(), state :: term()) ::
              {:ok, state :: term()} | {:error, term()}

  @doc """
  Called when ignorable whitespace is encountered.
  """
  @callback ignorable_whitespace(chars :: String.t(), state :: term()) ::
              {:ok, state :: term()} | {:error, term()}

  @doc """
  Called when a parse error is encountered.
  """
  @callback error(reason :: term(), location :: term(), state :: term()) ::
              {:ok, state :: term()} | {:error, term()}

  @optional_callbacks [
    start_prefix_mapping: 3,
    end_prefix_mapping: 2,
    processing_instruction: 3,
    comment: 2,
    ignorable_whitespace: 2,
    error: 3
  ]

  @doc """
  Dispatch SAX events from a parser stream to a handler.

  This is the primary way to use SAX with FnXML's pipeline style,
  taking a pre-parsed event stream as input.

  ## Options

  - `:namespaces` - Enable namespace resolution (default: true)

  ## Examples

      # Pipeline style (recommended)
      {:ok, state} = FnXML.Parser.parse("<root><item/></root>")
                     |> FnXML.API.SAX.dispatch(MyHandler, %{})

      # With validation and transforms
      {:ok, state} = File.stream!("data.xml")
                     |> FnXML.Parser.parse()
                     |> FnXML.Event.Validate.well_formed()
                     |> FnXML.API.SAX.dispatch(MyHandler, %{count: 0})

      # Without namespace resolution
      {:ok, state} = FnXML.Parser.parse(xml)
                     |> FnXML.API.SAX.dispatch(MyHandler, %{}, namespaces: false)
  """
  @spec dispatch(Enumerable.t(), module(), term(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def dispatch(stream, handler, initial_state, opts \\ []) do
    resolve_namespaces = Keyword.get(opts, :namespaces, true)

    stream =
      if resolve_namespaces do
        FnXML.Namespaces.resolve(stream)
      else
        stream
      end

    # Call start_document
    case handler.start_document(initial_state) do
      {:ok, state} ->
        process_events(stream, handler, state, resolve_namespaces)

      {:error, _} = error ->
        error
    end
  end

  defp process_events(stream, handler, initial_state, resolve_namespaces) do
    result =
      Enum.reduce_while(stream, {:ok, initial_state}, fn event, {:ok, state} ->
        case dispatch_event(event, handler, state, resolve_namespaces) do
          {:ok, new_state} -> {:cont, {:ok, new_state}}
          {:halt, final_state} -> {:halt, {:halt, final_state}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case result do
      {:ok, state} ->
        handler.end_document(state)

      {:halt, state} ->
        {:ok, state}

      {:error, _} = error ->
        error
    end
  end

  # Dispatch events to handler callbacks

  # With namespace resolution - start_element with position info (6-tuple from namespace resolver)
  defp dispatch_event(
         {:start_element, {uri, local}, attrs, _line, _ls, _pos},
         handler,
         state,
         true
       ) do
    qname = if uri, do: "#{local}", else: local
    handler.start_element(uri, local, qname, attrs, state)
  end

  # With namespace resolution - end_element with position info (5-tuple from namespace resolver)
  defp dispatch_event({:end_element, {uri, local}, _line, _ls, _pos}, handler, state, true) do
    qname = if uri, do: "#{local}", else: local
    handler.end_element(uri, local, qname, state)
  end

  # With namespace resolution - element names are {uri, local} (legacy 2-tuple)
  defp dispatch_event({:end_element, {uri, local}}, handler, state, true) do
    qname = if uri, do: "#{local}", else: local
    handler.end_element(uri, local, qname, state)
  end

  # Without namespace resolution - element names are strings
  # 6-tuple from parser: {:start_element, tag, attrs, line, ls, pos}
  defp dispatch_event({:start_element, tag, attrs, _line, _ls, _pos}, handler, state, false)
       when is_binary(tag) do
    {_prefix, local} = parse_qname(tag)
    handler.start_element(nil, local, tag, attrs, state)
  end

  # 5-tuple from parser: {:end_element, tag, line, ls, pos}
  defp dispatch_event({:end_element, tag, _line, _ls, _pos}, handler, state, false)
       when is_binary(tag) do
    {_prefix, local} = parse_qname(tag)
    handler.end_element(nil, local, tag, state)
  end

  # 2-tuple legacy (no position): {:end_element, tag}
  defp dispatch_event({:end_element, tag}, handler, state, false) when is_binary(tag) do
    {_prefix, local} = parse_qname(tag)
    handler.end_element(nil, local, tag, state)
  end

  # Text content - 5-tuple from parser: {:characters, content, line, ls, pos}
  defp dispatch_event({:characters, content, _line, _ls, _pos}, handler, state, _ns) do
    handler.characters(content, state)
  end

  # Comments (optional callback) - 5-tuple from parser
  defp dispatch_event({:comment, content, _line, _ls, _pos}, handler, state, _ns) do
    if function_exported?(handler, :comment, 2) do
      handler.comment(content, state)
    else
      {:ok, state}
    end
  end

  # Processing instructions (optional callback) - 6-tuple from parser
  defp dispatch_event(
         {:processing_instruction, target, data, _line, _ls, _pos},
         handler,
         state,
         _ns
       ) do
    if function_exported?(handler, :processing_instruction, 3) do
      handler.processing_instruction(target, data, state)
    else
      {:ok, state}
    end
  end

  # Errors (optional callback) - 6-tuple from parser
  defp dispatch_event({:error, type, msg, line, ls, pos}, handler, state, _ns) do
    if function_exported?(handler, :error, 3) do
      handler.error({type, msg}, {line, ls, pos}, state)
    else
      {:error, {{type, msg}, {line, ls, pos}}}
    end
  end

  # Skip document markers and other events
  defp dispatch_event({:start_document, _}, _handler, state, _ns), do: {:ok, state}
  defp dispatch_event({:end_document, _}, _handler, state, _ns), do: {:ok, state}
  # 6-tuple from parser: {:prolog, name, attrs, line, ls, pos}
  defp dispatch_event({:prolog, _, _, _, _, _}, _handler, state, _ns), do: {:ok, state}
  # 5-tuple from parser: {:dtd, content, line, ls, pos}
  defp dispatch_event({:dtd, _, _, _, _}, _handler, state, _ns), do: {:ok, state}

  # CDATA - 5-tuple from parser: {:cdata, content, line, ls, pos}
  defp dispatch_event({:cdata, content, line, ls, pos}, handler, state, ns) do
    dispatch_event({:characters, content, line, ls, pos}, handler, state, ns)
  end

  defp dispatch_event(_, _handler, state, _ns), do: {:ok, state}

  # Parse QName into {prefix, local_name}
  defp parse_qname(qname) do
    case String.split(qname, ":", parts: 2) do
      [local] -> {nil, local}
      [prefix, local] -> {prefix, local}
    end
  end
end
