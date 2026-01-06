defmodule FnXML.Parser.ErrorTransform do
  @moduledoc """
  Transforms raw NimbleParsec error messages into user-friendly FnXML.Error structs.

  NimbleParsec errors can be verbose and technical:

      "expected ASCII character in the range \"a\" to \"z\" or ASCII character
       in the range \"A\" to \"Z\" or byte equal to ?_"

  This module classifies common error patterns and provides clear, actionable messages.
  """

  alias FnXML.Error

  # Error patterns: {regex, error_type, user_friendly_message}
  # IMPORTANT: More specific patterns must come before general ones
  @error_patterns [
    # Element name errors
    {~r/expected.*element name/i, :invalid_tag_name,
     "Invalid tag name. Tag names must start with a letter or underscore."},
    {~r/expected.*letter.*underscore/i, :invalid_name_start,
     "Invalid name. Element and attribute names must start with a letter, underscore, or colon."},

    # Special construct errors - MUST be before generic '>' pattern
    {~r/expected.*\]\]>/i, :unclosed_cdata, "Unclosed CDATA section. Expected ']]>'."},
    {~r/expected.*-->/i, :unclosed_comment, "Unclosed comment. Expected '-->'."},
    {~r/expected.*\?>/i, :unclosed_pi, "Unclosed processing instruction. Expected '?>'."},

    # Tag structure errors
    {~r/expected.*close.*tag|expected.*<\//i, :unclosed_tag,
     "Unclosed tag. Expected closing tag."},
    {~r/expected.*open.*tag/i, :parse_error, "Expected opening tag."},

    # Bracket errors - general '>' pattern comes after specific constructs
    {~r/expected.*>|expected.*close.*bracket/i, :unclosed_bracket,
     "Unclosed tag. Missing closing '>'."},
    {~r/expected.*</i, :parse_error, "Expected XML tag starting with '<'."},

    # Attribute errors
    {~r/expected.*attribute.*value/i, :missing_attr_value,
     "Missing attribute value. Attributes must have quoted values: name=\"value\""},
    {~r/expected.*["'].*or.*["']/i, :invalid_quote,
     "Invalid or missing quote. Attribute values must be wrapped in matching quotes."},
    {~r/expected.*=/i, :missing_attr_value, "Missing '=' after attribute name."},

    # Character errors
    {~r/expected.*valid.*xml.*character/i, :invalid_character,
     "Invalid character. XML does not allow control characters (except tab, newline, carriage return)."},
    {~r/expected.*valid.*name.*character/i, :invalid_character,
     "Invalid character in name."}
  ]

  @doc """
  Classify a NimbleParsec error message and return a user-friendly error.

  Returns `{error_type, user_message}` tuple.
  """
  def classify(raw_message, rest \\ "") do
    # First try to infer from the remaining input context
    case classify_by_context(rest) do
      nil ->
        # Fall back to message pattern matching
        case find_matching_pattern(raw_message) do
          {_, type, message} -> {type, message}
          nil -> {:parse_error, simplify_message(raw_message)}
        end

      result ->
        result
    end
  end

  # Infer error type from remaining unparsed input
  defp classify_by_context(""), do: nil
  defp classify_by_context(rest) when is_binary(rest) do
    first_char = String.first(rest)

    cond do
      # Tag name starts with digit: <123invalid/>
      first_char != nil and first_char =~ ~r/[0-9]/ ->
        {:invalid_name_start,
         "Invalid tag name. Names cannot start with a digit '#{first_char}'."}

      # Invalid character in tag name: <bad!name/>
      first_char != nil and first_char =~ ~r/[!@#$%^&*()\[\]{}|\\;,]/ ->
        {:invalid_character,
         "Invalid character '#{first_char}' in tag name."}

      # Unclosed quote: has opening quote but no proper closing before tag end
      # Pattern: attr="value/> or attr="value>  (quote opened but not closed)
      has_unclosed_quote?(rest) ->
        {:unclosed_quote,
         "Unclosed attribute value. Missing closing quote."}

      # New tag starts immediately - missing '>' on previous tag
      # Pattern: <element attr="value"<next> - got '<' when expecting '>' or '/>'
      first_char == "<" ->
        {:unclosed_bracket,
         "Missing '>' to close tag. Found '<' when expecting '>' or '/>'."}

      true ->
        nil
    end
  end
  defp classify_by_context(_), do: nil

  # Check for unclosed quote patterns
  defp has_unclosed_quote?(rest) do
    # Look for patterns like: attr="unterminated/> or ="value>
    # Count quotes - odd number before /> or > suggests unclosed
    cond do
      # Pattern: something="..../> without closing quote
      rest =~ ~r/="[^"]*\/>$/ -> true
      rest =~ ~r/="[^"]*>$/ -> true
      # Pattern: has = followed by single quote char then tag end
      rest =~ ~r/=\s*"[^"]*[\/]?>/ and not (rest =~ ~r/=\s*"[^"]*"/) -> true
      true -> false
    end
  end

  @doc """
  Transform a NimbleParsec error tuple into an FnXML.Error struct.

  ## Parameters

  - `raw_message` - The error message from NimbleParsec
  - `rest` - The remaining unparsed input
  - `line` - The line number where the error occurred
  - `column` - The column number where the error occurred
  """
  def transform(raw_message, rest, line, column) do
    {type, message} = classify(raw_message, rest)

    Error.parse_error(type, message, line, column, %{
      near: extract_context(rest),
      raw: raw_message
    })
  end

  # Find the first matching error pattern
  defp find_matching_pattern(raw_message) do
    Enum.find(@error_patterns, fn {pattern, _, _} ->
      Regex.match?(pattern, raw_message)
    end)
  end

  @doc """
  Simplify verbose NimbleParsec messages into something more readable.
  """
  def simplify_message(raw) do
    raw
    # Convert character range descriptions
    |> String.replace(~r/ASCII character in the range "(.)" to "(.)"/, "\\1-\\2")
    # Convert byte descriptions
    |> String.replace(~r/byte equal to \?(\S)/, "'\\1'")
    # Clean up "or" chains
    |> String.replace(~r/\s+or\s+/, ", ")
    # Capitalize "expected"
    |> String.replace(~r/^expected\s+/i, "Expected ")
    # Truncate overly long messages
    |> String.slice(0, 150)
    |> String.trim()
  end

  # Extract a short context string from remaining input
  defp extract_context(rest) when is_binary(rest) do
    rest
    |> String.slice(0, 30)
    |> String.replace(~r/[\r\n]+/, " ")
    |> case do
      context when byte_size(rest) > 30 -> context <> "..."
      context -> context
    end
  end

  defp extract_context(_), do: ""
end
