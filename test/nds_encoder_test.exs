defmodule FnXML.Stream.NativeDataStruct.EncoderDefaultTest do
  use ExUnit.Case

  alias FnXML.Stream.NativeDataStruct, as: NDS

  doctest NDS.EncoderDefault

  # this is a weird error
  
  describe "basic" do
    test "encode" do
      map = %{ :a => 1, "text" => "world" }
      assert NDS.encode(map, tag: "hello") == [
        open_tag: [tag: "hello", attr_list: [a: 1]],
        text: ["world"],
        close_tag: [tag: "hello"]
      ]
    end
  end

  describe "interleave" do
    test "interleave with empty lists" do
      assert NDS.EncoderDefault.interleave([], []) == []
    end

    test "interleave with equal lists" do
      assert NDS.EncoderDefault.interleave([1, 2, 3], [4, 5, 6]) == [1, 4, 2, 5, 3, 6]
    end

    test "interleave with one empty list" do
      assert NDS.EncoderDefault.interleave([1, 2, 3], []) == [1, 2, 3]
      assert NDS.EncoderDefault.interleave([], [1, 2, 3]) == [1, 2, 3]
    end

    test "interleave with different length lists" do
      assert NDS.EncoderDefault.interleave([1, 2, 3], [4, 5]) == [1, 4, 2, 5, 3]
      assert NDS.EncoderDefault.interleave([1, 2], [4, 5, 6]) == [4, 1, 5, 2, 6]
    end
  end

  def elements_match?(list_a, list_b), do: Enum.sort(list_a) == Enum.sort(list_b)
  
  describe "order generator:" do
    test "with simple text elements" do
      data = %{ "a" => "hello", "b" => "world", a: 1}

      assert %NDS{data: data, attr_list: [a: 1]}
      |> NDS.EncoderDefault.default_order()
      |> elements_match?(["a", "b"])
    end

    test "with simple text list element" do
      data = %{ "a" => ["hello", "world"], a: 1}
      assert %NDS{data: data, attr_list: [a: 1]}
      |> NDS.EncoderDefault.default_order()
      |> elements_match?(["a", "a"])
    end

    test "with child element" do
      data = %{ "a" => "hello", "b" => %{"info" => "info", a: 1, b: 1}, c: "hi", d: 4}
      assert %NDS{data: data}
      |> NDS.EncoderDefault.default_order()
      |> elements_match?(["a", "b", :c, :d])
    end

    test "with text list element and child element" do
      data = %{ "a" => ["hello", "again"], "b" => %{"info" => "info", a: 1, b: 1}, c: "hi", d: 4}
      assert %NDS{data: data}
      |> NDS.EncoderDefault.default_order()
      |> elements_match?(["a", "b", "a", :c, :d])
    end
  end

  describe "child generator:" do
    test "no children" do
      nds = %NDS{data: %{"text" => "not an attribute", a: 1, b: 2}, attr_list: [{:a, 1}, {:b, 2}]}
      assert NDS.EncoderDefault.default_children(nds) == %{}
    end

    test "basic children" do
      nds = %NDS{
        data: %{
          "text" => "info",
          "c1" => %{"t" => "child", a: 1},
          "c2" => %{"t" => "child", a: 2},
          a: 1, b: 2},
        attr_list: [{:a, 1}, {:b, 2}]
      }
      assert NDS.EncoderDefault.default_children(nds) |> NDS.TestHelpers.clear_private() == %{
        "c1" => %NDS{
          tag: "c1",
          namespace: "",
          attr_list: [a: 1],
          order_id_list: ["t"],
          data: %{"t" => "child", a: 1},
        },
        "c2" => %NDS{
          tag: "c2",
          namespace: "",
          attr_list: [a: 2],
          order_id_list: ["t"],
          data: %{"t" => "child", a: 2},
        }
      }
    end

    # If a child is a list of maps, each map will be used to create a child element with the same tag name.
    test "child list" do
      nds = %NDS{
        data: %{"c" => [%{"t" => "first", a: 1}, %{"t" => "second", a: 2}], a: 1, b: 2},
        attr_list: [{:a, 1}, {:b, 2}]
      }
      
      assert NDS.EncoderDefault.default_children(nds) |> NDS.TestHelpers.clear_private() == %{
        "c" => [
        %NDS{
          tag: "c",
          namespace: "",
          attr_list: [a: 1],
          order_id_list: ["t"],
          data: %{"t" => "first", a: 1},
        },
        %NDS{
          tag: "c",
          namespace: "",
          attr_list: [a: 2],
          order_id_list: ["t"],
          data: %{"t" => "second", a: 2},
        }
      ]
      }
    end

    # the following two tests suck, they are too long and difficult to follow
    test "nested children" do
      nds = %NDS{
        data: %{
          "text" => "info",
          "c1" => %{
            "t" => "child",
            "c1.1" => %{"t" => "child.1", b: 1},
            "c1.2" => %{"t" => "child.2", b: 2},
            a: 1
          },
          "c2" => %{"t" => "child", a: 2},
          a: 1, b: 2},
        attr_list: [{:a, 1}, {:b, 2}]
      }
      assert NDS.EncoderDefault.default_children(nds) |> NDS.TestHelpers.clear_private() == %{
        # trust me this is what it should return:
        "c1" => %NDS{
          tag: "c1",
          namespace: "",
          attr_list: [a: 1],
          child_list: %{
            "c1.1" => %NDS{
              tag: "c1.1", namespace: "", attr_list: [b: 1],
              order_id_list: ["t"],
              child_list: %{},
              data: %{:b => 1, "t" => "child.1"},
            },
            "c1.2" => %NDS{
              tag: "c1.2", namespace: "", attr_list: [b: 2],
              order_id_list: ["t"],
              child_list: %{},
              data: %{:b => 2, "t" => "child.2"},
            }
          },
          order_id_list: ["c1.1", "t", "c1.2"],
          data: nds.data["c1"],
        },
        "c2" => %NDS{
          tag: "c2",
          namespace: "",
          attr_list: [a: 2],
          order_id_list: ["t"],
          data: %{"t" => "child", a: 2},
        }
      }
    end

    test "nested children with lists" do
      nds = %NDS{
        data: %{
          "text" => "info",
          "c1" => %{
            "t" => "child",
            "c1.1" => [%{"t" => "child.1", c: 1}, %{"t" => "child.2", c: 2}],
            a: 1
          },
          "c2" => %{"t" => "child", a: 2},
          a: 1, b: 2},
        attr_list: [{:a, 1}, {:b, 2}]
      }
      assert NDS.EncoderDefault.default_children(nds) |> NDS.TestHelpers.clear_private() == %{
        # trust me this is what it should return:
        "c1" => %NDS{
          tag: "c1",
          namespace: "",
          attr_list: [a: 1],
          child_list: %{
            "c1.1" => [
              %NDS{
                tag: "c1.1", namespace: "", attr_list: [c: 1],
                order_id_list: ["t"],
                child_list: %{},
                data: %{"t" => "child.1", c: 1},
              },
              %NDS{
                tag: "c1.1", namespace: "", attr_list: [c: 2],
                order_id_list: ["t"],
                child_list: %{},
                data: %{"t" => "child.2", c: 2},
              }
            ]
          },
          order_id_list: ["c1.1", "t", "c1.1"],
          data: nds.data["c1"],
        },
        "c2" => %NDS{
          tag: "c2",
          namespace: "",
          attr_list: [a: 2],
          order_id_list: ["t"],
          data: %{"t" => "child", a: 2},
        }
      }
    end
    

  end

end
