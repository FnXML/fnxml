defmodule FnXML.DTD.EntityResolverTest do
  use ExUnit.Case, async: true

  alias FnXML.DTD.{EntityResolver, Model, Parser}

  describe "extract_entities/1" do
    test "extracts internal entities" do
      model =
        Model.new()
        |> Model.add_entity("copyright", {:internal, "(c) 2024"})
        |> Model.add_entity("author", {:internal, "Jane Doe"})

      entities = EntityResolver.extract_entities(model)

      assert entities["copyright"] == "(c) 2024"
      assert entities["author"] == "Jane Doe"
    end

    test "skips external entities without resolver" do
      model =
        Model.new()
        |> Model.add_entity("internal", {:internal, "value"})
        |> Model.add_entity("external", {:external, "file.xml", nil})

      entities = EntityResolver.extract_entities(model)

      assert entities["internal"] == "value"
      refute Map.has_key?(entities, "external")
    end

    test "skips unparsed entities" do
      model =
        Model.new()
        |> Model.add_entity("logo", {:external_unparsed, "logo.gif", nil, "gif"})

      entities = EntityResolver.extract_entities(model)

      assert entities == %{}
    end
  end

  describe "extract_and_expand_entities/2" do
    test "expands nested entity references" do
      model =
        Model.new()
        |> Model.add_entity("greeting", {:internal, "Hello"})
        |> Model.add_entity("message", {:internal, "&greeting;, World!"})

      {:ok, entities} = EntityResolver.extract_and_expand_entities(model)

      assert entities["greeting"] == "Hello"
      assert entities["message"] == "Hello, World!"
    end

    test "handles multiple levels of nesting" do
      model =
        Model.new()
        |> Model.add_entity("a", {:internal, "A"})
        |> Model.add_entity("b", {:internal, "&a;B"})
        |> Model.add_entity("c", {:internal, "&b;C"})

      {:ok, entities} = EntityResolver.extract_and_expand_entities(model)

      assert entities["a"] == "A"
      assert entities["b"] == "AB"
      assert entities["c"] == "ABC"
    end

    test "handles forward references" do
      # b references a, but a is defined after b
      model =
        Model.new()
        |> Model.add_entity("b", {:internal, "&a; world"})
        |> Model.add_entity("a", {:internal, "hello"})

      {:ok, entities} = EntityResolver.extract_and_expand_entities(model)

      assert entities["a"] == "hello"
      assert entities["b"] == "hello world"
    end

    test "preserves character references" do
      model =
        Model.new()
        |> Model.add_entity("copy", {:internal, "&#169;"})
        |> Model.add_entity("euro", {:internal, "&#x20AC;"})

      {:ok, entities} = EntityResolver.extract_and_expand_entities(model)

      # Character references should be preserved for FnXML.Transform.Entities to handle
      assert entities["copy"] == "&#169;"
      assert entities["euro"] == "&#x20AC;"
    end

    test "enforces depth limit" do
      # Create circular reference
      model =
        Model.new()
        |> Model.add_entity("a", {:internal, "&b;"})
        |> Model.add_entity("b", {:internal, "&a;"})

      result = EntityResolver.extract_and_expand_entities(model, max_expansion_depth: 5)

      assert {:error, msg} = result
      assert msg =~ "depth limit exceeded"
    end

    test "enforces expansion size limit" do
      # Create exponential expansion (billion laughs style)
      model =
        Model.new()
        |> Model.add_entity("x", {:internal, String.duplicate("A", 1000)})
        |> Model.add_entity("y", {:internal, "&x;&x;&x;&x;&x;&x;&x;&x;&x;&x;"})

      result = EntityResolver.extract_and_expand_entities(model, max_total_expansion: 5000)

      assert {:error, msg} = result
      assert msg =~ "size limit exceeded"
    end

    test "preserves unknown entity references" do
      model =
        Model.new()
        |> Model.add_entity("known", {:internal, "value &unknown; here"})

      {:ok, entities} = EntityResolver.extract_and_expand_entities(model)

      # Unknown references preserved for FnXML.Transform.Entities to handle
      assert entities["known"] == "value &unknown; here"
    end
  end

  describe "expand_entity/4" do
    test "expands simple reference" do
      entities = %{"greeting" => "Hello"}

      {:ok, result, _} = EntityResolver.expand_entity("Say &greeting;!", entities, 10, 1000)

      assert result == "Say Hello!"
    end

    test "expands multiple references" do
      entities = %{"a" => "1", "b" => "2", "c" => "3"}

      {:ok, result, _} = EntityResolver.expand_entity("&a;-&b;-&c;", entities, 10, 1000)

      assert result == "1-2-3"
    end

    test "returns error on depth exceeded" do
      entities = %{"loop" => "&loop;"}

      result = EntityResolver.expand_entity("&loop;", entities, 3, 1000)

      assert {:error, msg} = result
      assert msg =~ "depth limit exceeded"
    end
  end

  describe "resolve/3 integration" do
    test "resolves entities in XML stream" do
      dtd = """
      <!ENTITY greeting "Hello">
      <!ENTITY target "World">
      """

      {:ok, model} = Parser.parse(dtd)

      xml = "<root>&greeting;, &target;!</root>"

      events =
        FnXML.Parser.parse(xml)
        |> EntityResolver.resolve(model, on_unknown: :keep)
        |> Enum.to_list()

      text_event =
        Enum.find(events, fn
          {:characters, _, _, _, _} -> true
          {:characters, _, _} -> true
          _ -> false
        end)

      assert text_event != nil
      assert elem(text_event, 1) == "Hello, World!"
    end

    test "resolves entities in attributes" do
      model =
        Model.new()
        |> Model.add_entity("val", {:internal, "test-value"})

      xml = ~s(<div class="&val;">content</div>)

      events =
        FnXML.Parser.parse(xml)
        |> EntityResolver.resolve(model, on_unknown: :keep)
        |> Enum.to_list()

      open_event =
        Enum.find(events, fn
          {:start_element, "div", _, _, _, _} -> true
          {:start_element, "div", _, _} -> true
          _ -> false
        end)

      assert open_event != nil
      attrs = elem(open_event, 2)
      assert {"class", "test-value"} in attrs
    end

    test "handles nested entities in stream" do
      model =
        Model.new()
        |> Model.add_entity("inner", {:internal, "INNER"})
        |> Model.add_entity("outer", {:internal, "[&inner;]"})

      xml = "<root>&outer;</root>"

      events =
        FnXML.Parser.parse(xml)
        |> EntityResolver.resolve(model)
        |> Enum.to_list()

      text_event =
        Enum.find(events, fn
          {:characters, _, _, _, _} -> true
          {:characters, _, _} -> true
          _ -> false
        end)

      assert text_event != nil
      assert elem(text_event, 1) == "[INNER]"
    end

    test "respects on_unknown option" do
      model = Model.new()

      xml = "<root>&unknown;</root>"

      # With :keep, unknown entity stays as-is
      events =
        FnXML.Parser.parse(xml)
        |> EntityResolver.resolve(model, on_unknown: :keep)
        |> Enum.to_list()

      text_event =
        Enum.find(events, fn
          {:characters, _, _, _, _} -> true
          {:characters, _, _} -> true
          _ -> false
        end)

      assert text_event != nil
      assert elem(text_event, 1) == "&unknown;"
    end

    test "uses external resolver when provided" do
      model =
        Model.new()
        |> Model.add_entity("external", {:external, "http://example.com/entity.txt", nil})

      resolver = fn "http://example.com/entity.txt", nil ->
        {:ok, "External Content"}
      end

      {:ok, entities} =
        EntityResolver.extract_and_expand_entities(model, external_resolver: resolver)

      assert entities["external"] == "External Content"
    end
  end

  describe "security limits" do
    test "default depth limit is 10" do
      # Create deep nesting
      model =
        Enum.reduce(1..15, Model.new(), fn i, m ->
          value = if i == 1, do: "base", else: "&e#{i - 1};"
          Model.add_entity(m, "e#{i}", {:internal, value})
        end)

      result = EntityResolver.extract_and_expand_entities(model)

      assert {:error, _} = result
    end

    test "custom depth limit is respected" do
      # Create a chain that requires nested expansion
      # When expanding "outer", we need to expand "inner" which is depth 1
      model =
        Model.new()
        |> Model.add_entity("inner", {:internal, "value"})
        |> Model.add_entity("outer", {:internal, "&inner;"})

      # Even with depth 1, simple chains should work
      {:ok, entities} = EntityResolver.extract_and_expand_entities(model, max_expansion_depth: 5)
      assert entities["outer"] == "value"

      # Circular references should fail regardless of depth
      circular =
        Model.new()
        |> Model.add_entity("a", {:internal, "&b;"})
        |> Model.add_entity("b", {:internal, "&a;"})

      result = EntityResolver.extract_and_expand_entities(circular, max_expansion_depth: 5)
      assert {:error, _} = result
    end
  end
end
