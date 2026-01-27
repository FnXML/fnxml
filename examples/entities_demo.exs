# Entity Resolution Demo
# Run with: mix run examples/entities_demo.exs
#
# Demonstrates XML entity resolution in text and attributes

alias FnXML.Parser
alias FnXML.Transform.Entities
alias FnXML.Error

defmodule EntitiesDemo do
  @separator String.duplicate("-", 60)

  def run do
    IO.puts("\n#{@separator}")
    IO.puts("Entity Resolution Demo")
    IO.puts("#{@separator}\n")

    demo_predefined_entities()
    demo_numeric_references()
    demo_attribute_entities()
    demo_custom_entities()
    demo_unknown_handling()
    demo_encoding()

    IO.puts("#{@separator}")
    IO.puts("Demo complete")
    IO.puts("#{@separator}\n")
  end

  defp demo_predefined_entities do
    IO.puts("1. Predefined XML Entities")
    IO.puts(@separator)

    examples = [
      {"&amp;", "<a>Tom &amp; Jerry</a>"},
      {"&lt; and &gt;", "<a>&lt;tag&gt;</a>"},
      {"&quot;", "<a>say &quot;hello&quot;</a>"},
      {"&apos;", "<a>it&apos;s working</a>"},
      {"Multiple", "<a>&lt;foo&gt; &amp; &lt;bar&gt;</a>"}
    ]

    for {name, xml} <- examples do
      result = parse_and_resolve(xml)
      IO.puts("   #{name}:")
      IO.puts("     Input:  #{inspect(xml)}")
      IO.puts("     Output: #{inspect(result)}")
      IO.puts("")
    end
  end

  defp demo_numeric_references do
    IO.puts("2. Numeric Character References")
    IO.puts(@separator)

    examples = [
      {"Decimal &#60;", "<a>&#60;</a>", "<"},
      {"Decimal &#62;", "<a>&#62;</a>", ">"},
      {"Hex &#x3C;", "<a>&#x3C;</a>", "<"},
      {"Hex &#x3E;", "<a>&#x3E;</a>", ">"},
      {"Euro &#8364;", "<a>Price: &#8364;100</a>", "Price: €100"},
      {"Euro hex &#x20AC;", "<a>&#x20AC;</a>", "€"},
      {"Emoji &#x1F600;", "<a>&#x1F600;</a>", "😀"},
      {"Copyright &#169;", "<a>&#169; 2024</a>", "© 2024"}
    ]

    for {name, xml, expected} <- examples do
      result = parse_and_resolve(xml)
      status = if result == expected, do: "✓", else: "✗"
      IO.puts("   #{name}: #{inspect(result)} #{status}")
    end
    IO.puts("")
  end

  defp demo_attribute_entities do
    IO.puts("3. Entities in Attributes")
    IO.puts(@separator)

    examples = [
      {~s(<a href="?foo&amp;bar"/>), "href", "?foo&bar"},
      {~s(<a title="&lt;value&gt;"/>), "title", "<value>"},
      {~s(<a data="&#169; 2024"/>), "data", "© 2024"}
    ]

    for {xml, attr, expected} <- examples do
      result = extract_attr(xml, attr)
      status = if result == expected, do: "✓", else: "✗"
      IO.puts("   #{attr}: #{inspect(result)} #{status}")
      IO.puts("     From: #{xml}")
      IO.puts("")
    end
  end

  defp demo_custom_entities do
    IO.puts("4. Custom Entities")
    IO.puts(@separator)

    custom = %{
      "copy" => "©",
      "reg" => "®",
      "tm" => "™",
      "mdash" => "—",
      "nbsp" => " "
    }

    examples = [
      {"&copy;", "<a>&copy; 2024</a>", "© 2024"},
      {"&reg;", "<a>Brand&reg;</a>", "Brand®"},
      {"&tm;", "<a>Product&tm;</a>", "Product™"},
      {"Mixed", "<a>&copy; Company&reg; &mdash; All rights</a>", "© Company® — All rights"}
    ]

    IO.puts("   Custom entities: #{inspect(Map.keys(custom))}")
    IO.puts("")

    for {name, xml, expected} <- examples do
      result =
        Parser.parse(xml)
        |> Entities.resolve(entities: custom)
        |> extract_text()

      status = if result == expected, do: "✓", else: "✗"
      IO.puts("   #{name}: #{inspect(result)} #{status}")
    end
    IO.puts("")
  end

  defp demo_unknown_handling do
    IO.puts("5. Unknown Entity Handling")
    IO.puts(@separator)

    xml = "<a>Hello &unknown; World</a>"
    IO.puts("   XML: #{xml}")
    IO.puts("")

    # on_unknown: :keep
    result_keep =
      Parser.parse(xml)
      |> Entities.resolve(on_unknown: :keep)
      |> extract_text()

    IO.puts("   on_unknown: :keep   -> #{inspect(result_keep)}")

    # on_unknown: :remove
    result_remove =
      Parser.parse(xml)
      |> Entities.resolve(on_unknown: :remove)
      |> extract_text()

    IO.puts("   on_unknown: :remove -> #{inspect(result_remove)}")

    # on_unknown: :emit
    result_emit =
      Parser.parse(xml)
      |> Entities.resolve(on_unknown: :emit)
      |> Enum.to_list()

    has_error = Enum.any?(result_emit, &match?({:error, _}, &1))
    IO.puts("   on_unknown: :emit   -> error token emitted: #{has_error}")

    # on_unknown: :raise (default)
    IO.puts("   on_unknown: :raise  -> raises FnXML.Error")

    try do
      Parser.parse(xml)
      |> Entities.resolve()
      |> Enum.to_list()
    rescue
      e in Error ->
        IO.puts("     Error: #{e.message}")
    end

    IO.puts("")
  end

  defp demo_encoding do
    IO.puts("6. Encoding (Reverse Operation)")
    IO.puts(@separator)

    examples = [
      {"Tom & Jerry", "Tom &amp; Jerry"},
      {"<tag>", "&lt;tag&gt;"},
      {"a < b > c", "a &lt; b &gt; c"},
      {"1 & 2 & 3", "1 &amp; 2 &amp; 3"}
    ]

    for {input, expected} <- examples do
      result = Entities.encode(input)
      status = if result == expected, do: "✓", else: "✗"
      IO.puts("   #{inspect(input)} -> #{inspect(result)} #{status}")
    end

    IO.puts("")
    IO.puts("   Attribute encoding (also escapes quotes):")
    attr_input = "say \"hello\""
    attr_result = Entities.encode_attr(attr_input)
    IO.puts("   #{inspect(attr_input)} -> #{inspect(attr_result)}")
    IO.puts("")
  end

  # Helper functions
  defp parse_and_resolve(xml) do
    Parser.parse(xml)
    |> Entities.resolve()
    |> extract_text()
  end

  defp extract_text(stream) do
    stream
    |> Enum.to_list()
    |> Enum.find_value(fn
      {:text, meta} -> Keyword.get(meta, :content)
      _ -> nil
    end)
  end

  defp extract_attr(xml, attr_name) do
    Parser.parse(xml)
    |> Entities.resolve()
    |> Enum.to_list()
    |> Enum.find_value(fn
      {:open, meta} ->
        attrs = Keyword.get(meta, :attributes, [])
        Enum.find_value(attrs, fn {name, val} -> if name == attr_name, do: val end)

      _ ->
        nil
    end)
  end
end

EntitiesDemo.run()
