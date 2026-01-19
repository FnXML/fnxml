# Plan: Migrate fnxsd and fnsoap to use FnXML.XsTypes

## Overview

Replace the independent type implementations in fnxsd and fnsoap with the unified `FnXML.XsTypes` module from fnxml.

### Benefits
- Single source of truth for XSD type handling
- Consistent validation, parsing, and encoding across all projects
- Full facet support
- Type hierarchy queries
- Code generation support
- Better maintainability

---

## Current State

### fnxsd Types (`lib/fnxsd/types.ex`)
- ~1000 lines of type validation code
- 44 built-in types supported
- Basic facet validation
- No parsing to Elixir types (validation only)
- No encoding back to strings

### fnsoap Types (`lib/fnsoap/service/types.ex`)
- ~400 lines of type handling
- 11 simple types (`:string`, `:integer`, etc.)
- XSD name mapping (`to_xsd_type/1`)
- Basic encode/decode for SOAP serialization

### FnXML.XsTypes (target)
- Complete XSD type system
- 44+ types with full hierarchy
- Validation, parsing, encoding
- Facet support
- Type inference
- Code generation helpers

---

## Migration Plan

### Phase 1: fnxsd Migration

#### Step 1.1: Add FnXML dependency
```elixir
# fnxsd/mix.exs
defp deps do
  [
    {:fnxml, path: "../fnxml"},  # or hex version
    # ... existing deps
  ]
end
```

#### Step 1.2: Replace `lib/fnxsd/types.ex` validation

**Current API:**
```elixir
FnXSD.Types.validate(value, type_name, schema_types)
FnXSD.Types.builtin_type?(name)
FnXSD.Types.builtin_types()
```

**New API (wrapper):**
```elixir
defmodule FnXSD.Types do
  @moduledoc "XSD type validation - delegates to FnXML.XsTypes"

  alias FnXML.XsTypes

  # Delegate builtin type queries
  defdelegate builtin_type?(name), to: XsTypes
  defdelegate builtin_types(), to: XsTypes

  @doc "Validate value against type with optional schema-defined types"
  def validate(value, type_name, schema_types \\ %{})

  def validate(value, type_name, schema_types) when is_binary(type_name) do
    local_name = normalize_type_name(type_name)

    cond do
      # Built-in types
      XsTypes.builtin_type?(local_name) ->
        XsTypes.validate(value, local_name)

      # Schema-defined types
      Map.has_key?(schema_types, type_name) ->
        validate_schema_type(value, Map.get(schema_types, type_name), schema_types)

      Map.has_key?(schema_types, local_name) ->
        validate_schema_type(value, Map.get(schema_types, local_name), schema_types)

      true ->
        {:error, "Unknown type: #{type_name}"}
    end
  end

  def validate(value, %SimpleType{} = type, schema_types) do
    validate_schema_type(value, type, schema_types)
  end

  # Schema-defined type validation with facets
  defp validate_schema_type(value, %SimpleType{base: base, facets: facets, variety: variety}, schema_types) do
    case variety do
      :atomic -> validate_atomic(value, base, facets, schema_types)
      :list -> validate_list(value, type, schema_types)
      :union -> validate_union(value, type, schema_types)
      nil -> validate_atomic(value, base, facets, schema_types)
    end
  end

  defp validate_atomic(value, base, facets, schema_types) do
    # First validate against base type
    case validate(value, base, schema_types) do
      :ok ->
        # Then validate facets using FnXML.XsTypes
        primitive = XsTypes.primitive_base(normalize_type_name(base))
        XsTypes.validate_with_facets(value, primitive, convert_facets(facets))
      error ->
        error
    end
  end

  # Convert FnXSD.Model.Facet to FnXML.XsTypes facet format
  defp convert_facets(facets) do
    Enum.map(facets, fn
      %Facet{type: type, value: value} -> {type, value}
      {type, value} -> {type, value}
    end)
  end

  defp normalize_type_name(name) when is_binary(name) do
    name
    |> String.replace(~r/^(xs:|xsd:)/, "")
    |> String.to_atom()
  end
  defp normalize_type_name(name) when is_atom(name), do: name
end
```

#### Step 1.3: Update `lib/fnxsd/validator.ex`

Replace inline type validation calls:
```elixir
# Before
defp validate_simple_content(value, type_name, schema) do
  FnXSD.Types.validate(value, type_name, schema.types)
end

# After (no change needed if Types wrapper is correct)
```

#### Step 1.4: Files to modify in fnxsd

| File | Changes |
|------|---------|
| `mix.exs` | Add fnxml dependency |
| `lib/fnxsd/types.ex` | Replace with thin wrapper (~100 lines vs ~1000) |
| `lib/fnxsd/validator.ex` | Minor updates for error format |
| `lib/fnxsd/resolver.ex` | Update `builtin_type?` calls |
| `test/types_test.exs` | Update test expectations |

#### Step 1.5: Testing
```bash
cd fnxsd
mix deps.get
mix test
```

---

### Phase 2: fnsoap Migration

#### Step 2.1: Ensure FnXML dependency
```elixir
# fnsoap/mix.exs - likely already has fnxml via fnxsd
```

#### Step 2.2: Replace `lib/fnsoap/service/types.ex`

**Current functions to migrate:**

| Current | Replacement |
|---------|-------------|
| `encode/2` | `FnXML.XsTypes.encode/2` |
| `decode/2` | `FnXML.XsTypes.parse/2` |
| `to_xsd_type/1` | Keep (maps Elixir atoms to XSD names) |
| `validate_type/2` | `FnXML.XsTypes.validate/2` |

**New wrapper:**
```elixir
defmodule FnSOAP.Service.Types do
  @moduledoc "SOAP type handling - delegates to FnXML.XsTypes"

  alias FnXML.XsTypes

  # Keep the Elixir atom -> XSD name mapping
  @spec to_xsd_type(atom()) :: String.t()
  def to_xsd_type(:string), do: "string"
  def to_xsd_type(:integer), do: "integer"
  def to_xsd_type(:int), do: "int"
  def to_xsd_type(:float), do: "double"
  def to_xsd_type(:double), do: "double"
  def to_xsd_type(:decimal), do: "decimal"
  def to_xsd_type(:boolean), do: "boolean"
  def to_xsd_type(:date), do: "date"
  def to_xsd_type(:datetime), do: "dateTime"
  def to_xsd_type(:time), do: "time"
  def to_xsd_type(:binary), do: "base64Binary"
  def to_xsd_type({:optional, type}), do: to_xsd_type(type)
  def to_xsd_type({:list, _type}), do: "array"
  def to_xsd_type({:enum, _values}), do: "string"
  def to_xsd_type(_), do: "string"

  # Map fnsoap atoms to XsTypes atoms
  defp to_xs_type(:datetime), do: :dateTime
  defp to_xs_type(:binary), do: :base64Binary
  defp to_xs_type(type), do: type

  @doc "Encode Elixir value to XML string"
  def encode(value, type) do
    XsTypes.encode(value, to_xs_type(type))
  end

  @doc "Decode XML string to Elixir value"
  def decode(value, type) when is_binary(value) do
    XsTypes.parse(value, to_xs_type(type))
  end

  @doc "Validate string value against type"
  def validate(value, type) when is_binary(value) do
    XsTypes.validate(value, to_xs_type(type))
  end

  # Complex type handling stays in fnsoap
  def encode(value, {:list, item_type}) do
    # ... existing list handling
  end

  def decode(value, {:complex, fields}) do
    # ... existing complex type handling
  end
end
```

#### Step 2.3: Update encoding modules

Files using type encoding/decoding:
- `lib/fnsoap/encoding/literal.ex`
- `lib/fnsoap/encoding/rpc.ex`
- `lib/fnsoap/encoding/complex.ex`
- `lib/fnsoap/envelope.ex`

**Pattern to replace:**
```elixir
# Before (if custom encoding exists)
defp encode_value(value, :integer), do: Integer.to_string(value)
defp encode_value(value, :boolean), do: to_string(value)

# After
defp encode_value(value, type) do
  case FnSOAP.Service.Types.encode(value, type) do
    {:ok, str} -> str
    {:error, _} -> to_string(value)  # fallback
  end
end
```

#### Step 2.4: Update WSDL generator

`lib/fnsoap/wsdl/generator.ex` and `lib/fnsoap/wsdl/type_registry.ex`:
- Keep XSD generation (already uses string templates)
- Can optionally use `XsTypes.type_uri/1` for namespace

#### Step 2.5: Files to modify in fnsoap

| File | Changes |
|------|---------|
| `lib/fnsoap/service/types.ex` | Replace with wrapper |
| `lib/fnsoap/encoding/literal.ex` | Use new encode/decode |
| `lib/fnsoap/encoding/rpc.ex` | Use new encode/decode |
| `lib/fnsoap/encoding/complex.ex` | Use new encode/decode |
| `lib/fnsoap/wsdl/type_registry.ex` | Minor updates |
| `test/service/types_test.exs` | Update test expectations |
| `test/encoding/*_test.exs` | Update test expectations |

#### Step 2.6: Testing
```bash
cd fnsoap
mix deps.get
mix test
```

---

### Phase 3: Integration Testing

#### Step 3.1: Cross-project tests
```bash
# Run all tests
cd fnxml && mix test
cd ../fnxsd && mix test
cd ../fnsoap && mix test
```

#### Step 3.2: End-to-end validation
- Parse XSD schema with fnxsd
- Generate SOAP client with fnsoap
- Validate request/response types flow correctly

---

## Detailed File Changes

### fnxsd Changes

#### `lib/fnxsd/types.ex` (rewrite)
- Remove: ~900 lines of validation functions
- Keep: `validate/3` wrapper, schema type handling
- Add: Delegation to `FnXML.XsTypes`
- Result: ~150 lines

#### `lib/fnxsd/validator.ex` (minor)
- Update error tuple handling if format differs
- Lines affected: ~10-20

#### `lib/fnxsd/resolver.ex` (minor)
- Update `builtin_type?` calls
- Lines affected: ~5

### fnsoap Changes

#### `lib/fnsoap/service/types.ex` (partial rewrite)
- Remove: Custom encode/decode for simple types (~200 lines)
- Keep: `to_xsd_type/1`, complex type handling
- Add: Delegation to `FnXML.XsTypes`
- Result: ~200 lines (down from ~400)

#### `lib/fnsoap/encoding/*.ex` (updates)
- Use new `Types.encode/2` and `Types.decode/2`
- Lines affected per file: ~20-50

---

## Error Format Alignment

### Current fnxsd errors:
```elixir
{:error, "Invalid boolean value: 'abc'"}
```

### FnXML.XsTypes errors:
```elixir
{:error, {:invalid_value, :boolean, "abc"}}
```

**Migration strategy:** Update error handlers or add translation layer:
```elixir
defp translate_error({:error, {:invalid_value, type, value}}) do
  {:error, "Invalid #{type} value: '#{value}'"}
end
defp translate_error({:error, {:facet_violation, facet, details}}) do
  {:error, "Facet #{facet} violated: #{inspect(details)}"}
end
defp translate_error(error), do: error
```

---

## Rollback Strategy

If issues arise:
1. Keep old `types.ex` as `types_legacy.ex`
2. Add feature flag to switch implementations
3. Gradually migrate with parallel validation

---

## Timeline Estimate

| Phase | Effort |
|-------|--------|
| Phase 1: fnxsd | 2-3 hours |
| Phase 2: fnsoap | 3-4 hours |
| Phase 3: Testing | 1-2 hours |
| **Total** | **6-9 hours** |

---

## Checklist

### fnxsd
- [ ] Add fnxml dependency to mix.exs
- [ ] Rewrite lib/fnxsd/types.ex as wrapper
- [ ] Update lib/fnxsd/validator.ex error handling
- [ ] Update lib/fnxsd/resolver.ex
- [ ] Update tests
- [ ] Run full test suite
- [ ] Verify 141 tests pass

### fnsoap
- [ ] Verify fnxml dependency available
- [ ] Rewrite lib/fnsoap/service/types.ex
- [ ] Update lib/fnsoap/encoding/literal.ex
- [ ] Update lib/fnsoap/encoding/rpc.ex
- [ ] Update lib/fnsoap/encoding/complex.ex
- [ ] Update lib/fnsoap/wsdl/type_registry.ex
- [ ] Update tests
- [ ] Run full test suite
- [ ] Verify 863 tests pass

### Integration
- [ ] Run fnxml tests (411 pass)
- [ ] Run fnxpath tests (411 pass)
- [ ] Run fnxsd tests (141 pass)
- [ ] Run fnsoap tests (863 pass)
- [ ] End-to-end validation test
