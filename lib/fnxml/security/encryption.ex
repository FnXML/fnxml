defmodule FnXML.Security.Encryption do
  @moduledoc """
  XML Encryption implementation following W3C XML Encryption Syntax and Processing.

  This module provides functions to encrypt and decrypt XML content according to
  the W3C XML Encryption specification (xmlenc-core).

  ## Features

  - **Element encryption**: Encrypt entire elements including tags
  - **Content encryption**: Encrypt just the content of an element
  - **Key wrapping**: Encrypt symmetric keys with recipient's public key

  ## Supported Algorithms

  ### Content Encryption
  - AES-128-GCM, AES-256-GCM (recommended)
  - AES-128-CBC, AES-256-CBC

  ### Key Transport
  - RSA-OAEP

  ## Usage

  ### Encrypting an Element

      # Encrypt an element with a symmetric key
      {:ok, encrypted_doc} = FnXML.Security.Encryption.encrypt(
        xml_doc,
        "#element-id",
        symmetric_key,
        algorithm: :aes_256_gcm,
        type: :element
      )

      # Encrypt with key transport (symmetric key encrypted with recipient's public key)
      {:ok, encrypted_doc} = FnXML.Security.Encryption.encrypt(
        xml_doc,
        "#element-id",
        symmetric_key,
        algorithm: :aes_256_gcm,
        key_transport: {:rsa_oaep, recipient_public_key}
      )

  ### Decrypting

      {:ok, decrypted_doc} = FnXML.Security.Encryption.decrypt(
        encrypted_doc,
        symmetric_key
      )

      # With key transport
      {:ok, decrypted_doc} = FnXML.Security.Encryption.decrypt(
        encrypted_doc,
        private_key: recipient_private_key
      )

  ## EncryptedData Structure

      <xenc:EncryptedData xmlns:xenc="http://www.w3.org/2001/04/xmlenc#">
        <xenc:EncryptionMethod Algorithm="..."/>
        <ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
          <xenc:EncryptedKey>
            <xenc:EncryptionMethod Algorithm="..."/>
            <xenc:CipherData>
              <xenc:CipherValue>...</xenc:CipherValue>
            </xenc:CipherData>
          </xenc:EncryptedKey>
        </ds:KeyInfo>
        <xenc:CipherData>
          <xenc:CipherValue>...</xenc:CipherValue>
        </xenc:CipherData>
      </xenc:EncryptedData>

  ## References

  - W3C XML Encryption: https://www.w3.org/TR/xmlenc-core/
  - W3C XML Encryption 1.1: https://www.w3.org/TR/xmlenc-core1/
  """

  alias FnXML.Namespaces, as: XMLNamespaces
  alias FnXML.Security.{Algorithms, Namespaces}

  # C14N alias currently unused in this module - uncomment when needed
  # alias FnXML.Security.C14N
  alias FnXML.Security.Encryption.{Encryptor, Decryptor}

  @type encryption_type :: :element | :content

  @type encrypt_opts :: [
          algorithm: Algorithms.encryption_algorithm(),
          type: encryption_type(),
          key_transport: {Algorithms.key_transport_algorithm(), term()} | nil,
          id: String.t()
        ]

  @type decrypt_opts :: [
          private_key: term()
        ]

  @doc """
  Encrypt XML content.

  ## Arguments

  - `xml` - The XML document (binary or event stream)
  - `target` - Target element selector (URI like "#id" or XPath)
  - `key` - Symmetric encryption key (or nil if using key_transport)
  - `opts` - Encryption options

  ## Options

  - `:algorithm` - Encryption algorithm (default: `:aes_256_gcm`)
  - `:type` - Encryption type: `:element` or `:content` (default: `:element`)
  - `:key_transport` - Tuple of `{algorithm, public_key}` for key wrapping
  - `:id` - ID for the EncryptedData element

  ## Examples

      # Encrypt with existing key
      key = Algorithms.generate_key(32)
      {:ok, encrypted} = Encryption.encrypt(xml, "#secret", key)

      # Encrypt with key transport
      {:ok, encrypted} = Encryption.encrypt(xml, "#secret", nil,
        key_transport: {:rsa_oaep, recipient_public_key}
      )

  """
  @spec encrypt(binary(), String.t(), binary() | nil, encrypt_opts()) ::
          {:ok, binary()} | {:error, term()}
  def encrypt(xml, target, key, opts \\ []) do
    Encryptor.encrypt(xml, target, key, opts)
  end

  @doc """
  Decrypt encrypted XML content.

  ## Arguments

  - `xml` - The XML document containing EncryptedData
  - `key_or_opts` - Either a symmetric key or options with private_key

  ## Options

  - `:private_key` - Private key for decrypting the encrypted key

  ## Examples

      # Decrypt with known symmetric key
      {:ok, decrypted} = Encryption.decrypt(encrypted_xml, symmetric_key)

      # Decrypt with private key (key transport)
      {:ok, decrypted} = Encryption.decrypt(encrypted_xml, private_key: my_private_key)

  """
  @spec decrypt(binary(), binary() | decrypt_opts()) ::
          {:ok, binary()} | {:error, term()}
  def decrypt(xml, key) when is_binary(key) do
    Decryptor.decrypt(xml, key: key)
  end

  def decrypt(xml, opts) when is_list(opts) do
    Decryptor.decrypt(xml, opts)
  end

  @doc """
  Extract EncryptedData elements from a document.

  Returns a list of EncryptedData element information.
  """
  @spec find_encrypted_data(binary()) :: {:ok, [map()]} | {:error, term()}
  def find_encrypted_data(xml) when is_binary(xml) do
    events = FnXML.Parser.parse(xml)
    {:ok, extract_encrypted_data_elements(events)}
  end

  @doc """
  Get information about encrypted content without decrypting.

  Returns metadata about the encryption including algorithms used.
  """
  @spec info(binary()) :: {:ok, map()} | {:error, term()}
  def info(xml) when is_binary(xml) do
    with {:ok, encrypted_list} <- find_encrypted_data(xml) do
      case encrypted_list do
        [] -> {:error, :no_encrypted_data}
        [first | _] -> {:ok, first}
      end
    end
  end

  # ==========================================================================
  # Internal Functions
  # ==========================================================================

  defp extract_encrypted_data_elements(events) do
    xenc_ns = Namespaces.xenc()

    state = %{
      in_encrypted_data: false,
      depth: 0,
      current: nil,
      results: []
    }

    result =
      Enum.reduce(events, state, fn event, acc ->
        case {acc.in_encrypted_data, event} do
          # Found start of EncryptedData
          {false, {:start_element, name, attrs, _, _, _}}
          when name == "EncryptedData" or name == "xenc:EncryptedData" ->
            if in_xenc_namespace?(name, attrs, xenc_ns) do
              %{
                acc
                | in_encrypted_data: true,
                  depth: 1,
                  current: %{
                    id: find_attr(attrs, "Id"),
                    type: parse_type_attr(find_attr(attrs, "Type")),
                    algorithm: nil,
                    key_transport_algorithm: nil,
                    has_encrypted_key: false
                  }
              }
            else
              acc
            end

          {false, {:start_element, name, attrs, _}}
          when name == "EncryptedData" or name == "xenc:EncryptedData" ->
            if in_xenc_namespace?(name, attrs, xenc_ns) do
              %{
                acc
                | in_encrypted_data: true,
                  depth: 1,
                  current: %{
                    id: find_attr(attrs, "Id"),
                    type: parse_type_attr(find_attr(attrs, "Type")),
                    algorithm: nil,
                    key_transport_algorithm: nil,
                    has_encrypted_key: false
                  }
              }
            else
              acc
            end

          # Inside EncryptedData - track depth and collect info
          {true, {:start_element, name, attrs, _, _, _}} ->
            acc
            |> update_depth(1)
            |> update_encrypted_info(XMLNamespaces.local_part(name), attrs)

          {true, {:start_element, name, attrs, _}} ->
            acc
            |> update_depth(1)
            |> update_encrypted_info(XMLNamespaces.local_part(name), attrs)

          # End of EncryptedData
          {true, {:end_element, _, _, _, _}} when acc.depth == 1 ->
            %{
              acc
              | in_encrypted_data: false,
                depth: 0,
                current: nil,
                results: [acc.current | acc.results]
            }

          {true, {:end_element, _, _}} when acc.depth == 1 ->
            %{
              acc
              | in_encrypted_data: false,
                depth: 0,
                current: nil,
                results: [acc.current | acc.results]
            }

          {true, {:end_element, _}} when acc.depth == 1 ->
            %{
              acc
              | in_encrypted_data: false,
                depth: 0,
                current: nil,
                results: [acc.current | acc.results]
            }

          {true, {:end_element, _, _, _, _}} ->
            update_depth(acc, -1)

          {true, {:end_element, _, _}} ->
            update_depth(acc, -1)

          {true, {:end_element, _}} ->
            update_depth(acc, -1)

          _ ->
            acc
        end
      end)

    Enum.reverse(result.results)
  end

  defp in_xenc_namespace?(name, attrs, xenc_ns) do
    cond do
      String.starts_with?(name, "xenc:") ->
        Enum.any?(attrs, fn
          {"xmlns:xenc", ^xenc_ns} -> true
          _ -> false
        end)

      true ->
        Enum.any?(attrs, fn
          {"xmlns", ^xenc_ns} -> true
          _ -> false
        end)
    end
  end

  defp update_depth(acc, delta) do
    %{acc | depth: acc.depth + delta}
  end

  defp update_encrypted_info(acc, "EncryptionMethod", attrs) do
    case find_attr(attrs, "Algorithm") do
      nil ->
        acc

      uri ->
        # Could be content encryption or key transport algorithm
        algo = parse_encryption_uri(uri) || parse_key_transport_uri(uri)

        if acc.current.algorithm == nil do
          %{acc | current: %{acc.current | algorithm: algo}}
        else
          # This is for EncryptedKey
          %{acc | current: %{acc.current | key_transport_algorithm: algo}}
        end
    end
  end

  defp update_encrypted_info(acc, "EncryptedKey", _attrs) do
    %{acc | current: %{acc.current | has_encrypted_key: true}}
  end

  defp update_encrypted_info(acc, _name, _attrs), do: acc

  defp find_attr(attrs, name) do
    case Enum.find(attrs, fn {k, _} -> k == name end) do
      {_, v} -> v
      nil -> nil
    end
  end

  defp parse_encryption_uri(uri) do
    case Algorithms.encryption_algorithm_from_uri(uri) do
      {:ok, algo} -> algo
      _ -> nil
    end
  end

  defp parse_key_transport_uri(uri) do
    case Algorithms.key_transport_algorithm_from_uri(uri) do
      {:ok, algo} -> algo
      _ -> nil
    end
  end

  defp parse_type_attr(nil), do: nil

  defp parse_type_attr(uri) do
    cond do
      String.ends_with?(uri, "#Element") -> :element
      String.ends_with?(uri, "#Content") -> :content
      true -> nil
    end
  end
end
