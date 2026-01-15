defmodule FnXML.XsTypes.Derived do
  @moduledoc """
  XSD derived type validation, parsing, and encoding.

  This module handles the 25 derived XSD types defined in XML Schema Part 2.

  ## String-Derived Types

  | Type | Base | Constraints |
  |------|------|-------------|
  | normalizedString | string | No CR/LF/Tab |
  | token | normalizedString | No leading/trailing/consecutive spaces |
  | language | token | RFC 3066 language tag |
  | NMTOKEN | token | XML name token |
  | NMTOKENS | list of NMTOKEN | Space-separated |
  | Name | token | XML name |
  | NCName | Name | No colons |
  | ID | NCName | Unique identifier |
  | IDREF | NCName | Reference to ID |
  | IDREFS | list of IDREF | Space-separated |
  | ENTITY | NCName | Entity reference |
  | ENTITIES | list of ENTITY | Space-separated |

  ## Integer-Derived Types

  | Type | Base | Range |
  |------|------|-------|
  | integer | decimal | No fractional part |
  | nonPositiveInteger | integer | ≤ 0 |
  | negativeInteger | nonPositiveInteger | < 0 |
  | long | integer | -2^63 to 2^63-1 |
  | int | long | -2^31 to 2^31-1 |
  | short | int | -32768 to 32767 |
  | byte | short | -128 to 127 |
  | nonNegativeInteger | integer | ≥ 0 |
  | unsignedLong | nonNegativeInteger | 0 to 2^64-1 |
  | unsignedInt | unsignedLong | 0 to 2^32-1 |
  | unsignedShort | unsignedInt | 0 to 65535 |
  | unsignedByte | unsignedShort | 0 to 255 |
  | positiveInteger | nonNegativeInteger | > 0 |
  """

  # Integer type ranges
  @ranges %{
    byte: {-128, 127},
    short: {-32768, 32767},
    int: {-2_147_483_648, 2_147_483_647},
    long: {-9_223_372_036_854_775_808, 9_223_372_036_854_775_807},
    unsignedByte: {0, 255},
    unsignedShort: {0, 65535},
    unsignedInt: {0, 4_294_967_295},
    unsignedLong: {0, 18_446_744_073_709_551_615}
  }

  # ============================================================================
  # Validation
  # ============================================================================

  @doc """
  Validate a string value against a derived type.
  """
  @spec validate(String.t(), atom()) :: :ok | {:error, term()}

  # String-derived types
  def validate(value, :normalizedString), do: validate_normalized_string(value)
  def validate(value, :token), do: validate_token(value)
  def validate(value, :language), do: validate_pattern(value, ~r/^[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*$/, :language)
  def validate(value, :NMTOKEN), do: validate_nmtoken(value)
  def validate(value, :NMTOKENS), do: validate_nmtokens(value)
  def validate(value, :Name), do: validate_name(value)
  def validate(value, :NCName), do: validate_ncname(value)
  def validate(value, :ID), do: validate_ncname(value)
  def validate(value, :IDREF), do: validate_ncname(value)
  def validate(value, :IDREFS), do: validate_ncnames(value)
  def validate(value, :ENTITY), do: validate_ncname(value)
  def validate(value, :ENTITIES), do: validate_ncnames(value)

  # Duration-derived types (XSD 1.1 / XPath 2.0+)
  def validate(value, :yearMonthDuration), do: validate_year_month_duration(value)
  def validate(value, :dayTimeDuration), do: validate_day_time_duration(value)

  # Integer-derived types
  def validate(value, :integer), do: validate_integer(value)
  def validate(value, :nonPositiveInteger), do: validate_integer_range(value, nil, 0)
  def validate(value, :negativeInteger), do: validate_integer_range(value, nil, -1)
  def validate(value, :nonNegativeInteger), do: validate_integer_range(value, 0, nil)
  def validate(value, :positiveInteger), do: validate_integer_range(value, 1, nil)
  def validate(value, :long), do: validate_bounded_integer(value, :long)
  def validate(value, :int), do: validate_bounded_integer(value, :int)
  def validate(value, :short), do: validate_bounded_integer(value, :short)
  def validate(value, :byte), do: validate_bounded_integer(value, :byte)
  def validate(value, :unsignedLong), do: validate_bounded_integer(value, :unsignedLong)
  def validate(value, :unsignedInt), do: validate_bounded_integer(value, :unsignedInt)
  def validate(value, :unsignedShort), do: validate_bounded_integer(value, :unsignedShort)
  def validate(value, :unsignedByte), do: validate_bounded_integer(value, :unsignedByte)

  defp validate_normalized_string(value) do
    if String.contains?(value, ["\t", "\n", "\r"]) do
      {:error, {:invalid_value, :normalizedString, value}}
    else
      :ok
    end
  end

  defp validate_token(value) do
    cond do
      String.contains?(value, ["\t", "\n", "\r"]) ->
        {:error, {:invalid_value, :token, value}}
      String.starts_with?(value, " ") or String.ends_with?(value, " ") ->
        {:error, {:invalid_value, :token, value}}
      String.contains?(value, "  ") ->
        {:error, {:invalid_value, :token, value}}
      true ->
        :ok
    end
  end

  defp validate_nmtoken(value) do
    pattern = ~r/^[_\p{L}0-9.\-:]+$/u
    validate_pattern(value, pattern, :NMTOKEN)
  end

  defp validate_nmtokens(value) do
    value
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reduce_while(:ok, fn token, :ok ->
      case validate_nmtoken(token) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_name(value) do
    pattern = ~r/^[:_\p{L}][:_\p{L}0-9.\-]*$/u
    validate_pattern(value, pattern, :Name)
  end

  defp validate_ncname(value) do
    pattern = ~r/^[_\p{L}][_\p{L}0-9.\-]*$/u
    validate_pattern(value, pattern, :NCName)
  end

  defp validate_ncnames(value) do
    value
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reduce_while(:ok, fn name, :ok ->
      case validate_ncname(name) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_integer(value) do
    trimmed = String.trim(value)
    case Integer.parse(trimmed) do
      {_int, ""} -> :ok
      _ -> {:error, {:invalid_value, :integer, value}}
    end
  end

  defp validate_integer_range(value, min, max) do
    trimmed = String.trim(value)
    case Integer.parse(trimmed) do
      {int, ""} ->
        cond do
          min != nil and int < min -> {:error, {:out_of_range, :integer, int}}
          max != nil and int > max -> {:error, {:out_of_range, :integer, int}}
          true -> :ok
        end
      _ ->
        {:error, {:invalid_value, :integer, value}}
    end
  end

  defp validate_bounded_integer(value, type) do
    trimmed = String.trim(value)
    {min, max} = Map.fetch!(@ranges, type)
    case Integer.parse(trimmed) do
      {int, ""} when int >= min and int <= max -> :ok
      {int, ""} -> {:error, {:out_of_range, type, int}}
      _ -> {:error, {:invalid_value, type, value}}
    end
  end

  defp validate_pattern(value, pattern, type) do
    if Regex.match?(pattern, value) do
      :ok
    else
      {:error, {:invalid_value, type, value}}
    end
  end

  defp validate_year_month_duration(value) do
    # xs:yearMonthDuration allows only year and month components: -?P(\d+Y)?(\d+M)?
    # Must have at least one component and cannot have day/time parts
    pattern = ~r/^-?P(\d+Y)?(\d+M)?$/
    cond do
      not Regex.match?(pattern, value) ->
        {:error, {:invalid_value, :yearMonthDuration, value}}
      value in ["P", "-P"] ->
        {:error, {:invalid_value, :yearMonthDuration, value}}
      true ->
        :ok
    end
  end

  defp validate_day_time_duration(value) do
    # xs:dayTimeDuration allows only day and time components: -?P(\d+D)?(T(\d+H)?(\d+M)?(\d+(\.\d+)?S)?)?
    # Must have at least one component and cannot have year/month parts
    pattern = ~r/^-?P(\d+D)?(T(\d+H)?(\d+M)?(\d+(\.\d+)?S)?)?$/
    cond do
      not Regex.match?(pattern, value) ->
        {:error, {:invalid_value, :dayTimeDuration, value}}
      value in ["P", "-P", "PT", "-PT"] ->
        {:error, {:invalid_value, :dayTimeDuration, value}}
      true ->
        :ok
    end
  end

  # ============================================================================
  # Parsing
  # ============================================================================

  @doc """
  Parse a string value to its Elixir representation.
  """
  @spec parse(String.t(), atom()) :: {:ok, term()} | {:error, term()}

  # String-derived types - return as string (already normalized by caller)
  def parse(value, type) when type in [:normalizedString, :token, :language, :NMTOKEN,
                                       :Name, :NCName, :ID, :IDREF, :ENTITY] do
    {:ok, value}
  end

  # List types - return as list of strings
  def parse(value, :NMTOKENS), do: {:ok, String.split(value, ~r/\s+/, trim: true)}
  def parse(value, :IDREFS), do: {:ok, String.split(value, ~r/\s+/, trim: true)}
  def parse(value, :ENTITIES), do: {:ok, String.split(value, ~r/\s+/, trim: true)}

  # Duration-derived types - return as map
  def parse(value, :yearMonthDuration), do: parse_year_month_duration(value)
  def parse(value, :dayTimeDuration), do: parse_day_time_duration(value)

  # Integer types - return as integer
  def parse(value, type) when type in [:integer, :nonPositiveInteger, :negativeInteger,
                                       :nonNegativeInteger, :positiveInteger,
                                       :long, :int, :short, :byte,
                                       :unsignedLong, :unsignedInt, :unsignedShort, :unsignedByte] do
    parse_integer(value, type)
  end

  defp parse_integer(value, type) do
    trimmed = String.trim(value)
    case Integer.parse(trimmed) do
      {int, ""} -> {:ok, int}
      _ -> {:error, {:invalid_value, type, value}}
    end
  end

  defp parse_year_month_duration(value) do
    negative = String.starts_with?(value, "-")
    cleaned = value |> String.trim_leading("-") |> String.trim_leading("P")

    duration = %{
      years: parse_duration_component(cleaned, "Y"),
      months: parse_duration_component(cleaned, "M")
    }
    |> maybe_add_negative(negative)
    |> Enum.reject(fn {k, v} -> v == 0 or (k == :negative and v == false) end)
    |> Map.new()

    {:ok, duration}
  end

  defp parse_day_time_duration(value) do
    negative = String.starts_with?(value, "-")
    cleaned = value |> String.trim_leading("-") |> String.trim_leading("P")

    {_date_part, time_part} = case String.split(cleaned, "T", parts: 2) do
      [date, time] -> {date, time}
      [date] -> {date, ""}
    end

    duration = %{
      days: parse_duration_component(cleaned, "D"),
      hours: parse_duration_component(time_part, "H"),
      minutes: parse_duration_component(time_part, "M"),
      seconds: parse_duration_component_decimal(time_part, "S")
    }
    |> maybe_add_negative(negative)
    |> Enum.reject(fn {k, v} -> v == 0 or v == 0.0 or (k == :negative and v == false) end)
    |> Map.new()

    {:ok, duration}
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

  defp maybe_add_negative(map, true), do: Map.put(map, :negative, true)
  defp maybe_add_negative(map, false), do: map

  # ============================================================================
  # Encoding
  # ============================================================================

  @doc """
  Encode an Elixir value to its XSD string representation.
  """
  @spec encode(term(), atom()) :: {:ok, String.t()} | {:error, term()}

  # String-derived types
  def encode(value, type) when type in [:normalizedString, :token, :language, :NMTOKEN,
                                        :Name, :NCName, :ID, :IDREF, :ENTITY] and is_binary(value) do
    {:ok, value}
  end

  # List types
  def encode(values, :NMTOKENS) when is_list(values), do: {:ok, Enum.join(values, " ")}
  def encode(values, :IDREFS) when is_list(values), do: {:ok, Enum.join(values, " ")}
  def encode(values, :ENTITIES) when is_list(values), do: {:ok, Enum.join(values, " ")}

  # Duration-derived types
  def encode(value, :yearMonthDuration) when is_map(value), do: encode_year_month_duration(value)
  def encode(value, :yearMonthDuration) when is_binary(value), do: {:ok, value}
  def encode(value, :dayTimeDuration) when is_map(value), do: encode_day_time_duration(value)
  def encode(value, :dayTimeDuration) when is_binary(value), do: {:ok, value}

  # Integer types
  def encode(value, type) when is_integer(value) and type in [:integer, :nonPositiveInteger,
                                                              :negativeInteger, :nonNegativeInteger,
                                                              :positiveInteger, :long, :int, :short,
                                                              :byte, :unsignedLong, :unsignedInt,
                                                              :unsignedShort, :unsignedByte] do
    {:ok, Integer.to_string(value)}
  end

  def encode(value, type), do: {:error, {:encode_error, type, value}}

  defp encode_year_month_duration(map) do
    negative = if Map.get(map, :negative, false), do: "-", else: ""
    years = encode_duration_part(map, :years, "Y")
    months = encode_duration_part(map, :months, "M")
    {:ok, negative <> "P" <> years <> months}
  end

  defp encode_day_time_duration(map) do
    negative = if Map.get(map, :negative, false), do: "-", else: ""
    days = encode_duration_part(map, :days, "D")
    hours = encode_duration_part(map, :hours, "H")
    minutes = encode_duration_part(map, :minutes, "M")
    seconds = encode_duration_part(map, :seconds, "S")

    time_part = hours <> minutes <> seconds
    time_str = if time_part != "", do: "T" <> time_part, else: ""

    {:ok, negative <> "P" <> days <> time_str}
  end

  defp encode_duration_part(map, key, suffix) do
    case Map.get(map, key) do
      nil -> ""
      0 -> ""
      val when val == 0.0 -> ""
      val when is_float(val) -> "#{val}#{suffix}"
      val -> "#{val}#{suffix}"
    end
  end
end
