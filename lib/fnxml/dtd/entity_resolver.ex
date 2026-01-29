defmodule FnXML.DTD.EntityResolver do
  @moduledoc """
  DTD-aware entity resolution using composition with `FnXML.Event.Transform.Entities`.

  This module extracts entity definitions from a `FnXML.DTD.Model` and delegates
  the actual resolution to `FnXML.Event.Transform.Entities`, adding DTD-specific features
  like security limits and external entity handling.

  ## Usage

      {:ok, dtd_model} = FnXML.DTD.Parser.parse(dtd_string)

      FnXML.Parser.parse(xml)
      |> FnXML.DTD.EntityResolver.resolve(dtd_model)
      |> Enum.to_list()

  ## Security

  To prevent entity expansion attacks (billion laughs, quadratic blowup),
  this module enforces limits on:

  - `:max_expansion_depth` - Maximum nesting of entity references (default: 10)
  - `:max_total_expansion` - Maximum total characters from entity expansion (default: 1_000_000)

  ## Options

  - `:max_expansion_depth` - Limit recursive entity expansion (default: 10)
  - `:max_total_expansion` - Limit total expanded content size (default: 1_000_000)
  - `:external_resolver` - Function to fetch external entities: `(system_id, public_id) -> {:ok, content} | {:error, reason}`
  - `:on_unknown` - How to handle unknown entities (passed to FnXML.Event.Transform.Entities)

  ## Examples

      # Basic DTD entity resolution
      iex> dtd = "<!ENTITY greeting \\"Hello, World!\\">"
      iex> {:ok, model} = FnXML.DTD.Parser.parse(dtd)
      iex> entities = FnXML.DTD.EntityResolver.extract_entities(model)
      iex> entities["greeting"]
      "Hello, World!"

  """

  alias FnXML.DTD.Model
  alias FnXML.Event.Transform.Entities

  @default_max_depth 10
  @default_max_expansion 1_000_000

  @doc deprecated: "Use FnXML.DTD.resolve(stream, model, opts) instead"
  @doc """
  Resolve entities in the stream using definitions from the DTD model.

  Extracts entity definitions from the model, expands any nested entity
  references within the definitions (respecting security limits), then
  delegates to `FnXML.Event.Transform.Entities.resolve/2`.

  ## Options

  - `:max_expansion_depth` - Maximum nesting depth (default: 10)
  - `:max_total_expansion` - Maximum expanded size (default: 1_000_000)
  - `:external_resolver` - Function to resolve external entities
  - `:on_unknown` - `:raise` | `:emit` | `:keep` | `:remove` (default: :raise)

  ## Deprecated

  Use `FnXML.DTD.resolve(stream, model, opts)` instead. This function is kept
  for backward compatibility but will be removed in a future version.
  """
  def resolve(stream, %Model{} = model, opts \\ []) do
    case extract_and_expand_entities(model, opts) do
      {:ok, entities} ->
        entity_opts = [
          entities: entities,
          on_unknown: Keyword.get(opts, :on_unknown, :raise)
        ]

        Entities.resolve(stream, entity_opts)

      {:error, reason} ->
        # Emit error as first event, then continue stream
        Stream.concat([{:error, reason, nil}], stream)
    end
  end

  @doc """
  Extract entity definitions from a DTD model as a map.

  Returns a map of entity name => replacement value suitable for
  passing to `FnXML.Event.Transform.Entities.resolve/2`.

  Only internal entities are included. External entities are skipped
  unless an `:external_resolver` is provided.
  """
  @spec extract_entities(Model.t()) :: %{String.t() => String.t()}
  def extract_entities(%Model{} = model) do
    model.entities
    |> Enum.reduce(%{}, fn {name, definition}, acc ->
      case definition do
        {:internal, value} ->
          Map.put(acc, name, value)

        # External entities skipped without resolver
        {:external, _system_id, _public_id} ->
          acc

        {:external_unparsed, _system_id, _public_id, _notation} ->
          acc
      end
    end)
  end

  @doc """
  Extract and expand entity definitions, resolving nested references.

  This handles cases where one entity references another:

      <!ENTITY a "hello">
      <!ENTITY b "&a; world">

  After expansion, `b` becomes `"hello world"`.

  Returns `{:ok, entities_map}` or `{:error, reason}` if limits are exceeded.
  """
  @spec extract_and_expand_entities(Model.t(), keyword()) ::
          {:ok, %{String.t() => String.t()}} | {:error, String.t()}
  def extract_and_expand_entities(%Model{} = model, opts \\ []) do
    max_depth = Keyword.get(opts, :max_expansion_depth, @default_max_depth)
    max_expansion = Keyword.get(opts, :max_total_expansion, @default_max_expansion)
    external_resolver = Keyword.get(opts, :external_resolver)

    # First extract raw entities
    raw_entities = extract_raw_entities(model, external_resolver)

    # Then expand nested references
    expand_all_entities(raw_entities, max_depth, max_expansion)
  end

  @doc """
  Expand a single entity value, resolving any nested entity references.

  Used internally and exposed for testing.
  """
  @spec expand_entity(
          String.t(),
          %{String.t() => String.t()},
          non_neg_integer(),
          non_neg_integer()
        ) ::
          {:ok, String.t(), non_neg_integer()} | {:error, String.t()}
  def expand_entity(value, entities, max_depth, max_expansion) do
    expand_entity_impl(value, entities, 0, max_depth, 0, max_expansion)
  end

  # ============================================================================
  # Private Implementation
  # ============================================================================

  # Extract raw entity values (without expansion)
  defp extract_raw_entities(%Model{} = model, external_resolver) do
    model.entities
    |> Enum.reduce(%{}, fn {name, definition}, acc ->
      case resolve_definition(definition, external_resolver) do
        {:ok, value} -> Map.put(acc, name, value)
        :skip -> acc
      end
    end)
  end

  defp resolve_definition({:internal, value}, _resolver), do: {:ok, value}

  defp resolve_definition({:external, system_id, public_id}, resolver)
       when is_function(resolver) do
    case resolver.(system_id, public_id) do
      {:ok, content} -> {:ok, content}
      {:error, _} -> :skip
    end
  end

  defp resolve_definition({:external, _system_id, _public_id}, nil), do: :skip
  defp resolve_definition({:external_unparsed, _, _, _}, _), do: :skip

  # Expand all entities, handling nested references
  defp expand_all_entities(entities, max_depth, max_expansion) do
    # Multiple passes to handle forward references
    expand_pass(entities, entities, max_depth, max_expansion, 0)
  end

  defp expand_pass(entities, original, max_depth, max_expansion, pass) when pass < max_depth do
    result =
      Enum.reduce_while(entities, {:ok, %{}, 0}, fn {name, value}, {:ok, acc, total} ->
        case expand_entity_impl(value, original, 0, max_depth, total, max_expansion) do
          {:ok, expanded, new_total} ->
            {:cont, {:ok, Map.put(acc, name, expanded), new_total}}

          {:error, _} = err ->
            {:halt, err}
        end
      end)

    case result do
      {:ok, expanded, _total} ->
        # Check if anything changed
        if expanded == entities do
          {:ok, expanded}
        else
          # Another pass needed for forward references
          expand_pass(expanded, expanded, max_depth, max_expansion, pass + 1)
        end

      {:error, _} = err ->
        err
    end
  end

  defp expand_pass(entities, _original, _max_depth, _max_expansion, _pass) do
    # Max passes reached, return as-is
    {:ok, entities}
  end

  # Recursive entity expansion with limits
  defp expand_entity_impl(value, _entities, depth, max_depth, _total, _max_expansion)
       when depth > max_depth do
    {:error,
     "Entity expansion depth limit exceeded (max: #{max_depth}). Possible recursive entity definition in: #{String.slice(value, 0, 50)}"}
  end

  defp expand_entity_impl(_value, _entities, _depth, _max_depth, total, max_expansion)
       when total > max_expansion do
    {:error,
     "Entity expansion size limit exceeded (max: #{max_expansion} bytes). Possible entity expansion attack."}
  end

  defp expand_entity_impl(value, entities, depth, max_depth, total, max_expansion) do
    # Find entity references in value, skipping unknown ones
    case find_known_entity_ref(value, entities) do
      nil ->
        # No more known references
        {:ok, value, total + byte_size(value)}

      {before, _entity_name, after_ref, replacement} ->
        # Expand the replacement recursively
        case expand_entity_impl(replacement, entities, depth + 1, max_depth, total, max_expansion) do
          {:ok, expanded_replacement, new_total} ->
            new_value = before <> expanded_replacement <> after_ref
            expand_entity_impl(new_value, entities, depth, max_depth, new_total, max_expansion)

          {:error, _} = err ->
            err
        end
    end
  end

  # Find first KNOWN entity reference in a string
  # Returns {before, entity_name, after, replacement} or nil
  # Only returns entities that exist in the entities map
  defp find_known_entity_ref(string, entities) do
    case find_entity_ref(string) do
      nil ->
        nil

      {before, entity_name, after_ref} ->
        case Map.get(entities, entity_name) do
          nil ->
            # Unknown entity - skip it and look for next one
            # +2 for & and ;
            skip_len = byte_size(before) + byte_size(entity_name) + 2

            if skip_len < byte_size(string) do
              rest = binary_part(string, skip_len, byte_size(string) - skip_len)

              case find_known_entity_ref(rest, entities) do
                nil ->
                  nil

                {before2, name2, after2, replacement2} ->
                  {binary_part(string, 0, skip_len) <> before2, name2, after2, replacement2}
              end
            else
              nil
            end

          replacement ->
            {before, entity_name, after_ref, replacement}
        end
    end
  end

  # Find first entity reference in a string
  # Returns {before, entity_name, after} or nil
  defp find_entity_ref(string) do
    case :binary.match(string, "&") do
      :nomatch ->
        nil

      {start, 1} ->
        after_amp = binary_part(string, start + 1, byte_size(string) - start - 1)

        # Skip character references (&#...) - those are handled by FnXML.Entities
        if String.starts_with?(after_amp, "#") do
          # Look for next entity ref after this one
          case :binary.match(after_amp, ";") do
            :nomatch ->
              nil

            {semi_pos, 1} ->
              skip_to = start + 1 + semi_pos + 1

              if skip_to < byte_size(string) do
                rest = binary_part(string, skip_to, byte_size(string) - skip_to)

                case find_entity_ref(rest) do
                  nil ->
                    nil

                  {before2, name, after2} ->
                    {binary_part(string, 0, skip_to) <> before2, name, after2}
                end
              else
                nil
              end
          end
        else
          case :binary.match(after_amp, ";") do
            :nomatch ->
              nil

            {semi_pos, 1} ->
              entity_name = binary_part(after_amp, 0, semi_pos)

              # Validate it looks like an entity name (not empty, valid chars)
              if valid_entity_name?(entity_name) do
                before = binary_part(string, 0, start)

                after_ref =
                  binary_part(after_amp, semi_pos + 1, byte_size(after_amp) - semi_pos - 1)

                {before, entity_name, after_ref}
              else
                nil
              end
          end
        end
    end
  end

  # Basic validation of entity name
  defp valid_entity_name?(""), do: false

  defp valid_entity_name?(name) do
    name
    |> String.to_charlist()
    |> Enum.all?(fn c ->
      (c >= ?a and c <= ?z) or (c >= ?A and c <= ?Z) or
        (c >= ?0 and c <= ?9) or c == ?_ or c == ?- or c == ?.
    end)
  end
end
