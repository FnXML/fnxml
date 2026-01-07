defmodule FnXML.Stream.NativeDataStruct.Format.XMLTest do
  use ExUnit.Case

  alias FnXML.Stream.NativeDataStruct, as: NDS

  doctest NDS.Format.XML

  describe "Format NDS to XML Stream:" do
    test "value" do
      result = NDS.encode("world", tag: "hello")
      # New format: {:open, tag, attrs, loc}, {:text, content, loc}, {:close, tag}
      assert match?(
        [{:open, "hello", [], nil}, {:text, "world", nil}, {:close, "hello"}],
        result
      )
    end

    test "basic map" do
      map = %{"text" => "hi", :a => "1"}

      result = NDS.encode(map, tag: "foo")
      assert match?({:open, "foo", [{"a", "1"}], nil}, Enum.at(result, 0))
      assert match?({:text, "hi", nil}, Enum.at(result, 1))
      assert match?({:close, "foo"}, Enum.at(result, 2))
    end

    test "nested map" do
      map = %{
        :a => "1",
        "text" => "world",
        "child" => %{
          :b => "2",
          "text" => "child world"
        }
      }

      result = NDS.encode(map, tag_from_parent: "hello")
      assert match?({:open, "hello", [{"a", "1"}], nil}, Enum.at(result, 0))
      assert match?({:text, "world", nil}, Enum.at(result, 1))
      assert match?({:open, "child", [{"b", "2"}], nil}, Enum.at(result, 2))
      assert match?({:text, "child world", nil}, Enum.at(result, 3))
      assert match?({:close, "child"}, Enum.at(result, 4))
      assert match?({:close, "hello"}, Enum.at(result, 5))
    end

    test "nested map with child list" do
      map = %{
        :a => "1",
        "text" => "world",
        "child" => [
          %{:b => "1", "text" => "child world"},
          %{:b => "2", "text" => "child alt world"},
          %{:b => "3", "text" => "child other world"}
        ]
      }

      result = NDS.encode(map, tag_from_parent: "hello")
      # Verify structure
      assert match?({:open, "hello", [{"a", "1"}], nil}, Enum.at(result, 0))

      # Find all child opens
      children = Enum.filter(result, fn
        {:open, "child", _, nil} -> true
        _ -> false
      end)
      assert length(children) == 3
    end
  end
end
