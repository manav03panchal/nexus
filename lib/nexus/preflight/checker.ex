defmodule Nexus.Preflight.Checker do
  @moduledoc """
  Pre-flight checks for pipeline execution.

  Validates configuration, host reachability, SSH authentication,
  and generates execution plans before running tasks.
  """

  alias Nexus.DAG
  alias Nexus.DSL.{Parser, Validator}
  alias Nexus.Types.{Config, Host, Task}

  @type check_result :: :ok | {:error, term()}
  @type check_name :: :config | :hosts | :ssh | :sudo | :tasks
  @type check_report :: %{
          name: check_name(),
          status: :passed | :failed | :skipped,
          message: String.t(),
          details: term()
        }
  @type report :: %{
          status: :ok | :error,
          checks: [check_report()],
          execution_plan: list() | nil,
          duration_ms: non_neg_integer()
        }

  @default_checks [:config, :hosts, :ssh, :tasks]
  @tcp_connect_timeout 5_000

  @doc """
  Runs pre-flight checks for the given configuration and tasks.

  ## Options

    * `:checks` - List of checks to run (default: all)
    * `:skip_checks` - List of checks to skip
    * `:config_path` - Path to nexus.exs file
    * `:ssh_opts` - SSH options for authentication checks
    * `:verbose` - Include detailed output

  ## Returns

    * `{:ok, report}` - All checks passed
    * `{:error, report}` - One or more checks failed

  """
  @spec run(keyword()) :: {:ok, report()} | {:error, report()}
  def run(opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    checks_to_run = determine_checks(opts)

    {check_results, config} = run_checks(checks_to_run, opts)

    execution_plan =
      if config do
        tasks = Keyword.get(opts, :tasks, [])
        generate_execution_plan(config, tasks)
      else
        nil
      end

    duration_ms = System.monotonic_time(:millisecond) - start_time

    report = %{
      status: if(all_passed?(check_results), do: :ok, else: :error),
      checks: check_results,
      execution_plan: execution_plan,
      duration_ms: duration_ms
    }

    if report.status == :ok do
      {:ok, report}
    else
      {:error, report}
    end
  end

  @doc """
  Runs a single check by name.
  """
  @spec run_check(check_name(), keyword()) :: check_report()
  def run_check(check_name, opts \\ []) do
    case check_name do
      :config -> check_config(opts)
      :hosts -> check_hosts(opts)
      :ssh -> check_ssh(opts)
      :sudo -> check_sudo(opts)
      :tasks -> check_tasks(opts)
      _ -> %{name: check_name, status: :skipped, message: "Unknown check", details: nil}
    end
  end

  @doc """
  Generates an execution plan showing what would be executed.
  """
  @spec generate_execution_plan(Config.t(), [atom()]) :: list()
  def generate_execution_plan(%Config{} = config, task_names) do
    all_tasks = Map.values(config.tasks)

    tasks_to_run =
      if Enum.empty?(task_names) do
        all_tasks
      else
        Enum.filter(all_tasks, fn task -> task.name in task_names end)
      end

    case DAG.build_from_tasks(tasks_to_run) do
      {:ok, graph} ->
        phases = DAG.execution_phases(graph)

        Enum.with_index(phases, 1)
        |> Enum.map(fn {phase_tasks, phase_num} ->
          %{
            phase: phase_num,
            tasks:
              Enum.map(phase_tasks, fn task_name ->
                # Look in all_tasks since phases may include dependencies
                task = Enum.find(all_tasks, fn t -> t.name == task_name end)
                format_task_plan(task, config)
              end)
          }
        end)

      {:error, {:cycle, _path}} ->
        []
    end
  end

  @doc """
  Formats the execution plan as a string for display.
  """
  @spec format_plan(list()) :: String.t()
  def format_plan(execution_plan) do
    if Enum.empty?(execution_plan) do
      "No tasks to execute."
    else
      Enum.map_join(execution_plan, "\n\n", &format_phase/1)
    end
  end

  # Private functions

  defp determine_checks(opts) do
    base_checks = Keyword.get(opts, :checks, @default_checks)
    skip_checks = Keyword.get(opts, :skip_checks, [])
    Enum.reject(base_checks, fn c -> c in skip_checks end)
  end

  defp run_checks(checks, opts) do
    # Run config check first to get config for other checks
    config_result = if :config in checks, do: check_config(opts), else: nil

    config =
      case config_result do
        %{status: :passed, details: %{config: cfg}} -> cfg
        _ -> nil
      end

    opts_with_config = Keyword.put(opts, :config, config)

    results =
      Enum.map(checks, fn check ->
        if check == :config do
          config_result || %{name: :config, status: :skipped, message: "Skipped", details: nil}
        else
          run_check(check, opts_with_config)
        end
      end)

    {results, config}
  end

  defp all_passed?(check_results) do
    Enum.all?(check_results, fn r -> r.status in [:passed, :skipped] end)
  end

  # Check implementations

  defp check_config(opts) do
    config_path = Keyword.get(opts, :config_path, "nexus.exs")

    with {:ok, config} <- Parser.parse_file(config_path),
         :ok <- Validator.validate(config) do
      %{
        name: :config,
        status: :passed,
        message: "Configuration is valid",
        details: %{
          config: config,
          tasks: map_size(config.tasks),
          hosts: map_size(config.hosts),
          groups: map_size(config.groups)
        }
      }
    else
      {:error, errors} when is_list(errors) ->
        %{
          name: :config,
          status: :failed,
          message: "Validation errors: #{length(errors)} issue(s)",
          details: errors
        }

      {:error, reason} when is_binary(reason) ->
        %{
          name: :config,
          status: :failed,
          message: reason,
          details: nil
        }
    end
  end

  defp check_hosts(opts) do
    config = Keyword.get(opts, :config)

    if config == nil do
      %{
        name: :hosts,
        status: :skipped,
        message: "Skipped (no config)",
        details: nil
      }
    else
      hosts = Map.values(config.hosts)
      results = Enum.map(hosts, &check_host_reachability/1)

      failed = Enum.filter(results, fn {_, status, _} -> status == :unreachable end)

      if Enum.empty?(failed) do
        %{
          name: :hosts,
          status: :passed,
          message: "All #{length(hosts)} host(s) reachable",
          details: results
        }
      else
        %{
          name: :hosts,
          status: :failed,
          message: "#{length(failed)} host(s) unreachable",
          details: results
        }
      end
    end
  end

  defp check_host_reachability(%Host{} = host) do
    case :gen_tcp.connect(
           String.to_charlist(host.hostname),
           host.port,
           [:binary, active: false],
           @tcp_connect_timeout
         ) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        {host.name, :reachable, nil}

      {:error, reason} ->
        {host.name, :unreachable, reason}
    end
  end

  defp check_ssh(opts) do
    config = Keyword.get(opts, :config)
    ssh_opts = Keyword.get(opts, :ssh_opts, [])

    if config == nil do
      %{
        name: :ssh,
        status: :skipped,
        message: "Skipped (no config)",
        details: nil
      }
    else
      config
      |> get_remote_hosts()
      |> check_ssh_for_hosts(ssh_opts)
    end
  end

  defp check_ssh_for_hosts([], _ssh_opts) do
    %{
      name: :ssh,
      status: :passed,
      message: "No remote hosts to check",
      details: []
    }
  end

  defp check_ssh_for_hosts(remote_hosts, ssh_opts) do
    results = Enum.map(remote_hosts, fn host -> check_ssh_auth(host, ssh_opts) end)
    failed = Enum.filter(results, fn {_, status, _} -> status == :failed end)
    build_ssh_check_result(remote_hosts, results, failed)
  end

  defp build_ssh_check_result(remote_hosts, results, []) do
    %{
      name: :ssh,
      status: :passed,
      message: "SSH authentication OK for #{length(remote_hosts)} host(s)",
      details: results
    }
  end

  defp build_ssh_check_result(_remote_hosts, results, failed) do
    %{
      name: :ssh,
      status: :failed,
      message: "SSH auth failed for #{length(failed)} host(s)",
      details: results
    }
  end

  defp get_remote_hosts(%Config{} = config) do
    remote_task_targets =
      config.tasks
      |> Map.values()
      |> Enum.reject(fn t -> t.on == :local end)
      |> Enum.map(fn t -> t.on end)
      |> Enum.uniq()

    remote_task_targets
    |> Enum.flat_map(&resolve_target_to_hosts(&1, config))
    |> Enum.uniq_by(fn h -> h.name end)
  end

  defp resolve_target_to_hosts(target, %Config{} = config) do
    case Map.get(config.groups, target) do
      nil -> resolve_host_ref(target, config)
      group -> resolve_group_members(group.hosts, config)
    end
  end

  defp resolve_host_ref(target, %Config{hosts: hosts}) do
    case Map.get(hosts, target) do
      nil -> []
      host -> [host]
    end
  end

  defp resolve_group_members(members, %Config{} = config) do
    Enum.flat_map(members, &resolve_host_ref(&1, config))
  end

  defp check_ssh_auth(%Host{} = host, ssh_opts) do
    # Try to establish SSH connection
    user = host.user || System.get_env("USER") || "root"

    # Build base options - disable password prompts to avoid interactive issues
    base_opts = [
      user: String.to_charlist(user),
      silently_accept_hosts: true,
      connect_timeout: @tcp_connect_timeout
    ]

    # Check if we have explicit credentials
    has_identity = Keyword.has_key?(ssh_opts, :identity)
    has_password = Keyword.has_key?(ssh_opts, :password)

    opts =
      if has_identity do
        identity_path = Keyword.get(ssh_opts, :identity)

        Keyword.merge(base_opts,
          user_dir: String.to_charlist(Path.dirname(identity_path)),
          user_interaction: false
        )
      else
        if has_password do
          password = Keyword.get(ssh_opts, :password)

          Keyword.merge(base_opts,
            password: String.to_charlist(password),
            user_interaction: false
          )
        else
          # No explicit credentials - try SSH agent / default keys only
          # Disable password auth to prevent interactive prompts
          Keyword.merge(base_opts,
            user_interaction: false,
            auth_methods: ~c"publickey"
          )
        end
      end

    case :ssh.connect(String.to_charlist(host.hostname), host.port, opts) do
      {:ok, conn} ->
        :ssh.close(conn)
        {host.name, :ok, nil}

      {:error, reason} ->
        {host.name, :failed, reason}
    end
  end

  defp check_sudo(opts) do
    config = Keyword.get(opts, :config)

    if config == nil do
      %{
        name: :sudo,
        status: :skipped,
        message: "Skipped (no config)",
        details: nil
      }
    else
      # Check if any commands require sudo
      sudo_commands =
        config.tasks
        |> Map.values()
        |> Enum.flat_map(fn t -> t.commands end)
        |> Enum.filter(fn c -> c.sudo end)

      if Enum.empty?(sudo_commands) do
        %{
          name: :sudo,
          status: :passed,
          message: "No sudo commands",
          details: nil
        }
      else
        %{
          name: :sudo,
          status: :passed,
          message: "#{length(sudo_commands)} command(s) require sudo",
          details: %{count: length(sudo_commands)}
        }
      end
    end
  end

  defp check_tasks(opts) do
    config = Keyword.get(opts, :config)
    task_names = Keyword.get(opts, :tasks, [])

    if config == nil do
      %{
        name: :tasks,
        status: :skipped,
        message: "Skipped (no config)",
        details: nil
      }
    else
      available_tasks = Map.keys(config.tasks)
      validate_task_names(task_names, available_tasks)
    end
  end

  defp validate_task_names([], available_tasks) do
    %{
      name: :tasks,
      status: :passed,
      message: "#{length(available_tasks)} task(s) available",
      details: available_tasks
    }
  end

  defp validate_task_names(task_names, available_tasks) do
    unknown = Enum.reject(task_names, fn t -> t in available_tasks end)
    build_task_check_result(task_names, available_tasks, unknown)
  end

  defp build_task_check_result(task_names, _available_tasks, []) do
    %{
      name: :tasks,
      status: :passed,
      message: "All requested tasks found",
      details: task_names
    }
  end

  defp build_task_check_result(_task_names, available_tasks, unknown) do
    %{
      name: :tasks,
      status: :failed,
      message: "Unknown tasks: #{Enum.map_join(unknown, ", ", &Atom.to_string/1)}",
      details: %{unknown: unknown, available: available_tasks}
    }
  end

  # Plan formatting helpers

  defp format_task_plan(%Task{} = task, %Config{} = config) do
    hosts = resolve_task_hosts(task, config)

    %{
      name: task.name,
      on: task.on,
      hosts: hosts,
      commands: length(task.commands),
      strategy: task.strategy,
      deps: task.deps,
      timeout: task.timeout
    }
  end

  defp resolve_task_hosts(%Task{on: :local}, _config), do: [:local]

  defp resolve_task_hosts(%Task{on: target}, %Config{} = config) do
    case Map.get(config.groups, target) do
      nil ->
        # Direct host reference
        [target]

      group ->
        group.hosts
    end
  end

  defp format_phase(%{phase: phase_num, tasks: tasks}) do
    header = "Phase #{phase_num}:"

    task_lines =
      Enum.map(tasks, fn task ->
        hosts_str =
          case task.hosts do
            [:local] -> "local"
            hosts -> Enum.map_join(hosts, ", ", &Atom.to_string/1)
          end

        deps_str =
          if Enum.empty?(task.deps) do
            ""
          else
            " (after: #{Enum.map_join(task.deps, ", ", &Atom.to_string/1)})"
          end

        "  - #{task.name} [#{hosts_str}] (#{task.commands} cmd, #{task.strategy})#{deps_str}"
      end)

    Enum.join([header | task_lines], "\n")
  end
end
