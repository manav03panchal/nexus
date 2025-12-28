defmodule Nexus.Integration.PipelineTest do
  @moduledoc """
  Integration tests for the Pipeline module with remote SSH execution.

  These tests require Docker containers running SSH servers.
  Start them with: docker compose -f docker-compose.test.yml up -d
  """

  use ExUnit.Case, async: false

  alias Nexus.Executor.Pipeline
  alias Nexus.Types.{Command, Config, Host, Task}

  @moduletag :integration

  @ssh_password_host %Host{
    name: :ssh_password,
    hostname: "localhost",
    user: "testuser",
    port: 2232
  }

  @ssh_key_host %Host{
    name: :ssh_key,
    hostname: "localhost",
    user: "testuser",
    port: 2233
  }

  setup do
    # Ensure containers are running
    case check_ssh_containers() do
      :ok -> :ok
      {:error, reason} -> skip_test(reason)
    end

    :ok
  end

  describe "run/3 with remote tasks" do
    @tag timeout: 120_000
    test "executes remote task on single host" do
      config =
        Config.new()
        |> Config.add_host(@ssh_password_host)
        |> Config.add_task(%Task{
          name: :remote_echo,
          on: :ssh_password,
          commands: [Command.new("echo hello from remote")]
        })

      {:ok, result} = Pipeline.run(config, [:remote_echo], ssh_opts: ssh_password_opts())

      assert result.status == :ok
      assert result.tasks_run == 1
      assert result.tasks_succeeded == 1

      [task_result] = result.task_results
      assert task_result.task == :remote_echo
      [host_result] = task_result.host_results
      assert host_result.host == :ssh_password
      [cmd_result] = host_result.commands
      assert String.contains?(cmd_result.output, "hello from remote")
    end

    @tag timeout: 120_000
    test "executes pipeline with mixed local and remote tasks" do
      config =
        Config.new()
        |> Config.add_host(@ssh_password_host)
        |> Config.add_task(%Task{
          name: :local_build,
          on: :local,
          commands: [Command.new("echo local build complete")]
        })
        |> Config.add_task(%Task{
          name: :remote_deploy,
          on: :ssh_password,
          deps: [:local_build],
          commands: [Command.new("echo deployed")]
        })

      {:ok, result} = Pipeline.run(config, [:remote_deploy], ssh_opts: ssh_password_opts())

      assert result.status == :ok
      assert result.tasks_run == 2
      assert result.tasks_succeeded == 2

      task_names = Enum.map(result.task_results, & &1.task)
      assert :local_build in task_names
      assert :remote_deploy in task_names
    end

    @tag timeout: 120_000
    test "handles remote task failure" do
      config =
        Config.new()
        |> Config.add_host(@ssh_password_host)
        |> Config.add_task(%Task{
          name: :failing_remote,
          on: :ssh_password,
          commands: [Command.new("exit 42")]
        })

      {:ok, result} = Pipeline.run(config, [:failing_remote], ssh_opts: ssh_password_opts())

      assert result.status == :error
      assert result.tasks_failed == 1
    end

    @tag timeout: 120_000
    test "executes on multiple hosts in parallel" do
      # This test uses both SSH containers
      config =
        Config.new()
        |> Config.add_host(@ssh_password_host)
        |> Config.add_host(@ssh_key_host)
        |> Config.add_group(%Nexus.Types.HostGroup{
          name: :all_hosts,
          hosts: [:ssh_password, :ssh_key]
        })
        |> Config.add_task(%Task{
          name: :parallel_task,
          on: :all_hosts,
          strategy: :parallel,
          commands: [Command.new("hostname")]
        })

      # Need to provide SSH opts that work for both
      # For this test, we use key auth since ssh_key host requires it
      ssh_opts = ssh_key_opts()

      {:ok, result} = Pipeline.run(config, [:parallel_task], ssh_opts: ssh_opts)

      # At least one should succeed (key host)
      assert result.tasks_run == 1

      [task_result] = result.task_results
      # Should have attempted both hosts
      assert length(task_result.host_results) == 2
    end
  end

  describe "dry_run/2 with remote config" do
    test "returns execution plan for remote tasks" do
      config =
        Config.new()
        |> Config.add_host(@ssh_password_host)
        |> Config.add_task(%Task{
          name: :build,
          on: :local,
          commands: [Command.new("make build")]
        })
        |> Config.add_task(%Task{
          name: :deploy,
          on: :ssh_password,
          deps: [:build],
          commands: [Command.new("./deploy.sh")]
        })

      {:ok, plan} = Pipeline.dry_run(config, [:deploy])

      assert plan.total_tasks == 2
      assert plan.phases == [[:build], [:deploy]]
    end
  end

  # Helper functions

  defp check_ssh_containers do
    # Try to connect to the password SSH container
    case :gen_tcp.connect(~c"localhost", 2232, [], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, reason} ->
        {:error, "SSH container not available: #{inspect(reason)}"}
    end
  end

  defp skip_test(reason) do
    IO.puts("\nSkipping integration test: #{reason}")
    IO.puts("Start containers with: docker compose -f docker-compose.test.yml up -d\n")
    ExUnit.configure(exclude: [:integration])
    :ok
  end

  defp ssh_password_opts do
    [
      password: "testpass",
      silently_accept_hosts: true
    ]
  end

  defp ssh_key_opts do
    key_path = Path.expand("test/fixtures/ssh_keys")

    [
      identity: Path.join(key_path, "id_ed25519"),
      silently_accept_hosts: true
    ]
  end
end
