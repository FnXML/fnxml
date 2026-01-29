# Comprehensive Parser Benchmarks
# Run with: mix run bench/all_parsers_bench.exs
#
# Compares FnXML parsers against external libraries

defmodule NullHandler do
  @behaviour Saxy.Handler

  @impl true
  def handle_event(:start_document, _prolog, state), do: {:ok, state}
  @impl true
  def handle_event(:end_document, _data, state), do: {:ok, state}
  @impl true
  def handle_event(:start_element, _data, state), do: {:ok, state}
  @impl true
  def handle_event(:end_element, _name, state), do: {:ok, state}
  @impl true
  def handle_event(:characters, _chars, state), do: {:ok, state}
  @impl true
  def handle_event(:cdata, _cdata, state), do: {:ok, state}
  @impl true
  def handle_event(:comment, _comment, state), do: {:ok, state}
end

# Define parser variants for benchmarking

# Edition 5 variants
defmodule MacroBlk.Compliant.Ed5 do
  use FnXML.Parser.Generator, edition: 5
end

defmodule MacroBlk.Reduced.Ed5 do
  use FnXML.Parser.Generator, edition: 5, disable: [:space, :comment]
end

defmodule MacroBlk.Structural.Ed5 do
  use FnXML.Parser.Generator, edition: 5,
    disable: [:space, :comment, :cdata, :prolog, :characters]
end

# Edition 4 variants
defmodule MacroBlk.Compliant.Ed4 do
  use FnXML.Parser.Generator, edition: 4
end

defmodule MacroBlk.Reduced.Ed4 do
  use FnXML.Parser.Generator, edition: 4, disable: [:space, :comment]
end

defmodule MacroBlk.Structural.Ed4 do
  use FnXML.Parser.Generator, edition: 4,
    disable: [:space, :comment, :cdata, :prolog, :characters]
end

defmodule AllParsersBench do
  @small File.read!("bench/data/small.xml")
  @medium File.read!("bench/data/medium.xml")
  @large File.read!("bench/data/large.xml")

  defp print_file_info do
    IO.puts("Test files:")
    IO.puts("  small.xml:  #{byte_size(@small)} bytes")
    IO.puts("  medium.xml: #{byte_size(@medium)} bytes")
    IO.puts("  large.xml:  #{byte_size(@large)} bytes")
    IO.puts("")
  end

  defp print_parser_info do
    IO.puts("Parser types:")
    IO.puts("  Edition 5: Permissive Unicode character validation")
    IO.puts("  Edition 4: Strict character validation per XML 1.0 4th edition")
    IO.puts("  Legacy:    Original ExBlkParser and FastExBlkParser implementations")
    IO.puts("")
  end

  defp chunk_string(string, chunk_size) do
    string
    |> :binary.bin_to_list()
    |> Enum.chunk_every(chunk_size)
    |> Enum.map(&:binary.list_to_bin/1)
  end

  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("COMPREHENSIVE PARSER BENCHMARKS")
    IO.puts("FnXML parsers vs external libraries")
    IO.puts(String.duplicate("=", 70) <> "\n")

    print_file_info()
    print_parser_info()

    IO.puts("Parsers compared:")
    IO.puts("  External:")
    IO.puts("    - saxy: Highly optimized SAX parser")
    IO.puts("    - erlsom: Erlang XML library")
    IO.puts("    - xmerl: Erlang stdlib DOM parser")
    IO.puts("  FnXML Edition 5 (permissive Unicode):")
    IO.puts("    - macro_blk_compliant_ed5:  All events")
    IO.puts("    - macro_blk_reduced_ed5:    No space/comment")
    IO.puts("    - macro_blk_structural_ed5: Only start/end elements")
    IO.puts("  FnXML Edition 4 (strict validation):")
    IO.puts("    - macro_blk_compliant_ed4:  All events")
    IO.puts("    - macro_blk_reduced_ed4:    No space/comment")
    IO.puts("    - macro_blk_structural_ed4: Only start/end elements")
    IO.puts("  FnXML Legacy:")
    IO.puts("    - fnxml_ex_blk_parser: FnXML.Legacy.ExBlkParser")
    IO.puts("    - fnxml_fnxml_fast_ex_blk: FnXML.Legacy.FastExBlkParser")
    IO.puts("")

    Benchee.run(
      %{
        # External parsers
        "saxy" => fn -> Saxy.parse_string(@medium, NullHandler, nil) end,
        "erlsom" => fn -> :erlsom.simple_form(@medium) end,
        "xmerl" => fn -> :xmerl_scan.string(String.to_charlist(@medium)) end,

        # FnXML MacroBlkParser - Edition 5 variants
        "macro_blk_compliant_ed5" => fn ->
          [@medium] |> MacroBlk.Compliant.Ed5.stream() |> Stream.run()
        end,
        "macro_blk_reduced_ed5" => fn ->
          [@medium] |> MacroBlk.Reduced.Ed5.stream() |> Stream.run()
        end,
        "macro_blk_structural_ed5" => fn ->
          [@medium] |> MacroBlk.Structural.Ed5.stream() |> Stream.run()
        end,

        # FnXML MacroBlkParser - Edition 4 variants
        "macro_blk_compliant_ed4" => fn ->
          [@medium] |> MacroBlk.Compliant.Ed4.stream() |> Stream.run()
        end,
        "macro_blk_reduced_ed4" => fn ->
          [@medium] |> MacroBlk.Reduced.Ed4.stream() |> Stream.run()
        end,
        "macro_blk_structural_ed4" => fn ->
          [@medium] |> MacroBlk.Structural.Ed4.stream() |> Stream.run()
        end,

        # FnXML legacy parsers
        "ex_blk_parser" => fn -> [@medium] |> FnXML.Legacy.ExBlkParser.stream() |> Stream.run() end,
        "fast_ex_blk" => fn -> [@medium] |> FnXML.Legacy.FastExBlkParser.stream() |> Stream.run() end
      },
      warmup: 2,
      time: 5,
      memory_time: 2,
      formatters: [Benchee.Formatters.Console]
    )
  end

  def run_streaming do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("STREAMING PARSER BENCHMARKS")
    IO.puts("Chunked input simulation")
    IO.puts(String.duplicate("=", 70) <> "\n")

    print_file_info()
    print_parser_info()

    medium_chunks = chunk_string(@medium, 4096)
    large_chunks = chunk_string(@large, 4096)

    IO.puts("\n--- MEDIUM FILE STREAMING (#{length(medium_chunks)} x 4KB chunks) ---\n")

    Benchee.run(
      %{
        # FnXML MacroBlkParser - Edition 5
        "compliant_ed5" => fn -> medium_chunks |> MacroBlk.Compliant.Ed5.stream() |> Stream.run() end,
        "reduced_ed5" => fn -> medium_chunks |> MacroBlk.Reduced.Ed5.stream() |> Stream.run() end,
        "structural_ed5" => fn -> medium_chunks |> MacroBlk.Structural.Ed5.stream() |> Stream.run() end,

        # FnXML MacroBlkParser - Edition 4
        "compliant_ed4" => fn -> medium_chunks |> MacroBlk.Compliant.Ed4.stream() |> Stream.run() end,
        "reduced_ed4" => fn -> medium_chunks |> MacroBlk.Reduced.Ed4.stream() |> Stream.run() end,
        "structural_ed4" => fn -> medium_chunks |> MacroBlk.Structural.Ed4.stream() |> Stream.run() end,

        # FnXML legacy parsers
        "ex_blk_parser" => fn -> medium_chunks |> FnXML.Legacy.ExBlkParser.stream() |> Stream.run() end,
        "fast_ex_blk" => fn -> medium_chunks |> FnXML.Legacy.FastExBlkParser.stream() |> Stream.run() end
      },
      warmup: 2,
      time: 5,
      memory_time: 2,
      formatters: [Benchee.Formatters.Console]
    )

    IO.puts("\n--- LARGE FILE STREAMING (#{length(large_chunks)} x 4KB chunks) ---\n")

    Benchee.run(
      %{
        # FnXML MacroBlkParser - Edition 5
        "compliant_ed5" => fn -> large_chunks |> MacroBlk.Compliant.Ed5.stream() |> Stream.run() end,
        "reduced_ed5" => fn -> large_chunks |> MacroBlk.Reduced.Ed5.stream() |> Stream.run() end,
        "structural_ed5" => fn -> large_chunks |> MacroBlk.Structural.Ed5.stream() |> Stream.run() end,

        # FnXML MacroBlkParser - Edition 4
        "compliant_ed4" => fn -> large_chunks |> MacroBlk.Compliant.Ed4.stream() |> Stream.run() end,
        "reduced_ed4" => fn -> large_chunks |> MacroBlk.Reduced.Ed4.stream() |> Stream.run() end,
        "structural_ed4" => fn -> large_chunks |> MacroBlk.Structural.Ed4.stream() |> Stream.run() end,

        # FnXML legacy parsers
        "ex_blk_parser" => fn -> large_chunks |> FnXML.Legacy.ExBlkParser.stream() |> Stream.run() end,
        "fast_ex_blk" => fn -> large_chunks |> FnXML.Legacy.FastExBlkParser.stream() |> Stream.run() end
      },
      warmup: 2,
      time: 5,
      memory_time: 2,
      formatters: [Benchee.Formatters.Console]
    )
  end

  def run_by_size do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("PARSER BENCHMARKS BY FILE SIZE")
    IO.puts(String.duplicate("=", 70) <> "\n")

    print_file_info()
    print_parser_info()

    IO.puts("\n--- SMALL FILE (#{byte_size(@small)} bytes) ---\n")

    Benchee.run(
      %{
        "saxy" => fn -> Saxy.parse_string(@small, NullHandler, nil) end,
        "erlsom" => fn -> :erlsom.simple_form(@small) end,
        "xmerl" => fn -> :xmerl_scan.string(String.to_charlist(@small)) end,
        "macro_blk_compliant_ed5" => fn -> [@small] |> MacroBlk.Compliant.Ed5.stream() |> Stream.run() end,
        "macro_blk_reduced_ed5" => fn -> [@small] |> MacroBlk.Reduced.Ed5.stream() |> Stream.run() end,
        "macro_blk_structural_ed5" => fn -> [@small] |> MacroBlk.Structural.Ed5.stream() |> Stream.run() end,
        "macro_blk_compliant_ed4" => fn -> [@small] |> MacroBlk.Compliant.Ed4.stream() |> Stream.run() end,
        "macro_blk_reduced_ed4" => fn -> [@small] |> MacroBlk.Reduced.Ed4.stream() |> Stream.run() end,
        "macro_blk_structural_ed4" => fn -> [@small] |> MacroBlk.Structural.Ed4.stream() |> Stream.run() end,
        "fnxml_ex_blk_parser" => fn -> [@small] |> FnXML.Legacy.ExBlkParser.stream() |> Stream.run() end,
        "fnxml_fast_ex_blk" => fn -> [@small] |> FnXML.Legacy.FastExBlkParser.stream() |> Stream.run() end
      },
      warmup: 1,
      time: 3,
      memory_time: 1,
      formatters: [Benchee.Formatters.Console]
    )

    IO.puts("\n--- MEDIUM FILE (#{byte_size(@medium)} bytes) ---\n")

    Benchee.run(
      %{
        "saxy" => fn -> Saxy.parse_string(@medium, NullHandler, nil) end,
        "erlsom" => fn -> :erlsom.simple_form(@medium) end,
        "xmerl" => fn -> :xmerl_scan.string(String.to_charlist(@medium)) end,
        "macro_blk_compliant_ed5" => fn -> [@medium] |> MacroBlk.Compliant.Ed5.stream() |> Stream.run() end,
        "macro_blk_reduced_ed5" => fn -> [@medium] |> MacroBlk.Reduced.Ed5.stream() |> Stream.run() end,
        "macro_blk_structural_ed5" => fn -> [@medium] |> MacroBlk.Structural.Ed5.stream() |> Stream.run() end,
        "macro_blk_compliant_ed4" => fn -> [@medium] |> MacroBlk.Compliant.Ed4.stream() |> Stream.run() end,
        "macro_blk_reduced_ed4" => fn -> [@medium] |> MacroBlk.Reduced.Ed4.stream() |> Stream.run() end,
        "macro_blk_structural_ed4" => fn -> [@medium] |> MacroBlk.Structural.Ed4.stream() |> Stream.run() end,
        "fnxml_ex_blk_parser" => fn -> [@medium] |> FnXML.Legacy.ExBlkParser.stream() |> Stream.run() end,
        "fnxml_fast_ex_blk" => fn -> [@medium] |> FnXML.Legacy.FastExBlkParser.stream() |> Stream.run() end
      },
      warmup: 1,
      time: 3,
      memory_time: 1,
      formatters: [Benchee.Formatters.Console]
    )

    IO.puts("\n--- LARGE FILE (#{byte_size(@large)} bytes) ---\n")

    Benchee.run(
      %{
        "saxy" => fn -> Saxy.parse_string(@large, NullHandler, nil) end,
        "erlsom" => fn -> :erlsom.simple_form(@large) end,
        "xmerl" => fn -> :xmerl_scan.string(String.to_charlist(@large)) end,
        "macro_blk_compliant_ed5" => fn -> [@large] |> MacroBlk.Compliant.Ed5.stream() |> Stream.run() end,
        "macro_blk_reduced_ed5" => fn -> [@large] |> MacroBlk.Reduced.Ed5.stream() |> Stream.run() end,
        "macro_blk_structural_ed5" => fn -> [@large] |> MacroBlk.Structural.Ed5.stream() |> Stream.run() end,
        "macro_blk_compliant_ed4" => fn -> [@large] |> MacroBlk.Compliant.Ed4.stream() |> Stream.run() end,
        "macro_blk_reduced_ed4" => fn -> [@large] |> MacroBlk.Reduced.Ed4.stream() |> Stream.run() end,
        "macro_blk_structural_ed4" => fn -> [@large] |> MacroBlk.Structural.Ed4.stream() |> Stream.run() end,
        "fnxml_ex_blk_parser" => fn -> [@large] |> FnXML.Legacy.ExBlkParser.stream() |> Stream.run() end,
        "fnxml_fast_ex_blk" => fn -> [@large] |> FnXML.Legacy.FastExBlkParser.stream() |> Stream.run() end
      },
      warmup: 1,
      time: 3,
      memory_time: 1,
      formatters: [Benchee.Formatters.Console]
    )
  end

  def run_ed5_only do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("MACRO_BLK_PARSER EDITION 5 VARIANTS BENCHMARK")
    IO.puts("All Edition 5 variants on medium file")
    IO.puts(String.duplicate("=", 70) <> "\n")

    IO.puts("File: medium.xml (#{byte_size(@medium)} bytes)")
    IO.puts("")
    IO.puts("Variants:")
    IO.puts("  compliant:  All events (default)")
    IO.puts("  reduced:    No space/comment events")
    IO.puts("  structural: Only start/end elements")
    IO.puts("")

    Benchee.run(
      %{
        "compliant" => fn -> [@medium] |> MacroBlk.Compliant.Ed5.stream() |> Stream.run() end,
        "reduced" => fn -> [@medium] |> MacroBlk.Reduced.Ed5.stream() |> Stream.run() end,
        "structural" => fn -> [@medium] |> MacroBlk.Structural.Ed5.stream() |> Stream.run() end
      },
      warmup: 2,
      time: 5,
      memory_time: 2,
      formatters: [Benchee.Formatters.Console]
    )
  end
end

case System.argv() do
  ["--by-size"] -> AllParsersBench.run_by_size()
  ["--ed5"] -> AllParsersBench.run_ed5_only()
  _ -> AllParsersBench.run()
end
