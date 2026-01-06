# Namespace Validation Demo
# Run with: mix run examples/namespaces_demo.exs
#
# Tests namespace prefix declarations and scoping

alias FnXML.Parser
alias FnXML.Stream.Validate
alias FnXML.Error

defmodule NamespacesDemo do
  @separator String.duplicate("-", 60)

  def run do
    IO.puts("\n#{@separator}")
    IO.puts("Namespace Validation Demo")
    IO.puts("Validates: namespace prefixes must be declared before use")
    IO.puts("Reserved prefixes 'xml' and 'xmlns' are always valid")
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
      # Valid cases - no namespaces
      {"No namespace prefixes",
       ~s(<root><child/></root>),
       :valid},

      # Valid cases - declared namespaces
      {"Declared prefix on element",
       ~s(<root xmlns:ns="http://example.com"><ns:child/></root>),
       :valid},

      {"Declared prefix on attribute",
       ~s(<root xmlns:ns="http://example.com" ns:attr="value"/>),
       :valid},

      {"Multiple namespace declarations",
       ~s(<root xmlns:a="http://a.com" xmlns:b="http://b.com"><a:x/><b:y/></root>),
       :valid},

      {"Default namespace (no prefix)",
       ~s(<root xmlns="http://default.com"><child/></root>),
       :valid},

      {"Namespace declared on same element",
       ~s(<ns:root xmlns:ns="http://example.com"/>),
       :valid},

      {"Nested namespace scoping",
       ~s(<root><inner xmlns:ns="http://x"><ns:child/></inner></root>),
       :valid},

      # Valid cases - reserved prefixes
      {"Reserved 'xml' prefix (always valid)",
       ~s(<root xml:lang="en" xml:space="preserve"/>),
       :valid},

      {"Reserved 'xmlns' for declarations",
       ~s(<root xmlns:custom="http://custom.com"/>),
       :valid},

      # Error cases - undeclared prefixes
      {"Undeclared prefix on element",
       ~s(<ns:root/>),
       :error},

      {"Undeclared prefix on nested element",
       ~s(<root><ns:child/></root>),
       :error},

      {"Undeclared prefix on attribute",
       ~s(<root ns:attr="value"/>),
       :error},

      {"Prefix used before declaration (wrong order)",
       ~s(<ns:root xmlns:ns="http://x"/>),
       :valid},  # Actually valid - xmlns on same element

      {"Prefix out of scope (declared in sibling)",
       ~s(<root><a xmlns:ns="http://x"/><b><ns:child/></b></root>),
       :error},

      {"Prefix out of scope (declared in child)",
       ~s(<root><inner xmlns:ns="http://x"/><ns:other/></root>),
       :error},

      {"Multiple undeclared prefixes",
       ~s(<a:root><b:child c:attr="val"/></a:root>),
       :error},

      {"Typo in prefix name",
       ~s(<root xmlns:data="http://x"><dta:child/></root>),
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
    |> Validate.namespaces(on_error: :emit)
    |> Enum.find_value(:valid, fn
      {:error, e} -> {:error, e}
      _ -> nil
    end)
  rescue
    e in Error -> {:error, e}
    e in MatchError -> {:parse_error, e}
  end
end

NamespacesDemo.run()
