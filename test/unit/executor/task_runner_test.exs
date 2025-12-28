defmodule Nexus.Executor.TaskRunnerTest do
  use ExUnit.Case, async: true

  alias Nexus.Executor.TaskRunner
  alias Nexus.Types.{Command, Task}

  @moduletag :unit

  describe "run/3 with local tasks" do
    test "executes a simple local command" do
      task = %Task{
        name: :test_task,
        on: :local,
        commands: [Command.new("echo hello")]
      }

      {:ok, result} = TaskRunner.run(task, [])

      assert result.task == :test_task
      assert result.status == :ok
      assert result.duration_ms >= 0
      assert length(result.host_results) == 1

      [host_result] = result.host_results
      assert host_result.host == :local
      assert host_result.status == :ok
      assert length(host_result.commands) == 1

      [cmd_result] = host_result.commands
      assert cmd_result.cmd == "echo hello"
      assert cmd_result.status == :ok
      assert String.trim(cmd_result.output) == "hello"
      assert cmd_result.exit_code == 0
      assert cmd_result.attempts == 1
    end

    test "handles non-zero exit codes" do
      task = %Task{
        name: :failing_task,
        on: :local,
        commands: [Command.new("exit 42")]
      }

      {:ok, result} = TaskRunner.run(task, [])

      assert result.status == :error
      [host_result] = result.host_results
      assert host_result.status == :error
      [cmd_result] = host_result.commands
      assert cmd_result.status == :error
      assert cmd_result.exit_code == 42
    end

    test "executes multiple commands in sequence" do
      task = %Task{
        name: :multi_cmd,
        on: :local,
        commands: [
          Command.new("echo first"),
          Command.new("echo second"),
          Command.new("echo third")
        ]
      }

      {:ok, result} = TaskRunner.run(task, [])

      assert result.status == :ok
      [host_result] = result.host_results
      assert length(host_result.commands) == 3

      outputs =
        host_result.commands
        |> Enum.map(& &1.output)
        |> Enum.map(&String.trim/1)

      assert outputs == ["first", "second", "third"]
    end

    test "stops on first failure by default" do
      task = %Task{
        name: :stop_on_fail,
        on: :local,
        commands: [
          Command.new("echo first"),
          Command.new("exit 1"),
          Command.new("echo third")
        ]
      }

      {:ok, result} = TaskRunner.run(task, [])

      assert result.status == :error
      [host_result] = result.host_results

      # Should only have 2 commands (stopped after failure)
      assert length(host_result.commands) == 2

      [first, second] = host_result.commands
      assert first.status == :ok
      assert second.status == :error
    end

    test "continues on error when option set" do
      task = %Task{
        name: :continue_on_fail,
        on: :local,
        commands: [
          Command.new("echo first"),
          Command.new("exit 1"),
          Command.new("echo third")
        ]
      }

      {:ok, result} = TaskRunner.run(task, [], continue_on_error: true)

      assert result.status == :error
      [host_result] = result.host_results

      # Should have all 3 commands
      assert length(host_result.commands) == 3

      [first, second, third] = host_result.commands
      assert first.status == :ok
      assert second.status == :error
      assert third.status == :ok
    end

    test "retries failed commands" do
      # Create a command that will fail but we'll retry
      # Use a file to track attempts
      tmp_file = Path.join(System.tmp_dir!(), "nexus_retry_test_#{:rand.uniform(1_000_000)}")

      task = %Task{
        name: :retry_task,
        on: :local,
        commands: [
          Command.new(
            # This command fails the first time, succeeds the second
            "if [ -f #{tmp_file} ]; then echo success; else touch #{tmp_file} && exit 1; fi",
            retries: 2,
            retry_delay: 10
          )
        ]
      }

      try do
        {:ok, result} = TaskRunner.run(task, [])

        assert result.status == :ok
        [host_result] = result.host_results
        [cmd_result] = host_result.commands
        assert cmd_result.status == :ok
        assert cmd_result.attempts == 2
      after
        File.rm(tmp_file)
      end
    end

    test "handles command timeout" do
      task = %Task{
        name: :timeout_task,
        on: :local,
        commands: [
          Command.new("sleep 10", timeout: 100)
        ]
      }

      {:ok, result} = TaskRunner.run(task, [])

      assert result.status == :error
      [host_result] = result.host_results
      [cmd_result] = host_result.commands
      assert cmd_result.status == :error
    end
  end

  describe "run/3 with remote tasks" do
    test "returns error when no hosts provided for remote task" do
      task = %Task{
        name: :remote_task,
        on: :web,
        commands: [Command.new("echo hello")]
      }

      {:error, reason} = TaskRunner.run(task, [])
      assert reason == {:no_hosts, :web}
    end
  end

  describe "parallel vs serial execution" do
    # These tests verify the strategy setting is respected
    # Actual parallel execution is tested in integration tests

    test "serial strategy runs commands one at a time" do
      task = %Task{
        name: :serial_task,
        on: :local,
        strategy: :serial,
        commands: [
          Command.new("echo one"),
          Command.new("echo two")
        ]
      }

      {:ok, result} = TaskRunner.run(task, [])
      assert result.status == :ok
    end

    test "parallel strategy is the default" do
      task = %Task{name: :default_strategy, on: :local, commands: []}
      assert task.strategy == :parallel
    end
  end

  describe "result structure" do
    test "includes all expected fields in task result" do
      task = %Task{
        name: :result_test,
        on: :local,
        commands: [Command.new("echo test")]
      }

      {:ok, result} = TaskRunner.run(task, [])

      assert Map.has_key?(result, :task)
      assert Map.has_key?(result, :status)
      assert Map.has_key?(result, :duration_ms)
      assert Map.has_key?(result, :host_results)
    end

    test "includes all expected fields in command result" do
      task = %Task{
        name: :cmd_result_test,
        on: :local,
        commands: [Command.new("echo test")]
      }

      {:ok, result} = TaskRunner.run(task, [])
      [host_result] = result.host_results
      [cmd_result] = host_result.commands

      assert Map.has_key?(cmd_result, :cmd)
      assert Map.has_key?(cmd_result, :status)
      assert Map.has_key?(cmd_result, :output)
      assert Map.has_key?(cmd_result, :exit_code)
      assert Map.has_key?(cmd_result, :attempts)
      assert Map.has_key?(cmd_result, :duration_ms)
    end
  end
end
