defmodule FnXML.TypeTest.Struct do
  defstruct [:name, :age]
end

defmodule FnXML.TypeTest do
  use ExUnit.Case

  test "type test" do
    val = %FnXML.TypeTest.Struct{name: "John", age: 30}

    assert FnXML.Type.type(val) == FnXML.TypeTest.Struct
    assert FnXML.Type.type(1) == Integer
    assert FnXML.Type.type(1.0) == Float
    assert FnXML.Type.type(true) == Boolean
    assert FnXML.Type.type(false) == Boolean
    assert FnXML.Type.type(nil) == :nil
    assert FnXML.Type.type(:a) == Atom
    assert FnXML.Type.type([1, 2, 4]) == List
    assert FnXML.Type.type(%{a: 1, b: 2}) == Map
    assert FnXML.Type.type({1, 2, 3}) == Tuple
    assert FnXML.Type.type(&IO.puts/1) == Function
    assert FnXML.Type.type("hello") == String
    assert FnXML.Type.type(<<1::1>>) == BitString
  end
end
