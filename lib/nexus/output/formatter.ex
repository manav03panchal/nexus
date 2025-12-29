defmodule Nexus.Output.Formatter do
  @moduledoc """
  Formats output messages for CLI display.

  Provides consistent formatting for task status, errors, and results.
  Supports plain text and JSON output formats.
  """

  alias Nexus.Types.Task, as: NexusTask

  @type format :: :text | :json
  @type verbosity :: :quiet | :normal | :verbose

  @doc """
  Formats a task start message.
  """
  @spec format_task_start(NexusTask.t(), keyword()) :: String.t()
  def format_task_start(%NexusTask{} = task, opts \\ []) do
    format = Keyword.get(opts, :format, :text)
    verbosity = Keyword.get(opts, :verbosity, :normal)

    case {format, verbosity} do
      {:json, _} ->
        Jason.encode!(%{
          event: "task_start",
          task: Atom.to_string(task.name),
          on: Atom.to_string(task.on),
          commands: length(task.commands)
        })

      {:text, :quiet} ->
        ""

      {:text, _} ->
        target = if task.on == :local, do: "local", else: Atom.to_string(task.on)
        "Running task: #{task.name} [#{target}]"
    end
  end

  @doc """
  Formats a task completion message.
  """
  @spec format_task_complete(NexusTask.t(), map(), keyword()) :: String.t()
  def format_task_complete(%NexusTask{} = task, result, opts \\ []) do
    format = Keyword.get(opts, :format, :text)
    verbosity = Keyword.get(opts, :verbosity, :normal)

    case {format, verbosity} do
      {:json, _} ->
        Jason.encode!(%{
          event: "task_complete",
          task: Atom.to_string(task.name),
          status: result.status,
          duration_ms: result.duration_ms
        })

      {:text, :quiet} ->
        ""

      {:text, _} ->
        status_str = format_status(result.status)
        duration = format_duration(result.duration_ms)
        "  #{status_str} #{task.name} (#{duration})"
    end
  end

  @doc """
  Formats a command start message.
  """
  @spec format_command_start(String.t(), keyword()) :: String.t()
  def format_command_start(cmd, opts \\ []) do
    format = Keyword.get(opts, :format, :text)
    verbosity = Keyword.get(opts, :verbosity, :normal)

    case {format, verbosity} do
      {:json, _} ->
        Jason.encode!(%{event: "command_start", command: cmd})

      {:text, :verbose} ->
        "    $ #{truncate_cmd(cmd, 60)}"

      _ ->
        ""
    end
  end

  @doc """
  Formats a command completion message.
  """
  @spec format_command_complete(String.t(), integer(), keyword()) :: String.t()
  def format_command_complete(cmd, exit_code, opts \\ []) do
    format = Keyword.get(opts, :format, :text)
    verbosity = Keyword.get(opts, :verbosity, :normal)

    case {format, verbosity} do
      {:json, _} ->
        Jason.encode!(%{
          event: "command_complete",
          command: cmd,
          exit_code: exit_code
        })

      {:text, :verbose} ->
        status = if exit_code == 0, do: "ok", else: "exit #{exit_code}"
        "    [#{status}]"

      _ ->
        ""
    end
  end

  @doc """
  Formats an error message.
  """
  @spec format_error(term(), keyword()) :: String.t()
  def format_error(error, opts \\ []) do
    format = Keyword.get(opts, :format, :text)

    case format do
      :json ->
        Jason.encode!(%{event: "error", message: error_to_string(error)})

      :text ->
        "Error: #{error_to_string(error)}"
    end
  end

  @doc """
  Formats a pipeline result summary.
  """
  @spec format_pipeline_result(map(), keyword()) :: String.t()
  def format_pipeline_result(result, opts \\ []) do
    format = Keyword.get(opts, :format, :text)
    verbosity = Keyword.get(opts, :verbosity, :normal)

    case {format, verbosity} do
      {:json, _} ->
        Jason.encode!(%{
          event: "pipeline_complete",
          status: result.status,
          duration_ms: result.duration_ms,
          tasks_run: result.tasks_run,
          tasks_succeeded: result.tasks_succeeded,
          tasks_failed: result.tasks_failed,
          aborted_at: result.aborted_at && Atom.to_string(result.aborted_at)
        })

      {:text, :quiet} ->
        status_str = if result.status == :ok, do: "OK", else: "FAILED"
        "#{status_str}"

      {:text, _} ->
        format_pipeline_result_text(result)
    end
  end

  @doc """
  Formats command output (stdout/stderr).
  """
  @spec format_output(String.t(), keyword()) :: String.t()
  def format_output(output, opts \\ []) do
    format = Keyword.get(opts, :format, :text)
    verbosity = Keyword.get(opts, :verbosity, :normal)

    case {format, verbosity} do
      {:json, _} ->
        Jason.encode!(%{event: "output", content: output})

      {:text, :verbose} ->
        output
        |> String.split("\n")
        |> Enum.map_join("\n", &("      | " <> &1))

      _ ->
        ""
    end
  end

  @doc """
  Formats a host connection message.
  """
  @spec format_host_connect(atom() | String.t(), keyword()) :: String.t()
  def format_host_connect(host, opts \\ []) do
    format = Keyword.get(opts, :format, :text)
    verbosity = Keyword.get(opts, :verbosity, :normal)
    host_str = if is_atom(host), do: Atom.to_string(host), else: host

    case {format, verbosity} do
      {:json, _} ->
        Jason.encode!(%{event: "host_connect", host: host_str})

      {:text, :verbose} ->
        "  Connecting to #{host_str}..."

      _ ->
        ""
    end
  end

  @doc """
  Formats a retry message.
  """
  @spec format_retry(String.t(), integer(), integer(), keyword()) :: String.t()
  def format_retry(cmd, attempt, max_attempts, opts \\ []) do
    format = Keyword.get(opts, :format, :text)

    case format do
      :json ->
        Jason.encode!(%{
          event: "retry",
          command: cmd,
          attempt: attempt,
          max_attempts: max_attempts
        })

      :text ->
        "    Retry #{attempt}/#{max_attempts}: #{truncate_cmd(cmd, 40)}"
    end
  end

  # Private helpers

  defp format_status(:ok), do: "[ok]"
  defp format_status(:error), do: "[FAILED]"
  defp format_status(:skipped), do: "[skipped]"
  defp format_status(status), do: "[#{status}]"

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)}s"

  defp format_duration(ms) do
    minutes = div(ms, 60_000)
    seconds = rem(ms, 60_000) / 1000
    "#{minutes}m#{Float.round(seconds, 1)}s"
  end

  defp format_pipeline_result_text(result) do
    status_str = if result.status == :ok, do: "SUCCESS", else: "FAILED"

    lines = [
      "",
      String.duplicate("=", 40),
      "Status: #{status_str}",
      "Duration: #{format_duration(result.duration_ms)}",
      "Tasks: #{result.tasks_succeeded}/#{result.tasks_run} succeeded"
    ]

    lines =
      if result.aborted_at do
        lines ++ ["Aborted at: #{result.aborted_at}"]
      else
        lines
      end

    Enum.join(lines ++ [""], "\n")
  end

  defp truncate_cmd(cmd, max_len) do
    if String.length(cmd) > max_len do
      String.slice(cmd, 0, max_len - 3) <> "..."
    else
      cmd
    end
  end

  defp error_to_string({:file_not_found, path}), do: "File not found: #{path}"

  defp error_to_string({:unknown_tasks, tasks}),
    do: "Unknown tasks: #{Enum.map_join(tasks, ", ", &Atom.to_string/1)}"

  defp error_to_string({:cycle, path}),
    do: "Circular dependency: #{Enum.map_join(path, " -> ", &Atom.to_string/1)}"

  defp error_to_string({:connection_failed, host}), do: "Connection failed: #{host}"
  defp error_to_string({:auth_failed, host}), do: "Authentication failed: #{host}"
  defp error_to_string({:timeout, cmd}), do: "Command timed out: #{truncate_cmd(cmd, 40)}"
  defp error_to_string(error) when is_binary(error), do: error
  defp error_to_string(error), do: inspect(error)
end
