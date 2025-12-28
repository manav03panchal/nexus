defmodule Nexus.TypesTest do
  use ExUnit.Case, async: true

  alias Nexus.Types.{Command, Config, Host, HostGroup, Task}

  @moduletag :unit

  describe "Host.parse/2" do
    test "parses simple hostname" do
      assert {:ok, host} = Host.parse(:web1, "example.com")
      assert host.name == :web1
      assert host.hostname == "example.com"
      assert host.user == nil
      assert host.port == 22
    end

    test "parses user@hostname" do
      assert {:ok, host} = Host.parse(:web1, "deploy@example.com")
      assert host.name == :web1
      assert host.hostname == "example.com"
      assert host.user == "deploy"
      assert host.port == 22
    end

    test "parses user@hostname:port" do
      assert {:ok, host} = Host.parse(:web1, "deploy@example.com:2222")
      assert host.name == :web1
      assert host.hostname == "example.com"
      assert host.user == "deploy"
      assert host.port == 2222
    end

    test "parses hostname:port" do
      assert {:ok, host} = Host.parse(:web1, "example.com:2222")
      assert host.name == :web1
      assert host.hostname == "example.com"
      assert host.user == nil
      assert host.port == 2222
    end

    test "returns error for invalid format" do
      assert {:error, message} = Host.parse(:web1, "user@host:port:extra")
      assert message =~ "invalid host string format"
    end

    test "handles hostnames with subdomains" do
      assert {:ok, host} = Host.parse(:web1, "web.prod.example.com")
      assert host.hostname == "web.prod.example.com"
    end

    test "handles IP addresses" do
      assert {:ok, host} = Host.parse(:web1, "192.168.1.1")
      assert host.hostname == "192.168.1.1"
    end

    test "handles IP address with port" do
      assert {:ok, host} = Host.parse(:web1, "admin@192.168.1.1:22")
      assert host.hostname == "192.168.1.1"
      assert host.user == "admin"
      assert host.port == 22
    end
  end

  describe "Command.new/2" do
    test "creates command with defaults" do
      cmd = Command.new("echo hello")
      assert cmd.cmd == "echo hello"
      assert cmd.sudo == false
      assert cmd.user == nil
      assert cmd.timeout == 60_000
      assert cmd.retries == 0
      assert cmd.retry_delay == 1_000
    end

    test "creates command with options" do
      cmd = Command.new("apt update", sudo: true, retries: 3, timeout: 120_000)
      assert cmd.cmd == "apt update"
      assert cmd.sudo == true
      assert cmd.retries == 3
      assert cmd.timeout == 120_000
    end

    test "creates command with user" do
      cmd = Command.new("whoami", user: "postgres")
      assert cmd.user == "postgres"
    end
  end

  describe "Task.new/2" do
    test "creates task with defaults" do
      task = Task.new(:build)
      assert task.name == :build
      assert task.deps == []
      assert task.on == :local
      assert task.commands == []
      assert task.timeout == 300_000
      assert task.strategy == :parallel
    end

    test "creates task with options" do
      task = Task.new(:deploy, deps: [:build, :test], on: :web, strategy: :serial)
      assert task.name == :deploy
      assert task.deps == [:build, :test]
      assert task.on == :web
      assert task.strategy == :serial
    end
  end

  describe "Task.add_command/2" do
    test "adds command to task" do
      task = Task.new(:build)
      cmd = Command.new("mix compile")
      task = Task.add_command(task, cmd)

      assert length(task.commands) == 1
      assert hd(task.commands).cmd == "mix compile"
    end

    test "preserves command order" do
      task = Task.new(:build)
      task = Task.add_command(task, Command.new("step 1"))
      task = Task.add_command(task, Command.new("step 2"))
      task = Task.add_command(task, Command.new("step 3"))

      commands = Enum.map(task.commands, & &1.cmd)
      assert commands == ["step 1", "step 2", "step 3"]
    end
  end

  describe "Config" do
    test "creates config with defaults" do
      config = Config.new()
      assert config.default_user == nil
      assert config.default_port == 22
      assert config.connect_timeout == 10_000
      assert config.command_timeout == 60_000
      assert config.max_connections == 5
      assert config.continue_on_error == false
      assert config.hosts == %{}
      assert config.groups == %{}
      assert config.tasks == %{}
    end

    test "creates config with options" do
      config = Config.new(default_user: "deploy", max_connections: 10)
      assert config.default_user == "deploy"
      assert config.max_connections == 10
    end

    test "adds host to config" do
      config = Config.new()
      {:ok, host} = Host.parse(:web1, "example.com")
      config = Config.add_host(config, host)

      assert Map.has_key?(config.hosts, :web1)
      assert config.hosts[:web1].hostname == "example.com"
    end

    test "adds group to config" do
      config = Config.new()
      group = %HostGroup{name: :web, hosts: [:web1, :web2]}
      config = Config.add_group(config, group)

      assert Map.has_key?(config.groups, :web)
      assert config.groups[:web].hosts == [:web1, :web2]
    end

    test "adds task to config" do
      config = Config.new()
      task = Task.new(:build)
      config = Config.add_task(config, task)

      assert Map.has_key?(config.tasks, :build)
    end
  end

  describe "Config.resolve_hosts/2" do
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

    test "returns empty list for :local", %{config: config} do
      assert {:ok, []} = Config.resolve_hosts(config, :local)
    end

    test "resolves single host", %{config: config} do
      assert {:ok, [host]} = Config.resolve_hosts(config, :web1)
      assert host.name == :web1
    end

    test "resolves host group", %{config: config} do
      assert {:ok, hosts} = Config.resolve_hosts(config, :web)
      assert length(hosts) == 2
      names = Enum.map(hosts, & &1.name)
      assert :web1 in names
      assert :web2 in names
    end

    test "returns error for unknown reference", %{config: config} do
      assert {:error, message} = Config.resolve_hosts(config, :unknown)
      assert message =~ "unknown host or group"
    end
  end
end
