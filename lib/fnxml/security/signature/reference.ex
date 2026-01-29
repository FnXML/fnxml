defmodule FnXML.Security.Signature.Reference do
  @moduledoc """
  XML Signature Reference processing.

  Handles the creation and validation of Reference elements, including:
  - URI dereferencing
  - Transform application
  - Digest computation and validation
  """

  alias FnXML.C14N
  alias FnXML.Security.{Algorithms, Namespaces}

  @doc """
  Create a Reference element with digest value.

  ## Options

  - `:reference_uri` - URI for the reference (default: "" for enveloped)
  - `:digest_algorithm` - Algorithm for digest (default: :sha256)
  - `:type` - Signature type (:enveloped, :enveloping, :detached)
  - `:c14n_algorithm` - Canonicalization algorithm
  - `:transforms` - Additional transforms to apply
  """
  @spec create(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  def create(xml, opts) do
    uri = Keyword.get(opts, :reference_uri, "")
    digest_algo = Keyword.get(opts, :digest_algorithm, :sha256)
    sig_type = Keyword.get(opts, :type, :enveloped)
    c14n_algo = Keyword.get(opts, :c14n_algorithm, :exc_c14n)
    inclusive_ns = Keyword.get(opts, :inclusive_namespaces, [])

    # Build transform list based on signature type
    transforms = build_transforms(sig_type, c14n_algo, inclusive_ns)

    # Apply transforms and compute digest
    with {:ok, transformed} <- apply_transforms(xml, transforms, sig_type),
         digest <- compute_digest(transformed, digest_algo) do
      digest_b64 = Base.encode64(digest)
      digest_uri = Algorithms.digest_algorithm_uri(digest_algo)

      uri_attr = if uri == "", do: ~s(URI=""), else: ~s(URI="#{uri}")

      reference = """
      <ds:Reference xmlns:ds="#{Namespaces.dsig()}" #{uri_attr}>
        <ds:Transforms>
          #{transforms_to_xml(transforms)}
        </ds:Transforms>
        <ds:DigestMethod Algorithm="#{digest_uri}"/>
        <ds:DigestValue>#{digest_b64}</ds:DigestValue>
      </ds:Reference>
      """

      {:ok, String.trim(reference)}
    end
  end

  @doc """
  Validate a Reference element by recomputing the digest.

  Returns `:ok` if the digest matches, `{:error, :digest_mismatch}` otherwise.
  """
  @spec validate(map(), binary()) :: :ok | {:error, term()}
  def validate(reference_info, source_xml) do
    uri = reference_info[:uri] || ""
    digest_algo = reference_info[:digest_algorithm]
    expected_digest = reference_info[:digest_value]
    transforms = reference_info[:transforms] || []

    # Dereference URI (for now, "" means the whole document)
    with {:ok, dereferenced} <- dereference_uri(uri, source_xml),
         {:ok, transformed} <- apply_transform_list(dereferenced, transforms),
         computed_digest <- compute_digest(transformed, digest_algo) do
      if computed_digest == expected_digest do
        :ok
      else
        {:error, {:digest_mismatch, uri}}
      end
    end
  end

  # Build list of transforms based on signature type
  defp build_transforms(:enveloped, c14n_algo, inclusive_ns) do
    [
      {:enveloped_signature, nil},
      {:c14n, c14n_algo, inclusive_ns}
    ]
  end

  defp build_transforms(:enveloping, c14n_algo, inclusive_ns) do
    [{:c14n, c14n_algo, inclusive_ns}]
  end

  defp build_transforms(:detached, c14n_algo, inclusive_ns) do
    [{:c14n, c14n_algo, inclusive_ns}]
  end

  # Apply transforms to get canonical form for digest
  defp apply_transforms(xml, transforms, sig_type) do
    # For enveloped signatures, we need to compute the digest as if
    # the Signature element didn't exist yet (which it doesn't)
    case sig_type do
      :enveloped ->
        # For new signatures, just canonicalize the document
        events = FnXML.Parser.parse(xml)
        c14n_opts = extract_c14n_opts(transforms)
        canonical = C14N.canonicalize(events, c14n_opts)
        {:ok, canonical}

      _ ->
        events = FnXML.Parser.parse(xml)
        c14n_opts = extract_c14n_opts(transforms)
        canonical = C14N.canonicalize(events, c14n_opts)
        {:ok, canonical}
    end
  end

  defp extract_c14n_opts(transforms) do
    Enum.reduce(transforms, [], fn
      {:c14n, algo, inclusive_ns}, acc ->
        acc
        |> Keyword.put(:algorithm, algo)
        |> Keyword.put(:inclusive_namespaces, inclusive_ns)

      _, acc ->
        acc
    end)
  end

  # Convert transforms to XML elements
  defp transforms_to_xml(transforms) do
    transforms
    |> Enum.map(&transform_to_xml/1)
    |> Enum.join("\n    ")
  end

  defp transform_to_xml({:enveloped_signature, _}) do
    ~s(<ds:Transform Algorithm="#{Namespaces.enveloped_signature()}"/>)
  end

  defp transform_to_xml({:c14n, algo, inclusive_ns}) do
    uri = C14N.algorithm_uri(algo)

    inclusive_element =
      case {algo, inclusive_ns} do
        {a, prefixes} when a in [:exc_c14n, :exc_c14n_with_comments] and prefixes != [] ->
          prefix_list = Enum.join(prefixes, " ")

          """
          <ec:InclusiveNamespaces xmlns:ec="#{Namespaces.exc_c14n()}" PrefixList="#{prefix_list}"/>
          """

        _ ->
          ""
      end

    if inclusive_element == "" do
      ~s(<ds:Transform Algorithm="#{uri}"/>)
    else
      """
      <ds:Transform Algorithm="#{uri}">
            #{String.trim(inclusive_element)}
          </ds:Transform>
      """
      |> String.trim()
    end
  end

  defp transform_to_xml({:base64, _}) do
    ~s(<ds:Transform Algorithm="#{Namespaces.base64()}"/>)
  end

  # Compute digest using specified algorithm
  defp compute_digest(data, algorithm) do
    Algorithms.digest(data, algorithm)
  end

  # Dereference URI to get content to digest
  defp dereference_uri("", xml) do
    # Empty URI means the whole document (minus Signature element for enveloped)
    {:ok, xml}
  end

  defp dereference_uri("#" <> id, xml) do
    # Fragment URI - find element with matching ID
    find_element_by_id(xml, id)
  end

  defp dereference_uri(_uri, _xml) do
    # External URIs not supported yet
    {:error, :external_uri_not_supported}
  end

  defp find_element_by_id(xml, id) do
    events = FnXML.Parser.parse(xml)

    # Find element with matching Id attribute
    result =
      events
      |> find_element_with_id(id)
      |> case do
        {:found, element_events} ->
          # Serialize the element
          canonical = C14N.canonicalize(element_events)
          {:ok, canonical}

        :not_found ->
          {:error, {:element_not_found, id}}
      end

    result
  end

  defp find_element_with_id(events, target_id) do
    # Track depth and collect events when inside target element
    {result, _} =
      Enum.reduce_while(events, {:searching, {0, []}}, fn event, {status, {depth, acc}} ->
        case {status, event, depth} do
          # Check if start element has matching ID
          {:searching, {:start_element, _name, attrs, _, _, _} = evt, 0} ->
            if has_id_attr?(attrs, target_id) do
              {:cont, {:collecting, {1, [evt]}}}
            else
              {:cont, {:searching, {0, []}}}
            end

          {:searching, {:start_element, _name, attrs, _} = evt, 0} ->
            if has_id_attr?(attrs, target_id) do
              {:cont, {:collecting, {1, [evt]}}}
            else
              {:cont, {:searching, {0, []}}}
            end

          # Continue searching at deeper levels
          {:searching, {:start_element, _, _, _, _, _}, _} ->
            {:cont, {:searching, {depth + 1, []}}}

          {:searching, {:start_element, _, _, _}, _} ->
            {:cont, {:searching, {depth + 1, []}}}

          {:searching, {:end_element, _, _, _, _}, d} when d > 0 ->
            {:cont, {:searching, {d - 1, []}}}

          {:searching, {:end_element, _, _}, d} when d > 0 ->
            {:cont, {:searching, {d - 1, []}}}

          {:searching, {:end_element, _}, d} when d > 0 ->
            {:cont, {:searching, {d - 1, []}}}

          # Collecting target element
          {:collecting, {:start_element, _, _, _, _, _} = evt, _} ->
            {:cont, {:collecting, {depth + 1, [evt | acc]}}}

          {:collecting, {:start_element, _, _, _} = evt, _} ->
            {:cont, {:collecting, {depth + 1, [evt | acc]}}}

          {:collecting, {:end_element, _, _, _, _} = evt, 1} ->
            # End of target element
            {:halt, {{:found, Enum.reverse([evt | acc])}, {0, []}}}

          {:collecting, {:end_element, _, _} = evt, 1} ->
            {:halt, {{:found, Enum.reverse([evt | acc])}, {0, []}}}

          {:collecting, {:end_element, _} = evt, 1} ->
            {:halt, {{:found, Enum.reverse([evt | acc])}, {0, []}}}

          {:collecting, {:end_element, _, _, _, _} = evt, _} ->
            {:cont, {:collecting, {depth - 1, [evt | acc]}}}

          {:collecting, {:end_element, _, _} = evt, _} ->
            {:cont, {:collecting, {depth - 1, [evt | acc]}}}

          {:collecting, {:end_element, _} = evt, _} ->
            {:cont, {:collecting, {depth - 1, [evt | acc]}}}

          {:collecting, evt, _} ->
            {:cont, {:collecting, {depth, [evt | acc]}}}

          _ ->
            {:cont, {status, {depth, acc}}}
        end
      end)

    result
  end

  defp has_id_attr?(attrs, target_id) do
    Enum.any?(attrs, fn
      {"Id", ^target_id} -> true
      {"ID", ^target_id} -> true
      {"id", ^target_id} -> true
      _ -> false
    end)
  end

  # Apply a list of parsed transforms during verification
  defp apply_transform_list(data, transforms) do
    Enum.reduce_while(transforms, {:ok, data}, fn transform, {:ok, current} ->
      case apply_single_transform(current, transform) do
        {:ok, result} -> {:cont, {:ok, result}}
        error -> {:halt, error}
      end
    end)
  end

  defp apply_single_transform(data, %{algorithm: :enveloped_signature}) do
    # Remove Signature element from data
    {:ok, remove_signature_element(data)}
  end

  defp apply_single_transform(data, %{algorithm: c14n_algo, inclusive_namespaces: inc_ns})
       when c14n_algo in [:c14n, :c14n_with_comments, :exc_c14n, :exc_c14n_with_comments] do
    events = FnXML.Parser.parse(data)
    canonical = C14N.canonicalize(events, algorithm: c14n_algo, inclusive_namespaces: inc_ns)
    {:ok, canonical}
  end

  defp apply_single_transform(data, %{algorithm: :base64}) do
    {:ok, Base.decode64!(data)}
  end

  defp apply_single_transform(_data, %{algorithm: algo}) do
    {:error, {:unsupported_transform, algo}}
  end

  # Remove Signature element for enveloped signature transform
  defp remove_signature_element(xml) when is_binary(xml) do
    # Simple approach: remove everything between <Signature and </Signature>
    # This is a basic implementation - a proper one would use the parser
    xml
    |> String.replace(~r/<ds:Signature[^>]*>.*?<\/ds:Signature>/s, "")
    |> String.replace(~r/<Signature[^>]*xmlns[^>]*>.*?<\/Signature>/s, "")
  end
end
