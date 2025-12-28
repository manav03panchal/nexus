defmodule Nexus.DSL.ValidatorTest do
  use ExUnit.Case, async: true

  alias Nexus.DSL.Validator
  alias Nexus.Types.{Command, Config, Host, HostGroup, Task}

  @moduletag :unit

  describe "validate/1" do
    test "validates empty config" do
      config = Config.new()
      assert :ok = Validator.validate(config)
    end

    test "validates valid config with hosts and tasks" do
      {:ok, host} = Host.parse(:web1, "example.com")

      config =
        Config.new()
        |> Config.add_host(host)
        |> Config.add_task(Task.new(:build))
        |> Config.add_task(Task.new(:deploy, deps: [:build], on: :web1))

      assert :ok = Validator.validate(config)
    end

    test "returns error for unknown task dependency" do
      config =
        Config.new()
        |> Config.add_task(Task.new(:deploy, deps: [:build]))

      assert {:error, errors} = Validator.validate(config)
      assert length(errors) == 1
      {type, message} = hd(errors)
      assert type == :task_deps
      assert message =~ "unknown task :build"
    end

    test "returns error for unknown host reference in task" do
      config =
        Config.new()
        |> Config.add_task(Task.new(:deploy, on: :web))

      assert {:error, errors} = Validator.validate(config)
      assert length(errors) == 1
      {type, message} = hd(errors)
      assert type == :task_hosts
      assert message =~ "unknown host or group :web"
    end

    test "allows :local as host reference" do
      config =
        Config.new()
        |> Config.add_task(Task.new(:build, on: :local))

      assert :ok = Validator.validate(config)
    end

    test "returns error for unknown host in group" do
      group = %HostGroup{name: :web, hosts: [:web1, :web2]}

      config =
        Config.new()
        |> Config.add_group(group)

      assert {:error, errors} = Validator.validate(config)
      assert length(errors) == 2

      messages = Enum.map(errors, fn {_type, msg} -> msg end)
      assert Enum.any?(messages, &(&1 =~ "unknown host :web1"))
      assert Enum.any?(messages, &(&1 =~ "unknown host :web2"))
    end

    test "validates group with existing hosts" do
      {:ok, host1} = Host.parse(:web1, "web1.example.com")
      {:ok, host2} = Host.parse(:web2, "web2.example.com")
      group = %HostGroup{name: :web, hosts: [:web1, :web2]}

      config =
        Config.new()
        |> Config.add_host(host1)
        |> Config.add_host(host2)
        |> Config.add_group(group)
        |> Config.add_task(Task.new(:deploy, on: :web))

      assert :ok = Validator.validate(config)
    end

    test "returns error for invalid port" do
      config = %{Config.new() | default_port: 0}
      assert {:error, errors} = Validator.validate(config)
      assert Enum.any?(errors, fn {type, _} -> type == :config end)
    end

    test "returns error for port above max" do
      config = %{Config.new() | default_port: 70_000}
      assert {:error, errors} = Validator.validate(config)
      assert Enum.any?(errors, fn {type, msg} -> type == :config and msg =~ "at most" end)
    end

    test "returns error for negative timeout" do
      config = %{Config.new() | connect_timeout: -1}
      assert {:error, errors} = Validator.validate(config)
      assert Enum.any?(errors, fn {type, _} -> type == :config end)
    end

    test "returns error for zero max_connections" do
      config = %{Config.new() | max_connections: 0}
      assert {:error, errors} = Validator.validate(config)
      assert Enum.any?(errors, fn {type, _} -> type == :config end)
    end

    test "validates command timeout" do
      task =
        Task.new(:build)
        |> Task.add_command(%Command{cmd: "test", timeout: 0})

      config = Config.add_task(Config.new(), task)

      assert {:error, errors} = Validator.validate(config)
      assert Enum.any?(errors, fn {type, msg} -> type == :command and msg =~ "timeout" end)
    end

    test "validates command retries with retry_delay" do
      task =
        Task.new(:build)
        |> Task.add_command(%Command{cmd: "test", retries: 3, retry_delay: 0, timeout: 1000})

      config = Config.add_task(Config.new(), task)

      assert {:error, errors} = Validator.validate(config)
      assert Enum.any?(errors, fn {type, msg} -> type == :command and msg =~ "retry_delay" end)
    end

    test "collects multiple errors" do
      group = %HostGroup{name: :web, hosts: [:unknown_host]}

      config =
        Config.new()
        |> Config.add_group(group)
        |> Config.add_task(Task.new(:deploy, deps: [:missing_dep], on: :missing_target))

      assert {:error, errors} = Validator.validate(config)
      # Should have at least 3 errors
      assert length(errors) >= 3
    end
  end

  describe "validate!/1" do
    test "returns config on success" do
      config = Config.new()
      assert %Config{} = Validator.validate!(config)
    end

    test "raises on validation failure" do
      config =
        Config.new()
        |> Config.add_task(Task.new(:deploy, deps: [:unknown]))

      assert_raise ArgumentError, ~r/configuration validation failed/, fn ->
        Validator.validate!(config)
      end
    end
  end

  describe "resolve_task_hosts/2" do
    setup do
      {:ok, host1} = Host.parse(:web1, "web1.example.com")
      {:ok, host2} = Host.parse(:web2, "web2.example.com")
      group = %HostGroup{name: :web, hosts: [:web1, :web2]}

      config =
        Config.new()
        |> Config.add_host(host1)
        |> Config.add_host(host2)
        |> Config.add_group(group)

      {:ok, config: config}
    end

    test "resolves local task to empty list", %{config: config} do
      task = Task.new(:build, on: :local)
      assert {:ok, []} = Validator.resolve_task_hosts(config, task)
    end

    test "resolves single host task", %{config: config} do
      task = Task.new(:deploy, on: :web1)
      assert {:ok, [host]} = Validator.resolve_task_hosts(config, task)
      assert host.name == :web1
    end

    test "resolves group task to all hosts", %{config: config} do
      task = Task.new(:deploy, on: :web)
      assert {:ok, hosts} = Validator.resolve_task_hosts(config, task)
      assert length(hosts) == 2
    end
  end
end
