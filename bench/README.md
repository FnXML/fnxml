# FnXML Benchmark Results

Comprehensive benchmarks comparing FnXML parsers against other Elixir/Erlang XML libraries.

## Environment

- **OS**: macOS (Darwin 25.1.0)
- **CPU**: Apple M1
- **Cores**: 8
- **Memory**: 16 GB
- **Elixir**: 1.19.3
- **Erlang**: 28.1.1
- **JIT**: Enabled

## Test Data

| File | Size | Description |
|------|------|-------------|
| small.xml | 757 B | Simple catalog with 2 books |
| medium.xml | 249 KB | 500 items with nested elements |
| large.xml | 1.3 MB | 2500 items with nested elements |

## Parsers Compared

| Parser | Type | Description |
|--------|------|-------------|
| **fast_ex_blk** | Block | FnXML optimized CPS parser (fastest) |
| **ex_blk_parser** | Block | FnXML standard CPS parser |
| **fast_ex_blk_stream** | Stream | FnXML streaming with 64KB chunks |
| **ex_blk_stream** | Stream | FnXML streaming with 64KB chunks |
| **saxy_string** | SAX | External, highly optimized callback parser |
| **saxy_stream** | SAX | External, streaming 64KB chunks |
| **erlsom** | SAX/DOM | External Erlang library, simple_form mode |
| **xmerl** | DOM | Erlang stdlib, full DOM tree |

---

## Parse Speed Comparison (Medium File - 249 KB)

| Parser | Speed (ips) | vs fast_ex_blk | Memory |
|--------|-------------|----------------|--------|
| **fast_ex_blk** | **565** | 1.00x | 2.02 MB |
| saxy_string | 351 | 1.61x slower | 3.89 MB |
| ex_blk_parser | 319 | 1.77x slower | 4.03 MB |
| saxy_stream | 284 | 1.99x slower | 4.03 MB |
| fast_ex_blk_stream | 252 | 2.24x slower | 1.86 MB |
| ex_blk_stream | 180 | 3.13x slower | 4.04 MB |
| erlsom | 154 | 3.67x slower | 17.98 MB |
| xmerl | 55 | 10.35x slower | 86.92 MB |

---

## Memory Usage Comparison (Medium File)

| Parser | Memory | vs fast_ex_blk |
|--------|--------|----------------|
| **fast_ex_blk_stream** | **1.86 MB** | 0.92x (lowest) |
| **fast_ex_blk** | **2.02 MB** | 1.00x |
| saxy_string | 3.89 MB | 1.92x more |
| ex_blk_parser | 4.03 MB | 1.99x more |
| saxy_stream | 4.03 MB | 1.99x more |
| ex_blk_stream | 4.04 MB | 2.00x more |
| erlsom | 17.98 MB | 8.88x more |
| xmerl | 86.92 MB | 42.94x more |

---

## Summary: FnXML vs Competition

| Metric | vs Saxy (string) | vs Saxy (stream) | vs erlsom | vs xmerl |
|--------|------------------|------------------|-----------|----------|
| **Speed** | 1.61x faster | 1.99x faster | 3.67x faster | 10.35x faster |
| **Memory** | 1.92x less | 1.99x less | 8.88x less | 42.94x less |

---

## Architecture

### CPS Recursive Descent Parser

```
XML Input -> Binary Pattern Match -> Emit Event -> Continue
             (single pass)          (accumulate)   (tail-call)
```

Key optimizations:
- **Continuation-passing style**: Tail-call optimized, minimal stack usage
- **Single binary reference**: Uses `binary_part/3` for zero-copy content extraction
- **Position tracking**: Integer offsets instead of creating sub-binary "rest"
- **Guard-based dispatch**: Character classes use guards for efficient branching
- **Mini-block streaming**: Elements spanning chunk boundaries handled efficiently

### Why FnXML is Fast

1. **Zero-copy parsing**: Content extracted via `binary_part/3` references original binary
2. **No intermediate AST**: Events emitted directly without building tree structure
3. **Minimal allocations**: Only event tuples are allocated during parsing
4. **Tail-call optimization**: CPS enables true tail recursion throughout
5. **BEAM-optimized patterns**: Multi-byte patterns like `<!--` matched directly

---

## When to Use Each Parser

| Use Case | Recommended |
|----------|-------------|
| Maximum speed, full document | `FnXML.Legacy.FastExBlkParser.parse(xml)` |
| Minimum memory, large files | `FnXML.Legacy.FastExBlkParser.stream(chunks)` |
| Auto NIF/Elixir selection | `FnXML.Parser.parse(xml)` |
| File streaming | `File.stream!(path, [], 65536) \|> FnXML.Parser.parse()` |

---

## Running Benchmarks

```bash
# Quick benchmark (medium file only)
mix run bench/parse_bench.exs --quick

# Full benchmark (all file sizes)
mix run bench/parse_bench.exs

# Comprehensive comparison (all parsers including legacy)
mix run bench/all_parsers_bench.exs

# By file size
mix run bench/all_parsers_bench.exs --by-size

# Edition 5 variants only
mix run bench/all_parsers_bench.exs --ed5
```

**Note**: The comprehensive benchmark now includes `fnxml_parser_orig` (FnXML.Legacy.ParserOrig) which is a dead code candidate being evaluated for removal.

## Regenerating Test Data

```bash
mix run bench/generate_data.exs
```
