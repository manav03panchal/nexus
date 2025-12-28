defmodule Nexus.DAGTest do
  use ExUnit.Case, async: true

  alias Nexus.DAG
  alias Nexus.Types.{Config, Task}

  describe "build/1" do
    test "builds graph from config with tasks" do
      config = %Config{
        tasks: %{
          build: %Task{name: :build, deps: []},
          test: %Task{name: :test, deps: [:build]},
          deploy: %Task{name: :deploy, deps: [:test]}
        }
      }

      assert {:ok, graph} = DAG.build(config)
      assert DAG.size(graph) == 3
      assert DAG.tasks(graph) == [:build, :deploy, :test]
    end

    test "builds graph from empty config" do
      config = %Config{tasks: %{}}

      assert {:ok, graph} = DAG.build(config)
      assert DAG.size(graph) == 0
      assert DAG.tasks(graph) == []
    end

    test "builds graph with single task" do
      config = %Config{
        tasks: %{
          single: %Task{name: :single, deps: []}
        }
      }

      assert {:ok, graph} = DAG.build(config)
      assert DAG.size(graph) == 1
      assert DAG.tasks(graph) == [:single]
    end

    test "detects simple circular dependency" do
      config = %Config{
        tasks: %{
          a: %Task{name: :a, deps: [:b]},
          b: %Task{name: :b, deps: [:a]}
        }
      }

      assert {:error, {:cycle, cycle}} = DAG.build(config)
      assert length(cycle) >= 2
      assert :a in cycle
      assert :b in cycle
    end

    test "detects self-referential dependency" do
      config = %Config{
        tasks: %{
          a: %Task{name: :a, deps: [:a]}
        }
      }

      assert {:error, {:cycle, cycle}} = DAG.build(config)
      assert :a in cycle
    end

    test "detects longer circular dependency chain" do
      config = %Config{
        tasks: %{
          a: %Task{name: :a, deps: [:c]},
          b: %Task{name: :b, deps: [:a]},
          c: %Task{name: :c, deps: [:b]}
        }
      }

      assert {:error, {:cycle, cycle}} = DAG.build(config)
      assert :a in cycle
      assert :b in cycle
      assert :c in cycle
    end
  end

  describe "build_from_tasks/1" do
    test "builds graph from task list" do
      tasks = [
        %Task{name: :build, deps: []},
        %Task{name: :test, deps: [:build]}
      ]

      assert {:ok, graph} = DAG.build_from_tasks(tasks)
      assert DAG.size(graph) == 2
    end

    test "builds graph from empty list" do
      assert {:ok, graph} = DAG.build_from_tasks([])
      assert DAG.size(graph) == 0
    end
  end

  describe "topological_sort/1" do
    test "returns tasks in valid execution order" do
      config = %Config{
        tasks: %{
          build: %Task{name: :build, deps: []},
          test: %Task{name: :test, deps: [:build]},
          deploy: %Task{name: :deploy, deps: [:test]}
        }
      }

      {:ok, graph} = DAG.build(config)
      sorted = DAG.topological_sort(graph)

      assert sorted == [:build, :test, :deploy]
    end

    test "handles independent tasks" do
      config = %Config{
        tasks: %{
          a: %Task{name: :a, deps: []},
          b: %Task{name: :b, deps: []},
          c: %Task{name: :c, deps: []}
        }
      }

      {:ok, graph} = DAG.build(config)
      sorted = DAG.topological_sort(graph)

      # All tasks should be present, order doesn't matter for independent tasks
      assert Enum.sort(sorted) == [:a, :b, :c]
    end

    test "handles diamond dependencies" do
      #     a
      #    / \
      #   b   c
      #    \ /
      #     d
      config = %Config{
        tasks: %{
          a: %Task{name: :a, deps: []},
          b: %Task{name: :b, deps: [:a]},
          c: %Task{name: :c, deps: [:a]},
          d: %Task{name: :d, deps: [:b, :c]}
        }
      }

      {:ok, graph} = DAG.build(config)
      sorted = DAG.topological_sort(graph)

      # Verify order constraints
      a_idx = Enum.find_index(sorted, &(&1 == :a))
      b_idx = Enum.find_index(sorted, &(&1 == :b))
      c_idx = Enum.find_index(sorted, &(&1 == :c))
      d_idx = Enum.find_index(sorted, &(&1 == :d))

      assert a_idx < b_idx
      assert a_idx < c_idx
      assert b_idx < d_idx
      assert c_idx < d_idx
    end

    test "returns empty list for empty graph" do
      {:ok, graph} = DAG.build_from_tasks([])
      assert DAG.topological_sort(graph) == []
    end

    test "handles long chain" do
      tasks =
        for i <- 1..10 do
          name = String.to_atom("task_#{i}")
          deps = if i == 1, do: [], else: [String.to_atom("task_#{i - 1}")]
          %Task{name: name, deps: deps}
        end

      {:ok, graph} = DAG.build_from_tasks(tasks)
      sorted = DAG.topological_sort(graph)

      # Verify chain order
      for i <- 1..9 do
        current = String.to_atom("task_#{i}")
        next = String.to_atom("task_#{i + 1}")

        assert Enum.find_index(sorted, &(&1 == current)) <
                 Enum.find_index(sorted, &(&1 == next))
      end
    end
  end

  describe "execution_phases/1" do
    test "groups independent tasks in same phase" do
      config = %Config{
        tasks: %{
          a: %Task{name: :a, deps: []},
          b: %Task{name: :b, deps: []},
          c: %Task{name: :c, deps: []}
        }
      }

      {:ok, graph} = DAG.build(config)
      phases = DAG.execution_phases(graph)

      assert phases == [[:a, :b, :c]]
    end

    test "separates dependent tasks into phases" do
      config = %Config{
        tasks: %{
          build: %Task{name: :build, deps: []},
          test: %Task{name: :test, deps: [:build]},
          deploy: %Task{name: :deploy, deps: [:test]}
        }
      }

      {:ok, graph} = DAG.build(config)
      phases = DAG.execution_phases(graph)

      assert phases == [[:build], [:test], [:deploy]]
    end

    test "handles diamond dependency pattern" do
      config = %Config{
        tasks: %{
          build: %Task{name: :build, deps: []},
          lint: %Task{name: :lint, deps: []},
          test: %Task{name: :test, deps: [:build]},
          deploy: %Task{name: :deploy, deps: [:test, :lint]}
        }
      }

      {:ok, graph} = DAG.build(config)
      phases = DAG.execution_phases(graph)

      # Phase 0: build, lint (no deps)
      # Phase 1: test (depends on build)
      # Phase 2: deploy (depends on test and lint)
      assert length(phases) == 3
      assert Enum.at(phases, 0) == [:build, :lint]
      assert Enum.at(phases, 1) == [:test]
      assert Enum.at(phases, 2) == [:deploy]
    end

    test "returns empty list for empty graph" do
      {:ok, graph} = DAG.build_from_tasks([])
      assert DAG.execution_phases(graph) == []
    end

    test "phases cover all tasks exactly once" do
      config = %Config{
        tasks: %{
          a: %Task{name: :a, deps: []},
          b: %Task{name: :b, deps: [:a]},
          c: %Task{name: :c, deps: []},
          d: %Task{name: :d, deps: [:b, :c]},
          e: %Task{name: :e, deps: [:d]}
        }
      }

      {:ok, graph} = DAG.build(config)
      phases = DAG.execution_phases(graph)

      all_tasks = phases |> List.flatten() |> Enum.sort()
      assert all_tasks == [:a, :b, :c, :d, :e]
    end

    test "complex graph with multiple parallel branches" do
      # Structure:
      #   a   b
      #   |   |
      #   c   d
      #    \ /
      #     e
      #     |
      #     f
      config = %Config{
        tasks: %{
          a: %Task{name: :a, deps: []},
          b: %Task{name: :b, deps: []},
          c: %Task{name: :c, deps: [:a]},
          d: %Task{name: :d, deps: [:b]},
          e: %Task{name: :e, deps: [:c, :d]},
          f: %Task{name: :f, deps: [:e]}
        }
      }

      {:ok, graph} = DAG.build(config)
      phases = DAG.execution_phases(graph)

      assert length(phases) == 4
      assert Enum.at(phases, 0) == [:a, :b]
      assert Enum.at(phases, 1) == [:c, :d]
      assert Enum.at(phases, 2) == [:e]
      assert Enum.at(phases, 3) == [:f]
    end
  end

  describe "dependencies/2" do
    test "returns all transitive dependencies" do
      config = %Config{
        tasks: %{
          a: %Task{name: :a, deps: []},
          b: %Task{name: :b, deps: [:a]},
          c: %Task{name: :c, deps: [:b]}
        }
      }

      {:ok, graph} = DAG.build(config)

      assert DAG.dependencies(graph, :a) == []
      assert DAG.dependencies(graph, :b) == [:a]
      assert DAG.dependencies(graph, :c) == [:a, :b]
    end

    test "returns empty list for task with no dependencies" do
      config = %Config{
        tasks: %{
          solo: %Task{name: :solo, deps: []}
        }
      }

      {:ok, graph} = DAG.build(config)
      assert DAG.dependencies(graph, :solo) == []
    end

    test "handles diamond dependencies" do
      config = %Config{
        tasks: %{
          a: %Task{name: :a, deps: []},
          b: %Task{name: :b, deps: [:a]},
          c: %Task{name: :c, deps: [:a]},
          d: %Task{name: :d, deps: [:b, :c]}
        }
      }

      {:ok, graph} = DAG.build(config)
      deps = DAG.dependencies(graph, :d)

      assert :a in deps
      assert :b in deps
      assert :c in deps
      assert length(deps) == 3
    end
  end

  describe "dependents/2" do
    test "returns all tasks that depend on given task" do
      config = %Config{
        tasks: %{
          a: %Task{name: :a, deps: []},
          b: %Task{name: :b, deps: [:a]},
          c: %Task{name: :c, deps: [:b]}
        }
      }

      {:ok, graph} = DAG.build(config)

      assert DAG.dependents(graph, :a) == [:b, :c]
      assert DAG.dependents(graph, :b) == [:c]
      assert DAG.dependents(graph, :c) == []
    end

    test "returns empty list for leaf task" do
      config = %Config{
        tasks: %{
          a: %Task{name: :a, deps: []},
          b: %Task{name: :b, deps: [:a]}
        }
      }

      {:ok, graph} = DAG.build(config)
      assert DAG.dependents(graph, :b) == []
    end
  end

  describe "direct_dependencies/2" do
    test "returns only immediate dependencies" do
      config = %Config{
        tasks: %{
          a: %Task{name: :a, deps: []},
          b: %Task{name: :b, deps: [:a]},
          c: %Task{name: :c, deps: [:b]}
        }
      }

      {:ok, graph} = DAG.build(config)

      assert DAG.direct_dependencies(graph, :c) == [:b]
      assert DAG.direct_dependencies(graph, :b) == [:a]
      assert DAG.direct_dependencies(graph, :a) == []
    end
  end

  describe "direct_dependents/2" do
    test "returns only immediate dependents" do
      config = %Config{
        tasks: %{
          a: %Task{name: :a, deps: []},
          b: %Task{name: :b, deps: [:a]},
          c: %Task{name: :c, deps: [:a]}
        }
      }

      {:ok, graph} = DAG.build(config)

      assert DAG.direct_dependents(graph, :a) == [:b, :c]
      assert DAG.direct_dependents(graph, :b) == []
    end
  end

  describe "subgraph_for/2" do
    test "creates subgraph with task and all dependencies" do
      config = %Config{
        tasks: %{
          a: %Task{name: :a, deps: []},
          b: %Task{name: :b, deps: [:a]},
          c: %Task{name: :c, deps: [:b]},
          d: %Task{name: :d, deps: []}
        }
      }

      {:ok, graph} = DAG.build(config)
      subgraph = DAG.subgraph_for(graph, :c)

      assert DAG.size(subgraph) == 3
      assert DAG.tasks(subgraph) == [:a, :b, :c]
    end

    test "subgraph for task with no deps contains only that task" do
      config = %Config{
        tasks: %{
          a: %Task{name: :a, deps: []},
          b: %Task{name: :b, deps: [:a]}
        }
      }

      {:ok, graph} = DAG.build(config)
      subgraph = DAG.subgraph_for(graph, :a)

      assert DAG.size(subgraph) == 1
      assert DAG.tasks(subgraph) == [:a]
    end
  end

  describe "size/1" do
    test "returns correct task count" do
      config = %Config{
        tasks: %{
          a: %Task{name: :a, deps: []},
          b: %Task{name: :b, deps: []},
          c: %Task{name: :c, deps: []}
        }
      }

      {:ok, graph} = DAG.build(config)
      assert DAG.size(graph) == 3
    end
  end

  describe "tasks/1" do
    test "returns sorted list of task names" do
      config = %Config{
        tasks: %{
          z: %Task{name: :z, deps: []},
          a: %Task{name: :a, deps: []},
          m: %Task{name: :m, deps: []}
        }
      }

      {:ok, graph} = DAG.build(config)
      assert DAG.tasks(graph) == [:a, :m, :z]
    end
  end

  describe "validate_deps/1" do
    test "returns ok for valid task list" do
      tasks = [
        %Task{name: :a, deps: []},
        %Task{name: :b, deps: [:a]}
      ]

      assert DAG.validate_deps(tasks) == :ok
    end

    test "returns error for missing dependency" do
      tasks = [
        %Task{name: :a, deps: [:missing]}
      ]

      assert {:error, [{:a, :missing}]} = DAG.validate_deps(tasks)
    end

    test "returns multiple errors for multiple missing deps" do
      tasks = [
        %Task{name: :a, deps: [:missing1]},
        %Task{name: :b, deps: [:missing2]}
      ]

      {:error, errors} = DAG.validate_deps(tasks)
      assert length(errors) == 2
      assert {:a, :missing1} in errors
      assert {:b, :missing2} in errors
    end
  end

  describe "format_cycle_error/1" do
    test "formats cycle as readable message" do
      cycle = [:a, :b, :c, :a]
      message = DAG.format_cycle_error(cycle)

      assert message == "circular dependency detected: a -> b -> c -> a"
    end

    test "handles two-element cycle" do
      cycle = [:x, :y, :x]
      message = DAG.format_cycle_error(cycle)

      assert message == "circular dependency detected: x -> y -> x"
    end
  end

  describe "detect_cycle/1" do
    test "returns nil for acyclic graph" do
      tasks = [
        %Task{name: :a, deps: []},
        %Task{name: :b, deps: [:a]},
        %Task{name: :c, deps: [:b]}
      ]

      {:ok, graph} = DAG.build_from_tasks(tasks)
      assert DAG.detect_cycle(graph) == nil
    end

    test "returns cycle path for cyclic graph" do
      graph =
        Graph.new()
        |> Graph.add_vertex(:a)
        |> Graph.add_vertex(:b)
        |> Graph.add_edge(:a, :b)
        |> Graph.add_edge(:b, :a)

      cycle = DAG.detect_cycle(graph)
      assert is_list(cycle)
      assert :a in cycle
      assert :b in cycle
    end
  end
end
