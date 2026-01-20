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

defmodule AllParsersBench do
  @small File.read!("bench/data/small.xml")
  @medium File.read!("bench/data/medium.xml")
  @large File.read!("bench/data/large.xml")

  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("COMPREHENSIVE PARSER BENCHMARKS")
    IO.puts("FnXML parsers vs external libraries")
    IO.puts(String.duplicate("=", 70) <> "\n")

    IO.puts("File sizes:")
    IO.puts("  small.xml:  #{byte_size(@small)} bytes")
    IO.puts("  medium.xml: #{byte_size(@medium)} bytes")
    IO.puts("  large.xml:  #{byte_size(@large)} bytes")
    IO.puts("")

    IO.puts("Parsers compared:")
    IO.puts("  External:")
    IO.puts("    - saxy: Highly optimized SAX parser")
    IO.puts("    - erlsom: Erlang XML library")
    IO.puts("    - xmerl: Erlang stdlib DOM parser")
    IO.puts("  FnXML:")
    IO.puts("    - macro_blk_ed5: MacroBlkParser Edition 5 (default, permissive Unicode)")
    IO.puts("    - macro_blk_ed4: MacroBlkParser Edition 4 (strict character validation)")
    IO.puts("    - ex_blk_parser: ExBlkParser (legacy)")
    IO.puts("    - fast_ex_blk: FastExBlkParser (legacy)")
    IO.puts("")

    Benchee.run(
      %{
        # External parsers
        "saxy" => fn -> Saxy.parse_string(@medium, NullHandler, nil) end,
        "erlsom" => fn -> :erlsom.simple_form(@medium) end,
        "xmerl" => fn -> :xmerl_scan.string(String.to_charlist(@medium)) end,

        # FnXML MacroBlkParser
        "macro_blk_ed5" => fn ->
          [@medium] |> FnXML.MacroBlkParser.Edition5.stream() |> Stream.run()
        end,
        "macro_blk_ed4" => fn ->
          [@medium] |> FnXML.MacroBlkParser.Edition4.stream() |> Stream.run()
        end,

        # FnXML legacy parsers
        "ex_blk_parser" => fn ->
          [@medium] |> FnXML.ExBlkParser.stream() |> Stream.run()
        end,
        "fast_ex_blk" => fn ->
          [@medium] |> FnXML.FastExBlkParser.stream() |> Stream.run()
        end
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

    IO.puts("\n--- SMALL FILE (#{byte_size(@small)} bytes) ---\n")

    Benchee.run(
      %{
        "saxy" => fn -> Saxy.parse_string(@small, NullHandler, nil) end,
        "erlsom" => fn -> :erlsom.simple_form(@small) end,
        "xmerl" => fn -> :xmerl_scan.string(String.to_charlist(@small)) end,
        "macro_blk_ed5" => fn -> [@small] |> FnXML.MacroBlkParser.Edition5.stream() |> Stream.run() end,
        "macro_blk_ed4" => fn -> [@small] |> FnXML.MacroBlkParser.Edition4.stream() |> Stream.run() end,
        "ex_blk_parser" => fn -> [@small] |> FnXML.ExBlkParser.stream() |> Stream.run() end,
        "fast_ex_blk" => fn -> [@small] |> FnXML.FastExBlkParser.stream() |> Stream.run() end
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
        "macro_blk_ed5" => fn -> [@medium] |> FnXML.MacroBlkParser.Edition5.stream() |> Stream.run() end,
        "macro_blk_ed4" => fn -> [@medium] |> FnXML.MacroBlkParser.Edition4.stream() |> Stream.run() end,
        "ex_blk_parser" => fn -> [@medium] |> FnXML.ExBlkParser.stream() |> Stream.run() end,
        "fast_ex_blk" => fn -> [@medium] |> FnXML.FastExBlkParser.stream() |> Stream.run() end
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
        "macro_blk_ed5" => fn -> [@large] |> FnXML.MacroBlkParser.Edition5.stream() |> Stream.run() end,
        "macro_blk_ed4" => fn -> [@large] |> FnXML.MacroBlkParser.Edition4.stream() |> Stream.run() end,
        "ex_blk_parser" => fn -> [@large] |> FnXML.ExBlkParser.stream() |> Stream.run() end,
        "fast_ex_blk" => fn -> [@large] |> FnXML.FastExBlkParser.stream() |> Stream.run() end
      },
      warmup: 1,
      time: 3,
      memory_time: 1,
      formatters: [Benchee.Formatters.Console]
    )
  end
end

case System.argv() do
  ["--by-size"] -> AllParsersBench.run_by_size()
  _ -> AllParsersBench.run()
end
