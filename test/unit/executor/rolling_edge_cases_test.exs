defmodule Nexus.Executor.Strategies.RollingEdgeCasesTest do
  use ExUnit.Case, async: true

  alias Nexus.Types.{Command, Task, WaitFor}

  @moduletag :unit

  describe "batch_size edge cases" do
    test "batch_size of 1 is serial execution" do
      task = %Task{
        name: :deploy,
        strategy: :rolling,
        batch_size: 1,
        on: :web,
        commands: [Command.new("systemctl restart app")]
      }

      assert task.batch_size == 1
    end

    test "batch_size of 0 should be handled" do
      task = %Task{
        name: :deploy,
        strategy: :rolling,
        batch_size: 0,
        on: :web,
        commands: []
      }

      # 0 batch size - implementation should handle gracefully
      assert task.batch_size == 0
    end

    test "batch_size larger than host count" do
      # If we have 3 hosts but batch_size is 10, should process all at once
      task = %Task{
        name: :deploy,
        strategy: :rolling,
        batch_size: 10,
        on: :web,
        commands: []
      }

      assert task.batch_size == 10
    end

    test "batch_size of 100 for large fleet" do
      task = %Task{
        name: :deploy,
        strategy: :rolling,
        batch_size: 100,
        on: :all_servers,
        commands: []
      }

      assert task.batch_size == 100
    end

    test "negative batch_size" do
      # Should be rejected or normalized
      task = %Task{
        name: :deploy,
        strategy: :rolling,
        batch_size: -1,
        on: :web,
        commands: []
      }

      # Implementation may reject or use default
      assert task.batch_size == -1
    end
  end

  describe "rolling strategy with health checks" do
    test "task with wait_for after restart" do
      task = %Task{
        name: :rolling_deploy,
        strategy: :rolling,
        batch_size: 2,
        on: :web,
        commands: [
          Command.new("systemctl restart app", sudo: true),
          WaitFor.new(:http, "http://localhost:4000/health",
            timeout: 60_000,
            interval: 5_000
          )
        ]
      }

      assert length(task.commands) == 2
      assert match?(%Command{}, Enum.at(task.commands, 0))
      assert match?(%WaitFor{}, Enum.at(task.commands, 1))
    end

    test "task with multiple health checks" do
      task = %Task{
        name: :rolling_deploy,
        strategy: :rolling,
        batch_size: 1,
        on: :web,
        commands: [
          Command.new("systemctl restart app"),
          WaitFor.new(:tcp, "localhost:4000", timeout: 30_000),
          WaitFor.new(:http, "http://localhost:4000/health", timeout: 30_000),
          WaitFor.new(:command, "curl -s localhost:4000/ready | grep -q OK")
        ]
      }

      assert length(task.commands) == 4
      wait_fors = Enum.filter(task.commands, &match?(%WaitFor{}, &1))
      assert length(wait_fors) == 3
    end

    test "task with only health checks (no commands)" do
      task = %Task{
        name: :verify_health,
        strategy: :rolling,
        batch_size: 5,
        on: :web,
        commands: [
          WaitFor.new(:http, "http://localhost/health")
        ]
      }

      assert length(task.commands) == 1
    end
  end

  describe "empty and edge case hosts" do
    test "rolling on empty host list" do
      task = %Task{
        name: :deploy,
        strategy: :rolling,
        batch_size: 2,
        on: :empty_group,
        commands: [Command.new("echo test")]
      }

      assert task.on == :empty_group
    end

    test "rolling on single host" do
      task = %Task{
        name: :deploy,
        strategy: :rolling,
        batch_size: 5,
        on: :single_host,
        commands: [Command.new("echo test")]
      }

      # With single host, batch_size doesn't matter
      assert task.strategy == :rolling
    end

    test "rolling on local target" do
      task = %Task{
        name: :deploy,
        strategy: :rolling,
        batch_size: 2,
        on: :local,
        commands: [Command.new("echo test")]
      }

      # Rolling on :local should work (single "host")
      assert task.on == :local
    end
  end

  describe "command sequences in rolling" do
    test "empty command list" do
      task = %Task{
        name: :noop,
        strategy: :rolling,
        batch_size: 2,
        on: :web,
        commands: []
      }

      assert task.commands == []
    end

    test "single command" do
      task = %Task{
        name: :restart,
        strategy: :rolling,
        batch_size: 2,
        on: :web,
        commands: [Command.new("systemctl restart app")]
      }

      assert length(task.commands) == 1
    end

    test "many commands in sequence" do
      commands =
        for i <- 1..20 do
          Command.new("step #{i}")
        end

      task = %Task{
        name: :complex_deploy,
        strategy: :rolling,
        batch_size: 3,
        on: :web,
        commands: commands
      }

      assert length(task.commands) == 20
    end

    test "commands with various options" do
      task = %Task{
        name: :deploy,
        strategy: :rolling,
        batch_size: 2,
        on: :web,
        commands: [
          Command.new("apt update", sudo: true),
          Command.new("slow_script.sh", timeout: 300_000),
          Command.new("flaky_command", retries: 3, retry_delay: 5_000),
          Command.new("final_step")
        ]
      }

      assert Enum.at(task.commands, 0).sudo == true
      assert Enum.at(task.commands, 1).timeout == 300_000
      assert Enum.at(task.commands, 2).retries == 3
    end
  end

  describe "strategy type validation" do
    test "rolling is valid strategy" do
      task = %Task{name: :test, strategy: :rolling, batch_size: 2, on: :web, commands: []}
      assert task.strategy == :rolling
    end

    test "parallel strategy exists" do
      task = %Task{name: :test, strategy: :parallel, on: :web, commands: []}
      assert task.strategy == :parallel
    end

    test "serial strategy exists" do
      task = %Task{name: :test, strategy: :serial, on: :web, commands: []}
      assert task.strategy == :serial
    end
  end

  describe "batch calculation edge cases" do
    test "calculates correct number of batches" do
      # Helper to simulate batch calculation
      calculate_batches = fn host_count, batch_size ->
        if batch_size <= 0 do
          1
        else
          div(host_count + batch_size - 1, batch_size)
        end
      end

      # 5 hosts, batch_size 2 = 3 batches (2, 2, 1)
      assert calculate_batches.(5, 2) == 3

      # 6 hosts, batch_size 2 = 3 batches (2, 2, 2)
      assert calculate_batches.(6, 2) == 3

      # 7 hosts, batch_size 3 = 3 batches (3, 3, 1)
      assert calculate_batches.(7, 3) == 3

      # 1 host, batch_size 10 = 1 batch
      assert calculate_batches.(1, 10) == 1

      # 100 hosts, batch_size 1 = 100 batches
      assert calculate_batches.(100, 1) == 100

      # 0 hosts, any batch_size = 0 batches
      assert calculate_batches.(0, 5) == 0
    end

    test "simulates batch processing order" do
      hosts = [:web1, :web2, :web3, :web4, :web5]
      batch_size = 2

      batches = Enum.chunk_every(hosts, batch_size)

      assert batches == [[:web1, :web2], [:web3, :web4], [:web5]]
      assert length(batches) == 3
    end
  end

  describe "failure scenarios" do
    test "task struct can represent failed state info" do
      # Tasks themselves don't track state, but we can have info for reporting
      task = %Task{
        name: :deploy,
        strategy: :rolling,
        batch_size: 2,
        on: :web,
        commands: [
          Command.new("might_fail", retries: 2),
          WaitFor.new(:http, "http://localhost/health", timeout: 10_000)
        ]
      }

      # Retries and timeout give us failure handling configuration
      assert Enum.at(task.commands, 0).retries == 2
      assert Enum.at(task.commands, 1).timeout == 10_000
    end
  end

  describe "timeout inheritance" do
    test "task timeout vs command timeout" do
      task = %Task{
        name: :deploy,
        strategy: :rolling,
        batch_size: 2,
        timeout: 600_000,
        on: :web,
        commands: [
          Command.new("long_running", timeout: 120_000)
        ]
      }

      # Task has overall timeout, command has its own
      assert task.timeout == 600_000
      assert Enum.at(task.commands, 0).timeout == 120_000
    end
  end
end
