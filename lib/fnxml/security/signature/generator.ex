defmodule FnXML.Security.Signature.Generator do
  @moduledoc """
  XML Signature generation.

  Implements the signature generation process according to W3C XML-Signature:

  1. Create Reference elements with digest values
  2. Create SignedInfo with canonicalization and signature methods
  3. Canonicalize SignedInfo
  4. Sign the canonical SignedInfo
  5. Assemble complete Signature element
  """

  alias FnXML.C14N
  alias FnXML.Security.{Algorithms, Namespaces}
  alias FnXML.Security.Signature.Reference

  @default_opts [
    signature_algorithm: :rsa_sha256,
    digest_algorithm: :sha256,
    c14n_algorithm: :exc_c14n,
    type: :enveloped,
    reference_uri: "",
    inclusive_namespaces: []
  ]

  @doc """
  Generate an XML Signature for the given document.
  """
  @spec sign(binary() | Enumerable.t(), term(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def sign(xml, private_key, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)

    with {:ok, xml_binary} <- ensure_binary(xml),
         {:ok, reference} <- create_reference(xml_binary, opts),
         {:ok, signed_info} <- create_signed_info(reference, opts),
         {:ok, signature_value} <- compute_signature(signed_info, private_key, opts),
         {:ok, signature_element} <- assemble_signature(signed_info, signature_value, opts) do
      case opts[:type] do
        :enveloped -> insert_enveloped_signature(xml_binary, signature_element)
        :enveloping -> create_enveloping_signature(xml_binary, signature_element, opts)
        :detached -> {:ok, signature_element}
      end
    end
  end

  # Ensure we have binary XML
  defp ensure_binary(xml) when is_binary(xml), do: {:ok, xml}

  defp ensure_binary(stream) do
    try do
      binary =
        stream
        |> Enum.to_list()
        |> serialize_events()

      {:ok, binary}
    rescue
      e -> {:error, {:serialization_failed, e}}
    end
  end

  defp serialize_events(events) do
    events
    |> C14N.canonicalize()
  end

  # Create Reference element with computed digest
  defp create_reference(xml, opts) do
    Reference.create(xml, opts)
  end

  # Create SignedInfo element
  defp create_signed_info(reference, opts) do
    c14n_uri = C14N.algorithm_uri(opts[:c14n_algorithm])
    sig_uri = Algorithms.signature_algorithm_uri(opts[:signature_algorithm])

    # Build inclusive namespaces element if needed
    inclusive_ns_element =
      case opts[:c14n_algorithm] do
        algo when algo in [:exc_c14n, :exc_c14n_with_comments] ->
          case opts[:inclusive_namespaces] do
            [] ->
              ""

            prefixes ->
              prefix_list = Enum.join(prefixes, " ")

              """
              <ec:InclusiveNamespaces xmlns:ec="#{Namespaces.exc_c14n()}" PrefixList="#{prefix_list}"/>
              """
          end

        _ ->
          ""
      end

    signed_info = """
    <ds:SignedInfo xmlns:ds="#{Namespaces.dsig()}">
      <ds:CanonicalizationMethod Algorithm="#{c14n_uri}">#{inclusive_ns_element}</ds:CanonicalizationMethod>
      <ds:SignatureMethod Algorithm="#{sig_uri}"/>
      #{reference}
    </ds:SignedInfo>
    """

    {:ok, String.trim(signed_info)}
  end

  # Compute signature over canonical SignedInfo
  defp compute_signature(signed_info, private_key, opts) do
    # Parse and canonicalize SignedInfo
    events = FnXML.Parser.parse(signed_info)

    canonical =
      C14N.canonicalize(events,
        algorithm: opts[:c14n_algorithm],
        inclusive_namespaces: opts[:inclusive_namespaces]
      )

    # Sign the canonical form
    Algorithms.sign(canonical, opts[:signature_algorithm], private_key)
  end

  # Assemble the complete Signature element
  defp assemble_signature(signed_info, signature_value, opts) do
    sig_value_b64 = Base.encode64(signature_value)

    # Optional ID attribute
    id_attr =
      case opts[:id] do
        nil -> ""
        id -> ~s( Id="#{id}")
      end

    signature = """
    <ds:Signature xmlns:ds="#{Namespaces.dsig()}"#{id_attr}>
      #{signed_info}
      <ds:SignatureValue>#{sig_value_b64}</ds:SignatureValue>
    </ds:Signature>
    """

    {:ok, String.trim(signature)}
  end

  # Insert enveloped signature into document
  defp insert_enveloped_signature(xml, signature_element) do
    # Find the root element and insert signature before closing tag
    case find_root_element_end(xml) do
      {:ok, position} ->
        {before, after_close} = String.split_at(xml, position)
        {:ok, before <> "\n  " <> signature_element <> "\n" <> after_close}

      :error ->
        {:error, :invalid_xml_structure}
    end
  end

  defp find_root_element_end(xml) do
    # Find the position of the last closing tag
    # This is a simple approach - find the last </
    case :binary.matches(xml, "</") do
      [] ->
        :error

      matches ->
        {pos, _len} = List.last(matches)
        {:ok, pos}
    end
  end

  # Create enveloping signature (content inside Object element)
  defp create_enveloping_signature(xml, signature_element, opts) do
    object_id = opts[:object_id] || "object-1"

    # Wrap content in Object element
    object_element = """
    <ds:Object xmlns:ds="#{Namespaces.dsig()}" Id="#{object_id}">
      #{xml}
    </ds:Object>
    """

    # Insert Object into Signature
    # Find </ds:Signature> and insert Object before it
    case String.split(signature_element, "</ds:Signature>") do
      [before, _after] ->
        {:ok, before <> "\n  " <> String.trim(object_element) <> "\n</ds:Signature>"}

      _ ->
        {:error, :invalid_signature_structure}
    end
  end
end
