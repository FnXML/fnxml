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
    IO.puts("  macro_blk_ed5:        MacroBlkParser Edition 5 (default, permissive Unicode)")
    IO.puts("  macro_blk_ed5_stream: MacroBlkParser Edition 5 with 64KB chunked streaming")
    IO.puts("  macro_blk_ed4:        MacroBlkParser Edition 4 (strict character validation)")
    IO.puts("  macro_blk_ed4_stream: MacroBlkParser Edition 4 with 64KB chunked streaming")
    IO.puts("  ex_blk_parser:        ExBlkParser (legacy)")
    IO.puts("  fast_ex_blk:          FastExBlkParser (legacy)")
    IO.puts("")

    Benchee.run(
      %{
        # MacroBlkParser - Edition 5 (default, more permissive Unicode)
        "macro_blk_ed5" => fn {xml, _path} ->
          [xml]
          |> FnXML.MacroBlkParser.Edition5.stream()
          |> Enum.to_list()
        end,
        "macro_blk_ed5_stream" => fn {_xml, path} ->
          File.stream!(path, [], 65536)
          |> FnXML.MacroBlkParser.Edition5.stream()
          |> Enum.to_list()
        end,

        # MacroBlkParser - Edition 4 (stricter character validation)
        "macro_blk_ed4" => fn {xml, _path} ->
          [xml]
          |> FnXML.MacroBlkParser.Edition4.stream()
          |> Enum.to_list()
        end,
        "macro_blk_ed4_stream" => fn {_xml, path} ->
          File.stream!(path, [], 65536)
          |> FnXML.MacroBlkParser.Edition4.stream()
          |> Enum.to_list()
        end,

        # Legacy parsers
        "ex_blk_parser" => fn {xml, _path} ->
          [xml]
          |> FnXML.ExBlkParser.stream()
          |> Enum.to_list()
        end,
        "fast_ex_blk" => fn {xml, _path} ->
          [xml]
          |> FnXML.FastExBlkParser.stream()
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
    IO.puts("  macro_blk_ed5:        MacroBlkParser Edition 5 (default, permissive Unicode)")
    IO.puts("  macro_blk_ed5_stream: MacroBlkParser Edition 5 with 64KB chunked streaming")
    IO.puts("  macro_blk_ed4:        MacroBlkParser Edition 4 (strict character validation)")
    IO.puts("  macro_blk_ed4_stream: MacroBlkParser Edition 4 with 64KB chunked streaming")
    IO.puts("  ex_blk_parser:        ExBlkParser (legacy)")
    IO.puts("  fast_ex_blk:          FastExBlkParser (legacy)")
    IO.puts("")

    Benchee.run(
      %{
        # MacroBlkParser - Edition 5 (default, more permissive Unicode)
        "macro_blk_ed5" => fn ->
          [@medium]
          |> FnXML.MacroBlkParser.Edition5.stream()
          |> Enum.to_list()
        end,
        "macro_blk_ed5_stream" => fn ->
          File.stream!(@medium_path, [], 65536)
          |> FnXML.MacroBlkParser.Edition5.stream()
          |> Enum.to_list()
        end,

        # MacroBlkParser - Edition 4 (stricter character validation)
        "macro_blk_ed4" => fn ->
          [@medium]
          |> FnXML.MacroBlkParser.Edition4.stream()
          |> Enum.to_list()
        end,
        "macro_blk_ed4_stream" => fn ->
          File.stream!(@medium_path, [], 65536)
          |> FnXML.MacroBlkParser.Edition4.stream()
          |> Enum.to_list()
        end,

        # Legacy parsers
        "ex_blk_parser" => fn ->
          [@medium]
          |> FnXML.ExBlkParser.stream()
          |> Enum.to_list()
        end,
        "fast_ex_blk" => fn ->
          [@medium]
          |> FnXML.FastExBlkParser.stream()
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
