# DAG Performance Benchmarks
# Run with: mix run test/performance/dag_benchmark.exs

alias Nexus.DAG
alias Nexus.Types.Task

defmodule DAGBenchmarkHelpers do
  @moduledoc false

  # Generate a chain of N tasks where each depends on the previous
  def generate_chain(n) do
    for i <- 1..n do
      name = String.to_atom("task_#{i}")
      deps = if i == 1, do: [], else: [String.to_atom("task_#{i - 1}")]
      %Task{name: name, deps: deps}
    end
  end

  # Generate tasks with random dependencies (each task can depend on earlier tasks)
  def generate_random_dag(n, max_deps_per_task \\ 3) do
    for i <- 1..n do
      name = String.to_atom("task_#{i}")

      possible_deps =
        if i > 1 do
          for j <- 1..(i - 1), do: String.to_atom("task_#{j}")
        else
          []
        end

      deps =
        if possible_deps == [] do
          []
        else
          count = :rand.uniform(min(max_deps_per_task + 1, length(possible_deps) + 1)) - 1
          Enum.take_random(possible_deps, count)
        end

      %Task{name: name, deps: deps}
    end
  end

  # Generate a diamond pattern repeated N times
  # Each diamond: top -> left, right -> bottom
  def generate_diamonds(n) do
    for i <- 1..n, task <- [:top, :left, :right, :bottom] do
      base_name = String.to_atom("diamond_#{i}_#{task}")

      deps =
        case task do
          :top -> if i == 1, do: [], else: [String.to_atom("diamond_#{i - 1}_bottom")]
          :left -> [String.to_atom("diamond_#{i}_top")]
          :right -> [String.to_atom("diamond_#{i}_top")]
          :bottom -> [String.to_atom("diamond_#{i}_left"), String.to_atom("diamond_#{i}_right")]
        end

      %Task{name: base_name, deps: deps}
    end
  end

  # Generate wide parallel tasks (many independent tasks)
  def generate_parallel(n) do
    for i <- 1..n do
      %Task{name: String.to_atom("parallel_#{i}"), deps: []}
    end
  end

  # Generate wide with single bottleneck
  def generate_funnel(width, depth) do
    # First level: wide parallel
    parallel = for i <- 1..width, do: %Task{name: String.to_atom("wide_#{i}"), deps: []}

    # Middle: funnel down
    funnel = [
      %Task{
        name: :funnel,
        deps: Enum.map(parallel, & &1.name)
      }
    ]

    # Tail: chain after funnel
    tail =
      for i <- 1..depth do
        deps = if i == 1, do: [:funnel], else: [String.to_atom("tail_#{i - 1}")]
        %Task{name: String.to_atom("tail_#{i}"), deps: deps}
      end

    parallel ++ funnel ++ tail
  end
end

IO.puts("=" |> String.duplicate(60))
IO.puts("Nexus DAG Performance Benchmarks")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# Warm up
IO.puts("Warming up...")
{:ok, _} = DAG.build_from_tasks(DAGBenchmarkHelpers.generate_chain(100))
IO.puts("")

# Define benchmark scenarios
scenarios = %{
  "chain_100" => DAGBenchmarkHelpers.generate_chain(100),
  "chain_500" => DAGBenchmarkHelpers.generate_chain(500),
  "chain_1000" => DAGBenchmarkHelpers.generate_chain(1000),
  "random_100" => DAGBenchmarkHelpers.generate_random_dag(100),
  "random_500" => DAGBenchmarkHelpers.generate_random_dag(500),
  "random_1000" => DAGBenchmarkHelpers.generate_random_dag(1000),
  "diamonds_25" => DAGBenchmarkHelpers.generate_diamonds(25),
  "diamonds_100" => DAGBenchmarkHelpers.generate_diamonds(100),
  "parallel_100" => DAGBenchmarkHelpers.generate_parallel(100),
  "parallel_500" => DAGBenchmarkHelpers.generate_parallel(500),
  "funnel_50_10" => DAGBenchmarkHelpers.generate_funnel(50, 10),
  "funnel_100_20" => DAGBenchmarkHelpers.generate_funnel(100, 20)
}

# Build graphs for each scenario
graphs =
  scenarios
  |> Enum.map(fn {name, tasks} ->
    {:ok, graph} = DAG.build_from_tasks(tasks)
    {name, graph}
  end)
  |> Map.new()

IO.puts("-" |> String.duplicate(60))
IO.puts("Scenario Task Counts:")
IO.puts("-" |> String.duplicate(60))

for {name, tasks} <- Enum.sort(scenarios) do
  IO.puts("  #{String.pad_trailing(name, 20)}: #{length(tasks)} tasks")
end

IO.puts("")

# Benchmark: Graph Building
IO.puts("-" |> String.duplicate(60))
IO.puts("Benchmark: Graph Building (build_from_tasks)")
IO.puts("-" |> String.duplicate(60))

Benchee.run(
  scenarios
  |> Enum.map(fn {name, tasks} ->
    {name, fn -> DAG.build_from_tasks(tasks) end}
  end)
  |> Map.new(),
  time: 3,
  memory_time: 1,
  warmup: 1,
  formatters: [Benchee.Formatters.Console]
)

IO.puts("")

# Benchmark: Topological Sort
IO.puts("-" |> String.duplicate(60))
IO.puts("Benchmark: Topological Sort")
IO.puts("-" |> String.duplicate(60))

Benchee.run(
  graphs
  |> Enum.map(fn {name, graph} ->
    {name, fn -> DAG.topological_sort(graph) end}
  end)
  |> Map.new(),
  time: 3,
  memory_time: 1,
  warmup: 1,
  formatters: [Benchee.Formatters.Console]
)

IO.puts("")

# Benchmark: Execution Phases
IO.puts("-" |> String.duplicate(60))
IO.puts("Benchmark: Execution Phases")
IO.puts("-" |> String.duplicate(60))

Benchee.run(
  graphs
  |> Enum.map(fn {name, graph} ->
    {name, fn -> DAG.execution_phases(graph) end}
  end)
  |> Map.new(),
  time: 3,
  memory_time: 1,
  warmup: 1,
  formatters: [Benchee.Formatters.Console]
)

IO.puts("")

# Benchmark: Cycle Detection
IO.puts("-" |> String.duplicate(60))
IO.puts("Benchmark: Cycle Detection")
IO.puts("-" |> String.duplicate(60))

Benchee.run(
  graphs
  |> Enum.map(fn {name, graph} ->
    {name, fn -> DAG.detect_cycle(graph) end}
  end)
  |> Map.new(),
  time: 3,
  memory_time: 1,
  warmup: 1,
  formatters: [Benchee.Formatters.Console]
)

IO.puts("")

# Benchmark: Dependency Queries
IO.puts("-" |> String.duplicate(60))
IO.puts("Benchmark: Dependency Queries (single task)")
IO.puts("-" |> String.duplicate(60))

# Pick a task near the end of each graph for dependency queries
query_benchmarks =
  graphs
  |> Enum.map(fn {name, graph} ->
    tasks = DAG.tasks(graph)
    # Pick a task 3/4 through the sorted list
    target = Enum.at(tasks, div(length(tasks) * 3, 4)) || List.last(tasks)
    {name, fn -> DAG.dependencies(graph, target) end}
  end)
  |> Map.new()

Benchee.run(
  query_benchmarks,
  time: 3,
  memory_time: 1,
  warmup: 1,
  formatters: [Benchee.Formatters.Console]
)

IO.puts("")
IO.puts("=" |> String.duplicate(60))
IO.puts("Performance Targets:")
IO.puts("=" |> String.duplicate(60))
IO.puts("  100 tasks with random deps: <100ms")
IO.puts("  500 tasks: <500ms")
IO.puts("  1000 tasks: <2s")
IO.puts("=" |> String.duplicate(60))
