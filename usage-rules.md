# FnXML Usage Rules for LLMs

Concise rules for using the FnXML library correctly.

## API Selection

| Scenario | Use This |
|----------|----------|
| Build tree, query/modify nodes | `FnXML.API.DOM` |
| Large file, extract specific data | `FnXML.API.SAX` |
| Large file, stateful processing | `FnXML.API.StAX` |
| Custom stream transformations | `FnXML.Parser` + `FnXML.Event.Transform.Stream` |
| Canonicalization for signing | `FnXML.C14N` |
| Sign/verify XML documents | `FnXML.Security.Signature` |
| Encrypt/decrypt XML content | `FnXML.Security.Encryption` |

## DOM Rules

```elixir
# CORRECT: Pipeline style (recommended)
doc = FnXML.Parser.parse(xml_string)
      |> FnXML.API.DOM.build()

# CORRECT: With validation/transforms
doc = File.stream!("data.xml")
      |> FnXML.Parser.parse()
      |> FnXML.Event.Validate.well_formed()
      |> FnXML.Namespaces.resolve()
      |> FnXML.API.DOM.build()

# CORRECT: Access
doc.root.tag
doc.root.children
FnXML.API.DOM.Element.get_attribute(element, "attr_name")

# CORRECT: Serialize
FnXML.API.DOM.to_string(doc)
FnXML.API.DOM.to_string(doc, pretty: true)

# CORRECT: Build elements
FnXML.API.DOM.Element.new("tag", [{"attr", "val"}], ["child text"])
```

**Memory:** O(n) - entire document in memory

## SAX Rules

```elixir
# CORRECT: Define handler module
defmodule MyHandler do
  use FnXML.API.SAX.Handler  # Provides default implementations

  @impl true
  def start_element(_uri, local_name, _qname, _attrs, state) do
    {:ok, new_state}  # Must return {:ok, state}, {:halt, state}, or {:error, reason}
  end
end

# CORRECT: Pipeline style (recommended)
{:ok, final_state} = FnXML.Parser.parse(xml)
                     |> FnXML.API.SAX.dispatch(MyHandler, initial_state)

# CORRECT: With validation/transforms
{:ok, result} = File.stream!("large.xml")
                |> FnXML.Parser.parse()
                |> FnXML.Event.Validate.well_formed()
                |> FnXML.API.SAX.dispatch(MyHandler, initial_state)

# CORRECT: With options
{:ok, result} = FnXML.Parser.parse(xml)
                |> FnXML.API.SAX.dispatch(MyHandler, state, namespaces: true)
```

**Callbacks (all receive state, return `{:ok, state}`):**
- `start_document(state)`
- `end_document(state)`
- `start_element(uri, local_name, qname, attrs, state)`
- `end_element(uri, local_name, qname, state)`
- `characters(text, state)`

**Early termination:** Return `{:halt, state}` from any callback

**Memory:** O(1) - streaming

## StAX Rules

```elixir
# CORRECT: Pipeline style (recommended)
reader = FnXML.Parser.parse(xml_string)
         |> FnXML.API.StAX.Reader.new()

# CORRECT: With validation/transforms
reader = File.stream!("large.xml")
         |> FnXML.Parser.parse()
         |> FnXML.Event.Validate.well_formed()
         |> FnXML.API.StAX.Reader.new()

# CORRECT: Pull events
reader = FnXML.API.StAX.Reader.next(reader)  # Must call next() to advance

# CORRECT: Check event type before accessing data
if FnXML.API.StAX.Reader.start_element?(reader) do
  name = FnXML.API.StAX.Reader.local_name(reader)
  attr = FnXML.API.StAX.Reader.attribute_value(reader, nil, "id")
end

# CORRECT: Iteration pattern
defp process(reader) do
  if FnXML.API.StAX.Reader.has_next?(reader) do
    reader = FnXML.API.StAX.Reader.next(reader)
    # process current event...
    process(reader)
  else
    reader
  end
end

# CORRECT: Get all text in element
{text, reader} = FnXML.API.StAX.Reader.element_text(reader)

# CORRECT: Writer usage
xml = FnXML.API.StAX.Writer.new()
|> FnXML.API.StAX.Writer.start_element("root")
|> FnXML.API.StAX.Writer.attribute("id", "1")  # Attributes before content
|> FnXML.API.StAX.Writer.characters("text")
|> FnXML.API.StAX.Writer.end_element()
|> FnXML.API.StAX.Writer.to_string()
```

**Event types:** `:start_element`, `:end_element`, `:characters`, `:comment`, `:cdata`, `:processing_instruction`, `:end_document`

**Memory:** O(1) - lazy stream

## Low-Level Stream Rules

```elixir
# CORRECT: Get event stream
stream = FnXML.Parser.parse(xml_string)

# CORRECT: With namespaces
stream = FnXML.Parser.parse(xml_string) |> FnXML.Namespaces.resolve()

# CORRECT: Convert to XML
iodata = stream |> FnXML.Event.to_iodata()
xml = IO.iodata_to_binary(iodata)

# Event tuple formats (W3C StAX-compatible):
{:start_element, "tag", [{"attr", "val"}], {line, line_start, byte_offset}}
{:end_element, "tag", {line, line_start, byte_offset}}
{:characters, "content", location}
{:comment, "content", location}
{:cdata, "content", location}

# With namespace resolution, tag becomes tuple:
{:start_element, {"http://ns.uri", "local_name"}, attrs, location}
```

## SimpleForm (Saxy Compatibility)

```elixir
# Tuple format: {tag, attrs, children}
{"root", [{"id", "1"}], ["text", {"child", [], []}]}

# CORRECT: Parse to SimpleForm
simple = FnXML.Event.Transform.Stream.SimpleForm.decode(xml_string)

# CORRECT: Encode to XML
xml = FnXML.Event.Transform.Stream.SimpleForm.encode(simple_form_tuple)

# CORRECT: Convert to/from DOM
element = FnXML.Event.Transform.Stream.SimpleForm.to_dom(simple_form_tuple)
tuple = FnXML.Event.Transform.Stream.SimpleForm.from_dom(element)
```

## Common Mistakes

```elixir
# WRONG: Accessing reader without calling next()
reader = FnXML.API.StAX.Reader.new(xml)
FnXML.API.StAX.Reader.local_name(reader)  # Returns nil!

# CORRECT: Call next() first
reader = FnXML.API.StAX.Reader.new(xml)
reader = FnXML.API.StAX.Reader.next(reader)
FnXML.API.StAX.Reader.local_name(reader)  # Works

# WRONG: SAX handler not returning proper tuple
def start_element(_, _, _, _, state) do
  state  # Missing {:ok, ...} wrapper!
end

# CORRECT: Return {:ok, state}
def start_element(_, _, _, _, state) do
  {:ok, state}
end

# WRONG: Writer attributes after content
writer
|> FnXML.API.StAX.Writer.start_element("root")
|> FnXML.API.StAX.Writer.characters("text")
|> FnXML.API.StAX.Writer.attribute("id", "1")  # Too late!

# CORRECT: Attributes immediately after start_element
writer
|> FnXML.API.StAX.Writer.start_element("root")
|> FnXML.API.StAX.Writer.attribute("id", "1")
|> FnXML.API.StAX.Writer.characters("text")
```

## Namespace Handling

```elixir
# SAX with namespaces (default: true)
FnXML.Parser.parse(xml)
|> FnXML.API.SAX.dispatch(Handler, state, namespaces: true)
# Handler receives: start_element("http://ns", "local", "prefix:local", attrs, state)

# SAX without namespaces
FnXML.Parser.parse(xml)
|> FnXML.API.SAX.dispatch(Handler, state, namespaces: false)
# Handler receives: start_element(nil, "prefix:local", "prefix:local", attrs, state)

# StAX with namespaces
reader = FnXML.Parser.parse(xml)
         |> FnXML.API.StAX.Reader.new(namespaces: true)
FnXML.API.StAX.Reader.namespace_uri(reader)  # => "http://ns"

# Low-level with namespaces
FnXML.Parser.parse(xml) |> FnXML.Namespaces.resolve()
```

## Performance Guidelines

1. **Large files (>10MB):** Use SAX or StAX, not DOM
2. **Extract single value:** SAX with `{:halt, value}`
3. **Complex state machine:** StAX with explicit control flow
4. **Transform and output:** Low-level stream pipeline
5. **Small files with queries:** DOM for convenience

## XML Security Rules

### Canonicalization (C14N)

```elixir
# CORRECT: Basic canonicalization
{:ok, canonical} = FnXML.C14N.canonicalize(xml)

# CORRECT: Exclusive C14N for document subsets
{:ok, canonical} = FnXML.C14N.canonicalize(xml, algorithm: :exc_c14n)

# CORRECT: Preserve comments
{:ok, canonical} = FnXML.C14N.canonicalize(xml, algorithm: :c14n_with_comments)

# Algorithms: :c14n, :c14n_with_comments, :exc_c14n, :exc_c14n_with_comments
```

### Signatures

```elixir
# CORRECT: Generate key pair for signing
private_key = :public_key.generate_key({:rsa, 2048, 65537})
{:RSAPrivateKey, _, n, e, _, _, _, _, _, _, _} = private_key
public_key = {:RSAPublicKey, n, e}

# CORRECT: Enveloped signature (signature inside document)
{:ok, signed} = FnXML.Security.Signature.sign(xml, private_key,
  reference_uri: "",           # Empty = whole document
  type: :enveloped,
  signature_algorithm: :rsa_sha256,
  digest_algorithm: :sha256,
  c14n_algorithm: :exc_c14n
)

# CORRECT: Verify signature
{:ok, :valid} = FnXML.Security.Signature.verify(signed_xml, public_key)

# CORRECT: Check signature info before verification
{:ok, info} = FnXML.Security.Signature.info(signed_xml)
info.signature_algorithm  # => :rsa_sha256
info.c14n_algorithm       # => :exc_c14n
info.references           # => [%{uri: "", digest_algorithm: :sha256}]
```

**Signature Types:**
- `:enveloped` - Signature inside signed document
- `:enveloping` - Signed data inside signature
- `:detached` - Signature and data separate

**Algorithms:**
- Signature: `:rsa_sha256`, `:rsa_sha384`, `:rsa_sha512`
- Digest: `:sha256`, `:sha384`, `:sha512`

### Encryption

```elixir
# CORRECT: Generate symmetric key
key = FnXML.Security.Algorithms.generate_key(32)  # 32 bytes = 256-bit

# CORRECT: Encrypt element by ID
{:ok, encrypted} = FnXML.Security.Encryption.encrypt(xml, "#element-id", key,
  algorithm: :aes_256_gcm,
  type: :element
)

# CORRECT: Decrypt with symmetric key
{:ok, decrypted} = FnXML.Security.Encryption.decrypt(encrypted_xml, key)

# CORRECT: Key transport (encrypt key with RSA)
{:ok, encrypted} = FnXML.Security.Encryption.encrypt(xml, "#element-id", nil,
  algorithm: :aes_256_gcm,
  key_transport: {:rsa_oaep, recipient_public_key}
)

# CORRECT: Decrypt with private key
{:ok, decrypted} = FnXML.Security.Encryption.decrypt(encrypted_xml,
  private_key: recipient_private_key
)

# CORRECT: Check encryption info
{:ok, info} = FnXML.Security.Encryption.info(encrypted_xml)
info.algorithm            # => :aes_256_gcm
info.type                 # => :element
info.has_encrypted_key    # => true
```

**Encryption Types:**
- `:element` - Encrypt entire element (including tags)
- `:content` - Encrypt element content only

**Algorithms:**
- Encryption: `:aes_128_gcm`, `:aes_256_gcm`, `:aes_128_cbc`, `:aes_256_cbc`
- Key Transport: `:rsa_oaep`

### Security Best Practices

```elixir
# WRONG: Using SHA-1 (deprecated)
signature_algorithm: :rsa_sha1  # Insecure!

# CORRECT: Use SHA-256 or stronger
signature_algorithm: :rsa_sha256

# WRONG: Using AES-CBC without authentication
algorithm: :aes_256_cbc  # Vulnerable to padding oracle

# CORRECT: Use authenticated encryption
algorithm: :aes_256_gcm

# WRONG: Hardcoding keys
key = <<1, 2, 3, ...>>  # Never hardcode!

# CORRECT: Generate random keys
key = FnXML.Security.Algorithms.generate_key(32)

# WRONG: Ignoring verification errors
FnXML.Security.Signature.verify(xml, key)  # Ignoring result!

# CORRECT: Handle verification result
case FnXML.Security.Signature.verify(xml, key) do
  {:ok, :valid} -> process_trusted(xml)
  {:error, reason} -> handle_invalid(reason)
end
```

### Low-Level Algorithms

```elixir
# Direct digest computation
hash = FnXML.Security.Algorithms.digest("data", :sha256)

# Sign data
{:ok, signature} = FnXML.Security.Algorithms.sign(data, :rsa_sha256, private_key)

# Verify signature
:ok = FnXML.Security.Algorithms.verify(data, signature, :rsa_sha256, public_key)

# Encrypt/decrypt with AES-GCM
{:ok, ciphertext} = FnXML.Security.Algorithms.encrypt(plaintext, :aes_256_gcm, key)
{:ok, plaintext} = FnXML.Security.Algorithms.decrypt(ciphertext, :aes_256_gcm, key)

# Key wrapping for key transport
{:ok, wrapped} = FnXML.Security.Algorithms.encrypt_key(dek, :rsa_oaep, public_key)
{:ok, dek} = FnXML.Security.Algorithms.decrypt_key(wrapped, :rsa_oaep, private_key)
```
