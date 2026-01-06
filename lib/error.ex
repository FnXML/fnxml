defmodule FnXML.Error do
  @moduledoc """
  Error types for FnXML parsing and validation.

  Provides structured error information with:
  - Error type classification
  - Human-readable messages
  - Source location (line/column)
  - Context for debugging
  """

  defexception [:type, :message, :line, :column, :context]

  @type error_type ::
          :parse_error
          | :tag_mismatch
          | :unexpected_close
          | :duplicate_attr
          | :invalid_character
          | :invalid_name_start
          | :undeclared_namespace
          | :unclosed_tag
          | :unclosed_cdata
          | :unclosed_comment
          | :unclosed_pi
          | :missing_attr_value
          | :invalid_quote
          | :buffer_overflow
          | :stream_error

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          line: pos_integer() | nil,
          column: pos_integer() | nil,
          context: map()
        }

  @doc """
  Create a parse error from NimbleParsec output or other parse failures.
  """
  def parse_error(type, message, line \\ nil, column \\ nil, context \\ %{}) do
    %__MODULE__{
      type: type,
      message: message,
      line: line,
      column: column,
      context: context
    }
  end

  @doc """
  Create a tag mismatch error.
  """
  def tag_mismatch(expected, got, {line, column}) do
    %__MODULE__{
      type: :tag_mismatch,
      message: "Expected </#{expected}>, got </#{got}>",
      line: line,
      column: column,
      context: %{expected: expected, got: got}
    }
  end

  def tag_mismatch(expected, got, line, column) do
    tag_mismatch(expected, got, {line, column})
  end

  @doc """
  Create an unexpected close tag error.
  """
  def unexpected_close(tag, {line, column}) do
    %__MODULE__{
      type: :unexpected_close,
      message: "Unexpected close tag </#{tag}>, no matching open tag",
      line: line,
      column: column,
      context: %{tag: tag}
    }
  end

  @doc """
  Create a duplicate attribute error.
  """
  def duplicate_attribute(attr_name, {line, column}) do
    %__MODULE__{
      type: :duplicate_attr,
      message: "Duplicate attribute '#{attr_name}'",
      line: line,
      column: column,
      context: %{attribute: attr_name}
    }
  end

  @doc """
  Create an undeclared namespace error.
  """
  def undeclared_namespace(prefix, {line, column}) do
    %__MODULE__{
      type: :undeclared_namespace,
      message: "Undeclared namespace prefix '#{prefix}'",
      line: line,
      column: column,
      context: %{prefix: prefix}
    }
  end

  @doc """
  Format error context showing surrounding source lines with a pointer.

  ## Example output

      5 | <root>
      6 |   <child>
   >> 7 |     <bad!tag/>
         |         ^
      8 |   </child>
      9 | </root>
  """
  def format_context(source, line, column, _window \\ 40) when is_binary(source) do
    lines = String.split(source, ~r/\r?\n/)
    line_count = length(lines)

    # Calculate line range to show (2 before, 2 after)
    start_line = max(1, line - 2)
    end_line = min(line_count, line + 2)

    # Build context lines
    context_lines =
      start_line..end_line
      |> Enum.map(fn num ->
        line_text = Enum.at(lines, num - 1, "")
        prefix = if num == line, do: ">> ", else: "   "
        line_num = String.pad_leading(Integer.to_string(num), 3)
        "#{prefix}#{line_num} | #{line_text}"
      end)

    # Build pointer line
    pointer_padding = String.duplicate(" ", 8 + max(0, column - 1))
    pointer_line = "#{pointer_padding}^"

    # Insert pointer after the error line
    {before_pointer, after_pointer} =
      Enum.split_while(context_lines, fn line ->
        not String.starts_with?(line, ">>")
      end)

    case after_pointer do
      [error_line | rest] ->
        Enum.join(before_pointer ++ [error_line, pointer_line] ++ rest, "\n")

      [] ->
        Enum.join(context_lines ++ [pointer_line], "\n")
    end
  end

  @doc """
  Format error for display, optionally with source context.
  """
  def format(%__MODULE__{} = error, source \\ nil) do
    location =
      case {error.line, error.column} do
        {nil, nil} -> ""
        {line, nil} -> " (at line #{line})"
        {line, col} -> " (at line #{line}, column #{col})"
      end

    base = "[#{error.type}] #{error.message}#{location}"

    if source && error.line do
      context = format_context(source, error.line, error.column || 1)
      "#{base}\n\n#{context}"
    else
      base
    end
  end

  # Implementation of Exception.message/1
  @impl true
  def message(%__MODULE__{} = error) do
    format(error)
  end
end
