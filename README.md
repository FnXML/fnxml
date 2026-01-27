# FnXML

A functional XML library for Elixir with streaming support and three standard API paradigms: DOM, SAX, and StAX.

## Architecture

```
 ┌─────────────────────────────────────────────────────────────────┐
 │                        High-Level APIs                          │
 ├─────────────────┬─────────────────────┬─────────────────────────┤
 │  FnXML.API.DOM  │  FnXML.API.SAX      │  FnXML.API.StAX         │
 │  (Tree)         │  (Push Callbacks)   │  (Pull Cursor)          │
 │  O(n) memory    │  O(1) memory        │  O(1) memory            │
 ├─────────────────┴─────────────────────┴─────────────────────────┤
 │                    FnXML.Security                               │
 │     C14N (Canonicalization) │ Signatures │ Encryption           │
 ├─────────────────────────────────────────────────────────────────┤
 │                     FnXML.Transform.Stream                                │
 │            Event stream transformations & formatting            │
 ├─────────────────────────────────────────────────────────────────┤
 │  FnXML.Namespaces          │  FnXML.Transform.Stream.SimpleForm           │
 │  Namespace resolution      │  Saxy compatibility                │
 ├─────────────────────────────────────────────────────────────────┤
 │                      FnXML.Parser                               │
 │      Auto-selects: Zig NIF (>60KB) or ExBlkParser (<60KB)       │
 ├─────────────────────────────────────────────────────────────────┤
 │  FnXML.Legacy.ExBlkParser  │  FnXML.Legacy.FastExBlkParser      │
 │  Pure Elixir, streaming    │  Optimized variant (legacy)        │
 └─────────────────────────────────────────────────────────────────┘
```

The parser uses CPS (continuation-passing style) recursive descent for efficient tail-call optimization and minimal memory usage.

## Quick Start

```elixir
# Parse XML to DOM tree
doc = FnXML.API.DOM.parse("<root><child id=\"1\">Hello</child></root>")
doc.root.tag  # => "root"

# SAX callback-based parsing
defmodule CountHandler do
  use FnXML.API.SAX.Handler
  def start_element(_uri, _local, _qname, _attrs, count), do: {:ok, count + 1}
end
{:ok, 2} = FnXML.API.SAX.parse("<root><child/></root>", CountHandler, 0)

# StAX pull-based parsing
reader = FnXML.API.StAX.Reader.new("<root attr=\"val\"/>")
reader = FnXML.API.StAX.Reader.next(reader)
FnXML.API.StAX.Reader.local_name(reader)  # => "root"
FnXML.API.StAX.Reader.attribute_value(reader, nil, "attr")  # => "val"
```

## Installation

```elixir
def deps do
  [{:fnxml, "~> 0.1.0"}]
end
```

## APIs

### DOM (Document Object Model)

Build an in-memory tree representation. Best for small-to-medium documents where you need random access.

```elixir
# Parse
doc = FnXML.API.DOM.parse("<root><child id=\"1\">text</child></root>")

# Navigate
doc.root.tag                                    # => "root"
doc.root.children                               # => [%Element{...}]
FnXML.API.DOM.Element.get_attribute(elem, "id")     # => "1"

# Serialize
FnXML.API.DOM.to_string(doc)                        # => "<root>..."
FnXML.API.DOM.to_string(doc, pretty: true)          # => formatted XML

# Build programmatically
alias FnXML.API.DOM.Element
elem = Element.new("div", [{"class", "container"}], ["Hello"])
```

### SAX (Simple API for XML)

Push-based event callbacks. Best for large documents where you only need specific data.

```elixir
defmodule MyHandler do
  use FnXML.API.SAX.Handler

  @impl true
  def start_element(_uri, local_name, _qname, _attrs, state) do
    {:ok, [local_name | state]}
  end

  @impl true
  def characters(text, state) do
    {:ok, Map.update(state, :text, text, &(&1 <> text))}
  end

  @impl true
  def end_document(state) do
    {:ok, Enum.reverse(state)}
  end
end

{:ok, result} = FnXML.API.SAX.parse(xml, MyHandler, [])
```

**Callbacks:** `start_document/1`, `end_document/1`, `start_element/5`, `end_element/4`, `characters/2`

**Return values:** `{:ok, state}`, `{:halt, state}` (stop early), `{:error, reason}`

### StAX (Streaming API for XML)

Pull-based cursor navigation. Best for large documents with complex processing logic.

```elixir
reader = FnXML.API.StAX.Reader.new(xml)

# Pull events one at a time (lazy - O(1) memory)
reader = FnXML.API.StAX.Reader.next(reader)

# Query current event
FnXML.API.StAX.Reader.event_type(reader)      # => :start_element
FnXML.API.StAX.Reader.local_name(reader)      # => "root"
FnXML.API.StAX.Reader.attribute_count(reader) # => 2
FnXML.API.StAX.Reader.attribute_value(reader, nil, "id")  # => "123"

# Convenience methods
FnXML.API.StAX.Reader.start_element?(reader)  # => true
FnXML.API.StAX.Reader.has_next?(reader)       # => true
{text, reader} = FnXML.API.StAX.Reader.element_text(reader)  # read all text in element
```

**Writer for building XML:**

```elixir
xml = FnXML.API.StAX.Writer.new()
|> FnXML.API.StAX.Writer.start_document()
|> FnXML.API.StAX.Writer.start_element("root")
|> FnXML.API.StAX.Writer.attribute("id", "1")
|> FnXML.API.StAX.Writer.characters("Hello")
|> FnXML.API.StAX.Writer.end_element()
|> FnXML.API.StAX.Writer.to_string()
# => "<?xml version=\"1.0\"?><root id=\"1\">Hello</root>"
```

### Low-Level Stream API

Direct access to the event stream for custom processing.

```elixir
# Parse to event stream (auto-selects NIF or Elixir)
FnXML.Parser.parse("<root><child/></root>")
# => [{:start_document, nil}, {:start_element, "root", [], {1, 0, 1}}, ...]

# Stream from file (64KB chunks, lazy evaluation)
File.stream!("large.xml", [], 65536)
|> FnXML.Parser.stream()
|> Enum.to_list()

# Force specific parser backend
FnXML.Parser.stream(xml, parser: :nif)     # Force Zig NIF
FnXML.Parser.stream(xml, parser: :elixir)  # Force pure Elixir

# Direct access to legacy block parsers
events = FnXML.Legacy.ExBlkParser.parse("<root/>")
events = FnXML.Legacy.FastExBlkParser.parse("<root/>")

# With namespace resolution
FnXML.Parser.parse("<root xmlns=\"http://example.org\"><child/></root>")
|> FnXML.Namespaces.resolve()
|> Enum.to_list()
# => [{:start_element, {"http://example.org", "root"}, [...], ...}, ...]

# Convert stream to XML
events
|> FnXML.Transform.Stream.to_xml()
|> Enum.join()
```

**Parser Options:**
- `:parser` - Force parser: `:nif`, `:elixir`, or `:auto` (default)
- `:threshold` - Auto-selection cutoff in bytes (default: 60KB)
- `:block_size` - For streams, hint about chunk size for auto-selection

**Event types (W3C StAX-compatible):**
- `{:start_element, tag, attrs, location}` - Start element
- `{:end_element, tag}` or `{:end_element, tag, location}` - End element
- `{:characters, content, location}` - Text content
- `{:comment, content, location}` - Comment
- `{:cdata, content, location}` - CDATA section
- `{:prolog, "xml", attrs, location}` - XML declaration
- `{:processing_instruction, target, data, location}` - Processing instruction

### Saxy Compatibility

For codebases using Saxy's SimpleForm format:

```elixir
# Decode to SimpleForm tuple
{"root", attrs, children} = FnXML.Transform.Stream.SimpleForm.decode("<root><child/></root>")

# Encode back to XML
FnXML.Transform.Stream.SimpleForm.encode({"root", [], ["text"]})

# Convert between SimpleForm and DOM
elem = FnXML.Transform.Stream.SimpleForm.to_dom({"root", [{"id", "1"}], ["text"]})
tuple = FnXML.Transform.Stream.SimpleForm.from_dom(elem)
```

## Choosing an API

| Use Case | Recommended API |
|----------|-----------------|
| Small documents, need random access | DOM |
| Large documents, extract specific data | SAX |
| Large documents, complex state machine | StAX |
| Stream transformations | Low-level Stream |
| Saxy migration/interop | SimpleForm |
| XML Signatures, Encryption | Security |

## XML Security

FnXML provides W3C-compliant XML Security support for canonicalization, signatures, and encryption.

### Canonicalization (C14N)

Transform XML to a canonical form for signing and comparison.

```elixir
# Canonical XML 1.0
{:ok, canonical} = FnXML.Security.C14N.canonicalize(xml)

# Exclusive Canonical XML (for signing document subsets)
{:ok, canonical} = FnXML.Security.C14N.canonicalize(xml, algorithm: :exc_c14n)

# With comments preserved
{:ok, canonical} = FnXML.Security.C14N.canonicalize(xml, algorithm: :c14n_with_comments)
```

### XML Signatures

Sign and verify XML documents following W3C XML Signature specification.

```elixir
# Generate RSA key pair
private_key = :public_key.generate_key({:rsa, 2048, 65537})
{:RSAPrivateKey, _, n, e, _, _, _, _, _, _, _} = private_key
public_key = {:RSAPublicKey, n, e}

# Sign a document (enveloped signature)
{:ok, signed_xml} = FnXML.Security.Signature.sign(xml, private_key,
  reference_uri: "",
  signature_algorithm: :rsa_sha256,
  digest_algorithm: :sha256,
  c14n_algorithm: :exc_c14n,
  type: :enveloped
)

# Verify a signed document
case FnXML.Security.Signature.verify(signed_xml, public_key) do
  {:ok, :valid} -> IO.puts("Signature is valid")
  {:error, reason} -> IO.puts("Verification failed: #{inspect(reason)}")
end

# Get signature information
{:ok, info} = FnXML.Security.Signature.info(signed_xml)
info.signature_algorithm  # => :rsa_sha256
info.c14n_algorithm       # => :exc_c14n
```

### XML Encryption

Encrypt and decrypt XML content following W3C XML Encryption specification.

```elixir
# Generate a symmetric key
key = FnXML.Security.Algorithms.generate_key(32)  # 256-bit key

# Encrypt an element
xml = ~s(<root><secret id="data">Sensitive info</secret></root>)
{:ok, encrypted_xml} = FnXML.Security.Encryption.encrypt(xml, "#data", key,
  algorithm: :aes_256_gcm,
  type: :element
)

# Decrypt
{:ok, decrypted_xml} = FnXML.Security.Encryption.decrypt(encrypted_xml, key)

# With key transport (RSA-OAEP)
{:ok, encrypted_xml} = FnXML.Security.Encryption.encrypt(xml, "#data", nil,
  algorithm: :aes_256_gcm,
  key_transport: {:rsa_oaep, recipient_public_key}
)

# Decrypt with private key
{:ok, decrypted_xml} = FnXML.Security.Encryption.decrypt(encrypted_xml,
  private_key: recipient_private_key
)
```

### Supported Algorithms

| Category | Algorithms |
|----------|------------|
| **Digest** | SHA-256, SHA-384, SHA-512 |
| **Signature** | RSA-SHA256, RSA-SHA384, RSA-SHA512 |
| **Encryption** | AES-128-GCM, AES-256-GCM, AES-128-CBC, AES-256-CBC |
| **Key Transport** | RSA-OAEP |
| **Canonicalization** | C14N 1.0, Exclusive C14N (with/without comments) |

All cryptographic operations use Erlang/OTP built-in `:crypto` and `:public_key` modules.

## Features

- **NIF acceleration** - Optional Zig NIF for high-throughput parsing (auto-selected for large inputs)
- **Streaming parser** - Process XML incrementally without loading entire document
- **Chunk boundary handling** - Mini-block approach handles elements spanning chunk boundaries
- **Namespace support** - Full XML namespace resolution
- **Three standard APIs** - DOM, SAX, StAX for different use cases
- **XML Security** - W3C-compliant canonicalization, signatures, and encryption
- **Lazy evaluation** - StAX Reader uses O(1) memory
- **Location tracking** - Line/column info for error reporting
- **Saxy compatible** - SimpleForm format for easy migration
- **Disable NIF** - Set `FNXML_NIF=false` or `{:fnxml, "~> x.x", nif: false}` for pure Elixir

## License

MIT

## Contributing

Contributions welcome! Please open an issue or PR on GitHub.
