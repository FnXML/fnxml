defmodule FnXML.Validate.Namespaces do
  @moduledoc """
  Namespace constraint validation for XML Namespaces.

  This module validates namespace constraints from the W3C spec:

  - **NSC: Prefix Declared** - All prefixes must be bound
  - **NSC: No Prefix Undeclaring** - Cannot bind prefix to empty string
  - **NSC: Reserved Prefixes** - xml/xmlns rules
  - **NSC: Attributes Unique** - No duplicate expanded attribute names
  - **QName validation** - Names must match productions

  ## Usage

      FnXML.Parser.parse(xml)
      |> FnXML.Validate.Namespaces.validate()
      |> Enum.to_list()

  Errors are emitted as `{:ns_error, reason, name, loc}` events.
  """

  alias FnXML.Namespaces.{Context, QName}

  @xml_namespace "http://www.w3.org/XML/1998/namespace"
  @xmlns_namespace "http://www.w3.org/2000/xmlns/"

  @doc """
  Validate namespace constraints in a stream of FnXML events.

  Returns a stream that includes error events for any violations.
  """
  @spec validate(Enumerable.t(), keyword()) :: Enumerable.t()
  def validate(stream, opts \\ []) do
    Stream.transform(stream, Context.new(), fn event, ctx ->
      {events, new_ctx} = validate_event(event, ctx, opts)
      {events, new_ctx}
    end)
  end

  @doc """
  Validate a single event.

  Returns `{events, new_context}` where events includes the original
  event plus any error events.
  """
  @spec validate_event(term(), Context.t(), keyword()) :: {list(term()), Context.t()}
  def validate_event(event, ctx, opts \\ [])

  # Element open with 4-tuple location (normalized)
  def validate_event({:start_element, tag, attrs, loc} = event, ctx, _opts) do
    errors = []

    # Validate tag is valid QName
    errors =
      if not QName.valid_qname?(tag) do
        [{:ns_error, {:invalid_qname, tag}, tag, loc} | errors]
      else
        errors
      end

    # Extract and validate namespace declarations
    {decl_errors, new_ctx} = process_declarations(attrs, ctx, loc)
    errors = decl_errors ++ errors

    # Validate element prefix is declared
    errors =
      case QName.parse(tag) do
        {nil, _} ->
          errors

        {prefix, _} when prefix in ["xml", "xmlns"] ->
          if prefix == "xmlns" do
            [{:ns_error, {:xmlns_element, tag}, tag, loc} | errors]
          else
            errors
          end

        {prefix, _} ->
          case Context.resolve_prefix(new_ctx, prefix) do
            {:ok, _} ->
              errors

            {:error, :undeclared_prefix} ->
              [{:ns_error, {:undeclared_prefix, prefix}, tag, loc} | errors]
          end
      end

    # Validate attributes
    attr_errors = validate_attributes(attrs, new_ctx, loc)
    errors = attr_errors ++ errors

    if errors == [] do
      {[event], new_ctx}
    else
      {Enum.reverse(errors) ++ [event], new_ctx}
    end
  end

  # Element open with 6-tuple format (from parser)
  def validate_event({:start_element, tag, attrs, line, ls, pos} = event, ctx, _opts) do
    loc = {line, ls, pos}
    errors = []

    # Validate tag is valid QName
    errors =
      if not QName.valid_qname?(tag) do
        [{:ns_error, {:invalid_qname, tag}, tag, loc} | errors]
      else
        errors
      end

    # Extract and validate namespace declarations
    {decl_errors, new_ctx} = process_declarations(attrs, ctx, loc)
    errors = decl_errors ++ errors

    # Validate element prefix is declared
    errors =
      case QName.parse(tag) do
        {nil, _} ->
          errors

        {prefix, _} when prefix in ["xml", "xmlns"] ->
          if prefix == "xmlns" do
            [{:ns_error, {:xmlns_element, tag}, tag, loc} | errors]
          else
            errors
          end

        {prefix, _} ->
          case Context.resolve_prefix(new_ctx, prefix) do
            {:ok, _} ->
              errors

            {:error, :undeclared_prefix} ->
              [{:ns_error, {:undeclared_prefix, prefix}, tag, loc} | errors]
          end
      end

    # Validate attributes
    attr_errors = validate_attributes(attrs, new_ctx, loc)
    errors = attr_errors ++ errors

    if errors == [] do
      {[event], new_ctx}
    else
      {Enum.reverse(errors) ++ [event], new_ctx}
    end
  end

  # Element close with 3-tuple location (normalized)
  def validate_event({:end_element, tag, loc} = event, ctx, _opts) do
    errors = []

    # Validate tag matches QName
    errors =
      if not QName.valid_qname?(tag) do
        [{:ns_error, {:invalid_qname, tag}, tag, loc} | errors]
      else
        errors
      end

    new_ctx = Context.pop(ctx)

    if errors == [] do
      {[event], new_ctx}
    else
      {Enum.reverse(errors) ++ [event], new_ctx}
    end
  end

  # Element close with 5-tuple format (from parser)
  def validate_event({:end_element, tag, line, ls, pos} = event, ctx, _opts) do
    loc = {line, ls, pos}
    errors = []

    # Validate tag matches QName
    errors =
      if not QName.valid_qname?(tag) do
        [{:ns_error, {:invalid_qname, tag}, tag, loc} | errors]
      else
        errors
      end

    new_ctx = Context.pop(ctx)

    if errors == [] do
      {[event], new_ctx}
    else
      {Enum.reverse(errors) ++ [event], new_ctx}
    end
  end

  # Element close without location
  def validate_event({:end_element, tag} = event, ctx, _opts) do
    errors =
      if not QName.valid_qname?(tag) do
        [{:ns_error, {:invalid_qname, tag}, tag, nil}]
      else
        []
      end

    new_ctx = Context.pop(ctx)

    if errors == [] do
      {[event], new_ctx}
    else
      {Enum.reverse(errors) ++ [event], new_ctx}
    end
  end

  # PI events - target must be NCName (no colons)
  def validate_event({:pi, target, _data, loc} = event, ctx, _opts) do
    if String.contains?(target, ":") do
      {[{:ns_error, {:colon_in_pi_target, target}, target, loc}, event], ctx}
    else
      {[event], ctx}
    end
  end

  def validate_event({:pi, target, _data} = event, ctx, _opts) do
    if String.contains?(target, ":") do
      {[{:ns_error, {:colon_in_pi_target, target}, target, nil}, event], ctx}
    else
      {[event], ctx}
    end
  end

  # FnXML uses :processing_instruction - 6-tuple from parser
  def validate_event({:processing_instruction, target, _data, line, ls, pos} = event, ctx, _opts) do
    loc = {line, ls, pos}

    if String.contains?(target, ":") do
      {[{:ns_error, {:colon_in_pi_target, target}, target, loc}, event], ctx}
    else
      {[event], ctx}
    end
  end

  # 4-tuple normalized format
  def validate_event({:processing_instruction, target, _data, loc} = event, ctx, _opts) do
    if String.contains?(target, ":") do
      {[{:ns_error, {:colon_in_pi_target, target}, target, loc}, event], ctx}
    else
      {[event], ctx}
    end
  end

  # 3-tuple legacy format
  def validate_event({:processing_instruction, target, _data} = event, ctx, _opts) do
    if String.contains?(target, ":") do
      {[{:ns_error, {:colon_in_pi_target, target}, target, nil}, event], ctx}
    else
      {[event], ctx}
    end
  end

  # XML prolog - detect XML version for NS 1.1 support
  # 6-tuple from parser
  def validate_event({:prolog, "xml", attrs, _line, _ls, _pos} = event, ctx, _opts) do
    version =
      Enum.find_value(attrs, "1.0", fn
        {"version", v} -> v
        _ -> nil
      end)

    new_ctx = Context.set_xml_version(ctx, version)
    {[event], new_ctx}
  end

  # 4-tuple normalized format
  def validate_event({:prolog, "xml", attrs, _loc} = event, ctx, _opts) do
    version =
      Enum.find_value(attrs, "1.0", fn
        {"version", v} -> v
        _ -> nil
      end)

    new_ctx = Context.set_xml_version(ctx, version)
    {[event], new_ctx}
  end

  # Document start/end pass through unchanged
  def validate_event({:start_document, _} = event, ctx, _opts) do
    {[event], ctx}
  end

  def validate_event({:end_document, _} = event, ctx, _opts) do
    {[event], ctx}
  end

  # Other events pass through unchanged
  def validate_event(event, ctx, _opts) do
    {[event], ctx}
  end

  # Process namespace declarations and return errors + new context
  defp process_declarations(attrs, ctx, loc) do
    Enum.reduce(attrs, {[], ctx}, fn {name, value}, {errors, current_ctx} ->
      case QName.namespace_declaration?(name) do
        {:default, _} ->
          # Default namespace declaration
          # Check reserved namespaces cannot be default
          new_errors = validate_default_namespace(value, loc)

          case Context.push(current_ctx, [{name, value}]) do
            {:ok, new_ctx, _} ->
              {new_errors ++ errors, new_ctx}

            {:error, reason} ->
              {[{:ns_error, reason, name, loc} | new_errors ++ errors], current_ctx}
          end

        {:prefix, prefix} ->
          # Prefixed namespace declaration - validate
          new_errors = validate_prefix_declaration(prefix, value, loc, current_ctx)

          case Context.push(current_ctx, [{name, value}]) do
            {:ok, new_ctx, _} ->
              {new_errors ++ errors, new_ctx}

            {:error, reason} ->
              {[{:ns_error, reason, name, loc} | new_errors ++ errors], current_ctx}
          end

        false ->
          {errors, current_ctx}
      end
    end)
  end

  # Validate a default namespace declaration
  # The xml and xmlns namespaces cannot be used as the default namespace
  defp validate_default_namespace(value, loc) do
    cond do
      value == @xml_namespace ->
        [{:ns_error, {:xml_namespace_as_default, value}, "xmlns", loc}]

      value == @xmlns_namespace ->
        [{:ns_error, {:xmlns_namespace_as_default, value}, "xmlns", loc}]

      true ->
        []
    end
  end

  # Validate a prefix declaration
  defp validate_prefix_declaration(prefix, value, loc, ctx) do
    errors = []

    # NSC: No Prefix Undeclaring (but allowed in XML 1.1 / NS 1.1)
    errors =
      if value == "" and Context.xml_version(ctx) != "1.1" do
        [{:ns_error, {:empty_prefix_binding, prefix}, "xmlns:#{prefix}", loc} | errors]
      else
        errors
      end

    # NSC: Reserved Prefixes - xml
    errors =
      cond do
        prefix == "xml" and value != @xml_namespace ->
          [{:ns_error, {:xml_prefix_wrong_uri, value}, "xmlns:xml", loc} | errors]

        prefix != "xml" and value == @xml_namespace ->
          [{:ns_error, {:xml_namespace_wrong_prefix, prefix}, "xmlns:#{prefix}", loc} | errors]

        true ->
          errors
      end

    # NSC: Reserved Prefixes - xmlns
    errors =
      cond do
        prefix == "xmlns" ->
          [{:ns_error, {:xmlns_prefix_declared, value}, "xmlns:xmlns", loc} | errors]

        value == @xmlns_namespace ->
          [{:ns_error, {:xmlns_namespace_bound, prefix}, "xmlns:#{prefix}", loc} | errors]

        true ->
          errors
      end

    errors
  end

  # Validate all attributes in an element
  defp validate_attributes(attrs, ctx, loc) do
    # First validate individual attributes
    individual_errors =
      attrs
      |> Enum.flat_map(fn {name, _value} ->
        validate_attribute_name(name, ctx, loc)
      end)

    # Then check for duplicate expanded names
    uniqueness_errors = check_attribute_uniqueness(attrs, ctx, loc)

    individual_errors ++ uniqueness_errors
  end

  # Validate a single attribute name
  defp validate_attribute_name(name, ctx, loc) do
    errors = []

    # Skip namespace declarations
    case QName.namespace_declaration?(name) do
      false ->
        # Must be valid QName
        errors =
          if not QName.valid_qname?(name) do
            [{:ns_error, {:invalid_qname, name}, name, loc} | errors]
          else
            errors
          end

        # If prefixed, prefix must be declared
        case QName.parse(name) do
          {nil, _} ->
            errors

          {prefix, _} when prefix in ["xml", "xmlns"] ->
            errors

          {prefix, _} ->
            case Context.resolve_prefix(ctx, prefix) do
              {:ok, _} ->
                errors

              {:error, :undeclared_prefix} ->
                [{:ns_error, {:undeclared_prefix, prefix}, name, loc} | errors]
            end
        end

      _ ->
        # Namespace declaration - validated separately
        errors
    end
  end

  # NSC: Attributes Unique - check for duplicate expanded names
  defp check_attribute_uniqueness(attrs, ctx, loc) do
    # Get expanded names for all non-declaration attributes
    expanded =
      attrs
      |> Enum.reject(fn {name, _} ->
        QName.namespace_declaration?(name) != false
      end)
      |> Enum.map(fn {name, _value} ->
        case Context.expand_attribute(ctx, name) do
          {:ok, expanded} -> {name, expanded}
          {:error, _} -> {name, {:error, name}}
        end
      end)

    # Find duplicates
    expanded
    |> Enum.group_by(fn {_name, exp} -> exp end)
    |> Enum.filter(fn {_exp, names} -> length(names) > 1 end)
    |> Enum.flat_map(fn {{uri, local}, names} ->
      original_names = Enum.map(names, &elem(&1, 0))
      [{:ns_error, {:duplicate_attribute, {uri, local}, original_names}, hd(original_names), loc}]
    end)
  end
end
