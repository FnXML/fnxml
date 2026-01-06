# Error Messaging Demo
# Run with: mix run examples/error_demo.exs

alias FnXML.Parser
alias FnXML.Stream.Validate
alias FnXML.Error
alias FnXML.Parser.ErrorTransform

defmodule ErrorDemo do
  @separator String.duplicate("-", 60)

  def run do
    IO.puts("\n#{@separator}")
    IO.puts("FnXML Error Messaging Demo")
    IO.puts("#{@separator}\n")

    examples()
    |> Enum.with_index(1)
    |> Enum.each(fn {{title, xml, validator}, index} ->
      demonstrate(index, title, xml, validator)
    end)

    IO.puts("#{@separator}")
    IO.puts("Demo complete - #{length(examples())} error examples shown")
    IO.puts("#{@separator}\n")
  end

  defp examples do
    [
      # Validation errors (Stream.Validate)
      {"Mismatched closing tag",
       ~s(<root><child></wrong></root>),
       :well_formed},

      {"Unexpected close tag (no matching open)",
       ~s(</orphan>),
       :well_formed},

      {"Deeply nested tag mismatch",
       ~s(<a><b><c></b></c></a>),
       :well_formed},

      {"Duplicate attribute",
       ~s(<element id="1" name="test" id="2"/>),
       :attributes},

      {"Undeclared namespace prefix on element",
       ~s(<foo:element>content</foo:element>),
       :namespaces},

      {"Undeclared namespace prefix on attribute",
       ~s(<root bar:attr="value"/>),
       :namespaces},

      # Parser errors (NimbleParsec with improved messages)
      {"Invalid tag name (starts with number)",
       ~s(<123invalid/>),
       :parse},

      {"Invalid tag name (special character)",
       ~s(<bad!name/>),
       :parse},

      {"Unclosed tag (missing >)",
       ~s(<element attr="value"),
       :parse},

      {"Unclosed attribute quote",
       ~s(<element attr="unterminated/>),
       :parse}
    ]
  end

  defp demonstrate(index, title, xml, validator) do
    IO.puts("#{index}. #{title}")
    IO.puts("   XML: #{inspect(xml)}")
    IO.puts("")

    error = capture_error(xml, validator)

    case error do
      %Error{} = e ->
        IO.puts("   Error Type: :#{e.type}")
        IO.puts("   Message: #{e.message}")
        if e.line || e.column do
          IO.puts("   Location: line #{e.line || "?"}, column #{e.column || "?"}")
        end
        if e.context[:near] do
          IO.puts("   Near: #{inspect(e.context[:near])}")
        end

      {:raw_parse_error, raw_msg, rest, line, col} ->
        # Show both raw and transformed for comparison
        IO.puts("   Raw NimbleParsec: #{String.slice(raw_msg, 0, 80)}...")
        IO.puts("   Remaining input: #{inspect(String.slice(rest, 0, 30))}")
        transformed = ErrorTransform.transform(raw_msg, rest, line, col)
        IO.puts("")
        IO.puts("   Transformed Error:")
        IO.puts("   Error Type: :#{transformed.type}")
        IO.puts("   Message: #{transformed.message}")
        IO.puts("   Location: line #{line}, column #{col}")

      :no_error ->
        IO.puts("   (No error captured - XML may be valid)")

      other ->
        IO.puts("   Result: #{inspect(other)}")
    end

    IO.puts("\n#{@separator}\n")
  end

  defp capture_error(xml, :well_formed) do
    Parser.parse(xml)
    |> Validate.well_formed(on_error: :emit)
    |> Enum.find_value(fn
      {:error, e} -> e
      _ -> nil
    end) || :no_error
  rescue
    e in Error -> e
  end

  defp capture_error(xml, :attributes) do
    Parser.parse(xml)
    |> Validate.attributes(on_error: :emit)
    |> Enum.find_value(fn
      {:error, e} -> e
      _ -> nil
    end) || :no_error
  rescue
    e in Error -> e
  end

  defp capture_error(xml, :namespaces) do
    Parser.parse(xml)
    |> Validate.namespaces(on_error: :emit)
    |> Enum.find_value(fn
      {:error, e} -> e
      _ -> nil
    end) || :no_error
  rescue
    e in Error -> e
  end

  defp capture_error(xml, :parse) do
    # Parser errors happen during parsing itself
    # NimbleParsec returns {:error, message, rest, context, line, column}
    Parser.parse(xml) |> Enum.to_list()
    :no_error
  rescue
    e in Error ->
      e

    e in MatchError ->
      # The parser crashes with MatchError when NimbleParsec returns error
      # Extract the error info from the exception
      case e.term do
        {:error, msg, rest, _ctx, {line, _}, col} ->
          {:raw_parse_error, msg, rest, line, col}

        other ->
          {:match_error, inspect(other)}
      end
  end
end

ErrorDemo.run()
