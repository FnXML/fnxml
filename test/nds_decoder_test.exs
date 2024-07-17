defmodule FnXML.Stream.NativeDataStruct.DecoderDefaultTest do
  use ExUnit.Case

  alias FnXML.Stream.NativeDataStruct, as: NDS

  doctest NDS.DecoderDefault

  test "open/close tag decode" do
    stream = [open_tag: [tag: "bar", close: true]]
    decode = NDS.DecoderDefault.decode(stream, []) |> Enum.at(0)
    assert decode == %NDS{ tag: "bar", data: %{} }
  end

  test "open/close tag, depth 1 decode" do
    stream = [
      open_tag: [tag: "bar"],
      open_tag: [tag: "foo", close: true],
      close_tag: [tag: "bar"]
    ]
    decode =
      NDS.DecoderDefault.decode(stream, [])
      |> Enum.map(fn x -> x end)
    
    assert decode == [
      %NDS{ tag: "bar", order_id_list: ["foo"], child_list: %{"foo" => %NDS{ tag: "foo" }}},
    ]
  end
  
  test "basic decode" do
    map = %{ :a => "1", "text" => "world" }
    result = (
      NDS.encode(map, tag: "hello")
      |> Stream.into([])
      |> NDS.DecoderDefault.decode([])
      |> Enum.map(fn x -> x end)
    )
    
    assert result == [
      %NDS{
        tag: "hello",
        attr_list: [a: "1"],
        order_id_list: ["text"],
        data: %{"text" => "world", a: "1"}
      }
    ]
  end

  test "decode with child" do
    map = %{
      :a => "1",
      "text" => ["hello", "world"],
      "child" => %{
        :b => "2",
        "text" => "child world"
      }
    }

    result = (
      NDS.encode(map, tag_from_parent: "hello")
      |> Stream.into([])
      |> NDS.DecoderDefault.decode([])
      |> Enum.map(fn x -> x end)
    )
        
    assert result == [
      %NDS{
        tag: "hello",
        attr_list: [a: "1"],
        order_id_list: ["text", "child", "text"],
        child_list: %{
          "child" => %NDS{
            tag: "child",
            attr_list: [b: "2"],
            order_id_list: ["text"],
            data: %{
              :b => "2",
              "text" => "child world"
            }
          }
        },
        data: %{
          :a => "1",
          "text" => ["hello", "world"],
        }
      }
    ]
  end

  test "decode with child list" do
    map = %{
      :a => "1",
      "text" => ["hello", "world"],
      "child" => [
        %{:b => "1", "text" => "child world" },
        %{:b => "2", "text" => "child alt world" }
      ]
    }

    result = (
      NDS.encode(map, tag_from_parent: "hello")
      |> Stream.into([])
      |> NDS.DecoderDefault.decode([])
      |> Enum.map(fn x -> x end)
    )
        
    assert result == [
      %NDS{
        tag: "hello",
        attr_list: [a: "1"],
        order_id_list: ["child", "text", "child", "text"],
        child_list: %{
          "child" => [
            %NDS{
              tag: "child",
              attr_list: [b: "1"],
              order_id_list: ["text"],
              data: %{
                :b => "1",
                "text" => "child world"
              }
            },
            %NDS{
              tag: "child",
              attr_list: [b: "2"],
              order_id_list: ["text"],
              data: %{
                :b => "2",
                "text" => "child alt world"
              }
            }
          ]
        },
        data: %{
          :a => "1",
          "text" => ["hello", "world"],
        }
      }
    ]
  end
  
end
