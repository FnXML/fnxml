defmodule FnXML.DTD.Validator do
  @moduledoc """
  DTD validation for XML event streams.

  This module validates DTD constraints that cannot be checked during parsing,
  including namespace-related constraints on entity and notation names.

  ## Usage

      FnXML.Parser.parse(xml)
      |> FnXML.DTD.Validator.validate()
      |> Enum.to_list()

  ## Validations

  - **Namespace Constraints**: Entity and notation names cannot contain colons
  - **Attribute Normalization**: Normalizes attribute values based on DTD types

  ## Options

  - `:on_error` - How to handle errors:
    - `:emit` (default) - Emit error events in stream
    - `:raise` - Raise an exception
    - `:skip` - Skip validation silently

  - `:normalize_attributes` - Apply DTD-based attribute normalization (default: true)
  """

  alias FnXML.DTD
  alias FnXML.DTD.Model

  # Tokenized attribute types that require normalization
  @tokenized_types [:nmtoken, :nmtokens, :id, :idref, :idrefs, :entity, :entities]

  @doc """
  Validate DTD constraints in an XML event stream.

  Extracts the DTD from the stream, validates namespace constraints,
  and optionally normalizes attribute values based on DTD type declarations.
  """
  @spec validate(Enumerable.t(), keyword()) :: Enumerable.t()
  def validate(stream, opts \\ []) do
    on_error = Keyword.get(opts, :on_error, :emit)
    normalize = Keyword.get(opts, :normalize_attributes, true)

    Stream.transform(stream, nil, fn
      # DTD - 5-tuple from parser
      {:dtd, content, line, ls, pos} = event, _model ->
        loc = {line, ls, pos}

        case DTD.parse_doctype(content) do
          {:ok, model} ->
            errors = validate_dtd_constraints(model, loc, on_error)
            {errors ++ [event], model}

          {:error, _} ->
            {[event], nil}
        end

      # DTD - 3-tuple normalized
      {:dtd, content, loc} = event, _model ->
        case DTD.parse_doctype(content) do
          {:ok, model} ->
            errors = validate_dtd_constraints(model, loc, on_error)
            {errors ++ [event], model}

          {:error, _} ->
            {[event], nil}
        end

      # Start element - 6-tuple from parser
      {:start_element, tag, attrs, line, ls, pos}, model when model != nil and normalize ->
        {[normalize_open_event_6(tag, attrs, line, ls, pos, model)], model}

      # Start element - 4-tuple normalized
      {:start_element, tag, attrs, loc}, model when model != nil and normalize ->
        {[normalize_open_event(tag, attrs, loc, model)], model}

      event, model ->
        {[event], model}
    end)
  end

  @doc """
  Validate namespace constraints in a DTD model.

  Returns a list of error events for any violations found.
  """
  @spec validate_dtd_constraints(Model.t(), term(), atom()) :: list()
  def validate_dtd_constraints(%Model{} = model, loc, on_error) do
    entity_errors = validate_entity_names(model.entities, loc, on_error)
    notation_errors = validate_notation_names(model.notations, loc, on_error)

    entity_errors ++ notation_errors
  end

  @doc """
  Normalize an open event's attributes based on DTD type declarations.

  Per XML spec, tokenized attribute types (NMTOKEN, ID, IDREF, etc.) have
  leading/trailing whitespace stripped and internal whitespace collapsed.
  """
  @spec normalize_open_event(String.t(), list(), term(), Model.t()) :: term()
  def normalize_open_event(tag, attrs, loc, model) do
    normalized_attrs = normalize_attrs(tag, attrs, model)
    {:start_element, tag, normalized_attrs, loc}
  end

  # Normalize for 6-tuple format from parser
  defp normalize_open_event_6(tag, attrs, line, ls, pos, model) do
    normalized_attrs = normalize_attrs(tag, attrs, model)
    {:start_element, tag, normalized_attrs, line, ls, pos}
  end

  defp normalize_attrs(tag, attrs, model) do
    element_name = extract_local_name(tag)
    attr_decls = Map.get(model.attributes, element_name, [])
    attr_types = Map.new(attr_decls, fn decl -> {decl.name, decl.type} end)

    Enum.map(attrs, fn {name, value} ->
      case Map.get(attr_types, name) do
        type when type in @tokenized_types ->
          {name, normalize_token_value(value)}

        _ ->
          {name, value}
      end
    end)
  end

  # Validate entity names don't contain colons (namespace constraint)
  defp validate_entity_names(entities, loc, on_error) do
    entities
    |> Enum.filter(fn {name, _} -> String.contains?(name, ":") end)
    |> Enum.flat_map(fn {name, _} ->
      make_error({:colon_in_entity_name, name}, "<!ENTITY #{name}>", loc, on_error)
    end)
  end

  # Validate notation names don't contain colons (namespace constraint)
  defp validate_notation_names(notations, loc, on_error) do
    notations
    |> Enum.filter(fn {name, _} -> String.contains?(name, ":") end)
    |> Enum.flat_map(fn {name, _} ->
      make_error({:colon_in_notation_name, name}, "<!NOTATION #{name}>", loc, on_error)
    end)
  end

  # Create error based on on_error setting
  defp make_error(reason, context, loc, :emit) do
    [{:dtd_error, reason, context, loc}]
  end

  defp make_error(reason, context, _loc, :raise) do
    raise "DTD validation error: #{inspect(reason)} in #{context}"
  end

  defp make_error(_reason, _context, _loc, :skip), do: []

  # Extract local name from potentially prefixed tag
  defp extract_local_name(tag) do
    case String.split(tag, ":", parts: 2) do
      [_, local] -> local
      [local] -> local
    end
  end

  # Normalize token values: trim and collapse whitespace
  defp normalize_token_value(value) do
    value
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end
end
