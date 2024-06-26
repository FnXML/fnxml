defmodule XMLStreamTools.NativeDataType.Meta do

  @moduledoc """
  This Module is a behaviour used to encode a Native Data Type (NDT) to an XML stream.
  """

  defstruct meta_id: :_meta, tag: "undef", namespace: nil, order: nil, tag_from_parent: nil,
    attr_list: [], order_id_list: [], child_list: %{}, text_id_list: [],
    data: nil, opts: nil

  def update(meta, key, value), do: Map.put(meta, key, value)

  @callback meta(map :: map, opts :: term) :: map
end

defmodule XMLStreamTools.NativeDataType.Encoder do

  @moduledoc """
  This Module is used to encode a Native Data Type (NDT) to an XML stream.
  """
  
end


defmodule XMLStreamTools.NativeDataType.Formatter do
  @callback emit(meta :: map) :: list
end


defmodule XMLStreamTools.NativeDataType.Decoder do

  @moduledoc """
  This Module is used to decode an XML stream to a Native Data Type (NDT).
  """
  
end
