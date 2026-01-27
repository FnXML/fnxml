defmodule FnXML.Namespaces.Resolver do
  @moduledoc """
  Stream transformer that resolves namespace prefixes to expanded names.

  This module transforms FnXML parser events to include expanded names
  (namespace URI + local name) instead of qualified names.

  ## Usage

      FnXML.Parser.parse(xml)
      |> FnXML.Namespaces.Resolver.resolve()
      |> Enum.to_list()

  ## Event Transformation

  Input events:
      {:start_element, "prefix:local", [{"xmlns:prefix", "uri"}, ...], loc}

  Output events:
      {:start_element, {"uri", "local"}, [{nil, "attr", "value"}, ...], loc}

  ## Options

  - `:strip_declarations` - Remove xmlns attributes from output (default: false)
  - `:include_prefix` - Include original prefix in output (default: false)
  """

  alias FnXML.Namespaces.Context

  @doc """
  Transform a stream of FnXML events to include expanded names.

  Returns a stream of events with element and attribute names expanded.
  """
  @spec resolve(Enumerable.t(), keyword()) :: Enumerable.t()
  def resolve(stream, opts \\ []) do
    Stream.transform(stream, Context.new(), fn event, ctx ->
      {events, new_ctx} = resolve_event(event, ctx, opts)
      {events, new_ctx}
    end)
  end

  @doc """
  Resolve a single event, returning transformed events and new context.

  This is useful for manual event processing.
  """
  @spec resolve_event(term(), Context.t(), keyword()) :: {list(term()), Context.t()}
  def resolve_event(event, ctx, opts \\ [])

  # Element open with 6-tuple format (from parser)
  def resolve_event({:start_element, tag, attrs, line, ls, pos}, ctx, opts) do
    case Context.push(ctx, attrs, opts) do
      {:ok, new_ctx, filtered_attrs} ->
        case resolve_element_and_attrs(tag, filtered_attrs, new_ctx, opts) do
          {:ok, expanded_tag, expanded_attrs} ->
            {[{:start_element, expanded_tag, expanded_attrs, line, ls, pos}], new_ctx}

          {:error, reason} ->
            # Emit error event but continue processing
            {[{:ns_error, reason, tag, line, ls, pos}], new_ctx}
        end

      {:error, reason} ->
        # Context push failed (e.g., reserved prefix violation)
        {[{:ns_error, reason, tag, line, ls, pos}], ctx}
    end
  end

  # Element close with 5-tuple format (from parser)
  def resolve_event({:end_element, tag, line, ls, pos}, ctx, opts) do
    case Context.expand_element(ctx, tag) do
      {:ok, expanded_tag} ->
        new_ctx = Context.pop(ctx)
        expanded = maybe_add_prefix(expanded_tag, tag, opts)
        {[{:end_element, expanded, line, ls, pos}], new_ctx}

      {:error, _reason} ->
        # Use original tag on error
        new_ctx = Context.pop(ctx)
        {[{:end_element, tag, line, ls, pos}], new_ctx}
    end
  end

  # Element close without location (legacy format)
  def resolve_event({:end_element, tag}, ctx, opts) do
    case Context.expand_element(ctx, tag) do
      {:ok, expanded_tag} ->
        new_ctx = Context.pop(ctx)
        expanded = maybe_add_prefix(expanded_tag, tag, opts)
        {[{:end_element, expanded}], new_ctx}

      {:error, _reason} ->
        new_ctx = Context.pop(ctx)
        {[{:end_element, tag}], new_ctx}
    end
  end

  # Text events pass through unchanged (5-tuple from parser)
  def resolve_event({:characters, content, line, ls, pos}, ctx, _opts) do
    {[{:characters, content, line, ls, pos}], ctx}
  end

  def resolve_event({:characters, content}, ctx, _opts) do
    {[{:characters, content}], ctx}
  end

  # CDATA events pass through unchanged (5-tuple from parser)
  def resolve_event({:cdata, content, line, ls, pos}, ctx, _opts) do
    {[{:cdata, content, line, ls, pos}], ctx}
  end

  def resolve_event({:cdata, content}, ctx, _opts) do
    {[{:cdata, content}], ctx}
  end

  # Comment events pass through unchanged (5-tuple from parser)
  def resolve_event({:comment, content, line, ls, pos}, ctx, _opts) do
    {[{:comment, content, line, ls, pos}], ctx}
  end

  def resolve_event({:comment, content}, ctx, _opts) do
    {[{:comment, content}], ctx}
  end

  # PI events pass through (target should be NCName but we don't transform)
  def resolve_event({:pi, target, data, loc}, ctx, _opts) do
    {[{:pi, target, data, loc}], ctx}
  end

  def resolve_event({:pi, target, data}, ctx, _opts) do
    {[{:pi, target, data}], ctx}
  end

  # Document events pass through unchanged
  def resolve_event({:start_document, info}, ctx, _opts) do
    {[{:start_document, info}], ctx}
  end

  def resolve_event({:end_document, info}, ctx, _opts) do
    {[{:end_document, info}], ctx}
  end

  # Error events (6-tuple from parser) - pass through flat format
  def resolve_event({:error, type, msg, line, ls, pos}, ctx, _opts) do
    {[{:error, type, msg, line, ls, pos}], ctx}
  end

  # DTD events (5-tuple from parser) - pass through flat format
  def resolve_event({:dtd, content, line, ls, pos}, ctx, _opts) do
    {[{:dtd, content, line, ls, pos}], ctx}
  end

  def resolve_event({:dtd, _} = event, ctx, _opts) do
    {[event], ctx}
  end

  # Prolog events (6-tuple from parser) - pass through flat format
  def resolve_event({:prolog, name, attrs, line, ls, pos}, ctx, _opts) do
    {[{:prolog, name, attrs, line, ls, pos}], ctx}
  end

  # Unknown events pass through
  def resolve_event(event, ctx, _opts) do
    {[event], ctx}
  end

  # Resolve element tag and all attributes
  defp resolve_element_and_attrs(tag, attrs, ctx, opts) do
    with {:ok, expanded_tag} <- Context.expand_element(ctx, tag),
         {:ok, expanded_attrs} <- resolve_attrs(attrs, ctx, opts) do
      expanded_tag = maybe_add_prefix(expanded_tag, tag, opts)
      {:ok, expanded_tag, expanded_attrs}
    end
  end

  # Resolve all attributes
  defp resolve_attrs(attrs, ctx, opts) do
    strip = Keyword.get(opts, :strip_declarations, false)

    results =
      attrs
      |> Enum.reject(fn {name, _} ->
        strip and is_namespace_declaration?(name)
      end)
      |> Enum.map(fn {name, value} ->
        case Context.expand_attribute(ctx, name) do
          {:ok, {uri, local}} ->
            if Keyword.get(opts, :include_prefix, false) do
              prefix = FnXML.Namespaces.QName.prefix(name)
              {:ok, {uri, local, prefix, value}}
            else
              {:ok, {uri, local, value}}
            end

          {:error, reason} ->
            {:error, {reason, name}}
        end
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      {:ok, Enum.map(results, fn {:ok, attr} -> attr end)}
    else
      {:error, elem(hd(errors), 1)}
    end
  end

  defp is_namespace_declaration?(name) do
    name == "xmlns" or String.starts_with?(name, "xmlns:")
  end

  # Optionally include original prefix in expanded name
  defp maybe_add_prefix({uri, local}, original, opts) do
    if Keyword.get(opts, :include_prefix, false) do
      prefix = FnXML.Namespaces.QName.prefix(original)
      {uri, local, prefix}
    else
      {uri, local}
    end
  end
end
