defmodule Nexus.CLI.Run do
  @moduledoc """
  Handles the `nexus run` command.

  Executes one or more tasks with their dependencies.
  """

  alias Nexus.Check.Reporter, as: CheckReporter
  alias Nexus.DSL.Parser
  alias Nexus.Executor.Pipeline
  alias Nexus.Notifications.Sender, as: NotificationSender
  alias Nexus.Types.Config
  alias Nexus.Types.Task

  @doc """
  Executes the run command with parsed arguments.
  """
  def execute(parsed) do
    config_path = parsed.options[:config]
    tasks = parse_tasks(parsed.args[:tasks])
    opts = build_opts(parsed)

    with {:ok, config} <- load_config(config_path),
         {:ok, config} <- apply_tag_filters(config, opts),
         :ok <- validate_tasks(config, tasks) do
      cond do
        opts[:dry_run] ->
          execute_dry_run(config, tasks, opts)

        opts[:check] ->
          execute_check_mode(config, tasks, opts)

        true ->
          execute_pipeline(config, tasks, opts)
      end
    else
      {:error, reason} ->
        print_error(reason, opts)
        {:error, 1}
    end
  end

  defp parse_tasks(tasks_string) do
    tasks_string
    |> String.split(~r/[\s,]+/, trim: true)
    |> Enum.map(&String.to_atom/1)
  end

  defp build_opts(parsed) do
    ssh_opts = build_ssh_opts(parsed.options)

    [
      dry_run: parsed.flags[:dry_run] || false,
      check: parsed.flags[:check] || false,
      verbose: parsed.flags[:verbose] || false,
      quiet: parsed.flags[:quiet] || false,
      continue_on_error: parsed.flags[:continue_on_error] || false,
      parallel_limit: parsed.options[:parallel_limit] || 10,
      format: parsed.options[:format] || :text,
      plain: parsed.flags[:plain] || false,
      ssh_opts: ssh_opts,
      tags: parse_tag_list(parsed.options[:tags]),
      skip_tags: parse_tag_list(parsed.options[:skip_tags])
    ]
  end

  defp parse_tag_list(nil), do: []

  defp parse_tag_list(tags_string) do
    tags_string
    |> String.split(~r/[\s,]+/, trim: true)
    |> Enum.map(&String.to_atom/1)
  end

  defp apply_tag_filters(config, opts) do
    tags = opts[:tags] || []
    skip_tags = opts[:skip_tags] || []

    if Enum.empty?(tags) and Enum.empty?(skip_tags) do
      {:ok, config}
    else
      filtered_tasks =
        config.tasks
        |> Enum.filter(fn {_name, task} ->
          passes_tag_filter?(task, tags, skip_tags)
        end)
        |> Map.new()

      {:ok, %{config | tasks: filtered_tasks}}
    end
  end

  defp passes_tag_filter?(task, include_tags, exclude_tags) do
    # If include_tags specified, task must have at least one of them
    include_ok =
      if Enum.empty?(include_tags) do
        true
      else
        Task.has_tag?(task, include_tags)
      end

    # If exclude_tags specified, task must NOT have any of them
    exclude_ok =
      if Enum.empty?(exclude_tags) do
        true
      else
        not Task.has_tag?(task, exclude_tags)
      end

    include_ok and exclude_ok
  end

  defp build_ssh_opts(options) do
    opts = [silently_accept_hosts: true]

    opts =
      if options[:identity] do
        Keyword.put(opts, :identity, options[:identity])
      else
        opts
      end

    opts =
      if options[:user] do
        Keyword.put(opts, :user, options[:user])
      else
        opts
      end

    opts =
      if options[:password] do
        password = resolve_password(options[:password])
        Keyword.put(opts, :password, password)
      else
        opts
      end

    opts
  end

  defp resolve_password("-") do
    IO.write(:stderr, "SSH password: ")
    password = IO.gets("") |> String.trim()
    # Clear the line
    IO.write(:stderr, "\r                    \r")
    password
  end

  defp resolve_password(password), do: password

  defp load_config(path) do
    if File.exists?(path) do
      Parser.parse_file(path)
    else
      {:error, {:file_not_found, path}}
    end
  end

  defp validate_tasks(config, tasks) do
    Pipeline.validate(config, tasks)
  end

  defp execute_dry_run(config, tasks, opts) do
    case Pipeline.dry_run(config, tasks) do
      {:ok, plan} ->
        print_dry_run(plan, opts)
        {:ok, 0}

      {:error, reason} ->
        print_error(reason, opts)
        {:error, 1}
    end
  end

  defp execute_check_mode(config, tasks, opts) do
    case Pipeline.dry_run(config, tasks) do
      {:ok, plan} ->
        print_check_mode(config, plan, opts)
        {:ok, 0}

      {:error, reason} ->
        print_error(reason, opts)
        {:error, 1}
    end
  end

  defp print_check_mode(config, plan, _opts) do
    CheckReporter.print_header()

    {total_changes, total_hosts} =
      Enum.reduce(plan.phases, {0, 0}, fn phase, acc ->
        Enum.reduce(phase, acc, fn task_name, {ch, h} ->
          process_task_for_check(config, plan, task_name, {ch, h})
        end)
      end)

    CheckReporter.print_summary(plan.total_tasks, total_hosts, total_changes)
  end

  defp process_task_for_check(config, plan, task_name, {ch, h}) do
    task = Map.get(plan.task_details, task_name)

    case Config.resolve_hosts(config, task.on) do
      {:ok, task_hosts} ->
        host_names = get_host_names(task_hosts)
        results = generate_check_results(task.commands, host_names)
        CheckReporter.print_task_check(task_name, host_names, results)
        {ch + length(results), h + length(host_names)}

      {:error, _} ->
        {ch, h}
    end
  end

  defp get_host_names([]), do: ["local"]
  defp get_host_names(task_hosts), do: Enum.map(task_hosts, & &1.hostname)

  defp generate_check_results(commands, host_names) do
    Enum.flat_map(commands, fn cmd ->
      Enum.map(host_names, fn host ->
        CheckReporter.check_command(cmd, host, %{})
      end)
    end)
  end

  defp execute_pipeline(config, tasks, opts) do
    pipeline_opts = [
      continue_on_error: opts[:continue_on_error],
      parallel_limit: opts[:parallel_limit],
      ssh_opts: opts[:ssh_opts]
    ]

    started_at = DateTime.utc_now()

    case Pipeline.run(config, tasks, pipeline_opts) do
      {:ok, result} ->
        print_result(result, opts)
        send_notifications(config, result, started_at, opts)

        if result.status == :ok do
          {:ok, 0}
        else
          {:error, 1}
        end

      {:error, reason} ->
        print_error(reason, opts)
        {:error, 1}
    end
  end

  defp send_notifications(config, result, started_at, opts) do
    if Enum.empty?(config.notifications) do
      :ok
    else
      finished_at = DateTime.utc_now()

      notification_result = %{
        status: if(result.status == :ok, do: :success, else: :failure),
        duration_ms: result.duration_ms,
        started_at: started_at,
        finished_at: finished_at,
        tasks: build_task_results(result.task_results)
      }

      unless opts[:quiet] do
        IO.puts("Sending #{length(config.notifications)} notification(s)...")
      end

      NotificationSender.send_all(config.notifications, notification_result)
    end
  end

  defp build_task_results(task_results) do
    Enum.map(task_results, fn task_result ->
      %{
        name: task_result.task,
        status: if(task_result.status == :ok, do: :success, else: :failure),
        hosts:
          Enum.map(task_result.host_results, fn host_result ->
            %{
              host: host_result.host,
              status: if(host_result.status == :ok, do: :success, else: :failure),
              output: nil,
              error: if(host_result.status != :ok, do: "Task failed", else: nil)
            }
          end)
      }
    end)
  end

  defp print_dry_run(plan, opts) do
    case opts[:format] do
      :json ->
        print_dry_run_json(plan)

      :text ->
        print_dry_run_text(plan, opts)
    end
  end

  defp print_dry_run_json(plan) do
    data = %{
      total_tasks: plan.total_tasks,
      phases: Enum.map(plan.phases, fn phase -> Enum.map(phase, &Atom.to_string/1) end),
      tasks:
        Map.new(plan.task_details, fn {name, task} ->
          {Atom.to_string(name),
           %{
             deps: Enum.map(task.deps, &Atom.to_string/1),
             on: Atom.to_string(task.on),
             commands: length(task.commands)
           }}
        end)
    }

    IO.puts(Jason.encode!(data, pretty: true))
  end

  defp print_dry_run_text(plan, _opts) do
    IO.puts("\nExecution Plan")
    IO.puts(String.duplicate("=", 40))
    IO.puts("Total tasks: #{plan.total_tasks}\n")

    plan.phases
    |> Enum.with_index(1)
    |> Enum.each(fn {phase, idx} ->
      tasks_str = Enum.map_join(phase, ", ", &Atom.to_string/1)
      parallel_note = if length(phase) > 1, do: " (parallel)", else: ""
      IO.puts("Phase #{idx}: #{tasks_str}#{parallel_note}")
    end)

    IO.puts("")
  end

  defp print_result(result, opts) do
    case opts[:format] do
      :json ->
        print_result_json(result)

      :text ->
        print_result_text(result, opts)
    end
  end

  defp print_result_json(result) do
    data = %{
      status: result.status,
      duration_ms: result.duration_ms,
      tasks_run: result.tasks_run,
      tasks_succeeded: result.tasks_succeeded,
      tasks_failed: result.tasks_failed,
      aborted_at: result.aborted_at && Atom.to_string(result.aborted_at)
    }

    IO.puts(Jason.encode!(data, pretty: true))
  end

  defp print_result_text(result, opts) do
    unless opts[:quiet] do
      # Print task output
      print_task_results(result.task_results, opts)

      IO.puts("")
      IO.puts(String.duplicate("=", 40))

      status_str =
        if result.status == :ok do
          "SUCCESS"
        else
          "FAILED"
        end

      IO.puts("Status: #{status_str}")
      IO.puts("Duration: #{result.duration_ms}ms")
      IO.puts("Tasks: #{result.tasks_succeeded}/#{result.tasks_run} succeeded")

      if result.aborted_at do
        IO.puts("Aborted at: #{result.aborted_at}")
      end

      IO.puts("")
    end
  end

  defp print_task_results(task_results, opts) do
    verbose = opts[:verbose] || false

    Enum.each(task_results, fn task_result ->
      print_task_result(task_result, verbose)
    end)
  end

  defp print_task_result(task_result, verbose) do
    task_name = task_result.task
    status_marker = if task_result.status == :ok, do: "[ok]", else: "[FAILED]"

    IO.puts("")
    IO.puts("#{status_marker} Task: #{task_name}")

    Enum.each(task_result.host_results, fn host_result ->
      print_host_result(host_result, verbose)
    end)
  end

  defp print_host_result(host_result, verbose) do
    host_name = host_result.host
    host_status = if host_result.status == :ok, do: "ok", else: "failed"

    IO.puts("  Host: #{host_name} (#{host_status})")

    Enum.each(host_result.commands, fn cmd_result ->
      print_command_result(cmd_result, verbose)
    end)
  end

  defp print_command_result(cmd_result, verbose) do
    status_icon = if cmd_result.status == :ok, do: "+", else: "x"
    IO.puts("    [#{status_icon}] $ #{cmd_result.cmd}")

    output = String.trim(cmd_result.output || "")

    if output != "" do
      output
      |> String.split("\n")
      |> Enum.each(fn line ->
        IO.puts("        #{line}")
      end)
    end

    if verbose do
      IO.puts(
        "        (exit: #{cmd_result.exit_code}, #{cmd_result.duration_ms}ms, attempts: #{cmd_result.attempts})"
      )
    end
  end

  defp print_error(reason, opts) do
    case opts[:format] do
      :json ->
        IO.puts(:stderr, Jason.encode!(%{error: format_error(reason)}))

      _ ->
        IO.puts(:stderr, "Error: #{format_error(reason)}")
    end
  end

  defp format_error({:file_not_found, path}) do
    "Config file not found: #{path}\n  Hint: Ensure the file exists or specify a different path with -c"
  end

  defp format_error({:unknown_tasks, tasks}) do
    "Unknown tasks: #{Enum.map_join(tasks, ", ", &Atom.to_string/1)}\n  Hint: Use 'nexus list' to see available tasks"
  end

  defp format_error({:cycle, path}) do
    "Circular dependency detected: #{Enum.map_join(path, " -> ", &Atom.to_string/1)}\n  Hint: Review task dependencies to break the cycle"
  end

  defp format_error(reason) when is_binary(reason) do
    reason
  end
end
