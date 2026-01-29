defmodule FnXML.Security.Encryption.Encryptor do
  @moduledoc """
  XML Encryption operations.

  Implements the encryption process according to W3C XML Encryption:

  1. Serialize and canonicalize the target content
  2. Generate or use provided symmetric key
  3. Encrypt the content
  4. Optionally wrap the key with key transport
  5. Build EncryptedData element
  6. Replace target content with EncryptedData
  """

  alias FnXML.C14N
  alias FnXML.Security.{Algorithms, Namespaces}

  @default_opts [
    algorithm: :aes_256_gcm,
    type: :element
  ]

  @doc """
  Encrypt XML content and return the modified document.
  """
  @spec encrypt(binary(), String.t(), binary() | nil, keyword()) ::
          {:ok, binary()} | {:error, term()}
  def encrypt(xml, target, key, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)

    with {:ok, content} <- extract_target_content(xml, target, opts[:type]),
         {:ok, key} <- ensure_key(key, opts),
         {:ok, encrypted} <- encrypt_content(content, key, opts[:algorithm]),
         {:ok, encrypted_data} <- build_encrypted_data(encrypted, key, opts) do
      replace_target(xml, target, encrypted_data, opts[:type])
    end
  end

  # Extract content to encrypt based on target and type
  defp extract_target_content(xml, "#" <> id, :element) do
    # Find element by ID and serialize it completely
    events = FnXML.Parser.parse(xml)

    case find_element_by_id(events, id) do
      {:ok, element_events} ->
        iodata = C14N.canonicalize(element_events)
        canonical = IO.iodata_to_binary(iodata)
        {:ok, canonical}

      :not_found ->
        {:error, {:element_not_found, id}}
    end
  end

  defp extract_target_content(xml, "#" <> id, :content) do
    # Find element by ID and serialize just its content
    events = FnXML.Parser.parse(xml)

    case find_element_content_by_id(events, id) do
      {:ok, content_events} ->
        iodata = C14N.canonicalize(content_events)
        canonical = IO.iodata_to_binary(iodata)
        {:ok, canonical}

      :not_found ->
        {:error, {:element_not_found, id}}
    end
  end

  defp extract_target_content(_xml, target, _type) do
    {:error, {:unsupported_target, target}}
  end

  # Ensure we have an encryption key
  defp ensure_key(nil, opts) do
    case opts[:key_transport] do
      {_algo, _pub_key} ->
        # Generate a random key
        key_size =
          case opts[:algorithm] do
            algo when algo in [:aes_128_gcm, :aes_128_cbc] -> 16
            algo when algo in [:aes_256_gcm, :aes_256_cbc] -> 32
            _ -> 32
          end

        {:ok, Algorithms.generate_key(key_size)}

      nil ->
        {:error, :no_encryption_key}
    end
  end

  defp ensure_key(key, _opts) when is_binary(key), do: {:ok, key}

  # Encrypt content using specified algorithm
  defp encrypt_content(content, key, algorithm) do
    Algorithms.encrypt(content, algorithm, key)
  end

  # Build EncryptedData element
  defp build_encrypted_data(encrypted, key, opts) do
    algorithm = opts[:algorithm]
    enc_uri = Algorithms.encryption_algorithm_uri(algorithm)

    # Build cipher value based on algorithm type
    cipher_value =
      case encrypted do
        {iv, ciphertext, tag} ->
          # GCM: IV || ciphertext || tag
          Base.encode64(iv <> ciphertext <> tag)

        {iv, ciphertext} ->
          # CBC: IV || ciphertext
          Base.encode64(iv <> ciphertext)
      end

    # Optional ID attribute
    id_attr =
      case opts[:id] do
        nil -> ""
        id -> ~s( Id="#{id}")
      end

    # Type attribute for element vs content encryption
    type_attr =
      case opts[:type] do
        :element ->
          ~s( Type="http://www.w3.org/2001/04/xmlenc#Element")

        :content ->
          ~s( Type="http://www.w3.org/2001/04/xmlenc#Content")
      end

    # Build KeyInfo if key transport is used
    key_info =
      case opts[:key_transport] do
        {kt_algo, public_key} ->
          build_key_info(key, kt_algo, public_key)

        nil ->
          ""
      end

    encrypted_data = """
    <xenc:EncryptedData xmlns:xenc="#{Namespaces.xenc()}"#{id_attr}#{type_attr}>
      <xenc:EncryptionMethod Algorithm="#{enc_uri}"/>#{key_info}
      <xenc:CipherData>
        <xenc:CipherValue>#{cipher_value}</xenc:CipherValue>
      </xenc:CipherData>
    </xenc:EncryptedData>
    """

    {:ok, String.trim(encrypted_data)}
  end

  # Build KeyInfo with EncryptedKey
  defp build_key_info(key, kt_algo, public_key) do
    kt_uri = Algorithms.key_transport_algorithm_uri(kt_algo)

    case Algorithms.encrypt_key(key, kt_algo, public_key) do
      {:ok, encrypted_key} ->
        encrypted_key_b64 = Base.encode64(encrypted_key)

        """

          <ds:KeyInfo xmlns:ds="#{Namespaces.dsig()}">
            <xenc:EncryptedKey xmlns:xenc="#{Namespaces.xenc()}">
              <xenc:EncryptionMethod Algorithm="#{kt_uri}"/>
              <xenc:CipherData>
                <xenc:CipherValue>#{encrypted_key_b64}</xenc:CipherValue>
              </xenc:CipherData>
            </xenc:EncryptedKey>
          </ds:KeyInfo>
        """

      {:error, _} = error ->
        # This shouldn't happen in normal use
        raise "Key encryption failed: #{inspect(error)}"
    end
  end

  # Replace target in document with EncryptedData
  defp replace_target(xml, "#" <> id, encrypted_data, :element) do
    # Find and replace the entire element
    events = FnXML.Parser.parse(xml)

    case replace_element_by_id(events, id, encrypted_data) do
      {:ok, new_events} ->
        result = serialize_events(new_events)
        {:ok, result}

      error ->
        error
    end
  end

  defp replace_target(xml, "#" <> id, encrypted_data, :content) do
    # Find element and replace just its content
    events = FnXML.Parser.parse(xml)

    case replace_element_content_by_id(events, id, encrypted_data) do
      {:ok, new_events} ->
        result = serialize_events(new_events)
        {:ok, result}

      error ->
        error
    end
  end

  # Find element by ID
  defp find_element_by_id(events, target_id) do
    state = %{
      status: :searching,
      depth: 0,
      events: []
    }

    result =
      Enum.reduce_while(events, state, fn event, acc ->
        case {acc.status, event} do
          {:searching, {:start_element, _name, attrs, _, _, _} = evt} ->
            if has_id_attr?(attrs, target_id) do
              {:cont, %{acc | status: :collecting, depth: 1, events: [evt]}}
            else
              {:cont, acc}
            end

          {:searching, {:start_element, _name, attrs, _} = evt} ->
            if has_id_attr?(attrs, target_id) do
              {:cont, %{acc | status: :collecting, depth: 1, events: [evt]}}
            else
              {:cont, acc}
            end

          {:collecting, {:start_element, _, _, _, _, _} = evt} ->
            {:cont, %{acc | depth: acc.depth + 1, events: [evt | acc.events]}}

          {:collecting, {:start_element, _, _, _} = evt} ->
            {:cont, %{acc | depth: acc.depth + 1, events: [evt | acc.events]}}

          {:collecting, evt} when acc.depth == 1 ->
            case evt do
              {:end_element, _, _, _, _} ->
                {:halt, %{acc | status: :found, events: Enum.reverse([evt | acc.events])}}

              {:end_element, _, _} ->
                {:halt, %{acc | status: :found, events: Enum.reverse([evt | acc.events])}}

              {:end_element, _} ->
                {:halt, %{acc | status: :found, events: Enum.reverse([evt | acc.events])}}

              _ ->
                {:cont, %{acc | events: [evt | acc.events]}}
            end

          {:collecting, {:end_element, _, _, _, _} = evt} ->
            {:cont, %{acc | depth: acc.depth - 1, events: [evt | acc.events]}}

          {:collecting, {:end_element, _, _} = evt} ->
            {:cont, %{acc | depth: acc.depth - 1, events: [evt | acc.events]}}

          {:collecting, {:end_element, _} = evt} ->
            {:cont, %{acc | depth: acc.depth - 1, events: [evt | acc.events]}}

          {:collecting, evt} ->
            {:cont, %{acc | events: [evt | acc.events]}}

          _ ->
            {:cont, acc}
        end
      end)

    case result.status do
      :found -> {:ok, result.events}
      _ -> :not_found
    end
  end

  # Find element content (children only) by ID
  defp find_element_content_by_id(events, target_id) do
    state = %{
      status: :searching,
      depth: 0,
      events: []
    }

    result =
      Enum.reduce_while(events, state, fn event, acc ->
        case {acc.status, event} do
          {:searching, {:start_element, _name, attrs, _, _, _}} ->
            if has_id_attr?(attrs, target_id) do
              # Start collecting after the start element (depth 0 = inside element)
              {:cont, %{acc | status: :collecting, depth: 0}}
            else
              {:cont, acc}
            end

          {:searching, {:start_element, _name, attrs, _}} ->
            if has_id_attr?(attrs, target_id) do
              {:cont, %{acc | status: :collecting, depth: 0}}
            else
              {:cont, acc}
            end

          {:collecting, {:start_element, _, _, _, _, _} = evt} ->
            {:cont, %{acc | depth: acc.depth + 1, events: [evt | acc.events]}}

          {:collecting, {:start_element, _, _, _} = evt} ->
            {:cont, %{acc | depth: acc.depth + 1, events: [evt | acc.events]}}

          {:collecting, evt} when acc.depth == 0 ->
            case evt do
              {:end_element, _, _, _, _} ->
                {:halt, %{acc | status: :found, events: Enum.reverse(acc.events)}}

              {:end_element, _, _} ->
                {:halt, %{acc | status: :found, events: Enum.reverse(acc.events)}}

              {:end_element, _} ->
                {:halt, %{acc | status: :found, events: Enum.reverse(acc.events)}}

              _ ->
                {:cont, %{acc | events: [evt | acc.events]}}
            end

          {:collecting, {:end_element, _, _, _, _} = evt} ->
            {:cont, %{acc | depth: acc.depth - 1, events: [evt | acc.events]}}

          {:collecting, {:end_element, _, _} = evt} ->
            {:cont, %{acc | depth: acc.depth - 1, events: [evt | acc.events]}}

          {:collecting, {:end_element, _} = evt} ->
            {:cont, %{acc | depth: acc.depth - 1, events: [evt | acc.events]}}

          {:collecting, evt} ->
            {:cont, %{acc | events: [evt | acc.events]}}

          _ ->
            {:cont, acc}
        end
      end)

    case result.status do
      :found -> {:ok, result.events}
      _ -> :not_found
    end
  end

  # Replace element by ID with replacement text
  defp replace_element_by_id(events, target_id, replacement) do
    state = %{
      status: :searching,
      depth: 0,
      events: [],
      replaced: false
    }

    result =
      Enum.reduce(events, state, fn event, acc ->
        case {acc.status, event} do
          {:searching, {:start_element, _name, attrs, _, _, _} = evt} ->
            if has_id_attr?(attrs, target_id) do
              # Skip this element, insert replacement
              %{acc | status: :skipping, depth: 1, replaced: true}
            else
              %{acc | events: [evt | acc.events]}
            end

          {:searching, {:start_element, _name, attrs, _} = evt} ->
            if has_id_attr?(attrs, target_id) do
              %{acc | status: :skipping, depth: 1, replaced: true}
            else
              %{acc | events: [evt | acc.events]}
            end

          {:skipping, {:start_element, _, _, _, _, _}} ->
            %{acc | depth: acc.depth + 1}

          {:skipping, {:start_element, _, _, _}} ->
            %{acc | depth: acc.depth + 1}

          {:skipping, {:end_element, _, _, _, _}} when acc.depth == 1 ->
            # End of skipped element - insert replacement
            replacement_event = {:raw, replacement}
            %{acc | status: :searching, depth: 0, events: [replacement_event | acc.events]}

          {:skipping, {:end_element, _, _}} when acc.depth == 1 ->
            replacement_event = {:raw, replacement}
            %{acc | status: :searching, depth: 0, events: [replacement_event | acc.events]}

          {:skipping, {:end_element, _}} when acc.depth == 1 ->
            replacement_event = {:raw, replacement}
            %{acc | status: :searching, depth: 0, events: [replacement_event | acc.events]}

          {:skipping, {:end_element, _, _, _, _}} ->
            %{acc | depth: acc.depth - 1}

          {:skipping, {:end_element, _, _}} ->
            %{acc | depth: acc.depth - 1}

          {:skipping, {:end_element, _}} ->
            %{acc | depth: acc.depth - 1}

          {:skipping, _} ->
            acc

          {:searching, evt} ->
            %{acc | events: [evt | acc.events]}
        end
      end)

    if result.replaced do
      {:ok, Enum.reverse(result.events)}
    else
      {:error, {:element_not_found, target_id}}
    end
  end

  # Replace element content by ID
  defp replace_element_content_by_id(events, target_id, replacement) do
    state = %{
      status: :searching,
      depth: 0,
      events: [],
      replaced: false
    }

    result =
      Enum.reduce(events, state, fn event, acc ->
        case {acc.status, event} do
          {:searching, {:start_element, _name, attrs, _, _, _} = evt} ->
            if has_id_attr?(attrs, target_id) do
              # Keep the start element, skip content
              %{acc | status: :skipping, depth: 0, events: [evt | acc.events], replaced: true}
            else
              %{acc | events: [evt | acc.events]}
            end

          {:searching, {:start_element, _name, attrs, _} = evt} ->
            if has_id_attr?(attrs, target_id) do
              %{acc | status: :skipping, depth: 0, events: [evt | acc.events], replaced: true}
            else
              %{acc | events: [evt | acc.events]}
            end

          {:skipping, {:start_element, _, _, _, _, _}} ->
            %{acc | depth: acc.depth + 1}

          {:skipping, {:start_element, _, _, _}} ->
            %{acc | depth: acc.depth + 1}

          {:skipping, {:end_element, _, _, _, _} = evt} when acc.depth == 0 ->
            # End of target element - insert replacement before end tag
            replacement_event = {:raw, replacement}
            %{acc | status: :searching, events: [evt, replacement_event | acc.events]}

          {:skipping, {:end_element, _, _} = evt} when acc.depth == 0 ->
            replacement_event = {:raw, replacement}
            %{acc | status: :searching, events: [evt, replacement_event | acc.events]}

          {:skipping, {:end_element, _} = evt} when acc.depth == 0 ->
            replacement_event = {:raw, replacement}
            %{acc | status: :searching, events: [evt, replacement_event | acc.events]}

          {:skipping, {:end_element, _, _, _, _}} ->
            %{acc | depth: acc.depth - 1}

          {:skipping, {:end_element, _, _}} ->
            %{acc | depth: acc.depth - 1}

          {:skipping, {:end_element, _}} ->
            %{acc | depth: acc.depth - 1}

          {:skipping, _} ->
            acc

          {:searching, evt} ->
            %{acc | events: [evt | acc.events]}
        end
      end)

    if result.replaced do
      {:ok, Enum.reverse(result.events)}
    else
      {:error, {:element_not_found, target_id}}
    end
  end

  defp has_id_attr?(attrs, target_id) do
    Enum.any?(attrs, fn
      {"Id", ^target_id} -> true
      {"ID", ^target_id} -> true
      {"id", ^target_id} -> true
      _ -> false
    end)
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

  defp event_to_iodata({:end_element, tag, _, _, _}) do
    ["</", tag, ">"]
  end

  defp event_to_iodata({:end_element, tag, _}) do
    ["</", tag, ">"]
  end

  defp event_to_iodata({:end_element, tag}) do
    ["</", tag, ">"]
  end

  defp event_to_iodata({:characters, content, _, _, _}) do
    escape_text(content)
  end

  defp event_to_iodata({:characters, content, _}) do
    escape_text(content)
  end

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
