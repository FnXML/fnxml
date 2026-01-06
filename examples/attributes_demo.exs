# Attribute Validation Demo
# Run with: mix run examples/attributes_demo.exs
#
# Tests attribute uniqueness within elements

alias FnXML.Parser
alias FnXML.Stream.Validate
alias FnXML.Error

defmodule AttributesDemo do
  @separator String.duplicate("-", 60)

  def run do
    IO.puts("\n#{@separator}")
    IO.puts("Attribute Validation Demo")
    IO.puts("Validates: no duplicate attribute names within an element")
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
      {"Single attribute",
       ~s(<element id="1"/>),
       :valid},

      {"Multiple unique attributes",
       ~s(<element id="1" name="test" class="primary"/>),
       :valid},

      {"Same attribute name on different elements",
       ~s(<root id="1"><child id="2"/></root>),
       :valid},

      {"Namespaced and non-namespaced (different)",
       ~s(<root xmlns:ns="http://x" id="1" ns:id="2"/>),
       :valid},

      {"Empty attribute value",
       ~s(<element id="" name=""/>),
       :valid},

      {"Attributes with special characters in values",
       ~s(<element data="a&amp;b" title="x&lt;y"/>),
       :valid},

      # Error cases
      {"Duplicate id attribute",
       ~s(<element id="1" id="2"/>),
       :error},

      {"Duplicate with different values",
       ~s(<element class="one" name="test" class="two"/>),
       :error},

      {"Duplicate at start and end",
       ~s(<element first="1" middle="2" last="3" first="4"/>),
       :error},

      {"Triple duplicate",
       ~s(<element x="1" x="2" x="3"/>),
       :error},

      {"Duplicate in nested element",
       ~s(<root ok="1"><child dup="a" other="b" dup="c"/></root>),
       :error},

      {"Duplicate namespace declaration",
       ~s(<root xmlns:ns="http://one" xmlns:ns="http://two"/>),
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
    |> Validate.attributes(on_error: :emit)
    |> Enum.find_value(:valid, fn
      {:error, e} -> {:error, e}
      _ -> nil
    end)
  rescue
    e in Error -> {:error, e}
    e in MatchError -> {:parse_error, e}
  end
end

AttributesDemo.run()
