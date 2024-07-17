ExUnit.start()

defmodule FnXML.Stream.NativeDataStruct.TestHelpers do

  alias FnXML.Stream.NativeDataStruct, as: NDS

  @doc """
  clear private data, restore to a value of `%{}`  (primarily for testing)
  """
  def clear_private(%NDS{} = nds) do
    %NDS{nds | private: %{}}
    |> Map.put(:child_list, clear_private(nds.child_list))
  end
  def clear_private(nds) when is_map(nds) do
    Map.keys(nds)
    |> Enum.map(fn x -> {x, clear_private(nds[x])} end)
    |> Enum.into(%{})
  end
  def clear_private(nds) when is_list(nds) do
    Enum.map(nds, fn x -> clear_private(x) end)
  end
end

