defmodule NDS_Test do
  defstruct [:a, :b, :c, :d]
end

defmodule NDS_SubTest do
  defstruct [:info, :a, :b]
end

defmodule FnXML.Stream.NativeDataStruct.Format.StructTest do
  use ExUnit.Case

  alias FnXML.Stream.NativeDataStruct, as: NDS

  doctest NDS.Format.Struct

  test "struct test" do
    data = %{"a" => "hi", "b" => %{"info" => "info", a: 1, b: 1}, c: "hi", d: 4}
    meta = NDS.EncoderDefault.encode(data, [tag_from_parent: "foo"])

    tag_map = %{
      a: "a",
      b: fn meta -> NDS.Format.Struct.emit(meta.child_list["b"], NDS_SubTest, tag_map: %{info: "info"}) end
    }
    assert NDS.Format.Struct.emit(meta, NDS_Test, tag_map: tag_map) == %NDS_Test{
      a: "hi", c: "hi", d: 4,
      b: %NDS_SubTest{ info: "info", a: 1, b: 1 }
    }
  end
end
