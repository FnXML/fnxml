defmodule FnXML.Validate do
  @moduledoc """
  Composable validation functions for XML event streams.

  These functions can be included in a stream pipeline to validate
  well-formedness, attribute uniqueness, and namespace declarations.

  ## Usage

      FnXML.Parser.parse(xml)
      |> FnXML.Validate.well_formed()
      |> FnXML.Validate.attributes()
      |> FnXML.Validate.namespaces()
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
      ...> |> FnXML.Validate.well_formed()
      ...> |> Enum.to_list()
      [{:start_element, "a", [], _}, {:start_element, "b", [], _}, {:end_element, "b"}, {:end_element, "a"}]

      iex> FnXML.Parser.parse("<a></b>")
      ...> |> FnXML.Validate.well_formed()
      ...> |> Enum.to_list()
      ** (FnXML.Error) [tag_mismatch] Expected </a>, got </b>
  """
  def well_formed(stream, opts \\ []) do
    on_error = Keyword.get(opts, :on_error, :raise)

    Stream.transform(stream, [], fn elem, stack ->
      validate_structure(elem, stack, on_error)
    end)
  end

  # Handle flattened 6-tuple format: {:start_element, tag, attrs, line, ls, pos}
  defp validate_structure(
         {:start_element, tag, _attrs, _line, _ls, _pos} = elem,
         stack,
         _on_error
       ) do
    tag_tuple = Element.tag(tag)
    {[elem], [tag_tuple | stack]}
  end

  defp validate_structure({:end_element, tag} = elem, [], on_error) do
    {tag_name, ns} = Element.tag(tag)
    full_tag = if ns == "", do: tag_name, else: "#{ns}:#{tag_name}"

    error = Error.unexpected_close(full_tag, {0, 0})
    handle_error(error, elem, [], on_error)
  end

  # Handle flattened 5-tuple format: {:end_element, tag, line, ls, pos}
  defp validate_structure({:end_element, tag, line, ls, pos} = elem, [], on_error) do
    {tag_name, ns} = Element.tag(tag)
    full_tag = if ns == "", do: tag_name, else: "#{ns}:#{tag_name}"
    {line_num, col} = loc_to_position({line, ls, pos})

    error = Error.unexpected_close(full_tag, {line_num, col})
    handle_error(error, elem, [], on_error)
  end

  defp validate_structure({:end_element, tag} = elem, [expected | rest], on_error) do
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

  # Handle flattened 5-tuple format: {:end_element, tag, line, ls, pos}
  defp validate_structure({:end_element, tag, line, ls, pos} = elem, [expected | rest], on_error) do
    actual = Element.tag(tag)

    if actual == expected do
      {[elem], rest}
    else
      {exp_name, exp_ns} = expected
      {act_name, act_ns} = actual
      expected_str = if exp_ns == "", do: exp_name, else: "#{exp_ns}:#{exp_name}"
      actual_str = if act_ns == "", do: act_name, else: "#{act_ns}:#{act_name}"
      {line_num, col} = loc_to_position({line, ls, pos})

      error = Error.tag_mismatch(expected_str, actual_str, {line_num, col})
      handle_error(error, elem, [expected | rest], on_error)
    end
  end

  # Check for unclosed elements at end of document
  defp validate_structure({:end_document, _} = elem, [], _on_error) do
    # Stack is empty - all elements properly closed
    {[elem], []}
  end

  defp validate_structure({:end_document, _} = elem, stack, on_error) do
    # Stack has unclosed elements - emit errors
    errors = make_unclosed_errors(stack)
    handle_unclosed_errors(errors, elem, on_error)
  end

  defp validate_structure(elem, stack, _on_error) do
    # Text, comment, prolog, proc_inst - pass through
    {[elem], stack}
  end

  # Create error structs for unclosed elements
  defp make_unclosed_errors(stack) do
    stack
    |> Enum.reverse()
    |> Enum.map(fn {tag_name, ns} ->
      full_tag = if ns == "", do: tag_name, else: "#{ns}:#{tag_name}"

      Error.parse_error(:unclosed_tag, "Unclosed element <#{full_tag}>", nil, nil, %{
        tag: full_tag
      })
    end)
  end

  defp handle_unclosed_errors(errors, _end_doc_elem, :raise) do
    raise hd(errors)
  end

  defp handle_unclosed_errors(errors, end_doc_elem, :emit) do
    error_events = Enum.map(errors, fn err -> {:error, err} end)
    {error_events ++ [end_doc_elem], []}
  end

  defp handle_unclosed_errors(_errors, end_doc_elem, :skip) do
    {[end_doc_elem], []}
  end

  @doc """
  Validate that attributes within each element are unique.

  Checks for:
  - Duplicate attribute names within a single element

  ## Options

  - `:on_error` - How to handle errors (`:raise`, `:emit`, `:skip`)

  ## Examples

      iex> FnXML.Parser.parse(~s(<a x="1" y="2"/>))
      ...> |> FnXML.Validate.attributes()
      ...> |> Enum.to_list()
      [{:start_element, "a", [{"x", "1"}, {"y", "2"}], _}, {:end_element, "a"}]

      iex> FnXML.Parser.parse(~s(<a x="1" x="2"/>))
      ...> |> FnXML.Validate.attributes()
      ...> |> Enum.to_list()
      ** (FnXML.Error) [duplicate_attr] Duplicate attribute 'x'
  """
  def attributes(stream, opts \\ []) do
    on_error = Keyword.get(opts, :on_error, :raise)

    Stream.map(stream, fn
      # 6-tuple format (from parser)
      {:start_element, _tag, attrs, line, ls, pos} = elem ->
        case check_duplicate_attrs(attrs) do
          :ok ->
            elem

          {:error, dup_attr} ->
            {line_num, col} = loc_to_position({line, ls, pos})
            error = Error.duplicate_attribute(dup_attr, {line_num, col})

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
  Validate that attribute values don't contain forbidden characters.

  Per XML 1.0 spec, the `<` character is forbidden in attribute values.
  Entity values that expand to contain `<` are also invalid.

  ## Options

  - `:on_error` - How to handle errors (`:raise`, `:emit`, `:error`)

  ## Examples

      iex> FnXML.Parser.parse(~s(<a x="valid"/>))
      ...> |> FnXML.Validate.attribute_values()
      ...> |> Enum.to_list()
      [{:start_element, "a", [{"x", "valid"}], _}, {:end_element, "a"}]

      iex> FnXML.Parser.parse(~s(<a x="has < char"/>))
      ...> |> FnXML.Validate.attribute_values()
      ...> |> Enum.to_list()
      ** (FnXML.Error) '<' not allowed in attribute value
  """
  def attribute_values(stream, opts \\ []) do
    on_error = Keyword.get(opts, :on_error, :error)

    Stream.flat_map(stream, fn
      # 6-tuple format (from parser)
      {:start_element, _tag, attrs, line, ls, pos} = event ->
        case check_attr_values(attrs) do
          :ok ->
            [event]

          {:error, attr_name, reason} ->
            {line_num, col} = loc_to_position({line, ls, pos})
            handle_attr_value_error(attr_name, reason, {line_num, col}, on_error, event)
        end

      event ->
        [event]
    end)
  end

  defp check_attr_values(attrs) do
    Enum.find_value(attrs, :ok, fn {name, value} ->
      cond do
        String.contains?(value, "<") ->
          {:error, name, "'<' not allowed in attribute value"}

        true ->
          nil
      end
    end)
  end

  defp handle_attr_value_error(attr_name, reason, {line, col}, :error, _event) do
    [{:error, "Invalid attribute '#{attr_name}': #{reason}", {line, 0, col}}]
  end

  defp handle_attr_value_error(attr_name, reason, {line, _col}, :raise, _event) do
    raise "Invalid attribute '#{attr_name}': #{reason} at line #{line}"
  end

  defp handle_attr_value_error(_attr_name, _reason, _loc, :emit, event) do
    [event]
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
      ...> |> FnXML.Validate.namespaces()
      ...> |> Enum.to_list()
      [{:start_element, "root", _, _}, {:start_element, "ns:child", [], _}, {:end_element, "ns:child"}, {:end_element, "root"}]

      iex> FnXML.Parser.parse("<ns:root/>")
      ...> |> FnXML.Validate.namespaces()
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

  # 6-tuple format (from parser)
  defp validate_namespaces(
         {:start_element, tag, attrs, line, ls, pos} = elem,
         [current_scope | rest_scopes],
         on_error
       ) do
    loc = {line, ls, pos}
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

  defp validate_namespaces({:end_element, _tag} = elem, [_current | rest], _on_error) do
    # Pop namespace scope
    {[elem], rest}
  end

  # 5-tuple format (from parser)
  defp validate_namespaces(
         {:end_element, _tag, _line, _ls, _pos} = elem,
         [_current | rest],
         _on_error
       ) do
    # Pop namespace scope
    {[elem], rest}
  end

  defp validate_namespaces({:end_element, _tag} = elem, [], _on_error) do
    # Edge case: more closes than opens (will be caught by well_formed)
    {[elem], []}
  end

  # 5-tuple format (from parser)
  defp validate_namespaces({:end_element, _tag, _line, _ls, _pos} = elem, [], _on_error) do
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
      |> FnXML.Validate.all(validators: [:structure, :attributes])
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

  # ============================================================================
  # Comment Validation (W3C Production [15])
  # ============================================================================

  @doc """
  Validate that comments don't contain '--' (double-hyphen).

  Per W3C XML 1.0 Production [15], the string '--' is not allowed
  within comment content. The only valid occurrence of '--' is at
  the end as part of the closing '-->'.

  ## Options

  - `:on_error` - How to handle invalid comments:
    - `:error` (default) - Emit `{:error, message, loc}` event
    - `:raise` - Raise an exception

  ## Examples

      # Valid comments pass through
      iex> FnXML.Parser.parse("<!-- single - hyphen ok -->")
      ...> |> FnXML.Validate.comments()
      ...> |> Enum.to_list()
      [{:start_document, nil}, {:comment, " single - hyphen ok ", _}, {:end_document, nil}]

      # Invalid comment with --
      iex> FnXML.Parser.parse("<!-- invalid -- comment -->")
      ...> |> FnXML.Validate.comments()
      ...> |> Enum.to_list()
      # Returns error event for '--' in comment
  """
  def comments(stream, opts \\ []) do
    on_error = Keyword.get(opts, :on_error, :error)

    Stream.flat_map(stream, fn
      {:comment, content, line, ls, pos} = event ->
        loc = {line, ls, pos}

        cond do
          # Check for -- anywhere in content
          :binary.match(content, "--") != :nomatch ->
            {offset, _len} = :binary.match(content, "--")
            handle_comment_error(loc, offset, on_error)

          # Check if content ends with - (would make ---> invalid)
          String.ends_with?(content, "-") ->
            handle_comment_dash_end_error(loc, on_error)

          true ->
            [event]
        end

      event ->
        [event]
    end)
  end

  defp handle_comment_error(loc, offset, :error) do
    msg = "'--' not allowed in comments (at byte offset #{offset})"
    [{:error, msg, loc}]
  end

  defp handle_comment_error(loc, offset, :emit) do
    msg = "'--' not allowed in comments (at byte offset #{offset})"
    [{:error, msg, loc}]
  end

  defp handle_comment_error(loc, offset, :raise) do
    {line, _, _} = loc
    raise "'--' not allowed in comments (at byte offset #{offset}), line #{line}"
  end

  defp handle_comment_dash_end_error(loc, :error) do
    [{:error, "Comment cannot end with '-' (would form '--->')", loc}]
  end

  defp handle_comment_dash_end_error(loc, :emit) do
    [{:error, "Comment cannot end with '-' (would form '--->')", loc}]
  end

  defp handle_comment_dash_end_error(loc, :raise) do
    {line, _, _} = loc
    raise "Comment cannot end with '-' (would form '--->'), line #{line}"
  end

  @doc """
  Validate processing instructions have valid targets.

  Checks:
  - PI target is not empty
  - PI target is not "xml" (case-insensitive, reserved for XML declaration)

  ## Options

  - `:on_error` - How to handle errors:
    - `:error` (default) - Emit error event in stream
    - `:raise` - Raise exception

  ## Examples

      # Valid PI
      iex> FnXML.Parser.parse("<?target data?>")
      ...> |> FnXML.Validate.processing_instructions()
      ...> |> Enum.to_list()
      ...> |> Enum.any?(fn {:error, _, _} -> true; _ -> false end)
      false

      # Invalid - empty target
      iex> FnXML.Parser.parse("<? ?>")
      ...> |> FnXML.Validate.processing_instructions()
      ...> |> Enum.to_list()
      ...> |> Enum.any?(fn {:error, _, _} -> true; _ -> false end)
      true
  """
  def processing_instructions(stream, opts \\ []) do
    on_error = Keyword.get(opts, :on_error, :error)

    Stream.flat_map(stream, fn
      {:processing_instruction, target, _content, line, ls, pos} = event ->
        validate_pi_target(event, target, {line, ls, pos}, on_error)

      event ->
        [event]
    end)
  end

  defp validate_pi_target(event, target, loc, on_error) do
    cond do
      target == "" or target == nil ->
        handle_pi_error(loc, "PI target cannot be empty", on_error)

      String.downcase(target) == "xml" ->
        handle_pi_error(loc, "PI target 'xml' is reserved", on_error)

      true ->
        [event]
    end
  end

  defp handle_pi_error(loc, msg, :error) do
    [{:error, msg, loc}]
  end

  defp handle_pi_error(loc, msg, :emit) do
    [{:error, msg, loc}]
  end

  defp handle_pi_error(loc, msg, :raise) do
    raise "#{msg} at #{inspect(loc)}"
  end

  @doc """
  Apply all XML conformance validations to an event stream.

  This is a convenience function that combines all validation checks
  needed for full XML 1.0 conformance. Use this for strict validation.

  Includes:
  - `well_formed/2` - Tag matching
  - `attributes/2` - Unique attribute names
  - `comments/2` - No '--' in comments, no trailing '-'
  - `processing_instructions/2` - Valid PI targets
  - `characters/2` - Valid XML characters

  ## Options

  - `:on_error` - How to handle errors: `:error` (default), `:raise`

  ## Examples

      FnXML.parse_stream(xml)
      |> FnXML.Validate.conformant()
      |> Enum.to_list()

      # For conformance testing with entities
      FnXML.parse_stream(xml)
      |> FnXML.Validate.conformant()
      |> FnXML.Transform.Entities.resolve(on_unknown: :keep)
      |> Enum.to_list()
  """
  def conformant(stream, opts \\ []) do
    stream
    |> well_formed(opts)
    |> attributes(opts)
    |> comments(opts)
    |> processing_instructions(opts)
  end

  # ============================================================================
  # Root Element Boundary Validation
  # ============================================================================

  @doc """
  Validate content only appears within the root element.

  Per XML 1.0, the document content must consist of a single root element.
  Character data (except whitespace) and CDATA sections are not allowed
  before or after the root element.

  Rejects:
  - Non-whitespace characters before root element
  - Non-whitespace characters after root element closes
  - CDATA sections outside root element

  Allows:
  - Whitespace, comments, and PIs before/after root element
  - XML declaration (prolog) before root element
  - DTD declaration before root element

  ## Options

  - `:on_error` - How to handle errors:
    - `:error` (default) - Emit error event in stream
    - `:raise` - Raise exception

  ## Examples

      # Valid - only whitespace before/after root
      FnXML.parse_stream("<root/>")
      |> FnXML.Validate.root_boundary()
      |> Enum.to_list()

      # Invalid - text after root
      FnXML.parse_stream("<root/>extra text")
      |> FnXML.Validate.root_boundary()
      |> Enum.to_list()
      # Returns error event for content after root
  """
  def root_boundary(stream, opts \\ []) do
    on_error = Keyword.get(opts, :on_error, :error)

    # State: :prolog | {:in_root, depth} | :after_root
    Stream.transform(stream, :prolog, fn event, state ->
      validate_root_boundary(event, state, on_error)
    end)
  end

  # Start element transitions from prolog to in_root, or increments depth
  defp validate_root_boundary({:start_element, _, _, _, _, _} = event, :prolog, _on_error) do
    {[event], {:in_root, 1}}
  end

  defp validate_root_boundary(
         {:start_element, _, _, _, _, _} = event,
         {:in_root, depth},
         _on_error
       ) do
    {[event], {:in_root, depth + 1}}
  end

  # Start element after root closed - multiple roots error
  defp validate_root_boundary(
         {:start_element, tag, _, line, ls, pos} = _event,
         :after_root,
         on_error
       ) do
    handle_root_boundary_error(
      "Multiple root elements not allowed (found <#{extract_tag_name(tag)}>)",
      {line, ls, pos},
      :after_root,
      on_error
    )
  end

  # End element decrements depth, transitions to after_root when depth becomes 0
  defp validate_root_boundary({:end_element, _} = event, {:in_root, 1}, _on_error) do
    {[event], :after_root}
  end

  defp validate_root_boundary({:end_element, _, _, _, _} = event, {:in_root, 1}, _on_error) do
    {[event], :after_root}
  end

  defp validate_root_boundary({:end_element, _} = event, {:in_root, depth}, _on_error) do
    {[event], {:in_root, depth - 1}}
  end

  defp validate_root_boundary({:end_element, _, _, _, _} = event, {:in_root, depth}, _on_error) do
    {[event], {:in_root, depth - 1}}
  end

  # Characters - check if whitespace-only outside root
  defp validate_root_boundary({:characters, content, line, ls, pos} = event, state, on_error)
       when state == :prolog or state == :after_root do
    if whitespace_only?(content) do
      {[event], state}
    else
      where = if state == :prolog, do: "before root element", else: "after root element"

      handle_root_boundary_error(
        "Non-whitespace content #{where}",
        {line, ls, pos},
        state,
        on_error
      )
    end
  end

  # CDATA - not allowed outside root
  defp validate_root_boundary({:cdata, _, line, ls, pos} = _event, state, on_error)
       when state == :prolog or state == :after_root do
    where = if state == :prolog, do: "before root element", else: "after root element"
    handle_root_boundary_error("CDATA section #{where}", {line, ls, pos}, state, on_error)
  end

  # End of document in prolog state means no root element
  defp validate_root_boundary({:end_document, _} = event, :prolog, on_error) do
    handle_root_boundary_error("Document has no root element", {1, 0, 0}, :prolog, on_error)
    |> case do
      {events, state} -> {events ++ [event], state}
    end
  end

  # All other events pass through
  defp validate_root_boundary(event, state, _on_error) do
    {[event], state}
  end

  defp whitespace_only?(content) do
    String.trim(content) == ""
  end

  defp extract_tag_name(tag) when is_binary(tag), do: tag
  defp extract_tag_name({name, _ns}), do: name

  defp handle_root_boundary_error(msg, loc, state, :error) do
    {[{:error, msg, loc}], state}
  end

  defp handle_root_boundary_error(msg, loc, state, :emit) do
    {[{:error, msg, loc}], state}
  end

  defp handle_root_boundary_error(msg, loc, _state, :raise) do
    {line, _, _} = loc
    raise "#{msg} at line #{line}"
  end

  # ============================================================================
  # Entity Reference Validation
  # ============================================================================

  # Predefined XML entities
  @predefined_entities ~w(amp lt gt quot apos)

  @doc """
  Validate that all entity references are defined and parsed.

  Checks that entity references in character data are either:
  - Predefined XML entities: `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`
  - Numeric character references: `&#NNN;` or `&#xHHH;`
  - Declared in DTD as parsed entities (if `:entities` option provided)

  Additionally checks that unparsed entities (those with NDATA) are not
  referenced in content (WFC: Parsed Entity).

  ## Options

  - `:on_error` - How to handle errors:
    - `:error` (default) - Emit error event in stream
    - `:raise` - Raise exception
  - `:entities` - Set of additional valid entity names (from DTD)
  - `:unparsed_entities` - Set of unparsed entity names (from DTD NDATA declarations)
  - `:external_entities` - Set of external entity names (from DTD SYSTEM/PUBLIC declarations)

  ## Examples

      # Valid - predefined entity
      FnXML.parse_stream("<doc>&amp;</doc>")
      |> FnXML.Validate.entity_references()
      |> Enum.to_list()

      # Invalid - undefined entity
      FnXML.parse_stream("<doc>&foo;</doc>")
      |> FnXML.Validate.entity_references()
      |> Enum.to_list()
      # Returns error event for undefined entity
  """
  def entity_references(stream, opts \\ []) do
    on_error = Keyword.get(opts, :on_error, :error)
    custom_entities = Keyword.get(opts, :entities, MapSet.new())
    unparsed_entities = Keyword.get(opts, :unparsed_entities, MapSet.new())
    external_entities = Keyword.get(opts, :external_entities, MapSet.new())

    Stream.flat_map(stream, fn
      {:characters, content, line, ls, pos} = event ->
        validate_entity_refs_in_text(
          event,
          content,
          {line, ls, pos},
          custom_entities,
          unparsed_entities,
          on_error
        )

      {:start_element, tag, attrs, line, ls, pos} = event ->
        validate_entity_refs_in_attrs(
          event,
          tag,
          attrs,
          {line, ls, pos},
          custom_entities,
          external_entities,
          unparsed_entities,
          on_error
        )

      event ->
        [event]
    end)
  end

  # Entity reference pattern: &name; where name is a valid XML name
  @entity_ref_pattern ~r/&([a-zA-Z_][a-zA-Z0-9._-]*);/

  defp validate_entity_refs_in_text(
         event,
         content,
         loc,
         custom_entities,
         unparsed_entities,
         on_error
       ) do
    # First check for unparsed entity references (WFC: Parsed Entity)
    case find_unparsed_entity_ref(content, unparsed_entities) do
      nil ->
        # No unparsed entity refs, check for undefined entities
        case find_undefined_entity(content, custom_entities) do
          nil ->
            [event]

          entity_name ->
            handle_entity_error(
              "Undefined entity reference '&#{entity_name};'",
              loc,
              on_error,
              event
            )
        end

      entity_name ->
        handle_entity_error(
          "Reference to unparsed entity '&#{entity_name};' in content",
          loc,
          on_error,
          event
        )
    end
  end

  defp validate_entity_refs_in_attrs(
         event,
         _tag,
         attrs,
         loc,
         custom_entities,
         external_entities,
         unparsed_entities,
         on_error
       ) do
    # First check for external entity references in attribute values
    # Per XML spec WFC: No External Entity References
    case find_external_entity_in_attrs(attrs, external_entities) do
      nil ->
        # Check for unparsed (NDATA) entity references in attributes
        # Unparsed entities are also external entities and forbidden in attributes
        case find_external_entity_in_attrs(attrs, unparsed_entities) do
          nil ->
            # No external/unparsed entity refs, check for undefined entities
            case find_undefined_entity_in_attrs(attrs, custom_entities) do
              nil ->
                [event]

              {attr_name, entity_name} ->
                handle_entity_error(
                  "Undefined entity reference '&#{entity_name};' in attribute '#{attr_name}'",
                  loc,
                  on_error,
                  event
                )
            end

          {attr_name, entity_name} ->
            handle_entity_error(
              "Reference to unparsed entity '&#{entity_name};' in attribute '#{attr_name}'",
              loc,
              on_error,
              event
            )
        end

      {attr_name, entity_name} ->
        handle_entity_error(
          "Reference to external entity '&#{entity_name};' in attribute '#{attr_name}'",
          loc,
          on_error,
          event
        )
    end
  end

  defp find_unparsed_entity_ref(content, unparsed_entities) do
    Regex.scan(@entity_ref_pattern, content)
    |> Enum.find_value(fn [_full, name] ->
      if MapSet.member?(unparsed_entities, name), do: name, else: nil
    end)
  end

  defp find_undefined_entity(content, custom_entities) do
    Regex.scan(@entity_ref_pattern, content)
    |> Enum.find_value(fn [_full, name] ->
      if valid_entity_ref?(name, custom_entities), do: nil, else: name
    end)
  end

  defp find_undefined_entity_in_attrs(attrs, custom_entities) do
    Enum.find_value(attrs, fn {attr_name, attr_value} ->
      case find_undefined_entity(attr_value, custom_entities) do
        nil -> nil
        entity_name -> {attr_name, entity_name}
      end
    end)
  end

  defp find_external_entity_in_attrs(attrs, external_entities) do
    Enum.find_value(attrs, fn {attr_name, attr_value} ->
      case find_external_entity_ref(attr_value, external_entities) do
        nil -> nil
        entity_name -> {attr_name, entity_name}
      end
    end)
  end

  defp find_external_entity_ref(content, external_entities) do
    Regex.scan(@entity_ref_pattern, content)
    |> Enum.find_value(fn [_full, name] ->
      if MapSet.member?(external_entities, name), do: name, else: nil
    end)
  end

  defp valid_entity_ref?(name, custom_entities) do
    name in @predefined_entities or MapSet.member?(custom_entities, name)
  end

  defp handle_entity_error(msg, loc, :error, _event) do
    [{:error, msg, loc}]
  end

  defp handle_entity_error(msg, loc, :raise, _event) do
    {line, _, _} = loc
    raise "#{msg} at line #{line}"
  end

  # ============================================================================
  # XML Declaration Validation
  # ============================================================================

  @valid_standalone_values ["yes", "no"]

  @doc """
  Validate XML declaration (prolog) syntax and attributes.

  Per XML 1.0 specification, the XML declaration must have:
  - Attribute names in lowercase: version, encoding, standalone
  - Correct order: version first, then encoding (optional), then standalone (optional)
  - Valid values: version must be "1.0" or "1.1", standalone must be "yes" or "no"
  - No unknown attributes
  - No whitespace in attribute values

  ## Options

  - `:on_error` - How to handle errors:
    - `:error` (default) - Emit error event in stream
    - `:raise` - Raise exception

  ## Examples

      # Valid XML declaration
      FnXML.parse_stream(~s[<?xml version="1.0"?><doc/>])
      |> FnXML.Validate.xml_declaration()
      |> Enum.to_list()

      # Invalid - uppercase VERSION
      FnXML.parse_stream(~s[<?xml VERSION="1.0"?><doc/>])
      |> FnXML.Validate.xml_declaration()
      |> Enum.to_list()
      # Returns error event
  """
  def xml_declaration(stream, opts \\ []) do
    on_error = Keyword.get(opts, :on_error, :error)

    Stream.flat_map(stream, fn
      {:prolog, "xml", attrs, line, ls, pos} = event ->
        validate_xml_declaration(event, attrs, {line, ls, pos}, on_error)

      event ->
        [event]
    end)
  end

  defp validate_xml_declaration(event, attrs, loc, on_error) do
    with :ok <- validate_xml_attr_names(attrs, loc),
         :ok <- validate_xml_attr_order(attrs, loc),
         :ok <- validate_xml_attr_values(attrs, loc) do
      [event]
    else
      {:error, msg} ->
        handle_xml_decl_error(msg, loc, on_error)
    end
  end

  # Check all attribute names are valid (lowercase, known)
  defp validate_xml_attr_names(attrs, _loc) do
    valid_names = ["version", "encoding", "standalone"]

    Enum.find_value(attrs, :ok, fn {name, _value} ->
      cond do
        name in valid_names ->
          nil

        String.downcase(name) in valid_names ->
          {:error, "XML declaration attribute '#{name}' must be lowercase"}

        true ->
          {:error, "Unknown XML declaration attribute '#{name}'"}
      end
    end)
  end

  # Check attributes are in correct order
  defp validate_xml_attr_order(attrs, _loc) do
    names = Enum.map(attrs, fn {name, _} -> name end)

    # version must be first if present
    version_idx = Enum.find_index(names, &(&1 == "version"))
    encoding_idx = Enum.find_index(names, &(&1 == "encoding"))
    standalone_idx = Enum.find_index(names, &(&1 == "standalone"))

    cond do
      # version is required and must be first
      version_idx == nil ->
        {:error, "XML declaration missing required 'version' attribute"}

      version_idx != 0 ->
        {:error, "XML declaration 'version' must be the first attribute"}

      # encoding must come before standalone
      encoding_idx != nil and standalone_idx != nil and encoding_idx > standalone_idx ->
        {:error, "XML declaration 'encoding' must come before 'standalone'"}

      # Check for duplicates
      length(names) != length(Enum.uniq(names)) ->
        {:error, "XML declaration has duplicate attributes"}

      true ->
        :ok
    end
  end

  # Check attribute values are valid
  defp validate_xml_attr_values(attrs, _loc) do
    Enum.find_value(attrs, :ok, fn {name, value} ->
      # Check for whitespace in values
      trimmed = String.trim(value)

      cond do
        value != trimmed ->
          {:error, "XML declaration '#{name}' value contains invalid whitespace"}

        name == "version" and not valid_version_num?(value) ->
          {:error, "XML declaration version must be '1.x', got '#{value}'"}

        name == "standalone" and value not in @valid_standalone_values ->
          {:error, "XML declaration standalone must be 'yes' or 'no', got '#{value}'"}

        name == "encoding" and not valid_encoding_name?(value) ->
          {:error, "Invalid encoding name '#{value}'"}

        true ->
          nil
      end
    end)
  end

  # Encoding name per XML spec: starts with letter, followed by letters, digits, ., _, -
  defp valid_encoding_name?(name) do
    Regex.match?(~r/^[A-Za-z][A-Za-z0-9._-]*$/, name)
  end

  # Version number per XML 1.0 spec: VersionNum ::= '1.' [0-9]+
  # This allows future versions like 1.2, 1.7, etc.
  defp valid_version_num?(version) do
    Regex.match?(~r/^1\.[0-9]+$/, version)
  end

  defp handle_xml_decl_error(msg, loc, :error) do
    [{:error, msg, loc}]
  end

  defp handle_xml_decl_error(msg, loc, :emit) do
    [{:error, msg, loc}]
  end

  defp handle_xml_decl_error(msg, loc, :raise) do
    {line, _, _} = loc
    raise "#{msg} at line #{line}"
  end

  # ============================================================================
  # Character Reference Validation
  # ============================================================================

  @doc """
  Validate that character references are well-formed.

  Checks for malformed character references in text content and attribute values:
  - `&#` must be followed by decimal digits and `;`
  - `&#x` must be followed by hexadecimal digits and `;`
  - Empty references (`&#;` or `&#x;`) are invalid
  - References to invalid codepoints (NUL, surrogates) are invalid

  ## Options

  - `:on_error` - How to handle errors:
    - `:error` (default) - Emit error event in stream
    - `:raise` - Raise exception

  ## Examples

      # Valid character reference
      FnXML.parse_stream("<doc>&#65;</doc>")
      |> FnXML.Validate.character_references()
      |> Enum.to_list()

      # Invalid - non-numeric
      FnXML.parse_stream("<doc>&#RE;</doc>")
      |> FnXML.Validate.character_references()
      |> Enum.to_list()
      # Returns error event
  """
  def character_references(stream, opts \\ []) do
    on_error = Keyword.get(opts, :on_error, :error)

    Stream.flat_map(stream, fn
      {:characters, content, line, ls, pos} = event ->
        validate_char_refs_in_text(event, content, {line, ls, pos}, on_error)

      {:start_element, tag, attrs, line, ls, pos} = event ->
        validate_char_refs_in_attrs(event, tag, attrs, {line, ls, pos}, on_error)

      event ->
        [event]
    end)
  end

  # Pattern to find potential character references
  # Matches &#...; patterns for validation
  @char_ref_pattern ~r/&#([^;]*);?/

  defp validate_char_refs_in_text(event, content, loc, on_error) do
    case find_invalid_char_ref(content) do
      nil ->
        [event]

      error_msg ->
        handle_char_ref_error(error_msg, loc, on_error)
    end
  end

  defp validate_char_refs_in_attrs(event, _tag, attrs, loc, on_error) do
    case find_invalid_char_ref_in_attrs(attrs) do
      nil ->
        [event]

      {attr_name, error_msg} ->
        handle_char_ref_error("#{error_msg} in attribute '#{attr_name}'", loc, on_error)
    end
  end

  defp find_invalid_char_ref(content) do
    # Look for &#... patterns
    Regex.scan(@char_ref_pattern, content, return: :index)
    |> Enum.find_value(fn [{start, len} | _] ->
      ref = binary_part(content, start, len)
      validate_single_char_ref(ref)
    end)
  end

  defp find_invalid_char_ref_in_attrs(attrs) do
    Enum.find_value(attrs, fn {attr_name, attr_value} ->
      case find_invalid_char_ref(attr_value) do
        nil -> nil
        error_msg -> {attr_name, error_msg}
      end
    end)
  end

  defp validate_single_char_ref(ref) do
    cond do
      # Empty decimal reference: &#;
      ref == "&#;" ->
        "Empty character reference '&#;'"

      # Empty hex reference: &#x;
      ref == "&#x;" ->
        "Empty character reference '#{ref}'"

      # Uppercase X is invalid per XML spec (only &#x is valid)
      String.starts_with?(ref, "&#X") ->
        "Invalid character reference '#{ref}' - use lowercase 'x' for hex references"

      # Hex reference: &#xHHH;
      String.starts_with?(ref, "&#x") ->
        validate_hex_char_ref(ref)

      # Decimal reference: &#NNN;
      String.starts_with?(ref, "&#") ->
        validate_decimal_char_ref(ref)

      true ->
        nil
    end
  end

  defp validate_decimal_char_ref(ref) do
    # Extract the numeric part: &#NNN; -> NNN
    case Regex.run(~r/^&#([^;]*);?$/, ref) do
      [_, ""] ->
        "Empty character reference '#{ref}'"

      [_, digits] ->
        if Regex.match?(~r/^[0-9]+$/, digits) do
          # Valid digits, check the codepoint value
          case Integer.parse(digits) do
            {codepoint, ""} ->
              validate_codepoint(codepoint, ref)

            _ ->
              "Invalid character reference '#{ref}'"
          end
        else
          "Invalid character reference '#{ref}' - expected decimal digits"
        end

      nil ->
        # Unclosed reference like &#65 without ;
        "Malformed character reference '#{ref}'"
    end
  end

  defp validate_hex_char_ref(ref) do
    # Extract the hex part: &#xHHH; -> HHH
    case Regex.run(~r/^&#[xX]([^;]*);?$/, ref) do
      [_, ""] ->
        "Empty character reference '#{ref}'"

      [_, hex_digits] ->
        if Regex.match?(~r/^[0-9A-Fa-f]+$/, hex_digits) do
          # Valid hex, check the codepoint value
          case Integer.parse(hex_digits, 16) do
            {codepoint, ""} ->
              validate_codepoint(codepoint, ref)

            _ ->
              "Invalid character reference '#{ref}'"
          end
        else
          "Invalid character reference '#{ref}' - expected hexadecimal digits"
        end

      nil ->
        "Malformed character reference '#{ref}'"
    end
  end

  # Validate codepoint is a legal XML character
  defp validate_codepoint(cp, ref) do
    cond do
      # NUL is never valid
      cp == 0 ->
        "Character reference '#{ref}' refers to NUL (not allowed in XML)"

      # Control characters (except tab, newline, carriage return)
      cp >= 0x1 and cp <= 0x8 ->
        "Character reference '#{ref}' refers to invalid control character"

      cp >= 0xB and cp <= 0xC ->
        "Character reference '#{ref}' refers to invalid control character"

      cp >= 0xE and cp <= 0x1F ->
        "Character reference '#{ref}' refers to invalid control character"

      # Surrogate pairs
      cp >= 0xD800 and cp <= 0xDFFF ->
        "Character reference '#{ref}' refers to surrogate codepoint (not allowed)"

      # Non-characters
      cp == 0xFFFE or cp == 0xFFFF ->
        "Character reference '#{ref}' refers to non-character"

      # Beyond Unicode range
      cp > 0x10FFFF ->
        "Character reference '#{ref}' is beyond Unicode range"

      true ->
        nil
    end
  end

  defp handle_char_ref_error(msg, loc, :error) do
    [{:error, msg, loc}]
  end

  defp handle_char_ref_error(msg, loc, :emit) do
    [{:error, msg, loc}]
  end

  defp handle_char_ref_error(msg, loc, :raise) do
    {line, _, _} = loc
    raise "#{msg} at line #{line}"
  end
end
