# XML Parser APIs Specification

This document consolidates the W3C DOM, SAX, and StAX specifications for XML parser APIs,
formatted for easy consumption by LLMs and as a reference for FnXML implementation.

## Table of Contents

1. [Overview](#overview)
2. [DOM - Document Object Model](#dom---document-object-model)
3. [SAX - Simple API for XML](#sax---simple-api-for-xml)
4. [StAX - Streaming API for XML](#stax---streaming-api-for-xml)
5. [API Comparison](#api-comparison)
6. [Elixir Adaptation Notes](#elixir-adaptation-notes)
7. [Implementation Plan for FnXML](#implementation-plan-for-fnxml)

---

## Overview

### Three Paradigms for XML Processing

| API | Model | Memory | Control | Use Case |
|-----|-------|--------|---------|----------|
| **DOM** | Tree | High (full document in memory) | Random access | Small documents, manipulation |
| **SAX** | Push events | Low (streaming) | Parser-driven | Large documents, read-only |
| **StAX** | Pull events | Low (streaming) | Application-driven | Large documents, selective processing |

---

## DOM - Document Object Model

**Specification:** W3C DOM Level 3 Core (April 2004)
**Reference:** https://www.w3.org/TR/2004/REC-DOM-Level-3-Core-20040407/

The DOM represents an XML document as a tree of nodes. Each node has a type, properties,
and relationships to other nodes (parent, children, siblings).

### Node Types

```
ELEMENT_NODE                = 1
ATTRIBUTE_NODE              = 2
TEXT_NODE                   = 3
CDATA_SECTION_NODE          = 4
ENTITY_REFERENCE_NODE       = 5
ENTITY_NODE                 = 6
PROCESSING_INSTRUCTION_NODE = 7
COMMENT_NODE                = 8
DOCUMENT_NODE               = 9
DOCUMENT_TYPE_NODE          = 10
DOCUMENT_FRAGMENT_NODE      = 11
NOTATION_NODE               = 12
```

### Document Position Constants

```
DOCUMENT_POSITION_DISCONNECTED          = 0x01
DOCUMENT_POSITION_PRECEDING             = 0x02
DOCUMENT_POSITION_FOLLOWING             = 0x04
DOCUMENT_POSITION_CONTAINS              = 0x08
DOCUMENT_POSITION_CONTAINED_BY          = 0x10
DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC = 0x20
```

### Node Interface

The base interface for all DOM nodes.

#### Properties

| Property | Type | Access | Description |
|----------|------|--------|-------------|
| `nodeName` | String | readonly | Name of the node |
| `nodeValue` | String | read/write | Value of the node (may raise DOMException) |
| `nodeType` | unsigned short | readonly | Type constant (1-12) |
| `parentNode` | Node | readonly | Parent node |
| `childNodes` | NodeList | readonly | List of child nodes |
| `firstChild` | Node | readonly | First child node |
| `lastChild` | Node | readonly | Last child node |
| `previousSibling` | Node | readonly | Previous sibling node |
| `nextSibling` | Node | readonly | Next sibling node |
| `attributes` | NamedNodeMap | readonly | Attributes (for Element only) |
| `ownerDocument` | Document | readonly | Document that owns this node |
| `namespaceURI` | String | readonly | Namespace URI (Level 2) |
| `prefix` | String | read/write | Namespace prefix (Level 2) |
| `localName` | String | readonly | Local name without prefix (Level 2) |
| `baseURI` | String | readonly | Base URI (Level 3) |
| `textContent` | String | read/write | Text content of node and descendants (Level 3) |

#### Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `insertBefore` | newChild, refChild | Node | Insert before reference child |
| `replaceChild` | newChild, oldChild | Node | Replace existing child |
| `removeChild` | oldChild | Node | Remove child node |
| `appendChild` | newChild | Node | Append to children |
| `hasChildNodes` | - | boolean | True if has children |
| `cloneNode` | deep | Node | Clone node (deep = include descendants) |
| `normalize` | - | void | Merge adjacent text nodes |
| `isSupported` | feature, version | boolean | Feature support check (Level 2) |
| `hasAttributes` | - | boolean | True if has attributes (Level 2) |
| `compareDocumentPosition` | other | unsigned short | Document order comparison (Level 3) |
| `isSameNode` | other | boolean | Identity comparison (Level 3) |
| `isEqualNode` | arg | boolean | Equality comparison (Level 3) |
| `lookupPrefix` | namespaceURI | String | Find prefix for namespace (Level 3) |
| `lookupNamespaceURI` | prefix | String | Find namespace for prefix (Level 3) |
| `isDefaultNamespace` | namespaceURI | boolean | Check if default namespace (Level 3) |
| `setUserData` | key, data, handler | DOMUserData | Attach user data (Level 3) |
| `getUserData` | key | DOMUserData | Retrieve user data (Level 3) |

### Document Interface

Factory for creating nodes and root of the document tree.

#### Properties

| Property | Type | Access | Description |
|----------|------|--------|-------------|
| `doctype` | DocumentType | readonly | Document type declaration |
| `implementation` | DOMImplementation | readonly | DOM implementation |
| `documentElement` | Element | readonly | Root element |
| `inputEncoding` | String | readonly | Input encoding (Level 3) |
| `xmlEncoding` | String | readonly | XML encoding declaration (Level 3) |
| `xmlStandalone` | boolean | read/write | Standalone declaration (Level 3) |
| `xmlVersion` | String | read/write | XML version (Level 3) |
| `strictErrorChecking` | boolean | read/write | Error checking mode (Level 3) |
| `documentURI` | String | read/write | Document URI (Level 3) |

#### Factory Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `createElement` | tagName | Element | Create element |
| `createDocumentFragment` | - | DocumentFragment | Create fragment |
| `createTextNode` | data | Text | Create text node |
| `createComment` | data | Comment | Create comment |
| `createCDATASection` | data | CDATASection | Create CDATA section |
| `createProcessingInstruction` | target, data | ProcessingInstruction | Create PI |
| `createAttribute` | name | Attr | Create attribute |
| `createEntityReference` | name | EntityReference | Create entity ref |
| `createElementNS` | namespaceURI, qualifiedName | Element | Create with namespace (Level 2) |
| `createAttributeNS` | namespaceURI, qualifiedName | Attr | Create with namespace (Level 2) |

#### Query Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getElementsByTagName` | tagname | NodeList | Find by tag name |
| `getElementsByTagNameNS` | namespaceURI, localName | NodeList | Find by namespace (Level 2) |
| `getElementById` | elementId | Element | Find by ID (Level 2) |

#### Manipulation Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `importNode` | importedNode, deep | Node | Import from another document (Level 2) |
| `adoptNode` | source | Node | Adopt from another document (Level 3) |
| `normalizeDocument` | - | void | Normalize entire document (Level 3) |
| `renameNode` | n, namespaceURI, qualifiedName | Node | Rename node (Level 3) |

### Element Interface

Represents an XML element.

#### Properties

| Property | Type | Access | Description |
|----------|------|--------|-------------|
| `tagName` | String | readonly | Element tag name |
| `schemaTypeInfo` | TypeInfo | readonly | Schema type info (Level 3) |

#### Attribute Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getAttribute` | name | String | Get attribute value |
| `setAttribute` | name, value | void | Set attribute value |
| `removeAttribute` | name | void | Remove attribute |
| `getAttributeNode` | name | Attr | Get attribute node |
| `setAttributeNode` | newAttr | Attr | Set attribute node |
| `removeAttributeNode` | oldAttr | Attr | Remove attribute node |
| `hasAttribute` | name | boolean | Check attribute exists (Level 2) |
| `getAttributeNS` | namespaceURI, localName | String | Get with namespace (Level 2) |
| `setAttributeNS` | namespaceURI, qualifiedName, value | void | Set with namespace (Level 2) |
| `removeAttributeNS` | namespaceURI, localName | void | Remove with namespace (Level 2) |
| `getAttributeNodeNS` | namespaceURI, localName | Attr | Get node with namespace (Level 2) |
| `setAttributeNodeNS` | newAttr | Attr | Set node with namespace (Level 2) |
| `hasAttributeNS` | namespaceURI, localName | boolean | Check with namespace (Level 2) |
| `setIdAttribute` | name, isId | void | Mark as ID (Level 3) |
| `setIdAttributeNS` | namespaceURI, localName, isId | void | Mark as ID (Level 3) |

### Attr Interface

Represents an attribute.

#### Properties

| Property | Type | Access | Description |
|----------|------|--------|-------------|
| `name` | String | readonly | Attribute name |
| `specified` | boolean | readonly | True if explicitly set |
| `value` | String | read/write | Attribute value |
| `ownerElement` | Element | readonly | Owning element (Level 2) |
| `schemaTypeInfo` | TypeInfo | readonly | Schema type (Level 3) |
| `isId` | boolean | readonly | True if ID attribute (Level 3) |

### CharacterData Interface

Base for Text, Comment, CDATASection.

#### Properties

| Property | Type | Access | Description |
|----------|------|--------|-------------|
| `data` | String | read/write | Character data |
| `length` | unsigned long | readonly | Length in characters |

#### Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `substringData` | offset, count | String | Extract substring |
| `appendData` | arg | void | Append to data |
| `insertData` | offset, arg | void | Insert at offset |
| `deleteData` | offset, count | void | Delete range |
| `replaceData` | offset, count, arg | void | Replace range |

### Text Interface

Extends CharacterData.

#### Properties (Level 3)

| Property | Type | Description |
|----------|------|-------------|
| `isElementContentWhitespace` | boolean | True if ignorable whitespace |
| `wholeText` | String | All adjacent text |

#### Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `splitText` | offset | Text | Split into two nodes |
| `replaceWholeText` | content | Text | Replace all adjacent text (Level 3) |

### ProcessingInstruction Interface

#### Properties

| Property | Type | Access | Description |
|----------|------|--------|-------------|
| `target` | String | readonly | PI target |
| `data` | String | read/write | PI data |

### DocumentType Interface

#### Properties

| Property | Type | Access | Description |
|----------|------|--------|-------------|
| `name` | String | readonly | Document type name |
| `entities` | NamedNodeMap | readonly | General entities |
| `notations` | NamedNodeMap | readonly | Notations |
| `publicId` | String | readonly | Public identifier (Level 2) |
| `systemId` | String | readonly | System identifier (Level 2) |
| `internalSubset` | String | readonly | Internal subset text (Level 2) |

### NodeList Interface

Ordered collection of nodes.

| Method/Property | Type | Description |
|-----------------|------|-------------|
| `length` | unsigned long | Number of nodes |
| `item(index)` | Node | Node at index |

### NamedNodeMap Interface

Collection of nodes accessed by name.

| Method/Property | Parameters | Returns | Description |
|-----------------|------------|---------|-------------|
| `length` | - | unsigned long | Number of nodes |
| `item` | index | Node | Node at index |
| `getNamedItem` | name | Node | Get by name |
| `setNamedItem` | arg | Node | Add/replace node |
| `removeNamedItem` | name | Node | Remove by name |
| `getNamedItemNS` | namespaceURI, localName | Node | Get with namespace (Level 2) |
| `setNamedItemNS` | arg | Node | Add/replace with namespace (Level 2) |
| `removeNamedItemNS` | namespaceURI, localName | Node | Remove with namespace (Level 2) |

---

## SAX - Simple API for XML

**Specification:** SAX 2.0 (de facto standard)
**Reference:** https://docs.oracle.com/javase/8/docs/api/org/xml/sax/package-summary.html

SAX is an event-driven, push-based API. The parser calls handler methods as it
encounters XML constructs. SAX is memory-efficient for large documents.

### Core Interfaces

#### ContentHandler

The main interface for receiving document content events.

| Method | Parameters | Description |
|--------|------------|-------------|
| `setDocumentLocator` | Locator locator | Receive location information provider |
| `startDocument` | - | Document parsing started |
| `endDocument` | - | Document parsing ended |
| `startPrefixMapping` | String prefix, String uri | Namespace scope begins |
| `endPrefixMapping` | String prefix | Namespace scope ends |
| `startElement` | String uri, String localName, String qName, Attributes atts | Element opened |
| `endElement` | String uri, String localName, String qName | Element closed |
| `characters` | char[] ch, int start, int length | Character data |
| `ignorableWhitespace` | char[] ch, int start, int length | Ignorable whitespace |
| `processingInstruction` | String target, String data | Processing instruction |
| `skippedEntity` | String name | Entity was skipped |

##### startElement Parameters

- `uri`: Namespace URI (empty string if none or namespace processing disabled)
- `localName`: Local name without prefix (empty if namespace processing disabled)
- `qName`: Qualified name with prefix (empty if not available)
- `atts`: Attributes collection

##### characters Notes

- Parser may split text into multiple `characters` calls
- All characters in one call come from the same external entity
- May include surrogate pairs and composite characters

#### ErrorHandler

Handles parse errors and warnings.

| Method | Parameters | Description |
|--------|------------|-------------|
| `warning` | SAXParseException exception | Non-fatal warning |
| `error` | SAXParseException exception | Recoverable error (e.g., validity error) |
| `fatalError` | SAXParseException exception | Non-recoverable error (well-formedness) |

##### Error Severity

- **Warning**: Parser continues normally
- **Error**: Parser continues, but document may be invalid
- **Fatal Error**: Parser stops; document is unusable

#### DTDHandler

Receives DTD-related events.

| Method | Parameters | Description |
|--------|------------|-------------|
| `notationDecl` | String name, String publicId, String systemId | Notation declared |
| `unparsedEntityDecl` | String name, String publicId, String systemId, String notationName | Unparsed entity declared |

#### EntityResolver

Resolves external entities.

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `resolveEntity` | String publicId, String systemId | InputSource | Provide custom entity resolution |

Returns `null` to use default resolution (open system ID as URL).

#### XMLReader

Main parser interface for SAX2.

##### Feature/Property Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getFeature` | String name | boolean | Get feature value |
| `setFeature` | String name, boolean value | void | Set feature value |
| `getProperty` | String name | Object | Get property value |
| `setProperty` | String name, Object value | void | Set property value |

##### Handler Registration

| Method | Parameters | Description |
|--------|------------|-------------|
| `setContentHandler` | ContentHandler handler | Register content handler |
| `getContentHandler` | - | Get content handler |
| `setErrorHandler` | ErrorHandler handler | Register error handler |
| `getErrorHandler` | - | Get error handler |
| `setDTDHandler` | DTDHandler handler | Register DTD handler |
| `getDTDHandler` | - | Get DTD handler |
| `setEntityResolver` | EntityResolver resolver | Register entity resolver |
| `getEntityResolver` | - | Get entity resolver |

##### Parsing

| Method | Parameters | Description |
|--------|------------|-------------|
| `parse` | InputSource input | Parse from InputSource |
| `parse` | String systemId | Parse from system ID (URI) |

##### Standard Features

| Feature URI | Default | Description |
|-------------|---------|-------------|
| `http://xml.org/sax/features/namespaces` | true | Enable namespace processing |
| `http://xml.org/sax/features/namespace-prefixes` | false | Report xmlns attributes |
| `http://xml.org/sax/features/validation` | false | Enable validation |

### Helper Interfaces

#### Locator

Provides document location information.

| Method | Returns | Description |
|--------|---------|-------------|
| `getPublicId` | String | Public identifier or null |
| `getSystemId` | String | System identifier (fully resolved) or null |
| `getLineNumber` | int | Line number (1-based) or -1 |
| `getColumnNumber` | int | Column number (1-based) or -1 |

#### Attributes

Collection of element attributes.

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getLength` | - | int | Number of attributes |
| `getURI` | int index | String | Namespace URI at index |
| `getLocalName` | int index | String | Local name at index |
| `getQName` | int index | String | Qualified name at index |
| `getType` | int index | String | Type at index (CDATA, ID, etc.) |
| `getValue` | int index | String | Value at index |
| `getIndex` | String uri, String localName | int | Find by namespace name |
| `getIndex` | String qName | int | Find by qualified name |
| `getType` | String uri, String localName | String | Type by namespace name |
| `getType` | String qName | String | Type by qualified name |
| `getValue` | String uri, String localName | String | Value by namespace name |
| `getValue` | String qName | String | Value by qualified name |

### Extension Interfaces

#### LexicalHandler

Optional handler for lexical events.

Property: `http://xml.org/sax/properties/lexical-handler`

| Method | Parameters | Description |
|--------|------------|-------------|
| `startDTD` | String name, String publicId, String systemId | DTD begins |
| `endDTD` | - | DTD ends |
| `startEntity` | String name | Entity expansion begins |
| `endEntity` | String name | Entity expansion ends |
| `startCDATA` | - | CDATA section begins |
| `endCDATA` | - | CDATA section ends |
| `comment` | char[] ch, int start, int length | Comment content |

---

## StAX - Streaming API for XML

**Specification:** JSR-173 (Java Community Process)
**Reference:** https://docs.oracle.com/javase/8/docs/api/javax/xml/stream/package-summary.html

StAX is a pull-based streaming API. The application controls when to advance
the parser and retrieve events. Provides both cursor and iterator APIs.

### Event Types

```
START_ELEMENT       = 1
END_ELEMENT         = 2
PROCESSING_INSTRUCTION = 3
CHARACTERS          = 4
COMMENT             = 5
SPACE               = 6   (ignorable whitespace)
START_DOCUMENT      = 7
END_DOCUMENT        = 8
ENTITY_REFERENCE    = 9
ATTRIBUTE           = 10
DTD                 = 11
CDATA               = 12
NAMESPACE           = 13
NOTATION_DECLARATION = 14
ENTITY_DECLARATION  = 15
```

### Cursor API

#### XMLStreamReader

Low-level, cursor-based reading interface.

##### Navigation Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `next` | int | Advance to next event, return event type |
| `hasNext` | boolean | True if more events available |
| `getEventType` | int | Current event type |
| `nextTag` | int | Skip whitespace/comments/PIs to next element |
| `require` | void | Validate current state (throws if mismatch) |

##### Element Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `getLocalName` | String | Element local name |
| `getName` | QName | Element QName |
| `getNamespaceURI` | String | Element namespace URI |
| `getPrefix` | String | Element prefix |
| `hasName` | boolean | True if START_ELEMENT or END_ELEMENT |
| `isStartElement` | boolean | True if START_ELEMENT |
| `isEndElement` | boolean | True if END_ELEMENT |

##### Text Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `getText` | String | Text content of current event |
| `getTextCharacters` | char[] | Character array (transient) |
| `getTextStart` | int | Start offset in array |
| `getTextLength` | int | Length in array |
| `getElementText` | String | Read text-only element content |
| `hasText` | boolean | True if current event has text |
| `isCharacters` | boolean | True if CHARACTERS event |
| `isWhiteSpace` | boolean | True if all whitespace |

##### Attribute Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getAttributeCount` | - | int | Number of attributes |
| `getAttributeName` | int index | QName | Attribute QName |
| `getAttributeLocalName` | int index | String | Attribute local name |
| `getAttributeNamespace` | int index | String | Attribute namespace |
| `getAttributePrefix` | int index | String | Attribute prefix |
| `getAttributeType` | int index | String | Attribute type |
| `getAttributeValue` | int index | String | Attribute value |
| `getAttributeValue` | String namespaceURI, String localName | String | Find attribute value |
| `isAttributeSpecified` | int index | boolean | True if not defaulted |

##### Namespace Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getNamespaceCount` | - | int | Namespace declarations on current element |
| `getNamespacePrefix` | int index | String | Prefix at index (null for default) |
| `getNamespaceURI` | int index | String | URI at index |
| `getNamespaceURI` | String prefix | String | Look up prefix binding |
| `getNamespaceContext` | - | NamespaceContext | Current namespace context (transient) |

##### Document Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `getVersion` | String | XML version (e.g., "1.0") |
| `getEncoding` | String | Detected encoding |
| `getCharacterEncodingScheme` | String | Declared encoding |
| `isStandalone` | boolean | Standalone declaration value |
| `standaloneSet` | boolean | True if standalone was declared |

##### Processing Instruction Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `getPITarget` | String | PI target |
| `getPIData` | String | PI data |

##### Location and Resource Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `getLocation` | Location | Current location (transient) |
| `getProperty` | Object | Reader property value |
| `close` | void | Release resources |

##### Valid Methods by Event Type

| Event | Valid Methods |
|-------|---------------|
| START_ELEMENT | getName, getLocalName, getPrefix, getNamespaceURI, getAttributeXXX, getNamespaceXXX, getElementText |
| END_ELEMENT | getName, getLocalName, getPrefix, getNamespaceURI, getNamespaceXXX |
| CHARACTERS, CDATA, COMMENT, SPACE | getTextXXX |
| START_DOCUMENT | getVersion, getEncoding, getCharacterEncodingScheme, isStandalone, standaloneSet |
| PROCESSING_INSTRUCTION | getPITarget, getPIData |
| DTD | getText |
| All events | getEventType, hasNext, next, getLocation, getProperty, close |

#### XMLStreamWriter

Cursor-based writing interface.

##### Document Methods

| Method | Parameters | Description |
|--------|------------|-------------|
| `writeStartDocument` | - | Write default XML declaration |
| `writeStartDocument` | String version | Write with version |
| `writeStartDocument` | String encoding, String version | Write with encoding and version |
| `writeEndDocument` | - | Close all open elements |

##### Element Methods

| Method | Parameters | Description |
|--------|------------|-------------|
| `writeStartElement` | String localName | Start element |
| `writeStartElement` | String namespaceURI, String localName | Start with namespace |
| `writeStartElement` | String prefix, String localName, String namespaceURI | Start with prefix |
| `writeEndElement` | - | End current element |
| `writeEmptyElement` | String localName | Self-closing element |
| `writeEmptyElement` | String namespaceURI, String localName | Self-closing with namespace |
| `writeEmptyElement` | String prefix, String localName, String namespaceURI | Self-closing with prefix |

##### Attribute Methods

| Method | Parameters | Description |
|--------|------------|-------------|
| `writeAttribute` | String localName, String value | Write attribute |
| `writeAttribute` | String namespaceURI, String localName, String value | Write with namespace |
| `writeAttribute` | String prefix, String namespaceURI, String localName, String value | Write with prefix |

##### Namespace Methods

| Method | Parameters | Description |
|--------|------------|-------------|
| `writeNamespace` | String prefix, String namespaceURI | Write namespace declaration |
| `writeDefaultNamespace` | String namespaceURI | Write default namespace |
| `setPrefix` | String prefix, String uri | Set prefix binding |
| `setDefaultNamespace` | String uri | Set default namespace |
| `setNamespaceContext` | NamespaceContext context | Set namespace context |
| `getPrefix` | String uri | Get prefix for namespace |
| `getNamespaceContext` | - | Get namespace context |

##### Content Methods

| Method | Parameters | Description |
|--------|------------|-------------|
| `writeCharacters` | String text | Write text (escapes &, <, >) |
| `writeCharacters` | char[] text, int start, int len | Write from array |
| `writeCData` | String data | Write CDATA section |
| `writeComment` | String data | Write comment |
| `writeProcessingInstruction` | String target | Write PI |
| `writeProcessingInstruction` | String target, String data | Write PI with data |
| `writeDTD` | String dtd | Write DTD |
| `writeEntityRef` | String name | Write entity reference |

##### Resource Methods

| Method | Description |
|--------|-------------|
| `flush` | Flush output |
| `close` | Close writer |
| `getProperty` | Get property value |

### Iterator API

Higher-level, object-oriented API using XMLEvent objects.

#### XMLEvent Interface

Base interface for all event types.

| Method | Returns | Description |
|--------|---------|-------------|
| `getEventType` | int | Event type constant |
| `getLocation` | Location | Event location |
| `isStartElement` | boolean | Type check |
| `isEndElement` | boolean | Type check |
| `isCharacters` | boolean | Type check |
| `isAttribute` | boolean | Type check |
| `isNamespace` | boolean | Type check |
| `asStartElement` | StartElement | Cast to StartElement |
| `asEndElement` | EndElement | Cast to EndElement |
| `asCharacters` | Characters | Cast to Characters |
| `writeAsEncodedUnicode` | void | Write as XML text |

#### Event Subtypes

| Interface | Description |
|-----------|-------------|
| `StartElement` | Element start with name and attributes |
| `EndElement` | Element end with name |
| `Characters` | Text content (also for CDATA) |
| `Attribute` | Single attribute |
| `Namespace` | Namespace declaration |
| `Comment` | Comment text |
| `ProcessingInstruction` | PI target and data |
| `StartDocument` | Document start with version/encoding |
| `EndDocument` | Document end |
| `DTD` | DTD content |
| `EntityReference` | Entity reference |
| `EntityDeclaration` | Entity declaration |
| `NotationDeclaration` | Notation declaration |

#### XMLEventReader

Iterator-based reading.

| Method | Returns | Description |
|--------|---------|-------------|
| `nextEvent` | XMLEvent | Get next event |
| `hasNext` | boolean | More events available |
| `peek` | XMLEvent | Look at next without consuming |
| `getElementText` | String | Read text-only element |
| `nextTag` | XMLEvent | Skip to next element |
| `getProperty` | Object | Get property |
| `close` | void | Release resources |

#### XMLEventWriter

Iterator-based writing.

| Method | Parameters | Description |
|--------|------------|-------------|
| `add` | XMLEvent event | Write event |
| `add` | Attribute attribute | Write attribute |
| `add` | Namespace namespace | Write namespace |
| `setDefaultNamespace` | String uri | Set default namespace |
| `setNamespaceContext` | NamespaceContext context | Set context |
| `setPrefix` | String prefix, String uri | Set prefix |
| `getNamespaceContext` | - | Get context |
| `getPrefix` | String uri | Get prefix |
| `flush` | - | Flush output |
| `close` | - | Close writer |

---

## API Comparison

### Memory and Performance

| Aspect | DOM | SAX | StAX |
|--------|-----|-----|------|
| Memory usage | High (full tree) | Very low | Very low |
| Parse speed | Slower | Fast | Fast |
| Random access | Yes | No | No |
| Forward only | No | Yes | Yes |
| Write support | Yes (modify tree) | No | Yes |
| Ease of use | High | Medium | Medium-High |

### Feature Comparison

| Feature | DOM | SAX | StAX |
|---------|-----|-----|------|
| Namespace support | Yes | Yes | Yes |
| Validation | Yes | Yes | Optional |
| XPath support | Yes (Level 3) | No | No |
| Entity resolution | Yes | Yes | Yes |
| DTD handling | Yes | Yes | Yes |
| Schema type info | Level 3 | No | No |

### When to Use Each

**DOM:**
- Small to medium documents
- Need to modify document
- Need random access
- Need XPath queries
- Building documents programmatically

**SAX:**
- Large documents (streaming)
- Read-only processing
- Simple filtering/extraction
- Memory-constrained environments
- Processing speed critical

**StAX:**
- Large documents (streaming)
- Need pull-based control
- Building/writing XML
- State-machine processing
- Pipeline architectures

---

## Elixir Adaptation Notes

### Mapping to Elixir Idioms

#### DOM Adaptation

```elixir
# DOM nodes as structs with parent/child references
defmodule FnXML.API.DOM.Node do
  defstruct [:node_type, :node_name, :node_value, :parent, :children,
             :attributes, :namespace_uri, :prefix, :local_name]
end

# Or using zipper for navigation
defmodule FnXML.API.DOM.Zipper do
  # Efficient tree navigation without mutable references
end
```

#### SAX Adaptation (Current FnXML Approach)

FnXML already uses a SAX-like streaming approach:

```elixir
# Current FnXML events map to SAX (W3C StAX-compatible names):
{:start_element, tag, attrs, loc}        # -> startElement
{:end_element, tag, loc}                 # -> endElement
{:characters, content, loc}              # -> characters
{:comment, content, loc}                 # -> comment (LexicalHandler)
{:prolog, target, attrs, loc}            # -> startDocument + processingInstruction
{:processing_instruction, target, data, loc}  # -> processingInstruction
{:dtd, content, loc}                     # -> startDTD (LexicalHandler)
{:cdata, content, loc}                   # -> startCDATA + characters + endCDATA
{:error, reason, loc}                    # -> error/fatalError
```

#### StAX Adaptation

```elixir
# StAX cursor API as Stream with state
defmodule FnXML.API.StAX.Reader do
  defstruct [:stream, :event, :location, :context]

  def next(%Reader{} = reader), do: ...
  def has_next?(%Reader{} = reader), do: ...
  def get_event_type(%Reader{} = reader), do: ...
end

# StAX writer
defmodule FnXML.API.StAX.Writer do
  def start_document(writer, opts \\ []), do: ...
  def start_element(writer, name, opts \\ []), do: ...
  def end_element(writer), do: ...
  def write_characters(writer, text), do: ...
end
```

### Event Type Mapping

| SAX/StAX Event | FnXML Event | Notes |
|----------------|-------------|-------|
| startDocument | `:prolog` / `:start_document` | XML declaration |
| endDocument | `:end_document` | End of stream |
| startElement | `:start_element` | `{:start_element, tag, attrs, loc}` |
| endElement | `:end_element` | `{:end_element, tag, loc}` |
| characters | `:characters` | Character content |
| ignorableWhitespace | `:characters` | Same as characters |
| comment | `:comment` | Comment content |
| processingInstruction | `:processing_instruction` | PI target and data |
| startCDATA/endCDATA | `:cdata` | FnXML has single event |
| startDTD/endDTD | `:dtd` | FnXML has single event |
| entityReference | (resolved) | FnXML resolves entities |
| startPrefixMapping | (in `:start_element`) | Namespace attrs on element |
| endPrefixMapping | (in `:end_element`) | Implicit with element close |

### Namespace Integration

FnXML's `FnXML.Namespaces` module provides:

- `Context` - Namespace scope management (like SAX's prefix mapping)
- `Resolver` - Expand names to `{uri, local_name}` tuples
- `Validator` - Check namespace constraint violations

### Recommended Implementation Priority

1. **Complete StAX-style Writer** - Build on current stream infrastructure
2. **DOM Tree Builder** - Use streams to construct tree
3. **DOM Tree API** - Navigation and manipulation
4. **DOM Serializer** - Tree to stream/text conversion
5. **Higher-level APIs** - Builder patterns, XPath, etc.

---

## Implementation Plan for FnXML

### Current State Assessment

FnXML currently provides:

- **Parser** (`FnXML.Parser`, `FnXML.ParserStream`) - SAX-like event stream
- **DTD** (`FnXML.DTD`) - DTD parsing and entity resolution
- **Namespaces** (`FnXML.Namespaces`) - Namespace validation and resolution
- **Stream Processors** - Entity resolution, validation, normalization

### Phase 1: StAX Writer API

**Goal:** Provide a streaming XML writer that complements the parser.

#### Module: `FnXML.Writer`

```elixir
defmodule FnXML.Writer do
  @moduledoc """
  Streaming XML writer with StAX-style cursor API.
  """

  defstruct [:output, :stack, :state, :options, :namespace_context]

  # Lifecycle
  def new(opts \\ [])
  def to_string(writer)
  def to_iodata(writer)

  # Document
  def start_document(writer, opts \\ [])
  def end_document(writer)

  # Elements
  def start_element(writer, name)
  def start_element(writer, namespace_uri, local_name)
  def start_element(writer, prefix, local_name, namespace_uri)
  def end_element(writer)
  def empty_element(writer, name)

  # Attributes (must be called after start_element, before content)
  def attribute(writer, name, value)
  def attribute(writer, namespace_uri, local_name, value)

  # Namespaces
  def namespace(writer, prefix, uri)
  def default_namespace(writer, uri)

  # Content
  def characters(writer, text)
  def cdata(writer, text)
  def comment(writer, text)
  def processing_instruction(writer, target, data \\ nil)

  # DTD
  def dtd(writer, name, public_id \\ nil, system_id \\ nil)
end
```

#### Implementation Details

- Use iodata accumulation for efficiency
- Track element stack for proper nesting
- Validate state transitions (e.g., attributes only after start_element)
- Auto-escape special characters in text and attributes
- Support namespace prefix management

#### Tests

- Well-formed output generation
- Namespace handling
- Character escaping
- Round-trip (parse then write)

### Phase 2: DOM Tree Structure

**Goal:** Define DOM node structures and basic operations.

#### Module: `FnXML.API.DOM`

```elixir
defmodule FnXML.API.DOM do
  @moduledoc """
  Document Object Model for XML.
  """

  # Node type constants
  @element_node 1
  @attribute_node 2
  @text_node 3
  @cdata_section_node 4
  @entity_reference_node 5
  @processing_instruction_node 7
  @comment_node 8
  @document_node 9
  @document_type_node 10
  @document_fragment_node 11
end
```

#### Module: `FnXML.API.DOM.Node`

```elixir
defmodule FnXML.API.DOM.Node do
  @moduledoc """
  Base structure for all DOM nodes.
  """

  @type t :: %__MODULE__{
    node_type: pos_integer(),
    node_name: String.t(),
    node_value: String.t() | nil,
    namespace_uri: String.t() | nil,
    prefix: String.t() | nil,
    local_name: String.t() | nil,
    parent: reference() | nil,
    children: [reference()],
    attributes: %{String.t() => FnXML.API.DOM.Attr.t()},
    owner_document: reference() | nil
  }

  defstruct [
    :node_type, :node_name, :node_value,
    :namespace_uri, :prefix, :local_name,
    :parent, :children, :attributes, :owner_document
  ]
end
```

#### Module: `FnXML.API.DOM.Document`

```elixir
defmodule FnXML.API.DOM.Document do
  @moduledoc """
  XML Document node and factory methods.
  """

  defstruct [
    :doctype,
    :document_element,
    :xml_version,
    :xml_encoding,
    :xml_standalone,
    :base_uri,
    nodes: %{}  # id => node map for reference resolution
  ]

  # Factory methods
  def create_element(doc, tag_name)
  def create_element_ns(doc, namespace_uri, qualified_name)
  def create_text_node(doc, data)
  def create_comment(doc, data)
  def create_cdata_section(doc, data)
  def create_processing_instruction(doc, target, data)
  def create_attribute(doc, name)
  def create_attribute_ns(doc, namespace_uri, qualified_name)
  def create_document_fragment(doc)

  # Query methods
  def get_element_by_id(doc, element_id)
  def get_elements_by_tag_name(doc, tag_name)
  def get_elements_by_tag_name_ns(doc, namespace_uri, local_name)
end
```

#### Module: `FnXML.API.DOM.Element`

```elixir
defmodule FnXML.API.DOM.Element do
  @moduledoc """
  Element node with attribute operations.
  """

  # Attribute operations
  def get_attribute(element, name)
  def set_attribute(element, name, value)
  def remove_attribute(element, name)
  def has_attribute(element, name)
  def get_attribute_ns(element, namespace_uri, local_name)
  def set_attribute_ns(element, namespace_uri, qualified_name, value)
  def remove_attribute_ns(element, namespace_uri, local_name)
  def has_attribute_ns(element, namespace_uri, local_name)

  # Query
  def get_elements_by_tag_name(element, name)
  def get_elements_by_tag_name_ns(element, namespace_uri, local_name)
end
```

### Phase 3: DOM Builder (Stream to Tree)

**Goal:** Build DOM tree from parser event stream.

#### Module: `FnXML.API.DOM.Builder`

```elixir
defmodule FnXML.API.DOM.Builder do
  @moduledoc """
  Build DOM tree from XML event stream.
  """

  def build(stream, opts \\ [])
  def build!(stream, opts \\ [])

  # Convenience
  def parse(xml_string, opts \\ [])
  def parse!(xml_string, opts \\ [])
end
```

#### Implementation Strategy

1. Process events sequentially
2. Maintain stack of open elements
3. On `:start_element` - create element, push to stack
4. On `:end_element` - pop stack, attach to parent
5. On `:characters`, `:comment`, etc. - create node, attach to current element
6. Handle namespace context
7. Build attribute nodes
8. Return complete Document

### Phase 4: DOM Serializer (Tree to Stream/Text)

**Goal:** Convert DOM tree back to XML text or event stream.

#### Module: `FnXML.API.DOM.Serializer`

```elixir
defmodule FnXML.API.DOM.Serializer do
  @moduledoc """
  Serialize DOM tree to XML.
  """

  # To string
  def to_string(node, opts \\ [])

  # To iodata (more efficient)
  def to_iodata(node, opts \\ [])

  # To event stream (for pipeline processing)
  def to_stream(node, opts \\ [])

  # Options:
  # - :indent - pretty print with indentation
  # - :encoding - output encoding
  # - :xml_declaration - include <?xml ...?>
  # - :standalone - standalone declaration
end
```

### Phase 5: DOM Navigation (Zipper)

**Goal:** Efficient tree navigation without mutable parent references.

#### Module: `FnXML.API.DOM.Zipper`

```elixir
defmodule FnXML.API.DOM.Zipper do
  @moduledoc """
  Zipper-based navigation for DOM trees.

  Provides efficient navigation and local updates without
  requiring mutable parent references.
  """

  defstruct [:focus, :path, :lefts, :rights]

  # Navigation
  def down(zipper)      # Move to first child
  def up(zipper)        # Move to parent
  def left(zipper)      # Move to previous sibling
  def right(zipper)     # Move to next sibling
  def root(zipper)      # Move to document root

  # Access
  def node(zipper)      # Get current node
  def children(zipper)  # Get children of current node

  # Modification (returns new zipper)
  def replace(zipper, node)
  def insert_left(zipper, node)
  def insert_right(zipper, node)
  def insert_child(zipper, node)
  def append_child(zipper, node)
  def remove(zipper)

  # Traversal
  def next(zipper)      # Depth-first next
  def prev(zipper)      # Depth-first previous

  # Creation
  def from_document(document)
  def to_document(zipper)
end
```

### Phase 6: SAX-style Handler API

**Goal:** Provide explicit SAX handler interface for compatibility.

#### Module: `FnXML.API.SAX`

```elixir
defmodule FnXML.API.SAX do
  @moduledoc """
  SAX-style handler-based XML processing.
  """

  @callback start_document(state) :: {:ok, state} | {:error, term()}
  @callback end_document(state) :: {:ok, state} | {:error, term()}
  @callback start_element(uri, local_name, qname, attributes, state) ::
    {:ok, state} | {:error, term()}
  @callback end_element(uri, local_name, qname, state) ::
    {:ok, state} | {:error, term()}
  @callback characters(chars, state) :: {:ok, state} | {:error, term()}
  @callback ignorable_whitespace(chars, state) :: {:ok, state} | {:error, term()}
  @callback processing_instruction(target, data, state) ::
    {:ok, state} | {:error, term()}
  @callback comment(text, state) :: {:ok, state} | {:error, term()}
  @callback start_prefix_mapping(prefix, uri, state) :: {:ok, state} | {:error, term()}
  @callback end_prefix_mapping(prefix, state) :: {:ok, state} | {:error, term()}

  # Optional callbacks with defaults
  @optional_callbacks [
    ignorable_whitespace: 2,
    processing_instruction: 3,
    comment: 2,
    start_prefix_mapping: 3,
    end_prefix_mapping: 2
  ]

  def parse(xml, handler, initial_state, opts \\ [])
end
```

### Phase 7: High-Level APIs

#### Module: `FnXML.Builder` (Declarative XML Construction)

```elixir
defmodule FnXML.Builder do
  @moduledoc """
  Declarative XML construction DSL.
  """

  defmacro xml(do: block)
  defmacro element(name, attrs \\ [], do: content)
  defmacro text(value)
  defmacro comment(value)
  defmacro cdata(value)

  # Example usage:
  # xml do
  #   element :root, xmlns: "http://example.org" do
  #     element :child, id: "1" do
  #       text "Hello"
  #     end
  #   end
  # end
end
```

#### Module: `FnXML.Query` (XPath-lite)

```elixir
defmodule FnXML.Query do
  @moduledoc """
  Simple path-based queries on DOM trees.
  """

  def find(document, path)      # Find first match
  def find_all(document, path)  # Find all matches
  def select(document, path)    # Select with predicates

  # Path examples:
  # "/root/child"           - absolute path
  # "//element"             - descendant
  # "/root/child[@id='1']"  - with predicate
  # "/root/child/text()"    - text content
end
```

### Testing Strategy

#### Unit Tests

Each module should have comprehensive unit tests covering:
- Normal operation
- Edge cases
- Error conditions
- Namespace handling

#### Integration Tests

- Parse -> DOM -> Serialize round-trip
- Parse -> SAX Handler processing
- Writer output well-formedness
- Large document handling

#### Conformance Tests

- W3C DOM test suite (subset applicable to Elixir)
- Namespace conformance (existing tests)
- Character encoding tests

### Documentation

Each module should include:
- Module-level `@moduledoc` with examples
- Function-level `@doc` with specs
- Type specifications (`@type`, `@spec`)
- Usage examples in docs

### Performance Considerations

1. **Lazy Evaluation**: Use streams where possible
2. **Binary Optimization**: Use iodata for string building
3. **Memory**: Consider ETS for large DOM trees
4. **Profiling**: Benchmark critical paths

### Milestone Summary

| Phase | Deliverable | Dependencies |
|-------|-------------|--------------|
| 1 | StAX Writer | None |
| 2 | DOM Structures | None |
| 3 | DOM Builder | Phase 2, Parser |
| 4 | DOM Serializer | Phase 2, Writer |
| 5 | DOM Zipper | Phase 2 |
| 6 | SAX Handler | Parser |
| 7 | High-Level APIs | Phases 2-5 |
