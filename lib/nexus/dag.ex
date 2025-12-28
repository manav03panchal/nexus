defmodule Nexus.DAG do
  @moduledoc """
  Directed Acyclic Graph for task dependency resolution.

  This module builds a dependency graph from task definitions,
  validates it for cycles, and computes execution order.
  """

  alias Nexus.Types.{Config, Task}

  @type graph :: Graph.t()
  @type cycle_error :: {:cycle, [atom()]}

  @doc """
  Builds a dependency graph from a configuration.

  Returns an error if circular dependencies are detected.

  ## Examples

      iex> config = %Nexus.Types.Config{
      ...>   tasks: %{
      ...>     build: %Nexus.Types.Task{name: :build, deps: []},
      ...>     test: %Nexus.Types.Task{name: :test, deps: [:build]},
      ...>     deploy: %Nexus.Types.Task{name: :deploy, deps: [:test]}
      ...>   }
      ...> }
      iex> {:ok, graph} = Nexus.DAG.build(config)
      iex> Graph.num_vertices(graph)
      3

  """
  @spec build(Config.t()) :: {:ok, graph()} | {:error, cycle_error()}
  def build(%Config{tasks: tasks}) do
    build_from_tasks(Map.values(tasks))
  end

  @doc """
  Builds a dependency graph from a list of tasks.

  Returns an error if circular dependencies are detected.
  """
  @spec build_from_tasks([Task.t()]) :: {:ok, graph()} | {:error, cycle_error()}
  def build_from_tasks(tasks) when is_list(tasks) do
    graph =
      tasks
      |> Enum.reduce(Graph.new(), fn task, g ->
        g = Graph.add_vertex(g, task.name)

        Enum.reduce(task.deps, g, fn dep, acc ->
          # Edge from dependency to task (dep must run before task)
          Graph.add_edge(acc, dep, task.name)
        end)
      end)

    if Graph.is_acyclic?(graph) do
      {:ok, graph}
    else
      cycle = find_cycle_path(graph)
      {:error, {:cycle, cycle}}
    end
  end

  @doc """
  Detects cycles in the graph.

  Returns nil if no cycle exists, or the cycle path if one is found.
  Uses libgraph's built-in cycle detection for correctness.
  """
  @spec detect_cycle(graph()) :: [atom()] | nil
  def detect_cycle(graph) do
    if Graph.is_acyclic?(graph) do
      nil
    else
      find_cycle_path(graph)
    end
  end

  # Finds and returns the cycle path when we know a cycle exists
  defp find_cycle_path(graph) do
    # Use strongly connected components to find cycles
    # A cycle exists in any SCC with more than one vertex,
    # or a single vertex with a self-loop
    sccs = Graph.strong_components(graph)

    cycle_scc =
      Enum.find(sccs, fn scc ->
        case scc do
          [single] -> Graph.edge(graph, single, single) != nil
          _ -> true
        end
      end)

    case cycle_scc do
      nil ->
        # Shouldn't happen if we already confirmed cycle exists
        [:unknown_cycle]

      [single] ->
        # Self-loop
        [single, single]

      vertices ->
        # Find actual cycle path within the SCC
        extract_cycle_from_scc(graph, vertices)
    end
  end

  defp extract_cycle_from_scc(graph, vertices) do
    vertex_set = MapSet.new(vertices)
    start = hd(vertices)

    # DFS to find a cycle path
    case find_path_to_cycle(graph, start, start, vertex_set, MapSet.new(), [start]) do
      {:found, path} -> path
      :not_found -> vertices ++ [hd(vertices)]
    end
  end

  @spec find_path_to_cycle(graph(), atom(), atom(), MapSet.t(), MapSet.t(), [atom()]) ::
          {:found, [atom()]} | :not_found
  # Dialyzer has trouble with MapSet opacity through reduce_while
  @dialyzer {:nowarn_function, find_path_to_cycle: 6}
  defp find_path_to_cycle(graph, target, current, valid_vertices, visited, path) do
    neighbors =
      graph
      |> Graph.out_neighbors(current)
      |> Enum.filter(&MapSet.member?(valid_vertices, &1))

    Enum.reduce_while(neighbors, :not_found, fn neighbor, _acc ->
      check_cycle_neighbor(graph, target, neighbor, valid_vertices, visited, current, path)
    end)
  end

  @spec check_cycle_neighbor(
          graph(),
          atom(),
          atom(),
          MapSet.t(),
          MapSet.t(),
          atom(),
          [atom()]
        ) ::
          {:halt, {:found, [atom()]}} | {:cont, :not_found}
  # Dialyzer has trouble with MapSet opacity through reduce_while
  @dialyzer {:nowarn_function, check_cycle_neighbor: 7}
  defp check_cycle_neighbor(graph, target, neighbor, valid_vertices, visited, current, path) do
    cond do
      neighbor == target and not Enum.empty?(visited) ->
        {:halt, {:found, path ++ [neighbor]}}

      MapSet.member?(visited, neighbor) ->
        {:cont, :not_found}

      true ->
        recurse_cycle_search(graph, target, neighbor, valid_vertices, visited, current, path)
    end
  end

  @spec recurse_cycle_search(
          graph(),
          atom(),
          atom(),
          MapSet.t(),
          MapSet.t(),
          atom(),
          [atom()]
        ) ::
          {:halt, {:found, [atom()]}} | {:cont, :not_found}
  defp recurse_cycle_search(graph, target, neighbor, valid_vertices, visited, current, path) do
    new_visited = MapSet.put(visited, current)
    new_path = path ++ [neighbor]

    case find_path_to_cycle(graph, target, neighbor, valid_vertices, new_visited, new_path) do
      {:found, p} -> {:halt, {:found, p}}
      :not_found -> {:cont, :not_found}
    end
  end

  @doc """
  Returns a topologically sorted list of task names.

  Tasks are ordered such that all dependencies come before their dependents.

  ## Examples

      iex> config = %Nexus.Types.Config{
      ...>   tasks: %{
      ...>     build: %Nexus.Types.Task{name: :build, deps: []},
      ...>     test: %Nexus.Types.Task{name: :test, deps: [:build]},
      ...>     deploy: %Nexus.Types.Task{name: :deploy, deps: [:test]}
      ...>   }
      ...> }
      iex> {:ok, graph} = Nexus.DAG.build(config)
      iex> Nexus.DAG.topological_sort(graph)
      [:build, :test, :deploy]

  """
  @spec topological_sort(graph()) :: [atom()]
  def topological_sort(graph) do
    case Graph.topsort(graph) do
      false -> []
      sorted -> sorted
    end
  end

  @doc """
  Groups tasks into execution phases.

  Tasks within the same phase have no dependencies on each other
  and can be executed in parallel. Phases must be executed in order.

  ## Examples

      iex> config = %Nexus.Types.Config{
      ...>   tasks: %{
      ...>     build: %Nexus.Types.Task{name: :build, deps: []},
      ...>     lint: %Nexus.Types.Task{name: :lint, deps: []},
      ...>     test: %Nexus.Types.Task{name: :test, deps: [:build]},
      ...>     deploy: %Nexus.Types.Task{name: :deploy, deps: [:test, :lint]}
      ...>   }
      ...> }
      iex> {:ok, graph} = Nexus.DAG.build(config)
      iex> Nexus.DAG.execution_phases(graph)
      [[:build, :lint], [:test], [:deploy]]

  """
  @spec execution_phases(graph()) :: [[atom()]]
  def execution_phases(graph) do
    vertices = Graph.vertices(graph)

    if Enum.empty?(vertices) do
      []
    else
      compute_phases(graph, vertices)
    end
  end

  defp compute_phases(graph, vertices) do
    # Calculate the depth (longest path from any root) for each vertex
    depths = calculate_depths(graph, vertices)

    # Group vertices by depth
    vertices
    |> Enum.group_by(fn v -> Map.get(depths, v, 0) end)
    |> Enum.sort_by(fn {depth, _} -> depth end)
    |> Enum.map(fn {_, tasks} -> Enum.sort(tasks) end)
  end

  defp calculate_depths(graph, vertices) do
    # Find roots (vertices with no incoming edges)
    roots = Enum.filter(vertices, fn v -> Graph.in_degree(graph, v) == 0 end)

    # BFS from roots to calculate depths
    initial_depths = Map.new(roots, fn r -> {r, 0} end)
    calculate_depths_bfs(graph, roots, initial_depths)
  end

  defp calculate_depths_bfs(_graph, [], depths), do: depths

  defp calculate_depths_bfs(graph, queue, depths) do
    {current, rest} = {hd(queue), tl(queue)}
    current_depth = Map.fetch!(depths, current)

    neighbors = Graph.out_neighbors(graph, current)

    {new_queue, new_depths} =
      Enum.reduce(neighbors, {rest, depths}, fn neighbor, {q, d} ->
        new_depth = current_depth + 1

        # Only update if we found a longer path
        case Map.get(d, neighbor) do
          nil ->
            {q ++ [neighbor], Map.put(d, neighbor, new_depth)}

          existing when new_depth > existing ->
            {q ++ [neighbor], Map.put(d, neighbor, new_depth)}

          _ ->
            {q, d}
        end
      end)

    calculate_depths_bfs(graph, new_queue, new_depths)
  end

  @doc """
  Returns all dependencies of a task (transitive closure).

  ## Examples

      iex> config = %Nexus.Types.Config{
      ...>   tasks: %{
      ...>     a: %Nexus.Types.Task{name: :a, deps: []},
      ...>     b: %Nexus.Types.Task{name: :b, deps: [:a]},
      ...>     c: %Nexus.Types.Task{name: :c, deps: [:b]}
      ...>   }
      ...> }
      iex> {:ok, graph} = Nexus.DAG.build(config)
      iex> Nexus.DAG.dependencies(graph, :c)
      [:a, :b]

  """
  @spec dependencies(graph(), atom()) :: [atom()]
  def dependencies(graph, task) do
    graph
    |> Graph.reaching([task])
    |> Enum.reject(&(&1 == task))
    |> Enum.sort()
  end

  @doc """
  Returns all tasks that depend on the given task (transitive closure).

  ## Examples

      iex> config = %Nexus.Types.Config{
      ...>   tasks: %{
      ...>     a: %Nexus.Types.Task{name: :a, deps: []},
      ...>     b: %Nexus.Types.Task{name: :b, deps: [:a]},
      ...>     c: %Nexus.Types.Task{name: :c, deps: [:b]}
      ...>   }
      ...> }
      iex> {:ok, graph} = Nexus.DAG.build(config)
      iex> Nexus.DAG.dependents(graph, :a)
      [:b, :c]

  """
  @spec dependents(graph(), atom()) :: [atom()]
  def dependents(graph, task) do
    graph
    |> Graph.reachable([task])
    |> Enum.reject(&(&1 == task))
    |> Enum.sort()
  end

  @doc """
  Returns the direct dependencies of a task (not transitive).
  """
  @spec direct_dependencies(graph(), atom()) :: [atom()]
  def direct_dependencies(graph, task) do
    graph
    |> Graph.in_neighbors(task)
    |> Enum.sort()
  end

  @doc """
  Returns the tasks that directly depend on the given task (not transitive).
  """
  @spec direct_dependents(graph(), atom()) :: [atom()]
  def direct_dependents(graph, task) do
    graph
    |> Graph.out_neighbors(task)
    |> Enum.sort()
  end

  @doc """
  Creates a subgraph containing only the specified task and its dependencies.

  Useful for running a single task with all required predecessors.
  """
  @spec subgraph_for(graph(), atom()) :: graph()
  def subgraph_for(graph, task) do
    required = [task | dependencies(graph, task)]
    Graph.subgraph(graph, required)
  end

  @doc """
  Returns the number of tasks in the graph.
  """
  @spec size(graph()) :: non_neg_integer()
  def size(graph) do
    Graph.num_vertices(graph)
  end

  @doc """
  Returns all task names in the graph.
  """
  @spec tasks(graph()) :: [atom()]
  def tasks(graph) do
    graph
    |> Graph.vertices()
    |> Enum.sort()
  end

  @doc """
  Validates that all task dependencies exist in a known set of valid tasks.

  This is typically already handled by the DSL validator, but
  can be useful for programmatic validation.

  ## Examples

      iex> tasks = [
      ...>   %Nexus.Types.Task{name: :a, deps: []},
      ...>   %Nexus.Types.Task{name: :b, deps: [:a]}
      ...> ]
      iex> Nexus.DAG.validate_deps(tasks)
      :ok

      iex> tasks = [
      ...>   %Nexus.Types.Task{name: :a, deps: [:missing]}
      ...> ]
      iex> Nexus.DAG.validate_deps(tasks)
      {:error, [{:a, :missing}]}

  """
  @spec validate_deps([Task.t()]) :: :ok | {:error, [{atom(), atom()}]}
  def validate_deps(tasks) when is_list(tasks) do
    valid_names = MapSet.new(tasks, & &1.name)

    missing =
      tasks
      |> Enum.flat_map(fn task ->
        task.deps
        |> Enum.reject(&MapSet.member?(valid_names, &1))
        |> Enum.map(&{task.name, &1})
      end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, missing}
    end
  end

  @doc """
  Formats a cycle error into a human-readable message.
  """
  @spec format_cycle_error([atom()]) :: String.t()
  def format_cycle_error(cycle) do
    path = Enum.map_join(cycle, " -> ", &Atom.to_string/1)
    "circular dependency detected: #{path}"
  end
end
