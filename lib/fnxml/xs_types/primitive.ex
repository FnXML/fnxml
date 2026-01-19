defmodule FnXML.XsTypes.Primitive do
  @moduledoc """
  XSD primitive type validation, parsing, and encoding.

  This module handles the 19 primitive XSD types defined in XML Schema Part 2.

  ## Primitive Types

  | Type | Elixir Type | Notes |
  |------|-------------|-------|
  | string | String.t() | Unicode string |
  | boolean | boolean() | true/false/1/0 |
  | decimal | Decimal.t() or float() | Arbitrary precision |
  | float | float() or :nan/:infinity/:neg_infinity | 32-bit IEEE 754 |
  | double | float() or :nan/:infinity/:neg_infinity | 64-bit IEEE 754 |
  | duration | map() | ISO 8601 duration |
  | dateTime | DateTime.t() or NaiveDateTime.t() | ISO 8601 |
  | time | Time.t() | ISO 8601 |
  | date | Date.t() | ISO 8601 |
  | gYearMonth | String.t() | YYYY-MM |
  | gYear | String.t() | YYYY |
  | gMonthDay | String.t() | --MM-DD |
  | gDay | String.t() | ---DD |
  | gMonth | String.t() | --MM |
  | hexBinary | binary() | Decoded hex bytes |
  | base64Binary | binary() | Decoded base64 bytes |
  | anyURI | String.t() | URI reference |
  | QName | {prefix, local} | Qualified name tuple |
  | NOTATION | String.t() | Notation reference |
  """

  # ============================================================================
  # Validation
  # ============================================================================

  @doc """
  Validate a string value against a primitive type.
  """
  @spec validate(String.t(), atom()) :: :ok | {:error, term()}
  def validate(value, :string), do: {:ok, value} |> to_validation_result()
  def validate(value, :boolean), do: validate_boolean(value)
  def validate(value, :decimal), do: validate_decimal(value)
  def validate(value, :float), do: validate_float(value)
  def validate(value, :double), do: validate_float(value)
  def validate(value, :duration), do: validate_duration(value)
  def validate(value, :dateTime), do: validate_datetime(value)
  def validate(value, :time), do: validate_time(value)
  def validate(value, :date), do: validate_date(value)

  def validate(value, :gYearMonth),
    do: validate_pattern(value, ~r/^-?\d{4,}-\d{2}(Z|[+-]\d{2}:\d{2})?$/, :gYearMonth)

  def validate(value, :gYear),
    do: validate_pattern(value, ~r/^-?\d{4,}(Z|[+-]\d{2}:\d{2})?$/, :gYear)

  def validate(value, :gMonthDay),
    do: validate_pattern(value, ~r/^--\d{2}-\d{2}(Z|[+-]\d{2}:\d{2})?$/, :gMonthDay)

  def validate(value, :gDay),
    do: validate_pattern(value, ~r/^---\d{2}(Z|[+-]\d{2}:\d{2})?$/, :gDay)

  def validate(value, :gMonth),
    do: validate_pattern(value, ~r/^--\d{2}(Z|[+-]\d{2}:\d{2})?$/, :gMonth)

  def validate(value, :hexBinary),
    do: validate_pattern(value, ~r/^([0-9a-fA-F]{2})*$/, :hexBinary)

  def validate(value, :base64Binary), do: validate_base64(value)
  def validate(value, :anyURI), do: validate_uri(value)
  def validate(value, :QName), do: validate_qname(value)
  def validate(_value, :NOTATION), do: :ok

  defp validate_boolean(value) do
    trimmed = String.trim(value)

    if trimmed in ["true", "false", "1", "0"] do
      :ok
    else
      {:error, {:invalid_value, :boolean, value}}
    end
  end

  defp validate_decimal(value) do
    trimmed = String.trim(value)

    if Code.ensure_loaded?(Decimal) do
      # Use apply to avoid compile-time warning when Decimal is not available
      case apply(Decimal, :parse, [trimmed]) do
        {_decimal, ""} -> :ok
        _ -> {:error, {:invalid_value, :decimal, value}}
      end
    else
      case Float.parse(trimmed) do
        {_float, ""} -> :ok
        _ -> {:error, {:invalid_value, :decimal, value}}
      end
    end
  rescue
    _ -> {:error, {:invalid_value, :decimal, value}}
  end

  defp validate_float(value) do
    trimmed = String.trim(value)

    cond do
      trimmed in ["INF", "-INF", "+INF", "NaN"] ->
        :ok

      true ->
        normalized = normalize_float_string(trimmed)

        case Float.parse(normalized) do
          {_float, ""} ->
            :ok

          :error ->
            if valid_float_syntax?(normalized),
              do: :ok,
              else: {:error, {:invalid_value, :float, value}}

          _ ->
            {:error, {:invalid_value, :float, value}}
        end
    end
  end

  defp validate_duration(value) do
    pattern = ~r/^-?P(\d+Y)?(\d+M)?(\d+D)?(T(\d+H)?(\d+M)?(\d+(\.\d+)?S)?)?$/

    if Regex.match?(pattern, value) do
      if value in ["P", "-P", "PT", "-PT"] do
        {:error, {:invalid_value, :duration, value}}
      else
        :ok
      end
    else
      {:error, {:invalid_value, :duration, value}}
    end
  end

  defp validate_datetime(value) do
    pattern = ~r/^-?\d{4,}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})?$/
    validate_pattern(value, pattern, :dateTime)
  end

  defp validate_time(value) do
    pattern = ~r/^\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})?$/
    validate_pattern(value, pattern, :time)
  end

  defp validate_date(value) do
    pattern = ~r/^-?\d{4,}-\d{2}-\d{2}(Z|[+-]\d{2}:\d{2})?$/
    validate_pattern(value, pattern, :date)
  end

  defp validate_base64(value) do
    normalized = String.replace(value, ~r/\s/, "")

    case Base.decode64(normalized) do
      {:ok, _} -> :ok
      :error -> {:error, {:invalid_value, :base64Binary, value}}
    end
  end

  defp validate_uri(_value), do: :ok

  defp validate_qname(value) do
    case String.split(value, ":", parts: 2) do
      [local] ->
        validate_ncname_format(local, :QName)

      [prefix, local] ->
        with :ok <- validate_ncname_format(prefix, :QName),
             :ok <- validate_ncname_format(local, :QName) do
          :ok
        end
    end
  end

  defp validate_ncname_format(value, type) do
    pattern = ~r/^[_\p{L}][_\p{L}0-9.\-]*$/u

    if Regex.match?(pattern, value) do
      :ok
    else
      {:error, {:invalid_value, type, value}}
    end
  end

  defp validate_pattern(value, pattern, type) do
    if Regex.match?(pattern, value) do
      :ok
    else
      {:error, {:invalid_value, type, value}}
    end
  end

  defp normalize_float_string(value) do
    value
    |> String.replace(~r/^\./, "0.")
    |> String.replace(~r/^-\./, "-0.")
    |> String.replace(~r/^\+\./, "+0.")
  end

  defp valid_float_syntax?(value) do
    Regex.match?(~r/^[+-]?(\d+\.?\d*|\d*\.?\d+)([eE][+-]?\d+)?$/, value)
  end

  defp to_validation_result({:ok, _}), do: :ok

  # ============================================================================
  # Parsing
  # ============================================================================

  @doc """
  Parse a string value to its Elixir representation.
  """
  @spec parse(String.t(), atom()) :: {:ok, term()} | {:error, term()}
  def parse(value, :string), do: {:ok, value}
  def parse(value, :boolean), do: parse_boolean(String.trim(value))
  def parse(value, :decimal), do: parse_decimal(String.trim(value))
  def parse(value, :float), do: parse_float(String.trim(value))
  def parse(value, :double), do: parse_float(String.trim(value))
  def parse(value, :duration), do: parse_duration(value)
  def parse(value, :dateTime), do: parse_datetime(String.trim(value))
  def parse(value, :time), do: parse_time(String.trim(value))
  def parse(value, :date), do: parse_date(String.trim(value))
  def parse(value, :gYearMonth), do: {:ok, value}
  def parse(value, :gYear), do: {:ok, value}
  def parse(value, :gMonthDay), do: {:ok, value}
  def parse(value, :gDay), do: {:ok, value}
  def parse(value, :gMonth), do: {:ok, value}
  def parse(value, :hexBinary), do: parse_hex_binary(value)
  def parse(value, :base64Binary), do: parse_base64_binary(value)
  def parse(value, :anyURI), do: {:ok, value}
  def parse(value, :QName), do: parse_qname(value)
  def parse(value, :NOTATION), do: {:ok, value}

  defp parse_boolean("true"), do: {:ok, true}
  defp parse_boolean("1"), do: {:ok, true}
  defp parse_boolean("false"), do: {:ok, false}
  defp parse_boolean("0"), do: {:ok, false}
  defp parse_boolean(value), do: {:error, {:invalid_value, :boolean, value}}

  defp parse_decimal(value) do
    if Code.ensure_loaded?(Decimal) do
      try do
        # Use apply to avoid compile-time warning when Decimal is not available
        {:ok, apply(Decimal, :new, [value])}
      rescue
        _ -> {:error, {:invalid_value, :decimal, value}}
      end
    else
      case Float.parse(value) do
        {float, ""} -> {:ok, float}
        _ -> {:error, {:invalid_value, :decimal, value}}
      end
    end
  end

  defp parse_float("INF"), do: {:ok, :infinity}
  defp parse_float("+INF"), do: {:ok, :infinity}
  defp parse_float("-INF"), do: {:ok, :neg_infinity}
  defp parse_float("NaN"), do: {:ok, :nan}

  defp parse_float(value) do
    normalized = normalize_float_string(value)

    case Float.parse(normalized) do
      {float, ""} -> {:ok, float}
      _ -> {:error, {:invalid_value, :float, value}}
    end
  end

  defp parse_duration(value) do
    negative = String.starts_with?(value, "-")
    cleaned = value |> String.trim_leading("-") |> String.trim_leading("P")

    {date_part, time_part} =
      case String.split(cleaned, "T", parts: 2) do
        [date, time] -> {date, time}
        [date] -> {date, ""}
      end

    duration =
      %{
        negative: negative,
        years: parse_duration_component(date_part, "Y"),
        months: parse_duration_component(date_part, "M"),
        days: parse_duration_component(date_part, "D"),
        hours: parse_duration_component(time_part, "H"),
        minutes: parse_duration_component(time_part, "M"),
        seconds: parse_duration_component_decimal(time_part, "S")
      }
      |> Enum.reject(fn {k, v} -> v == 0 or (k == :negative and v == false) end)
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

      _ ->
        0.0
    end
  end

  defp parse_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} ->
        {:ok, dt}

      {:error, _} ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, ndt} -> {:ok, ndt}
          {:error, _} -> {:error, {:invalid_value, :dateTime, value}}
        end
    end
  end

  defp parse_time(value) do
    case Time.from_iso8601(value) do
      {:ok, time} -> {:ok, time}
      {:error, _} -> {:error, {:invalid_value, :time, value}}
    end
  end

  defp parse_date(value) do
    # Strip timezone for Date parsing
    date_only = Regex.replace(~r/(Z|[+-]\d{2}:\d{2})$/, value, "")

    case Date.from_iso8601(date_only) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, {:invalid_value, :date, value}}
    end
  end

  defp parse_hex_binary(value) do
    case Base.decode16(value, case: :mixed) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, {:invalid_value, :hexBinary, value}}
    end
  end

  defp parse_base64_binary(value) do
    normalized = String.replace(value, ~r/\s/, "")

    case Base.decode64(normalized) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, {:invalid_value, :base64Binary, value}}
    end
  end

  defp parse_qname(value) do
    case String.split(value, ":", parts: 2) do
      [prefix, local] -> {:ok, {prefix, local}}
      [local] -> {:ok, {nil, local}}
    end
  end

  # ============================================================================
  # Parse to Map (for XPath compatibility)
  # ============================================================================

  @doc """
  Parse Gregorian types to map representation (used by XPath).

  XPath represents Gregorian types as maps with explicit components rather
  than as formatted strings.

  ## Examples

      iex> FnXML.XsTypes.Primitive.parse_to_map("2024-03", :gYearMonth)
      {:ok, %{year: 2024, month: 3}}

      iex> FnXML.XsTypes.Primitive.parse_to_map("--12-25", :gMonthDay)
      {:ok, %{month: 12, day: 25}}

      iex> FnXML.XsTypes.Primitive.parse_to_map("---15", :gDay)
      {:ok, %{day: 15}}
  """
  @spec parse_to_map(String.t(), atom()) :: {:ok, map()} | {:error, term()}
  def parse_to_map(value, :gYearMonth) do
    case Regex.run(~r/^(-?\d{4,})-(\d{2})/, value) do
      [_, year, month] ->
        {:ok, %{year: String.to_integer(year), month: String.to_integer(month)}}

      _ ->
        {:error, {:invalid_value, :gYearMonth, value}}
    end
  end

  def parse_to_map(value, :gYear) do
    case Regex.run(~r/^(-?\d{4,})/, value) do
      [_, year] ->
        {:ok, %{year: String.to_integer(year)}}

      _ ->
        {:error, {:invalid_value, :gYear, value}}
    end
  end

  def parse_to_map(value, :gMonthDay) do
    case Regex.run(~r/^--(\d{2})-(\d{2})/, value) do
      [_, month, day] ->
        {:ok, %{month: String.to_integer(month), day: String.to_integer(day)}}

      _ ->
        {:error, {:invalid_value, :gMonthDay, value}}
    end
  end

  def parse_to_map(value, :gDay) do
    case Regex.run(~r/^---(\d{2})/, value) do
      [_, day] ->
        {:ok, %{day: String.to_integer(day)}}

      _ ->
        {:error, {:invalid_value, :gDay, value}}
    end
  end

  def parse_to_map(value, :gMonth) do
    case Regex.run(~r/^--(\d{2})/, value) do
      [_, month] ->
        {:ok, %{month: String.to_integer(month)}}

      _ ->
        {:error, {:invalid_value, :gMonth, value}}
    end
  end

  def parse_to_map(value, type) do
    # Fall back to regular parse for non-Gregorian types
    parse(value, type)
  end

  # ============================================================================
  # Encoding
  # ============================================================================

  @doc """
  Encode an Elixir value to its XSD string representation.
  """
  @spec encode(term(), atom()) :: {:ok, String.t()} | {:error, term()}
  def encode(value, :string) when is_binary(value), do: {:ok, value}
  def encode(true, :boolean), do: {:ok, "true"}
  def encode(false, :boolean), do: {:ok, "false"}
  def encode(value, :decimal), do: encode_decimal(value)
  def encode(value, :float), do: encode_float(value)
  def encode(value, :double), do: encode_float(value)
  def encode(value, :duration) when is_binary(value), do: {:ok, value}
  def encode(value, :duration) when is_map(value), do: encode_duration(value)
  def encode(%DateTime{} = dt, :dateTime), do: {:ok, DateTime.to_iso8601(dt)}
  def encode(%NaiveDateTime{} = ndt, :dateTime), do: {:ok, NaiveDateTime.to_iso8601(ndt)}
  def encode(%Time{} = time, :time), do: {:ok, Time.to_iso8601(time)}
  def encode(%Date{} = date, :date), do: {:ok, Date.to_iso8601(date)}

  def encode(value, type)
      when type in [:gYearMonth, :gYear, :gMonthDay, :gDay, :gMonth] and is_binary(value) do
    {:ok, value}
  end

  def encode(value, :hexBinary) when is_binary(value), do: {:ok, Base.encode16(value)}
  def encode(value, :base64Binary) when is_binary(value), do: {:ok, Base.encode64(value)}
  def encode(value, :anyURI) when is_binary(value), do: {:ok, value}
  def encode(%URI{} = uri, :anyURI), do: {:ok, URI.to_string(uri)}
  def encode({nil, local}, :QName) when is_binary(local), do: {:ok, local}

  def encode({prefix, local}, :QName) when is_binary(prefix) and is_binary(local),
    do: {:ok, "#{prefix}:#{local}"}

  def encode(value, :NOTATION) when is_binary(value), do: {:ok, value}
  def encode(value, type), do: {:error, {:encode_error, type, value}}

  defp encode_decimal(value) do
    cond do
      Code.ensure_loaded?(Decimal) and is_struct(value, Decimal) ->
        # Use apply to avoid compile-time warning when Decimal is not available
        {:ok, apply(Decimal, :to_string, [value])}

      is_float(value) ->
        {:ok, Float.to_string(value)}

      is_integer(value) ->
        {:ok, Integer.to_string(value)}

      true ->
        {:error, {:encode_error, :decimal, value}}
    end
  end

  defp encode_float(:infinity), do: {:ok, "INF"}
  # XPath alias
  defp encode_float(:positive_infinity), do: {:ok, "INF"}
  defp encode_float(:neg_infinity), do: {:ok, "-INF"}
  # XPath alias
  defp encode_float(:negative_infinity), do: {:ok, "-INF"}
  defp encode_float(:nan), do: {:ok, "NaN"}
  defp encode_float(value) when is_float(value), do: {:ok, Float.to_string(value)}
  defp encode_float(value) when is_integer(value), do: {:ok, Float.to_string(value * 1.0)}
  defp encode_float(value), do: {:error, {:encode_error, :float, value}}

  defp encode_duration(map) do
    negative = if Map.get(map, :negative, false), do: "-", else: ""
    years = encode_duration_part(map, :years, "Y")
    months = encode_duration_part(map, :months, "M")
    days = encode_duration_part(map, :days, "D")
    hours = encode_duration_part(map, :hours, "H")
    minutes = encode_duration_part(map, :minutes, "M")
    seconds = encode_duration_part(map, :seconds, "S")

    time_part = hours <> minutes <> seconds
    time_str = if time_part != "", do: "T" <> time_part, else: ""

    {:ok, negative <> "P" <> years <> months <> days <> time_str}
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
