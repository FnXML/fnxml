defmodule FnXML.Stream.Validate do
  @moduledoc """
  Composable validation functions for XML event streams.

  These functions can be included in a stream pipeline to validate
  well-formedness, attribute uniqueness, and namespace declarations.

  ## Usage

      FnXML.Parser.parse(xml)
      |> FnXML.Stream.Validate.well_formed()
      |> FnXML.Stream.Validate.attributes()
      |> FnXML.Stream.Validate.namespaces()
      |> Enum.to_list()

  Each validator can be used independently or combined. By default,
  errors raise an FnXML.Error exception, but this can be configured
  with the `:on_error` option.
  """

  alias FnXML.Element
  alias FnXML.Error

  @xml_namespace "http://www.w3.org/XML/1998/namespace"
  @xmlns_namespace "http://www.w3.org/2000/xmlns/"

  # Reserved namespace prefixes that are always valid
  @reserved_prefixes %{
    "xml" => @xml_namespace,
    "xmlns" => @xmlns_namespace
  }

  @doc """
  Validate that open and close tags are properly matched.

  Checks for:
  - Mismatched close tags (e.g., `<a></b>`)
  - Unexpected close tags with no matching open
  - Unclosed tags at end of stream

  ## Options

  - `:on_error` - How to handle errors:
    - `:raise` (default) - Raise FnXML.Error
    - `:emit` - Emit error as `{:error, %FnXML.Error{}}` in stream
    - `:skip` - Skip the invalid element

  ## Examples

      iex> FnXML.Parser.parse("<a><b></b></a>")
      ...> |> FnXML.Stream.Validate.well_formed()
      ...> |> Enum.to_list()
      [{:open, "a", [], _}, {:open, "b", [], _}, {:close, "b"}, {:close, "a"}]

      iex> FnXML.Parser.parse("<a></b>")
      ...> |> FnXML.Stream.Validate.well_formed()
      ...> |> Enum.to_list()
      ** (FnXML.Error) [tag_mismatch] Expected </a>, got </b>
  """
  def well_formed(stream, opts \\ []) do
    on_error = Keyword.get(opts, :on_error, :raise)

    Stream.transform(stream, [], fn elem, stack ->
      validate_structure(elem, stack, on_error)
    end)
  end

  defp validate_structure({:open, tag, _attrs, _loc} = elem, stack, _on_error) do
    tag_tuple = Element.tag(tag)
    {[elem], [tag_tuple | stack]}
  end

  defp validate_structure({:close, tag} = elem, [], on_error) do
    {tag_name, ns} = Element.tag(tag)
    full_tag = if ns == "", do: tag_name, else: "#{ns}:#{tag_name}"

    error = Error.unexpected_close(full_tag, {0, 0})
    handle_error(error, elem, [], on_error)
  end

  defp validate_structure({:close, tag, loc} = elem, [], on_error) do
    {tag_name, ns} = Element.tag(tag)
    full_tag = if ns == "", do: tag_name, else: "#{ns}:#{tag_name}"
    {line, col} = loc_to_position(loc)

    error = Error.unexpected_close(full_tag, {line, col})
    handle_error(error, elem, [], on_error)
  end

  defp validate_structure({:close, tag} = elem, [expected | rest], on_error) do
    actual = Element.tag(tag)

    if actual == expected do
      {[elem], rest}
    else
      {exp_name, exp_ns} = expected
      {act_name, act_ns} = actual
      expected_str = if exp_ns == "", do: exp_name, else: "#{exp_ns}:#{exp_name}"
      actual_str = if act_ns == "", do: act_name, else: "#{act_ns}:#{act_name}"

      error = Error.tag_mismatch(expected_str, actual_str, {0, 0})
      handle_error(error, elem, [expected | rest], on_error)
    end
  end

  defp validate_structure({:close, tag, loc} = elem, [expected | rest], on_error) do
    actual = Element.tag(tag)

    if actual == expected do
      {[elem], rest}
    else
      {exp_name, exp_ns} = expected
      {act_name, act_ns} = actual
      expected_str = if exp_ns == "", do: exp_name, else: "#{exp_ns}:#{exp_name}"
      actual_str = if act_ns == "", do: act_name, else: "#{act_ns}:#{act_name}"
      {line, col} = loc_to_position(loc)

      error = Error.tag_mismatch(expected_str, actual_str, {line, col})
      handle_error(error, elem, [expected | rest], on_error)
    end
  end

  defp validate_structure(elem, stack, _on_error) do
    # Text, comment, prolog, proc_inst - pass through
    {[elem], stack}
  end

  @doc """
  Validate that attributes within each element are unique.

  Checks for:
  - Duplicate attribute names within a single element

  ## Options

  - `:on_error` - How to handle errors (`:raise`, `:emit`, `:skip`)

  ## Examples

      iex> FnXML.Parser.parse(~s(<a x="1" y="2"/>))
      ...> |> FnXML.Stream.Validate.attributes()
      ...> |> Enum.to_list()
      [{:open, "a", [{"x", "1"}, {"y", "2"}], _}, {:close, "a"}]

      iex> FnXML.Parser.parse(~s(<a x="1" x="2"/>))
      ...> |> FnXML.Stream.Validate.attributes()
      ...> |> Enum.to_list()
      ** (FnXML.Error) [duplicate_attr] Duplicate attribute 'x'
  """
  def attributes(stream, opts \\ []) do
    on_error = Keyword.get(opts, :on_error, :raise)

    Stream.map(stream, fn
      {:open, _tag, attrs, loc} = elem ->
        case check_duplicate_attrs(attrs) do
          :ok ->
            elem

          {:error, dup_attr} ->
            {line, col} = loc_to_position(loc)
            error = Error.duplicate_attribute(dup_attr, {line, col})

            case on_error do
              :raise -> raise error
              :emit -> {:error, error}
              :skip -> elem
            end
        end

      elem ->
        elem
    end)
  end

  defp check_duplicate_attrs(attrs) do
    names = Enum.map(attrs, fn {name, _value} -> name end)

    case names -- Enum.uniq(names) do
      [] -> :ok
      [dup | _] -> {:error, dup}
    end
  end

  @doc """
  Validate that namespace prefixes are properly declared.

  Checks for:
  - Use of undeclared namespace prefixes
  - Proper handling of `xmlns:prefix` declarations

  Reserved prefixes `xml` and `xmlns` are always valid.

  ## Options

  - `:on_error` - How to handle errors (`:raise`, `:emit`, `:skip`)

  ## Examples

      iex> FnXML.Parser.parse(~s(<root xmlns:ns="http://example.com"><ns:child/></root>))
      ...> |> FnXML.Stream.Validate.namespaces()
      ...> |> Enum.to_list()
      [{:open, "root", _, _}, {:open, "ns:child", [], _}, {:close, "ns:child"}, {:close, "root"}]

      iex> FnXML.Parser.parse("<ns:root/>")
      ...> |> FnXML.Stream.Validate.namespaces()
      ...> |> Enum.to_list()
      ** (FnXML.Error) [undeclared_namespace] Undeclared namespace prefix 'ns'
  """
  def namespaces(stream, opts \\ []) do
    on_error = Keyword.get(opts, :on_error, :raise)

    # Initial state: stack of namespace scopes
    # Each scope is a map of prefix -> uri
    initial_scope = @reserved_prefixes

    Stream.transform(stream, [initial_scope], fn elem, scopes ->
      validate_namespaces(elem, scopes, on_error)
    end)
  end

  defp validate_namespaces({:open, tag, attrs, loc} = elem, [current_scope | rest_scopes], on_error) do
    # Extract xmlns declarations from attributes
    new_decls = extract_xmlns_decls(attrs)
    new_scope = Map.merge(current_scope, new_decls)

    # Check element namespace prefix
    {_tag_name, prefix} = Element.tag(tag)

    case validate_prefix(prefix, new_scope, loc) do
      :ok ->
        # Check attribute namespace prefixes too
        case validate_attr_prefixes(attrs, new_scope, loc) do
          :ok ->
            {[elem], [new_scope, current_scope | rest_scopes]}

          {:error, error} ->
            handle_error(error, elem, [current_scope | rest_scopes], on_error)
        end

      {:error, error} ->
        handle_error(error, elem, [current_scope | rest_scopes], on_error)
    end
  end

  defp validate_namespaces({:close, _tag} = elem, [_current | rest], _on_error) do
    # Pop namespace scope
    {[elem], rest}
  end

  defp validate_namespaces({:close, _tag, _loc} = elem, [_current | rest], _on_error) do
    # Pop namespace scope
    {[elem], rest}
  end

  defp validate_namespaces({:close, _tag} = elem, [], _on_error) do
    # Edge case: more closes than opens (will be caught by well_formed)
    {[elem], []}
  end

  defp validate_namespaces({:close, _tag, _loc} = elem, [], _on_error) do
    # Edge case: more closes than opens (will be caught by well_formed)
    {[elem], []}
  end

  defp validate_namespaces(elem, scopes, _on_error) do
    # Pass through other elements
    {[elem], scopes}
  end

  defp extract_xmlns_decls(attrs) do
    attrs
    |> Enum.filter(fn {name, _value} ->
      String.starts_with?(name, "xmlns:") or name == "xmlns"
    end)
    |> Enum.map(fn
      {"xmlns:" <> prefix, uri} -> {prefix, uri}
      {"xmlns", uri} -> {"", uri}
    end)
    |> Enum.into(%{})
  end

  defp validate_prefix("", _scope, _loc), do: :ok

  defp validate_prefix(prefix, scope, loc) do
    if Map.has_key?(scope, prefix) do
      :ok
    else
      {line, col} = loc_to_position(loc)
      {:error, Error.undeclared_namespace(prefix, {line, col})}
    end
  end

  defp validate_attr_prefixes(attrs, scope, loc) do
    # Check namespace prefixes in attribute names (e.g., ns:attr="value")
    attrs
    |> Enum.reject(fn {name, _} ->
      # Skip xmlns declarations themselves
      String.starts_with?(name, "xmlns:") or name == "xmlns"
    end)
    |> Enum.find_value(:ok, fn {name, _value} ->
      case String.split(name, ":", parts: 2) do
        [_name] ->
          nil

        [prefix, _local] ->
          case validate_prefix(prefix, scope, loc) do
            :ok -> nil
            error -> error
          end
      end
    end)
  end

  defp loc_to_position({line, line_start, abs_pos}), do: {line, abs_pos - line_start}

  # Handle errors according to on_error setting
  defp handle_error(error, _elem, _stack, :raise), do: raise(error)
  defp handle_error(error, _elem, stack, :emit), do: {[{:error, error}], stack}
  defp handle_error(_error, elem, stack, :skip), do: {[elem], stack}

  @doc """
  Apply multiple validators in one pipeline step.

  ## Options

  - `:validators` - List of validators to apply:
    - `:structure` - Tag matching (well_formed)
    - `:attributes` - Attribute uniqueness
    - `:namespaces` - Namespace declarations

  - `:on_error` - Error handling mode for all validators

  ## Examples

      FnXML.Parser.parse(xml)
      |> FnXML.Stream.Validate.all(validators: [:structure, :attributes])
      |> Enum.to_list()
  """
  def all(stream, opts \\ []) do
    validators = Keyword.get(opts, :validators, [:structure, :attributes, :namespaces])
    on_error = Keyword.get(opts, :on_error, :raise)
    validator_opts = [on_error: on_error]

    Enum.reduce(validators, stream, fn
      :structure, s -> well_formed(s, validator_opts)
      :attributes, s -> attributes(s, validator_opts)
      :namespaces, s -> namespaces(s, validator_opts)
    end)
  end
end
