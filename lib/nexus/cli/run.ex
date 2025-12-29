defmodule Nexus.CLI.Run do
  @moduledoc """
  Handles the `nexus run` command.

  Executes one or more tasks with their dependencies.
  """

  alias Nexus.DSL.Parser
  alias Nexus.Executor.Pipeline

  @doc """
  Executes the run command with parsed arguments.
  """
  def execute(parsed) do
    config_path = parsed.options[:config]
    tasks = parse_tasks(parsed.args[:tasks])
    opts = build_opts(parsed)

    with {:ok, config} <- load_config(config_path),
         :ok <- validate_tasks(config, tasks) do
      if opts[:dry_run] do
        execute_dry_run(config, tasks, opts)
      else
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
      verbose: parsed.flags[:verbose] || false,
      quiet: parsed.flags[:quiet] || false,
      continue_on_error: parsed.flags[:continue_on_error] || false,
      parallel_limit: parsed.options[:parallel_limit] || 10,
      format: parsed.options[:format] || :text,
      plain: parsed.flags[:plain] || false,
      ssh_opts: ssh_opts
    ]
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

    opts
  end

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

  defp execute_pipeline(config, tasks, opts) do
    pipeline_opts = [
      continue_on_error: opts[:continue_on_error],
      parallel_limit: opts[:parallel_limit],
      ssh_opts: opts[:ssh_opts]
    ]

    case Pipeline.run(config, tasks, pipeline_opts) do
      {:ok, result} ->
        print_result(result, opts)

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

  defp print_error(reason, opts) do
    case opts[:format] do
      :json ->
        IO.puts(:stderr, Jason.encode!(%{error: format_error(reason)}))

      _ ->
        IO.puts(:stderr, "Error: #{format_error(reason)}")
    end
  end

  defp format_error({:file_not_found, path}) do
    "Config file not found: #{path}"
  end

  defp format_error({:unknown_tasks, tasks}) do
    "Unknown tasks: #{Enum.map_join(tasks, ", ", &Atom.to_string/1)}"
  end

  defp format_error({:cycle, path}) do
    "Circular dependency detected: #{Enum.map_join(path, " -> ", &Atom.to_string/1)}"
  end

  defp format_error(reason) when is_binary(reason) do
    reason
  end
end
