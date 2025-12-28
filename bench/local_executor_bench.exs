# Local Executor Performance Benchmarks
# Run with: mix run bench/local_executor_bench.exs

alias Nexus.Executor.Local

IO.puts("=" |> String.duplicate(60))
IO.puts("Nexus Local Executor Performance Benchmarks")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# Warm up
IO.puts("Warming up...")
Local.run("echo warmup")
IO.puts("")

# Benchmark: Sequential Commands
IO.puts("-" |> String.duplicate(60))
IO.puts("Benchmark: Sequential Command Execution")
IO.puts("-" |> String.duplicate(60))

sequential_100 = fn ->
  for _ <- 1..100 do
    {:ok, _, 0} = Local.run("echo test")
  end
end

Benchee.run(
  %{
    "100 sequential echo commands" => sequential_100
  },
  time: 5,
  memory_time: 1,
  warmup: 1,
  formatters: [Benchee.Formatters.Console]
)

IO.puts("")

# Benchmark: Parallel Commands
IO.puts("-" |> String.duplicate(60))
IO.puts("Benchmark: Parallel Command Execution")
IO.puts("-" |> String.duplicate(60))

parallel_100 = fn ->
  1..100
  |> Enum.map(fn _ ->
    Task.async(fn -> Local.run("echo test") end)
  end)
  |> Enum.map(&Task.await/1)
end

Benchee.run(
  %{
    "100 parallel echo commands" => parallel_100
  },
  time: 5,
  memory_time: 1,
  warmup: 1,
  formatters: [Benchee.Formatters.Console]
)

IO.puts("")

# Benchmark: Large Output
IO.puts("-" |> String.duplicate(60))
IO.puts("Benchmark: Large Output Handling")
IO.puts("-" |> String.duplicate(60))

Benchee.run(
  %{
    "1KB output (seq 1 100)" => fn -> Local.run("seq 1 100") end,
    "10KB output (seq 1 1000)" => fn -> Local.run("seq 1 1000") end,
    "100KB output (seq 1 10000)" => fn -> Local.run("seq 1 10000") end,
    "1MB output (seq 1 100000)" => fn -> Local.run("seq 1 100000") end
  },
  time: 5,
  memory_time: 1,
  warmup: 1,
  formatters: [Benchee.Formatters.Console]
)

IO.puts("")

# Benchmark: Streaming vs Buffered
IO.puts("-" |> String.duplicate(60))
IO.puts("Benchmark: Streaming vs Buffered (10KB output)")
IO.puts("-" |> String.duplicate(60))

Benchee.run(
  %{
    "buffered (run)" => fn ->
      Local.run("seq 1 1000")
    end,
    "streaming (run_streaming)" => fn ->
      Local.run_streaming("seq 1 1000", [], fn _chunk -> :ok end)
    end
  },
  time: 5,
  memory_time: 1,
  warmup: 1,
  formatters: [Benchee.Formatters.Console]
)

IO.puts("")

# Comparison: Sequential vs Parallel speedup
IO.puts("-" |> String.duplicate(60))
IO.puts("Benchmark: Sequential vs Parallel (50 commands)")
IO.puts("-" |> String.duplicate(60))

Benchee.run(
  %{
    "50 sequential" => fn ->
      for _ <- 1..50, do: Local.run("echo test")
    end,
    "50 parallel" => fn ->
      1..50
      |> Enum.map(fn _ -> Task.async(fn -> Local.run("echo test") end) end)
      |> Enum.map(&Task.await/1)
    end
  },
  time: 5,
  memory_time: 1,
  warmup: 1,
  formatters: [Benchee.Formatters.Console]
)

IO.puts("")
IO.puts("=" |> String.duplicate(60))
IO.puts("Benchmark Complete")
IO.puts("=" |> String.duplicate(60))
