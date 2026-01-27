# FnXML Quick Start Guide

A comprehensive guide to XML processing in Elixir with FnXML.

## Table of Contents

1. [The XML Ecosystem](#1-the-xml-ecosystem)
2. [FnXML Architecture Overview](#2-fnxml-architecture-overview)
3. [Parsing XML](#3-parsing-xml)
4. [DOM API - Document Object Model](#4-dom-api---document-object-model)
5. [SAX API - Event-Driven Processing](#5-sax-api---event-driven-processing)
6. [StAX API - Pull-Based Processing](#6-stax-api---pull-based-processing)
7. [XML Namespaces](#7-xml-namespaces)
8. [Document Type Definitions (DTD)](#8-document-type-definitions-dtd)
9. [XML Canonicalization (C14N)](#9-xml-canonicalization-c14n)
10. [XML Signatures](#10-xml-signatures)
11. [XML Encryption](#11-xml-encryption)
12. [Choosing the Right API](#12-choosing-the-right-api)

---

## 1. The XML Ecosystem

### What is XML?

XML (eXtensible Markup Language) is a flexible text format for structured data. Unlike HTML which has predefined tags, XML allows you to define your own tags to describe any kind of data.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<bookstore>
  <book category="fiction">
    <title>The Great Gatsby</title>
    <author>F. Scott Fitzgerald</author>
    <price>10.99</price>
  </book>
</bookstore>
```

### The XML Technology Stack

XML is not just a data format—it's an ecosystem of related technologies:

```
┌─────────────────────────────────────────────────────────────────┐
│                     Applications                                 │
│         SOAP, SAML, RSS, SVG, XHTML, Office Documents           │
├─────────────────────────────────────────────────────────────────┤
│                      Security Layer                              │
│            XML Signatures │ XML Encryption │ C14N               │
├─────────────────────────────────────────────────────────────────┤
│                     Query & Transform                            │
│                    XPath │ XSLT │ XQuery                        │
├─────────────────────────────────────────────────────────────────┤
│                      Validation Layer                            │
│              DTD │ XML Schema │ RelaxNG │ Schematron            │
├─────────────────────────────────────────────────────────────────┤
│                    Namespace Support                             │
│            Namespace resolution and prefix handling              │
├─────────────────────────────────────────────────────────────────┤
│                     Processing APIs                              │
│                    DOM │ SAX │ StAX                             │
├─────────────────────────────────────────────────────────────────┤
│                       XML Parser                                 │
│              Tokenization │ Well-formedness checking            │
└─────────────────────────────────────────────────────────────────┘
```

### Where XML is Used Today

| Domain | Examples |
|--------|----------|
| **Enterprise Integration** | SOAP web services, ESB messaging |
| **Identity & Security** | SAML assertions, WS-Security, XACML |
| **Document Formats** | Office Open XML (.docx), ODF, DocBook |
| **Data Exchange** | RSS/Atom feeds, financial data (FpML, FIXML) |
| **Configuration** | Maven POM, Spring beans, Android manifests |
| **Graphics** | SVG vector graphics |

---

## 2. FnXML Architecture Overview

### How FnXML Components Work Together

FnXML provides a complete XML processing stack for Elixir:

```
┌─────────────────────────────────────────────────────────────────┐
│                      Your Application                            │
├─────────────────────────────────────────────────────────────────┤
│                        High-Level APIs                           │
├─────────────────┬─────────────────────┬─────────────────────────┤
│  FnXML.API.DOM  │  FnXML.API.SAX      │  FnXML.API.StAX         │
│  Tree-based     │  Push callbacks     │  Pull cursor            │
│  Random access  │  Memory efficient   │  Application control    │
├─────────────────┴─────────────────────┴─────────────────────────┤
│                       FnXML.Security                             │
│     C14N (Canonicalization) │ Signatures │ Encryption           │
├─────────────────────────────────────────────────────────────────┤
│                        FnXML.Transform.Stream                              │
│            Event stream transformations & formatting             │
├──────────────────────────────┬──────────────────────────────────┤
│  FnXML.Namespaces            │  FnXML.DTD                       │
│  Namespace resolution        │  DTD parsing & validation        │
├──────────────────────────────┴──────────────────────────────────┤
│                        FnXML.Parser                              │
│       Auto-selects: Zig NIF (large) or Elixir (small)           │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow Through FnXML

```
XML String/File
       │
       ▼
┌─────────────────┐
│  FnXML.Parser   │──────► Event Stream
└─────────────────┘        {:start_element, "book", [...], loc}
       │                   {:characters, "content", loc}
       │                   {:end_element, "book", loc}
       │
       ├────────────────────────┬────────────────────────┐
       ▼                        ▼                        ▼
┌─────────────┐          ┌─────────────┐          ┌─────────────┐
│  DOM Tree   │          │ SAX Handler │          │ StAX Reader │
│  (in-memory)│          │ (callbacks) │          │  (cursor)   │
└─────────────┘          └─────────────┘          └─────────────┘
       │                        │                        │
       ▼                        ▼                        ▼
   Query/Modify            Extract Data            State Machine
   Serialize               Transform               Build Output
```

---

## 3. Parsing XML

### What is XML Parsing?

Parsing is the process of reading XML text and converting it into a structured form your code can work with. FnXML's parser handles:

- **Tokenization**: Breaking XML into elements, attributes, text, etc.
- **Well-formedness checking**: Ensuring tags are properly nested and closed
- **Character encoding**: Supporting UTF-8 and other encodings
- **Entity resolution**: Expanding `&amp;` to `&`, etc.

### Why is Parsing Important?

The parser is the foundation of all XML processing. A fast, correct parser enables:
- Reliable data extraction from XML documents
- Processing of large files without memory issues
- Detection of malformed XML before it causes problems

### How to Use the Parser

**Basic Parsing**

```elixir
# Parse XML to event stream
events = FnXML.Parser.parse("<root><child>Hello</child></root>")

# Events are tuples describing each XML construct
# [
#   {:start_element, "root", [], {1, 0, 1}},
#   {:start_element, "child", [], {1, 6, 7}},
#   {:characters, "Hello", {1, 13, 14}},
#   {:end_element, "child", {1, 18, 19}},
#   {:end_element, "root", {1, 26, 27}}
# ]
```

**Streaming Large Files**

```elixir
# Process large files in chunks (memory efficient)
File.stream!("large.xml", [], 65536)
|> FnXML.Parser.stream()
|> Enum.each(fn event ->
  # Process each event as it arrives
end)
```

**Parser Selection**

```elixir
# Auto-selects best parser (default)
FnXML.Parser.parse(xml)

# Force Zig NIF for maximum performance
FnXML.Parser.parse(xml, parser: :nif)

# Force pure Elixir (no NIF dependency)
FnXML.Parser.parse(xml, parser: :elixir)
```

---

## 4. DOM API - Document Object Model

### What is DOM?

The Document Object Model (DOM) loads the entire XML document into memory as a tree structure. Each element becomes a node that you can navigate, query, and modify.

```
Document
└── root (Element)
    ├── child1 (Element)
    │   └── "text content" (Text)
    └── child2 (Element)
        └── grandchild (Element)
```

### Why is DOM Important?

DOM is essential when you need to:
- Navigate to any part of the document at any time
- Modify the document structure
- Query elements by ID or tag name
- Build documents programmatically

### How to Use DOM

**Parsing and Navigation**

```elixir
# Parse XML to DOM tree
doc = FnXML.API.DOM.parse("""
<library>
  <book id="1">
    <title>Elixir in Action</title>
    <author>Saša Jurić</author>
  </book>
  <book id="2">
    <title>Programming Phoenix</title>
    <author>Chris McCord</author>
  </book>
</library>
""")

# Access the root element
doc.root.tag  # => "library"

# Navigate to children
first_book = hd(doc.root.children)
first_book.tag  # => "book"

# Get attributes
FnXML.API.DOM.Element.get_attribute(first_book, "id")  # => "1"

# Get text content
title = Enum.find(first_book.children, &(&1.tag == "title"))
FnXML.API.DOM.Element.text_content(title)  # => "Elixir in Action"
```

**Building Documents**

```elixir
alias FnXML.API.DOM.Element

# Create elements programmatically
book = Element.new("book", [{"id", "3"}], [
  Element.new("title", [], ["Real-Time Phoenix"]),
  Element.new("author", [], ["Stephen Bussey"])
])

# Serialize to XML string
FnXML.API.DOM.to_string(book)
# => "<book id=\"3\"><title>Real-Time Phoenix</title><author>Stephen Bussey</author></book>"

# Pretty print
FnXML.API.DOM.to_string(book, pretty: true)
```

**When to Use DOM**

| Use Case | DOM Suitability |
|----------|-----------------|
| Small to medium documents (<10MB) | Excellent |
| Need random access to any element | Excellent |
| Modify and reserialize | Excellent |
| Large documents (>100MB) | Poor (use SAX/StAX) |
| Extract single value from large file | Poor |

---

## 5. SAX API - Event-Driven Processing

### What is SAX?

SAX (Simple API for XML) is an event-driven, push-based parser. Instead of building a tree, it calls your handler functions as it encounters each XML construct. You process events as they stream past.

```
XML Input: <book><title>Hello</title></book>
              │
              ▼
         SAX Parser
              │
              ├─► start_element("book", ...) ──► Your Handler
              ├─► start_element("title", ...) ─► Your Handler
              ├─► characters("Hello") ─────────► Your Handler
              ├─► end_element("title") ────────► Your Handler
              └─► end_element("book") ─────────► Your Handler
```

### Why is SAX Important?

SAX is crucial for:
- Processing files too large to fit in memory
- High-performance data extraction
- Streaming XML processing
- Memory-constrained environments

### How to Use SAX

**Define a Handler**

```elixir
defmodule BookHandler do
  use FnXML.API.SAX.Handler

  # Called when an element opens
  @impl true
  def start_element(_uri, "book", _qname, attrs, state) do
    id = Enum.find_value(attrs, fn {k, v} -> if k == "id", do: v end)
    {:ok, Map.put(state, :current_book, %{id: id})}
  end

  def start_element(_uri, "title", _qname, _attrs, state) do
    {:ok, Map.put(state, :in_title, true)}
  end

  def start_element(_uri, _local, _qname, _attrs, state) do
    {:ok, state}
  end

  # Called for text content
  @impl true
  def characters(text, %{in_title: true} = state) do
    book = Map.put(state.current_book, :title, text)
    {:ok, %{state | current_book: book, in_title: false}}
  end

  def characters(_text, state), do: {:ok, state}

  # Called when an element closes
  @impl true
  def end_element(_uri, "book", _qname, state) do
    books = [state.current_book | state[:books] || []]
    {:ok, %{state | books: books, current_book: nil}}
  end

  def end_element(_uri, _local, _qname, state), do: {:ok, state}

  # Called at the end of the document
  @impl true
  def end_document(state) do
    {:ok, Enum.reverse(state[:books] || [])}
  end
end
```

**Parse with Handler**

```elixir
xml = """
<library>
  <book id="1"><title>Book One</title></book>
  <book id="2"><title>Book Two</title></book>
</library>
"""

{:ok, books} = FnXML.API.SAX.parse(xml, BookHandler, %{})
# => [%{id: "1", title: "Book One"}, %{id: "2", title: "Book Two"}]
```

**Early Termination**

```elixir
defmodule FindFirstHandler do
  use FnXML.API.SAX.Handler

  @impl true
  def start_element(_uri, "target", _qname, attrs, _state) do
    value = Enum.find_value(attrs, fn {k, v} -> if k == "value", do: v end)
    {:halt, value}  # Stop parsing immediately
  end

  def start_element(_uri, _local, _qname, _attrs, state), do: {:ok, state}
end

# Stops as soon as <target> is found
{:ok, value} = FnXML.API.SAX.parse(large_xml, FindFirstHandler, nil)
```

---

## 6. StAX API - Pull-Based Processing

### What is StAX?

StAX (Streaming API for XML) is a pull-based parser. Unlike SAX where the parser pushes events to you, with StAX you pull events when you're ready for them. This gives you explicit control over the parsing process.

```
          Your Code                    StAX Reader
              │                             │
              ├── reader.next() ───────────►│
              │◄────── {:start_element} ────┤
              │                             │
              ├── reader.next() ───────────►│
              │◄────── {:characters} ───────┤
              │                             │
              ├── reader.next() ───────────►│
              │◄────── {:end_element} ──────┤
```

### Why is StAX Important?

StAX excels when you need:
- Fine-grained control over parsing
- Complex state machine processing
- Pause and resume parsing
- Mix reading and writing XML
- Memory-efficient processing of large files

### How to Use StAX

**Reader: Parsing XML**

```elixir
alias FnXML.API.StAX.Reader

# Create a reader
reader = Reader.new("""
<users>
  <user id="1" name="Alice"/>
  <user id="2" name="Bob"/>
</users>
""")

# Pull events one at a time
reader = Reader.next(reader)
Reader.event_type(reader)  # => :start_element
Reader.local_name(reader)  # => "users"

reader = Reader.next(reader)
Reader.event_type(reader)  # => :start_element
Reader.local_name(reader)  # => "user"
Reader.attribute_value(reader, nil, "name")  # => "Alice"

# Process until end
defp process_users(reader, users) do
  if Reader.has_next?(reader) do
    reader = Reader.next(reader)

    case {Reader.event_type(reader), Reader.local_name(reader)} do
      {:start_element, "user"} ->
        user = %{
          id: Reader.attribute_value(reader, nil, "id"),
          name: Reader.attribute_value(reader, nil, "name")
        }
        process_users(reader, [user | users])

      {:end_element, "users"} ->
        Enum.reverse(users)

      _ ->
        process_users(reader, users)
    end
  else
    Enum.reverse(users)
  end
end
```

**Writer: Building XML**

```elixir
alias FnXML.API.StAX.Writer

xml = Writer.new()
|> Writer.start_document()
|> Writer.start_element("users")
|> Writer.start_element("user")
|> Writer.attribute("id", "1")
|> Writer.attribute("name", "Alice")
|> Writer.end_element()
|> Writer.start_element("user")
|> Writer.attribute("id", "2")
|> Writer.attribute("name", "Bob")
|> Writer.end_element()
|> Writer.end_element()
|> Writer.to_string()

# Result:
# <?xml version="1.0"?><users><user id="1" name="Alice"/><user id="2" name="Bob"/></users>
```

**Convenience Methods**

```elixir
# Get all text content within current element
{text, reader} = Reader.element_text(reader)

# Skip to next element (ignoring whitespace/comments)
reader = Reader.next_tag(reader)

# Check event type predicates
Reader.start_element?(reader)  # => true/false
Reader.end_element?(reader)    # => true/false
Reader.characters?(reader)     # => true/false
```

---

## 7. XML Namespaces

### What are Namespaces?

XML namespaces prevent naming conflicts when combining XML from different sources. They work like packages in programming languages—two elements can have the same local name but different namespaces.

```xml
<!-- Without namespaces: ambiguous! -->
<table>...</table>  <!-- HTML table or database table? -->

<!-- With namespaces: clear -->
<html:table xmlns:html="http://www.w3.org/1999/xhtml">...</html:table>
<db:table xmlns:db="http://example.org/database">...</db:table>
```

### Why are Namespaces Important?

Namespaces enable:
- Combining XML vocabularies (SOAP + custom content)
- Avoiding element name collisions
- Identifying XML elements by their full qualified name
- Standards compliance (SAML, SOAP require namespaces)

### How to Use Namespaces

**Resolving Namespaces**

```elixir
xml = """
<root xmlns="http://default.ns" xmlns:custom="http://custom.ns">
  <child>Default namespace</child>
  <custom:child>Custom namespace</custom:child>
</root>
"""

# Parse with namespace resolution
events = FnXML.Parser.parse(xml)
|> FnXML.Namespaces.resolve()
|> Enum.to_list()

# Elements now have {namespace_uri, local_name} tuples
# {:start_element, {"http://default.ns", "root"}, [...], loc}
# {:start_element, {"http://default.ns", "child"}, [...], loc}
# {:start_element, {"http://custom.ns", "child"}, [...], loc}
```

**SAX with Namespaces**

```elixir
defmodule NsHandler do
  use FnXML.API.SAX.Handler

  @impl true
  def start_element(uri, local_name, _qname, _attrs, state) do
    # uri contains the namespace URI
    # local_name is without prefix
    IO.puts("Element: {#{uri}}#{local_name}")
    {:ok, state}
  end
end

FnXML.API.SAX.parse(xml, NsHandler, nil, namespaces: true)
```

**StAX with Namespaces**

```elixir
reader = FnXML.API.StAX.Reader.new(xml, namespaces: true)
reader = FnXML.API.StAX.Reader.next(reader)

FnXML.API.StAX.Reader.namespace_uri(reader)  # => "http://default.ns"
FnXML.API.StAX.Reader.local_name(reader)     # => "root"
FnXML.API.StAX.Reader.prefix(reader)         # => nil (default namespace)
```

---

## 8. Document Type Definitions (DTD)

### What is a DTD?

A Document Type Definition (DTD) defines the legal structure of an XML document. It specifies which elements can appear, their attributes, and their relationships.

```xml
<!DOCTYPE note [
  <!ELEMENT note (to, from, body)>
  <!ELEMENT to (#PCDATA)>
  <!ELEMENT from (#PCDATA)>
  <!ELEMENT body (#PCDATA)>
  <!ATTLIST note priority (high|medium|low) "medium">
]>
<note priority="high">
  <to>Alice</to>
  <from>Bob</from>
  <body>Don't forget the meeting!</body>
</note>
```

### Why are DTDs Important?

DTDs provide:
- Document validation (ensure structure is correct)
- Default attribute values
- Entity definitions (reusable content)
- Documentation of expected structure

### How to Use DTDs

**Pipeline-Friendly Entity Resolution (Recommended)**

Use `FnXML.DTD.resolve/2` to extract and resolve DTD entities in a single streaming pass:

```elixir
xml = """
<?xml version="1.0"?>
<!DOCTYPE root [
  <!ENTITY company "Acme Corp">
  <!ELEMENT root (item+)>
  <!ELEMENT item (#PCDATA)>
]>
<root>
  <item>Welcome to &company;</item>
</root>
"""

# Single-pass DTD entity resolution
events = xml
|> FnXML.parse_stream()
|> FnXML.DTD.resolve()              # Extracts entities from DTD and resolves them
|> FnXML.Validate.well_formed()
|> Enum.to_list()

# The &company; entity is resolved to "Acme Corp"
# Predefined entities (&amp;, &lt;, etc.) are also resolved
```

**With External DTD**

```elixir
# Build resolver for external DTD references
resolver = fn system_id, _public_id ->
  path = Path.join("/path/to/dtds", system_id)
  File.read(path)
end

events = xml
|> FnXML.parse_stream()
|> FnXML.DTD.resolve(external_resolver: resolver)
|> Enum.to_list()
```

**Options**

```elixir
FnXML.DTD.resolve(stream,
  on_unknown: :keep,              # :raise | :emit | :keep | :remove
  edition: 5,                     # XML edition for re-parsing markup
  external_resolver: resolver,    # Function for external DTD files
  max_expansion_depth: 10,        # Prevent entity expansion attacks
  max_total_expansion: 1_000_000  # Maximum expanded content size
)
```

**Accessing DTD Information**

```elixir
# Parse DTD separately for validation/inspection
dtd_text = """
<!ELEMENT root (child*)>
<!ELEMENT child (#PCDATA)>
<!ATTLIST child type (a|b|c) "a">
"""

{:ok, dtd} = FnXML.DTD.Parser.parse(dtd_text)

# Query element definitions
dtd.elements["root"]   # => element content model
dtd.elements["child"]  # => #PCDATA

# Query attribute definitions
dtd.attributes["child"]  # => attribute definitions
```

---

## 9. XML Canonicalization (C14N)

### What is Canonicalization?

Canonicalization transforms XML into a standardized form. Different XML documents that are logically equivalent become byte-for-byte identical after canonicalization.

```xml
<!-- These are logically equivalent but different bytes -->
<root attr1="a" attr2="b"/>
<root   attr2="b"   attr1="a"  />
<root attr1='a' attr2='b'></root>

<!-- After C14N, all become: -->
<root attr1="a" attr2="b"></root>
```

### Why is C14N Important?

Canonicalization is essential for:
- **Digital Signatures**: Sign the canonical form so equivalent documents verify
- **Document Comparison**: Compare documents for logical equality
- **Hashing**: Get consistent hash values for equivalent documents
- **Interoperability**: Ensure different systems produce identical output

### C14N Rules

| Aspect | Canonical Form |
|--------|---------------|
| Attribute order | Sorted by namespace URI, then local name |
| Namespace declarations | Sorted alphabetically by prefix |
| Whitespace in attributes | Normalized |
| Empty elements | `<elem></elem>` (not `<elem/>`) |
| Quotes | Always double quotes |
| Line endings | LF only (no CRLF) |
| Comments | Removed (unless WithComments variant) |

### How to Use C14N

**Basic Canonicalization**

```elixir
xml = """
<root   b="2"   a="1">
  <child/>
</root>
"""

{:ok, canonical} = FnXML.Security.C14N.canonicalize(xml)
# Result (note attribute order and empty element):
# <root a="1" b="2">
#   <child></child>
# </root>
```

**Exclusive Canonicalization**

```elixir
# Exclusive C14N only includes "visibly utilized" namespaces
# Useful for signing document subsets that might be moved

xml = """
<root xmlns:unused="http://unused" xmlns:used="http://used">
  <used:child attr="value"/>
</root>
"""

{:ok, canonical} = FnXML.Security.C14N.canonicalize(xml, algorithm: :exc_c14n)
# Only xmlns:used is included, xmlns:unused is filtered out
```

**Algorithm Options**

```elixir
# C14N 1.0 (includes all inherited namespaces)
{:ok, c} = FnXML.Security.C14N.canonicalize(xml, algorithm: :c14n)

# C14N 1.0 with comments preserved
{:ok, c} = FnXML.Security.C14N.canonicalize(xml, algorithm: :c14n_with_comments)

# Exclusive C14N (only visibly utilized namespaces)
{:ok, c} = FnXML.Security.C14N.canonicalize(xml, algorithm: :exc_c14n)

# Exclusive C14N with comments
{:ok, c} = FnXML.Security.C14N.canonicalize(xml, algorithm: :exc_c14n_with_comments)
```

---

## 10. XML Signatures

### What are XML Signatures?

XML Signatures (XMLDSig) provide data integrity and authentication for XML documents. A signature proves that the signed content hasn't been modified and was created by someone with the private key.

```xml
<Document>
  <Data>Important content</Data>
  <ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
    <ds:SignedInfo>
      <ds:CanonicalizationMethod Algorithm="..."/>
      <ds:SignatureMethod Algorithm="..."/>
      <ds:Reference URI="">
        <ds:DigestMethod Algorithm="..."/>
        <ds:DigestValue>abc123...</ds:DigestValue>
      </ds:Reference>
    </ds:SignedInfo>
    <ds:SignatureValue>xyz789...</ds:SignatureValue>
  </ds:Signature>
</Document>
```

### Why are XML Signatures Important?

XML Signatures enable:
- **Data Integrity**: Detect if content was modified
- **Authentication**: Verify who signed the document
- **Non-repudiation**: Signer cannot deny signing
- **Selective Signing**: Sign specific parts of a document
- **Standards Compliance**: Required for SAML, SOAP-Security, etc.

### Signature Types

| Type | Description | Use Case |
|------|-------------|----------|
| **Enveloped** | Signature inside signed document | Sign entire documents |
| **Enveloping** | Signed data inside Signature element | Sign arbitrary data |
| **Detached** | Signature and data separate | Sign external resources |

### How to Use Signatures

**Generate RSA Key Pair**

```elixir
# Generate a 2048-bit RSA key pair
private_key = :public_key.generate_key({:rsa, 2048, 65537})
{:RSAPrivateKey, _, n, e, _, _, _, _, _, _, _} = private_key
public_key = {:RSAPublicKey, n, e}
```

**Sign a Document**

```elixir
xml = """
<Document Id="doc1">
  <Data>Sensitive information</Data>
</Document>
"""

{:ok, signed_xml} = FnXML.Security.Signature.sign(xml, private_key,
  reference_uri: "",              # Empty = entire document
  type: :enveloped,               # Signature inside document
  signature_algorithm: :rsa_sha256,
  digest_algorithm: :sha256,
  c14n_algorithm: :exc_c14n
)
```

**Verify a Signature**

```elixir
case FnXML.Security.Signature.verify(signed_xml, public_key) do
  {:ok, :valid} ->
    IO.puts("Signature is valid - document is authentic")

  {:error, :invalid_signature} ->
    IO.puts("Signature verification failed!")

  {:error, :digest_mismatch} ->
    IO.puts("Document was modified after signing!")
end
```

**Inspect Signature Information**

```elixir
{:ok, info} = FnXML.Security.Signature.info(signed_xml)

info.signature_algorithm  # => :rsa_sha256
info.c14n_algorithm       # => :exc_c14n
info.digest_algorithms    # => [:sha256]
info.references           # => [%{uri: "", transforms: [...]}]
```

---

## 11. XML Encryption

### What is XML Encryption?

XML Encryption allows you to encrypt parts of an XML document while leaving other parts readable. The encrypted content is replaced with an `<EncryptedData>` element containing the ciphertext.

```xml
<!-- Before encryption -->
<Patient>
  <Name>John Doe</Name>
  <SSN>123-45-6789</SSN>
</Patient>

<!-- After encrypting SSN element -->
<Patient>
  <Name>John Doe</Name>
  <xenc:EncryptedData xmlns:xenc="http://www.w3.org/2001/04/xmlenc#"
                      Type="http://www.w3.org/2001/04/xmlenc#Element">
    <xenc:EncryptionMethod Algorithm="..."/>
    <xenc:CipherData>
      <xenc:CipherValue>base64-encoded-ciphertext</xenc:CipherValue>
    </xenc:CipherData>
  </xenc:EncryptedData>
</Patient>
```

### Why is XML Encryption Important?

XML Encryption enables:
- **Selective Encryption**: Encrypt sensitive parts, leave others readable
- **Transport Security**: Protect data in transit
- **Storage Security**: Protect data at rest
- **Key Transport**: Securely deliver encryption keys
- **Standards Compliance**: Required for WS-Security, SAML encrypted assertions

### Encryption Types

| Type | What's Encrypted | Result |
|------|------------------|--------|
| **Element** | Entire element including tags | Element replaced by EncryptedData |
| **Content** | Element's children only | Children replaced by EncryptedData |

### How to Use Encryption

**Generate a Symmetric Key**

```elixir
# Generate a 256-bit AES key
key = FnXML.Security.Algorithms.generate_key(32)  # 32 bytes = 256 bits
```

**Encrypt an Element**

```elixir
xml = """
<Patient>
  <Name>John Doe</Name>
  <SSN Id="ssn">123-45-6789</SSN>
</Patient>
"""

{:ok, encrypted_xml} = FnXML.Security.Encryption.encrypt(xml, "#ssn", key,
  algorithm: :aes_256_gcm,  # Recommended: authenticated encryption
  type: :element            # Encrypt entire element
)

# Result: SSN element is replaced with EncryptedData
# The Name element remains readable
```

**Decrypt**

```elixir
{:ok, decrypted_xml} = FnXML.Security.Encryption.decrypt(encrypted_xml, key)
# Original document is restored
```

**Key Transport (RSA-OAEP)**

When you need to encrypt for a recipient whose public key you have:

```elixir
# Recipient's RSA key pair
recipient_private = :public_key.generate_key({:rsa, 2048, 65537})
{:RSAPrivateKey, _, n, e, _, _, _, _, _, _, _} = recipient_private
recipient_public = {:RSAPublicKey, n, e}

# Encrypt - a random key is generated and wrapped with recipient's public key
{:ok, encrypted_xml} = FnXML.Security.Encryption.encrypt(xml, "#ssn", nil,
  algorithm: :aes_256_gcm,
  key_transport: {:rsa_oaep, recipient_public}
)

# Decrypt - recipient uses their private key
{:ok, decrypted_xml} = FnXML.Security.Encryption.decrypt(encrypted_xml,
  private_key: recipient_private
)
```

**Inspect Encrypted Data**

```elixir
{:ok, info} = FnXML.Security.Encryption.info(encrypted_xml)

info.algorithm           # => :aes_256_gcm
info.type                # => :element
info.has_encrypted_key   # => true (if key transport was used)
info.key_transport_algorithm  # => :rsa_oaep
```

---

## 12. Choosing the Right API

### Decision Guide

```
                        ┌─────────────────────────┐
                        │ What's your use case?   │
                        └───────────┬─────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    │               │               │
                    ▼               ▼               ▼
            ┌───────────┐   ┌───────────┐   ┌───────────┐
            │ Need to   │   │ Large     │   │ Need      │
            │ modify or │   │ file,     │   │ security? │
            │ query     │   │ streaming │   │           │
            │ randomly? │   │ required? │   │           │
            └─────┬─────┘   └─────┬─────┘   └─────┬─────┘
                  │               │               │
           Yes    │        Yes    │        Yes    │
                  ▼               │               ▼
            ┌─────────┐           │         ┌─────────────┐
            │   DOM   │           │         │  Security   │
            └─────────┘           │         │  C14N/Sig/  │
                                  │         │  Encryption │
                                  │         └─────────────┘
                    ┌─────────────┴─────────────┐
                    │                           │
                    ▼                           ▼
            ┌───────────────┐         ┌───────────────┐
            │ Simple data   │         │ Complex state │
            │ extraction?   │         │ machine?      │
            └───────┬───────┘         └───────┬───────┘
                    │                         │
                    ▼                         ▼
              ┌─────────┐               ┌─────────┐
              │   SAX   │               │  StAX   │
              └─────────┘               └─────────┘
```

### Quick Reference Table

| Task | Recommended API | Why |
|------|-----------------|-----|
| Parse small config file | DOM | Simple, random access |
| Extract data from 1GB XML | SAX | Memory efficient |
| Build XML output | StAX Writer | Streaming, efficient |
| SAML assertion validation | Signature | Standard compliance |
| Encrypt sensitive fields | Encryption | Selective protection |
| Compare XML documents | C14N | Byte-identical comparison |
| Complex XML transformation | StAX | Full control over parsing |
| Find single element in large file | SAX with `:halt` | Early termination |
| Modify and save XML | DOM | Tree manipulation |
| XML-to-JSON conversion | SAX or StAX | No need for full tree |

### Memory Characteristics

| API | Memory Usage | Scales With |
|-----|--------------|-------------|
| DOM | O(n) | Document size |
| SAX | O(1) | State only |
| StAX | O(1) | State only |
| C14N | O(n) | Document size |
| Signature | O(n) | Signed portion |
| Encryption | O(n) | Encrypted portion |

### Performance Tips

1. **Use SAX for large files**: Don't load 100MB into DOM
2. **Use `:halt` for early exit**: Stop SAX when you find what you need
3. **Use Exclusive C14N**: Smaller output than regular C14N
4. **Use AES-GCM**: Authenticated encryption, faster than CBC
5. **Stream when possible**: Use `FnXML.Parser.stream/2` for files
6. **Reuse keys**: Key generation is expensive
