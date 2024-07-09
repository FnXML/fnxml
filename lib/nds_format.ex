defmodule FnXML.Stream.NativeDataStruct.Formatter do
  @moduledoc """
  This Module defines the NativeDataStruct.Formatter Behaviour which is used to convert
  a Native Data Struct (NDS) to an XML stream.
  """
  
  @callback emit(meta :: map, opts :: list) :: term
end
