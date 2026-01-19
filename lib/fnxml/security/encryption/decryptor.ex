defmodule FnXML.Security.Encryption.Decryptor do
  @moduledoc """
  XML Decryption operations.

  Implements the decryption process according to W3C XML Encryption:

  1. Parse EncryptedData element
  2. Extract encryption algorithm and cipher data
  3. Optionally decrypt the encrypted key using key transport
  4. Decrypt the content
  5. Replace EncryptedData with decrypted content
  """

  alias FnXML.Namespaces, as: XMLNamespaces
  alias FnXML.Security.{Algorithms, Namespaces}

  @doc """
  Decrypt encrypted XML content.

  ## Options

  - `:key` - The symmetric encryption key
  - `:private_key` - Private key for decrypting EncryptedKey
  """
  @spec decrypt(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  def decrypt(xml, opts) do
    with {:ok, enc_data_info} <- parse_encrypted_data(xml),
         {:ok, key} <- obtain_key(enc_data_info, opts),
         {:ok, plaintext} <- decrypt_content(enc_data_info, key) do
      replace_encrypted_data(xml, enc_data_info, plaintext)
    end
  end

  # Parse EncryptedData element and extract all needed information
  defp parse_encrypted_data(xml) do
    events = FnXML.Parser.parse(xml)

    state = %{
      in_encrypted_data: false,
      in_encrypted_key: false,
      depth: 0,
      enc_depth: 0,
      enc_key_depth: 0,
      algorithm: nil,
      key_algorithm: nil,
      cipher_value: nil,
      encrypted_key_value: nil,
      type: nil,
      enc_data_events: [],
      text_buffer: "",
      current_element: nil
    }

    result = Enum.reduce(events, state, &process_event/2)

    if result.algorithm && result.cipher_value do
      {:ok,
       %{
         algorithm: result.algorithm,
         key_algorithm: result.key_algorithm,
         cipher_value: result.cipher_value,
         encrypted_key_value: result.encrypted_key_value,
         type: result.type,
         enc_data_events: Enum.reverse(result.enc_data_events)
       }}
    else
      {:error, :invalid_encrypted_data}
    end
  end

  defp process_event(event, state) do
    xenc_ns = Namespaces.xenc()

    case event do
      {:start_element, name, attrs, _, _, _} ->
        handle_start_element(name, attrs, event, state, xenc_ns)

      {:start_element, name, attrs, _} ->
        handle_start_element(name, attrs, event, state, xenc_ns)

      {:end_element, name, _, _, _} ->
        handle_end_element(XMLNamespaces.local_part(name), event, state)

      {:end_element, name, _} ->
        handle_end_element(XMLNamespaces.local_part(name), event, state)

      {:end_element, name} ->
        handle_end_element(XMLNamespaces.local_part(name), event, state)

      {:characters, content, _, _, _} ->
        handle_characters(content, event, state)

      {:characters, content, _} ->
        handle_characters(content, event, state)

      _ ->
        if state.in_encrypted_data do
          %{state | enc_data_events: [event | state.enc_data_events]}
        else
          state
        end
    end
  end

  defp handle_start_element(name, attrs, event, state, xenc_ns) do
    local_name = XMLNamespaces.local_part(name)

    cond do
      # Start of EncryptedData
      local_name == "EncryptedData" and not state.in_encrypted_data ->
        if in_xenc_namespace?(name, attrs, xenc_ns) do
          enc_type = find_attr(attrs, "Type")

          %{
            state
            | in_encrypted_data: true,
              enc_depth: 1,
              type: parse_type(enc_type),
              enc_data_events: [event]
          }
        else
          state
        end

      # Start of EncryptedKey (inside KeyInfo)
      local_name == "EncryptedKey" and state.in_encrypted_data ->
        %{
          state
          | in_encrypted_key: true,
            enc_key_depth: 1,
            enc_data_events: [event | state.enc_data_events]
        }

      # EncryptionMethod - could be for EncryptedData or EncryptedKey
      local_name == "EncryptionMethod" and state.in_encrypted_data ->
        algo_uri = find_attr(attrs, "Algorithm")

        state =
          if state.in_encrypted_key do
            %{state | key_algorithm: parse_key_algorithm(algo_uri)}
          else
            %{state | algorithm: parse_algorithm(algo_uri)}
          end

        new_enc_depth = state.enc_depth + 1

        new_enc_key_depth =
          if state.in_encrypted_key, do: state.enc_key_depth + 1, else: state.enc_key_depth

        %{
          state
          | enc_depth: new_enc_depth,
            enc_key_depth: new_enc_key_depth,
            enc_data_events: [event | state.enc_data_events]
        }

      # CipherValue - stores the encrypted content
      local_name == "CipherValue" and state.in_encrypted_data ->
        new_enc_depth = state.enc_depth + 1

        new_enc_key_depth =
          if state.in_encrypted_key, do: state.enc_key_depth + 1, else: state.enc_key_depth

        %{
          state
          | current_element: :cipher_value,
            text_buffer: "",
            enc_depth: new_enc_depth,
            enc_key_depth: new_enc_key_depth,
            enc_data_events: [event | state.enc_data_events]
        }

      # Inside EncryptedData - track depth
      state.in_encrypted_data ->
        new_enc_depth = state.enc_depth + 1

        new_enc_key_depth =
          if state.in_encrypted_key, do: state.enc_key_depth + 1, else: state.enc_key_depth

        %{
          state
          | enc_depth: new_enc_depth,
            enc_key_depth: new_enc_key_depth,
            enc_data_events: [event | state.enc_data_events]
        }

      true ->
        state
    end
  end

  defp handle_end_element("EncryptedData", event, state) when state.in_encrypted_data do
    if state.enc_depth == 1 do
      %{
        state
        | in_encrypted_data: false,
          enc_depth: 0,
          enc_data_events: [event | state.enc_data_events]
      }
    else
      %{
        state
        | enc_depth: state.enc_depth - 1,
          enc_data_events: [event | state.enc_data_events]
      }
    end
  end

  defp handle_end_element("EncryptedKey", event, state) when state.in_encrypted_key do
    if state.enc_key_depth == 1 do
      %{
        state
        | in_encrypted_key: false,
          enc_key_depth: 0,
          enc_depth: state.enc_depth - 1,
          enc_data_events: [event | state.enc_data_events]
      }
    else
      %{
        state
        | enc_key_depth: state.enc_key_depth - 1,
          enc_depth: state.enc_depth - 1,
          enc_data_events: [event | state.enc_data_events]
      }
    end
  end

  defp handle_end_element("CipherValue", event, state)
       when state.current_element == :cipher_value do
    cipher_value = state.text_buffer |> String.trim() |> Base.decode64!()

    state =
      if state.in_encrypted_key do
        %{state | encrypted_key_value: cipher_value}
      else
        %{state | cipher_value: cipher_value}
      end

    new_enc_depth = if state.in_encrypted_data, do: state.enc_depth - 1, else: state.enc_depth

    new_enc_key_depth =
      if state.in_encrypted_key, do: state.enc_key_depth - 1, else: state.enc_key_depth

    %{
      state
      | current_element: nil,
        text_buffer: "",
        enc_depth: new_enc_depth,
        enc_key_depth: new_enc_key_depth,
        enc_data_events: [event | state.enc_data_events]
    }
  end

  defp handle_end_element(_name, event, state) when state.in_encrypted_data do
    new_enc_depth = state.enc_depth - 1

    new_enc_key_depth =
      if state.in_encrypted_key, do: state.enc_key_depth - 1, else: state.enc_key_depth

    %{
      state
      | enc_depth: new_enc_depth,
        enc_key_depth: new_enc_key_depth,
        enc_data_events: [event | state.enc_data_events]
    }
  end

  defp handle_end_element(_name, _event, state), do: state

  defp handle_characters(content, event, state) do
    state =
      if state.current_element == :cipher_value do
        %{state | text_buffer: state.text_buffer <> content}
      else
        state
      end

    if state.in_encrypted_data do
      %{state | enc_data_events: [event | state.enc_data_events]}
    else
      state
    end
  end

  # Obtain the encryption key (directly or via key transport)
  defp obtain_key(enc_data_info, opts) do
    cond do
      # Direct key provided
      opts[:key] ->
        {:ok, opts[:key]}

      # Encrypted key with private key for decryption
      enc_data_info.encrypted_key_value && opts[:private_key] ->
        Algorithms.decrypt_key(
          enc_data_info.encrypted_key_value,
          enc_data_info.key_algorithm,
          opts[:private_key]
        )

      # No way to get key
      true ->
        {:error, :no_decryption_key}
    end
  end

  # Decrypt the cipher value
  defp decrypt_content(enc_data_info, key) do
    algorithm = enc_data_info.algorithm
    cipher_data = enc_data_info.cipher_value

    # Parse cipher data based on algorithm
    encrypted =
      case algorithm do
        algo when algo in [:aes_128_gcm, :aes_256_gcm] ->
          # GCM: IV (12 bytes) || ciphertext || tag (16 bytes)
          iv_size = 12
          tag_size = 16
          iv = binary_part(cipher_data, 0, iv_size)
          tag = binary_part(cipher_data, byte_size(cipher_data) - tag_size, tag_size)

          ciphertext =
            binary_part(cipher_data, iv_size, byte_size(cipher_data) - iv_size - tag_size)

          {iv, ciphertext, tag}

        algo when algo in [:aes_128_cbc, :aes_256_cbc] ->
          # CBC: IV (16 bytes) || ciphertext
          iv_size = 16
          iv = binary_part(cipher_data, 0, iv_size)
          ciphertext = binary_part(cipher_data, iv_size, byte_size(cipher_data) - iv_size)
          {iv, ciphertext}
      end

    Algorithms.decrypt(encrypted, algorithm, key)
  end

  # Replace EncryptedData with decrypted content
  defp replace_encrypted_data(xml, enc_data_info, plaintext) do
    events = FnXML.Parser.parse(xml)
    xenc_ns = Namespaces.xenc()

    state = %{
      in_encrypted_data: false,
      depth: 0,
      events: [],
      replaced: false
    }

    result =
      Enum.reduce(events, state, fn event, acc ->
        case event do
          {:start_element, name, attrs, _, _, _} ->
            if XMLNamespaces.local_part(name) == "EncryptedData" and
                 in_xenc_namespace?(name, attrs, xenc_ns) and not acc.in_encrypted_data do
              %{acc | in_encrypted_data: true, depth: 1}
            else
              if acc.in_encrypted_data do
                %{acc | depth: acc.depth + 1}
              else
                %{acc | events: [event | acc.events]}
              end
            end

          {:start_element, name, attrs, _} ->
            if XMLNamespaces.local_part(name) == "EncryptedData" and
                 in_xenc_namespace?(name, attrs, xenc_ns) and not acc.in_encrypted_data do
              %{acc | in_encrypted_data: true, depth: 1}
            else
              if acc.in_encrypted_data do
                %{acc | depth: acc.depth + 1}
              else
                %{acc | events: [event | acc.events]}
              end
            end

          {:end_element, _, _, _, _} when acc.in_encrypted_data ->
            if acc.depth == 1 do
              # End of EncryptedData - insert decrypted content
              # For element encryption, plaintext is the complete element
              # For content encryption, plaintext is just the content
              case enc_data_info.type do
                :element ->
                  %{
                    acc
                    | in_encrypted_data: false,
                      depth: 0,
                      replaced: true,
                      events: [{:raw, plaintext} | acc.events]
                  }

                :content ->
                  %{
                    acc
                    | in_encrypted_data: false,
                      depth: 0,
                      replaced: true,
                      events: [{:raw, plaintext} | acc.events]
                  }

                _ ->
                  %{
                    acc
                    | in_encrypted_data: false,
                      depth: 0,
                      replaced: true,
                      events: [{:raw, plaintext} | acc.events]
                  }
              end
            else
              %{acc | depth: acc.depth - 1}
            end

          {:end_element, _, _} when acc.in_encrypted_data ->
            if acc.depth == 1 do
              case enc_data_info.type do
                _ ->
                  %{
                    acc
                    | in_encrypted_data: false,
                      depth: 0,
                      replaced: true,
                      events: [{:raw, plaintext} | acc.events]
                  }
              end
            else
              %{acc | depth: acc.depth - 1}
            end

          {:end_element, _} when acc.in_encrypted_data ->
            if acc.depth == 1 do
              %{
                acc
                | in_encrypted_data: false,
                  depth: 0,
                  replaced: true,
                  events: [{:raw, plaintext} | acc.events]
              }
            else
              %{acc | depth: acc.depth - 1}
            end

          _ when acc.in_encrypted_data ->
            acc

          _ ->
            %{acc | events: [event | acc.events]}
        end
      end)

    if result.replaced do
      {:ok, serialize_events(Enum.reverse(result.events))}
    else
      {:error, :encrypted_data_not_found}
    end
  end

  # Helper functions

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

  defp find_attr(attrs, name) do
    case Enum.find(attrs, fn {k, _} -> k == name end) do
      {_, v} -> v
      nil -> nil
    end
  end

  defp parse_algorithm(uri) do
    case Algorithms.encryption_algorithm_from_uri(uri) do
      {:ok, algo} -> algo
      _ -> nil
    end
  end

  defp parse_key_algorithm(uri) do
    case Algorithms.key_transport_algorithm_from_uri(uri) do
      {:ok, algo} -> algo
      _ -> nil
    end
  end

  defp parse_type(nil), do: :element

  defp parse_type(uri) do
    cond do
      String.ends_with?(uri, "#Element") -> :element
      String.ends_with?(uri, "#Content") -> :content
      true -> :element
    end
  end

  defp serialize_events(events) do
    events
    |> Enum.map(&event_to_iodata/1)
    |> IO.iodata_to_binary()
  end

  defp event_to_iodata({:raw, content}), do: content

  defp event_to_iodata({:start_element, tag, attrs, _, _, _}) do
    attr_str =
      attrs
      |> Enum.map(fn {k, v} -> [" ", k, "=\"", escape_attr(v), "\""] end)

    ["<", tag, attr_str, ">"]
  end

  defp event_to_iodata({:start_element, tag, attrs, _}) do
    attr_str =
      attrs
      |> Enum.map(fn {k, v} -> [" ", k, "=\"", escape_attr(v), "\""] end)

    ["<", tag, attr_str, ">"]
  end

  defp event_to_iodata({:end_element, tag, _, _, _}), do: ["</", tag, ">"]
  defp event_to_iodata({:end_element, tag, _}), do: ["</", tag, ">"]
  defp event_to_iodata({:end_element, tag}), do: ["</", tag, ">"]
  defp event_to_iodata({:characters, content, _, _, _}), do: escape_text(content)
  defp event_to_iodata({:characters, content, _}), do: escape_text(content)
  defp event_to_iodata({:start_document, _}), do: []
  defp event_to_iodata({:end_document, _}), do: []
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
end
