# Plan: Fix Remaining 57 Conformance Test Failures

## Current Status
- **Pass Rate**: 96.5% (1570/1627)
- **Failures**: 57 tests
- **Target**: 99%+ pass rate

## Phase 1: Attribute Value Validation (8 tests)

### Problem
Parser allows `<` character in attribute values, which is forbidden by XML spec.

### Tests Fixed
- `ibm-not-wf-P41-ibm41n10.xml` through `ibm-not-wf-P41-ibm41n14.xml` (4 tests)
- `not-wf-sa-074`, `not-wf-sa-103`, `not-wf-sa-132` (3 tests)
- `rmt-e2e-61` (1 test)

### Implementation

**File:** `lib/fnxml/validate.ex`

Add attribute value validation to check for forbidden characters:

```elixir
def attribute_values(stream) do
  Stream.flat_map(stream, fn
    {:start_element, name, attrs, line, ls, pos} = event ->
      case validate_attr_values(attrs) do
        :ok -> [event]
        {:error, attr_name, reason} ->
          [{:error, :invalid_attr_value, "Invalid character in attribute '#{attr_name}': #{reason}", line, ls, pos}, event]
      end
    event -> [event]
  end)
end

defp validate_attr_values(attrs) do
  Enum.find_value(attrs, :ok, fn {name, value} ->
    cond do
      String.contains?(value, "<") ->
        {:error, name, "'<' not allowed in attribute value"}
      true ->
        nil
    end
  end)
end
```

**File:** `lib/mix/tasks/conformance.xml.ex`

Add to pipeline:
```elixir
|> FnXML.Validate.attribute_values()
```

### Verification
```bash
mix conformance.xml --edition 5 --filter "P41-ibm41n1\|sa-074\|sa-103\|sa-132"
```

---

## Phase 2: Nested Content Model Parsing (3 tests)

### Problem
Content model `(a,(b|c))` fails because inner group `(b|c)` is treated as element name.

### Tests Fixed
- `ibm-valid-P47-ibm47v01.xml`
- `ibm-valid-P51-ibm51v01.xml`
- `ibm-invalid-P51-ibm51i03.xml`

### Implementation

**File:** `lib/dtd/parser.ex`

Fix `parse_group_items/2` to recursively parse nested groups:

```elixir
defp parse_group_items(inner, separator) do
  inner
  |> split_respecting_parens(separator)
  |> Enum.map(&String.trim/1)
  |> Enum.map(&parse_item/1)
  |> check_for_errors()
end

defp parse_item(item) do
  item = String.trim(item)

  cond do
    # Nested group - must parse recursively
    String.starts_with?(item, "(") ->
      case parse_group(item) do
        {:ok, model} -> model
        {:error, _} = err -> err
      end

    String.ends_with?(item, "?") ->
      name = String.trim_trailing(item, "?")
      validate_content_element_name(name, {:optional, name})

    # ... existing cases
  end
end
```

### Verification
```bash
mix conformance.xml --edition 5 --filter "P47-ibm47v01\|P51"
```

---

## Phase 3: ATTLIST Declaration Validation (5 tests)

### Problem
Parser doesn't detect malformed ATTLIST declarations.

### Tests Fixed
- `ibm-not-wf-P58-ibm58n06.xml`, `ibm-not-wf-P58-ibm58n08.xml`
- `ibm-not-wf-P59-ibm59n04.xml`
- `ibm-not-wf-P60-ibm60n05.xml`, `ibm-not-wf-P60-ibm60n07.xml`

### Implementation

**File:** `lib/dtd/parser.ex`

Enhance ATTLIST validation:

```elixir
defp parse_attlist(decl) do
  # Add validation for:
  # - Missing attribute type
  # - Invalid default declaration syntax
  # - NOTATION without enumeration
end
```

Examine each failing test to identify specific validation gaps.

### Verification
```bash
mix conformance.xml --edition 5 --filter "P58\|P59\|P60"
```

---

## Phase 4: Entity Declaration Validation (6 tests)

### Problem
Parser doesn't detect malformed entity declarations.

### Tests Fixed
- `ibm-not-wf-P68-ibm68n07.xml`
- `ibm-not-wf-P69-ibm69n06.xml`, `ibm-not-wf-P69-ibm69n07.xml`
- `ibm-not-wf-P75-ibm75n07.xml`, `ibm-not-wf-P75-ibm75n09.xml`
- `ibm-not-wf-P77-ibm77n02.xml`

### Implementation

**File:** `lib/dtd/parser.ex`

Enhance entity declaration validation:

```elixir
defp parse_entity(decl, opts) do
  # Add validation for:
  # - Missing quotes around entity value
  # - Invalid SYSTEM/PUBLIC identifier syntax
  # - NDATA on parameter entities (not allowed)
end
```

### Verification
```bash
mix conformance.xml --edition 5 --filter "P68\|P69\|P75\|P77"
```

---

## Phase 5: Content Model Syntax Validation (5 tests)

### Problem
Parser doesn't detect all content model syntax errors.

### Tests Fixed
- `ibm-not-wf-P47-ibm47n06.xml`
- `ibm-not-wf-P48-ibm48n07.xml`
- `ibm-not-wf-P49-ibm49n03.xml`
- `ibm-not-wf-P50-ibm50n06.xml`
- `sgml10`

### Implementation

**File:** `lib/dtd/parser.ex`

Add content model validation:

```elixir
defp validate_content_model_syntax(spec) do
  # Add checks for:
  # - Invalid characters in element names
  # - Empty groups ()
  # - Mismatched parentheses
  # - Invalid occurrence indicators
end
```

### Verification
```bash
mix conformance.xml --edition 5 --filter "P47n\|P48\|P49\|P50\|sgml10"
```

---

## Phase 6: Parameter Entity Expansion (15 tests)

### Problem
Entities defined via parameter entity expansion appear undefined.

### Tests Fixed
- `v-pe02`, `not-sa03`
- `ibm-valid-P09-ibm09v05.xml`
- `ibm-valid-P10-ibm10v03.xml`, `ibm-valid-P10-ibm10v04.xml`
- `rmt-e2e-18`, `rmt-e3e-06i`
- External DTD tests with PE references

### Implementation

**File:** `lib/fnxml/parameter_entities.ex` (new)

```elixir
defmodule FnXML.ParameterEntities do
  @moduledoc """
  Parameter entity expansion for DTD processing.
  """

  @doc """
  Expand parameter entity references in DTD content.
  """
  def expand(content, pe_definitions) do
    Regex.replace(~r/%([a-zA-Z_][\w.-]*);/, content, fn _, name ->
      Map.get(pe_definitions, name, "%#{name};")
    end)
  end

  @doc """
  Extract parameter entity definitions from DTD content.
  """
  def extract_definitions(content) do
    ~r/<!ENTITY\s+%\s+(\S+)\s+["']([^"']*)["']\s*>/
    |> Regex.scan(content)
    |> Enum.map(fn [_, name, value] -> {name, value} end)
    |> Map.new()
  end
end
```

**File:** `lib/dtd/parser.ex`

Integrate PE expansion:

```elixir
def parse(dtd_string, opts \\ []) do
  # First pass: extract PE definitions
  pe_defs = ParameterEntities.extract_definitions(dtd_string)

  # Second pass: expand PE references
  expanded = ParameterEntities.expand(dtd_string, pe_defs)

  # Third pass: parse declarations
  parse_declarations(expanded, opts)
end
```

### Verification
```bash
mix conformance.xml --edition 5 --filter "pe02\|not-sa03\|P09-ibm09v05\|P10-ibm10v0"
```

---

## Phase 7: External DTD Integration (10 tests)

### Problem
External DTDs with attribute defaults not being applied.

### Tests Fixed
- `attr05`, `attr06`
- `inv-dtd01`, `inv-dtd03`
- `cond01`, `cond02`
- `not-wf-not-sa-002`, `not-wf-not-sa-008`, `not-wf-not-sa-009`
- `ibm-not-wf-p28a-ibm28an01.xml`

### Implementation

**File:** `lib/fnxml/external_resolver.ex`

Enhance to handle PE expansion in external DTDs:

```elixir
def parse_external_dtd(content, opts \\ []) do
  # Expand parameter entities first
  pe_defs = ParameterEntities.extract_definitions(content)
  expanded = ParameterEntities.expand(content, pe_defs)

  # Process conditional sections
  case process_conditional_sections(expanded) do
    {:ok, processed} ->
      FnXML.DTD.Parser.parse(processed, opts)
    {:error, _} = err ->
      err
  end
end
```

**File:** `lib/mix/tasks/conformance.xml.ex`

Enable external DTD validation for all test types (not just not-wf):

```elixir
external_dtd_error =
  if test.entities != "none" do
    validate_external_dtd(events, test.uri, edition)
  else
    nil
  end
```

### Verification
```bash
mix conformance.xml --edition 5 --filter "attr0[56]\|inv-dtd0\|cond0\|not-sa-00"
```

---

## Phase 8: Errata & Edge Cases (5 tests)

### Tests
- `rmt-e2e-50` - XML 1.1 version test
- `rmt-e3e-12`, `rmt-e3e-13` - Errata edge cases
- `x-rmt-008b`, `x-ibm-1-0.5-valid-P05-ibm05v05.xml`

### Implementation
Investigate each test individually to determine required fixes.

---

## Phase 9: Namespace Edge Cases (4 tests)

### Tests
- `rmt-ns10-011`, `rmt-ns10-012` - Entity expansion in namespace URIs
- `rmt-ns11-001`, `rmt-ns11-002` - Namespaces 1.1 with special characters

### Implementation

For NS 1.0 tests, requires entity expansion before namespace comparison.
For NS 1.1 tests, requires Namespaces 1.1 support (different undeclaring rules).

---

## Implementation Order & Expected Results

| Phase | Tests Fixed | Cumulative Pass Rate |
|-------|-------------|---------------------|
| Current | - | 96.5% |
| Phase 1 | +8 | 97.0% |
| Phase 2 | +3 | 97.2% |
| Phase 3 | +5 | 97.5% |
| Phase 4 | +6 | 97.9% |
| Phase 5 | +5 | 98.2% |
| Phase 6 | +15 | 99.1% |
| Phase 7 | +10 | 99.7% |
| Phase 8 | +3 | 99.9% |
| Phase 9 | +2 | 99.9%+ |

## Files to Create/Modify

### New Files
- `lib/fnxml/parameter_entities.ex` - PE expansion

### Modified Files
- `lib/fnxml/validate.ex` - Attribute value validation
- `lib/dtd/parser.ex` - DTD parsing improvements
- `lib/fnxml/external_resolver.ex` - PE expansion in external DTDs
- `lib/mix/tasks/conformance.xml.ex` - Pipeline integration

## Verification Commands

```bash
# After each phase
mix test
mix conformance.xml --edition 5

# Specific category
mix conformance.xml --edition 5 --set "ibm-not-wf"
mix conformance.xml --edition 5 --set "xmltest"
```

## Risk Assessment

| Phase | Complexity | Risk |
|-------|------------|------|
| 1 | Low | Low - Simple validation |
| 2 | Medium | Low - Localized fix |
| 3-5 | Medium | Medium - DTD parser changes |
| 6-7 | High | Medium - PE expansion is complex |
| 8-9 | Variable | Low - Individual fixes |

## Recommended Approach

1. **Start with Phases 1-2** - Quick wins, low risk
2. **Then Phases 3-5** - DTD validation improvements
3. **Finally Phases 6-7** - PE expansion (most complex, most impact)
4. **Phases 8-9** - Edge cases as time permits
