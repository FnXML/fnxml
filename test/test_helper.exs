# Configure ExUnit to skip NIF-specific tests when NIF is disabled
exclude_tags =
  if FnXML.Parser.nif_enabled?() do
    []
  else
    [:nif_parser]
  end

ExUnit.start(exclude: exclude_tags)

# NativeDataStruct helpers commented out - module no longer exists
# defmodule FnXML.Stream.NativeDataStruct.TestHelpers do
#   alias FnXML.Stream.NativeDataStruct, as: NDS
#
#   @doc """
#   clear private data, restore to a value of `%{}`  (primarily for testing)
#   """
#   def clear_private(%NDS{} = nds),
#     do: %NDS{nds | private: %{}, content: clear_private(nds.content)}
#
#   def clear_private(list) when is_list(list), do: Enum.map(list, fn x -> clear_private(x) end)
#   def clear_private({:child, k, %NDS{} = v}), do: {:child, k, clear_private(v)}
#   def clear_private({_, _, _} = item), do: item
# end
