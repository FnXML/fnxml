# SAML 2.0 Specification Reference

> **Source**: OASIS Security Services Technical Committee
> **Version**: SAML 2.0 (March 2005, Errata 2012)
> **Purpose**: LLM-friendly reference for implementing SAML in FnXML

---

## Table of Contents

1. [Overview](#1-overview)
2. [Core Components](#2-core-components)
3. [Assertions](#3-assertions)
4. [Protocols](#4-protocols)
5. [Bindings](#5-bindings)
6. [Profiles](#6-profiles)
7. [Metadata](#7-metadata)
8. [Security Considerations](#8-security-considerations)
9. [XML Schemas](#9-xml-schemas)
10. [Namespaces and URIs](#10-namespaces-and-uris)
11. [Implementation Checklist](#11-implementation-checklist)

---

## 1. Overview

### 1.1 What is SAML?

SAML (Security Assertion Markup Language) is an XML-based framework for exchanging authentication, attribute, and authorization data between:

- **Identity Provider (IdP)**: Authenticates users and issues assertions
- **Service Provider (SP)**: Consumes assertions to grant access

### 1.2 Primary Use Cases

| Use Case | Description |
|----------|-------------|
| Web Browser SSO | Single sign-on across domains |
| Single Logout | Coordinated session termination |
| Identity Federation | Link accounts across providers |
| Attribute Exchange | Share user attributes |

### 1.3 Architecture Layers

```
┌─────────────────────────────────────────┐
│            PROFILES                      │
│  (Web SSO, Single Logout, ECP, etc.)    │
├─────────────────────────────────────────┤
│            BINDINGS                      │
│  (HTTP-Redirect, HTTP-POST, SOAP, etc.) │
├─────────────────────────────────────────┤
│            PROTOCOLS                     │
│  (AuthnRequest, Response, Logout, etc.) │
├─────────────────────────────────────────┤
│            ASSERTIONS                    │
│  (Authentication, Attribute, AuthZ)     │
└─────────────────────────────────────────┘
```

---

## 2. Core Components

### 2.1 Assertions

XML statements about a subject (user) that an asserting party claims to be true.

**Three Statement Types**:
1. **Authentication Statement**: How/when the subject was authenticated
2. **Attribute Statement**: Subject's identifying characteristics
3. **Authorization Decision Statement**: What subject is permitted to do

### 2.2 Protocols

Request/response message exchanges:
- Authentication Request Protocol
- Single Logout Protocol
- Assertion Query/Request Protocol
- Artifact Resolution Protocol
- Name Identifier Management Protocol

### 2.3 Bindings

Transport mechanisms for SAML messages:
- HTTP Redirect Binding
- HTTP POST Binding
- HTTP Artifact Binding
- SOAP Binding
- PAOS (Reverse SOAP) Binding

### 2.4 Profiles

Constrained usage patterns for specific use cases:
- Web Browser SSO Profile
- Enhanced Client/Proxy (ECP) Profile
- Single Logout Profile
- Identity Provider Discovery Profile

---

## 3. Assertions

### 3.1 Assertion Structure

```xml
<saml:Assertion
    xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion"
    Version="2.0"
    ID="_assertion-id-123"
    IssueInstant="2024-01-15T10:30:00Z">

    <saml:Issuer>https://idp.example.com</saml:Issuer>

    <ds:Signature>...</ds:Signature>

    <saml:Subject>
        <saml:NameID Format="urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress">
            user@example.com
        </saml:NameID>
        <saml:SubjectConfirmation Method="urn:oasis:names:tc:SAML:2.0:cm:bearer">
            <saml:SubjectConfirmationData
                NotOnOrAfter="2024-01-15T10:35:00Z"
                Recipient="https://sp.example.com/acs"
                InResponseTo="_request-id-456"/>
        </saml:SubjectConfirmation>
    </saml:Subject>

    <saml:Conditions
        NotBefore="2024-01-15T10:30:00Z"
        NotOnOrAfter="2024-01-15T10:35:00Z">
        <saml:AudienceRestriction>
            <saml:Audience>https://sp.example.com</saml:Audience>
        </saml:AudienceRestriction>
    </saml:Conditions>

    <saml:AuthnStatement
        AuthnInstant="2024-01-15T10:29:00Z"
        SessionIndex="_session-123">
        <saml:AuthnContext>
            <saml:AuthnContextClassRef>
                urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport
            </saml:AuthnContextClassRef>
        </saml:AuthnContext>
    </saml:AuthnStatement>

    <saml:AttributeStatement>
        <saml:Attribute Name="email" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:basic">
            <saml:AttributeValue>user@example.com</saml:AttributeValue>
        </saml:Attribute>
        <saml:Attribute Name="role">
            <saml:AttributeValue>admin</saml:AttributeValue>
        </saml:Attribute>
    </saml:AttributeStatement>
</saml:Assertion>
```

### 3.2 Assertion Elements

| Element | Required | Description |
|---------|----------|-------------|
| `Issuer` | Yes | Entity that issued the assertion |
| `Signature` | Conditional | XML Signature (required for signed assertions) |
| `Subject` | Conditional | Principal the assertion is about |
| `Conditions` | No | Validity constraints |
| `Advice` | No | Additional information |
| `AuthnStatement` | Conditional | Authentication details |
| `AttributeStatement` | Conditional | Subject attributes |
| `AuthzDecisionStatement` | Conditional | Authorization decision |

### 3.3 Assertion Attributes

| Attribute | Required | Type | Description |
|-----------|----------|------|-------------|
| `Version` | Yes | string | Must be "2.0" |
| `ID` | Yes | xs:ID | Unique identifier |
| `IssueInstant` | Yes | xs:dateTime | Creation timestamp (UTC) |

### 3.4 Subject Element

```xml
<saml:Subject>
    <!-- One of: BaseID, NameID, EncryptedID -->
    <saml:NameID
        Format="..."
        SPProvidedID="..."
        NameQualifier="..."
        SPNameQualifier="...">
        identifier-value
    </saml:NameID>

    <!-- Zero or more SubjectConfirmation -->
    <saml:SubjectConfirmation Method="...">
        <saml:SubjectConfirmationData
            NotBefore="..."
            NotOnOrAfter="..."
            Recipient="..."
            InResponseTo="..."/>
    </saml:SubjectConfirmation>
</saml:Subject>
```

### 3.5 NameID Formats

| Format URI | Description |
|------------|-------------|
| `urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified` | Unspecified |
| `urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress` | Email address |
| `urn:oasis:names:tc:SAML:2.0:nameid-format:persistent` | Persistent pseudonym |
| `urn:oasis:names:tc:SAML:2.0:nameid-format:transient` | Transient (one-time) |
| `urn:oasis:names:tc:SAML:1.1:nameid-format:X509SubjectName` | X.509 subject name |
| `urn:oasis:names:tc:SAML:1.1:nameid-format:WindowsDomainQualifiedName` | Windows domain name |
| `urn:oasis:names:tc:SAML:2.0:nameid-format:kerberos` | Kerberos principal |
| `urn:oasis:names:tc:SAML:2.0:nameid-format:entity` | SAML entity ID |

### 3.6 Subject Confirmation Methods

| Method URI | Description |
|------------|-------------|
| `urn:oasis:names:tc:SAML:2.0:cm:bearer` | Bearer token (most common) |
| `urn:oasis:names:tc:SAML:2.0:cm:holder-of-key` | Must prove key possession |
| `urn:oasis:names:tc:SAML:2.0:cm:sender-vouches` | Attesting entity vouches |

### 3.7 Conditions Element

```xml
<saml:Conditions
    NotBefore="2024-01-15T10:30:00Z"
    NotOnOrAfter="2024-01-15T10:35:00Z">

    <saml:AudienceRestriction>
        <saml:Audience>https://sp.example.com</saml:Audience>
    </saml:AudienceRestriction>

    <saml:OneTimeUse/>

    <saml:ProxyRestriction Count="2">
        <saml:Audience>https://proxy.example.com</saml:Audience>
    </saml:ProxyRestriction>
</saml:Conditions>
```

### 3.8 Authentication Statement

```xml
<saml:AuthnStatement
    AuthnInstant="2024-01-15T10:29:00Z"
    SessionIndex="_session-123"
    SessionNotOnOrAfter="2024-01-15T18:29:00Z">

    <saml:SubjectLocality
        Address="192.168.1.100"
        DNSName="client.example.com"/>

    <saml:AuthnContext>
        <saml:AuthnContextClassRef>
            urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport
        </saml:AuthnContextClassRef>
    </saml:AuthnContext>
</saml:AuthnStatement>
```

### 3.9 Authentication Context Classes

| Context Class URI | Description |
|-------------------|-------------|
| `urn:oasis:names:tc:SAML:2.0:ac:classes:unspecified` | Unspecified |
| `urn:oasis:names:tc:SAML:2.0:ac:classes:Password` | Password |
| `urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport` | Password over TLS |
| `urn:oasis:names:tc:SAML:2.0:ac:classes:X509` | X.509 certificate |
| `urn:oasis:names:tc:SAML:2.0:ac:classes:Smartcard` | Smartcard |
| `urn:oasis:names:tc:SAML:2.0:ac:classes:Kerberos` | Kerberos |
| `urn:oasis:names:tc:SAML:2.0:ac:classes:TLSClient` | TLS client certificate |
| `urn:oasis:names:tc:SAML:2.0:ac:classes:MobileTwoFactorContract` | Mobile 2FA |

### 3.10 Attribute Statement

```xml
<saml:AttributeStatement>
    <saml:Attribute
        Name="email"
        NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:basic"
        FriendlyName="Email Address">
        <saml:AttributeValue xsi:type="xs:string">
            user@example.com
        </saml:AttributeValue>
    </saml:Attribute>

    <saml:Attribute Name="groups">
        <saml:AttributeValue>admins</saml:AttributeValue>
        <saml:AttributeValue>developers</saml:AttributeValue>
    </saml:Attribute>
</saml:AttributeStatement>
```

### 3.11 Attribute Name Formats

| Format URI | Description |
|------------|-------------|
| `urn:oasis:names:tc:SAML:2.0:attrname-format:unspecified` | Unspecified |
| `urn:oasis:names:tc:SAML:2.0:attrname-format:uri` | URI-based name |
| `urn:oasis:names:tc:SAML:2.0:attrname-format:basic` | Basic string name |

---

## 4. Protocols

### 4.1 Common Request Attributes

All protocol requests extend `RequestAbstractType`:

| Attribute | Required | Type | Description |
|-----------|----------|------|-------------|
| `ID` | Yes | xs:ID | Unique request identifier |
| `Version` | Yes | string | Must be "2.0" |
| `IssueInstant` | Yes | xs:dateTime | Request creation time |
| `Destination` | No | xs:anyURI | Intended recipient |
| `Consent` | No | xs:anyURI | Consent indicator |

Common child elements:
- `saml:Issuer` (optional)
- `ds:Signature` (optional)
- `samlp:Extensions` (optional)

### 4.2 Common Response Attributes

All responses extend `StatusResponseType`:

| Attribute | Required | Type | Description |
|-----------|----------|------|-------------|
| `ID` | Yes | xs:ID | Unique response identifier |
| `Version` | Yes | string | Must be "2.0" |
| `IssueInstant` | Yes | xs:dateTime | Response creation time |
| `InResponseTo` | No | xs:NCName | ID of corresponding request |
| `Destination` | No | xs:anyURI | Intended recipient |
| `Consent` | No | xs:anyURI | Consent indicator |

### 4.3 AuthnRequest (Authentication Request)

**Purpose**: SP requests authentication of a subject from IdP

```xml
<samlp:AuthnRequest
    xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol"
    xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion"
    ID="_request-id-789"
    Version="2.0"
    IssueInstant="2024-01-15T10:28:00Z"
    Destination="https://idp.example.com/sso"
    AssertionConsumerServiceURL="https://sp.example.com/acs"
    ProtocolBinding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
    ForceAuthn="false"
    IsPassive="false">

    <saml:Issuer>https://sp.example.com</saml:Issuer>

    <samlp:NameIDPolicy
        Format="urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"
        AllowCreate="true"/>

    <samlp:RequestedAuthnContext Comparison="exact">
        <saml:AuthnContextClassRef>
            urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport
        </saml:AuthnContextClassRef>
    </samlp:RequestedAuthnContext>
</samlp:AuthnRequest>
```

**AuthnRequest Attributes**:

| Attribute | Required | Type | Description |
|-----------|----------|------|-------------|
| `ForceAuthn` | No | boolean | Force re-authentication |
| `IsPassive` | No | boolean | No user interaction allowed |
| `ProtocolBinding` | No | xs:anyURI | Desired response binding |
| `AssertionConsumerServiceIndex` | No | xs:unsignedShort | ACS index from metadata |
| `AssertionConsumerServiceURL` | No | xs:anyURI | ACS URL override |
| `AttributeConsumingServiceIndex` | No | xs:unsignedShort | Attribute service index |
| `ProviderName` | No | string | Human-readable SP name |

### 4.4 Response (Authentication Response)

**Purpose**: IdP returns assertion(s) in response to AuthnRequest

```xml
<samlp:Response
    xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol"
    xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion"
    ID="_response-id-abc"
    Version="2.0"
    IssueInstant="2024-01-15T10:30:00Z"
    Destination="https://sp.example.com/acs"
    InResponseTo="_request-id-789">

    <saml:Issuer>https://idp.example.com</saml:Issuer>

    <ds:Signature>...</ds:Signature>

    <samlp:Status>
        <samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:Success"/>
    </samlp:Status>

    <saml:Assertion>...</saml:Assertion>
    <!-- OR -->
    <saml:EncryptedAssertion>...</saml:EncryptedAssertion>
</samlp:Response>
```

### 4.5 Status Codes

**Top-Level Status Codes**:

| Status Code | Description |
|-------------|-------------|
| `urn:oasis:names:tc:SAML:2.0:status:Success` | Request succeeded |
| `urn:oasis:names:tc:SAML:2.0:status:Requester` | Request error |
| `urn:oasis:names:tc:SAML:2.0:status:Responder` | Responder error |
| `urn:oasis:names:tc:SAML:2.0:status:VersionMismatch` | Version not supported |

**Second-Level Status Codes** (nested in first-level):

| Status Code | Description |
|-------------|-------------|
| `urn:oasis:names:tc:SAML:2.0:status:AuthnFailed` | Authentication failed |
| `urn:oasis:names:tc:SAML:2.0:status:InvalidAttrNameOrValue` | Invalid attribute |
| `urn:oasis:names:tc:SAML:2.0:status:InvalidNameIDPolicy` | Invalid NameID policy |
| `urn:oasis:names:tc:SAML:2.0:status:NoAuthnContext` | No authentication context |
| `urn:oasis:names:tc:SAML:2.0:status:NoAvailableIDP` | No IdP available |
| `urn:oasis:names:tc:SAML:2.0:status:NoPassive` | Cannot authenticate passively |
| `urn:oasis:names:tc:SAML:2.0:status:NoSupportedIDP` | No supported IdP |
| `urn:oasis:names:tc:SAML:2.0:status:PartialLogout` | Partial logout only |
| `urn:oasis:names:tc:SAML:2.0:status:ProxyCountExceeded` | Proxy count exceeded |
| `urn:oasis:names:tc:SAML:2.0:status:RequestDenied` | Request denied |
| `urn:oasis:names:tc:SAML:2.0:status:RequestUnsupported` | Request not supported |
| `urn:oasis:names:tc:SAML:2.0:status:RequestVersionDeprecated` | Version deprecated |
| `urn:oasis:names:tc:SAML:2.0:status:RequestVersionTooHigh` | Version too high |
| `urn:oasis:names:tc:SAML:2.0:status:RequestVersionTooLow` | Version too low |
| `urn:oasis:names:tc:SAML:2.0:status:ResourceNotRecognized` | Resource not recognized |
| `urn:oasis:names:tc:SAML:2.0:status:TooManyResponses` | Too many responses |
| `urn:oasis:names:tc:SAML:2.0:status:UnknownAttrProfile` | Unknown attribute profile |
| `urn:oasis:names:tc:SAML:2.0:status:UnknownPrincipal` | Unknown principal |
| `urn:oasis:names:tc:SAML:2.0:status:UnsupportedBinding` | Unsupported binding |

### 4.6 LogoutRequest

**Purpose**: Initiate single logout across all sessions

```xml
<samlp:LogoutRequest
    xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol"
    xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion"
    ID="_logout-request-123"
    Version="2.0"
    IssueInstant="2024-01-15T18:00:00Z"
    Destination="https://idp.example.com/slo"
    NotOnOrAfter="2024-01-15T18:05:00Z"
    Reason="urn:oasis:names:tc:SAML:2.0:logout:user">

    <saml:Issuer>https://sp.example.com</saml:Issuer>

    <saml:NameID Format="urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress">
        user@example.com
    </saml:NameID>

    <samlp:SessionIndex>_session-123</samlp:SessionIndex>
</samlp:LogoutRequest>
```

**LogoutRequest Attributes**:

| Attribute | Required | Type | Description |
|-----------|----------|------|-------------|
| `Reason` | No | xs:anyURI | Logout reason |
| `NotOnOrAfter` | No | xs:dateTime | Request expiration |

**Logout Reason URIs**:

| Reason URI | Description |
|------------|-------------|
| `urn:oasis:names:tc:SAML:2.0:logout:user` | User-initiated |
| `urn:oasis:names:tc:SAML:2.0:logout:admin` | Admin-initiated |
| `urn:oasis:names:tc:SAML:2.0:logout:global-timeout` | Global timeout |
| `urn:oasis:names:tc:SAML:2.0:logout:sp-timeout` | SP session timeout |

### 4.7 LogoutResponse

```xml
<samlp:LogoutResponse
    xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol"
    ID="_logout-response-456"
    Version="2.0"
    IssueInstant="2024-01-15T18:00:05Z"
    Destination="https://sp.example.com/slo"
    InResponseTo="_logout-request-123">

    <saml:Issuer>https://idp.example.com</saml:Issuer>

    <samlp:Status>
        <samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:Success"/>
    </samlp:Status>
</samlp:LogoutResponse>
```

### 4.8 ArtifactResolve

**Purpose**: Resolve artifact to obtain original SAML message

```xml
<samlp:ArtifactResolve
    xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol"
    ID="_artifact-resolve-123"
    Version="2.0"
    IssueInstant="2024-01-15T10:30:01Z"
    Destination="https://idp.example.com/artifact">

    <saml:Issuer>https://sp.example.com</saml:Issuer>

    <samlp:Artifact>
        AAQAAMh48/1oXIM+sDo7Dh2VeFdGqJSsmIlKzrAJLPR5ZylDJGJZ...
    </samlp:Artifact>
</samlp:ArtifactResolve>
```

### 4.9 ArtifactResponse

```xml
<samlp:ArtifactResponse
    xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol"
    ID="_artifact-response-456"
    Version="2.0"
    IssueInstant="2024-01-15T10:30:02Z"
    InResponseTo="_artifact-resolve-123">

    <saml:Issuer>https://idp.example.com</saml:Issuer>

    <samlp:Status>
        <samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:Success"/>
    </samlp:Status>

    <!-- Original SAML message (Response, AuthnRequest, etc.) -->
    <samlp:Response>...</samlp:Response>
</samlp:ArtifactResponse>
```

### 4.10 ManageNameIDRequest

**Purpose**: Change or terminate name identifier

```xml
<samlp:ManageNameIDRequest
    xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol"
    ID="_manage-nameid-123"
    Version="2.0"
    IssueInstant="2024-01-15T12:00:00Z"
    Destination="https://idp.example.com/nameid">

    <saml:Issuer>https://sp.example.com</saml:Issuer>

    <saml:NameID Format="urn:oasis:names:tc:SAML:2.0:nameid-format:persistent">
        old-identifier-value
    </saml:NameID>

    <!-- Either NewID, NewEncryptedID, or Terminate -->
    <samlp:NewID>new-identifier-value</samlp:NewID>
    <!-- OR -->
    <samlp:Terminate/>
</samlp:ManageNameIDRequest>
```

---

## 5. Bindings

### 5.1 Binding Overview

| Binding | URI | Transport | Use Case |
|---------|-----|-----------|----------|
| HTTP-Redirect | `urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect` | GET | Short messages, AuthnRequest |
| HTTP-POST | `urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST` | POST | Large messages, Response |
| HTTP-Artifact | `urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Artifact` | GET/POST | Sensitive messages |
| SOAP | `urn:oasis:names:tc:SAML:2.0:bindings:SOAP` | SOAP 1.1 | Back-channel |
| PAOS | `urn:oasis:names:tc:SAML:2.0:bindings:PAOS` | Reverse SOAP | ECP |

### 5.2 HTTP-Redirect Binding

**Encoding Process**:

1. Remove XML signature from protocol message (if present)
2. DEFLATE compress the XML message (RFC 1951)
3. Base64 encode the compressed data
4. URL encode the result

**Query Parameters**:

| Parameter | Description |
|-----------|-------------|
| `SAMLRequest` | Encoded AuthnRequest or LogoutRequest |
| `SAMLResponse` | Encoded LogoutResponse |
| `RelayState` | Opaque state (max 80 bytes) |
| `SigAlg` | Signature algorithm URI |
| `Signature` | URL-encoded base64 signature |

**Example URL**:
```
https://idp.example.com/sso?
  SAMLRequest=fZJNT8MwDIbvSPwHK...&
  RelayState=token&
  SigAlg=http%3A%2F%2Fwww.w3.org%2F2001%2F04%2Fxmldsig-more%23rsa-sha256&
  Signature=Tm9wZVRoaXNJc0...
```

**Signature Computation** (for HTTP-Redirect):

The signature is computed over the concatenated query string:
```
SAMLRequest=value&RelayState=value&SigAlg=value
```

**Important**: Use original URL-encoded values for signature verification. Re-encoding may produce different results.

**Elixir Encoding Example**:
```elixir
def encode_redirect(xml_message, relay_state \\ nil) do
  # 1. Deflate compress
  compressed = :zlib.zip(xml_message)

  # 2. Base64 encode
  encoded = Base.encode64(compressed)

  # 3. URL encode
  params = [{"SAMLRequest", URI.encode_www_form(encoded)}]

  params = if relay_state do
    params ++ [{"RelayState", URI.encode_www_form(relay_state)}]
  else
    params
  end

  URI.encode_query(params)
end
```

### 5.3 HTTP-POST Binding

**Encoding Process**:

1. Base64 encode the XML message (no compression)
2. Embed in HTML form as hidden field

**HTML Form Template**:
```html
<!DOCTYPE html>
<html>
<head>
    <title>SAML POST</title>
</head>
<body onload="document.forms[0].submit()">
    <noscript>
        <p>JavaScript is disabled. Click Submit to continue.</p>
    </noscript>
    <form method="post" action="https://sp.example.com/acs">
        <input type="hidden" name="SAMLResponse" value="PHNhbWxwOlJlc3Bv..."/>
        <input type="hidden" name="RelayState" value="token"/>
        <noscript>
            <input type="submit" value="Submit"/>
        </noscript>
    </form>
</body>
</html>
```

**Form Parameters**:

| Parameter | Description |
|-----------|-------------|
| `SAMLRequest` | Base64-encoded AuthnRequest |
| `SAMLResponse` | Base64-encoded Response |
| `RelayState` | Opaque state (max 80 bytes) |

**Signature Handling**: XML Signature is embedded within the message (before base64 encoding)

### 5.4 HTTP-Artifact Binding

**Purpose**: Pass reference (artifact) instead of full message

**Artifact Structure** (44 bytes total):
```
TypeCode (2 bytes) + EndpointIndex (2 bytes) + SourceID (20 bytes) + MessageHandle (20 bytes)
```

| Component | Size | Description |
|-----------|------|-------------|
| TypeCode | 2 bytes | `0x0004` for SAML 2.0 |
| EndpointIndex | 2 bytes | Index into metadata endpoints |
| SourceID | 20 bytes | SHA-1 hash of issuer's entityID |
| MessageHandle | 20 bytes | Random bytes identifying message |

**Flow**:
1. Sender creates artifact referencing stored message
2. Artifact sent via HTTP-Redirect or HTTP-POST
3. Receiver sends ArtifactResolve via SOAP back-channel
4. Sender returns ArtifactResponse with original message

### 5.5 SOAP Binding

**Purpose**: Synchronous back-channel communication

**SOAP Envelope**:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
    <soap:Body>
        <samlp:ArtifactResolve>...</samlp:ArtifactResolve>
    </soap:Body>
</soap:Envelope>
```

**HTTP Headers**:
```
Content-Type: text/xml
SOAPAction: http://www.oasis-open.org/committees/security
```

---

## 6. Profiles

### 6.1 Web Browser SSO Profile

**SP-Initiated Flow**:

```
┌──────┐          ┌──────┐          ┌──────┐
│ User │          │  SP  │          │ IdP  │
└──┬───┘          └──┬───┘          └──┬───┘
   │ 1. Access        │                 │
   │    resource      │                 │
   │─────────────────>│                 │
   │                  │                 │
   │ 2. Redirect with │                 │
   │    AuthnRequest  │                 │
   │<─────────────────│                 │
   │                  │                 │
   │ 3. AuthnRequest via HTTP-Redirect/POST │
   │────────────────────────────────────────>│
   │                  │                 │
   │                  │ 4. Authenticate │
   │                  │    (login form) │
   │<────────────────────────────────────────│
   │                  │                 │
   │ 5. Credentials   │                 │
   │────────────────────────────────────────>│
   │                  │                 │
   │ 6. Response with assertion (HTTP-POST) │
   │<────────────────────────────────────────│
   │                  │                 │
   │ 7. POST Response │                 │
   │    to ACS        │                 │
   │─────────────────>│                 │
   │                  │                 │
   │                  │ 8. Validate     │
   │                  │    assertion    │
   │                  │                 │
   │ 9. Access granted│                 │
   │<─────────────────│                 │
```

**IdP-Initiated Flow** (Unsolicited Response):

```
┌──────┐          ┌──────┐          ┌──────┐
│ User │          │  SP  │          │ IdP  │
└──┬───┘          └──┬───┘          └──┬───┘
   │                  │                 │
   │ 1. Access IdP portal              │
   │────────────────────────────────────>│
   │                  │                 │
   │ 2. Select SP link                 │
   │────────────────────────────────────>│
   │                  │                 │
   │ 3. Response with assertion (POST)  │
   │<────────────────────────────────────│
   │                  │                 │
   │ 4. POST to ACS   │                 │
   │─────────────────>│                 │
   │                  │                 │
   │ 5. Access granted│                 │
   │<─────────────────│                 │
```

**Binding Combinations**:

| AuthnRequest Binding | Response Binding | Notes |
|---------------------|------------------|-------|
| HTTP-Redirect | HTTP-POST | Most common |
| HTTP-POST | HTTP-POST | Both use POST |
| HTTP-Redirect | HTTP-Artifact | Two-step response |
| HTTP-Artifact | HTTP-Artifact | Both use artifacts |

### 6.2 Single Logout Profile

**SP-Initiated Logout**:

```
┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐
│ User │   │ SP1  │   │ IdP  │   │ SP2  │
└──┬───┘   └──┬───┘   └──┬───┘   └──┬───┘
   │          │          │          │
   │ 1. Logout│          │          │
   │─────────>│          │          │
   │          │          │          │
   │          │ 2. LogoutRequest    │
   │          │─────────>│          │
   │          │          │          │
   │          │          │ 3. LogoutRequest
   │          │          │─────────>│
   │          │          │          │
   │          │          │ 4. LogoutResponse
   │          │          │<─────────│
   │          │          │          │
   │          │ 5. LogoutResponse   │
   │          │<─────────│          │
   │          │          │          │
   │ 6. Logout│          │          │
   │    complete         │          │
   │<─────────│          │          │
```

**Logout Bindings**:
- **Front-channel**: HTTP-Redirect, HTTP-POST (browser involved)
- **Back-channel**: SOAP (server-to-server)

### 6.3 Enhanced Client/Proxy (ECP) Profile

**Purpose**: Support non-browser clients and proxies

**Flow** uses PAOS (Reverse SOAP) binding:
1. Client sends HTTP request with PAOS headers
2. SP returns SOAP envelope with AuthnRequest
3. Client sends AuthnRequest to IdP
4. IdP returns Response to client
5. Client sends Response to SP

---

## 7. Metadata

### 7.1 EntityDescriptor

**Root element for SAML entity metadata**:

```xml
<md:EntityDescriptor
    xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata"
    xmlns:ds="http://www.w3.org/2000/09/xmldsig#"
    entityID="https://idp.example.com"
    validUntil="2025-01-15T00:00:00Z"
    cacheDuration="PT24H">

    <ds:Signature>...</ds:Signature>

    <md:IDPSSODescriptor>...</md:IDPSSODescriptor>
    <!-- OR -->
    <md:SPSSODescriptor>...</md:SPSSODescriptor>

    <md:Organization>
        <md:OrganizationName xml:lang="en">Example Corp</md:OrganizationName>
        <md:OrganizationDisplayName xml:lang="en">Example</md:OrganizationDisplayName>
        <md:OrganizationURL xml:lang="en">https://example.com</md:OrganizationURL>
    </md:Organization>

    <md:ContactPerson contactType="technical">
        <md:GivenName>John</md:GivenName>
        <md:SurName>Doe</md:SurName>
        <md:EmailAddress>admin@example.com</md:EmailAddress>
    </md:ContactPerson>
</md:EntityDescriptor>
```

**EntityDescriptor Attributes**:

| Attribute | Required | Type | Description |
|-----------|----------|------|-------------|
| `entityID` | Yes | xs:anyURI | Unique entity identifier (max 1024 chars) |
| `validUntil` | No | xs:dateTime | Metadata expiration |
| `cacheDuration` | No | xs:duration | Recommended cache time |
| `ID` | No | xs:ID | XML identifier |

### 7.2 IDPSSODescriptor

**Identity Provider metadata**:

```xml
<md:IDPSSODescriptor
    protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol"
    WantAuthnRequestsSigned="true">

    <md:KeyDescriptor use="signing">
        <ds:KeyInfo>
            <ds:X509Data>
                <ds:X509Certificate>MIICajCCAdOgAwIBA...</ds:X509Certificate>
            </ds:X509Data>
        </ds:KeyInfo>
    </md:KeyDescriptor>

    <md:KeyDescriptor use="encryption">
        <ds:KeyInfo>
            <ds:X509Data>
                <ds:X509Certificate>MIICajCCAdOgAwIBA...</ds:X509Certificate>
            </ds:X509Data>
        </ds:KeyInfo>
        <md:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes256-cbc"/>
    </md:KeyDescriptor>

    <md:SingleLogoutService
        Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect"
        Location="https://idp.example.com/slo"/>

    <md:SingleLogoutService
        Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
        Location="https://idp.example.com/slo"/>

    <md:NameIDFormat>urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress</md:NameIDFormat>
    <md:NameIDFormat>urn:oasis:names:tc:SAML:2.0:nameid-format:persistent</md:NameIDFormat>

    <md:SingleSignOnService
        Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect"
        Location="https://idp.example.com/sso"/>

    <md:SingleSignOnService
        Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
        Location="https://idp.example.com/sso"/>

    <saml:Attribute Name="email" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
    <saml:Attribute Name="displayName"/>
</md:IDPSSODescriptor>
```

**IDPSSODescriptor Attributes**:

| Attribute | Required | Type | Description |
|-----------|----------|------|-------------|
| `protocolSupportEnumeration` | Yes | xs:anyURI list | Supported protocols |
| `WantAuthnRequestsSigned` | No | boolean | Require signed requests |

### 7.3 SPSSODescriptor

**Service Provider metadata**:

```xml
<md:SPSSODescriptor
    protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol"
    AuthnRequestsSigned="true"
    WantAssertionsSigned="true">

    <md:KeyDescriptor use="signing">
        <ds:KeyInfo>
            <ds:X509Data>
                <ds:X509Certificate>MIICajCCAdOgAwIBA...</ds:X509Certificate>
            </ds:X509Data>
        </ds:KeyInfo>
    </md:KeyDescriptor>

    <md:KeyDescriptor use="encryption">
        <ds:KeyInfo>
            <ds:X509Data>
                <ds:X509Certificate>MIICajCCAdOgAwIBA...</ds:X509Certificate>
            </ds:X509Data>
        </ds:KeyInfo>
    </md:KeyDescriptor>

    <md:SingleLogoutService
        Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect"
        Location="https://sp.example.com/slo"/>

    <md:NameIDFormat>urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress</md:NameIDFormat>

    <md:AssertionConsumerService
        index="0"
        isDefault="true"
        Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
        Location="https://sp.example.com/acs"/>

    <md:AssertionConsumerService
        index="1"
        Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Artifact"
        Location="https://sp.example.com/acs"/>

    <md:AttributeConsumingService index="0" isDefault="true">
        <md:ServiceName xml:lang="en">My Application</md:ServiceName>
        <md:RequestedAttribute
            Name="email"
            NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"
            isRequired="true"/>
        <md:RequestedAttribute Name="displayName"/>
    </md:AttributeConsumingService>
</md:SPSSODescriptor>
```

**SPSSODescriptor Attributes**:

| Attribute | Required | Type | Description |
|-----------|----------|------|-------------|
| `protocolSupportEnumeration` | Yes | xs:anyURI list | Supported protocols |
| `AuthnRequestsSigned` | No | boolean | SP signs requests |
| `WantAssertionsSigned` | No | boolean | Require signed assertions |

### 7.4 EntitiesDescriptor

**Container for multiple entities**:

```xml
<md:EntitiesDescriptor
    xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata"
    Name="urn:example:federation"
    validUntil="2025-01-15T00:00:00Z">

    <ds:Signature>...</ds:Signature>

    <md:EntityDescriptor entityID="https://idp1.example.com">...</md:EntityDescriptor>
    <md:EntityDescriptor entityID="https://idp2.example.com">...</md:EntityDescriptor>
    <md:EntityDescriptor entityID="https://sp1.example.com">...</md:EntityDescriptor>
</md:EntitiesDescriptor>
```

---

## 8. Security Considerations

### 8.1 Critical Vulnerabilities

**XML Signature Wrapping (XSW) Attacks**:

Attackers manipulate XML structure to bypass signature validation:

```xml
<!-- ATTACK: Signature covers original assertion, but app processes injected one -->
<Response>
    <Assertion ID="original"><!-- Signed, legitimate --></Assertion>
    <Assertion ID="malicious"><!-- Unsigned, injected --></Assertion>
    <Signature>
        <Reference URI="#original"/>  <!-- Only validates original -->
    </Signature>
</Response>
```

**Prevention**:
1. Validate XML against schema BEFORE processing
2. Use absolute XPath to select signed elements
3. Never use `getElementsByTagName()` for security elements
4. Verify signature covers the assertion being processed
5. Use `StaticKeySelector` - don't trust embedded KeyInfo

### 8.2 Validation Checklist

**Response Validation**:

```elixir
def validate_response(response, config) do
  with :ok <- validate_schema(response),
       :ok <- validate_destination(response, config.acs_url),
       :ok <- validate_issuer(response, config.idp_entity_id),
       :ok <- validate_signature(response, config.idp_certificate),
       :ok <- validate_in_response_to(response, config.request_id),
       :ok <- validate_status(response),
       {:ok, assertion} <- extract_assertion(response),
       :ok <- validate_assertion(assertion, config) do
    {:ok, assertion}
  end
end
```

**Assertion Validation**:

```elixir
def validate_assertion(assertion, config) do
  with :ok <- validate_assertion_signature(assertion, config.idp_certificate),
       :ok <- validate_issuer(assertion, config.idp_entity_id),
       :ok <- validate_subject_confirmation(assertion, config),
       :ok <- validate_conditions(assertion, config),
       :ok <- validate_audience(assertion, config.sp_entity_id),
       :ok <- validate_timestamps(assertion) do
    :ok
  end
end
```

### 8.3 Timestamp Validation

```elixir
def validate_timestamps(assertion, clock_skew_seconds \\ 300) do
  now = DateTime.utc_now()
  skew = clock_skew_seconds

  # Check NotBefore (if present)
  with :ok <- check_not_before(assertion.conditions.not_before, now, skew),
       # Check NotOnOrAfter (if present)
       :ok <- check_not_on_or_after(assertion.conditions.not_on_or_after, now, skew),
       # Check SubjectConfirmationData NotOnOrAfter
       :ok <- check_subject_confirmation_expiry(assertion, now, skew) do
    :ok
  end
end
```

### 8.4 Replay Prevention

**OneTimeUse**:
```xml
<Conditions>
    <OneTimeUse/>
</Conditions>
```

**Implementation**:
```elixir
def check_replay(assertion_id, store) do
  case Store.get(store, assertion_id) do
    nil ->
      Store.put(store, assertion_id, :used, ttl: :timer.hours(24))
      :ok
    :used ->
      {:error, :replay_detected}
  end
end
```

### 8.5 Certificate Requirements

| Requirement | Specification |
|-------------|---------------|
| Key Size | RSA 2048-bit minimum, ECC 256-bit |
| Hash Algorithm | SHA-256 minimum, SHA-384/512 preferred |
| Validity Period | Maximum 2 years |
| Key Usage | `digitalSignature` only |
| Storage | HSM recommended (FIPS 140-2/140-3) |

### 8.6 Signature Algorithms

**Recommended**:

| Algorithm | URI |
|-----------|-----|
| RSA-SHA256 | `http://www.w3.org/2001/04/xmldsig-more#rsa-sha256` |
| RSA-SHA384 | `http://www.w3.org/2001/04/xmldsig-more#rsa-sha384` |
| RSA-SHA512 | `http://www.w3.org/2001/04/xmldsig-more#rsa-sha512` |
| ECDSA-SHA256 | `http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256` |

**Deprecated** (DO NOT USE):

| Algorithm | URI |
|-----------|-----|
| RSA-SHA1 | `http://www.w3.org/2000/09/xmldsig#rsa-sha1` |
| DSA-SHA1 | `http://www.w3.org/2000/09/xmldsig#dsa-sha1` |

### 8.7 Encryption Algorithms

**Key Transport**:

| Algorithm | URI |
|-----------|-----|
| RSA-OAEP | `http://www.w3.org/2001/04/xmlenc#rsa-oaep-mgf1p` |
| RSA-OAEP-SHA256 | `http://www.w3.org/2009/xmlenc11#rsa-oaep` |

**Block Encryption**:

| Algorithm | URI |
|-----------|-----|
| AES-128-CBC | `http://www.w3.org/2001/04/xmlenc#aes128-cbc` |
| AES-256-CBC | `http://www.w3.org/2001/04/xmlenc#aes256-cbc` |
| AES-128-GCM | `http://www.w3.org/2009/xmlenc11#aes128-gcm` |
| AES-256-GCM | `http://www.w3.org/2009/xmlenc11#aes256-gcm` |

---

## 9. XML Schemas

### 9.1 Assertion Schema (saml-schema-assertion-2.0.xsd)

**Key Type Definitions**:

```
AssertionType
├── Version: string (required, "2.0")
├── ID: xs:ID (required)
├── IssueInstant: xs:dateTime (required)
├── Issuer: NameIDType (required)
├── Signature: ds:SignatureType (optional)
├── Subject: SubjectType (optional)
├── Conditions: ConditionsType (optional)
├── Advice: AdviceType (optional)
└── Statement*: (choice of)
    ├── StatementAbstractType
    ├── AuthnStatementType
    ├── AuthzDecisionStatementType
    └── AttributeStatementType

SubjectType
├── (BaseID | NameID | EncryptedID)?
└── SubjectConfirmation*

NameIDType (extends string)
├── NameQualifier: string
├── SPNameQualifier: string
├── Format: xs:anyURI
└── SPProvidedID: string

ConditionsType
├── NotBefore: xs:dateTime
├── NotOnOrAfter: xs:dateTime
├── Condition*: (choice of)
│   ├── AudienceRestriction
│   ├── OneTimeUse
│   └── ProxyRestriction

AuthnStatementType
├── AuthnInstant: xs:dateTime (required)
├── SessionIndex: string
├── SessionNotOnOrAfter: xs:dateTime
├── SubjectLocality: SubjectLocalityType
└── AuthnContext: AuthnContextType (required)

AttributeStatementType
└── (Attribute | EncryptedAttribute)+

AttributeType
├── Name: string (required)
├── NameFormat: xs:anyURI
├── FriendlyName: string
└── AttributeValue*: xs:anyType
```

### 9.2 Protocol Schema (saml-schema-protocol-2.0.xsd)

**Key Type Definitions**:

```
RequestAbstractType (abstract)
├── ID: xs:ID (required)
├── Version: string (required, "2.0")
├── IssueInstant: xs:dateTime (required)
├── Destination: xs:anyURI
├── Consent: xs:anyURI
├── Issuer: saml:NameIDType
├── Signature: ds:SignatureType
└── Extensions: ExtensionsType

StatusResponseType
├── ID: xs:ID (required)
├── Version: string (required)
├── IssueInstant: xs:dateTime (required)
├── InResponseTo: xs:NCName
├── Destination: xs:anyURI
├── Consent: xs:anyURI
├── Issuer: saml:NameIDType
├── Signature: ds:SignatureType
├── Extensions: ExtensionsType
└── Status: StatusType (required)

AuthnRequestType (extends RequestAbstractType)
├── ForceAuthn: boolean
├── IsPassive: boolean
├── ProtocolBinding: xs:anyURI
├── AssertionConsumerServiceIndex: xs:unsignedShort
├── AssertionConsumerServiceURL: xs:anyURI
├── AttributeConsumingServiceIndex: xs:unsignedShort
├── ProviderName: string
├── Subject: saml:SubjectType
├── NameIDPolicy: NameIDPolicyType
├── Conditions: saml:ConditionsType
├── RequestedAuthnContext: RequestedAuthnContextType
└── Scoping: ScopingType

ResponseType (extends StatusResponseType)
└── (saml:Assertion | saml:EncryptedAssertion)*

LogoutRequestType (extends RequestAbstractType)
├── Reason: xs:anyURI
├── NotOnOrAfter: xs:dateTime
├── (BaseID | NameID | EncryptedID)
└── SessionIndex*

StatusType
├── StatusCode: StatusCodeType (required)
├── StatusMessage: string
└── StatusDetail: StatusDetailType

StatusCodeType
├── Value: xs:anyURI (required)
└── StatusCode: StatusCodeType (nested)
```

### 9.3 Metadata Schema (saml-schema-metadata-2.0.xsd)

**Key Type Definitions**:

```
EntityDescriptorType
├── entityID: xs:anyURI (required, max 1024)
├── validUntil: xs:dateTime
├── cacheDuration: xs:duration
├── ID: xs:ID
├── Signature: ds:SignatureType
├── Extensions: ExtensionsType
├── (RoleDescriptor+ | AffiliationDescriptor)
├── Organization: OrganizationType
├── ContactPerson*: ContactType
└── AdditionalMetadataLocation*

IDPSSODescriptorType (extends SSODescriptorType)
├── WantAuthnRequestsSigned: boolean
├── SingleSignOnService+: EndpointType
├── NameIDMappingService*: EndpointType
├── AssertionIDRequestService*: EndpointType
├── AttributeProfile*: xs:anyURI
└── Attribute*: saml:AttributeType

SPSSODescriptorType (extends SSODescriptorType)
├── AuthnRequestsSigned: boolean
├── WantAssertionsSigned: boolean
├── AssertionConsumerService+: IndexedEndpointType
└── AttributeConsumingService*: AttributeConsumingServiceType

SSODescriptorType (extends RoleDescriptorType)
├── ArtifactResolutionService*: IndexedEndpointType
├── SingleLogoutService*: EndpointType
├── ManageNameIDService*: EndpointType
└── NameIDFormat*: xs:anyURI

RoleDescriptorType
├── protocolSupportEnumeration: xs:anyURI list (required)
├── errorURL: xs:anyURI
├── validUntil: xs:dateTime
├── cacheDuration: xs:duration
├── ID: xs:ID
├── Signature: ds:SignatureType
├── Extensions: ExtensionsType
├── KeyDescriptor*: KeyDescriptorType
├── Organization: OrganizationType
└── ContactPerson*: ContactType

EndpointType
├── Binding: xs:anyURI (required)
├── Location: xs:anyURI (required)
└── ResponseLocation: xs:anyURI

IndexedEndpointType (extends EndpointType)
├── index: xs:unsignedShort (required)
└── isDefault: boolean

KeyDescriptorType
├── use: ("signing" | "encryption")
├── KeyInfo: ds:KeyInfoType (required)
└── EncryptionMethod*: xenc:EncryptionMethodType
```

---

## 10. Namespaces and URIs

### 10.1 XML Namespaces

| Prefix | URI | Description |
|--------|-----|-------------|
| `saml` | `urn:oasis:names:tc:SAML:2.0:assertion` | Assertions |
| `samlp` | `urn:oasis:names:tc:SAML:2.0:protocol` | Protocols |
| `md` | `urn:oasis:names:tc:SAML:2.0:metadata` | Metadata |
| `ds` | `http://www.w3.org/2000/09/xmldsig#` | XML Signature |
| `xenc` | `http://www.w3.org/2001/04/xmlenc#` | XML Encryption |
| `xs` | `http://www.w3.org/2001/XMLSchema` | XML Schema |
| `xsi` | `http://www.w3.org/2001/XMLSchema-instance` | Schema instance |

### 10.2 Binding URIs

| Binding | URI |
|---------|-----|
| HTTP-Redirect | `urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect` |
| HTTP-POST | `urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST` |
| HTTP-Artifact | `urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Artifact` |
| SOAP | `urn:oasis:names:tc:SAML:2.0:bindings:SOAP` |
| PAOS | `urn:oasis:names:tc:SAML:2.0:bindings:PAOS` |
| URI | `urn:oasis:names:tc:SAML:2.0:bindings:URI` |

### 10.3 NameID Format URIs

| Format | URI |
|--------|-----|
| Unspecified | `urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified` |
| Email | `urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress` |
| X509 Subject | `urn:oasis:names:tc:SAML:1.1:nameid-format:X509SubjectName` |
| Windows Domain | `urn:oasis:names:tc:SAML:1.1:nameid-format:WindowsDomainQualifiedName` |
| Kerberos | `urn:oasis:names:tc:SAML:2.0:nameid-format:kerberos` |
| Entity | `urn:oasis:names:tc:SAML:2.0:nameid-format:entity` |
| Persistent | `urn:oasis:names:tc:SAML:2.0:nameid-format:persistent` |
| Transient | `urn:oasis:names:tc:SAML:2.0:nameid-format:transient` |
| Encrypted | `urn:oasis:names:tc:SAML:2.0:nameid-format:encrypted` |

### 10.4 Consent URIs

| Consent | URI |
|---------|-----|
| Unspecified | `urn:oasis:names:tc:SAML:2.0:consent:unspecified` |
| Obtained | `urn:oasis:names:tc:SAML:2.0:consent:obtained` |
| Prior | `urn:oasis:names:tc:SAML:2.0:consent:prior` |
| Implicit | `urn:oasis:names:tc:SAML:2.0:consent:current-implicit` |
| Explicit | `urn:oasis:names:tc:SAML:2.0:consent:current-explicit` |
| Unavailable | `urn:oasis:names:tc:SAML:2.0:consent:unavailable` |
| Inapplicable | `urn:oasis:names:tc:SAML:2.0:consent:inapplicable` |

---

## 11. Implementation Checklist

### 11.1 Service Provider (SP) Implementation

**Core Requirements**:
- [ ] Generate AuthnRequest with unique ID
- [ ] Support HTTP-Redirect binding for AuthnRequest
- [ ] Support HTTP-POST binding for Response
- [ ] Parse and validate SAML Response
- [ ] Extract and validate Assertion
- [ ] Verify XML Signature (Response and/or Assertion)
- [ ] Validate Conditions (timestamps, audience)
- [ ] Validate SubjectConfirmation
- [ ] Extract NameID and Attributes
- [ ] Manage RelayState
- [ ] Generate and parse SP Metadata

**Security Requirements**:
- [ ] Validate InResponseTo matches request ID
- [ ] Validate Destination matches ACS URL
- [ ] Validate Issuer matches expected IdP
- [ ] Enforce clock skew tolerance
- [ ] Implement replay detection
- [ ] Use absolute XPath for element selection
- [ ] Schema validation before processing

**Single Logout**:
- [ ] Generate LogoutRequest
- [ ] Process LogoutRequest from IdP
- [ ] Generate LogoutResponse
- [ ] Process LogoutResponse

### 11.2 Identity Provider (IdP) Implementation

**Core Requirements**:
- [ ] Parse AuthnRequest
- [ ] Validate AuthnRequest signature (if required)
- [ ] Generate SAML Response with Assertion
- [ ] Sign Response and/or Assertion
- [ ] Support HTTP-POST binding for Response
- [ ] Generate IdP Metadata

**Security Requirements**:
- [ ] Validate AuthnRequest Destination
- [ ] Validate AuthnRequest Issuer against known SPs
- [ ] Generate cryptographically random IDs
- [ ] Use secure timestamp generation
- [ ] Implement session management

**Single Logout**:
- [ ] Process LogoutRequest from SP
- [ ] Propagate logout to all session participants
- [ ] Generate LogoutResponse

### 11.3 Common Requirements

**Cryptography**:
- [ ] RSA-SHA256 signature support
- [ ] X.509 certificate handling
- [ ] Certificate validation
- [ ] XML Canonicalization (C14N)

**Encoding**:
- [ ] DEFLATE compression
- [ ] Base64 encoding/decoding
- [ ] URL encoding/decoding

**Metadata**:
- [ ] Parse EntityDescriptor
- [ ] Parse IDPSSODescriptor
- [ ] Parse SPSSODescriptor
- [ ] Extract certificates from KeyDescriptor
- [ ] Extract endpoint locations

---

## References

### Official OASIS Documents

- [SAML 2.0 Core Specification](http://docs.oasis-open.org/security/saml/v2.0/saml-core-2.0-os.pdf)
- [SAML 2.0 Bindings](http://docs.oasis-open.org/security/saml/v2.0/saml-bindings-2.0-os.pdf)
- [SAML 2.0 Profiles](http://docs.oasis-open.org/security/saml/v2.0/saml-profiles-2.0-os.pdf)
- [SAML 2.0 Metadata](http://docs.oasis-open.org/security/saml/v2.0/saml-metadata-2.0-os.pdf)
- [SAML 2.0 Technical Overview](https://docs.oasis-open.org/security/saml/Post2.0/sstc-saml-tech-overview-2.0.html)
- [SAML Specifications Index](https://saml.xml.org/saml-specifications)

### XSD Schemas

- [Assertion Schema](http://docs.oasis-open.org/security/saml/v2.0/saml-schema-assertion-2.0.xsd)
- [Protocol Schema](http://docs.oasis-open.org/security/saml/v2.0/saml-schema-protocol-2.0.xsd)
- [Metadata Schema](http://docs.oasis-open.org/security/saml/v2.0/saml-schema-metadata-2.0.xsd)

### Security Guidance

- [OWASP SAML Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/SAML_Security_Cheat_Sheet.html)
- [On Breaking SAML (XSW Research)](https://www.usenix.org/system/files/conference/usenixsecurity12/sec12-final91.pdf)
