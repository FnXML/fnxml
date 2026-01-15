defmodule FnXML.Security.Signature do
  @moduledoc """
  XML Digital Signature implementation following W3C XML-Signature Syntax and Processing.

  This module provides functions to sign and verify XML documents according to
  the W3C XML Signature specification (xmldsig-core).

  ## Features

  - **Enveloped signatures**: Signature embedded within the signed document
  - **Enveloping signatures**: Signed content embedded within the signature
  - **Detached signatures**: Signature references external content

  ## Supported Algorithms

  ### Canonicalization
  - Canonical XML 1.0 (with/without comments)
  - Exclusive Canonical XML 1.0 (with/without comments)

  ### Digest
  - SHA-256, SHA-384, SHA-512

  ### Signature
  - RSA-SHA256, RSA-SHA384, RSA-SHA512
  - ECDSA-SHA256, ECDSA-SHA384, ECDSA-SHA512

  ## Usage

  ### Signing a Document

      # Generate an enveloped signature
      {:ok, signed_doc} = FnXML.Security.Signature.sign(
        xml_doc,
        private_key,
        signature_algorithm: :rsa_sha256,
        digest_algorithm: :sha256,
        c14n_algorithm: :exc_c14n,
        type: :enveloped
      )

  ### Verifying a Signature

      {:ok, :valid} = FnXML.Security.Signature.verify(signed_doc, public_key)

  ## Signature Structure

  An XML Signature has the following structure:

      <Signature xmlns="http://www.w3.org/2000/09/xmldsig#">
        <SignedInfo>
          <CanonicalizationMethod Algorithm="..."/>
          <SignatureMethod Algorithm="..."/>
          <Reference URI="...">
            <Transforms>
              <Transform Algorithm="..."/>
            </Transforms>
            <DigestMethod Algorithm="..."/>
            <DigestValue>...</DigestValue>
          </Reference>
        </SignedInfo>
        <SignatureValue>...</SignatureValue>
        <KeyInfo>
          ...
        </KeyInfo>
      </Signature>

  ## References

  - W3C XML Signature: https://www.w3.org/TR/xmldsig-core/
  - W3C XML Signature 1.1: https://www.w3.org/TR/xmldsig-core1/
  """

  alias FnXML.Namespaces, as: XMLNamespaces
  alias FnXML.Security.{Algorithms, C14N, Namespaces}
  alias FnXML.Security.Signature.{Generator, Verifier}

  # Reference alias currently unused - uncomment when needed
  # alias FnXML.Security.Signature.Reference

  @type signature_type :: :enveloped | :enveloping | :detached

  @type sign_opts :: [
          signature_algorithm: Algorithms.signature_algorithm(),
          digest_algorithm: Algorithms.digest_algorithm(),
          c14n_algorithm: C14N.algorithm(),
          type: signature_type(),
          reference_uri: String.t(),
          id: String.t(),
          inclusive_namespaces: [String.t()]
        ]

  @type verify_opts :: [
          trusted_certificates: [binary()]
        ]

  @doc """
  Sign an XML document or element.

  ## Options

  - `:signature_algorithm` - Signature algorithm (default: `:rsa_sha256`)
  - `:digest_algorithm` - Digest algorithm for references (default: `:sha256`)
  - `:c14n_algorithm` - Canonicalization algorithm (default: `:exc_c14n`)
  - `:type` - Signature type: `:enveloped`, `:enveloping`, `:detached` (default: `:enveloped`)
  - `:reference_uri` - URI for the reference (default: `""` for enveloped)
  - `:id` - ID for the Signature element
  - `:inclusive_namespaces` - Namespace prefixes to include for exclusive C14N

  ## Examples

      # Sign with enveloped signature
      {:ok, signed_xml} = Signature.sign(xml, private_key, type: :enveloped)

      # Sign with specific algorithms
      {:ok, signed_xml} = Signature.sign(xml, private_key,
        signature_algorithm: :rsa_sha512,
        digest_algorithm: :sha512,
        c14n_algorithm: :exc_c14n
      )

  """
  @spec sign(binary() | Enumerable.t(), term(), sign_opts()) ::
          {:ok, binary()} | {:error, term()}
  def sign(xml, private_key, opts \\ []) do
    Generator.sign(xml, private_key, opts)
  end

  @doc """
  Verify an XML signature.

  Validates all references in the signature and verifies the signature value.

  ## Options

  - `:trusted_certificates` - List of trusted certificates for key validation

  ## Returns

  - `{:ok, :valid}` - Signature is valid
  - `{:error, reason}` - Signature is invalid or verification failed

  ## Examples

      {:ok, :valid} = Signature.verify(signed_xml, public_key)

      case Signature.verify(signed_xml, public_key) do
        {:ok, :valid} -> IO.puts("Signature valid")
        {:error, :invalid_signature} -> IO.puts("Signature invalid")
        {:error, {:digest_mismatch, ref}} -> IO.puts("Reference digest mismatch: \#{ref}")
      end

  """
  @spec verify(binary() | Enumerable.t(), term(), verify_opts()) ::
          {:ok, :valid} | {:error, term()}
  def verify(xml, public_key, opts \\ []) do
    Verifier.verify(xml, public_key, opts)
  end

  @doc """
  Extract the Signature element from a signed document.

  Returns the Signature element as XML binary, or error if not found.

  ## Examples

      {:ok, sig_xml} = Signature.extract_signature(signed_doc)

  """
  @spec extract_signature(binary()) :: {:ok, binary()} | {:error, :signature_not_found}
  def extract_signature(xml) when is_binary(xml) do
    # Parse and find Signature element
    events = FnXML.Parser.parse(xml)
    extract_signature_element(events)
  end

  @doc """
  Validate the structure of a Signature element.

  Checks that all required elements are present and properly formatted.

  ## Returns

  - `:ok` - Structure is valid
  - `{:error, reason}` - Structure is invalid

  """
  @spec validate_structure(binary()) :: :ok | {:error, term()}
  def validate_structure(signature_xml) when is_binary(signature_xml) do
    events = FnXML.Parser.parse(signature_xml)
    do_validate_structure(events)
  end

  @doc """
  Get information about a signature without verifying it.

  Returns a map with signature metadata including algorithms used,
  references, and key info.

  ## Examples

      {:ok, info} = Signature.info(signed_doc)
      # => %{
      #   signature_algorithm: :rsa_sha256,
      #   c14n_algorithm: :exc_c14n,
      #   references: [%{uri: "", digest_algorithm: :sha256}],
      #   key_info: %{...}
      # }

  """
  @spec info(binary()) :: {:ok, map()} | {:error, term()}
  def info(xml) when is_binary(xml) do
    with {:ok, sig_xml} <- extract_signature(xml) do
      parse_signature_info(sig_xml)
    end
  end

  # ==========================================================================
  # Internal Functions
  # ==========================================================================

  defp extract_signature_element(events) do
    # Find the Signature element in the event stream
    dsig_ns = Namespaces.dsig()

    events
    |> find_element("Signature", dsig_ns)
    |> case do
      {:ok, sig_events} ->
        {:ok, serialize_events(sig_events)}

      :not_found ->
        {:error, :signature_not_found}
    end
  end

  defp find_element(events, target_name, target_ns) do
    # Precompute prefixed name for use in guards
    ds_target_name = "ds:" <> target_name

    # Track depth and collect events when inside target element
    {result, _} =
      Enum.reduce_while(events, {:not_found, {0, []}}, fn event, {status, {depth, acc}} ->
        case {status, event, depth} do
          # Found start of target element
          {:not_found, {:start_element, name, attrs, _, _, _}, 0}
          when name == target_name or name == ds_target_name ->
            # Check namespace
            if element_in_namespace?(name, attrs, target_ns) do
              {:cont, {:collecting, {1, [normalize_for_serialize(event)]}}}
            else
              {:cont, {:not_found, {0, []}}}
            end

          {:not_found, {:start_element, name, attrs, _}, 0}
          when name == target_name or name == ds_target_name ->
            if element_in_namespace?(name, attrs, target_ns) do
              {:cont, {:collecting, {1, [normalize_for_serialize(event)]}}}
            else
              {:cont, {:not_found, {0, []}}}
            end

          # Inside target element - track depth
          {:collecting, {:start_element, _, _, _, _, _}, _depth} ->
            {:cont, {:collecting, {depth + 1, [normalize_for_serialize(event) | acc]}}}

          {:collecting, {:start_element, _, _, _}, _depth} ->
            {:cont, {:collecting, {depth + 1, [normalize_for_serialize(event) | acc]}}}

          {:collecting, {:end_element, _, _, _, _}, 1} ->
            # End of target element
            final_acc = [normalize_for_serialize(event) | acc]
            {:halt, {{:ok, Enum.reverse(final_acc)}, {0, []}}}

          {:collecting, {:end_element, _, _}, 1} ->
            final_acc = [normalize_for_serialize(event) | acc]
            {:halt, {{:ok, Enum.reverse(final_acc)}, {0, []}}}

          {:collecting, {:end_element, _}, 1} ->
            final_acc = [normalize_for_serialize(event) | acc]
            {:halt, {{:ok, Enum.reverse(final_acc)}, {0, []}}}

          {:collecting, {:end_element, _, _, _, _}, _depth} ->
            {:cont, {:collecting, {depth - 1, [normalize_for_serialize(event) | acc]}}}

          {:collecting, {:end_element, _, _}, _depth} ->
            {:cont, {:collecting, {depth - 1, [normalize_for_serialize(event) | acc]}}}

          {:collecting, {:end_element, _}, _depth} ->
            {:cont, {:collecting, {depth - 1, [normalize_for_serialize(event) | acc]}}}

          {:collecting, _, _depth} ->
            {:cont, {:collecting, {depth, [normalize_for_serialize(event) | acc]}}}

          _ ->
            {:cont, {status, {depth, acc}}}
        end
      end)

    result
  end

  defp element_in_namespace?(name, attrs, target_ns) do
    # Check if element has the target namespace
    cond do
      # Prefixed element (ds:Signature)
      String.starts_with?(name, "ds:") ->
        # Look for xmlns:ds declaration
        Enum.any?(attrs, fn
          {"xmlns:ds", ^target_ns} -> true
          _ -> false
        end)

      # Unprefixed element with default namespace
      true ->
        Enum.any?(attrs, fn
          {"xmlns", ^target_ns} -> true
          _ -> false
        end)
    end
  end

  # Normalize events to 4-tuple format for serialization
  defp normalize_for_serialize({:start_element, tag, attrs, _, _, _}),
    do: {:start_element, tag, attrs, nil}

  defp normalize_for_serialize({:end_element, tag, _, _, _}), do: {:end_element, tag, nil}
  defp normalize_for_serialize({:characters, content, _, _, _}), do: {:characters, content, nil}
  defp normalize_for_serialize(event), do: event

  defp serialize_events(events) do
    events
    |> Enum.map(&event_to_iodata/1)
    |> IO.iodata_to_binary()
  end

  defp event_to_iodata({:start_element, tag, attrs, _}) do
    attr_str =
      attrs
      |> Enum.map(fn {k, v} -> [" ", k, "=\"", escape_attr(v), "\""] end)

    ["<", tag, attr_str, ">"]
  end

  defp event_to_iodata({:end_element, _, _}), do: []

  defp event_to_iodata({:end_element, tag}) do
    ["</", tag, ">"]
  end

  defp event_to_iodata({:characters, content, _}) do
    escape_text(content)
  end

  defp event_to_iodata(_), do: []

  defp escape_text(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_attr(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace("\"", "&quot;")
  end

  defp do_validate_structure(events) do
    required_elements = [
      "SignedInfo",
      "SignatureValue",
      "CanonicalizationMethod",
      "SignatureMethod",
      "Reference",
      "DigestMethod",
      "DigestValue"
    ]

    found_elements =
      events
      |> Enum.filter(fn
        {:start_element, _, _, _, _, _} -> true
        {:start_element, _, _, _} -> true
        _ -> false
      end)
      |> Enum.map(fn
        {:start_element, name, _, _, _, _} -> XMLNamespaces.local_part(name)
        {:start_element, name, _, _} -> XMLNamespaces.local_part(name)
      end)
      |> MapSet.new()

    missing = Enum.reject(required_elements, &(&1 in found_elements))

    case missing do
      [] -> :ok
      _ -> {:error, {:missing_elements, missing}}
    end
  end

  defp parse_signature_info(sig_xml) do
    events = FnXML.Parser.parse(sig_xml)

    info = %{
      signature_algorithm: nil,
      c14n_algorithm: nil,
      digest_algorithms: [],
      references: [],
      has_key_info: false
    }

    {:ok, extract_info_from_events(events, info)}
  end

  defp extract_info_from_events(events, info) do
    Enum.reduce(events, info, fn event, acc ->
      case event do
        {:start_element, name, attrs, _, _, _} ->
          update_info_from_element(XMLNamespaces.local_part(name), attrs, acc)

        {:start_element, name, attrs, _} ->
          update_info_from_element(XMLNamespaces.local_part(name), attrs, acc)

        _ ->
          acc
      end
    end)
  end

  defp update_info_from_element("CanonicalizationMethod", attrs, info) do
    case find_attr(attrs, "Algorithm") do
      nil ->
        info

      uri ->
        case C14N.algorithm_atom(uri) do
          {:ok, algo} -> %{info | c14n_algorithm: algo}
          _ -> info
        end
    end
  end

  defp update_info_from_element("SignatureMethod", attrs, info) do
    case find_attr(attrs, "Algorithm") do
      nil ->
        info

      uri ->
        case Algorithms.signature_algorithm_from_uri(uri) do
          {:ok, algo} -> %{info | signature_algorithm: algo}
          _ -> info
        end
    end
  end

  defp update_info_from_element("DigestMethod", attrs, info) do
    case find_attr(attrs, "Algorithm") do
      nil ->
        info

      uri ->
        case Algorithms.digest_algorithm_from_uri(uri) do
          {:ok, algo} -> %{info | digest_algorithms: [algo | info.digest_algorithms]}
          _ -> info
        end
    end
  end

  defp update_info_from_element("Reference", attrs, info) do
    ref = %{
      uri: find_attr(attrs, "URI") || "",
      type: find_attr(attrs, "Type")
    }

    %{info | references: [ref | info.references]}
  end

  defp update_info_from_element("KeyInfo", _attrs, info) do
    %{info | has_key_info: true}
  end

  defp update_info_from_element(_name, _attrs, info), do: info

  defp find_attr(attrs, name) do
    case Enum.find(attrs, fn {k, _} -> k == name end) do
      {_, v} -> v
      nil -> nil
    end
  end
end
