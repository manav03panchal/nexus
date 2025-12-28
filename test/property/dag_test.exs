defmodule Nexus.Property.DAGTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Nexus.DAG
  alias Nexus.Types.Task

  # Generator for valid task names
  defp task_name do
    gen all(
          prefix <- string(:alphanumeric, min_length: 1, max_length: 10),
          suffix <- integer(1..1000)
        ) do
      String.to_atom("#{prefix}_#{suffix}")
    end
  end

  # Generator for a list of unique task names
  defp unique_task_names(min, max) do
    gen all(
          count <- integer(min..max),
          names <- uniq_list_of(task_name(), min_length: count, max_length: count)
        ) do
      names
    end
  end

  # Generator for acyclic task graph (DAG)
  # Creates tasks where each can only depend on tasks that come before it in the list
  defp acyclic_tasks do
    gen all(names <- unique_task_names(1, 15)) do
      names
      |> Enum.with_index()
      |> Enum.map(fn {name, idx} ->
        # Can only depend on tasks before this one
        possible_deps = Enum.take(names, idx)

        deps =
          if Enum.empty?(possible_deps) do
            []
          else
            # Randomly select 0 to min(3, available) dependencies
            count = :rand.uniform(min(4, length(possible_deps) + 1)) - 1
            Enum.take_random(possible_deps, count)
          end

        %Task{name: name, deps: deps}
      end)
    end
  end

  describe "topological sort properties" do
    property "topological sort includes all tasks exactly once" do
      check all(tasks <- acyclic_tasks()) do
        {:ok, graph} = DAG.build_from_tasks(tasks)
        sorted = DAG.topological_sort(graph)

        task_names = Enum.map(tasks, & &1.name) |> Enum.sort()
        sorted_names = Enum.sort(sorted)

        assert sorted_names == task_names
        assert length(sorted) == length(tasks)
      end
    end

    property "dependencies always come before dependents in topological order" do
      check all(tasks <- acyclic_tasks()) do
        {:ok, graph} = DAG.build_from_tasks(tasks)
        sorted = DAG.topological_sort(graph)
        positions = sorted |> Enum.with_index() |> Map.new()

        for task <- tasks, dep <- task.deps do
          dep_pos = Map.get(positions, dep)
          task_pos = Map.get(positions, task.name)

          # Dependency must come before the task
          assert dep_pos < task_pos,
                 "Expected #{dep} (pos #{dep_pos}) before #{task.name} (pos #{task_pos})"
        end
      end
    end
  end

  describe "execution phases properties" do
    property "execution phases cover all tasks exactly once" do
      check all(tasks <- acyclic_tasks()) do
        {:ok, graph} = DAG.build_from_tasks(tasks)
        phases = DAG.execution_phases(graph)

        all_in_phases = List.flatten(phases) |> Enum.sort()
        task_names = Enum.map(tasks, & &1.name) |> Enum.sort()

        assert all_in_phases == task_names
      end
    end

    property "no task appears in multiple phases" do
      check all(tasks <- acyclic_tasks()) do
        {:ok, graph} = DAG.build_from_tasks(tasks)
        phases = DAG.execution_phases(graph)

        all_tasks = List.flatten(phases)
        unique_tasks = Enum.uniq(all_tasks)

        assert length(all_tasks) == length(unique_tasks)
      end
    end

    property "tasks in earlier phases have no dependencies on later phases" do
      check all(tasks <- acyclic_tasks()) do
        {:ok, graph} = DAG.build_from_tasks(tasks)
        phases = DAG.execution_phases(graph)

        phase_map =
          phases
          |> Enum.with_index()
          |> Enum.flat_map(fn {phase_tasks, idx} ->
            Enum.map(phase_tasks, &{&1, idx})
          end)
          |> Map.new()

        for task <- tasks, dep <- task.deps do
          dep_phase = Map.get(phase_map, dep)
          task_phase = Map.get(phase_map, task.name)

          # Dependency must be in an earlier or same phase
          # (same phase means they're independent of each other)
          assert dep_phase < task_phase,
                 "Dependency #{dep} (phase #{dep_phase}) should be before #{task.name} (phase #{task_phase})"
        end
      end
    end
  end

  describe "dependency query properties" do
    property "dependencies are transitive closure" do
      check all(tasks <- acyclic_tasks()) do
        {:ok, graph} = DAG.build_from_tasks(tasks)

        for task <- tasks do
          deps = DAG.dependencies(graph, task.name) |> MapSet.new()

          # Direct deps should be included
          for direct_dep <- task.deps do
            assert MapSet.member?(deps, direct_dep),
                   "Direct dependency #{direct_dep} missing from #{task.name}'s dependencies"
          end

          # Transitive deps should be included
          for direct_dep <- task.deps do
            transitive = DAG.dependencies(graph, direct_dep)

            for t <- transitive do
              assert MapSet.member?(deps, t),
                     "Transitive dependency #{t} (via #{direct_dep}) missing from #{task.name}'s dependencies"
            end
          end
        end
      end
    end

    property "dependents is inverse of dependencies" do
      check all(tasks <- acyclic_tasks()) do
        {:ok, graph} = DAG.build_from_tasks(tasks)
        task_names = Enum.map(tasks, & &1.name)

        for a <- task_names, b <- task_names, a != b do
          a_deps = DAG.dependencies(graph, a) |> MapSet.new()
          b_dependents = DAG.dependents(graph, b) |> MapSet.new()

          # If b is in a's dependencies, then a should be in b's dependents
          if MapSet.member?(a_deps, b) do
            assert MapSet.member?(b_dependents, a),
                   "If #{b} is dependency of #{a}, then #{a} should be dependent of #{b}"
          end

          # And vice versa
          if MapSet.member?(b_dependents, a) do
            assert MapSet.member?(a_deps, b),
                   "If #{a} is dependent of #{b}, then #{b} should be dependency of #{a}"
          end
        end
      end
    end
  end

  describe "subgraph properties" do
    property "subgraph contains exactly the task and its dependencies" do
      check all(tasks <- acyclic_tasks(), tasks != []) do
        {:ok, graph} = DAG.build_from_tasks(tasks)

        # Pick a random task
        task = Enum.random(tasks)
        subgraph = DAG.subgraph_for(graph, task.name)

        subgraph_tasks = DAG.tasks(subgraph) |> MapSet.new()
        expected = [task.name | DAG.dependencies(graph, task.name)] |> MapSet.new()

        assert subgraph_tasks == expected
      end
    end

    property "subgraph preserves dependency relationships" do
      check all(tasks <- acyclic_tasks(), tasks != []) do
        {:ok, graph} = DAG.build_from_tasks(tasks)

        task = Enum.random(tasks)
        subgraph = DAG.subgraph_for(graph, task.name)

        for t <- DAG.tasks(subgraph) do
          original_deps = DAG.direct_dependencies(graph, t)
          subgraph_deps = DAG.direct_dependencies(subgraph, t)

          # Subgraph should have same deps for tasks that are in the subgraph
          for dep <- subgraph_deps do
            assert dep in original_deps
          end
        end
      end
    end
  end

  describe "cycle detection properties" do
    property "acyclic graphs are detected as acyclic" do
      check all(tasks <- acyclic_tasks()) do
        {:ok, graph} = DAG.build_from_tasks(tasks)
        assert DAG.detect_cycle(graph) == nil
      end
    end

    property "build succeeds for all acyclic task sets" do
      check all(tasks <- acyclic_tasks()) do
        assert {:ok, _graph} = DAG.build_from_tasks(tasks)
      end
    end
  end

  describe "graph size properties" do
    property "graph size equals number of tasks" do
      check all(tasks <- acyclic_tasks()) do
        {:ok, graph} = DAG.build_from_tasks(tasks)
        assert DAG.size(graph) == length(tasks)
      end
    end
  end
end
