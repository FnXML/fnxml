# FnSAML Implementation Plan

> **Project**: FnSAML - SAML 2.0 Implementation for Elixir
> **Dependencies**: FnXML, FnXPath, FnXSD
> **Target**: Service Provider (SP) and Identity Provider (IdP) support

---

## Overview

This plan describes implementing SAML 2.0 support within the FnXML ecosystem, leveraging existing capabilities:

| Existing Component | SAML Usage |
|-------------------|------------|
| FnXML Parser | Parse SAML messages |
| FnXML.Security.Signature | XML-DSig verification/signing |
| FnXML.Security.Encryption | Encrypted assertions |
| FnXML.Security.C14N | Canonicalization |
| FnXPath | Element selection for validation |
| FnXSD | Schema validation |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        FnSAML                                │
├─────────────────────────────────────────────────────────────┤
│  High-Level API                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ FnSAML.SP   │  │ FnSAML.IdP  │  │ FnSAML.Metadata     │  │
│  │ (Service    │  │ (Identity   │  │ (Parse/Generate)    │  │
│  │  Provider)  │  │  Provider)  │  │                     │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  Protocol Layer                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ AuthnRequest│  │ Response    │  │ LogoutRequest/Resp  │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  Assertion Layer                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Assertion   │  │ Subject     │  │ Conditions          │  │
│  ├─────────────┤  ├─────────────┤  ├─────────────────────┤  │
│  │ AuthnStmt   │  │ NameID      │  │ AttributeStatement  │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  Binding Layer                                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ HTTP-Redirect│ │ HTTP-POST   │  │ SOAP (Artifact)     │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  Security Layer                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Signature   │  │ Encryption  │  │ Validation          │  │
│  │ (via FnXML) │  │ (via FnXML) │  │ (XSW prevention)    │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  Foundation (FnXML Ecosystem)                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ FnXML       │  │ FnXPath     │  │ FnXSD               │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## Module Structure

```
lib/
├── fn_saml.ex                    # Main API
├── fn_saml/
│   ├── assertion.ex              # Assertion struct & parsing
│   ├── assertion/
│   │   ├── authn_statement.ex    # Authentication statement
│   │   ├── attribute_statement.ex # Attribute statement
│   │   ├── conditions.ex         # Conditions validation
│   │   ├── subject.ex            # Subject & NameID
│   │   └── subject_confirmation.ex
│   │
│   ├── protocol.ex               # Protocol base types
│   ├── protocol/
│   │   ├── authn_request.ex      # AuthnRequest
│   │   ├── response.ex           # Response
│   │   ├── logout_request.ex     # LogoutRequest
│   │   ├── logout_response.ex    # LogoutResponse
│   │   ├── artifact_resolve.ex   # ArtifactResolve
│   │   ├── artifact_response.ex  # ArtifactResponse
│   │   └── status.ex             # Status codes
│   │
│   ├── binding.ex                # Binding dispatcher
│   ├── binding/
│   │   ├── http_redirect.ex      # DEFLATE + Base64 + URL
│   │   ├── http_post.ex          # Base64 + HTML form
│   │   ├── http_artifact.ex      # Artifact handling
│   │   └── soap.ex               # SOAP binding
│   │
│   ├── metadata.ex               # Metadata API
│   ├── metadata/
│   │   ├── entity_descriptor.ex  # EntityDescriptor
│   │   ├── idp_sso_descriptor.ex # IDPSSODescriptor
│   │   ├── sp_sso_descriptor.ex  # SPSSODescriptor
│   │   ├── key_descriptor.ex     # KeyDescriptor
│   │   └── endpoint.ex           # Endpoint types
│   │
│   ├── sp.ex                     # Service Provider API
│   ├── sp/
│   │   ├── config.ex             # SP configuration
│   │   ├── session.ex            # Session management
│   │   └── plug.ex               # Phoenix Plug integration
│   │
│   ├── idp.ex                    # Identity Provider API
│   ├── idp/
│   │   ├── config.ex             # IdP configuration
│   │   ├── session.ex            # Session management
│   │   └── plug.ex               # Phoenix Plug integration
│   │
│   ├── security.ex               # Security utilities
│   ├── security/
│   │   ├── signature.ex          # Signature wrapper
│   │   ├── encryption.ex         # Encryption wrapper
│   │   ├── validator.ex          # XSW-safe validation
│   │   └── replay_cache.ex       # Replay prevention
│   │
│   ├── xml.ex                    # XML building utilities
│   ├── constants.ex              # URIs, namespaces
│   └── error.ex                  # Error types
```

---

## Implementation Phases

### Phase 1: Foundation (Core Data Structures)

**Goal**: Define all SAML data structures and basic parsing

#### 1.1 Constants Module

```elixir
defmodule FnSAML.Constants do
  # Namespaces
  @saml_ns "urn:oasis:names:tc:SAML:2.0:assertion"
  @samlp_ns "urn:oasis:names:tc:SAML:2.0:protocol"
  @md_ns "urn:oasis:names:tc:SAML:2.0:metadata"

  # Bindings
  @binding_redirect "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect"
  @binding_post "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
  @binding_artifact "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Artifact"
  @binding_soap "urn:oasis:names:tc:SAML:2.0:bindings:SOAP"

  # NameID Formats
  @nameid_email "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"
  @nameid_persistent "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent"
  @nameid_transient "urn:oasis:names:tc:SAML:2.0:nameid-format:transient"

  # Status Codes
  @status_success "urn:oasis:names:tc:SAML:2.0:status:Success"
  @status_requester "urn:oasis:names:tc:SAML:2.0:status:Requester"
  @status_responder "urn:oasis:names:tc:SAML:2.0:status:Responder"

  # Subject Confirmation
  @cm_bearer "urn:oasis:names:tc:SAML:2.0:cm:bearer"
  @cm_holder_of_key "urn:oasis:names:tc:SAML:2.0:cm:holder-of-key"

  # ... all URIs from spec
end
```

#### 1.2 Core Structs

```elixir
defmodule FnSAML.Assertion do
  @type t :: %__MODULE__{
    id: String.t(),
    version: String.t(),
    issue_instant: DateTime.t(),
    issuer: String.t(),
    subject: FnSAML.Subject.t() | nil,
    conditions: FnSAML.Conditions.t() | nil,
    authn_statement: FnSAML.AuthnStatement.t() | nil,
    attribute_statement: FnSAML.AttributeStatement.t() | nil,
    signature: map() | nil
  }

  defstruct [
    :id, :version, :issue_instant, :issuer,
    :subject, :conditions, :authn_statement,
    :attribute_statement, :signature
  ]
end

defmodule FnSAML.Subject do
  @type t :: %__MODULE__{
    name_id: FnSAML.NameID.t() | nil,
    subject_confirmations: [FnSAML.SubjectConfirmation.t()]
  }
end

defmodule FnSAML.NameID do
  @type t :: %__MODULE__{
    value: String.t(),
    format: String.t() | nil,
    name_qualifier: String.t() | nil,
    sp_name_qualifier: String.t() | nil,
    sp_provided_id: String.t() | nil
  }
end

defmodule FnSAML.Conditions do
  @type t :: %__MODULE__{
    not_before: DateTime.t() | nil,
    not_on_or_after: DateTime.t() | nil,
    audience_restrictions: [String.t()],
    one_time_use: boolean(),
    proxy_restriction: map() | nil
  }
end
```

#### 1.3 Protocol Structs

```elixir
defmodule FnSAML.Protocol.AuthnRequest do
  @type t :: %__MODULE__{
    id: String.t(),
    version: String.t(),
    issue_instant: DateTime.t(),
    destination: String.t() | nil,
    issuer: String.t(),
    assertion_consumer_service_url: String.t() | nil,
    assertion_consumer_service_index: non_neg_integer() | nil,
    protocol_binding: String.t() | nil,
    name_id_policy: map() | nil,
    force_authn: boolean(),
    is_passive: boolean(),
    requested_authn_context: map() | nil
  }
end

defmodule FnSAML.Protocol.Response do
  @type t :: %__MODULE__{
    id: String.t(),
    version: String.t(),
    issue_instant: DateTime.t(),
    destination: String.t() | nil,
    in_response_to: String.t() | nil,
    issuer: String.t(),
    status: FnSAML.Protocol.Status.t(),
    assertions: [FnSAML.Assertion.t()],
    encrypted_assertions: [map()],
    signature: map() | nil
  }
end

defmodule FnSAML.Protocol.Status do
  @type t :: %__MODULE__{
    code: String.t(),
    sub_code: String.t() | nil,
    message: String.t() | nil
  }
end
```

#### 1.4 Parsing Implementation

```elixir
defmodule FnSAML.Parser do
  @moduledoc """
  Parse SAML XML into Elixir structs.
  Uses FnXML for parsing and FnXPath for element extraction.
  """

  alias FnSAML.{Assertion, Protocol, Constants}

  @doc """
  Parse a SAML Response from XML string or DOM.
  """
  def parse_response(xml) when is_binary(xml) do
    with {:ok, dom} <- FnXML.DOM.parse(xml) do
      parse_response(dom)
    end
  end

  def parse_response(dom) do
    # Use absolute XPath to prevent XSW attacks
    with {:ok, response_elem} <- select_single(dom, "/samlp:Response"),
         {:ok, response} <- build_response(response_elem) do
      {:ok, response}
    end
  end

  @doc """
  Parse a SAML AuthnRequest from XML string or DOM.
  """
  def parse_authn_request(xml) when is_binary(xml) do
    with {:ok, dom} <- FnXML.DOM.parse(xml) do
      parse_authn_request(dom)
    end
  end

  def parse_authn_request(dom) do
    with {:ok, request_elem} <- select_single(dom, "/samlp:AuthnRequest"),
         {:ok, request} <- build_authn_request(request_elem) do
      {:ok, request}
    end
  end

  # Private helpers using absolute XPath
  defp select_single(dom, xpath) do
    case FnXpath.select(dom, xpath, namespaces: saml_namespaces()) do
      [element] -> {:ok, element}
      [] -> {:error, {:element_not_found, xpath}}
      _ -> {:error, {:multiple_elements, xpath}}
    end
  end

  defp saml_namespaces do
    %{
      "saml" => Constants.saml_ns(),
      "samlp" => Constants.samlp_ns(),
      "ds" => Constants.ds_ns()
    }
  end
end
```

**Deliverables**:
- [ ] `FnSAML.Constants` - All SAML URIs
- [ ] `FnSAML.Assertion` - Assertion struct
- [ ] `FnSAML.Subject`, `FnSAML.NameID`, `FnSAML.Conditions` structs
- [ ] `FnSAML.Protocol.AuthnRequest`, `Response`, `Status` structs
- [ ] `FnSAML.Parser` - XML to struct parsing

---

### Phase 2: Bindings

**Goal**: Implement HTTP-Redirect and HTTP-POST bindings

#### 2.1 HTTP-Redirect Binding

```elixir
defmodule FnSAML.Binding.HTTPRedirect do
  @moduledoc """
  HTTP-Redirect binding (DEFLATE + Base64 + URL encoding).
  """

  @doc """
  Encode a SAML message for HTTP-Redirect binding.
  Returns query string parameters.
  """
  def encode(xml, opts \\ []) do
    relay_state = Keyword.get(opts, :relay_state)
    sign_params = Keyword.get(opts, :sign)

    # 1. DEFLATE compress (raw deflate, not gzip)
    compressed = deflate(xml)

    # 2. Base64 encode
    encoded = Base.encode64(compressed)

    # 3. Build query params
    params = build_params(encoded, relay_state, opts)

    # 4. Sign if credentials provided
    params = maybe_sign(params, sign_params)

    {:ok, URI.encode_query(params)}
  end

  @doc """
  Decode a SAML message from HTTP-Redirect binding.
  """
  def decode(query_params) do
    with {:ok, encoded} <- get_saml_param(query_params),
         {:ok, compressed} <- Base.decode64(encoded),
         {:ok, xml} <- inflate(compressed) do
      {:ok, xml, Map.get(query_params, "RelayState")}
    end
  end

  @doc """
  Verify signature on redirect binding.
  IMPORTANT: Must use original URL-encoded values.
  """
  def verify_signature(query_string, certificate) do
    # Parse without decoding to preserve original encoding
    params = parse_preserving_encoding(query_string)

    with {:ok, sig_alg} <- Map.fetch(params, "SigAlg"),
         {:ok, signature} <- Map.fetch(params, "Signature"),
         :ok <- verify(params, sig_alg, signature, certificate) do
      :ok
    end
  end

  # Private helpers
  defp deflate(data) do
    z = :zlib.open()
    :zlib.deflateInit(z, :default, :deflated, -15, 8, :default)
    compressed = :zlib.deflate(z, data, :finish)
    :zlib.deflateEnd(z)
    :zlib.close(z)
    IO.iodata_to_binary(compressed)
  end

  defp inflate(data) do
    z = :zlib.open()
    :zlib.inflateInit(z, -15)
    result = :zlib.inflate(z, data)
    :zlib.inflateEnd(z)
    :zlib.close(z)
    {:ok, IO.iodata_to_binary(result)}
  rescue
    _ -> {:error, :inflate_failed}
  end
end
```

#### 2.2 HTTP-POST Binding

```elixir
defmodule FnSAML.Binding.HTTPPOST do
  @moduledoc """
  HTTP-POST binding (Base64 + HTML form).
  """

  @doc """
  Encode a SAML message for HTTP-POST binding.
  Returns Base64-encoded message.
  """
  def encode(xml, _opts \\ []) do
    {:ok, Base.encode64(xml)}
  end

  @doc """
  Decode a SAML message from HTTP-POST binding.
  """
  def decode(form_params) do
    with {:ok, encoded} <- get_saml_param(form_params),
         {:ok, xml} <- Base.decode64(encoded) do
      {:ok, xml, Map.get(form_params, "RelayState")}
    end
  end

  @doc """
  Generate HTML auto-submit form.
  """
  def generate_form(destination, saml_message, opts \\ []) do
    encoded = Base.encode64(saml_message)
    relay_state = Keyword.get(opts, :relay_state)
    param_name = Keyword.get(opts, :param_name, "SAMLResponse")

    """
    <!DOCTYPE html>
    <html>
    <head><title>SAML POST</title></head>
    <body onload="document.forms[0].submit()">
      <noscript><p>JavaScript disabled. Click Submit.</p></noscript>
      <form method="post" action="#{escape_html(destination)}">
        <input type="hidden" name="#{param_name}" value="#{encoded}"/>
        #{if relay_state, do: ~s(<input type="hidden" name="RelayState" value="#{escape_html(relay_state)}"/>), else: ""}
        <noscript><input type="submit" value="Submit"/></noscript>
      </form>
    </body>
    </html>
    """
  end
end
```

**Deliverables**:
- [ ] `FnSAML.Binding.HTTPRedirect` - DEFLATE encoding/decoding, signature handling
- [ ] `FnSAML.Binding.HTTPPOST` - Base64 encoding, HTML form generation
- [ ] `FnSAML.Binding` - Dispatcher module

---

### Phase 3: Security Layer

**Goal**: Secure signature verification and XSW attack prevention

#### 3.1 Secure Validator

```elixir
defmodule FnSAML.Security.Validator do
  @moduledoc """
  XSW-safe SAML validation.

  CRITICAL: This module prevents XML Signature Wrapping attacks by:
  1. Using absolute XPath for element selection
  2. Verifying signature covers the element being processed
  3. Never using getElementsByTagName for security elements
  """

  alias FnSAML.{Constants, Parser}

  @doc """
  Validate a SAML Response with full security checks.
  """
  def validate_response(xml, config) when is_binary(xml) do
    with {:ok, dom} <- FnXML.DOM.parse(xml),
         :ok <- validate_schema(dom),
         :ok <- validate_response_structure(dom, config),
         :ok <- validate_response_signature(dom, config),
         {:ok, assertion} <- extract_and_validate_assertion(dom, config) do
      {:ok, assertion}
    end
  end

  @doc """
  Validate Response-level attributes.
  """
  def validate_response_structure(dom, config) do
    with {:ok, response} <- select_response(dom),
         :ok <- validate_destination(response, config.acs_url),
         :ok <- validate_issuer(response, config.idp_entity_id),
         :ok <- validate_in_response_to(response, config.request_id),
         :ok <- validate_status(response) do
      :ok
    end
  end

  @doc """
  Extract assertion using absolute XPath and validate.
  """
  def extract_and_validate_assertion(dom, config) do
    # SECURITY: Use absolute XPath to select assertion
    xpath = "/samlp:Response/saml:Assertion[1]"

    with {:ok, assertion_elem} <- select_single(dom, xpath),
         :ok <- validate_assertion_signature(assertion_elem, dom, config),
         {:ok, assertion} <- Parser.build_assertion(assertion_elem),
         :ok <- validate_assertion_content(assertion, config) do
      {:ok, assertion}
    end
  end

  @doc """
  Verify signature covers the correct element.
  """
  def validate_assertion_signature(assertion_elem, dom, config) do
    assertion_id = get_attribute(assertion_elem, "ID")

    # Find signature that references this assertion
    sig_xpath = "ds:Signature/ds:SignedInfo/ds:Reference/@URI"

    case select_all(assertion_elem, sig_xpath) do
      [ref_uri] ->
        # Verify URI matches assertion ID
        expected_uri = "##{assertion_id}"
        if ref_uri == expected_uri do
          verify_signature(assertion_elem, config.idp_certificate)
        else
          {:error, :signature_reference_mismatch}
        end

      [] ->
        # Check if Response is signed instead
        validate_response_signature(dom, config)

      _ ->
        {:error, :multiple_signature_references}
    end
  end

  defp verify_signature(element, certificate) do
    FnXML.Security.Signature.verify(element, certificate)
  end
end
```

#### 3.2 Replay Prevention

```elixir
defmodule FnSAML.Security.ReplayCache do
  @moduledoc """
  Prevent assertion replay attacks.
  Uses ETS for fast lookups with TTL-based expiration.
  """

  use GenServer

  @table_name :saml_replay_cache
  @cleanup_interval :timer.minutes(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if assertion ID has been seen. Returns :ok or {:error, :replay}.
  """
  def check_and_store(assertion_id, ttl_seconds \\ 3600) do
    expires_at = System.system_time(:second) + ttl_seconds

    case :ets.insert_new(@table_name, {assertion_id, expires_at}) do
      true -> :ok
      false -> {:error, :replay_detected}
    end
  end

  @doc """
  Check if request ID exists (for InResponseTo validation).
  """
  def store_request_id(request_id, ttl_seconds \\ 300) do
    expires_at = System.system_time(:second) + ttl_seconds
    :ets.insert(@table_name, {:request, request_id, expires_at})
    :ok
  end

  def check_request_id(request_id) do
    case :ets.lookup(@table_name, {:request, request_id}) do
      [{_, _, expires_at}] ->
        if System.system_time(:second) < expires_at do
          :ets.delete(@table_name, {:request, request_id})
          :ok
        else
          {:error, :request_expired}
        end

      [] ->
        {:error, :unknown_request}
    end
  end

  # GenServer callbacks
  def init(_opts) do
    :ets.new(@table_name, [:set, :public, :named_table])
    schedule_cleanup()
    {:ok, %{}}
  end

  def handle_info(:cleanup, state) do
    now = System.system_time(:second)
    # Delete expired entries
    :ets.select_delete(@table_name, [
      {{:_, :"$1"}, [{:<, :"$1", now}], [true]},
      {{{:request, :_, :"$1"}}, [{:<, :"$1", now}], [true]}
    ])
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
```

**Deliverables**:
- [ ] `FnSAML.Security.Validator` - XSW-safe validation
- [ ] `FnSAML.Security.ReplayCache` - Replay attack prevention
- [ ] `FnSAML.Security.Signature` - Wrapper around FnXML.Security.Signature
- [ ] `FnSAML.Security.Encryption` - Wrapper for encrypted assertions

---

### Phase 4: Metadata

**Goal**: Parse and generate SAML metadata

#### 4.1 Metadata Parser

```elixir
defmodule FnSAML.Metadata do
  @moduledoc """
  Parse and generate SAML 2.0 metadata.
  """

  alias FnSAML.Metadata.{EntityDescriptor, IDPSSODescriptor, SPSSODescriptor}

  @doc """
  Parse metadata XML into struct.
  """
  def parse(xml) when is_binary(xml) do
    with {:ok, dom} <- FnXML.DOM.parse(xml),
         {:ok, entity} <- parse_entity_descriptor(dom) do
      {:ok, entity}
    end
  end

  @doc """
  Parse from URL with caching.
  """
  def fetch(url, opts \\ []) do
    cache_duration = Keyword.get(opts, :cache_duration, :timer.hours(24))

    case get_cached(url) do
      {:ok, metadata} ->
        {:ok, metadata}

      :miss ->
        with {:ok, xml} <- http_get(url),
             {:ok, metadata} <- parse(xml),
             :ok <- validate_metadata_signature(metadata, opts) do
          cache_metadata(url, metadata, cache_duration)
          {:ok, metadata}
        end
    end
  end

  @doc """
  Generate SP metadata XML.
  """
  def generate_sp_metadata(config) do
    SPSSODescriptor.to_xml(config)
  end

  @doc """
  Generate IdP metadata XML.
  """
  def generate_idp_metadata(config) do
    IDPSSODescriptor.to_xml(config)
  end
end

defmodule FnSAML.Metadata.EntityDescriptor do
  @type t :: %__MODULE__{
    entity_id: String.t(),
    valid_until: DateTime.t() | nil,
    cache_duration: String.t() | nil,
    idp_sso_descriptor: FnSAML.Metadata.IDPSSODescriptor.t() | nil,
    sp_sso_descriptor: FnSAML.Metadata.SPSSODescriptor.t() | nil,
    organization: map() | nil,
    contact_persons: [map()],
    signature: map() | nil
  }
end

defmodule FnSAML.Metadata.IDPSSODescriptor do
  @type t :: %__MODULE__{
    protocol_support: [String.t()],
    want_authn_requests_signed: boolean(),
    key_descriptors: [FnSAML.Metadata.KeyDescriptor.t()],
    single_sign_on_services: [FnSAML.Metadata.Endpoint.t()],
    single_logout_services: [FnSAML.Metadata.Endpoint.t()],
    name_id_formats: [String.t()],
    attributes: [map()]
  }
end
```

**Deliverables**:
- [ ] `FnSAML.Metadata` - Main metadata API
- [ ] `FnSAML.Metadata.EntityDescriptor` - Entity descriptor struct/parser
- [ ] `FnSAML.Metadata.IDPSSODescriptor` - IdP descriptor
- [ ] `FnSAML.Metadata.SPSSODescriptor` - SP descriptor
- [ ] `FnSAML.Metadata.KeyDescriptor` - Key handling
- [ ] `FnSAML.Metadata.Endpoint` - Endpoint types

---

### Phase 5: Service Provider

**Goal**: Complete SP implementation with Phoenix integration

#### 5.1 SP Module

```elixir
defmodule FnSAML.SP do
  @moduledoc """
  SAML 2.0 Service Provider implementation.
  """

  alias FnSAML.{Protocol, Binding, Security, Metadata}

  @doc """
  Create authentication request for IdP.
  """
  def create_authn_request(config, opts \\ []) do
    request_id = generate_id()
    issue_instant = DateTime.utc_now()

    request = %Protocol.AuthnRequest{
      id: request_id,
      version: "2.0",
      issue_instant: issue_instant,
      destination: config.idp_sso_url,
      issuer: config.sp_entity_id,
      assertion_consumer_service_url: config.acs_url,
      protocol_binding: Keyword.get(opts, :binding, Constants.binding_post()),
      name_id_policy: Keyword.get(opts, :name_id_policy),
      force_authn: Keyword.get(opts, :force_authn, false),
      is_passive: Keyword.get(opts, :is_passive, false)
    }

    # Store request ID for InResponseTo validation
    Security.ReplayCache.store_request_id(request_id)

    xml = Protocol.AuthnRequest.to_xml(request)

    case Keyword.get(opts, :binding, :redirect) do
      :redirect ->
        {:ok, query} = Binding.HTTPRedirect.encode(xml,
          relay_state: Keyword.get(opts, :relay_state),
          sign: config.sign_requests && config.sp_private_key
        )
        {:ok, :redirect, "#{config.idp_sso_url}?#{query}", request_id}

      :post ->
        {:ok, encoded} = Binding.HTTPPOST.encode(xml)
        form = Binding.HTTPPOST.generate_form(
          config.idp_sso_url,
          xml,
          relay_state: Keyword.get(opts, :relay_state),
          param_name: "SAMLRequest"
        )
        {:ok, :post, form, request_id}
    end
  end

  @doc """
  Process authentication response from IdP.
  """
  def process_response(saml_response, config, opts \\ []) do
    request_id = Keyword.get(opts, :request_id)

    validation_config = %{
      idp_entity_id: config.idp_entity_id,
      idp_certificate: config.idp_certificate,
      sp_entity_id: config.sp_entity_id,
      acs_url: config.acs_url,
      request_id: request_id,
      clock_skew: Keyword.get(opts, :clock_skew, 300)
    }

    with {:ok, xml, relay_state} <- decode_response(saml_response, config),
         {:ok, assertion} <- Security.Validator.validate_response(xml, validation_config),
         :ok <- Security.ReplayCache.check_and_store(assertion.id) do
      {:ok, build_identity(assertion), relay_state}
    end
  end

  @doc """
  Initiate single logout.
  """
  def create_logout_request(config, session, opts \\ []) do
    request = %Protocol.LogoutRequest{
      id: generate_id(),
      version: "2.0",
      issue_instant: DateTime.utc_now(),
      destination: config.idp_slo_url,
      issuer: config.sp_entity_id,
      name_id: session.name_id,
      session_index: session.session_index,
      reason: Keyword.get(opts, :reason, Constants.logout_user())
    }

    xml = Protocol.LogoutRequest.to_xml(request)
    # ... encode and return
  end

  defp build_identity(assertion) do
    %{
      name_id: assertion.subject.name_id.value,
      name_id_format: assertion.subject.name_id.format,
      session_index: assertion.authn_statement.session_index,
      attributes: extract_attributes(assertion.attribute_statement),
      authn_instant: assertion.authn_statement.authn_instant,
      issuer: assertion.issuer
    }
  end
end
```

#### 5.2 Phoenix Plug

```elixir
defmodule FnSAML.SP.Plug do
  @moduledoc """
  Phoenix Plug for SAML SP authentication.
  """

  import Plug.Conn
  alias FnSAML.SP

  def init(opts), do: opts

  @doc """
  Handle SAML callback (ACS endpoint).
  """
  def call(%{request_path: path} = conn, opts) when path == opts[:acs_path] do
    config = opts[:config]

    case conn.method do
      "POST" ->
        handle_acs_post(conn, config, opts)

      _ ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(405, "Method not allowed")
        |> halt()
    end
  end

  def call(conn, _opts), do: conn

  defp handle_acs_post(conn, config, opts) do
    saml_response = conn.body_params["SAMLResponse"]
    relay_state = conn.body_params["RelayState"]

    # Get stored request ID from session
    request_id = get_session(conn, :saml_request_id)

    case SP.process_response(saml_response, config, request_id: request_id) do
      {:ok, identity, _relay_state} ->
        conn
        |> delete_session(:saml_request_id)
        |> put_session(:saml_identity, identity)
        |> apply_callback(opts[:on_success], identity, relay_state)

      {:error, reason} ->
        apply_callback(conn, opts[:on_error], reason, relay_state)
    end
  end
end
```

**Deliverables**:
- [ ] `FnSAML.SP` - Service Provider API
- [ ] `FnSAML.SP.Config` - SP configuration struct
- [ ] `FnSAML.SP.Plug` - Phoenix Plug integration
- [ ] `FnSAML.SP.Session` - Session management helpers

---

### Phase 6: Identity Provider

**Goal**: Complete IdP implementation

#### 6.1 IdP Module

```elixir
defmodule FnSAML.IdP do
  @moduledoc """
  SAML 2.0 Identity Provider implementation.
  """

  alias FnSAML.{Protocol, Assertion, Binding, Security}

  @doc """
  Process authentication request from SP.
  """
  def process_authn_request(saml_request, config, opts \\ []) do
    binding = Keyword.get(opts, :binding, :redirect)

    with {:ok, xml, relay_state} <- decode_request(saml_request, binding),
         {:ok, request} <- Parser.parse_authn_request(xml),
         :ok <- validate_authn_request(request, config) do
      {:ok, request, relay_state}
    end
  end

  @doc """
  Create authentication response with assertion.
  """
  def create_response(request, user, config, opts \\ []) do
    now = DateTime.utc_now()
    assertion_id = generate_id()
    response_id = generate_id()

    assertion = build_assertion(assertion_id, user, request, config, now)

    # Sign assertion
    signed_assertion = if config.sign_assertions do
      Security.Signature.sign(assertion, config.idp_private_key,
        certificate: config.idp_certificate
      )
    else
      assertion
    end

    response = %Protocol.Response{
      id: response_id,
      version: "2.0",
      issue_instant: now,
      destination: request.assertion_consumer_service_url,
      in_response_to: request.id,
      issuer: config.idp_entity_id,
      status: %Protocol.Status{code: Constants.status_success()},
      assertions: [signed_assertion]
    }

    # Sign response if configured
    response_xml = if config.sign_response do
      Security.Signature.sign(
        Protocol.Response.to_xml(response),
        config.idp_private_key
      )
    else
      Protocol.Response.to_xml(response)
    end

    # Return as POST form
    form = Binding.HTTPPOST.generate_form(
      request.assertion_consumer_service_url,
      response_xml,
      relay_state: Keyword.get(opts, :relay_state)
    )

    {:ok, form}
  end

  defp build_assertion(id, user, request, config, now) do
    validity_seconds = config.assertion_validity_seconds || 300

    %Assertion{
      id: id,
      version: "2.0",
      issue_instant: now,
      issuer: config.idp_entity_id,
      subject: %Subject{
        name_id: %NameID{
          value: user.identifier,
          format: determine_name_id_format(request, config)
        },
        subject_confirmations: [
          %SubjectConfirmation{
            method: Constants.cm_bearer(),
            data: %{
              not_on_or_after: DateTime.add(now, validity_seconds, :second),
              recipient: request.assertion_consumer_service_url,
              in_response_to: request.id
            }
          }
        ]
      },
      conditions: %Conditions{
        not_before: now,
        not_on_or_after: DateTime.add(now, validity_seconds, :second),
        audience_restrictions: [request.issuer]
      },
      authn_statement: %AuthnStatement{
        authn_instant: now,
        session_index: generate_session_id(),
        authn_context: %{
          class_ref: config.authn_context_class || Constants.ac_password_protected()
        }
      },
      attribute_statement: build_attributes(user, config)
    }
  end
end
```

**Deliverables**:
- [ ] `FnSAML.IdP` - Identity Provider API
- [ ] `FnSAML.IdP.Config` - IdP configuration struct
- [ ] `FnSAML.IdP.Plug` - Phoenix Plug integration
- [ ] `FnSAML.IdP.Session` - Multi-SP session management

---

### Phase 7: XML Generation

**Goal**: Generate well-formed SAML XML

#### 7.1 XML Builder

```elixir
defmodule FnSAML.XML do
  @moduledoc """
  Build SAML XML documents.
  """

  alias FnSAML.Constants

  @doc """
  Build AuthnRequest XML.
  """
  def build_authn_request(request) do
    """
    <samlp:AuthnRequest
        xmlns:samlp="#{Constants.samlp_ns()}"
        xmlns:saml="#{Constants.saml_ns()}"
        ID="#{request.id}"
        Version="2.0"
        IssueInstant="#{format_datetime(request.issue_instant)}"
        #{attr_if("Destination", request.destination)}
        #{attr_if("AssertionConsumerServiceURL", request.assertion_consumer_service_url)}
        #{attr_if("ProtocolBinding", request.protocol_binding)}
        #{attr_if("ForceAuthn", request.force_authn, &to_string/1)}
        #{attr_if("IsPassive", request.is_passive, &to_string/1)}>
      <saml:Issuer>#{escape(request.issuer)}</saml:Issuer>
      #{build_name_id_policy(request.name_id_policy)}
      #{build_requested_authn_context(request.requested_authn_context)}
    </samlp:AuthnRequest>
    """
    |> String.trim()
  end

  @doc """
  Build Response XML.
  """
  def build_response(response) do
    """
    <samlp:Response
        xmlns:samlp="#{Constants.samlp_ns()}"
        xmlns:saml="#{Constants.saml_ns()}"
        ID="#{response.id}"
        Version="2.0"
        IssueInstant="#{format_datetime(response.issue_instant)}"
        #{attr_if("Destination", response.destination)}
        #{attr_if("InResponseTo", response.in_response_to)}>
      <saml:Issuer>#{escape(response.issuer)}</saml:Issuer>
      #{build_status(response.status)}
      #{Enum.map_join(response.assertions, "\n", &build_assertion/1)}
    </samlp:Response>
    """
    |> String.trim()
  end

  @doc """
  Build Assertion XML.
  """
  def build_assertion(assertion) do
    """
    <saml:Assertion
        xmlns:saml="#{Constants.saml_ns()}"
        Version="2.0"
        ID="#{assertion.id}"
        IssueInstant="#{format_datetime(assertion.issue_instant)}">
      <saml:Issuer>#{escape(assertion.issuer)}</saml:Issuer>
      #{build_subject(assertion.subject)}
      #{build_conditions(assertion.conditions)}
      #{build_authn_statement(assertion.authn_statement)}
      #{build_attribute_statement(assertion.attribute_statement)}
    </saml:Assertion>
    """
    |> String.trim()
  end

  # Helper functions
  defp format_datetime(dt), do: DateTime.to_iso8601(dt)

  defp escape(nil), do: ""
  defp escape(s), do: FnXML.escape(s)

  defp attr_if(_, nil), do: ""
  defp attr_if(_, nil, _), do: ""
  defp attr_if(name, value), do: ~s(#{name}="#{escape(value)}")
  defp attr_if(name, value, transform), do: ~s(#{name}="#{escape(transform.(value))}")
end
```

**Deliverables**:
- [ ] `FnSAML.XML` - XML generation utilities
- [ ] XML builders for all protocol messages
- [ ] XML builders for assertions
- [ ] XML builders for metadata

---

### Phase 8: Testing & Conformance

**Goal**: Comprehensive testing including interoperability

#### 8.1 Test Structure

```
test/
├── fn_saml/
│   ├── assertion_test.exs
│   ├── parser_test.exs
│   ├── binding/
│   │   ├── http_redirect_test.exs
│   │   └── http_post_test.exs
│   ├── security/
│   │   ├── validator_test.exs
│   │   ├── xsw_attack_test.exs      # XSW attack vectors
│   │   └── replay_cache_test.exs
│   ├── metadata_test.exs
│   ├── sp_test.exs
│   └── idp_test.exs
├── integration/
│   ├── sp_idp_flow_test.exs         # Full SSO flow
│   └── single_logout_test.exs
└── fixtures/
    ├── assertions/
    ├── responses/
    ├── metadata/
    └── attacks/                      # XSW attack samples
```

#### 8.2 XSW Attack Test Cases

```elixir
defmodule FnSAML.Security.XSWAttackTest do
  use ExUnit.Case

  @moduletag :security

  describe "XML Signature Wrapping prevention" do
    test "rejects XSW1: cloned unsigned assertion" do
      # Attack: Clone assertion, modify clone, signature still valid for original
      xml = File.read!("test/fixtures/attacks/xsw1.xml")
      assert {:error, _} = FnSAML.Security.Validator.validate_response(xml, config())
    end

    test "rejects XSW2: assertion moved to Extensions" do
      xml = File.read!("test/fixtures/attacks/xsw2.xml")
      assert {:error, _} = FnSAML.Security.Validator.validate_response(xml, config())
    end

    test "rejects XSW3: signature wraps malicious assertion" do
      xml = File.read!("test/fixtures/attacks/xsw3.xml")
      assert {:error, _} = FnSAML.Security.Validator.validate_response(xml, config())
    end

    # ... tests for XSW4-XSW8
  end
end
```

**Deliverables**:
- [ ] Unit tests for all modules
- [ ] XSW attack test suite
- [ ] Integration tests for full SSO flow
- [ ] Interoperability tests with common IdPs (Okta, Azure AD, etc.)

---

## Dependencies

### Required FnXML Components

| Component | Usage |
|-----------|-------|
| `FnXML.DOM` | Parse SAML XML |
| `FnXML.Security.Signature` | XML-DSig sign/verify |
| `FnXML.Security.Encryption` | Encrypted assertions |
| `FnXML.Security.C14N` | Canonicalization |
| `FnXPath` | Element selection |

### External Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:fn_xml, path: "../fnxml"},
    {:fn_xpath, path: "../fnxpath"},
    # For HTTP metadata fetching (optional)
    {:req, "~> 0.4", optional: true},
    # For Phoenix integration (optional)
    {:plug, "~> 1.14", optional: true}
  ]
end
```

---

## Security Checklist

### Must Implement

- [ ] Schema validation before processing
- [ ] Absolute XPath for element selection
- [ ] Signature reference URI validation
- [ ] InResponseTo validation
- [ ] Destination validation
- [ ] Audience validation
- [ ] Timestamp validation with clock skew
- [ ] Replay detection
- [ ] Certificate validation

### Must NOT Do

- [ ] Never use `getElementsByTagName` for security elements
- [ ] Never trust embedded KeyInfo
- [ ] Never process unsigned assertions (unless explicitly configured)
- [ ] Never allow external entity resolution
- [ ] Never skip signature verification

---

## API Summary

### Service Provider

```elixir
# Configuration
config = %FnSAML.SP.Config{
  sp_entity_id: "https://myapp.example.com",
  acs_url: "https://myapp.example.com/saml/acs",
  idp_entity_id: "https://idp.example.com",
  idp_sso_url: "https://idp.example.com/sso",
  idp_certificate: File.read!("idp_cert.pem"),
  sp_private_key: File.read!("sp_key.pem"),  # optional, for signing
  sign_requests: false
}

# Initiate login
{:ok, :redirect, url, request_id} = FnSAML.SP.create_authn_request(config)

# Process response
{:ok, identity, relay_state} = FnSAML.SP.process_response(
  saml_response,
  config,
  request_id: request_id
)
```

### Identity Provider

```elixir
# Configuration
config = %FnSAML.IdP.Config{
  idp_entity_id: "https://idp.example.com",
  idp_private_key: File.read!("idp_key.pem"),
  idp_certificate: File.read!("idp_cert.pem"),
  sign_assertions: true,
  sign_response: true
}

# Process AuthnRequest
{:ok, request, relay_state} = FnSAML.IdP.process_authn_request(saml_request, config)

# Create Response (after authentication)
{:ok, html_form} = FnSAML.IdP.create_response(request, user, config,
  relay_state: relay_state
)
```

### Metadata

```elixir
# Parse IdP metadata
{:ok, metadata} = FnSAML.Metadata.parse(File.read!("idp_metadata.xml"))

# Generate SP metadata
sp_metadata_xml = FnSAML.Metadata.generate_sp_metadata(sp_config)
```

---

## Milestones

| Phase | Milestone | Estimated Effort |
|-------|-----------|------------------|
| 1 | Core data structures + parsing | Foundation |
| 2 | HTTP-Redirect + HTTP-POST bindings | Bindings |
| 3 | Security validation (XSW prevention) | Critical |
| 4 | Metadata parsing + generation | Metadata |
| 5 | Service Provider implementation | SP Complete |
| 6 | Identity Provider implementation | IdP Complete |
| 7 | XML generation | XML Builder |
| 8 | Testing + conformance | Production Ready |

---

## References

- [spec_saml.md](./spec_saml.md) - Full SAML 2.0 specification reference
- [OWASP SAML Security](https://cheatsheetseries.owasp.org/cheatsheets/SAML_Security_Cheat_Sheet.html)
- [On Breaking SAML](https://www.usenix.org/system/files/conference/usenixsecurity12/sec12-final91.pdf)
