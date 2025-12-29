defmodule Nexus.Preflight.CheckerTest do
  use ExUnit.Case, async: true

  alias Nexus.Preflight.Checker
  alias Nexus.Types.{Command, Config, Host, Task}

  describe "run/1" do
    test "returns ok when all checks pass with valid config" do
      path = write_valid_config_no_hosts()

      result = Checker.run(config_path: path, skip_checks: [:hosts, :ssh])

      assert {:ok, report} = result
      assert report.status == :ok
      assert is_integer(report.duration_ms)
      assert report.checks != []
      assert Enum.all?(report.checks, fn c -> c.status in [:passed, :skipped] end)

      File.rm!(path)
    end

    test "returns error when config file not found" do
      result = Checker.run(config_path: "nonexistent.exs")

      assert {:error, report} = result
      assert report.status == :error

      config_check = Enum.find(report.checks, fn c -> c.name == :config end)
      assert config_check.status == :failed
      assert config_check.message =~ "no such file" or config_check.message =~ "not found"
    end

    test "skips specified checks" do
      path = write_valid_config()

      result = Checker.run(config_path: path, skip_checks: [:hosts, :ssh])

      assert {:ok, report} = result

      hosts_check = Enum.find(report.checks, fn c -> c.name == :hosts end)
      ssh_check = Enum.find(report.checks, fn c -> c.name == :ssh end)

      assert hosts_check == nil or hosts_check.status == :skipped
      assert ssh_check == nil or ssh_check.status == :skipped

      File.rm!(path)
    end

    test "includes execution plan when config is valid" do
      path = write_valid_config_no_hosts()

      {:ok, report} = Checker.run(config_path: path, skip_checks: [:hosts, :ssh])

      assert report.execution_plan != nil
      assert is_list(report.execution_plan)

      File.rm!(path)
    end
  end

  describe "run_check/2" do
    test "config check passes with valid config" do
      path = write_valid_config()

      result = Checker.run_check(:config, config_path: path)

      assert result.name == :config
      assert result.status == :passed
      assert result.details.tasks > 0

      File.rm!(path)
    end

    test "config check fails with invalid config" do
      path = write_temp_file("invalid elixir syntax {{{")

      result = Checker.run_check(:config, config_path: path)

      assert result.name == :config
      assert result.status == :failed

      File.rm!(path)
    end

    test "hosts check skipped without config" do
      result = Checker.run_check(:hosts, [])

      assert result.name == :hosts
      assert result.status == :skipped
    end

    test "hosts check passes with local-only tasks" do
      config = build_local_config()

      result = Checker.run_check(:hosts, config: config)

      assert result.name == :hosts
      assert result.status == :passed
    end

    test "ssh check skipped without config" do
      result = Checker.run_check(:ssh, [])

      assert result.name == :ssh
      assert result.status == :skipped
    end

    test "ssh check passes when no remote hosts" do
      config = build_local_config()

      result = Checker.run_check(:ssh, config: config)

      assert result.name == :ssh
      assert result.status == :passed
      assert result.message =~ "No remote hosts"
    end

    test "sudo check passes with no sudo commands" do
      config = build_local_config()

      result = Checker.run_check(:sudo, config: config)

      assert result.name == :sudo
      assert result.status == :passed
    end

    test "sudo check reports sudo command count" do
      config = build_config_with_sudo()

      result = Checker.run_check(:sudo, config: config)

      assert result.name == :sudo
      assert result.status == :passed
      assert result.message =~ "require sudo"
    end

    test "tasks check passes when all tasks found" do
      config = build_local_config()

      result = Checker.run_check(:tasks, config: config, tasks: [:build])

      assert result.name == :tasks
      assert result.status == :passed
    end

    test "tasks check fails with unknown tasks" do
      config = build_local_config()

      result = Checker.run_check(:tasks, config: config, tasks: [:nonexistent])

      assert result.name == :tasks
      assert result.status == :failed
      assert result.message =~ "Unknown tasks"
    end

    test "tasks check lists available tasks when no specific tasks requested" do
      config = build_local_config()

      result = Checker.run_check(:tasks, config: config, tasks: [])

      assert result.name == :tasks
      assert result.status == :passed
      assert result.message =~ "available"
    end

    test "unknown check is skipped" do
      result = Checker.run_check(:unknown_check, [])

      assert result.status == :skipped
      assert result.message =~ "Unknown check"
    end
  end

  describe "generate_execution_plan/2" do
    test "generates phases for tasks with dependencies" do
      config = build_config_with_deps()

      plan = Checker.generate_execution_plan(config, [])

      assert length(plan) == 2

      phase1 = Enum.at(plan, 0)
      assert phase1.phase == 1
      assert length(phase1.tasks) == 1
      assert hd(phase1.tasks).name == :build

      phase2 = Enum.at(plan, 1)
      assert phase2.phase == 2
      assert Enum.any?(phase2.tasks, fn t -> t.name == :test end)
    end

    test "filters tasks when specific names provided" do
      config = build_config_with_deps()

      plan = Checker.generate_execution_plan(config, [:build])

      assert length(plan) == 1
      assert hd(hd(plan).tasks).name == :build
    end

    test "includes host information in task plan" do
      config = build_config_with_remote()

      plan = Checker.generate_execution_plan(config, [])

      deploy_phase =
        Enum.find(plan, fn p -> Enum.any?(p.tasks, fn t -> t.name == :deploy end) end)

      deploy_task = Enum.find(deploy_phase.tasks, fn t -> t.name == :deploy end)

      assert :web1 in deploy_task.hosts
    end

    test "returns empty list for cyclic dependencies" do
      config = build_cyclic_config()

      plan = Checker.generate_execution_plan(config, [])

      assert plan == []
    end
  end

  describe "format_plan/1" do
    test "formats empty plan" do
      result = Checker.format_plan([])
      assert result == "No tasks to execute."
    end

    test "formats plan with phases" do
      plan = [
        %{
          phase: 1,
          tasks: [
            %{
              name: :build,
              on: :local,
              hosts: [:local],
              commands: 2,
              strategy: :serial,
              deps: [],
              timeout: 30_000
            }
          ]
        },
        %{
          phase: 2,
          tasks: [
            %{
              name: :test,
              on: :local,
              hosts: [:local],
              commands: 1,
              strategy: :serial,
              deps: [:build],
              timeout: 30_000
            }
          ]
        }
      ]

      result = Checker.format_plan(plan)

      assert result =~ "Phase 1:"
      assert result =~ "Phase 2:"
      assert result =~ "build"
      assert result =~ "test"
      assert result =~ "after: build"
    end
  end

  # Helper functions

  defp write_valid_config do
    content = """
    host :localhost, "test@127.0.0.1:22"

    task :build do
      run "echo building"
    end

    task :test, deps: [:build] do
      run "echo testing"
    end
    """

    write_temp_file(content)
  end

  defp write_valid_config_no_hosts do
    content = """
    task :build do
      run "echo building"
    end

    task :test, deps: [:build] do
      run "echo testing"
    end
    """

    write_temp_file(content)
  end

  defp write_temp_file(content) do
    path = Path.join(System.tmp_dir!(), "nexus_test_#{:rand.uniform(100_000)}.exs")
    File.write!(path, content)
    path
  end

  defp build_local_config do
    build_task = %Task{
      name: :build,
      on: :local,
      deps: [],
      commands: [%Command{cmd: "echo build", sudo: false, user: nil, timeout: 5000}],
      timeout: 30_000,
      strategy: :serial
    }

    %Config{
      hosts: %{},
      groups: %{},
      tasks: %{build: build_task}
    }
  end

  defp build_config_with_sudo do
    install_task = %Task{
      name: :install,
      on: :local,
      deps: [],
      commands: [
        %Command{cmd: "apt-get update", sudo: true, user: nil, timeout: 5000},
        %Command{cmd: "apt-get install nginx", sudo: true, user: nil, timeout: 5000}
      ],
      timeout: 60_000,
      strategy: :serial
    }

    %Config{
      hosts: %{},
      groups: %{},
      tasks: %{install: install_task}
    }
  end

  defp build_config_with_deps do
    build_task = %Task{
      name: :build,
      on: :local,
      deps: [],
      commands: [%Command{cmd: "echo build", sudo: false, user: nil, timeout: 5000}],
      timeout: 30_000,
      strategy: :serial
    }

    test_task = %Task{
      name: :test,
      on: :local,
      deps: [:build],
      commands: [%Command{cmd: "echo test", sudo: false, user: nil, timeout: 5000}],
      timeout: 30_000,
      strategy: :serial
    }

    %Config{
      hosts: %{},
      groups: %{},
      tasks: %{build: build_task, test: test_task}
    }
  end

  defp build_config_with_remote do
    web1_host = %Host{name: :web1, hostname: "web1.example.com", user: "deploy", port: 22}

    build_task = %Task{
      name: :build,
      on: :local,
      deps: [],
      commands: [%Command{cmd: "echo build", sudo: false, user: nil, timeout: 5000}],
      timeout: 30_000,
      strategy: :serial
    }

    deploy_task = %Task{
      name: :deploy,
      on: :web1,
      deps: [:build],
      commands: [%Command{cmd: "echo deploy", sudo: false, user: nil, timeout: 5000}],
      timeout: 60_000,
      strategy: :parallel
    }

    %Config{
      hosts: %{web1: web1_host},
      groups: %{},
      tasks: %{build: build_task, deploy: deploy_task}
    }
  end

  defp build_cyclic_config do
    task_a = %Task{
      name: :a,
      on: :local,
      deps: [:b],
      commands: [],
      timeout: 30_000,
      strategy: :serial
    }

    task_b = %Task{
      name: :b,
      on: :local,
      deps: [:a],
      commands: [],
      timeout: 30_000,
      strategy: :serial
    }

    %Config{
      hosts: %{},
      groups: %{},
      tasks: %{a: task_a, b: task_b}
    }
  end
end
