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

  defp validate_structure({:start_element, tag, _attrs, _loc} = elem, stack, _on_error) do
    tag_tuple = Element.tag(tag)
    {[elem], [tag_tuple | stack]}
  end

  # Handle flattened 6-tuple format: {:start_element, tag, attrs, line, ls, pos}
  defp validate_structure({:start_element, tag, _attrs, _line, _ls, _pos} = elem, stack, _on_error) do
    tag_tuple = Element.tag(tag)
    {[elem], [tag_tuple | stack]}
  end

  defp validate_structure({:end_element, tag} = elem, [], on_error) do
    {tag_name, ns} = Element.tag(tag)
    full_tag = if ns == "", do: tag_name, else: "#{ns}:#{tag_name}"

    error = Error.unexpected_close(full_tag, {0, 0})
    handle_error(error, elem, [], on_error)
  end

  defp validate_structure({:end_element, tag, loc} = elem, [], on_error) do
    {tag_name, ns} = Element.tag(tag)
    full_tag = if ns == "", do: tag_name, else: "#{ns}:#{tag_name}"
    {line, col} = loc_to_position(loc)

    error = Error.unexpected_close(full_tag, {line, col})
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

  defp validate_structure({:end_element, tag, loc} = elem, [expected | rest], on_error) do
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
      {:start_element, _tag, attrs, loc} = elem ->
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

  defp validate_namespaces(
         {:start_element, tag, attrs, loc} = elem,
         [current_scope | rest_scopes],
         on_error
       ) do
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

  defp validate_namespaces({:end_element, _tag, _loc} = elem, [_current | rest], _on_error) do
    # Pop namespace scope
    {[elem], rest}
  end

  defp validate_namespaces({:end_element, _tag} = elem, [], _on_error) do
    # Edge case: more closes than opens (will be caught by well_formed)
    {[elem], []}
  end

  defp validate_namespaces({:end_element, _tag, _loc} = elem, [], _on_error) do
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
  # Character Validation (W3C Production [2])
  # ============================================================================

  @doc """
  Validate that text content and attribute values contain only valid XML characters.

  Per W3C XML 1.0 Production [2], valid characters are:
  - Tab (#x9), LF (#xA), CR (#xD)
  - #x20-#xD7FF (most of BMP)
  - #xE000-#xFFFD (private use area through replacement char)
  - #x10000-#x10FFFF (supplementary planes)

  Invalid characters include:
  - NUL and C0 control chars (#x0-#x8, #xB-#xC, #xE-#x1F)
  - Surrogate pairs (#xD800-#xDFFF)
  - Non-characters (#xFFFE-#xFFFF)

  ## Options

  - `:on_error` - How to handle invalid characters:
    - `:error` (default) - Emit `{:error, message, loc}` event
    - `:raise` - Raise an exception
    - `:skip` - Remove invalid characters silently
    - `{:replace, char}` - Replace invalid chars with given char

  ## Examples

      iex> FnXML.Parser.parse("<a>hello</a>")
      ...> |> FnXML.Validate.characters()
      ...> |> Enum.to_list()
      [{:start_document, nil}, {:start_element, "a", [], _}, {:characters, "hello", _}, {:end_element, "a", _}, {:end_document, nil}]

      # Detect invalid character
      iex> FnXML.Parser.parse("<a>\\x00</a>")
      ...> |> FnXML.Validate.characters()
      ...> |> Enum.to_list()
      # Returns error event for NUL character
  """
  def characters(stream, opts \\ []) do
    on_error = Keyword.get(opts, :on_error, :error)

    Stream.flat_map(stream, fn
      {:characters, content, loc} = event ->
        validate_chars_and_emit_or_pass(event, :text, content, loc, on_error)

      # Handle flattened 5-tuple format: {:characters, content, line, ls, pos}
      {:characters, content, line, ls, pos} = event ->
        validate_chars_and_emit_or_pass(event, :text, content, {line, ls, pos}, on_error)

      {:start_element, tag, attrs, loc} = event ->
        validate_attrs_chars_and_emit_or_pass(event, tag, attrs, loc, on_error)

      # Handle flattened 6-tuple format: {:start_element, tag, attrs, line, ls, pos}
      {:start_element, tag, attrs, line, ls, pos} = event ->
        validate_attrs_chars_and_emit_or_pass(event, tag, attrs, {line, ls, pos}, on_error)

      {:cdata, content, loc} = event ->
        validate_chars_and_emit_or_pass(event, :cdata, content, loc, on_error)

      # Handle flattened 5-tuple format for cdata
      {:cdata, content, line, ls, pos} = event ->
        validate_chars_and_emit_or_pass(event, :cdata, content, {line, ls, pos}, on_error)

      {:comment, content, loc} = event ->
        validate_chars_and_emit_or_pass(event, :comment, content, loc, on_error)

      # Handle flattened 5-tuple format for comment
      {:comment, content, line, ls, pos} = event ->
        validate_chars_and_emit_or_pass(event, :comment, content, {line, ls, pos}, on_error)

      {:processing_instruction, target, content, loc} = event ->
        case find_invalid_char(content, 0) do
          nil ->
            [event]

          {char, offset} ->
            handle_char_error(:proc_inst, target, content, loc, char, offset, on_error)
        end

      # Handle flattened 6-tuple format for processing_instruction
      {:processing_instruction, target, content, line, ls, pos} = event ->
        loc = {line, ls, pos}
        case find_invalid_char(content, 0) do
          nil ->
            [event]

          {char, offset} ->
            handle_char_error(:proc_inst, target, content, loc, char, offset, on_error)
        end

      event ->
        [event]
    end)
  end

  # Helper that passes through original event if valid, or handles error
  defp validate_chars_and_emit_or_pass(original_event, type, content, loc, on_error) do
    case find_invalid_char(content, 0) do
      nil ->
        [original_event]

      {char, offset} ->
        handle_char_error(type, nil, content, loc, char, offset, on_error)
    end
  end

  defp validate_attrs_chars_and_emit_or_pass(original_event, tag, attrs, loc, on_error) do
    case find_invalid_attr_char(attrs) do
      nil ->
        [original_event]

      {attr_name, attr_val, char, offset} ->
        handle_attr_char_error(tag, attr_name, attr_val, loc, char, offset, on_error)
    end
  end

  # Find the first invalid XML character in a binary
  defp find_invalid_char(<<>>, _offset), do: nil

  defp find_invalid_char(<<c::utf8, rest::binary>>, offset) do
    if valid_xml_char?(c) do
      find_invalid_char(rest, offset + utf8_byte_size(c))
    else
      {c, offset}
    end
  end

  # Handle invalid UTF-8 sequence (shouldn't happen with valid Elixir strings)
  defp find_invalid_char(<<byte, _rest::binary>>, offset), do: {byte, offset}

  # Valid XML character per W3C Production [2]
  defp valid_xml_char?(c) when c == 0x9 or c == 0xA or c == 0xD, do: true
  defp valid_xml_char?(c) when c >= 0x20 and c <= 0xD7FF, do: true
  defp valid_xml_char?(c) when c >= 0xE000 and c <= 0xFFFD, do: true
  defp valid_xml_char?(c) when c >= 0x10000 and c <= 0x10FFFF, do: true
  defp valid_xml_char?(_), do: false

  defp utf8_byte_size(c) when c < 0x80, do: 1
  defp utf8_byte_size(c) when c < 0x800, do: 2
  defp utf8_byte_size(c) when c < 0x10000, do: 3
  defp utf8_byte_size(_), do: 4

  defp find_invalid_attr_char([]), do: nil

  defp find_invalid_attr_char([{name, value} | rest]) do
    case find_invalid_char(value, 0) do
      nil -> find_invalid_attr_char(rest)
      {char, offset} -> {name, char, offset}
    end
  end

  defp handle_char_error(_type, _extra, _content, loc, char, offset, :error) do
    msg = "Invalid XML character #{format_codepoint(char)} at byte offset #{offset}"
    [{:error, msg, loc}]
  end

  defp handle_char_error(_type, _extra, _content, loc, char, offset, :raise) do
    {line, _, _} = loc
    raise "Invalid XML character #{format_codepoint(char)} at byte offset #{offset}, line #{line}"
  end

  defp handle_char_error(type, nil, content, loc, _char, _offset, :skip) do
    clean = remove_invalid_chars(content)

    event_type =
      case type do
        :text -> :characters
        other -> other
      end

    [{event_type, clean, loc}]
  end

  defp handle_char_error(:proc_inst, target, content, loc, _char, _offset, :skip) do
    clean = remove_invalid_chars(content)
    [{:processing_instruction, target, clean, loc}]
  end

  defp handle_char_error(type, nil, content, loc, _char, _offset, {:replace, replacement}) do
    clean = replace_invalid_chars(content, replacement)

    event_type =
      case type do
        :text -> :characters
        other -> other
      end

    [{event_type, clean, loc}]
  end

  defp handle_char_error(
         :proc_inst,
         target,
         content,
         loc,
         _char,
         _offset,
         {:replace, replacement}
       ) do
    clean = replace_invalid_chars(content, replacement)
    [{:processing_instruction, target, clean, loc}]
  end

  defp handle_attr_char_error(_tag, _attrs, loc, attr_name, char, offset, :error) do
    msg =
      "Invalid XML character #{format_codepoint(char)} in attribute '#{attr_name}' at byte offset #{offset}"

    [{:error, msg, loc}]
  end

  defp handle_attr_char_error(_tag, _attrs, loc, attr_name, char, offset, :raise) do
    {line, _, _} = loc

    raise "Invalid XML character #{format_codepoint(char)} in attribute '#{attr_name}' at byte offset #{offset}, line #{line}"
  end

  defp handle_attr_char_error(tag, attrs, loc, _attr_name, _char, _offset, :skip) do
    clean_attrs = Enum.map(attrs, fn {n, v} -> {n, remove_invalid_chars(v)} end)
    [{:start_element, tag, clean_attrs, loc}]
  end

  defp handle_attr_char_error(
         tag,
         attrs,
         loc,
         _attr_name,
         _char,
         _offset,
         {:replace, replacement}
       ) do
    clean_attrs = Enum.map(attrs, fn {n, v} -> {n, replace_invalid_chars(v, replacement)} end)
    [{:start_element, tag, clean_attrs, loc}]
  end

  defp remove_invalid_chars(binary) do
    for <<c::utf8 <- binary>>, valid_xml_char?(c), into: <<>>, do: <<c::utf8>>
  end

  defp replace_invalid_chars(binary, replacement) do
    for <<c::utf8 <- binary>>, into: <<>> do
      if valid_xml_char?(c), do: <<c::utf8>>, else: replacement
    end
  end

  defp format_codepoint(c) when c < 0x20 do
    "U+#{String.pad_leading(Integer.to_string(c, 16), 4, "0")}"
  end

  defp format_codepoint(c) when c < 0x80 do
    "U+#{String.pad_leading(Integer.to_string(c, 16), 4, "0")} ('#{<<c::utf8>>}')"
  end

  defp format_codepoint(c) do
    "U+#{Integer.to_string(c, 16)}"
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
      {:comment, content, loc} = event ->
        case :binary.match(content, "--") do
          :nomatch ->
            [event]

          {offset, _len} ->
            handle_comment_error(loc, offset, on_error)
        end

      event ->
        [event]
    end)
  end

  defp handle_comment_error(loc, offset, :error) do
    msg = "'--' not allowed in comments (at byte offset #{offset})"
    [{:error, msg, loc}]
  end

  defp handle_comment_error(loc, offset, :raise) do
    {line, _, _} = loc
    raise "'--' not allowed in comments (at byte offset #{offset}), line #{line}"
  end
end
