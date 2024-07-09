defmodule FnXML.Stream.NativeDataStruct.Encoder do
  @moduledoc """
  This Module defines the NativeDataStruct.Encoder Behaviour which is used to
  encode a Native Data Struct (NDS) to an XML stream.
  """

  alias FnXL.Stream.NativeDataStruct, as: NDS

  @callback encode(meta :: NDS.t) :: list
  @callback encode(map :: map, opts :: term) :: map
end


