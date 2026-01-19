defmodule FnXML.Security.Signature.Verifier do
  @moduledoc """
  XML Signature verification.

  Implements the signature verification process according to W3C XML-Signature:

  1. Validate all Reference digests
  2. Canonicalize SignedInfo
  3. Verify signature over canonical SignedInfo
  """

  alias FnXML.Namespaces, as: XMLNamespaces
  alias FnXML.Security.{Algorithms, C14N, Namespaces}
  alias FnXML.Security.Signature.Reference

  @doc """
  Verify an XML Signature.

  ## Process

  1. Extract and parse the Signature element
  2. For each Reference:
     - Dereference the URI
     - Apply transforms
     - Verify digest value
  3. Canonicalize SignedInfo
  4. Verify SignatureValue over canonical SignedInfo

  ## Returns

  - `{:ok, :valid}` - Signature is valid
  - `{:error, reason}` - Verification failed
  """
  @spec verify(binary(), term(), keyword()) :: {:ok, :valid} | {:error, term()}
  def verify(xml, public_key, _opts \\ []) do
    with {:ok, sig_info} <- parse_signature(xml),
         :ok <- validate_references(sig_info, xml),
         :ok <- verify_signature_value(sig_info, public_key) do
      {:ok, :valid}
    end
  end

  # Parse signature and extract all needed information
  defp parse_signature(xml) when is_binary(xml) do
    events = FnXML.Parser.parse(xml)

    with {:ok, sig_events} <- find_signature_events(events),
         {:ok, info} <- extract_signature_info(sig_events, xml) do
      {:ok, info}
    end
  end

  defp find_signature_events(events) do
    dsig_ns = Namespaces.dsig()

    state = %{
      in_signature: false,
      depth: 0,
      events: [],
      found: false
    }

    result =
      Enum.reduce_while(events, state, fn event, acc ->
        case {acc.in_signature, event} do
          # Found start of Signature
          {false, {:start_element, name, attrs, _, _, _}}
          when name == "Signature" or name == "ds:Signature" ->
            if in_dsig_namespace?(name, attrs, dsig_ns) do
              {:cont, %{acc | in_signature: true, depth: 1, events: [event]}}
            else
              {:cont, acc}
            end

          {false, {:start_element, name, attrs, _}}
          when name == "Signature" or name == "ds:Signature" ->
            if in_dsig_namespace?(name, attrs, dsig_ns) do
              {:cont, %{acc | in_signature: true, depth: 1, events: [event]}}
            else
              {:cont, acc}
            end

          # Inside Signature - track depth
          {true, {:start_element, _, _, _, _, _}} ->
            {:cont, %{acc | depth: acc.depth + 1, events: [event | acc.events]}}

          {true, {:start_element, _, _, _}} ->
            {:cont, %{acc | depth: acc.depth + 1, events: [event | acc.events]}}

          # End element inside Signature
          {true, {:end_element, _, _, _, _}} when acc.depth > 1 ->
            {:cont, %{acc | depth: acc.depth - 1, events: [event | acc.events]}}

          {true, {:end_element, _, _}} when acc.depth > 1 ->
            {:cont, %{acc | depth: acc.depth - 1, events: [event | acc.events]}}

          {true, {:end_element, _}} when acc.depth > 1 ->
            {:cont, %{acc | depth: acc.depth - 1, events: [event | acc.events]}}

          # End of Signature
          {true, {:end_element, _, _, _, _}} when acc.depth == 1 ->
            final = %{acc | events: [event | acc.events], found: true, in_signature: false}
            {:halt, final}

          {true, {:end_element, _, _}} when acc.depth == 1 ->
            final = %{acc | events: [event | acc.events], found: true, in_signature: false}
            {:halt, final}

          {true, {:end_element, _}} when acc.depth == 1 ->
            final = %{acc | events: [event | acc.events], found: true, in_signature: false}
            {:halt, final}

          # Other events inside Signature
          {true, _} ->
            {:cont, %{acc | events: [event | acc.events]}}

          # Outside Signature
          _ ->
            {:cont, acc}
        end
      end)

    if result.found do
      {:ok, Enum.reverse(result.events)}
    else
      {:error, :signature_not_found}
    end
  end

  defp in_dsig_namespace?(name, attrs, dsig_ns) do
    cond do
      String.starts_with?(name, "ds:") ->
        Enum.any?(attrs, fn
          {"xmlns:ds", ^dsig_ns} -> true
          _ -> false
        end)

      true ->
        Enum.any?(attrs, fn
          {"xmlns", ^dsig_ns} -> true
          _ -> false
        end)
    end
  end

  # Extract all signature information from parsed events
  defp extract_signature_info(sig_events, source_xml) do
    info = %{
      source_xml: source_xml,
      c14n_algorithm: nil,
      signature_algorithm: nil,
      signature_value: nil,
      signed_info_events: [],
      references: []
    }

    {:ok, parse_signature_elements(sig_events, info)}
  end

  defp parse_signature_elements(events, info) do
    state = %{
      info: info,
      current_element: nil,
      in_signed_info: false,
      signed_info_depth: 0,
      signed_info_events: [],
      current_reference: nil,
      current_transforms: [],
      current_transform: nil,
      text_buffer: ""
    }

    result =
      Enum.reduce(events, state, fn event, acc ->
        process_signature_event(event, acc)
      end)

    %{result.info | signed_info_events: Enum.reverse(result.signed_info_events)}
  end

  defp process_signature_event(event, state) do
    case event do
      {:start_element, name, attrs, _, _, _} ->
        handle_start_element(XMLNamespaces.local_part(name), attrs, event, state)

      {:start_element, name, attrs, _} ->
        handle_start_element(XMLNamespaces.local_part(name), attrs, event, state)

      {:end_element, name, _, _, _} ->
        handle_end_element(XMLNamespaces.local_part(name), state)

      {:end_element, name, _} ->
        handle_end_element(XMLNamespaces.local_part(name), state)

      {:end_element, name} ->
        handle_end_element(XMLNamespaces.local_part(name), state)

      {:characters, content, _, _, _} ->
        handle_characters(content, state)

      {:characters, content, _} ->
        handle_characters(content, state)

      _ ->
        # Also collect for SignedInfo
        if state.in_signed_info do
          %{state | signed_info_events: [event | state.signed_info_events]}
        else
          state
        end
    end
  end

  defp handle_start_element("SignedInfo", _attrs, event, state) do
    %{state | in_signed_info: true, signed_info_depth: 1, signed_info_events: [event]}
  end

  defp handle_start_element("CanonicalizationMethod", attrs, event, state) do
    algo =
      case find_attr(attrs, "Algorithm") do
        nil -> nil
        uri -> parse_c14n_uri(uri)
      end

    state =
      if state.in_signed_info do
        %{state | signed_info_events: [event | state.signed_info_events]}
      else
        state
      end

    %{state | info: %{state.info | c14n_algorithm: algo}}
  end

  defp handle_start_element("SignatureMethod", attrs, event, state) do
    algo =
      case find_attr(attrs, "Algorithm") do
        nil -> nil
        uri -> parse_signature_uri(uri)
      end

    state =
      if state.in_signed_info do
        %{state | signed_info_events: [event | state.signed_info_events]}
      else
        state
      end

    %{state | info: %{state.info | signature_algorithm: algo}}
  end

  defp handle_start_element("Reference", attrs, event, state) do
    ref = %{
      uri: find_attr(attrs, "URI") || "",
      transforms: [],
      digest_algorithm: nil,
      digest_value: nil
    }

    state =
      if state.in_signed_info do
        %{state | signed_info_events: [event | state.signed_info_events]}
      else
        state
      end

    %{state | current_reference: ref}
  end

  defp handle_start_element("Transform", attrs, event, state) do
    algo =
      case find_attr(attrs, "Algorithm") do
        nil -> nil
        uri -> parse_transform_uri(uri)
      end

    transform = %{algorithm: algo, inclusive_namespaces: []}

    state =
      if state.in_signed_info do
        %{state | signed_info_events: [event | state.signed_info_events]}
      else
        state
      end

    %{state | current_transform: transform}
  end

  defp handle_start_element("InclusiveNamespaces", attrs, event, state) do
    prefixes =
      case find_attr(attrs, "PrefixList") do
        nil -> []
        list -> String.split(list, " ", trim: true)
      end

    state =
      if state.in_signed_info do
        %{state | signed_info_events: [event | state.signed_info_events]}
      else
        state
      end

    case state.current_transform do
      nil ->
        state

      transform ->
        %{state | current_transform: %{transform | inclusive_namespaces: prefixes}}
    end
  end

  defp handle_start_element("DigestMethod", attrs, event, state) do
    algo =
      case find_attr(attrs, "Algorithm") do
        nil -> nil
        uri -> parse_digest_uri(uri)
      end

    state =
      if state.in_signed_info do
        %{state | signed_info_events: [event | state.signed_info_events]}
      else
        state
      end

    case state.current_reference do
      nil ->
        state

      ref ->
        %{state | current_reference: %{ref | digest_algorithm: algo}}
    end
  end

  defp handle_start_element(name, _attrs, event, state) do
    state = %{state | current_element: name, text_buffer: ""}

    if state.in_signed_info do
      %{
        state
        | signed_info_depth: state.signed_info_depth + 1,
          signed_info_events: [event | state.signed_info_events]
      }
    else
      state
    end
  end

  defp handle_end_element("SignedInfo", state) do
    # Don't add end element to events since we want just the content
    %{state | in_signed_info: false, signed_info_depth: 0}
  end

  defp handle_end_element("Reference", state) do
    ref = state.current_reference
    refs = [ref | state.info.references]

    state =
      if state.in_signed_info do
        %{state | signed_info_depth: state.signed_info_depth - 1}
      else
        state
      end

    %{state | info: %{state.info | references: refs}, current_reference: nil}
  end

  defp handle_end_element("Transform", state) do
    transform = state.current_transform

    state =
      if state.in_signed_info do
        %{state | signed_info_depth: state.signed_info_depth - 1}
      else
        state
      end

    case state.current_reference do
      nil ->
        %{state | current_transform: nil}

      ref ->
        transforms = [transform | ref.transforms]
        %{state | current_reference: %{ref | transforms: transforms}, current_transform: nil}
    end
  end

  defp handle_end_element("DigestValue", state) do
    digest = state.text_buffer |> String.trim() |> Base.decode64!()

    state =
      if state.in_signed_info do
        %{state | signed_info_depth: state.signed_info_depth - 1}
      else
        state
      end

    case state.current_reference do
      nil ->
        %{state | text_buffer: ""}

      ref ->
        %{state | current_reference: %{ref | digest_value: digest}, text_buffer: ""}
    end
  end

  defp handle_end_element("SignatureValue", state) do
    sig_value = state.text_buffer |> String.trim() |> Base.decode64!()
    %{state | info: %{state.info | signature_value: sig_value}, text_buffer: ""}
  end

  defp handle_end_element(_name, state) do
    if state.in_signed_info and state.signed_info_depth > 0 do
      %{state | signed_info_depth: state.signed_info_depth - 1}
    else
      state
    end
  end

  defp handle_characters(content, state) do
    if state.in_signed_info do
      %{
        state
        | text_buffer: state.text_buffer <> content,
          signed_info_events: [{:characters, content, nil} | state.signed_info_events]
      }
    else
      %{state | text_buffer: state.text_buffer <> content}
    end
  end

  # Validate all references
  defp validate_references(sig_info, xml) do
    results =
      sig_info.references
      |> Enum.map(fn ref ->
        Reference.validate(ref, xml)
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      error -> error
    end
  end

  # Verify signature value over canonical SignedInfo
  defp verify_signature_value(sig_info, public_key) do
    # Reconstruct SignedInfo as XML and canonicalize
    signed_info_xml = serialize_signed_info(sig_info.signed_info_events)

    events = FnXML.Parser.parse(signed_info_xml)

    c14n_opts =
      case sig_info.c14n_algorithm do
        nil -> []
        algo -> [algorithm: algo]
      end

    canonical = C14N.canonicalize(events, c14n_opts)

    # Verify signature
    Algorithms.verify(
      canonical,
      sig_info.signature_value,
      sig_info.signature_algorithm,
      public_key
    )
  end

  defp serialize_signed_info(events) do
    events
    |> Enum.map(&event_to_iodata/1)
    |> IO.iodata_to_binary()
  end

  defp event_to_iodata({:start_element, tag, attrs, _, _, _}) do
    event_to_iodata({:start_element, tag, attrs, nil})
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

  defp find_attr(attrs, name) do
    case Enum.find(attrs, fn {k, _} -> k == name end) do
      {_, v} -> v
      nil -> nil
    end
  end

  defp parse_c14n_uri(uri) do
    case C14N.algorithm_atom(uri) do
      {:ok, algo} -> algo
      _ -> nil
    end
  end

  defp parse_signature_uri(uri) do
    case Algorithms.signature_algorithm_from_uri(uri) do
      {:ok, algo} -> algo
      _ -> nil
    end
  end

  defp parse_digest_uri(uri) do
    case Algorithms.digest_algorithm_from_uri(uri) do
      {:ok, algo} -> algo
      _ -> nil
    end
  end

  defp parse_transform_uri(uri) do
    cond do
      uri == Namespaces.enveloped_signature() -> :enveloped_signature
      uri == Namespaces.base64() -> :base64
      true -> parse_c14n_uri(uri)
    end
  end
end
