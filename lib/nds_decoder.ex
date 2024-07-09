defmodule FnXML.Stream.NativeDataStruct.Decoder do

  @moduledoc """
  This Module is used to decode an XML stream to a Native Data Struct (NDS).
  """

  @callback decode(stream :: Stream.t, opts :: term) :: map
  
end
