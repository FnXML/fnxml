defmodule FnXML.Security.SignatureTest do
  use ExUnit.Case, async: true

  alias FnXML.Security.Signature
  alias FnXML.Security.Algorithms

  # Helper to generate test RSA key pair
  defp generate_rsa_keypair do
    private_key = :public_key.generate_key({:rsa, 2048, 65537})
    # Extract public key from private key
    {:RSAPrivateKey, _, n, e, _, _, _, _, _, _, _} = private_key
    public_key = {:RSAPublicKey, n, e}
    {private_key, public_key}
  end

  describe "Signature.info/1" do
    test "extracts signature information from signed document" do
      signed_doc = """
      <root>
        <ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
          <ds:SignedInfo>
            <ds:CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>
            <ds:SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"/>
            <ds:Reference URI="">
              <ds:Transforms>
                <ds:Transform Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature"/>
              </ds:Transforms>
              <ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/>
              <ds:DigestValue>abc123</ds:DigestValue>
            </ds:Reference>
          </ds:SignedInfo>
          <ds:SignatureValue>xyz789</ds:SignatureValue>
        </ds:Signature>
      </root>
      """

      {:ok, info} = Signature.info(signed_doc)

      assert info.c14n_algorithm == :exc_c14n
      assert info.signature_algorithm == :rsa_sha256
      assert length(info.references) == 1
      assert :sha256 in info.digest_algorithms
    end
  end

  describe "Signature.extract_signature/1" do
    test "extracts Signature element from document" do
      doc = """
      <root>
        <ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
          <ds:SignedInfo/>
          <ds:SignatureValue>test</ds:SignatureValue>
        </ds:Signature>
      </root>
      """

      {:ok, sig_xml} = Signature.extract_signature(doc)
      assert sig_xml =~ "Signature"
      assert sig_xml =~ "SignatureValue"
    end

    test "returns error when no signature present" do
      doc = "<root><child/></root>"
      assert {:error, :signature_not_found} = Signature.extract_signature(doc)
    end
  end

  describe "Signature.validate_structure/1" do
    test "validates complete signature structure" do
      sig = """
      <ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
        <ds:SignedInfo>
          <ds:CanonicalizationMethod Algorithm="test"/>
          <ds:SignatureMethod Algorithm="test"/>
          <ds:Reference URI="">
            <ds:DigestMethod Algorithm="test"/>
            <ds:DigestValue>test</ds:DigestValue>
          </ds:Reference>
        </ds:SignedInfo>
        <ds:SignatureValue>test</ds:SignatureValue>
      </ds:Signature>
      """

      assert :ok = Signature.validate_structure(sig)
    end

    test "returns error for incomplete signature" do
      sig = """
      <ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
        <ds:SignedInfo>
          <ds:CanonicalizationMethod Algorithm="test"/>
        </ds:SignedInfo>
      </ds:Signature>
      """

      assert {:error, {:missing_elements, missing}} = Signature.validate_structure(sig)
      assert "SignatureValue" in missing
    end
  end

  describe "Algorithms integration" do
    test "RSA key pair can sign and verify" do
      data = "test data to sign"
      {private_key, public_key} = generate_rsa_keypair()

      {:ok, signature} = Algorithms.sign(data, :rsa_sha256, private_key)
      assert :ok = Algorithms.verify(data, signature, :rsa_sha256, public_key)
    end

    test "verification fails with wrong key" do
      data = "test data"
      {private_key, _public_key} = generate_rsa_keypair()

      # Generate a different key pair
      {_other_private, other_public} = generate_rsa_keypair()

      {:ok, signature} = Algorithms.sign(data, :rsa_sha256, private_key)

      assert {:error, :invalid_signature} =
               Algorithms.verify(data, signature, :rsa_sha256, other_public)
    end
  end

  describe "Reference processing" do
    alias FnXML.Security.Signature.Reference

    test "creates reference with digest" do
      xml = "<root><child>content</child></root>"

      {:ok, reference} =
        Reference.create(xml,
          reference_uri: "",
          digest_algorithm: :sha256,
          type: :enveloped,
          c14n_algorithm: :exc_c14n
        )

      assert reference =~ "Reference"
      assert reference =~ "DigestValue"
      assert reference =~ "DigestMethod"
      assert reference =~ "Transform"
    end
  end
end
