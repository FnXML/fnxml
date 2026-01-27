# Parse Benchmarks
# Run with: mix run bench/parse_bench.exs
#           mix run bench/parse_bench.exs --quick
#
# Compares FnXML parsing performance against Saxy, erlsom, and xmerl

defmodule NullHandler do
  @moduledoc "Minimal Saxy handler for fair comparison"
  @behaviour Saxy.Handler

  @impl true
  def handle_event(:start_document, _prolog, state), do: {:ok, state}

  @impl true
  def handle_event(:end_document, _data, state), do: {:ok, state}

  @impl true
  def handle_event(:start_element, {_name, _attrs}, state), do: {:ok, state}

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

defmodule ParseBench do
  @small_path "bench/data/small.xml"
  @medium_path "bench/data/medium.xml"
  @large_path "bench/data/large.xml"

  @small File.read!(@small_path)
  @medium File.read!(@medium_path)
  @large File.read!(@large_path)

  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("PARSE BENCHMARKS")
    IO.puts("Comparing: FnXML vs Saxy (string & stream) vs others")
    IO.puts(String.duplicate("=", 70) <> "\n")

    IO.puts("File sizes:")
    IO.puts("  small.xml:  #{byte_size(@small)} bytes")
    IO.puts("  medium.xml: #{byte_size(@medium)} bytes")
    IO.puts("  large.xml:  #{byte_size(@large)} bytes")
    IO.puts("")

    IO.puts("Parsers:")
    IO.puts("  Edition 5 (permissive Unicode):")
    IO.puts("    macro_blk_compliant_ed5:  All events (default)")
    IO.puts("    macro_blk_reduced_ed5:    No space/comment events")
    IO.puts("    macro_blk_structural_ed5: Only start/end elements")
    IO.puts("  Edition 4 (strict character validation):")
    IO.puts("    macro_blk_compliant_ed4:  All events (default)")
    IO.puts("    macro_blk_reduced_ed4:    No space/comment events")
    IO.puts("    macro_blk_structural_ed4: Only start/end elements")
    IO.puts("  Legacy:")
    IO.puts("    fnxml_parser_orig:        FnXML.Legacy.ParserOrig (dead code candidate)")
    IO.puts("    fnxml_ex_blk_parser:      FnXML.Legacy.ExBlkParser")
    IO.puts("    fnxml_fnxml_fast_ex_blk:        FnXML.Legacy.FastExBlkParser")
    IO.puts("")

    Benchee.run(
      %{
        # MacroBlkParser - Edition 5 variants
        "macro_blk_compliant_ed5" => fn {xml, _path} ->
          [xml] |> MacroBlk.Compliant.Ed5.stream() |> Enum.to_list()
        end,
        "macro_blk_reduced_ed5" => fn {xml, _path} ->
          [xml] |> MacroBlk.Reduced.Ed5.stream() |> Enum.to_list()
        end,
        "macro_blk_structural_ed5" => fn {xml, _path} ->
          [xml] |> MacroBlk.Structural.Ed5.stream() |> Enum.to_list()
        end,

        # MacroBlkParser - Edition 4 variants
        "macro_blk_compliant_ed4" => fn {xml, _path} ->
          [xml] |> MacroBlk.Compliant.Ed4.stream() |> Enum.to_list()
        end,
        "macro_blk_reduced_ed4" => fn {xml, _path} ->
          [xml] |> MacroBlk.Reduced.Ed4.stream() |> Enum.to_list()
        end,
        "macro_blk_structural_ed4" => fn {xml, _path} ->
          [xml] |> MacroBlk.Structural.Ed4.stream() |> Enum.to_list()
        end,

        # Legacy parsers
        "fnxml_parser_orig" => fn {xml, _path} ->
          FnXML.Legacy.ParserOrig.parse(xml) |> Enum.to_list()
        end,
        "fnxml_ex_blk_parser" => fn {xml, _path} ->
          [xml]
          |> FnXML.Legacy.ExBlkParser.stream()
          |> Enum.to_list()
        end,
        "fnxml_fast_ex_blk" => fn {xml, _path} ->
          [xml]
          |> FnXML.Legacy.FastExBlkParser.stream()
          |> Enum.to_list()
        end,

        # Saxy
        "saxy_string" => fn {xml, _path} ->
          Saxy.parse_string(xml, NullHandler, nil)
        end,
        "saxy_stream" => fn {_xml, path} ->
          File.stream!(path, [], 65536)
          |> Saxy.parse_stream(NullHandler, nil)
        end,

        # Others
        "erlsom" => fn {xml, _path} ->
          :erlsom.simple_form(xml)
        end,
        "xmerl" => fn {xml, _path} ->
          :xmerl_scan.string(String.to_charlist(xml))
        end
      },
      inputs: %{
        "small" => {@small, @small_path},
        "medium" => {@medium, @medium_path},
        "large" => {@large, @large_path}
      },
      warmup: 2,
      time: 5,
      memory_time: 2,
      formatters: [
        Benchee.Formatters.Console
      ]
    )
  end

  def run_quick do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("QUICK PARSE BENCHMARKS (medium file only)")
    IO.puts("Comparing: FnXML vs Saxy (string & stream) vs others")
    IO.puts(String.duplicate("=", 70) <> "\n")

    IO.puts("File: medium.xml (#{byte_size(@medium)} bytes)\n")

    IO.puts("Parsers:")
    IO.puts("  Edition 5 (permissive Unicode):")
    IO.puts("    macro_blk_compliant_ed5:  All events (default)")
    IO.puts("    macro_blk_reduced_ed5:    No space/comment events")
    IO.puts("    macro_blk_structural_ed5: Only start/end elements")
    IO.puts("  Edition 4 (strict character validation):")
    IO.puts("    macro_blk_compliant_ed4:  All events (default)")
    IO.puts("    macro_blk_reduced_ed4:    No space/comment events")
    IO.puts("    macro_blk_structural_ed4: Only start/end elements")
    IO.puts("  Legacy:")
    IO.puts("    fnxml_parser_orig:        FnXML.Legacy.ParserOrig (dead code candidate)")
    IO.puts("    fnxml_ex_blk_parser:      FnXML.Legacy.ExBlkParser")
    IO.puts("    fnxml_fnxml_fast_ex_blk:        FnXML.Legacy.FastExBlkParser")
    IO.puts("")

    Benchee.run(
      %{
        # MacroBlkParser - Edition 5 variants
        "macro_blk_compliant_ed5" => fn ->
          [@medium] |> MacroBlk.Compliant.Ed5.stream() |> Enum.to_list()
        end,
        "macro_blk_reduced_ed5" => fn ->
          [@medium] |> MacroBlk.Reduced.Ed5.stream() |> Enum.to_list()
        end,
        "macro_blk_structural_ed5" => fn ->
          [@medium] |> MacroBlk.Structural.Ed5.stream() |> Enum.to_list()
        end,

        # MacroBlkParser - Edition 4 variants
        "macro_blk_compliant_ed4" => fn ->
          [@medium] |> MacroBlk.Compliant.Ed4.stream() |> Enum.to_list()
        end,
        "macro_blk_reduced_ed4" => fn ->
          [@medium] |> MacroBlk.Reduced.Ed4.stream() |> Enum.to_list()
        end,
        "macro_blk_structural_ed4" => fn ->
          [@medium] |> MacroBlk.Structural.Ed4.stream() |> Enum.to_list()
        end,

        # Legacy parsers
        "fnxml_parser_orig" => fn ->
          FnXML.Legacy.ParserOrig.parse(@medium) |> Enum.to_list()
        end,
        "fnxml_ex_blk_parser" => fn ->
          [@medium]
          |> FnXML.Legacy.ExBlkParser.stream()
          |> Enum.to_list()
        end,
        "fnxml_fast_ex_blk" => fn ->
          [@medium]
          |> FnXML.Legacy.FastExBlkParser.stream()
          |> Enum.to_list()
        end,

        # Saxy
        "saxy_string" => fn ->
          Saxy.parse_string(@medium, NullHandler, nil)
        end,
        "saxy_stream" => fn ->
          File.stream!(@medium_path, [], 65536)
          |> Saxy.parse_stream(NullHandler, nil)
        end,

        # Others
        "erlsom" => fn ->
          :erlsom.simple_form(@medium)
        end,
        "xmerl" => fn ->
          :xmerl_scan.string(String.to_charlist(@medium))
        end
      },
      warmup: 1,
      time: 3,
      memory_time: 1,
      formatters: [
        Benchee.Formatters.Console
      ]
    )
  end
end

# Run full benchmarks by default, or quick with --quick flag
if "--quick" in System.argv() do
  ParseBench.run_quick()
else
  ParseBench.run()
end
