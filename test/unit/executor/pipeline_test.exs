defmodule Nexus.Executor.PipelineTest do
  use ExUnit.Case, async: true

  alias Nexus.Executor.Pipeline
  alias Nexus.Types.{Command, Config, Task}

  @moduletag :unit

  describe "run/3 with local tasks" do
    test "runs a single task with no dependencies" do
      config =
        build_config([
          %Task{name: :build, on: :local, commands: [Command.new("echo building")]}
        ])

      {:ok, result} = Pipeline.run(config, [:build])

      assert result.status == :ok
      assert result.tasks_run == 1
      assert result.tasks_succeeded == 1
      assert result.tasks_failed == 0
      assert result.aborted_at == nil
      assert length(result.task_results) == 1
    end

    test "runs tasks with dependencies in correct order" do
      config =
        build_config([
          %Task{name: :build, on: :local, deps: [], commands: [Command.new("echo build")]},
          %Task{name: :test, on: :local, deps: [:build], commands: [Command.new("echo test")]},
          %Task{name: :deploy, on: :local, deps: [:test], commands: [Command.new("echo deploy")]}
        ])

      {:ok, result} = Pipeline.run(config, [:deploy])

      assert result.status == :ok
      assert result.tasks_run == 3
      assert result.tasks_succeeded == 3

      # Verify all tasks ran
      task_names = Enum.map(result.task_results, & &1.task)
      assert :build in task_names
      assert :test in task_names
      assert :deploy in task_names
    end

    test "runs multiple target tasks" do
      config =
        build_config([
          %Task{name: :lint, on: :local, deps: [], commands: [Command.new("echo lint")]},
          %Task{name: :test, on: :local, deps: [], commands: [Command.new("echo test")]}
        ])

      {:ok, result} = Pipeline.run(config, [:lint, :test])

      assert result.status == :ok
      assert result.tasks_run == 2
      assert result.tasks_succeeded == 2
    end

    test "stops on first failure by default" do
      config =
        build_config([
          %Task{name: :build, on: :local, deps: [], commands: [Command.new("exit 1")]},
          %Task{name: :test, on: :local, deps: [:build], commands: [Command.new("echo test")]}
        ])

      {:ok, result} = Pipeline.run(config, [:test])

      assert result.status == :error
      assert result.tasks_failed >= 1
      assert result.aborted_at == :build
    end

    test "continues on error when option set" do
      config =
        build_config([
          %Task{name: :lint, on: :local, deps: [], commands: [Command.new("exit 1")]},
          %Task{name: :test, on: :local, deps: [], commands: [Command.new("echo test")]}
        ])

      {:ok, result} = Pipeline.run(config, [:lint, :test], continue_on_error: true)

      # Both tasks ran because they're in the same phase
      assert result.tasks_run == 2
      assert result.tasks_failed == 1
      assert result.tasks_succeeded == 1
    end

    test "respects config continue_on_error setting" do
      config =
        build_config([
          %Task{name: :lint, on: :local, deps: [], commands: [Command.new("exit 1")]},
          %Task{name: :test, on: :local, deps: [], commands: [Command.new("echo test")]}
        ])
        |> Map.put(:continue_on_error, true)

      {:ok, result} = Pipeline.run(config, [:lint, :test])

      # Should continue because config has continue_on_error: true
      assert result.tasks_run == 2
    end

    test "handles diamond dependencies" do
      #     A
      #    / \
      #   B   C
      #    \ /
      #     D
      config =
        build_config([
          %Task{name: :a, on: :local, deps: [], commands: [Command.new("echo a")]},
          %Task{name: :b, on: :local, deps: [:a], commands: [Command.new("echo b")]},
          %Task{name: :c, on: :local, deps: [:a], commands: [Command.new("echo c")]},
          %Task{name: :d, on: :local, deps: [:b, :c], commands: [Command.new("echo d")]}
        ])

      {:ok, result} = Pipeline.run(config, [:d])

      assert result.status == :ok
      assert result.tasks_run == 4
      assert result.tasks_succeeded == 4
    end
  end

  describe "dry_run/2" do
    test "returns execution plan without running tasks" do
      config =
        build_config([
          %Task{name: :build, on: :local, deps: [], commands: [Command.new("echo build")]},
          %Task{name: :test, on: :local, deps: [:build], commands: [Command.new("echo test")]},
          %Task{name: :deploy, on: :local, deps: [:test], commands: [Command.new("echo deploy")]}
        ])

      {:ok, plan} = Pipeline.dry_run(config, [:deploy])

      assert plan.total_tasks == 3
      assert length(plan.phases) == 3
      assert plan.phases == [[:build], [:test], [:deploy]]
      assert Map.has_key?(plan.task_details, :build)
      assert Map.has_key?(plan.task_details, :test)
      assert Map.has_key?(plan.task_details, :deploy)
    end

    test "shows parallel execution phases" do
      config =
        build_config([
          %Task{name: :build, on: :local, deps: [], commands: []},
          %Task{name: :lint, on: :local, deps: [], commands: []},
          %Task{name: :test, on: :local, deps: [:build], commands: []},
          %Task{name: :deploy, on: :local, deps: [:test, :lint], commands: []}
        ])

      {:ok, plan} = Pipeline.dry_run(config, [:deploy])

      # Phase 1: build and lint (parallel)
      # Phase 2: test
      # Phase 3: deploy
      assert length(plan.phases) == 3

      [phase1, phase2, phase3] = plan.phases
      assert :build in phase1
      assert :lint in phase1
      assert phase2 == [:test]
      assert phase3 == [:deploy]
    end

    test "returns error for unknown task" do
      config = build_config([])

      {:error, reason} = Pipeline.dry_run(config, [:unknown])
      assert reason == {:unknown_tasks, [:unknown]}
    end

    test "returns error for cyclic dependencies" do
      config =
        build_config([
          %Task{name: :a, on: :local, deps: [:b], commands: []},
          %Task{name: :b, on: :local, deps: [:a], commands: []}
        ])

      {:error, {:cycle, _path}} = Pipeline.dry_run(config, [:a])
    end
  end

  describe "validate/2" do
    test "returns :ok for valid tasks" do
      config =
        build_config([
          %Task{name: :build, on: :local, deps: [], commands: []},
          %Task{name: :test, on: :local, deps: [:build], commands: []}
        ])

      assert Pipeline.validate(config, [:test]) == :ok
    end

    test "returns error for unknown tasks" do
      config = build_config([])

      {:error, {:unknown_tasks, missing}} = Pipeline.validate(config, [:unknown])
      assert missing == [:unknown]
    end

    test "returns error for cyclic dependencies" do
      config =
        build_config([
          %Task{name: :a, on: :local, deps: [:b], commands: []},
          %Task{name: :b, on: :local, deps: [:a], commands: []}
        ])

      {:error, {:cycle, _path}} = Pipeline.validate(config, [:a])
    end
  end

  describe "result structure" do
    test "includes all expected fields" do
      config =
        build_config([
          %Task{name: :test, on: :local, commands: [Command.new("echo test")]}
        ])

      {:ok, result} = Pipeline.run(config, [:test])

      assert Map.has_key?(result, :status)
      assert Map.has_key?(result, :duration_ms)
      assert Map.has_key?(result, :tasks_run)
      assert Map.has_key?(result, :tasks_succeeded)
      assert Map.has_key?(result, :tasks_failed)
      assert Map.has_key?(result, :task_results)
      assert Map.has_key?(result, :aborted_at)
    end

    test "duration_ms is positive" do
      config =
        build_config([
          %Task{name: :test, on: :local, commands: [Command.new("sleep 0.1")]}
        ])

      {:ok, result} = Pipeline.run(config, [:test])

      assert result.duration_ms >= 100
    end
  end

  # Helper to build a config from a list of tasks
  defp build_config(tasks) do
    tasks
    |> Enum.reduce(Config.new(), fn task, config ->
      Config.add_task(config, task)
    end)
  end
end
