# Parser Error Transformation Demo
# Run with: mix run examples/parser_errors_demo.exs
#
# Shows how NimbleParsec errors are transformed into user-friendly messages

alias FnXML.Parser
alias FnXML.Parser.ErrorTransform
alias FnXML.Error

defmodule ParserErrorsDemo do
  @separator String.duplicate("-", 60)

  def run do
    IO.puts("\n#{@separator}")
    IO.puts("Parser Error Transformation Demo")
    IO.puts("Transforms cryptic NimbleParsec errors into clear messages")
    IO.puts("#{@separator}\n")

    examples()
    |> Enum.with_index(1)
    |> Enum.each(fn {{title, xml}, index} ->
      demonstrate(index, title, xml)
    end)

    IO.puts("#{@separator}")
    IO.puts("Demo complete - #{length(examples())} examples shown")
    IO.puts("#{@separator}\n")
  end

  defp examples do
    [
      # Invalid tag name starts
      {"Tag name starts with digit",
       ~s(<123element/>)},

      {"Tag name starts with hyphen",
       ~s(<-element/>)},

      {"Tag name starts with period",
       ~s(<.element/>)},

      # Invalid characters in tag names
      {"Exclamation in tag name",
       ~s(<bad!name/>)},

      {"At sign in tag name",
       ~s(<bad@name/>)},

      {"Hash in tag name",
       ~s(<bad#name/>)},

      {"Asterisk in tag name",
       ~s(<bad*name/>)},

      # Unclosed structures
      {"Missing closing bracket",
       ~s(<element attr="value")},

      {"Missing closing bracket with child",
       ~s(<element attr="value"<child/>)},

      {"Unclosed attribute quote",
       ~s(<element attr="unterminated/>)},

      {"Unclosed single quote",
       ~s(<element attr='unterminated/>)},

      # Malformed attributes
      {"Missing attribute value",
       ~s(<element attr=/>)},

      {"Missing equals sign",
       ~s(<element attr"value"/>)},

      # Special constructs (if parser supports them)
      {"Unclosed comment",
       ~s(<!-- comment without closing)},

      {"Unclosed CDATA",
       ~s(<![CDATA[content without closing)},

      # Edge cases
      {"Empty tag name",
       ~s(</>)},

      {"Just an open bracket",
       ~s(<)},

      {"Whitespace after open bracket",
       ~s(<  element/>)}
    ]
  end

  defp demonstrate(index, title, xml) do
    IO.puts("#{index}. #{title}")
    IO.puts("   XML: #{inspect(xml)}")

    case capture_error(xml) do
      {:ok, tokens} ->
        IO.puts("   Result: Parsed successfully (#{length(tokens)} tokens)")

      {:error, type, message, rest, line, col} ->
        IO.puts("   Error Type: :#{type}")
        IO.puts("   Message: #{message}")
        IO.puts("   Location: line #{line}, column #{col}")
        if rest != "" do
          IO.puts("   Near: #{inspect(String.slice(rest, 0, 25))}")
        end

      {:raw_error, msg} ->
        IO.puts("   Raw Error: #{String.slice(msg, 0, 60)}...")
    end

    IO.puts("\n#{@separator}\n")
  end

  defp capture_error(xml) do
    tokens = Parser.parse(xml) |> Enum.to_list()
    {:ok, tokens}
  rescue
    e in MatchError ->
      case e.term do
        {:error, msg, rest, _ctx, {line, _}, col} ->
          transformed = ErrorTransform.transform(msg, rest, line, col)
          {:error, transformed.type, transformed.message, rest, line, col}

        _ ->
          {:raw_error, inspect(e)}
      end

    e ->
      {:raw_error, Exception.message(e)}
  end
end

ParserErrorsDemo.run()
