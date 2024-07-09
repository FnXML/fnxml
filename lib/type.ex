defprotocol FnXML.Type do
  @fallback_to_any true
  @spec type(t) :: Atom.t()
  def type(value)
end

defimpl FnXML.Type, for: Any do
  def type(value) when is_struct(value), do: value.__struct__
end

defimpl FnXML.Type, for: Integer do
  def type(_value), do: Integer
end

defimpl FnXML.Type, for: Float do
  def type(_value), do: Float
end

defimpl FnXML.Type, for: Atom do
  def type(value) when is_boolean(value), do: Boolean
  def type(value) when is_nil(value), do: :nil
  def type(_value), do: Atom
end

defimpl FnXML.Type, for: List do
  def type(_value), do: List
end

defimpl FnXML.Type, for: Map do
  def type(_value), do: Map |> IO.inspect(label: "type:")
end

defimpl FnXML.Type, for: Tuple do
  def type(_value), do: Tuple
end

defimpl FnXML.Type, for: Function do
  def type(_value), do: Funcion
end

defimpl FnXML.Type, for: String do
  def type(_value), do: String
end

defimpl FnXML.Type, for: BitString do
  def type(value) when is_binary(value), do: Binary
  def type(_value), do: BitString
end
