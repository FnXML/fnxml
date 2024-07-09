defmodule FnXML.Stream.NativeDataStruct.EncoderDefaultTest do
  use ExUnit.Case

  alias FnXML.Stream.NativeDataStruct, as: NDS

#  doctest NDS.EncoderDefault

  test "basic encode" do
    map = %{ :a => 1, "text" => "world" }
    assert NDS.encode(map, tag: "hello") == [
      open_tag: [tag: "hello", attr_list: [a: 1]],
      text: ["world"],
      close_tag: [tag: "hello"]
    ]
  end

  describe "rezip" do
    test "rezip with empty lists" do
      assert NDS.EncoderDefault.rezip([], []) == []
    end

    test "rezip with equal lists" do
      assert NDS.EncoderDefault.rezip([1, 2, 3], [4, 5, 6]) == [1, 4, 2, 5, 3, 6]
    end

    test "rezip with one empty list" do
      assert NDS.EncoderDefault.rezip([1, 2, 3], []) == [1, 2, 3]
      assert NDS.EncoderDefault.rezip([], [1, 2, 3]) == [1, 2, 3]
    end

    test "rezip with different length lists" do
      assert NDS.EncoderDefault.rezip([1, 2, 3], [4, 5]) == [1, 4, 2, 5, 3]
      assert NDS.EncoderDefault.rezip([1, 2], [4, 5, 6]) == [4, 1, 5, 2, 6]
    end
  end

  def elements_match?(list_a, list_b), do: Enum.sort(list_a) == Enum.sort(list_b)
  
  describe "order generator:" do
    test "with simple text elements" do
      data = %{ "a" => "hello", "b" => "world", a: 1}

      assert %NDS{data: data, attr_list: [a: 1]}
      |> NDS.EncoderDefault.order()
      |> elements_match?(["a", "b"])
    end

    test "with simple text list element" do
      data = %{ "a" => ["hello", "world"], a: 1}
      assert %NDS{data: data, attr_list: [a: 1]}
      |> NDS.EncoderDefault.order()
      |> elements_match?(["a", "a"])
    end

    test "with child element" do
      data = %{ "a" => "hello", "b" => %{"info" => "info", a: 1, b: 1}, c: "hi", d: 4}
      assert %NDS{data: data}
      |> NDS.EncoderDefault.order()
      |> elements_match?(["a", "b", :c, :d])
    end

    test "with text list element and child element" do
      data = %{ "a" => ["hello", "again"], "b" => %{"info" => "info", a: 1, b: 1}, c: "hi", d: 4}
      assert %NDS{data: data}
      |> NDS.EncoderDefault.order()
      |> elements_match?(["a", "b", "a", :c, :d])
    end
  end

  describe "child generator:" do
    test "no children" do
      meta = %NDS{data: %{"text" => "not an attribute", a: 1, b: 2}, attr_list: [{:a, 1}, {:b, 2}]}
      assert NDS.EncoderDefault.children(meta, nil) == %{}
    end

    test "basic children" do
      meta = %NDS{
        data: %{
          "text" => "info",
          "c1" => %{"t" => "child", a: 1},
          "c2" => %{"t" => "child", a: 2},
          a: 1, b: 2},
        attr_list: [{:a, 1}, {:b, 2}]
      }
      assert NDS.EncoderDefault.children(meta, nil) == %{
        "c1" => %NDS{
          meta_id: :_meta,
          tag: "c1",
          tag_from_parent: "c1",
          namespace: "",
          attr_list: [a: 1],
          order_id_list: ["t"],
          data: %{"t" => "child", a: 1},
          opts: [tag_from_parent: "c1"]
        },
        "c2" => %NDS{
          meta_id: :_meta,
          tag: "c2",
          tag_from_parent: "c2",
          namespace: "",
          attr_list: [a: 2],
          order_id_list: ["t"],
          data: %{"t" => "child", a: 2},
          opts: [tag_from_parent: "c2"]
        }
      }
    end

    # If a child is a list of maps, each map will be used to create a child element with the same tag name.
    test "child list" do
      meta = %NDS{
        data: %{"c" => [%{"t" => "first", a: 1}, %{"t" => "second", a: 2}], a: 1, b: 2},
        attr_list: [{:a, 1}, {:b, 2}]
      }
      
      assert NDS.EncoderDefault.children(meta, ["c"]) == %{
        "c" => [
        %NDS{
          meta_id: :_meta,
          tag: "c",
          tag_from_parent: "c",
          namespace: "",
          attr_list: [a: 1],
          order_id_list: ["t"],
          data: %{"t" => "first", a: 1},
          opts: [tag_from_parent: "c"]
        },
        %NDS{
          meta_id: :_meta,
          tag: "c",
          tag_from_parent: "c",
          namespace: "",
          attr_list: [a: 2],
          order_id_list: ["t"],
          data: %{"t" => "second", a: 2},
          opts: [tag_from_parent: "c"]
        }
      ]
      }
    end

    # the following two tests suck, they are too long and difficult to follow
    test "nested children" do
      meta = %NDS{
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
      assert NDS.EncoderDefault.children(meta, nil) == %{
        # trust me this is what it should return:
        "c1" => %NDS{
          meta_id: :_meta,
          tag: "c1",
          tag_from_parent: "c1",
          namespace: "",
          attr_list: [a: 1],
          child_list: %{
            "c1.1" => %NDS{
              meta_id: :_meta, tag: "c1.1", namespace: "", tag_from_parent: "c1.1", attr_list: [b: 1],
              order_id_list: ["t"],
              child_list: %{},
              data: %{:b => 1, "t" => "child.1"},
              opts: [tag_from_parent: "c1.1", tag_from_parent: "c1"]
            },
            "c1.2" => %NDS{
              meta_id: :_meta, tag: "c1.2", namespace: "", tag_from_parent: "c1.2", attr_list: [b: 2],
              order_id_list: ["t"],
              child_list: %{},
              data: %{:b => 2, "t" => "child.2"},
              opts: [tag_from_parent: "c1.2", tag_from_parent: "c1"]
            }
          },
          order_id_list: ["c1.1", "t", "c1.2"],
          data: meta.data["c1"],
          opts: [tag_from_parent: "c1"]
        },
        "c2" => %NDS{
          meta_id: :_meta,
          tag: "c2",
          tag_from_parent: "c2",
          namespace: "",
          attr_list: [a: 2],
          order_id_list: ["t"],
          data: %{"t" => "child", a: 2},
          opts: [tag_from_parent: "c2"]
        }
      }
    end

    test "nested children with lists" do
      meta = %NDS{
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
      assert NDS.EncoderDefault.children(meta, nil) == %{
        # trust me this is what it should return:
        "c1" => %NDS{
          meta_id: :_meta,
          tag: "c1",
          tag_from_parent: "c1",
          namespace: "",
          attr_list: [a: 1],
          child_list: %{
            "c1.1" => [
              %NDS{
                meta_id: :_meta, tag: "c1.1", namespace: "", tag_from_parent: "c1.1", attr_list: [c: 1],
                order_id_list: ["t"],
                child_list: %{},
                data: %{"t" => "child.1", c: 1},
                opts: [tag_from_parent: "c1.1", tag_from_parent: "c1"]
              },
              %NDS{
                meta_id: :_meta, tag: "c1.1", namespace: "", tag_from_parent: "c1.1", attr_list: [c: 2],
                order_id_list: ["t"],
                child_list: %{},
                data: %{"t" => "child.2", c: 2},
                opts: [tag_from_parent: "c1.1", tag_from_parent: "c1"]
              }
            ]
          },
          order_id_list: ["c1.1", "c1.1", "t"],
          data: meta.data["c1"],
          opts: [tag_from_parent: "c1"]
        },
        "c2" => %NDS{
          meta_id: :_meta,
          tag: "c2",
          tag_from_parent: "c2",
          namespace: "",
          attr_list: [a: 2],
          order_id_list: ["t"],
          data: %{"t" => "child", a: 2},
          opts: [tag_from_parent: "c2"]
        }
      }
    end
    

  end

end
