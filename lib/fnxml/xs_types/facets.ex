defmodule FnXML.XsTypes.Facets do
  @moduledoc """
  XSD facet validation.

  Facets are constraining rules that can be applied to XSD types to
  further restrict their value space.

  ## Supported Facets

  | Facet | Description | Applicable Types |
  |-------|-------------|------------------|
  | length | Exact length | string, binary, list types |
  | minLength | Minimum length | string, binary, list types |
  | maxLength | Maximum length | string, binary, list types |
  | pattern | Regex pattern | All types |
  | enumeration | Allowed values | All types |
  | minInclusive | Minimum value (≥) | Numeric, date/time types |
  | maxInclusive | Maximum value (≤) | Numeric, date/time types |
  | minExclusive | Minimum value (>) | Numeric, date/time types |
  | maxExclusive | Maximum value (<) | Numeric, date/time types |
  | totalDigits | Max total digits | Decimal types |
  | fractionDigits | Max fraction digits | Decimal types |
  | whiteSpace | Whitespace handling | String types |

  ## Examples

      iex> FnXML.XsTypes.Facets.validate("hello", :string, [{:minLength, 1}, {:maxLength, 10}])
      :ok

      iex> FnXML.XsTypes.Facets.validate("50", :integer, [{:minInclusive, "0"}, {:maxInclusive, "100"}])
      :ok
  """

  alias FnXML.XsTypes.Hierarchy

  @type facet ::
          {:length, non_neg_integer()}
          | {:minLength, non_neg_integer()}
          | {:maxLength, non_neg_integer()}
          | {:pattern, String.t()}
          | {:enumeration, [String.t()]}
          | {:minInclusive, String.t()}
          | {:maxInclusive, String.t()}
          | {:minExclusive, String.t()}
          | {:maxExclusive, String.t()}
          | {:totalDigits, pos_integer()}
          | {:fractionDigits, non_neg_integer()}
          | {:whiteSpace, :preserve | :replace | :collapse}

  @doc """
  Validate a value against a list of facets.

  ## Examples

      iex> FnXML.XsTypes.Facets.validate("hello", :string, [{:minLength, 1}])
      :ok

      iex> FnXML.XsTypes.Facets.validate("", :string, [{:minLength, 1}])
      {:error, {:facet_violation, :minLength, [expected: 1, got: 0]}}
  """
  @spec validate(String.t(), atom(), [facet()]) :: :ok | {:error, term()}
  def validate(_value, _type, []), do: :ok

  def validate(value, type, facets) do
    # Separate enumeration facets (OR logic) from other facets (AND logic)
    {enum_facets, other_facets} = Enum.split_with(facets, fn
      {:enumeration, _} -> true
      _ -> false
    end)

    # First validate enumeration (if any)
    enum_result = validate_enumerations(value, enum_facets)

    case enum_result do
      :ok ->
        # Then validate all other facets (all must pass)
        Enum.reduce_while(other_facets, :ok, fn facet, :ok ->
          case validate_facet(value, type, facet) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)
      error -> error
    end
  end

  defp validate_enumerations(_value, []), do: :ok

  defp validate_enumerations(value, enum_facets) do
    enum_values = Enum.flat_map(enum_facets, fn {:enumeration, vals} -> vals end)
    if value in enum_values do
      :ok
    else
      {:error, {:facet_violation, :enumeration, [expected: enum_values, got: value]}}
    end
  end

  # ============================================================================
  # Individual Facet Validation
  # ============================================================================

  defp validate_facet(value, type, {:length, expected}) do
    actual = get_length(value, type)
    if actual == expected do
      :ok
    else
      {:error, {:facet_violation, :length, [expected: expected, got: actual]}}
    end
  end

  defp validate_facet(value, type, {:minLength, min}) do
    actual = get_length(value, type)
    if actual >= min do
      :ok
    else
      {:error, {:facet_violation, :minLength, [expected: min, got: actual]}}
    end
  end

  defp validate_facet(value, type, {:maxLength, max}) do
    actual = get_length(value, type)
    if actual <= max do
      :ok
    else
      {:error, {:facet_violation, :maxLength, [expected: max, got: actual]}}
    end
  end

  defp validate_facet(value, _type, {:pattern, pattern}) do
    pcre_pattern = xsd_pattern_to_pcre(pattern)
    case Regex.compile("^#{pcre_pattern}$") do
      {:ok, regex} ->
        if Regex.match?(regex, value) do
          :ok
        else
          {:error, {:facet_violation, :pattern, [expected: pattern, got: value]}}
        end
      {:error, _} ->
        # If pattern conversion fails, skip validation
        :ok
    end
  end

  defp validate_facet(value, _type, {:minInclusive, min_str}) do
    case compare_values(value, min_str) do
      :lt -> {:error, {:facet_violation, :minInclusive, [expected: ">= #{min_str}", got: value]}}
      _ -> :ok
    end
  end

  defp validate_facet(value, _type, {:maxInclusive, max_str}) do
    case compare_values(value, max_str) do
      :gt -> {:error, {:facet_violation, :maxInclusive, [expected: "<= #{max_str}", got: value]}}
      _ -> :ok
    end
  end

  defp validate_facet(value, _type, {:minExclusive, min_str}) do
    case compare_values(value, min_str) do
      :gt -> :ok
      _ -> {:error, {:facet_violation, :minExclusive, [expected: "> #{min_str}", got: value]}}
    end
  end

  defp validate_facet(value, _type, {:maxExclusive, max_str}) do
    case compare_values(value, max_str) do
      :lt -> :ok
      _ -> {:error, {:facet_violation, :maxExclusive, [expected: "< #{max_str}", got: value]}}
    end
  end

  defp validate_facet(value, _type, {:totalDigits, max_digits}) do
    digit_count = count_total_digits(value)
    if digit_count <= max_digits do
      :ok
    else
      {:error, {:facet_violation, :totalDigits, [expected: max_digits, got: digit_count]}}
    end
  end

  defp validate_facet(value, _type, {:fractionDigits, max_fraction}) do
    fraction_count = count_fraction_digits(value)
    if fraction_count <= max_fraction do
      :ok
    else
      {:error, {:facet_violation, :fractionDigits, [expected: max_fraction, got: fraction_count]}}
    end
  end

  defp validate_facet(value, _type, {:whiteSpace, mode}) do
    case mode do
      :preserve -> :ok
      :replace ->
        if String.contains?(value, ["\t", "\n", "\r"]) do
          {:error, {:facet_violation, :whiteSpace, [expected: :replace, got: value]}}
        else
          :ok
        end
      :collapse ->
        cond do
          String.contains?(value, ["\t", "\n", "\r"]) ->
            {:error, {:facet_violation, :whiteSpace, [expected: :collapse, got: value]}}
          String.starts_with?(value, " ") or String.ends_with?(value, " ") ->
            {:error, {:facet_violation, :whiteSpace, [expected: :collapse, got: value]}}
          String.contains?(value, "  ") ->
            {:error, {:facet_violation, :whiteSpace, [expected: :collapse, got: value]}}
          true ->
            :ok
        end
    end
  end

  defp validate_facet(_value, _type, _facet), do: :ok

  # ============================================================================
  # Length Calculation
  # ============================================================================

  defp get_length(value, type) do
    cond do
      type == :hexBinary ->
        div(String.length(value), 2)
      type == :base64Binary ->
        get_base64_byte_length(value)
      Hierarchy.list_type?(type) ->
        value |> String.split(~r/\s+/, trim: true) |> length()
      true ->
        String.length(value)
    end
  end

  defp get_base64_byte_length(value) do
    clean = String.replace(value, ~r/\s/, "")
    len = String.length(clean)
    padding = cond do
      String.ends_with?(clean, "==") -> 2
      String.ends_with?(clean, "=") -> 1
      true -> 0
    end
    div(len * 3, 4) - padding
  end

  # ============================================================================
  # Digit Counting
  # ============================================================================

  defp count_total_digits(value) do
    value
    |> String.replace(~r/[^0-9]/, "")
    |> String.replace(~r/^0+/, "")
    |> String.length()
  end

  defp count_fraction_digits(value) do
    case String.split(value, ".") do
      [_] -> 0
      [_, fraction] -> String.length(String.replace(fraction, ~r/0+$/, ""))
    end
  end

  # ============================================================================
  # Value Comparison
  # ============================================================================

  defp compare_values(a, b) when is_binary(a) and is_binary(b) do
    cond do
      String.starts_with?(a, "P") or String.starts_with?(a, "-P") ->
        compare_duration(a, b)
      String.starts_with?(a, "--") ->
        compare_strings(a, b)
      is_datetime_format?(a) ->
        compare_datetime(a, b)
      true ->
        compare_numeric(a, b)
    end
  rescue
    _ -> :eq
  end

  defp compare_numeric(a, b) do
    if Code.ensure_loaded?(Decimal) do
      # Use apply to avoid compile-time warning when Decimal is not available
      case {apply(Decimal, :parse, [a]), apply(Decimal, :parse, [b])} do
        {{a_dec, ""}, {b_dec, ""}} -> apply(Decimal, :compare, [a_dec, b_dec])
        {{a_dec, _}, {b_dec, _}} -> apply(Decimal, :compare, [a_dec, b_dec])
        _ -> compare_float(a, b)
      end
    else
      compare_float(a, b)
    end
  end

  defp compare_float(a, b) do
    case {Float.parse(a), Float.parse(b)} do
      {{a_num, _}, {b_num, _}} ->
        cond do
          a_num < b_num -> :lt
          a_num > b_num -> :gt
          true -> :eq
        end
      _ -> :eq
    end
  end

  defp compare_duration(a, b) do
    a_seconds = duration_to_seconds(a)
    b_seconds = duration_to_seconds(b)
    cond do
      a_seconds < b_seconds -> :lt
      a_seconds > b_seconds -> :gt
      true -> :eq
    end
  rescue
    _ -> :eq
  end

  defp duration_to_seconds(duration) do
    negative = String.starts_with?(duration, "-")
    duration = duration |> String.trim_leading("-") |> String.trim_leading("P")

    {date_part, time_part} = case String.split(duration, "T", parts: 2) do
      [date, time] -> {date, time}
      [date] -> {date, ""}
    end

    years = parse_duration_component(date_part, "Y")
    months = parse_duration_component(date_part, "M")
    days = parse_duration_component(date_part, "D")
    hours = parse_duration_component(time_part, "H")
    minutes = parse_duration_component(time_part, "M")
    seconds = parse_duration_component_decimal(time_part, "S")

    total = years * 365.25 * 24 * 60 * 60 +
            months * 30.4375 * 24 * 60 * 60 +
            days * 24 * 60 * 60 +
            hours * 60 * 60 +
            minutes * 60 +
            seconds

    if negative, do: -total, else: total
  end

  defp parse_duration_component(str, suffix) do
    case Regex.run(~r/(\d+)#{suffix}/, str) do
      [_, num] -> String.to_integer(num)
      _ -> 0
    end
  end

  defp parse_duration_component_decimal(str, suffix) do
    case Regex.run(~r/([\d.]+)#{suffix}/, str) do
      [_, num] ->
        case Float.parse(num) do
          {val, _} -> val
          :error -> 0.0
        end
      _ -> 0.0
    end
  end

  defp compare_datetime(a, b) do
    a_norm = normalize_datetime(a)
    b_norm = normalize_datetime(b)
    compare_strings(a_norm, b_norm)
  end

  defp compare_strings(a, b) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> :eq
    end
  end

  defp is_datetime_format?(s) do
    String.contains?(s, "T") or
    Regex.match?(~r/^-?\d{4,}-\d{2}-\d{2}/, s) or
    Regex.match?(~r/^\d{2}:\d{2}:\d{2}/, s) or
    Regex.match?(~r/^-?\d{4}-\d{2}(Z|[+-]\d{2}:\d{2})?$/, s) or
    Regex.match?(~r/^-?\d{4}(Z|[+-]\d{2}:\d{2})$/, s)
  end

  defp normalize_datetime(dt) do
    dt
    |> String.replace(~r/Z$/, "")
    |> String.replace(~r/[+-]\d{2}:\d{2}$/, "")
  end

  # ============================================================================
  # XSD Pattern Conversion
  # ============================================================================

  defp xsd_pattern_to_pcre(pattern) do
    pattern
    |> String.replace("\\i", "[_:A-Za-z\\xC0-\\xD6\\xD8-\\xF6\\xF8-\\xFF]")
    |> String.replace("\\I", "[^_:A-Za-z\\xC0-\\xD6\\xD8-\\xF6\\xF8-\\xFF]")
    |> String.replace("\\c", "[-._:A-Za-z0-9\\xB7\\xC0-\\xD6\\xD8-\\xF6\\xF8-\\xFF]")
    |> String.replace("\\C", "[^-._:A-Za-z0-9\\xB7\\xC0-\\xD6\\xD8-\\xF6\\xF8-\\xFF]")
  end
end
