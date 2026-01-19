defmodule FnXML.Security.AlgorithmsTest do
  use ExUnit.Case, async: true

  alias FnXML.Security.Algorithms

  describe "digest/2" do
    test "SHA-256 produces correct digest" do
      # Test vector: SHA-256 of "hello"
      expected =
        Base.decode16!("2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824")

      assert Algorithms.digest("hello", :sha256) == expected
    end

    test "SHA-384 produces correct digest" do
      # SHA-384 of empty string
      expected =
        Base.decode16!(
          "38B060A751AC96384CD9327EB1B1E36A21FDB71114BE07434C0CC7BF63F6E1DA274EDEBFE76F65FBD51AD2F14898B95B"
        )

      assert Algorithms.digest("", :sha384) == expected
    end

    test "SHA-512 produces correct digest" do
      # SHA-512 of "hello"
      expected =
        Base.decode16!(
          "9B71D224BD62F3785D96D46AD3EA3D73319BFBC2890CAADAE2DFF72519673CA72323C3D99BA5C11D7C7ACC6E14B8C5DA0C4663475C2E5C3ADEF46F73BCDEC043"
        )

      assert Algorithms.digest("hello", :sha512) == expected
    end
  end

  describe "digest_algorithm_from_uri/1" do
    test "parses SHA-256 URI" do
      assert Algorithms.digest_algorithm_from_uri("http://www.w3.org/2001/04/xmlenc#sha256") ==
               {:ok, :sha256}
    end

    test "parses SHA-384 URI" do
      assert Algorithms.digest_algorithm_from_uri("http://www.w3.org/2001/04/xmldsig-more#sha384") ==
               {:ok, :sha384}
    end

    test "parses SHA-512 URI" do
      assert Algorithms.digest_algorithm_from_uri("http://www.w3.org/2001/04/xmlenc#sha512") ==
               {:ok, :sha512}
    end

    test "returns error for deprecated SHA-1" do
      assert Algorithms.digest_algorithm_from_uri("http://www.w3.org/2000/09/xmldsig#sha1") ==
               {:error, :deprecated_algorithm}
    end

    test "returns error for unknown URI" do
      assert Algorithms.digest_algorithm_from_uri("http://example.com/unknown") ==
               {:error, :unknown_algorithm}
    end
  end

  describe "encryption" do
    test "AES-256-GCM encrypt/decrypt round-trip" do
      plaintext = "Hello, World!"
      key = Algorithms.generate_key(32)

      {:ok, encrypted} = Algorithms.encrypt(plaintext, :aes_256_gcm, key)
      {:ok, decrypted} = Algorithms.decrypt(encrypted, :aes_256_gcm, key)

      assert decrypted == plaintext
    end

    test "AES-128-GCM encrypt/decrypt round-trip" do
      plaintext = "Test message for encryption"
      key = Algorithms.generate_key(16)

      {:ok, encrypted} = Algorithms.encrypt(plaintext, :aes_128_gcm, key)
      {:ok, decrypted} = Algorithms.decrypt(encrypted, :aes_128_gcm, key)

      assert decrypted == plaintext
    end

    test "AES-256-CBC encrypt/decrypt round-trip" do
      plaintext = "CBC mode test data"
      key = Algorithms.generate_key(32)

      {:ok, encrypted} = Algorithms.encrypt(plaintext, :aes_256_cbc, key)
      {:ok, decrypted} = Algorithms.decrypt(encrypted, :aes_256_cbc, key)

      assert decrypted == plaintext
    end

    test "AES-128-CBC encrypt/decrypt round-trip" do
      plaintext = "Short"
      key = Algorithms.generate_key(16)

      {:ok, encrypted} = Algorithms.encrypt(plaintext, :aes_128_cbc, key)
      {:ok, decrypted} = Algorithms.decrypt(encrypted, :aes_128_cbc, key)

      assert decrypted == plaintext
    end

    test "GCM decryption fails with wrong key" do
      plaintext = "Secret data"
      key1 = Algorithms.generate_key(32)
      key2 = Algorithms.generate_key(32)

      {:ok, encrypted} = Algorithms.encrypt(plaintext, :aes_256_gcm, key1)
      assert {:error, _} = Algorithms.decrypt(encrypted, :aes_256_gcm, key2)
    end

    test "returns error for invalid key size" do
      plaintext = "test"
      # 192-bit, not valid for AES-256
      invalid_key = Algorithms.generate_key(24)

      assert {:error, {:invalid_key_size, :aes_256_gcm, 24}} =
               Algorithms.encrypt(plaintext, :aes_256_gcm, invalid_key)
    end
  end

  describe "encryption_algorithm_from_uri/1" do
    test "parses AES-256-GCM URI" do
      assert Algorithms.encryption_algorithm_from_uri(
               "http://www.w3.org/2009/xmlenc11#aes256-gcm"
             ) ==
               {:ok, :aes_256_gcm}
    end

    test "parses AES-256-CBC URI" do
      assert Algorithms.encryption_algorithm_from_uri(
               "http://www.w3.org/2001/04/xmlenc#aes256-cbc"
             ) ==
               {:ok, :aes_256_cbc}
    end
  end

  describe "signature_algorithm_from_uri/1" do
    test "parses RSA-SHA256 URI" do
      assert Algorithms.signature_algorithm_from_uri(
               "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
             ) ==
               {:ok, :rsa_sha256}
    end

    test "parses ECDSA-SHA256 URI" do
      assert Algorithms.signature_algorithm_from_uri(
               "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256"
             ) ==
               {:ok, :ecdsa_sha256}
    end

    test "returns error for deprecated RSA-SHA1" do
      assert Algorithms.signature_algorithm_from_uri("http://www.w3.org/2000/09/xmldsig#rsa-sha1") ==
               {:error, :deprecated_algorithm}
    end
  end

  describe "key generation" do
    test "generate_key returns correct length" do
      assert byte_size(Algorithms.generate_key(16)) == 16
      assert byte_size(Algorithms.generate_key(32)) == 32
      assert byte_size(Algorithms.generate_key(64)) == 64
    end

    test "generate_iv returns correct length for GCM" do
      assert byte_size(Algorithms.generate_iv(:aes_256_gcm)) == 12
      assert byte_size(Algorithms.generate_iv(:aes_128_gcm)) == 12
    end

    test "generate_iv returns correct length for CBC" do
      assert byte_size(Algorithms.generate_iv(:aes_256_cbc)) == 16
      assert byte_size(Algorithms.generate_iv(:aes_128_cbc)) == 16
    end

    test "generated keys are random" do
      key1 = Algorithms.generate_key(32)
      key2 = Algorithms.generate_key(32)
      assert key1 != key2
    end
  end

  describe "algorithm URIs" do
    test "digest_algorithm_uri returns correct URIs" do
      assert Algorithms.digest_algorithm_uri(:sha256) == "http://www.w3.org/2001/04/xmlenc#sha256"

      assert Algorithms.digest_algorithm_uri(:sha384) ==
               "http://www.w3.org/2001/04/xmldsig-more#sha384"

      assert Algorithms.digest_algorithm_uri(:sha512) == "http://www.w3.org/2001/04/xmlenc#sha512"
    end

    test "signature_algorithm_uri returns correct URIs" do
      assert Algorithms.signature_algorithm_uri(:rsa_sha256) ==
               "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"

      assert Algorithms.signature_algorithm_uri(:ecdsa_sha256) ==
               "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256"
    end

    test "encryption_algorithm_uri returns correct URIs" do
      assert Algorithms.encryption_algorithm_uri(:aes_256_gcm) ==
               "http://www.w3.org/2009/xmlenc11#aes256-gcm"

      assert Algorithms.encryption_algorithm_uri(:aes_256_cbc) ==
               "http://www.w3.org/2001/04/xmlenc#aes256-cbc"
    end
  end
end
