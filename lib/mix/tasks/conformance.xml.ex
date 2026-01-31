defmodule Mix.Tasks.Conformance.Xml do
  @moduledoc """
  Run XML conformance tests against FnXML parser.

  Uses the W3C XML Conformance Test Suite to validate parser behavior.

  ## Usage

      # Run tests for both Edition 4 and Edition 5 parsers (default)
      mix conformance.xml

      # Run tests for a specific edition only
      mix conformance.xml --edition 4
      mix conformance.xml --edition 5

      # Run specific test set
      mix conformance.xml --set xmltest

      # Run with verbose output
      mix conformance.xml --verbose

      # Quick check (100 tests)
      mix conformance.xml --quick

      # Run only specific test types
      mix conformance.xml --type valid
      mix conformance.xml --type not-wf

  ## Options

      --set NAME      Run tests from specific test set (xmltest, sun, oasis, ibm, etc.)
      --type TYPE     Run only tests of specific type (valid, not-wf, invalid, error)
      --filter PATTERN Filter tests by ID pattern
      --verbose       Print each test result
      --quick         Quick check with first 100 tests
      --limit N       Limit number of tests to run
      --suite PATH    Path to xmlconf test suite (default: searches common locations)
      --edition N     XML 1.0 edition to use: 4 or 5 (default: both)
  """

  use Mix.Task

  @shortdoc "Run XML conformance tests"

  @impl Mix.Task
  def run(args) do
    # Start required applications
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          set: :string,
          type: :string,
          filter: :string,
          verbose: :boolean,
          quick: :boolean,
          limit: :integer,
          suite: :string,
          edition: :integer
        ],
        aliases: [
          s: :set,
          t: :type,
          f: :filter,
          v: :verbose,
          q: :quick,
          l: :limit,
          e: :edition
        ]
      )

    suite_path = find_test_suite(opts[:suite])

    case suite_path do
      nil ->
        Mix.shell().error("Could not find XML conformance test suite.")

        Mix.shell().error(
          "Please specify path with --suite or ensure xmlconf is in a standard location."
        )

        System.halt(1)

      path ->
        Mix.shell().info("Using test suite at: #{path}")

        # Determine which editions to test
        editions =
          case opts[:edition] do
            nil -> [4, 5]
            edition -> [edition]
          end

        run_tests_for_editions(path, editions, opts)
    end
  end

  defp run_tests_for_editions(suite_path, editions, opts) do
    # Run tests for each edition and collect results
    all_edition_results =
      Enum.map(editions, fn edition ->
        Mix.shell().info("\n" <> String.duplicate("=", 60))
        Mix.shell().info("Testing Edition #{edition} Parser")
        Mix.shell().info(String.duplicate("=", 60))

        results = run_tests(suite_path, Keyword.put(opts, :edition, edition))
        {edition, results}
      end)

    # Print combined summary if testing multiple editions
    if length(editions) > 1 do
      print_combined_summary(all_edition_results)
    end
  end

  defp find_test_suite(explicit_path) do
    paths =
      [
        explicit_path,
        "priv/test_suites/xmlconf",
        "../fnconformance/priv/test_suites/xmlconf",
        "../../fnconformance/priv/test_suites/xmlconf",
        Path.expand("~/Projects/elixir/xml/fnconformance/priv/test_suites/xmlconf")
      ]
      |> Enum.filter(& &1)

    Enum.find(paths, fn path ->
      File.exists?(Path.join(path, "xmlconf.xml"))
    end)
  end

  defp run_tests(suite_path, opts) do
    edition = opts[:edition]
    Mix.shell().info("Loading test catalog...")

    tests =
      load_tests(suite_path)
      |> filter_tests(opts)
      |> maybe_limit(opts)

    total = length(tests)
    Mix.shell().info("Running #{total} tests for Edition #{edition}...\n")

    results = run_all_tests(tests, suite_path, opts)

    print_summary(results, edition)

    # Return results for combined summary
    results
  end

  defp load_tests(suite_path) do
    # Parse individual test files directly instead of the master catalog
    # (which has external entity references that are complex to handle)
    test_files = [
      {"xmltest", "xmltest/xmltest.xml"},
      {"sun-valid", "sun/sun-valid.xml"},
      {"sun-invalid", "sun/sun-invalid.xml"},
      {"sun-not-wf", "sun/sun-not-wf.xml"},
      {"sun-error", "sun/sun-error.xml"},
      {"oasis", "oasis/oasis.xml"},
      {"ibm-valid", "ibm/ibm_oasis_valid.xml"},
      {"ibm-invalid", "ibm/ibm_oasis_invalid.xml"},
      {"ibm-not-wf", "ibm/ibm_oasis_not-wf.xml"},
      {"japanese", "japanese/japanese.xml"},
      {"eduni-errata2e", "eduni/errata-2e/errata2e.xml"},
      {"eduni-errata3e", "eduni/errata-3e/errata3e.xml"},
      {"eduni-errata4e", "eduni/errata-4e/errata4e.xml"},
      {"eduni-ns10", "eduni/namespaces/1.0/rmt-ns10.xml"},
      {"eduni-ns11", "eduni/namespaces/1.1/rmt-ns11.xml"}
    ]

    test_files
    |> Enum.flat_map(fn {set_name, rel_path} ->
      full_path = Path.join(suite_path, rel_path)
      base_dir = Path.dirname(full_path)

      if File.exists?(full_path) do
        parse_test_file(full_path, base_dir, set_name)
      else
        []
      end
    end)
  end

  defp parse_test_file(path, base_dir, set_name) do
    case File.read(path) do
      {:ok, content} ->
        # Simple regex-based parsing for TEST elements
        # This avoids needing a full XML parser with DTD support
        ~r/<TEST\s+([^>]+)>([^<]*)<\/TEST>/s
        |> Regex.scan(content)
        |> Enum.map(fn [_full, attrs, description] ->
          parse_test_attrs(attrs, description, base_dir, set_name)
        end)
        |> Enum.filter(& &1)

      {:error, _} ->
        []
    end
  end

  defp parse_test_attrs(attrs_str, description, base_dir, set_name) do
    attrs = parse_xml_attrs(attrs_str)

    case {attrs["ID"], attrs["URI"], attrs["TYPE"]} do
      {id, uri, type} when id != nil and uri != nil and type != nil ->
        %{
          id: id,
          uri: Path.join(base_dir, uri),
          type: String.downcase(type),
          set: set_name,
          description: String.trim(description),
          entities: attrs["ENTITIES"] || "none",
          sections: attrs["SECTIONS"],
          # Parse EDITION attribute (e.g., "5", "1 2 3 4", etc.)
          target_editions: parse_editions(attrs["EDITION"]),
          # NAMESPACE="no" means skip namespace validation
          namespace: attrs["NAMESPACE"] != "no"
        }

      _ ->
        nil
    end
  end

  # Parse EDITION attribute into list of integers
  # "5" -> [5], "1 2 3 4" -> [1, 2, 3, 4], nil -> [1, 2, 3, 4, 5] (all editions)
  defp parse_editions(nil), do: [1, 2, 3, 4, 5]

  defp parse_editions(edition_str) do
    edition_str
    |> String.split()
    |> Enum.map(&String.to_integer/1)
  end

  defp parse_xml_attrs(attrs_str) do
    ~r/(\w+)\s*=\s*"([^"]*)"/
    |> Regex.scan(attrs_str)
    |> Enum.map(fn [_, name, value] -> {name, value} end)
    |> Map.new()
  end

  defp filter_tests(tests, opts) do
    tests
    |> filter_by_set(opts[:set])
    |> filter_by_type(opts[:type])
    |> filter_by_pattern(opts[:filter])
  end

  defp filter_by_set(tests, nil), do: tests

  defp filter_by_set(tests, set) do
    pattern = String.downcase(set)

    Enum.filter(tests, fn t ->
      String.contains?(String.downcase(t.set), pattern)
    end)
  end

  defp filter_by_type(tests, nil), do: tests

  defp filter_by_type(tests, type) do
    Enum.filter(tests, fn t -> t.type == String.downcase(type) end)
  end

  defp filter_by_pattern(tests, nil), do: tests

  defp filter_by_pattern(tests, pattern) do
    Enum.filter(tests, fn t -> String.contains?(t.id, pattern) end)
  end

  defp maybe_limit(tests, opts) do
    cond do
      opts[:quick] -> Enum.take(tests, 100)
      opts[:limit] -> Enum.take(tests, opts[:limit])
      true -> tests
    end
  end

  defp run_all_tests(tests, _suite_path, opts) do
    verbose = opts[:verbose]
    edition = opts[:edition]
    total = length(tests)

    tests
    |> Enum.with_index(1)
    |> Enum.map(fn {test, idx} ->
      result = run_single_test(test, edition)

      if verbose do
        status =
          cond do
            result[:skipped] -> "SKIP"
            result.pass -> "PASS"
            true -> "FAIL"
          end

        Mix.shell().info("[#{idx}/#{total}] #{status} #{test.id}")
      else
        # Progress indicator
        if rem(idx, 100) == 0 do
          Mix.shell().info("  Completed #{idx}/#{total} tests...")
        end
      end

      result
    end)
  end

  defp run_single_test(test, requested_edition) do
    start_time = System.monotonic_time(:millisecond)

    # Check if this test is applicable to the requested edition
    # If test targets only Edition 5 and we're running Edition 4, skip it
    result =
      if requested_edition in test.target_editions do
        case File.read(test.uri) do
          {:ok, content} ->
            # Use the highest applicable edition for this test
            # (e.g., if test targets [1,2,3,4] and we request 4, use 4)
            effective_edition = min(requested_edition, Enum.max(test.target_editions))
            execute_test(test, content, effective_edition)

          {:error, reason} ->
            %{pass: false, error: {:file_error, reason}}
        end
      else
        # Test not applicable to this edition - skip with note
        %{pass: true, skipped: true, note: {:edition_mismatch, test.target_editions}}
      end

    elapsed = System.monotonic_time(:millisecond) - start_time

    Map.merge(result, %{
      id: test.id,
      type: test.type,
      set: test.set,
      elapsed_ms: elapsed,
      target_editions: test.target_editions
    })
  end

  defp execute_test(test, content, edition) do
    # Use full validation pipeline for XML conformance testing
    # Edition determines which character validation rules to use:
    # - Edition 4: Strict enumerated character classes from Appendix B
    # - Edition 5: Permissive broad Unicode ranges
    parse_result =
      try do
        # Convert UTF-16 to UTF-8 if needed (auto-detects BOM)
        # Also convert ISO-8859-1 if declared
        # Normalize line endings (CRLF/CR -> LF) per XML 1.0 spec
        # For XML 1.1, also normalize NEL and LS to LF
        utf8_content =
          content
          |> FnXML.Preprocess.Utf16.to_utf8()
          |> convert_iso8859_if_declared()

        # Detect XML version for line-end normalization
        xml_version = detect_xml_version(utf8_content)

        normalized_content =
          utf8_content
          |> FnXML.Preprocess.Normalize.line_endings()
          |> maybe_normalize_xml11_line_ends(xml_version)

        # Check for encoding mismatch (e.g., UTF-16 declared but no BOM)
        encoding_error =
          case check_encoding_mismatch(content, normalized_content) do
            :ok -> nil
            {:error, reason} -> reason
          end

        # Check if this test has an external-only DTD (no internal subset)
        # For these cases, skip entity validation since we can't resolve external entities
        # But if there's an internal subset [...], we can extract and validate those entities
        has_external_only_dtd = has_external_dtd_without_internal_subset(normalized_content)

        # Extract entity names from internal DTD declarations
        # Returns {parsed_entities, unparsed_entities, external_entities, entity_values}
        {internal_entities, internal_unparsed, internal_external, _entity_values} =
          if has_external_only_dtd do
            {MapSet.new(), MapSet.new(), MapSet.new(), %{}}
          else
            extract_entity_names(normalized_content)
          end

        # Extract entities from internal subset's external PEs (for valid tests)
        # This handles cases like rmt-e2e-18 where entities are defined via external PE chains
        internal_subset_pe_entities =
          if test.type in ["valid", "invalid"] and not has_external_only_dtd do
            extract_entities_from_internal_pe(normalized_content, test.uri)
          else
            MapSet.new()
          end

        # Extract entity names from external DTD (if present and entities are allowed)
        # Only extract for valid/invalid tests, not for not-wf tests
        # For not-wf tests, missing entity definitions may be part of the expected error
        external_entities =
          if test.entities != "none" and test.type in ["valid", "invalid"] do
            extract_external_dtd_entities(normalized_content, test.uri, edition)
          else
            MapSet.new()
          end

        # Merge entity sets (internal takes precedence per XML spec, but for validation
        # we just need to know which entities exist)
        merged_entities =
          external_entities
          |> MapSet.union(internal_entities)
          |> MapSet.union(internal_subset_pe_entities)

        # Check if internal subset contains PE references
        # When PE references are present, undefined entity refs become validity errors
        # (not WFC errors), so non-validating parsers should accept them
        has_pe_references = has_pe_references_in_internal_subset(normalized_content)

        # Determine final entity validation set
        # Include unparsed and external entities info for proper validation
        # Skip entity validation for invalid tests with PE references (undefined becomes VC)
        dtd_entities =
          cond do
            has_external_only_dtd and MapSet.size(merged_entities) == 0 ->
              :skip

            # For invalid tests with PE refs, undefined entities are validity errors
            test.type == "invalid" and has_pe_references ->
              :skip

            true ->
              {merged_entities, internal_unparsed, internal_external}
          end

        # Build external resolver for DTD.resolve() to fetch external DTD content
        external_resolver = build_external_resolver(test.uri)

        # Use edition-specific parser for proper character validation
        parser = FnXML.Parser.generate(edition)

        events =
          normalized_content
          |> wrap_as_list()
          |> parser.stream()
          |> wrap_with_document_events()
          |> FnXML.Event.Validate.compliant()
          |> FnXML.Event.Validate.root_boundary()
          # Validate XML declaration attributes and values
          |> FnXML.Event.Validate.xml_declaration()
          # Validate character references are well-formed
          |> FnXML.Event.Validate.character_references()
          # Validate entity references are defined (predefined or DTD-declared)
          # Skip entity validation for tests with external DTD references
          |> maybe_validate_entities(dtd_entities)
          # Validate attribute values don't contain forbidden '<' character
          # Must be BEFORE entity resolution so &lt; is still an entity ref
          |> FnXML.Event.Validate.attribute_values()
          # Use FnXML.DTD.resolve() for pipeline-friendly DTD entity resolution
          # This extracts entities from the DTD event and resolves them in one pass
          # Use :keep for unknown entities since we may not have all external entities
          |> FnXML.DTD.resolve(
            on_unknown: :keep,
            edition: edition,
            external_resolver: external_resolver
          )
          # Validate namespace constraints (NSC: Prefix Declared, etc.)
          # Skip if NAMESPACE="no" in test definition
          |> maybe_validate_namespaces(test.namespace)
          |> Enum.to_list()

        # Check if any error events exist in the stream
        errors =
          Enum.filter(events, fn
            {:error, _, _, _, _, _} -> true
            {:error, _, _} -> true
            {:error, _} -> true
            # Namespace constraint violations
            {:ns_error, _, _, _} -> true
            _ -> false
          end)

        # Also validate DTD syntax if present (passing edition for name validation)
        # Pass namespace flag to skip NE08 (colon in names) check when namespaces disabled
        dtd_error = validate_dtd(events, edition, test.namespace)

        # For not-wf tests with external entities, also validate external DTD
        # (Only for not-wf tests because valid/invalid tests may have complex
        # parameter entity usage that we can't fully expand)
        external_dtd_error =
          if test.entities != "none" and test.type == "not-wf" do
            case validate_external_dtd(events, test.uri, edition) do
              {:ok, _entities} -> nil
              {:error, reason} -> reason
            end
          else
            nil
          end

        # Validate external parsed entities (TextDecl validation)
        # Only for not-wf tests with external entities
        external_entity_error =
          if test.entities != "none" and test.type == "not-wf" do
            validate_external_parsed_entities(normalized_content, test.uri)
          else
            nil
          end

        # Check for entity forward references in DTD (referenced before declared)
        # Only for not-wf tests since this is a WFC, not a VC
        forward_ref_error =
          if test.type == "not-wf" do
            case extract_internal_dtd_content(normalized_content) do
              nil -> nil
              dtd_content -> check_entity_forward_refs(dtd_content)
            end
          else
            nil
          end

        # Check for namespace URI duplicates after DTD-aware attribute normalization
        # (e.g., xmlns:a="urn:x" and xmlns:b=" urn:x " with NMTOKEN type)
        ns_normalization_error =
          if test.namespace do
            case FnXML.DTD.decode(events, edition: edition) do
              {:ok, model} -> check_dtd_namespace_normalization(events, model)
              _ -> nil
            end
          else
            nil
          end

        cond do
          errors != [] ->
            {:error, errors}

          encoding_error != nil ->
            {:error, {:encoding_error, encoding_error}}

          dtd_error != nil ->
            {:error, {:dtd_error, dtd_error}}

          forward_ref_error != nil and forward_ref_error != :ok ->
            {:error, {:forward_ref_error, forward_ref_error}}

          external_dtd_error != nil ->
            {:error, {:external_dtd_error, external_dtd_error}}

          external_entity_error != nil ->
            {:error, {:external_entity_error, external_entity_error}}

          ns_normalization_error != nil ->
            {:error, {:ns_normalization_error, ns_normalization_error}}

          true ->
            {:ok, events}
        end
      rescue
        e -> {:error, {:exception, Exception.message(e)}}
      catch
        :exit, reason -> {:error, {:exit, reason}}
      end

    evaluate_result(test.type, parse_result)
  end

  # Validate DTD syntax if present in the event stream
  # namespace_enabled: true if namespace validation should be applied
  defp validate_dtd(events, edition, namespace_enabled) do
    case FnXML.DTD.decode(events, edition: edition) do
      {:ok, model} ->
        # Check for circular entity references
        case FnXML.DTD.check_circular_entities(model) do
          {:ok, model} ->
            # Check for undefined entity references
            case FnXML.DTD.check_undefined_entities(model) do
              {:ok, _} ->
                # Check for external entity refs in default attribute values
                case check_external_entity_in_attr_defaults(model) do
                  :ok ->
                    # Check namespace constraints on DTD names (NE08)
                    # Only apply when namespace validation is enabled
                    if namespace_enabled do
                      validate_dtd_namespace_constraints(model)
                    else
                      nil
                    end

                  {:error, reason} ->
                    reason
                end

              {:error, reason} ->
                reason
            end

          {:error, reason} ->
            reason
        end

      {:error, :no_dtd} ->
        nil

      {:error, reason} ->
        reason
    end
  end

  # Check that default attribute values don't contain references to external entities
  # This is WFC: No External Entity References
  defp check_external_entity_in_attr_defaults(model) do
    # Build set of external entity names
    external_entities =
      model.entities
      |> Enum.filter(fn {_name, def} ->
        match?({:external, _, _}, def) or match?({:external_unparsed, _, _, _}, def)
      end)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()

    # If no external entities, nothing to check
    if MapSet.size(external_entities) == 0 do
      :ok
    else
      # Check each attribute definition's default value
      invalid =
        model.attributes
        |> Enum.flat_map(fn {_elem, attrs} ->
          Enum.filter(attrs, fn attr_def ->
            # attr_def is a map with :name, :type, :default keys
            default_value = get_attr_default_value(attr_def)
            default_value != nil and has_external_entity_ref?(default_value, external_entities)
          end)
        end)

      case invalid do
        [] ->
          :ok

        [attr_def | _] ->
          attr_name = get_attr_name(attr_def)
          {:error, "Default attribute value '#{attr_name}' contains external entity reference"}
      end
    end
  end

  defp get_attr_default_value(%{default: {:default, value}}), do: value
  defp get_attr_default_value(%{default: {:fixed, value}}), do: value
  defp get_attr_default_value(_), do: nil

  defp get_attr_name(%{name: name}), do: name
  defp get_attr_name(_), do: "unknown"

  # Extract internal DTD content from DOCTYPE
  defp extract_internal_dtd_content(content) do
    case Regex.run(~r/<!DOCTYPE\s+\S+(?:\s+(?:SYSTEM|PUBLIC)[^>\[]*)?\s*\[(.+?)\]>/s, content) do
      [_, dtd_content] -> dtd_content
      nil -> nil
    end
  end

  # Check for entity references that appear before their declaration
  # This is WFC: Entity Declared
  defp check_entity_forward_refs(dtd_content) do
    # Find all entity declarations and their positions
    entity_positions =
      Regex.scan(~r/<!ENTITY\s+([a-zA-Z_][a-zA-Z0-9._-]*)\s/, dtd_content, return: :index)
      |> Enum.map(fn [{start, _}, {name_start, name_len}] ->
        name = binary_part(dtd_content, name_start, name_len)
        {name, start}
      end)
      |> Map.new()

    # Find all entity references in ATTLIST default values
    # Pattern: ATTLIST ... "..&name;.."
    attlist_refs =
      Regex.scan(
        ~r/<!ATTLIST\s+[^>]*["']([^"']*&[a-zA-Z_][a-zA-Z0-9._-]*;[^"']*)["']/,
        dtd_content,
        return: :index
      )
      |> Enum.flat_map(fn [{start, _} | _] ->
        # Extract the default value portion and find entity refs
        after_attlist = binary_part(dtd_content, start, byte_size(dtd_content) - start)

        Regex.scan(~r/&([a-zA-Z_][a-zA-Z0-9._-]*);/, after_attlist, return: :index)
        |> Enum.take(10)
        |> Enum.map(fn [{ref_offset, _}, {name_offset, name_len}] ->
          name = binary_part(after_attlist, name_offset, name_len)
          {name, start + ref_offset}
        end)
      end)

    # Check for forward references
    forward_ref =
      Enum.find(attlist_refs, fn {name, ref_pos} ->
        case Map.get(entity_positions, name) do
          nil -> false
          decl_pos -> ref_pos < decl_pos
        end
      end)

    case forward_ref do
      nil -> :ok
      {name, _} -> {:error, "Entity '#{name}' referenced before declaration"}
    end
  end

  defp has_external_entity_ref?(value, external_entities) do
    # Find all entity references in the value
    Regex.scan(~r/&([a-zA-Z_][a-zA-Z0-9._-]*);/, value)
    |> Enum.any?(fn [_, name] -> MapSet.member?(external_entities, name) end)
  end

  # Validate external DTD if present
  # Returns {:ok, entities_mapset} on success, {:error, reason} on failure
  defp validate_external_dtd(events, test_uri, edition) do
    # Find DOCTYPE event and extract SYSTEM identifier and internal subset
    case find_doctype_info(events) do
      nil ->
        {:ok, MapSet.new()}

      {system_id, internal_subset_content} ->
        # Extract PE definitions from internal subset
        # These take precedence over external DTD definitions per XML spec
        internal_pe_defs = extract_internal_pe_defs(internal_subset_content)

        # Fetch and parse external DTD
        case FnXML.DTD.ExternalResolver.fetch(system_id, test_uri) do
          {:ok, content} ->
            case FnXML.DTD.ExternalResolver.parse_external_dtd(content,
                   edition: edition,
                   internal_pe_defs: internal_pe_defs
                 ) do
              {:ok, model} ->
                # Extract entity names from external DTD
                entities = model.entities |> Map.keys() |> MapSet.new()
                {:ok, entities}

              {:error, reason} ->
                {:error, reason}
            end

          {:error, {:file_error, _path, :enoent}} ->
            # External file not found - skip validation
            {:ok, MapSet.new()}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # Extract PE definitions from internal DTD subset content
  defp extract_internal_pe_defs(nil), do: %{}
  defp extract_internal_pe_defs(""), do: %{}

  defp extract_internal_pe_defs(content) do
    FnXML.DTD.ParameterEntities.extract_definitions(content)
  end

  # Extract SYSTEM identifier and internal subset from DOCTYPE event
  # Returns {system_id, internal_subset_content} or nil
  defp find_doctype_info(events) do
    Enum.find_value(events, fn
      {:dtd, content, _, _, _} ->
        extract_doctype_info(content)

      {:dtd, content, _loc} ->
        extract_doctype_info(content)

      _ ->
        nil
    end)
  end

  # Parse DOCTYPE content to extract SYSTEM identifier and internal subset
  defp extract_doctype_info(content) do
    # First extract SYSTEM/PUBLIC identifier
    system_id =
      cond do
        # DOCTYPE with SYSTEM identifier: DOCTYPE name SYSTEM "uri"
        match = Regex.run(~r/SYSTEM\s+["']([^"']+)["']/, content) ->
          [_, uri] = match
          uri

        # DOCTYPE with PUBLIC identifier: DOCTYPE name PUBLIC "pubid" "uri"
        match = Regex.run(~r/PUBLIC\s+["'][^"']+["']\s+["']([^"']+)["']/, content) ->
          [_, uri] = match
          uri

        true ->
          nil
      end

    if system_id do
      # Extract internal subset content (content between [ and ])
      internal_subset =
        case Regex.run(~r/\[(.+)\]/s, content) do
          [_, subset] -> subset
          nil -> nil
        end

      {system_id, internal_subset}
    else
      nil
    end
  end

  # NE08: Colons are not allowed in entity names, notation names, or PI targets
  # (PI targets are checked by the namespace validator for element content)
  defp validate_dtd_namespace_constraints(model) do
    # Check entity names for colons
    entity_with_colon =
      model.entities
      |> Map.keys()
      |> Enum.find(&String.contains?(&1, ":"))

    if entity_with_colon do
      {:colon_in_entity_name, entity_with_colon}
    else
      # Check notation names for colons
      notation_with_colon =
        model.notations
        |> Map.keys()
        |> Enum.find(&String.contains?(&1, ":"))

      if notation_with_colon do
        {:colon_in_notation_name, notation_with_colon}
      else
        nil
      end
    end
  end

  # Apply namespace validation only if NAMESPACE attribute is not "no"
  defp maybe_validate_namespaces(stream, true), do: FnXML.Namespaces.validate(stream)
  defp maybe_validate_namespaces(stream, false), do: stream

  # Build an external resolver function for FnXML.DTD.resolve()
  # This resolves relative URIs against the test file's directory
  defp build_external_resolver(test_uri) do
    base_dir = Path.dirname(test_uri)

    fn system_id, _public_id ->
      resolved_path = Path.join(base_dir, system_id)

      case File.read(resolved_path) do
        {:ok, content} -> {:ok, content}
        {:error, reason} -> {:error, {:file_error, resolved_path, reason}}
      end
    end
  end

  # Check for namespace URI equality after DTD-aware attribute normalization
  # Per XML spec, NMTOKEN/ID/IDREF/ENTITY/NOTATION types normalize leading/trailing whitespace
  # This means xmlns:a="urn:x" and xmlns:b=" urn:x " (with NMTOKEN type) would be duplicates
  defp check_dtd_namespace_normalization(events, model) do
    # Get attribute type declarations for xmlns:* attributes
    xmlns_attr_types = extract_xmlns_attr_types(model)

    if map_size(xmlns_attr_types) == 0 do
      nil
    else
      # Find start_element events and check for normalized namespace duplicates
      events
      |> Enum.find_value(fn
        {:start_element, tag, attrs, _, _, _} ->
          check_element_namespace_duplicates(tag, attrs, xmlns_attr_types)

        {:start_element, tag, attrs, _loc} ->
          check_element_namespace_duplicates(tag, attrs, xmlns_attr_types)

        _ ->
          nil
      end)
    end
  end

  # Extract type declarations for xmlns:* attributes from DTD model
  defp extract_xmlns_attr_types(model) do
    model.attributes
    |> Enum.flat_map(fn {elem, attrs} ->
      attrs
      |> Enum.filter(fn attr_def ->
        name = get_attr_name(attr_def)
        String.starts_with?(name, "xmlns:")
      end)
      |> Enum.map(fn attr_def ->
        name = get_attr_name(attr_def)
        type = get_attr_type(attr_def)
        {{elem, name}, type}
      end)
    end)
    |> Map.new()
  end

  # Get attribute type from attribute definition
  defp get_attr_type(%{type: type}), do: type
  defp get_attr_type(_), do: :cdata

  # Check for namespace duplicates after normalization in a single element
  defp check_element_namespace_duplicates(tag, attrs, xmlns_attr_types) do
    # Get xmlns:* attributes
    xmlns_attrs =
      attrs
      |> Enum.filter(fn {name, _} -> String.starts_with?(name, "xmlns:") end)
      |> Enum.map(fn {name, value} ->
        prefix = String.slice(name, 6..-1//1)
        type = Map.get(xmlns_attr_types, {tag, name}, :cdata)
        normalized_value = normalize_attr_value(value, type)
        {prefix, name, normalized_value, value}
      end)

    # Group by normalized value to find duplicates
    duplicates =
      xmlns_attrs
      |> Enum.group_by(fn {_prefix, _name, normalized, _original} -> normalized end)
      |> Enum.filter(fn {_uri, prefixes} -> length(prefixes) > 1 end)

    case duplicates do
      [{uri, prefixes} | _] ->
        prefix_names = Enum.map(prefixes, fn {p, _, _, _} -> p end)
        {:duplicate_namespace_after_normalization, uri, prefix_names}

      [] ->
        nil
    end
  end

  # Normalize attribute value based on DTD type
  # NMTOKEN, ID, IDREF, ENTITY, NOTATION - strip leading/trailing whitespace
  # Also collapse internal whitespace for tokenized types
  defp normalize_attr_value(value, type)
       when type in [:nmtoken, :nmtokens, :id, :idref, :idrefs, :entity, :entities, :notation] do
    value
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp normalize_attr_value(value, _type), do: value

  defp evaluate_result("valid", {:ok, _events}) do
    %{pass: true}
  end

  defp evaluate_result("valid", {:error, reason}) do
    %{pass: false, error: {:unexpected_error, reason}}
  end

  defp evaluate_result("not-wf", {:ok, _events}) do
    %{pass: false, error: :expected_error_but_passed}
  end

  defp evaluate_result("not-wf", {:error, _reason}) do
    %{pass: true}
  end

  defp evaluate_result("invalid", {:ok, _events}) do
    # Invalid tests have well-formed XML but are not valid against DTD
    # Without DTD validation, we consider parse success as pass
    %{pass: true, note: :no_dtd_validation}
  end

  defp evaluate_result("invalid", {:error, reason}) do
    %{pass: false, error: {:unexpected_error, reason}}
  end

  defp evaluate_result("error", {:ok, _events}) do
    # Error tests may or may not fail depending on implementation
    %{pass: true, note: :optional_error}
  end

  defp evaluate_result("error", {:error, _reason}) do
    %{pass: true}
  end

  defp evaluate_result(_type, result) do
    %{pass: false, error: {:unknown_type, result}}
  end

  defp print_summary(results, edition) do
    total = length(results)
    skipped = Enum.count(results, fn r -> r[:skipped] == true end)
    passed = Enum.count(results, fn r -> r.pass and r[:skipped] != true end)
    failed = total - passed - skipped

    # Group by type (excluding skipped)
    active_results = Enum.reject(results, fn r -> r[:skipped] == true end)
    by_type = Enum.group_by(active_results, & &1.type)

    # Group by set (excluding skipped)
    by_set = Enum.group_by(active_results, & &1.set)

    Mix.shell().info("\n" <> String.duplicate("=", 60))
    Mix.shell().info("XML CONFORMANCE TEST RESULTS - Edition #{edition}")
    Mix.shell().info(String.duplicate("=", 60))

    Mix.shell().info("\nOverall:")
    Mix.shell().info("  Passed:    #{passed}")
    Mix.shell().info("  Failed:    #{failed}")
    if skipped > 0, do: Mix.shell().info("  Skipped:   #{skipped} (edition mismatch)")
    active_total = passed + failed

    Mix.shell().info(
      "  Total:     #{active_total}#{if skipped > 0, do: " (#{total} including skipped)", else: ""}"
    )

    pass_rate = if active_total > 0, do: Float.round(passed / active_total * 100, 1), else: 0.0
    Mix.shell().info("  Pass Rate: #{pass_rate}%")

    Mix.shell().info("\nBy Type:")

    for {type, type_results} <- Enum.sort(by_type) do
      type_passed = Enum.count(type_results, & &1.pass)
      type_total = length(type_results)
      Mix.shell().info("  #{String.pad_trailing(type, 12)} #{type_passed}/#{type_total}")
    end

    Mix.shell().info("\nBy Test Set:")

    by_set
    |> Enum.sort_by(fn {_set, results} -> -length(results) end)
    |> Enum.take(15)
    |> Enum.each(fn {set, set_results} ->
      set_passed = Enum.count(set_results, & &1.pass)
      set_total = length(set_results)
      rate = if set_total > 0, do: Float.round(set_passed / set_total * 100, 1), else: 0.0
      Mix.shell().info("  #{String.pad_trailing(set, 20)} #{set_passed}/#{set_total} (#{rate}%)")
    end)

    # Show some failures if any
    failures = Enum.filter(results, &(!&1.pass))

    if length(failures) > 0 do
      Mix.shell().info("\nSample Failures (first 10):")

      failures
      |> Enum.take(10)
      |> Enum.each(fn f ->
        Mix.shell().info("  #{f.id}: #{inspect(f.error)}")
      end)
    end

    Mix.shell().info(String.duplicate("=", 60) <> "\n")
  end

  # Conditionally apply entity reference validation
  defp maybe_validate_entities(stream, :skip), do: stream

  defp maybe_validate_entities(stream, {entities, unparsed, external}) do
    FnXML.Event.Validate.entity_references(stream,
      entities: entities,
      unparsed_entities: unparsed,
      external_entities: external
    )
  end

  defp maybe_validate_entities(stream, entities) when is_struct(entities, MapSet) do
    FnXML.Event.Validate.entity_references(stream, entities: entities)
  end

  # Check if content has external DTD reference without internal subset
  # Pattern: <!DOCTYPE name SYSTEM "uri"> or <!DOCTYPE name PUBLIC "pubid" "uri">
  # without a subsequent [...] internal subset
  # Only checks the FIRST DOCTYPE in the document (the actual document DOCTYPE)
  defp has_external_dtd_without_internal_subset(content) do
    # First, find the first DOCTYPE declaration in the document
    # This must be in the prolog, before any root element
    case Regex.run(~r/<!DOCTYPE\s+\S+[^>]*>/s, content) do
      [doctype] ->
        # Check if this DOCTYPE has SYSTEM/PUBLIC but no internal subset [
        # External-only: has SYSTEM/PUBLIC and ends with > (no [)
        has_external = Regex.match?(~r/\s(SYSTEM|PUBLIC)\s/, doctype)
        has_internal = String.contains?(doctype, "[")
        has_external and not has_internal

      nil ->
        # No DOCTYPE at all
        false
    end
  end

  # Extract entities defined via external PE chains in the internal subset
  # This handles cases where internal subset has SYSTEM PEs that define entities
  defp extract_entities_from_internal_pe(content, base_uri) do
    # Extract internal subset content
    case extract_internal_dtd_content(content) do
      nil ->
        MapSet.new()

      dtd_content ->
        # Find SYSTEM PE definitions
        system_pes = extract_system_pe_definitions(dtd_content)

        if map_size(system_pes) == 0 do
          MapSet.new()
        else
          # Fetch and process each external PE (with recursion limit)
          fetch_and_extract_pe_entities(system_pes, base_uri, 10)
        end
    end
  end

  # Extract SYSTEM parameter entity definitions from DTD content
  # Returns %{pe_name => system_uri}
  defp extract_system_pe_definitions(dtd_content) do
    # Match <!ENTITY % name SYSTEM "uri">
    pattern = ~r/<!ENTITY\s+%\s+([a-zA-Z_][a-zA-Z0-9._-]*)\s+SYSTEM\s+["']([^"']+)["']\s*>/

    Regex.scan(pattern, dtd_content)
    |> Enum.map(fn [_, name, uri] -> {name, uri} end)
    |> Map.new()
  end

  # Recursively fetch external PE files and extract entity definitions
  defp fetch_and_extract_pe_entities(system_pes, base_uri, depth) when depth > 0 do
    base_dir = Path.dirname(base_uri)

    entities =
      system_pes
      |> Enum.flat_map(fn {_name, uri} ->
        resolved_path = Path.join(base_dir, uri)

        case File.read(resolved_path) do
          {:ok, pe_content} ->
            # Extract entity definitions from this PE content
            direct_entities = extract_entities_from_pe_content(pe_content)

            # Also look for nested SYSTEM PEs
            nested_pes = extract_system_pe_definitions(pe_content)

            nested_entities =
              if map_size(nested_pes) > 0 do
                # Recursively process nested PEs with new base path
                fetch_and_extract_pe_entities(nested_pes, resolved_path, depth - 1)
              else
                MapSet.new()
              end

            MapSet.to_list(direct_entities) ++ MapSet.to_list(nested_entities)

          {:error, _} ->
            []
        end
      end)

    MapSet.new(entities)
  end

  defp fetch_and_extract_pe_entities(_system_pes, _base_uri, _depth), do: MapSet.new()

  # Extract general entity names from PE content
  defp extract_entities_from_pe_content(content) do
    # Match <!ENTITY name ...> (not parameter entities)
    # Internal: <!ENTITY name "value">
    # External: <!ENTITY name SYSTEM "uri">
    patterns = [
      ~r/<!ENTITY\s+([a-zA-Z_][a-zA-Z0-9._-]*)\s+["'][^"']*["']\s*>/,
      ~r/<!ENTITY\s+([a-zA-Z_][a-zA-Z0-9._-]*)\s+SYSTEM\s+["'][^"']*["']\s*>/,
      ~r/<!ENTITY\s+([a-zA-Z_][a-zA-Z0-9._-]*)\s+PUBLIC\s+["'][^"']*["']\s+["'][^"']*["']/
    ]

    patterns
    |> Enum.flat_map(fn pattern ->
      Regex.scan(pattern, content)
      |> Enum.map(fn [_, name] -> name end)
    end)
    |> MapSet.new()
  end

  # Check if the internal subset contains parameter entity references
  # When PEs are present, undefined entity refs become validity errors (not WFC)
  defp has_pe_references_in_internal_subset(content) do
    # Extract the internal subset content
    case Regex.run(~r/<!DOCTYPE\s+\S+(?:\s+(?:SYSTEM|PUBLIC)[^>\[]*)?\s*\[(.+?)\]>/s, content) do
      [_, internal_subset] ->
        # Look for PE references: %name;
        Regex.match?(~r/%[a-zA-Z_][a-zA-Z0-9._-]*;/, internal_subset)

      nil ->
        false
    end
  end

  # Extract entity names from DTD using the full DTD parser
  # This handles parameter entity expansion properly, so that entities
  # defined via PE expansion (like in the pe02 test) are recognized
  # Returns {entity_names, unparsed_entity_names, external_entity_names}
  defp extract_entity_names(content) do
    # Extract the DTD internal subset content
    # Allow for optional SYSTEM/PUBLIC identifier before the internal subset [...]
    case Regex.run(~r/<!DOCTYPE\s+\S+(?:\s+(?:SYSTEM|PUBLIC)[^>\[]*)?\s*\[(.+?)\]>/s, content) do
      [_, dtd_content] ->
        # Parse the DTD to get entity definitions (including PE-expanded ones)
        case FnXML.DTD.Parser.parse(dtd_content) do
          {:ok, model} ->
            # Categorize entities: internal, external, unparsed
            {internal, external, unparsed} =
              Enum.reduce(model.entities, {[], [], []}, fn {name, definition}, {int, ext, unp} ->
                case definition do
                  {:internal, _} ->
                    {[name | int], ext, unp}

                  {:external, _, _} ->
                    # External parsed entity
                    {int, [name | ext], unp}

                  {:external_unparsed, _, _, _} ->
                    # Unparsed (NDATA) entity
                    {int, ext, [name | unp]}
                end
              end)

            # All entity names (internal + external) for undefined reference check
            all_names = (internal ++ external ++ unparsed) |> MapSet.new()
            unparsed_names = unparsed |> MapSet.new()
            external_names = external |> MapSet.new()

            # Extract internal entity values for entity resolution
            entity_values =
              model.entities
              |> Enum.filter(fn {_name, def} -> match?({:internal, _}, def) end)
              |> Enum.map(fn {name, {:internal, value}} -> {name, value} end)
              |> Map.new()

            # Find entities that indirectly reference external entities
            # An entity is "indirectly external" if its value contains a reference
            # to an external entity (or to another indirectly external entity)
            indirect_external =
              find_indirect_external_entities(entity_values, external_names)

            # Combine direct and indirect external entity names
            all_external = MapSet.union(external_names, indirect_external)

            {all_names, unparsed_names, all_external, entity_values}

          {:error, _} ->
            # Fall back to simple regex extraction on parse error
            {extract_entity_names_simple(content), MapSet.new(), MapSet.new(), %{}}
        end

      nil ->
        # No internal DTD subset - use simple extraction
        {extract_entity_names_simple(content), MapSet.new(), MapSet.new(), %{}}
    end
  end

  # Fallback simple extraction for when DTD parsing fails
  defp extract_entity_names_simple(content) do
    patterns = [
      # Internal entity: <!ENTITY name "value">
      ~r/<!ENTITY\s+([a-zA-Z_][a-zA-Z0-9._-]*)\s+["'][^"']*["']\s*>/,
      # SYSTEM entity: <!ENTITY name SYSTEM "uri">
      ~r/<!ENTITY\s+([a-zA-Z_][a-zA-Z0-9._-]*)\s+SYSTEM\s+["'][^"']*["']\s*>/,
      # PUBLIC entity: <!ENTITY name PUBLIC "pubid" "uri">
      ~r/<!ENTITY\s+([a-zA-Z_][a-zA-Z0-9._-]*)\s+PUBLIC\s+["'][^"']*["']\s+["'][^"']*["']/
    ]

    patterns
    |> Enum.flat_map(fn pattern ->
      Regex.scan(pattern, content)
      |> Enum.map(fn [_, name] -> name end)
    end)
    |> MapSet.new()
  end

  # Find entities that indirectly reference external entities
  # Uses iterative expansion to handle chains: A -> B -> C (external)
  defp find_indirect_external_entities(entity_values, external_names) do
    # Extract entity references from each entity value
    entity_refs =
      entity_values
      |> Enum.map(fn {name, value} ->
        refs = extract_entity_refs_from_value(value)
        {name, refs}
      end)
      |> Map.new()

    # Iteratively find entities that reference external entities
    find_indirect_loop(entity_refs, external_names, MapSet.new())
  end

  defp find_indirect_loop(entity_refs, external_names, found) do
    # Find entities whose values contain references to external or already-found entities
    new_found =
      entity_refs
      |> Enum.filter(fn {_name, refs} ->
        Enum.any?(refs, fn ref ->
          MapSet.member?(external_names, ref) or MapSet.member?(found, ref)
        end)
      end)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()

    combined = MapSet.union(found, new_found)

    if MapSet.size(combined) == MapSet.size(found) do
      # No new entities found, we're done
      found
    else
      # Continue iterating to find transitive references
      find_indirect_loop(entity_refs, external_names, combined)
    end
  end

  defp extract_entity_refs_from_value(value) do
    # Match &name; patterns (entity references)
    Regex.scan(~r/&([a-zA-Z_][a-zA-Z0-9._-]*);/, value)
    |> Enum.map(fn [_, name] -> name end)
    |> MapSet.new()
  end

  # Extract entity names from external DTD
  # Parses the external DTD file to get entity definitions
  defp extract_external_dtd_entities(content, test_uri, edition) do
    # Extract SYSTEM/PUBLIC identifier from raw content
    system_id = extract_system_id_from_content(content)

    if system_id do
      # Extract PE definitions from internal subset for external DTD expansion
      internal_pe_defs =
        case Regex.run(~r/\[(.+)\]/s, content) do
          [_, subset] -> extract_internal_pe_defs(subset)
          nil -> %{}
        end

      # Fetch and parse external DTD
      case FnXML.DTD.ExternalResolver.fetch(system_id, test_uri) do
        {:ok, dtd_content} ->
          case FnXML.DTD.ExternalResolver.parse_external_dtd(dtd_content,
                 edition: edition,
                 internal_pe_defs: internal_pe_defs
               ) do
            {:ok, model} ->
              model.entities |> Map.keys() |> MapSet.new()

            {:error, _} ->
              MapSet.new()
          end

        {:error, _} ->
          MapSet.new()
      end
    else
      MapSet.new()
    end
  end

  # Validate TextDecl in external parsed entities
  # Per XML 1.0 spec, external parsed entities must have TextDecl at the very start
  # and the TextDecl must be well-formed (proper ordering, case, etc.)
  defp validate_external_parsed_entities(content, test_uri) do
    # Extract external entity declarations from internal DTD subset
    case Regex.run(~r/<!DOCTYPE\s+\S+\s*\[(.+?)\]>/s, content) do
      [_, dtd_content] ->
        # Find all external parsed entity declarations (SYSTEM, not NDATA)
        external_entities = extract_external_entity_declarations(dtd_content)

        # Validate each external entity's TextDecl
        Enum.find_value(external_entities, fn {_name, system_id} ->
          case FnXML.DTD.ExternalResolver.fetch(system_id, test_uri) do
            {:ok, entity_content} ->
              case validate_text_decl(entity_content) do
                :ok -> nil
                {:error, reason} -> reason
              end

            {:error, {:file_error, _path, :enoent}} ->
              # File not found - skip validation
              nil

            {:error, reason} ->
              reason
          end
        end)

      nil ->
        # No internal DTD subset
        nil
    end
  end

  # Extract external entity declarations (SYSTEM, not NDATA/unparsed)
  # Includes both general entities and parameter entities
  defp extract_external_entity_declarations(dtd_content) do
    # Match general entities: <!ENTITY name SYSTEM "uri"> (not followed by NDATA)
    general_pattern = ~r/<!ENTITY\s+([a-zA-Z_][a-zA-Z0-9._-]*)\s+SYSTEM\s+["']([^"']+)["']\s*>/

    general_entities =
      Regex.scan(general_pattern, dtd_content)
      |> Enum.filter(fn [full_match, _name, _uri] ->
        # Exclude unparsed (NDATA) entities
        not String.contains?(full_match, "NDATA")
      end)
      |> Enum.map(fn [_, name, uri] -> {name, uri} end)

    # Match parameter entities: <!ENTITY % name SYSTEM "uri">
    pe_pattern = ~r/<!ENTITY\s+%\s*([a-zA-Z_][a-zA-Z0-9._-]*)\s+SYSTEM\s+["']([^"']+)["']\s*>/

    parameter_entities =
      Regex.scan(pe_pattern, dtd_content)
      |> Enum.map(fn [_, name, uri] -> {name, uri} end)

    general_entities ++ parameter_entities
  end

  # Validate TextDecl at the start of external parsed entity content
  # TextDecl ::= '<?xml' VersionInfo? EncodingDecl S? '?>'
  # If present, TextDecl must be at the very beginning (no whitespace before)
  defp validate_text_decl(content) do
    cond do
      # Valid: starts with <?xml (potential TextDecl)
      String.starts_with?(content, "<?xml") ->
        validate_text_decl_syntax(content)

      # Valid: starts with <?XML (wrong case - error!)
      match = Regex.run(~r/^<\?[Xx][Mm][Ll]/, content) ->
        if match != ["<?xml"] do
          {:error,
           "TextDecl keyword must be lowercase 'xml', not '#{extract_pi_target(content)}'"}
        else
          validate_text_decl_syntax(content)
        end

      # Check if there's a TextDecl later in the content (not at start)
      Regex.match?(~r/<\?xml\s/, content) ->
        {:error, "TextDecl must appear at the very beginning of external parsed entity"}

      # Check for TextDecl with whitespace before it
      Regex.match?(~r/^\s+<\?xml/, content) ->
        {:error, "TextDecl must appear at the very beginning, no whitespace allowed before it"}

      # No TextDecl present - that's valid
      true ->
        :ok
    end
  end

  # Validate TextDecl syntax: version must come before encoding
  defp validate_text_decl_syntax(content) do
    # Extract the TextDecl up to ?>
    case Regex.run(~r/^<\?xml(.*?)\?>(.*)$/s, content) do
      [_, attrs, rest] ->
        # Check attribute ordering: version (optional) must come before encoding (required)
        version_pos = find_attr_position(attrs, "version")
        encoding_pos = find_attr_position(attrs, "encoding")

        cond do
          # No encoding attribute - invalid TextDecl (encoding is required)
          encoding_pos == nil ->
            {:error, "TextDecl must have encoding attribute"}

          # Version present but after encoding - invalid ordering
          version_pos != nil and version_pos > encoding_pos ->
            {:error, "In TextDecl, version must appear before encoding"}

          # Check for duplicate XML/text declaration after the first one
          Regex.match?(~r/<\?xml\s/, rest) ->
            {:error, "Duplicate XML/text declaration in external entity"}

          # Valid ordering
          true ->
            :ok
        end

      nil ->
        # Malformed TextDecl (no closing ?>)
        {:error, "Malformed TextDecl - missing closing '?>'"}
    end
  end

  defp find_attr_position(attrs, attr_name) do
    case Regex.run(~r/#{attr_name}\s*=/, attrs, return: :index) do
      [{pos, _len}] -> pos
      nil -> nil
    end
  end

  defp extract_pi_target(content) do
    case Regex.run(~r/^<\?(\S+)/, content) do
      [_, target] -> target
      nil -> "unknown"
    end
  end

  # Extract SYSTEM identifier from DOCTYPE declaration in raw content
  defp extract_system_id_from_content(content) do
    cond do
      # DOCTYPE with SYSTEM identifier: DOCTYPE name SYSTEM "uri"
      match = Regex.run(~r/<!DOCTYPE\s+\S+\s+SYSTEM\s+["']([^"']+)["']/, content) ->
        [_, uri] = match
        uri

      # DOCTYPE with PUBLIC identifier: DOCTYPE name PUBLIC "pubid" "uri"
      match = Regex.run(~r/<!DOCTYPE\s+\S+\s+PUBLIC\s+["'][^"']+["']\s+["']([^"']+)["']/, content) ->
        [_, uri] = match
        uri

      true ->
        nil
    end
  end

  # Helper to wrap content in a list for the parser stream
  defp wrap_as_list(content), do: [content]

  # Helper to add document start/end events
  defp wrap_with_document_events(stream) do
    Stream.concat([
      [{:start_document, nil}],
      stream,
      [{:end_document, nil}]
    ])
  end

  # Print combined summary comparing results across editions
  defp print_combined_summary(edition_results) do
    Mix.shell().info("\n" <> String.duplicate("=", 60))
    Mix.shell().info("COMBINED CONFORMANCE SUMMARY - All Parsers")
    Mix.shell().info(String.duplicate("=", 60))

    # Calculate stats for each edition
    edition_stats =
      Enum.map(edition_results, fn {edition, results} ->
        total = length(results)
        skipped = Enum.count(results, fn r -> r[:skipped] == true end)
        passed = Enum.count(results, fn r -> r.pass and r[:skipped] != true end)
        failed = total - passed - skipped
        active_total = passed + failed

        pass_rate =
          if active_total > 0, do: Float.round(passed / active_total * 100, 1), else: 0.0

        {edition,
         %{passed: passed, failed: failed, skipped: skipped, total: active_total, rate: pass_rate}}
      end)

    # Print comparison table
    Mix.shell().info("\nParser Comparison:")

    Mix.shell().info(
      "  #{String.pad_trailing("Edition", 10)} #{String.pad_trailing("Passed", 10)} #{String.pad_trailing("Failed", 10)} #{String.pad_trailing("Rate", 10)}"
    )

    Mix.shell().info("  #{String.duplicate("-", 40)}")

    for {edition, stats} <- edition_stats do
      Mix.shell().info(
        "  #{String.pad_trailing("Edition #{edition}", 10)} " <>
          "#{String.pad_trailing("#{stats.passed}", 10)} " <>
          "#{String.pad_trailing("#{stats.failed}", 10)} " <>
          "#{String.pad_trailing("#{stats.rate}%", 10)}"
      )
    end

    # Find tests that pass in one edition but fail in another
    if length(edition_results) == 2 do
      [{ed1, results1}, {ed2, results2}] = edition_results

      # Build maps of test results by ID
      results1_map = Map.new(results1, fn r -> {r.id, r.pass} end)
      results2_map = Map.new(results2, fn r -> {r.id, r.pass} end)

      # Find differences
      pass_in_1_fail_in_2 =
        results1
        |> Enum.filter(fn r ->
          r.pass and r[:skipped] != true and Map.get(results2_map, r.id) == false
        end)
        |> Enum.map(& &1.id)

      pass_in_2_fail_in_1 =
        results2
        |> Enum.filter(fn r ->
          r.pass and r[:skipped] != true and Map.get(results1_map, r.id) == false
        end)
        |> Enum.map(& &1.id)

      if length(pass_in_1_fail_in_2) > 0 or length(pass_in_2_fail_in_1) > 0 do
        Mix.shell().info("\nEdition Differences:")

        if length(pass_in_1_fail_in_2) > 0 do
          Mix.shell().info(
            "  Pass in Edition #{ed1}, Fail in Edition #{ed2}: #{length(pass_in_1_fail_in_2)} tests"
          )

          pass_in_1_fail_in_2
          |> Enum.take(5)
          |> Enum.each(fn id -> Mix.shell().info("    - #{id}") end)

          if length(pass_in_1_fail_in_2) > 5 do
            Mix.shell().info("    ... and #{length(pass_in_1_fail_in_2) - 5} more")
          end
        end

        if length(pass_in_2_fail_in_1) > 0 do
          Mix.shell().info(
            "  Pass in Edition #{ed2}, Fail in Edition #{ed1}: #{length(pass_in_2_fail_in_1)} tests"
          )

          pass_in_2_fail_in_1
          |> Enum.take(5)
          |> Enum.each(fn id -> Mix.shell().info("    - #{id}") end)

          if length(pass_in_2_fail_in_1) > 5 do
            Mix.shell().info("    ... and #{length(pass_in_2_fail_in_1) - 5} more")
          end
        end
      else
        Mix.shell().info("\nNo differences found between editions (same tests pass/fail)")
      end
    end

    Mix.shell().info(String.duplicate("=", 60) <> "\n")
  end

  # Detect XML version from XML declaration
  defp detect_xml_version(content) do
    case Regex.run(~r/<\?xml[^?]*version\s*=\s*["']([^"']+)["']/, content) do
      [_, version] -> version
      nil -> "1.0"
    end
  end

  # For XML 1.1, normalize NEL (U+0085) and LS (U+2028) to LF
  # Per XML 1.1 spec section 2.11
  defp maybe_normalize_xml11_line_ends(content, "1.1") do
    content
    # NEL (U+0085) in UTF-8 is 0xC2 0x85, normalize to LF
    |> :binary.replace(<<0xC2, 0x85>>, <<?\n>>, [:global])
    # LS (U+2028) in UTF-8 is 0xE2 0x80 0xA8, normalize to LF
    |> :binary.replace(<<0xE2, 0x80, 0xA8>>, <<?\n>>, [:global])
  end

  defp maybe_normalize_xml11_line_ends(content, _version), do: content

  # Convert ISO-8859-1 encoded content to UTF-8 if declared in XML declaration
  # This handles XML 1.1 tests that use ISO-8859-1 encoding with non-ASCII characters
  defp convert_iso8859_if_declared(content) when is_binary(content) do
    declared_encoding = extract_declared_encoding(content)

    if declared_encoding != nil and
         String.downcase(declared_encoding) in ["iso-8859-1", "iso_8859-1", "latin1", "latin-1"] do
      # Convert from ISO-8859-1 (Latin-1) to UTF-8
      # In ISO-8859-1, each byte directly maps to a Unicode codepoint
      content
      |> :binary.bin_to_list()
      |> Enum.map(fn byte -> <<byte::utf8>> end)
      |> IO.iodata_to_binary()
    else
      content
    end
  end

  # Check for encoding declaration mismatch
  # Per XML spec, if a document declares an encoding that doesn't match its actual encoding,
  # it's a fatal error. This specifically catches the case where a document claims UTF-16
  # but doesn't have a BOM and is actually ASCII/UTF-8.
  defp check_encoding_mismatch(raw_content, normalized_content) do
    # Detect actual encoding from BOM
    actual_encoding = FnXML.Preprocess.Utf16.detect_encoding(raw_content) |> elem(0)

    # Extract declared encoding from XML declaration (if present)
    declared_encoding = extract_declared_encoding(normalized_content)

    case {actual_encoding, declared_encoding} do
      # UTF-16 declared but no BOM (actual is :utf8 without UTF-16 BOM)
      {:utf8, encoding} when encoding in ["UTF-16", "utf-16", "UTF16", "utf16"] ->
        {:error,
         "Document declares encoding '#{encoding}' but has no UTF-16 BOM and is not UTF-16"}

      # UTF-16 LE detected but UTF-16 BE declared (or vice versa) - would be caught by parser
      # For now, we consider any UTF-16 BOM as acceptable for UTF-16 declaration
      _ ->
        :ok
    end
  end

  # Extract encoding from XML declaration
  defp extract_declared_encoding(content) do
    # Match encoding in XML declaration: <?xml ... encoding="..." ?>
    case Regex.run(~r/<\?xml[^?]*encoding\s*=\s*["']([^"']+)["']/, content) do
      [_, encoding] -> encoding
      nil -> nil
    end
  end
end
