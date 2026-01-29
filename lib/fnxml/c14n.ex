defmodule FnXML.C14N do
  @moduledoc """
  XML Canonicalization (C14N) implementation.

  Provides streaming canonicalization of XML documents following W3C specifications:
  - Canonical XML 1.0 (with/without comments)
  - Exclusive Canonical XML 1.0 (with/without comments)

  ## Algorithm URIs

  | Algorithm | Atom | URI |
  |-----------|------|-----|
  | C14N 1.0 | `:c14n` | `http://www.w3.org/TR/2001/REC-xml-c14n-20010315` |
  | C14N 1.0 with Comments | `:c14n_with_comments` | `...#WithComments` |
  | Exclusive C14N | `:exc_c14n` | `http://www.w3.org/2001/10/xml-exc-c14n#` |
  | Exclusive C14N with Comments | `:exc_c14n_with_comments` | `...#WithComments` |

  ## Usage

      # Basic canonicalization
      xml = "<root b='2' a='1'><child/></root>"
      iodata = FnXML.Parser.parse(xml) |> FnXML.C14N.canonicalize()
      canonical = IO.iodata_to_binary(iodata)
      # => "<root a=\"1\" b=\"2\"><child></child></root>"

      # Exclusive C14N with inclusive namespaces
      iodata = FnXML.Parser.parse(xml)
      |> FnXML.C14N.canonicalize(
        algorithm: :exc_c14n,
        inclusive_namespaces: ["ns1", "ns2"]
      )

  ## C14N Rules

  1. UTF-8 encoding (no BOM)
  2. Line breaks normalized to LF
  3. Namespace declarations sorted alphabetically by prefix
  4. Attributes sorted by namespace URI, then local name
  5. Empty elements as `<tag></tag>` (not `<tag/>`)
  6. Comments removed (unless WithComments variant)

  ## References

  - W3C Canonical XML 1.0: https://www.w3.org/TR/xml-c14n
  - W3C Exclusive C14N: https://www.w3.org/TR/xml-exc-c14n/
  """

  alias FnXML.C14N.Serializer

  @type algorithm :: :c14n | :c14n_with_comments | :exc_c14n | :exc_c14n_with_comments

  @doc """
  Canonicalize an XML event stream to iodata.

  Collects the canonicalized stream into iodata. Use `IO.iodata_to_binary/1`
  to convert to a string if needed.

  ## Options

  - `:algorithm` - Canonicalization algorithm (default: `:c14n`)
    - `:c14n` - Canonical XML 1.0
    - `:c14n_with_comments` - Canonical XML 1.0 with comments
    - `:exc_c14n` - Exclusive Canonical XML 1.0
    - `:exc_c14n_with_comments` - Exclusive C14N with comments
  - `:inclusive_namespaces` - List of namespace prefixes to always include
    (only used with exclusive C14N algorithms, default: [])

  ## Examples

      iex> iodata = FnXML.Parser.parse("<root/>") |> FnXML.C14N.canonicalize()
      iex> IO.iodata_to_binary(iodata)
      "<root></root>"

      iex> iodata = FnXML.Parser.parse("<root b='2' a='1'/>") |> FnXML.C14N.canonicalize()
      iex> IO.iodata_to_binary(iodata)
      "<root a=\\"1\\" b=\\"2\\"></root>"

  """
  @spec canonicalize(Enumerable.t(), keyword()) :: iodata()
  def canonicalize(stream, opts \\ []) do
    stream
    |> canonicalize_stream(opts)
    |> Enum.to_list()
  end

  @doc """
  Canonicalize an XML event stream, returning a stream of iodata chunks.

  Useful for lazy processing or streaming output to a file/socket.

  ## Options

  Same as `canonicalize/2`.
  """
  @spec canonicalize_stream(Enumerable.t(), keyword()) :: Enumerable.t()
  def canonicalize_stream(stream, opts \\ []) do
    algorithm = Keyword.get(opts, :algorithm, :c14n)
    inclusive_ns = Keyword.get(opts, :inclusive_namespaces, [])

    with_comments = algorithm in [:c14n_with_comments, :exc_c14n_with_comments]

    # State: {ns_scope_stack, pending_start}
    # ns_scope_stack tracks namespace declarations at each element level
    # pending_start buffers start elements to detect empty elements
    initial_state = {[%{}], nil}

    Stream.transform(stream, initial_state, fn event, state ->
      process_event(normalize_event(event), state, algorithm, inclusive_ns, with_comments)
    end)
  end

  # Normalize events to a common format for processing
  # 6-tuple start_element: {:start_element, tag, attrs, line, ls, pos} -> {:start_element, tag, attrs}
  # 4-tuple start_element: {:start_element, tag, attrs, loc} -> {:start_element, tag, attrs}
  defp normalize_event({:start_element, tag, attrs, _line, _ls, _pos}),
    do: {:start_element, tag, attrs}

  defp normalize_event({:start_element, tag, attrs, _loc}), do: {:start_element, tag, attrs}

  # 4-tuple end_element with location: {:end_element, tag, line, ls, pos} -> {:end_element, tag}
  defp normalize_event({:end_element, tag, _line, _ls, _pos}), do: {:end_element, tag}
  # 3-tuple end_element with loc tuple: {:end_element, tag, loc} -> {:end_element, tag}
  defp normalize_event({:end_element, tag, loc}) when is_tuple(loc), do: {:end_element, tag}
  # 2-tuple end_element: {:end_element, tag} -> {:end_element, tag}
  defp normalize_event({:end_element, tag}), do: {:end_element, tag}

  # 5-tuple characters: {:characters, content, line, ls, pos} -> {:characters, content}
  defp normalize_event({:characters, content, _line, _ls, _pos}), do: {:characters, content}
  # 3-tuple characters: {:characters, content, loc} -> {:characters, content}
  defp normalize_event({:characters, content, _loc}), do: {:characters, content}

  # 5-tuple comment: {:comment, content, line, ls, pos} -> {:comment, content}
  defp normalize_event({:comment, content, _line, _ls, _pos}), do: {:comment, content}
  # 3-tuple comment: {:comment, content, loc} -> {:comment, content}
  defp normalize_event({:comment, content, _loc}), do: {:comment, content}

  # 6-tuple PI: {:processing_instruction, target, content, line, ls, pos}
  defp normalize_event({:processing_instruction, target, content, _line, _ls, _pos}),
    do: {:processing_instruction, target, content}

  # 4-tuple PI: {:processing_instruction, target, content, loc}
  defp normalize_event({:processing_instruction, target, content, _loc}),
    do: {:processing_instruction, target, content}

  # 5-tuple prolog: {:prolog, "xml", attrs, line, ls, pos}
  defp normalize_event({:prolog, tag, attrs, _line, _ls, _pos}), do: {:prolog, tag, attrs}
  # 4-tuple prolog: {:prolog, "xml", attrs, loc}
  defp normalize_event({:prolog, tag, attrs, _loc}), do: {:prolog, tag, attrs}

  # DTD events
  defp normalize_event({:dtd, content, _loc}), do: {:dtd, content}
  defp normalize_event({:dtd, content}), do: {:dtd, content}

  # Document markers pass through
  defp normalize_event({:start_document, _} = event), do: event
  defp normalize_event({:end_document, _} = event), do: event

  # Unknown events pass through
  defp normalize_event(event), do: event

  # Process document start - pass through without output
  defp process_event({:start_document, _}, state, _alg, _inc_ns, _comments) do
    {[], state}
  end

  # Process document end - flush any pending element
  defp process_event({:end_document, _}, {ns_stack, pending}, alg, inc_ns, _comments) do
    case pending do
      nil ->
        {[], {ns_stack, nil}}

      {:start, tag, attrs} ->
        ns_context = if ns_stack == [], do: %{}, else: hd(ns_stack)
        emit = Serializer.serialize_empty(tag, attrs, ns_context, alg, inc_ns)
        {[emit], {tl(ns_stack), nil}}
    end
  end

  # Process start element - buffer it to detect empty elements
  defp process_event(
         {:start_element, tag, attrs},
         {ns_stack, nil},
         _alg,
         _inc_ns,
         _comments
       ) do
    new_ns_scope = extract_ns_scope(attrs, hd(ns_stack))
    new_ns_stack = [new_ns_scope | ns_stack]
    {[], {new_ns_stack, {:start, tag, attrs}}}
  end

  # Start element when there's already a pending start - emit the pending one
  defp process_event(
         {:start_element, tag, attrs},
         {ns_stack, {:start, ptag, pattrs}},
         alg,
         inc_ns,
         _comments
       ) do
    parent_ns_context = hd(tl(ns_stack))
    emit = Serializer.serialize_start(ptag, pattrs, parent_ns_context, alg, inc_ns)
    new_ns_scope = extract_ns_scope(attrs, hd(ns_stack))
    new_ns_stack = [new_ns_scope | ns_stack]
    {[emit], {new_ns_stack, {:start, tag, attrs}}}
  end

  # End element matching pending start - empty element
  defp process_event(
         {:end_element, tag},
         {[_current | rest_ns], {:start, ptag, pattrs}},
         alg,
         inc_ns,
         _comments
       )
       when tag == ptag do
    ns_context = if rest_ns == [], do: %{}, else: hd(rest_ns)
    emit = Serializer.serialize_empty(ptag, pattrs, ns_context, alg, inc_ns)
    {[emit], {rest_ns, nil}}
  end

  # End element when there's a pending start for different tag
  defp process_event(
         {:end_element, tag},
         {[_current | rest_ns], {:start, ptag, pattrs}},
         alg,
         inc_ns,
         _comments
       ) do
    ns_context = if rest_ns == [], do: %{}, else: hd(rest_ns)
    start_emit = Serializer.serialize_start(ptag, pattrs, ns_context, alg, inc_ns)
    end_emit = Serializer.serialize_end(tag)
    {[start_emit, end_emit], {rest_ns, nil}}
  end

  # End element with no pending start
  defp process_event({:end_element, tag}, {[_ | rest_ns], nil}, _alg, _inc_ns, _comments) do
    emit = Serializer.serialize_end(tag)
    {[emit], {rest_ns, nil}}
  end

  # End element with empty namespace stack (shouldn't happen in well-formed XML)
  defp process_event({:end_element, tag}, {[], nil}, _alg, _inc_ns, _comments) do
    emit = Serializer.serialize_end(tag)
    {[emit], {[], nil}}
  end

  # Characters - flush pending start then emit text
  defp process_event(
         {:characters, content},
         {ns_stack, {:start, ptag, pattrs}},
         alg,
         inc_ns,
         _comments
       ) do
    ns_context = hd(tl(ns_stack))
    start_emit = Serializer.serialize_start(ptag, pattrs, ns_context, alg, inc_ns)
    text_emit = Serializer.serialize_text(content)
    {[start_emit, text_emit], {ns_stack, nil}}
  end

  defp process_event({:characters, content}, {ns_stack, nil}, _alg, _inc_ns, _comments) do
    emit = Serializer.serialize_text(content)
    {[emit], {ns_stack, nil}}
  end

  # Comments - only emit if WithComments algorithm
  defp process_event(
         {:comment, content},
         {ns_stack, {:start, ptag, pattrs}},
         alg,
         inc_ns,
         true = _with_comments
       ) do
    ns_context = hd(tl(ns_stack))
    start_emit = Serializer.serialize_start(ptag, pattrs, ns_context, alg, inc_ns)
    comment_emit = Serializer.serialize_comment(content)
    {[start_emit, comment_emit], {ns_stack, nil}}
  end

  defp process_event(
         {:comment, content},
         {ns_stack, nil},
         _alg,
         _inc_ns,
         true = _with_comments
       ) do
    emit = Serializer.serialize_comment(content)
    {[emit], {ns_stack, nil}}
  end

  # Comments without WithComments - skip (but flush pending if any)
  defp process_event(
         {:comment, _content},
         {ns_stack, {:start, ptag, pattrs}},
         alg,
         inc_ns,
         false = _with_comments
       ) do
    ns_context = hd(tl(ns_stack))
    start_emit = Serializer.serialize_start(ptag, pattrs, ns_context, alg, inc_ns)
    {[start_emit], {ns_stack, nil}}
  end

  defp process_event({:comment, _content}, state, _alg, _inc_ns, false = _with_comments) do
    {[], state}
  end

  # Processing instructions - flush pending and emit
  defp process_event(
         {:processing_instruction, target, content},
         {ns_stack, {:start, ptag, pattrs}},
         alg,
         inc_ns,
         _comments
       ) do
    ns_context = hd(tl(ns_stack))
    start_emit = Serializer.serialize_start(ptag, pattrs, ns_context, alg, inc_ns)
    pi_emit = Serializer.serialize_pi(target, content)
    {[start_emit, pi_emit], {ns_stack, nil}}
  end

  defp process_event(
         {:processing_instruction, target, content},
         {ns_stack, nil},
         _alg,
         _inc_ns,
         _comments
       ) do
    emit = Serializer.serialize_pi(target, content)
    {[emit], {ns_stack, nil}}
  end

  # XML prolog - skip in canonical form
  defp process_event({:prolog, _, _}, state, _alg, _inc_ns, _comments) do
    {[], state}
  end

  # DTD - skip in canonical form
  defp process_event({:dtd, _}, state, _alg, _inc_ns, _comments) do
    {[], state}
  end

  # Unknown events - pass through state unchanged
  defp process_event(_event, state, _alg, _inc_ns, _comments) do
    {[], state}
  end

  # Extract namespace declarations from attributes and merge with parent scope
  defp extract_ns_scope(attrs, parent_scope) do
    Enum.reduce(attrs, parent_scope, fn
      {"xmlns", uri}, scope ->
        Map.put(scope, "", uri)

      {"xmlns:" <> prefix, uri}, scope ->
        Map.put(scope, prefix, uri)

      _, scope ->
        scope
    end)
  end

  @doc """
  Get the algorithm URI for a given algorithm atom.

  ## Examples

      iex> FnXML.C14N.algorithm_uri(:c14n)
      "http://www.w3.org/TR/2001/REC-xml-c14n-20010315"

      iex> FnXML.C14N.algorithm_uri(:exc_c14n)
      "http://www.w3.org/2001/10/xml-exc-c14n#"

  """
  @spec algorithm_uri(algorithm()) :: String.t()
  def algorithm_uri(:c14n), do: FnXML.Security.Namespaces.c14n()
  def algorithm_uri(:c14n_with_comments), do: FnXML.Security.Namespaces.c14n_with_comments()
  def algorithm_uri(:exc_c14n), do: FnXML.Security.Namespaces.exc_c14n()

  def algorithm_uri(:exc_c14n_with_comments),
    do: FnXML.Security.Namespaces.exc_c14n_with_comments()

  @doc """
  Parse an algorithm URI to its atom representation.

  ## Examples

      iex> FnXML.C14N.algorithm_atom("http://www.w3.org/TR/2001/REC-xml-c14n-20010315")
      {:ok, :c14n}

      iex> FnXML.C14N.algorithm_atom("unknown")
      {:error, :unknown_algorithm}

  """
  @spec algorithm_atom(String.t()) :: {:ok, algorithm()} | {:error, :unknown_algorithm}
  def algorithm_atom(uri) do
    case uri do
      "http://www.w3.org/TR/2001/REC-xml-c14n-20010315" -> {:ok, :c14n}
      "http://www.w3.org/TR/2001/REC-xml-c14n-20010315#WithComments" -> {:ok, :c14n_with_comments}
      "http://www.w3.org/2001/10/xml-exc-c14n#" -> {:ok, :exc_c14n}
      "http://www.w3.org/2001/10/xml-exc-c14n#WithComments" -> {:ok, :exc_c14n_with_comments}
      _ -> {:error, :unknown_algorithm}
    end
  end
end
