# FnXML Refactoring Log

## Initial Analysis - 2026-01-09

### Credo Summary
- **Refactoring opportunities**: 203
- **Code readability issues**: 20
- **Software design suggestions**: 12
- **Warnings**: 8
- **Consistency issues**: 1

### Test Coverage: 71.2%

### Largest Files (lines)
| File | Lines |
|------|-------|
| parser_stream.ex | 2174 |
| parser.ex | 2021 |
| validate.ex | 649 |
| dtd/parser.ex | 644 |
| stax/reader.ex | 568 |

---

## Refactoring Plan

We will address issues in subgroups, prioritized by impact:

### Subgroup 1: High Complexity Functions (cyclomatic > 9)
Priority: Critical - these are the hardest to understand and maintain

| Function | File | Complexity |
|----------|------|------------|
| `ncname_start_char?` | namespaces/qname.ex:209 | 29 |
| `parse_doctype` | dtd.ex:135 | 14 |
| `convert_event` | nif_parser.ex:241 | 16 |
| `next_events` | nif_parser.ex:98, 302 | 12 |
| `find_entity_ref` | dtd/entity_resolver.ex:284 | 12 |
| `parse_attr_default` | dtd/parser.ex:607 | 11 |
| `ncname_char?` | namespaces/qname.ex:229 | 10 |
| `extract_declarations` | namespaces/context.ex:283 | 10 |
| `parse_group` | dtd/parser.ex:366 | 10 |

### Subgroup 2: Deeply Nested Functions (depth > 2)
Priority: High - hard to follow control flow

### Subgroup 3: Code Readability Issues
Priority: Medium - predicate naming, formatting

### Subgroup 4: Design Improvements
Priority: Medium - module aliasing

### Subgroup 5: Warnings
Priority: Low - performance suggestions

---

## Subgroup 1: High Complexity Functions

### Starting State
- Tests: 772 passing
- Credo issues: 244 total

---

### Refactoring 1.1: FnXML.NifParser (2026-01-09)

**Target**: `convert_event/2` (complexity 16) and `next_events/2` (complexity 12)

**Changes**:
1. Converted `convert_event/2` from case expression to pattern matching function clauses
2. Extracted helper functions from `next_events/2`:
   - `handle_chunk/4` - processes a chunk after parsing
   - `emit_events/6` - builds and emits parsed events
   - `compute_leftover_state/4` - determines leftover buffer state
   - `retry_with_joined_chunk/4` - joins chunks when element spans boundaries
   - `join_with_previous/3` - helper for chunk joining
   - `handle_eof/1` - handles end-of-stream

**Metrics**:
| Metric | Before | After |
|--------|--------|-------|
| Refactoring issues | 203 | 198 |
| next_events complexity | 12 | ~5 |
| convert_event complexity | 16 | 1 per clause |
| Max nesting depth | 4 | 2 |

**Tests**: 772 passing

---

### Refactoring 1.2: FnXML.DTD.parse_doctype (2026-01-09)

**Target**: `parse_doctype/2` (complexity 14, nesting depth 4)

**Changes**:
1. Replaced nested case expressions with `with` expression
2. Extracted helper functions:
   - `maybe_merge_external_dtd/3` - handles external DTD resolution
   - `resolve_and_merge_external/4` - resolves external DTD content
   - `maybe_parse_internal_subset/2` - handles internal subset parsing

**Metrics**:
| Metric | Before | After |
|--------|--------|-------|
| Refactoring issues | 198 | 196 |
| parse_doctype lines | 42 | 10 |
| Max nesting depth | 4 | 1 |

**Tests**: 772 passing

---

### Refactoring 1.3: FnXML.DTD.EntityResolver.find_entity_ref (2026-01-09)

**Target**: `find_entity_ref/1` (complexity 12, nesting depth 5)

**Changes**:
1. Split into focused helper functions:
   - `parse_entity_at/2` - dispatches to char ref or named entity handling
   - `skip_char_reference/3` - handles character reference skipping
   - `continue_after_char_ref/2` - continues search after char ref
   - `parse_named_entity/3` - parses named entity references
   - `extract_entity_name/4` - extracts and validates entity name

**Metrics**:
| Metric | Before | After |
|--------|--------|-------|
| Refactoring issues | 196 | 194 |
| find_entity_ref lines | 55 | 5 |
| Max nesting depth | 5 | 2 |

**Tests**: 772 passing

---

### Subgroup 1 Summary

**Total refactoring issues reduced**: 203 → 194 (9 issues fixed)

**Functions refactored**:
1. `FnXML.NifParser.convert_event/2` - case to pattern matching
2. `FnXML.NifParser.next_events/2` - extracted 6 helper functions
3. `FnXML.DTD.parse_doctype/2` - with expression + 3 helpers
4. `FnXML.DTD.EntityResolver.find_entity_ref/1` - 5 helper functions

**Remaining high-complexity functions** (inherent to spec, not refactored):
- `ncname_start_char?/1` (complexity 29) - XML NCName character ranges
- `ncname_char?/1` (complexity 10) - XML NCName character ranges

---

## Subgroup 2: Deeply Nested Functions

### Starting State
- Refactoring issues: 194

---

### Refactoring 2.1: FnXML.DTD.EntityResolver.find_known_entity_ref (2026-01-09)

**Target**: `find_known_entity_ref/2` (nesting depth 4)

**Changes**:
1. Extracted helper functions:
   - `resolve_or_skip_entity/5` - handles known vs unknown entity
   - `skip_and_continue/4` - skips unknown entity and continues search
   - `prepend_skipped/3` - prepends skipped content to result

**Metrics**:
| Metric | Before | After |
|--------|--------|-------|
| Refactoring issues | 194 | 193 |
| Max nesting depth | 4 | 2 |

**Tests**: 772 passing

---

### Refactoring 2.2: FnXML.Namespaces.Validator.validate_attribute_name (2026-01-09)

**Target**: `validate_attribute_name/3` (nesting depth 3)

**Changes**:
1. Extracted helper functions:
   - `validate_regular_attribute/3` - validates non-declaration attributes
   - `validate_qname_syntax/2` - validates QName format
   - `validate_attr_prefix/4` - validates prefix declaration
   - `check_prefix_declared/5` - checks if prefix is declared

**Metrics**:
| Metric | Before | After |
|--------|--------|-------|
| Refactoring issues | 193 | 191 |
| Max nesting depth | 3 | 1 |

**Tests**: 772 passing

---

### Subgroup 2 Summary (Partial)

**Refactoring issues reduced**: 194 → 191 (3 issues fixed)

**Functions refactored**:
1. `FnXML.DTD.EntityResolver.find_known_entity_ref/2` - 3 helper functions
2. `FnXML.Namespaces.Validator.validate_attribute_name/3` - 4 helper functions

**Remaining deeply nested functions**:
- `produce_events` in parser_stream.ex (depth 4) - FIXED in session 2
- `process_declarations` in namespaces/validator.ex (depth 3) - FIXED in session 2
- `resolve_attrs` in namespaces/resolver.ex (depth 3)
- `extract_declarations` in namespaces/context.ex (depth 3)
- Others...

---

### Refactoring 2.3: FnXML.ParserStream.produce_events (2026-01-09)

**Target**: `produce_events` (nesting depth 4)

**Changes**:
1. Extracted helper functions:
   - `finish_with_success/0` - handles successful parse completion
   - `finish_with_error/2` - handles parse errors
   - `collect_and_clear_events/0` - collects events from process dictionary
   - `handle_halted_parse/3` - handles halted continuation
   - `continue_with_chunk/2` - continues with next chunk
   - `finish_at_eof/1` - handles end of file

**Metrics**:
| Metric | Before | After |
|--------|--------|-------|
| Max nesting depth | 4 | 2 |

**Tests**: 772 passing

---

### Refactoring 2.4: FnXML.Namespaces.Validator.process_declarations (2026-01-09)

**Target**: `process_declarations/3` (nesting depth 3)

**Changes**:
1. Extracted helper functions:
   - `process_single_declaration/5` - processes one declaration
   - `push_declaration_to_context/6` - pushes declaration with validation

**Metrics**:
| Metric | Before | After |
|--------|--------|-------|
| Max nesting depth | 3 | 2 |

**Tests**: 772 passing

---

### Subgroup 2 Final Summary

**Total refactoring issues**: 194 → 189 (5 issues fixed)

**Functions refactored**:
1. `FnXML.DTD.EntityResolver.find_known_entity_ref/2` - 3 helper functions
2. `FnXML.Namespaces.Validator.validate_attribute_name/3` - 4 helper functions
3. `FnXML.ParserStream.produce_events` - 6 helper functions
4. `FnXML.Namespaces.Validator.process_declarations/3` - 2 helper functions

---

## Subgroup 3: Code Readability Issues

### Starting State
- Code readability issues: 20
- After initial fixes in session 1: 7

---

### Refactoring 3.1: Remaining Readability Issues (2026-01-09)

**Changes**:
1. Fixed alias ordering in test files:
   - `test/stream/simple_form_test.exs` - Reordered aliases alphabetically
   - `test/dom/serializer_test.exs` - Reordered grouped aliases alphabetically

2. Converted strings with multiple quotes to sigils:
   - `lib/fnxml/stax/writer.ex:130` - XML declaration string → `~s` sigil
   - `test/stax/stax_test.exs:103` - XML with attributes → `~s` sigil
   - `test/simple_form_test.exs:18` - XML with attributes → `~s` sigil
   - `test/dom/dom_test.exs:125` - XML with attributes → `~s` sigil
   - `test/dom/dom_test.exs:154` - XML declaration → `~s` sigil

**Metrics**:
| Metric | Before | After |
|--------|--------|-------|
| Code readability issues | 7 | 0 |

**Tests**: 772 passing

---

### Subgroup 3 Summary

**Total code readability issues fixed**: 20 → 0 (all fixed)

**Changes made**:
- Renamed `is_namespace_declaration?` to `namespace_declaration?` (predicate naming)
- Removed parentheses from `id_list()` to `id_list` (no-arg function style)
- Converted explicit try to implicit try in `resolve_text` (idiomatic Elixir)
- Fixed alias ordering in multiple test files
- Converted escaped quote strings to sigils

---

## Subgroup 5: Warnings

### Starting State
- Warnings: 8
- Consistency issues: 1

---

### Refactoring 5.1: Length Warnings (2026-01-09)

**Target**: All `length(list) >= 1` and `length(list) > 0` patterns

**Changes**:
Replaced inefficient `length/1` comparisons with empty list checks:
- `test/sax/sax_test.exs:186,194,211` - `length(x) >= 1` → `x != []`
- `test/stream/validate_test.exs:259,263` - `length(x) >= 1` → `x != []`
- `test/parser_test.exs:195` - `length(x) >= 1` → `x != []`
- `test/namespaces_test.exs:143` - `length(x) > 0` → `x != []`
- `test/fnxml_test.exs:25` - `length(x) > 0` → `x != []`

**Metrics**:
| Metric | Before | After |
|--------|--------|-------|
| Warnings | 8 | 0 |

**Tests**: 772 passing

---

### Refactoring 5.2: Consistency Issue (2026-01-09)

**Target**: Parameter pattern match ordering

**Changes**:
- `lib/stream.ex:139` - Changed `str = ""` to `"" = str` (pattern before variable)

**Metrics**:
| Metric | Before | After |
|--------|--------|-------|
| Consistency issues | 1 | 0 |

**Tests**: 772 passing

---

### Subgroup 5 Summary

**Total warnings fixed**: 8 → 0 (all fixed)
**Total consistency issues fixed**: 1 → 0 (all fixed)

---

## Subgroup 4: Design Improvements

### Starting State
- Design suggestions: 12

---

### Refactoring 4.1: Module Aliasing (2026-01-09)

**Target**: Nested module references that should be aliased

**Changes**:
1. `lib/namespaces/resolver.ex` - Added `QName` to alias, replaced `FnXML.Namespaces.QName.prefix` with `QName.prefix`
2. `test/namespaces_test.exs` - Added `alias FnXML.Namespaces.Context`, replaced 4 occurrences
3. `test/namespaces/resolver_test.exs` - Added `Context` to alias, replaced 1 occurrence
4. `test/dtd_test.exs` - Added `alias FnXML.DTD.EntityResolver`, replaced 2 occurrences
5. `test/dom/dom_test.exs` - Added `Builder` to alias, replaced 3 occurrences

**Metrics**:
| Metric | Before | After |
|--------|--------|-------|
| Design suggestions | 12 | 0 |

**Tests**: 772 passing

---

### Subgroup 4 Summary

**Total design suggestions fixed**: 12 → 0 (all fixed)

---

## Final Summary

### Overall Progress

| Category | Initial | Final | Resolved |
|----------|---------|-------|----------|
| Refactoring opportunities | 203 | 189 | 14 |
| Code readability issues | 20 | 0 | 20 |
| Software design suggestions | 12 | 0 | 12 |
| Warnings | 8 | 0 | 8 |
| Consistency issues | 1 | 0 | 1 |
| **Total** | **244** | **189** | **55** |

### Tests
- All 772 tests passing throughout refactoring
- No regressions introduced

### Key Improvements
1. **Reduced code complexity** - Multiple high-complexity functions broken into smaller, focused helpers
2. **Reduced nesting depth** - Deep nesting eliminated through function extraction
3. **Improved readability** - Idiomatic Elixir patterns, proper naming conventions
4. **Better organization** - Module aliasing for cleaner code
5. **Performance hints addressed** - Removed expensive `length/1` checks

### Remaining Work
- 189 refactoring opportunities remain (mostly high-arity functions in parser_stream.ex and parser.ex)
- These are core parser functions with complex state passing that would require significant architectural changes to reduce arity

