defmodule FnXML.Stream.NativeDataStruct.Encoder.DefaultTest do
  use ExUnit.Case

  alias FnXML.Stream.NativeDataStruct, as: NDS
  alias FnXML.Stream.NativeDataStruct.Encoder.Default, as: Encoder

  doctest NDS.Encoder.Default

  describe "sandbox" do
  end
  
  describe "basic" do
    test "encode text" do
      map = %{ :a => 1, "text" => "world" }
      assert NDS.Encoder.encode(map, tag: "hello") == %NDS{
        tag: "hello",
        attributes: [{"a", "1"}],
        content: [{:text, "text", "world"}],
        private: %{ opts: [tag: "hello"], meta: %{} }
      }
    end

    test "encode child" do
      map = %{ :a => 1, "child" => "world" }
      assert NDS.Encoder.encode(map, tag: "hello") == %NDS{
        tag: "hello",
        attributes: [{"a", "1"}],
        content: [
          {:child, "child", %NDS{
              tag: "child",
              content: [{:text, "text", "world"}],
              private: %{meta: %{}, opts: [tag_from_parent: "child"]}
           }
          }
        ],
        private: %{ opts: [tag: "hello"], meta: %{} },
      }
    end
  end

  describe "complex" do
    test "encode 1" do
      map = %{ "text" => [ "hello", "world" ] }

      result = 
        %NDS{private: %{opts: [tag_from_parent: "foo", order: ["text", "text"]]}}
        |> Encoder.meta(map)
        |> Encoder.content(map)

      assert result == %NDS{
        tag: "foo",
        content: [
          {:text, "text", "hello"},
          {:text, "text", "world"}
        ],
        private: %{opts: [tag_from_parent: "foo", order: ["text", "text"]], meta: %{}}
      }
    end
  end

  def elements_match?(list_a, list_b), do: Enum.sort(list_a) == Enum.sort(list_b)

  describe "meta" do
    test "meta encoded to NDS" do
      assert NDS.Encoder.Default.meta(%NDS{}, %{_meta: %{tag: "tg0", namespace: "ns0"}}) == %NDS{
        tag: "tg0",
        namespace: "ns0",
        attributes: [],
        content: [],
        private: %{meta: %{tag: "tg0", namespace: "ns0"}}
      }
    end
  end

  describe "attributes" do
    test "encode attributes" do
      map = %{ :"ns:a" => 1, "text" => "info" }
      assert NDS.Encoder.encode(map, tag: "a") == %NDS{
        tag: "a",
        attributes: [{"ns:a", "1"}],
        content: [{:text, "text", "info"}],
        private: %{ opts: [tag: "a"], meta: %{} }
      }
    end
  end
  
  describe "text keys" do
    test "default" do
      assert NDS.Encoder.Default.text_keys(%NDS{}, %{"t" => "b", a: "1" }) == ["t"]
    end

    test "default 2" do
      assert NDS.Encoder.Default.text_keys(%NDS{}, %{"t" => "b", "#" => "a", "text" => "c" }) == ["text", "t", "#"]
    end

    test "default with non-text excluded" do
      assert NDS.Encoder.Default.text_keys(%NDS{}, %{"a" => "b", "#" => "a", "text" => "c" }) == ["text", "#"]
    end

    test "opts text keys, one key found" do
      nds = %NDS{ private: %{ opts: [text_keys: ["a", "b"]] } }
      assert NDS.Encoder.Default.text_keys(nds, %{"a" => "b", "#" => "a", "text" => "c" }) == ["a"]
    end

    test "opts text keys, all keys found" do
      nds = %NDS{ private: %{ opts: [text_keys: ["a", "b"]] } }
      assert NDS.Encoder.Default.text_keys(nds, %{"a" => "b", "b" => "a", "text" => "c" }) == ["a", "b"]
    end

    test "meta text keys, all keys found" do
      nds = %NDS{ private: %{ meta: %{text_keys: ["a", "b"]} } }
      assert NDS.Encoder.Default.text_keys(nds, %{"a" => "b", "b" => "a", "text" => "c" }) == ["a", "b"]
    end
  end

  describe "valid child" do
    test "invalid child" do
      assert NDS.Encoder.Default.valid_child?(:a) == false
    end
    test "child map" do
      assert NDS.Encoder.Default.valid_child?(%{a: "1"}) == true
    end
    test "child list" do
      assert NDS.Encoder.Default.valid_child?([%{a: "1"}]) == true
    end
    test "child binary" do
      assert NDS.Encoder.Default.valid_child?("a") == true
    end
  end

  describe "key order" do
    test "using opts[:order]" do
      nds = %NDS{ private: %{ opts: [ order: ["a", "b", "c", "d"] ] } }
      assert NDS.Encoder.Default.key_order(nds, %{"a" => "t1", "b" => "t2"}, ["a", "b"], ["a", "b"]) == [{:text, "a", "t1"}, {:text, "b", "t2"}]
    end

    test "using meta[:order]" do
      nds = %NDS{ private: %{ meta: [ order: ["a", "b", "c", "d"] ] } }
      assert NDS.Encoder.Default.key_order(nds, %{"a" => "t1", "b" => "t2"}, ["a", "b"], ["a", "b"]) == [{:text, "a", "t1"}, {:text, "b", "t2"}]
    end

    test "with simple text and child elements" do
      nds = %NDS{}
      data = %{ "a" => "hello", "b" => "world", a: 1}

      assert NDS.Encoder.Default.key_order(nds, data, [], []) == [{:child, "a", "hello"}, {:child, "b","world"}]

      assert NDS.Encoder.Default.key_order(nds, data, [:a], ["b"]) == [{:text, "b", "world"}, {:child, "a", "hello"}]
    end

    test "with text list element" do
      data = %{ "#" => ["hello", "world"]}
      assert NDS.Encoder.Default.key_order(%NDS{}, data, [], ["#"]) == [{:text, "#", "hello"}, {:text, "#", "world"}]
    end
    
    test "with child element" do
      data = %{ "a" => "hello", "b" => %{"info" => "info", a: 1, b: 1}, c: "hi", d: 4}
      assert NDS.Encoder.Default.key_order(%NDS{}, data, [:c], ["a"]) == [{:text, "a", "hello"}, {:child, "b", %{"info" => "info", a: 1, b: 1}}]
    end

    test "with text list element and child element" do
      data = %{ "a" => ["hello", "again"], "b" => %{"info" => "info", a: 1, b: 1}, c: "hi", d: 4}
      assert NDS.Encoder.Default.key_order(%NDS{}, data, [:c, :d], ["a"]) == [{:text, "a", "hello"}, {:text, "a", "again"}, {:child, "b", %{"info" => "info", a: 1, b: 1}}]
    end

    test "no children" do
      data = %{"text" => "not an attribute", a: 1, b: 2}
      assert NDS.Encoder.Default.key_order(%NDS{}, data, [:a, :b, "text"], ["text"]) == []
    end
  end

  describe "child generator:" do
    @tag focus: true
    test "basic children" do
      data = %{ "text" => "info", "c1" => %{"t" => "child", a: 1}, "c2" => %{"t" => "child", a: 2} }
      assert NDS.Encoder.Default.content(%NDS{}, data) |> NDS.TestHelpers.clear_private() == %NDS{
        content: [
          {:text, "text", "info"},
          {:child, "c1", %NDS{tag: "c1", attributes: [{"a", "1"}], content: [{:text, "t", "child"}]}},
          {:child, "c2", %NDS{tag: "c2", attributes: [{"a", "2"}], content: [{:text, "t", "child"}]}}
        ]
      }
    end

    # If a child is a list of maps, each map will be used to create a child element with the same tag name.
    test "child list" do
      data = %{"c" => [%{"t" => "first", a: 1}, %{"t" => "second", a: 2}]}

      assert NDS.Encoder.Default.content(%NDS{}, data) |> NDS.TestHelpers.clear_private() == %NDS{
        content: [
          {:child, "c", %NDS{tag: "c", attributes: [{"a", "1"}], content: [{:text, "t", "first"}]}},
          {:child, "c", %NDS{tag: "c", attributes: [{"a", "2"}], content: [{:text, "t", "second"}]}}
        ]
      }
    end

    # the following two tests suck, they are too long and difficult to follow
    test "nested children" do
      data = %{
        "text" => "info",
        "c1" => %{
          "t" => "child",
          "c1.1" => %{"t" => "child.1", b: 1},
          "c1.2" => %{"t" => "child.2", b: 2},
          a: 1
        },
        "c2" => %{"t" => "child", a: 2}
      }

      assert NDS.Encoder.Default.content(%NDS{}, data) |> NDS.TestHelpers.clear_private() == %NDS{
        content: [
          {:text, "text", "info"},
          {:child, "c1", %NDS{
            tag: "c1",
            attributes: [{"a", "1"}],
            content: [
              {:text, "t", "child"},
              {:child, "c1.1", %NDS{tag: "c1.1", attributes: [{"b", "1"}], content: [{:text, "t", "child.1"}]}},
              {:child, "c1.2", %NDS{tag: "c1.2", attributes: [{"b", "2"}], content: [{:text, "t", "child.2"}]}}
            ]
          }},
          {:child, "c2", %NDS{tag: "c2", attributes: [{"a", "2"}], content: [{:text, "t", "child"}]}}
        ]
      }
    end

    test "nested children with lists" do
      data = %{
        "text" => "info",
        "c1" => %{
          "t" => "child",
          "c1.1" => [%{"t" => "child.1", c: 1}, %{"t" => "child.2", c: 2}],
          a: 1
        },
        "c2" => %{"t" => "child", a: 2}
      }

      assert NDS.Encoder.Default.content(%NDS{}, data) |> NDS.TestHelpers.clear_private() == %NDS{
        content: [
          {:text, "text", "info"},
          {:child, "c1", %NDS{
              tag: "c1",
              attributes: [{"a", "1"}],
              content: [
                {:text, "t", "child"},
                {:child, "c1.1", %NDS{tag: "c1.1", attributes: [{"c", "1"}], content: [{:text, "t", "child.1"}]}},
                {:child, "c1.1", %NDS{tag: "c1.1", attributes: [{"c", "2"}], content: [{:text, "t", "child.2"}]}}
              ]
           }},
          {:child, "c2", %NDS{tag: "c2", attributes: [{"a", "2"}], content: [{:text, "t", "child"}]}}
        ]
      }
    end
  end
end
