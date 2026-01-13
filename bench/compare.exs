xml = File.read!("bench/data/medium.xml")

# Warmup
for _ <- 1..5 do
  FnXML.FastExBlkParser.stream([xml]) |> Stream.run()
  FnXML.ExBlkParserTest.stream([xml]) |> Stream.run()
end

# FastExBlkParser
{t1, _} = :timer.tc(fn ->
  for _ <- 1..100 do
    FnXML.FastExBlkParser.stream([xml]) |> Stream.run()
  end
end)

# ExBlkParserTest (copy of FastExBlkParser)
{t2, _} = :timer.tc(fn ->
  for _ <- 1..100 do
    FnXML.ExBlkParserTest.stream([xml]) |> Stream.run()
  end
end)

IO.puts("FastExBlkParser: #{Float.round(t1/100/1000, 2)}ms per run")
IO.puts("ExBlkParserTest: #{Float.round(t2/100/1000, 2)}ms per run")
IO.puts("Ratio: #{Float.round(t2/t1, 3)}x")
