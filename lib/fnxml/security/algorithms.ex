defmodule FnXML.Security.Algorithms do
  @moduledoc """
  Cryptographic algorithm implementations for XML Security.

  This module provides a thin wrapper over Erlang/OTP's `:crypto` and `:public_key`
  modules, implementing the algorithms required for XML Signature and XML Encryption.

  ## Supported Algorithms

  ### Digest Algorithms
  - SHA-256, SHA-384, SHA-512

  ### Signature Algorithms
  - RSA-SHA256, RSA-SHA384, RSA-SHA512
  - ECDSA-SHA256, ECDSA-SHA384, ECDSA-SHA512

  ### Encryption Algorithms
  - AES-128-GCM, AES-256-GCM
  - AES-128-CBC, AES-256-CBC

  ### Key Transport Algorithms
  - RSA-OAEP

  ## Usage

      # Compute digest
      digest = FnXML.Security.Algorithms.digest(data, :sha256)

      # Sign data
      signature = FnXML.Security.Algorithms.sign(data, :rsa_sha256, private_key)

      # Verify signature
      :ok = FnXML.Security.Algorithms.verify(data, signature, :rsa_sha256, public_key)

  ## Security Notes

  All cryptographic operations are delegated to Erlang/OTP's battle-tested
  implementations. No custom cryptographic code is used.
  """

  alias FnXML.Security.Namespaces

  # ==========================================================================
  # Digest Algorithms
  # ==========================================================================

  @type digest_algorithm :: :sha256 | :sha384 | :sha512

  @doc """
  Compute a cryptographic digest of the given data.

  ## Examples

      iex> FnXML.Security.Algorithms.digest("hello", :sha256) |> Base.encode16(case: :lower)
      "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"

  """
  @spec digest(binary(), digest_algorithm()) :: binary()
  def digest(data, :sha256), do: :crypto.hash(:sha256, data)
  def digest(data, :sha384), do: :crypto.hash(:sha384, data)
  def digest(data, :sha512), do: :crypto.hash(:sha512, data)

  @doc """
  Get the digest algorithm atom from a URI.

  ## Examples

      iex> FnXML.Security.Algorithms.digest_algorithm_from_uri("http://www.w3.org/2001/04/xmlenc#sha256")
      {:ok, :sha256}

  """
  @spec digest_algorithm_from_uri(String.t()) ::
          {:ok, digest_algorithm()} | {:error, :unknown_algorithm}
  def digest_algorithm_from_uri(uri) do
    case uri do
      "http://www.w3.org/2001/04/xmlenc#sha256" -> {:ok, :sha256}
      "http://www.w3.org/2001/04/xmldsig-more#sha384" -> {:ok, :sha384}
      "http://www.w3.org/2001/04/xmlenc#sha512" -> {:ok, :sha512}
      # Also accept SHA-1 URI but return error (deprecated)
      "http://www.w3.org/2000/09/xmldsig#sha1" -> {:error, :deprecated_algorithm}
      _ -> {:error, :unknown_algorithm}
    end
  end

  @doc """
  Get the URI for a digest algorithm.
  """
  @spec digest_algorithm_uri(digest_algorithm()) :: String.t()
  def digest_algorithm_uri(:sha256), do: Namespaces.sha256()
  def digest_algorithm_uri(:sha384), do: Namespaces.sha384()
  def digest_algorithm_uri(:sha512), do: Namespaces.sha512()

  # ==========================================================================
  # Signature Algorithms
  # ==========================================================================

  @type signature_algorithm ::
          :rsa_sha256 | :rsa_sha384 | :rsa_sha512 | :ecdsa_sha256 | :ecdsa_sha384 | :ecdsa_sha512

  @doc """
  Sign data using the specified algorithm and private key.

  The private key should be in Erlang's public_key format, typically obtained
  by decoding a PEM file.

  ## Examples

      {:ok, signature} = FnXML.Security.Algorithms.sign(data, :rsa_sha256, private_key)

  """
  @spec sign(binary(), signature_algorithm(), term()) :: {:ok, binary()} | {:error, term()}
  def sign(data, algorithm, private_key) do
    {hash_algo, _key_type} = parse_signature_algorithm(algorithm)

    try do
      signature = :public_key.sign(data, hash_algo, private_key)
      {:ok, signature}
    rescue
      e -> {:error, {:signing_failed, e}}
    end
  end

  @doc """
  Verify a signature using the specified algorithm and public key.

  Returns `:ok` if the signature is valid, `{:error, reason}` otherwise.

  ## Examples

      :ok = FnXML.Security.Algorithms.verify(data, signature, :rsa_sha256, public_key)

  """
  @spec verify(binary(), binary(), signature_algorithm(), term()) :: :ok | {:error, term()}
  def verify(data, signature, algorithm, public_key) do
    {hash_algo, _key_type} = parse_signature_algorithm(algorithm)

    try do
      case :public_key.verify(data, hash_algo, signature, public_key) do
        true -> :ok
        false -> {:error, :invalid_signature}
      end
    rescue
      e -> {:error, {:verification_failed, e}}
    end
  end

  @doc """
  Get the signature algorithm atom from a URI.
  """
  @spec signature_algorithm_from_uri(String.t()) ::
          {:ok, signature_algorithm()} | {:error, :unknown_algorithm}
  def signature_algorithm_from_uri(uri) do
    case uri do
      "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256" -> {:ok, :rsa_sha256}
      "http://www.w3.org/2001/04/xmldsig-more#rsa-sha384" -> {:ok, :rsa_sha384}
      "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512" -> {:ok, :rsa_sha512}
      "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256" -> {:ok, :ecdsa_sha256}
      "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha384" -> {:ok, :ecdsa_sha384}
      "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha512" -> {:ok, :ecdsa_sha512}
      # Deprecated algorithms
      "http://www.w3.org/2000/09/xmldsig#rsa-sha1" -> {:error, :deprecated_algorithm}
      _ -> {:error, :unknown_algorithm}
    end
  end

  @doc """
  Get the URI for a signature algorithm.
  """
  @spec signature_algorithm_uri(signature_algorithm()) :: String.t()
  def signature_algorithm_uri(:rsa_sha256), do: Namespaces.rsa_sha256()
  def signature_algorithm_uri(:rsa_sha384), do: Namespaces.rsa_sha384()
  def signature_algorithm_uri(:rsa_sha512), do: Namespaces.rsa_sha512()
  def signature_algorithm_uri(:ecdsa_sha256), do: Namespaces.ecdsa_sha256()

  defp parse_signature_algorithm(:rsa_sha256), do: {:sha256, :rsa}
  defp parse_signature_algorithm(:rsa_sha384), do: {:sha384, :rsa}
  defp parse_signature_algorithm(:rsa_sha512), do: {:sha512, :rsa}
  defp parse_signature_algorithm(:ecdsa_sha256), do: {:sha256, :ecdsa}
  defp parse_signature_algorithm(:ecdsa_sha384), do: {:sha384, :ecdsa}
  defp parse_signature_algorithm(:ecdsa_sha512), do: {:sha512, :ecdsa}

  # ==========================================================================
  # Encryption Algorithms
  # ==========================================================================

  @type encryption_algorithm :: :aes_128_gcm | :aes_256_gcm | :aes_128_cbc | :aes_256_cbc

  @doc """
  Encrypt data using the specified algorithm and key.

  For GCM modes, returns `{iv, ciphertext, tag}`.
  For CBC modes, returns `{iv, ciphertext}`.

  The IV is randomly generated.

  ## Examples

      {:ok, {iv, ciphertext, tag}} = FnXML.Security.Algorithms.encrypt(plaintext, :aes_256_gcm, key)

  """
  @spec encrypt(binary(), encryption_algorithm(), binary()) ::
          {:ok, {binary(), binary(), binary()}} | {:ok, {binary(), binary()}} | {:error, term()}
  def encrypt(plaintext, :aes_128_gcm, key) when byte_size(key) == 16 do
    encrypt_gcm(plaintext, key, :aes_128_gcm)
  end

  def encrypt(plaintext, :aes_256_gcm, key) when byte_size(key) == 32 do
    encrypt_gcm(plaintext, key, :aes_256_gcm)
  end

  def encrypt(plaintext, :aes_128_cbc, key) when byte_size(key) == 16 do
    encrypt_cbc(plaintext, key, :aes_128_cbc)
  end

  def encrypt(plaintext, :aes_256_cbc, key) when byte_size(key) == 32 do
    encrypt_cbc(plaintext, key, :aes_256_cbc)
  end

  def encrypt(_plaintext, algorithm, key) do
    {:error, {:invalid_key_size, algorithm, byte_size(key)}}
  end

  @doc """
  Decrypt data using the specified algorithm and key.

  For GCM modes, expects `{iv, ciphertext, tag}`.
  For CBC modes, expects `{iv, ciphertext}`.

  ## Examples

      {:ok, plaintext} = FnXML.Security.Algorithms.decrypt({iv, ciphertext, tag}, :aes_256_gcm, key)

  """
  @spec decrypt(
          {binary(), binary(), binary()} | {binary(), binary()},
          encryption_algorithm(),
          binary()
        ) ::
          {:ok, binary()} | {:error, term()}
  def decrypt({iv, ciphertext, tag}, :aes_128_gcm, key) when byte_size(key) == 16 do
    decrypt_gcm(iv, ciphertext, tag, key, :aes_128_gcm)
  end

  def decrypt({iv, ciphertext, tag}, :aes_256_gcm, key) when byte_size(key) == 32 do
    decrypt_gcm(iv, ciphertext, tag, key, :aes_256_gcm)
  end

  def decrypt({iv, ciphertext}, :aes_128_cbc, key) when byte_size(key) == 16 do
    decrypt_cbc(iv, ciphertext, key, :aes_128_cbc)
  end

  def decrypt({iv, ciphertext}, :aes_256_cbc, key) when byte_size(key) == 32 do
    decrypt_cbc(iv, ciphertext, key, :aes_256_cbc)
  end

  def decrypt(_encrypted, algorithm, key) do
    {:error, {:invalid_key_size, algorithm, byte_size(key)}}
  end

  @doc """
  Get the encryption algorithm atom from a URI.
  """
  @spec encryption_algorithm_from_uri(String.t()) ::
          {:ok, encryption_algorithm()} | {:error, :unknown_algorithm}
  def encryption_algorithm_from_uri(uri) do
    case uri do
      "http://www.w3.org/2009/xmlenc11#aes128-gcm" -> {:ok, :aes_128_gcm}
      "http://www.w3.org/2009/xmlenc11#aes256-gcm" -> {:ok, :aes_256_gcm}
      "http://www.w3.org/2001/04/xmlenc#aes128-cbc" -> {:ok, :aes_128_cbc}
      "http://www.w3.org/2001/04/xmlenc#aes256-cbc" -> {:ok, :aes_256_cbc}
      _ -> {:error, :unknown_algorithm}
    end
  end

  @doc """
  Get the URI for an encryption algorithm.
  """
  @spec encryption_algorithm_uri(encryption_algorithm()) :: String.t()
  def encryption_algorithm_uri(:aes_128_gcm), do: Namespaces.aes128_gcm()
  def encryption_algorithm_uri(:aes_256_gcm), do: Namespaces.aes256_gcm()
  def encryption_algorithm_uri(:aes_128_cbc), do: "http://www.w3.org/2001/04/xmlenc#aes128-cbc"
  def encryption_algorithm_uri(:aes_256_cbc), do: Namespaces.aes256_cbc()

  # GCM encryption/decryption helpers
  defp encrypt_gcm(plaintext, key, algorithm) do
    # 96-bit IV for GCM
    iv = :crypto.strong_rand_bytes(12)

    try do
      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(
          algorithm,
          key,
          iv,
          plaintext,
          # AAD (Additional Authenticated Data)
          <<>>,
          # encrypt
          true
        )

      {:ok, {iv, ciphertext, tag}}
    rescue
      e -> {:error, {:encryption_failed, e}}
    end
  end

  defp decrypt_gcm(iv, ciphertext, tag, key, algorithm) do
    try do
      case :crypto.crypto_one_time_aead(
             algorithm,
             key,
             iv,
             ciphertext,
             # AAD
             <<>>,
             tag,
             # decrypt
             false
           ) do
        plaintext when is_binary(plaintext) -> {:ok, plaintext}
        :error -> {:error, :decryption_failed}
      end
    rescue
      e -> {:error, {:decryption_failed, e}}
    end
  end

  # CBC encryption/decryption helpers
  defp encrypt_cbc(plaintext, key, algorithm) do
    # 128-bit IV for CBC
    iv = :crypto.strong_rand_bytes(16)
    padded = pkcs7_pad(plaintext, 16)

    try do
      ciphertext = :crypto.crypto_one_time(algorithm, key, iv, padded, true)
      {:ok, {iv, ciphertext}}
    rescue
      e -> {:error, {:encryption_failed, e}}
    end
  end

  defp decrypt_cbc(iv, ciphertext, key, algorithm) do
    try do
      padded = :crypto.crypto_one_time(algorithm, key, iv, ciphertext, false)
      {:ok, pkcs7_unpad(padded)}
    rescue
      e -> {:error, {:decryption_failed, e}}
    end
  end

  # PKCS7 padding helpers
  defp pkcs7_pad(data, block_size) do
    pad_len = block_size - rem(byte_size(data), block_size)
    padding = :binary.copy(<<pad_len>>, pad_len)
    data <> padding
  end

  defp pkcs7_unpad(data) do
    pad_len = :binary.last(data)
    binary_part(data, 0, byte_size(data) - pad_len)
  end

  # ==========================================================================
  # Key Transport Algorithms
  # ==========================================================================

  @type key_transport_algorithm :: :rsa_oaep | :rsa_oaep_mgf1p

  @doc """
  Encrypt a key using the specified key transport algorithm.

  Used for encrypting symmetric keys with a recipient's public key.

  ## Examples

      {:ok, encrypted_key} = FnXML.Security.Algorithms.encrypt_key(symmetric_key, :rsa_oaep, public_key)

  """
  @spec encrypt_key(binary(), key_transport_algorithm(), term()) ::
          {:ok, binary()} | {:error, term()}
  def encrypt_key(key_data, algorithm, public_key)
      when algorithm in [:rsa_oaep, :rsa_oaep_mgf1p] do
    try do
      encrypted =
        :public_key.encrypt_public(
          key_data,
          public_key,
          [{:rsa_padding, :rsa_pkcs1_oaep_padding}]
        )

      {:ok, encrypted}
    rescue
      e -> {:error, {:key_encryption_failed, e}}
    end
  end

  @doc """
  Decrypt a key using the specified key transport algorithm.

  ## Examples

      {:ok, symmetric_key} = FnXML.Security.Algorithms.decrypt_key(encrypted_key, :rsa_oaep, private_key)

  """
  @spec decrypt_key(binary(), key_transport_algorithm(), term()) ::
          {:ok, binary()} | {:error, term()}
  def decrypt_key(encrypted_key, algorithm, private_key)
      when algorithm in [:rsa_oaep, :rsa_oaep_mgf1p] do
    try do
      decrypted =
        :public_key.decrypt_private(
          encrypted_key,
          private_key,
          [{:rsa_padding, :rsa_pkcs1_oaep_padding}]
        )

      {:ok, decrypted}
    rescue
      e -> {:error, {:key_decryption_failed, e}}
    end
  end

  @doc """
  Get the key transport algorithm atom from a URI.
  """
  @spec key_transport_algorithm_from_uri(String.t()) ::
          {:ok, key_transport_algorithm()} | {:error, :unknown_algorithm}
  def key_transport_algorithm_from_uri(uri) do
    case uri do
      "http://www.w3.org/2001/04/xmlenc#rsa-oaep-mgf1p" -> {:ok, :rsa_oaep_mgf1p}
      "http://www.w3.org/2009/xmlenc11#rsa-oaep" -> {:ok, :rsa_oaep}
      _ -> {:error, :unknown_algorithm}
    end
  end

  @doc """
  Get the URI for a key transport algorithm.
  """
  @spec key_transport_algorithm_uri(key_transport_algorithm()) :: String.t()
  def key_transport_algorithm_uri(:rsa_oaep), do: "http://www.w3.org/2009/xmlenc11#rsa-oaep"
  def key_transport_algorithm_uri(:rsa_oaep_mgf1p), do: Namespaces.rsa_oaep()

  # ==========================================================================
  # Key Generation
  # ==========================================================================

  @doc """
  Generate a random symmetric key of the specified length in bytes.

  ## Examples

      key = FnXML.Security.Algorithms.generate_key(32)  # 256-bit key

  """
  @spec generate_key(pos_integer()) :: binary()
  def generate_key(length) when is_integer(length) and length > 0 do
    :crypto.strong_rand_bytes(length)
  end

  @doc """
  Generate a random IV (Initialization Vector) for the specified algorithm.

  ## Examples

      iv = FnXML.Security.Algorithms.generate_iv(:aes_256_gcm)  # 12 bytes
      iv = FnXML.Security.Algorithms.generate_iv(:aes_256_cbc)  # 16 bytes

  """
  @spec generate_iv(encryption_algorithm()) :: binary()
  def generate_iv(algorithm) when algorithm in [:aes_128_gcm, :aes_256_gcm] do
    # 96-bit IV for GCM
    :crypto.strong_rand_bytes(12)
  end

  def generate_iv(algorithm) when algorithm in [:aes_128_cbc, :aes_256_cbc] do
    # 128-bit IV for CBC
    :crypto.strong_rand_bytes(16)
  end

  # ==========================================================================
  # Key Parsing Utilities
  # ==========================================================================

  @doc """
  Parse a PEM-encoded private key.

  ## Examples

      {:ok, private_key} = FnXML.Security.Algorithms.parse_private_key_pem(pem_string)

  """
  @spec parse_private_key_pem(String.t()) :: {:ok, term()} | {:error, term()}
  def parse_private_key_pem(pem) do
    try do
      case :public_key.pem_decode(pem) do
        [entry | _] ->
          key = :public_key.pem_entry_decode(entry)
          {:ok, key}

        [] ->
          {:error, :invalid_pem}
      end
    rescue
      e -> {:error, {:pem_decode_failed, e}}
    end
  end

  @doc """
  Parse a PEM-encoded public key or certificate to extract public key.

  ## Examples

      {:ok, public_key} = FnXML.Security.Algorithms.parse_public_key_pem(pem_string)

  """
  @spec parse_public_key_pem(String.t()) :: {:ok, term()} | {:error, term()}
  def parse_public_key_pem(pem) do
    try do
      case :public_key.pem_decode(pem) do
        [entry | _] ->
          decoded = :public_key.pem_entry_decode(entry)
          key = extract_public_key(decoded)
          {:ok, key}

        [] ->
          {:error, :invalid_pem}
      end
    rescue
      e -> {:error, {:pem_decode_failed, e}}
    end
  end

  # Extract public key from various formats
  defp extract_public_key({:Certificate, _, _, _} = cert) do
    :public_key.pkix_decode_cert(:public_key.pem_entry_encode(:Certificate, cert), :otp)
    |> elem(1)
    |> elem(7)
    |> elem(2)
  end

  # OTP certificate record
  defp extract_public_key({:OTPCertificate, tbs, _, _}) do
    tbs
    |> elem(7)
    |> elem(2)
  end

  # Already a public key
  defp extract_public_key({:RSAPublicKey, _, _} = key), do: key
  defp extract_public_key({{:ECPoint, _}, _} = key), do: key

  defp extract_public_key({:SubjectPublicKeyInfo, _, _} = key) do
    :public_key.pem_entry_decode(key)
  end

  # Extract from private key
  defp extract_public_key({:RSAPrivateKey, _, n, e, _, _, _, _, _, _, _}) do
    {:RSAPublicKey, n, e}
  end

  defp extract_public_key(other), do: other
end
