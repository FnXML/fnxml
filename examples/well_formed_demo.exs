# Well-Formedness Validation Demo
# Run with: mix run examples/well_formed_demo.exs
#
# Tests tag structure: matching open/close tags, proper nesting

alias FnXML.Parser
alias FnXML.Stream.Validate
alias FnXML.Error

defmodule WellFormedDemo do
  @separator String.duplicate("-", 60)

  def run do
    IO.puts("\n#{@separator}")
    IO.puts("Well-Formedness Validation Demo")
    IO.puts("Validates: tag matching, proper nesting, no orphan closes")
    IO.puts("#{@separator}\n")

    examples()
    |> Enum.with_index(1)
    |> Enum.each(fn {{title, xml, expected_valid}, index} ->
      demonstrate(index, title, xml, expected_valid)
    end)

    IO.puts("#{@separator}")
    IO.puts("Demo complete - #{length(examples())} examples shown")
    IO.puts("#{@separator}\n")
  end

  defp examples do
    [
      # Valid cases
      {"Simple valid nesting",
       ~s(<root><child>text</child></root>),
       :valid},

      {"Self-closing tags",
       ~s(<root><empty/><another/></root>),
       :valid},

      {"Deeply nested valid structure",
       ~s(<a><b><c><d>deep</d></c></b></a>),
       :valid},

      {"Mixed content valid",
       ~s(<root>text<child/>more text</root>),
       :valid},

      # Error cases
      {"Mismatched close tag (wrong name)",
       ~s(<root><child></wrong></root>),
       :error},

      {"Mismatched close tag (swapped order)",
       ~s(<a><b></a></b>),
       :error},

      {"Orphan close tag (no matching open)",
       ~s(</orphan>),
       :error},

      {"Close tag before any open",
       ~s(</first><root></root>),
       :error},

      {"Extra close tag at end",
       ~s(<root></root></extra>),
       :error},

      {"Wrong close in deep nesting",
       ~s(<a><b><c></b></c></a>),
       :error},

      {"Multiple mismatches",
       ~s(<x><y><z></x></y></z>),
       :error},

      {"Namespace prefix mismatch (different prefix)",
       ~s(<ns:root xmlns:ns="http://x"></other:root>),
       :error}
    ]
  end

  defp demonstrate(index, title, xml, expected) do
    IO.puts("#{index}. #{title}")
    IO.puts("   XML: #{inspect(xml)}")
    IO.puts("   Expected: #{expected}")

    result = validate(xml)

    case {result, expected} do
      {:valid, :valid} ->
        IO.puts("   Result: VALID ✓")

      {{:error, %Error{} = e}, :error} ->
        IO.puts("   Result: ERROR ✓")
        IO.puts("   Type: :#{e.type}")
        IO.puts("   Message: #{e.message}")
        if e.line, do: IO.puts("   Location: line #{e.line}, column #{e.column}")

      {result, expected} ->
        IO.puts("   Result: UNEXPECTED - got #{inspect(result)}, expected #{expected}")
    end

    IO.puts("\n#{@separator}\n")
  end

  defp validate(xml) do
    Parser.parse(xml)
    |> Validate.well_formed(on_error: :emit)
    |> Enum.find_value(:valid, fn
      {:error, e} -> {:error, e}
      _ -> nil
    end)
  rescue
    e in Error -> {:error, e}
    e in MatchError -> {:parse_error, e}
  end
end

WellFormedDemo.run()
