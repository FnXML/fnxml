# Plan: Update fnxsd and fnsoap for New FnXML Event Format

## Background

FnXML event format changed from nested location tuples to flat format:

| Event Type | Old Format | New Format |
|------------|------------|------------|
| start_element | `{:start_element, tag, attrs, {line, ls, pos}}` (4 elements) | `{:start_element, tag, attrs, line, ls, pos}` (6 elements) |
| end_element | `{:end_element, tag, {line, ls, pos}}` (3 elements) | `{:end_element, tag, line, ls, pos}` (5 elements) |
| characters | `{:characters, content, {line, ls, pos}}` (3 elements) | `{:characters, content, line, ls, pos}` (5 elements) |
| space | `{:space, content, {line, ls, pos}}` (3 elements) | `{:space, content, line, ls, pos}` (5 elements) |
| comment | `{:comment, content, {line, ls, pos}}` (3 elements) | `{:comment, content, line, ls, pos}` (5 elements) |
| cdata | `{:cdata, content, {line, ls, pos}}` (3 elements) | `{:cdata, content, line, ls, pos}` (5 elements) |
| prolog | `{:prolog, name, attrs, {line, ls, pos}}` (4 elements) | `{:prolog, name, attrs, line, ls, pos}` (6 elements) |
| processing_instruction | `{:processing_instruction, name, content, {line, ls, pos}}` (4 elements) | `{:processing_instruction, name, content, line, ls, pos}` (6 elements) |
| error | `{:error, type, msg, {line, ls, pos}}` (4 elements) | `{:error, type, msg, line, ls, pos}` (6 elements) |
| dtd | `{:dtd, content, {line, ls, pos}}` (3 elements) | `{:dtd, content, line, ls, pos}` (5 elements) |

---

## fnxsd Project Status

### Current State: ✅ Already Updated

The fnxsd project has already been updated to use the new flat format:

| File | Status | Notes |
|------|--------|-------|
| `lib/fnxsd/parser.ex` | ✅ Updated | Uses 6/5 element patterns |
| `lib/fnxsd/validator.ex` | ✅ Updated | Uses 6/5 element patterns |

### Action Items for fnxsd

1. **Run tests to verify compatibility**
   ```bash
   cd /Users/dco/Projects/elixir/xml/fnxsd
   mix test
   ```

2. **Fix any test failures** - Test files may still use old format assertions

3. **Check test files for old patterns**:
   - `test/fnxsd_test.exs`
   - `test/parser_test.exs`
   - `test/validator_test.exs`
   - `test/schema_test.exs`
   - Other test files

---

## fnsoap Project Status

### Current State: ⚠️ Mixed (Needs Cleanup)

Most files are updated, but `addressing.ex` has defensive multi-format handling that should be cleaned up.

| File | Status | Notes |
|------|--------|-------|
| `lib/fnsoap/envelope.ex` | ✅ Updated | Uses flat format throughout |
| `lib/fnsoap/encoding/rpc.ex` | ✅ Updated | Uses flat format |
| `lib/fnsoap/security/signature.ex` | ✅ Safe | Uses generic `elem()` access |
| `lib/fnsoap/security/username_token.ex` | ✅ Safe | Uses generic `elem()` access |
| `lib/fnsoap/addressing.ex` | ⚠️ **Mixed** | Has both old and new patterns |

### Action Items for fnsoap

#### Step 1: Fix addressing.ex (lines 348-377)

Current code has multi-format handling:
```elixir
# New format (keep these)
{:start_element, name, attrs, _, _, _}     # 6 elements
{:end_element, name, _, _, _}              # 5 elements
{:characters, text, _, _, _}               # 5 elements

# Old format (remove these)
{:start_element, name, attrs, _}           # 4 elements - REMOVE
{:end_element, name, _}                    # 3 elements - REMOVE
{:end_element, name}                       # 2 elements - REMOVE
{:characters, text, _}                     # 3 elements - REMOVE
{:characters, text}                        # 2 elements - REMOVE
```

**Action**: Remove the old format patterns, keep only new flat format.

#### Step 2: Run tests
```bash
cd /Users/dco/Projects/elixir/xml/fnsoap
mix test
```

#### Step 3: Fix test files as needed

Test files that may need updating:
- `test/fnsoap/envelope_test.exs`
- `test/fnsoap/addressing_test.exs`
- `test/fnsoap/encoding/*_test.exs`
- `test/fnsoap/wsdl/*_test.exs`
- Other test files with event assertions

---

## Implementation Steps

### Phase 1: fnxsd Verification

1. [ ] Run fnxsd tests
2. [ ] Identify failing tests
3. [ ] Update test assertions to new format
4. [ ] Verify all tests pass

### Phase 2: fnsoap Cleanup

1. [ ] Clean up `lib/fnsoap/addressing.ex` - remove old format patterns
2. [ ] Run fnsoap tests
3. [ ] Identify failing tests
4. [ ] Update test assertions to new format
5. [ ] Verify all tests pass

### Phase 3: Final Verification

1. [ ] Run full test suite for fnxsd
2. [ ] Run full test suite for fnsoap
3. [ ] Check for any remaining warnings
4. [ ] Update any documentation if needed

---

## Pattern Search Commands

To find remaining old-format patterns:

```bash
# Find 4-element start_element (old format)
grep -rn "{:start_element, .*, .*, _}" lib/ test/

# Find 3-element end_element (old format)
grep -rn "{:end_element, .*, _}" lib/ test/

# Find 3-element characters (old format)
grep -rn "{:characters, .*, _}" lib/ test/
```

To find new-format patterns (verification):

```bash
# Find 6-element start_element (new format)
grep -rn "{:start_element, .*, .*, .*, .*, .*}" lib/ test/

# Find 5-element end_element (new format)
grep -rn "{:end_element, .*, .*, .*, .*}" lib/ test/
```

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Test failures | Medium | Run tests incrementally, fix as found |
| Missing pattern updates | Low | Use grep to find all occurrences |
| Runtime errors | Medium | Comprehensive test coverage |

---

## Estimated Effort

- **fnxsd**: Low - Already updated, just test verification
- **fnsoap**: Medium - One file cleanup + test updates
- **Total**: 1-2 hours of work
