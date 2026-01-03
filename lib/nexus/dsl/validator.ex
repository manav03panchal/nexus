defmodule Nexus.DSL.Validator do
  @moduledoc """
  Validates Nexus configuration for correctness and consistency.

  Performs the following validations:
  - Task dependency references exist
  - Host/group references in tasks exist
  - Group member references exist
  - No circular dependencies (delegated to DAG module)
  - Configuration values are within valid ranges
  """

  alias Nexus.Types.{Config, Download, Task, Template, Upload}

  @type validation_error :: {atom(), String.t()}
  @type validation_result :: :ok | {:error, [validation_error()]}

  @doc """
  Validates a configuration, returning `:ok` or a list of errors.

  ## Examples

      iex> Nexus.DSL.Validator.validate(config)
      :ok

      iex> Nexus.DSL.Validator.validate(invalid_config)
      {:error, [{:task_deps, "task :deploy depends on unknown task :build"}]}

  """
  @spec validate(Config.t()) :: validation_result()
  def validate(%Config{} = config) do
    errors =
      []
      |> validate_task_deps(config)
      |> validate_task_hosts(config)
      |> validate_group_members(config)
      |> validate_config_values(config)
      |> validate_task_commands(config)

    case errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  @doc """
  Validates and returns the config or raises on error.
  """
  @spec validate!(Config.t()) :: Config.t()
  def validate!(%Config{} = config) do
    case validate(config) do
      :ok ->
        config

      {:error, errors} ->
        message =
          Enum.map_join(errors, "\n", fn {type, msg} -> "  - [#{type}] #{msg}" end)

        raise ArgumentError, "configuration validation failed:\n#{message}"
    end
  end

  # Validate that all task dependencies reference existing tasks
  defp validate_task_deps(errors, %Config{tasks: tasks}) do
    task_names = Map.keys(tasks)

    Enum.reduce(tasks, errors, fn {_name, task}, acc ->
      validate_task_dep_list(acc, task, task_names)
    end)
  end

  defp validate_task_dep_list(errors, task, task_names) do
    Enum.reduce(task.deps, errors, fn dep, acc ->
      if dep in task_names do
        acc
      else
        [{:task_deps, "task :#{task.name} depends on unknown task :#{dep}"} | acc]
      end
    end)
  end

  # Validate that task host references exist
  defp validate_task_hosts(errors, %Config{tasks: tasks, hosts: hosts, groups: groups}) do
    host_names = Map.keys(hosts)
    group_names = Map.keys(groups)
    valid_targets = [:local | host_names ++ group_names]

    Enum.reduce(tasks, errors, fn {_name, task}, acc ->
      if task.on in valid_targets do
        acc
      else
        [{:task_hosts, "task :#{task.name} references unknown host or group :#{task.on}"} | acc]
      end
    end)
  end

  # Validate that group members reference existing hosts
  defp validate_group_members(errors, %Config{hosts: hosts, groups: groups}) do
    host_names = Map.keys(hosts)

    Enum.reduce(groups, errors, fn {_name, group}, acc ->
      validate_group_host_refs(acc, group, host_names)
    end)
  end

  defp validate_group_host_refs(errors, group, host_names) do
    Enum.reduce(group.hosts, errors, fn host_ref, acc ->
      if host_ref in host_names do
        acc
      else
        [{:group_members, "group :#{group.name} references unknown host :#{host_ref}"} | acc]
      end
    end)
  end

  # Validate configuration values are within valid ranges
  defp validate_config_values(errors, %Config{} = config) do
    errors
    |> validate_positive(:default_port, config.default_port, 1, 65_535)
    |> validate_positive(:connect_timeout, config.connect_timeout, 1, 3_600_000)
    |> validate_positive(:command_timeout, config.command_timeout, 1, 86_400_000)
    |> validate_positive(:max_connections, config.max_connections, 1, 1000)
  end

  defp validate_positive(errors, field, value, min, max) do
    cond do
      not is_integer(value) ->
        [{:config, "#{field} must be an integer, got: #{inspect(value)}"} | errors]

      value < min ->
        [{:config, "#{field} must be at least #{min}, got: #{value}"} | errors]

      value > max ->
        [{:config, "#{field} must be at most #{max}, got: #{value}"} | errors]

      true ->
        errors
    end
  end

  # Validate task commands
  defp validate_task_commands(errors, %Config{tasks: tasks}) do
    Enum.reduce(tasks, errors, fn {_name, task}, acc ->
      validate_commands_in_task(acc, task)
    end)
  end

  defp validate_commands_in_task(errors, task) do
    Enum.reduce(task.commands, errors, fn command, acc ->
      acc
      |> validate_command_timeout(task.name, command)
      |> validate_command_retries(task.name, command)
      |> validate_path_traversal(task.name, command)
    end)
  end

  defp validate_command_timeout(errors, task_name, command) do
    # Only validate timeout for Command type which has the timeout field
    case Map.get(command, :timeout) do
      nil ->
        # Upload, Download, Template, WaitFor, and resource types don't have timeout
        errors

      timeout when is_integer(timeout) and timeout > 0 ->
        errors

      timeout ->
        [
          {:command, "command in task :#{task_name} has invalid timeout: #{timeout}"}
          | errors
        ]
    end
  end

  defp validate_command_retries(errors, task_name, command) do
    # Only validate retries for legacy run commands that have the retries field
    # Command resources don't have retries (they use creates/unless/onlyif for idempotency)
    retries = Map.get(command, :retries, 0)
    retry_delay = Map.get(command, :retry_delay, 1000)

    cond do
      retries < 0 ->
        [
          {:command, "command in task :#{task_name} has invalid retries: #{retries}"}
          | errors
        ]

      retries > 0 and retry_delay <= 0 ->
        [{:command, "command in task :#{task_name} has retries but invalid retry_delay"} | errors]

      true ->
        errors
    end
  end

  # Validate paths don't contain traversal sequences
  defp validate_path_traversal(errors, task_name, %Upload{} = upload) do
    errors
    |> check_path_traversal(task_name, :upload, :local_path, upload.local_path)
    |> check_path_traversal(task_name, :upload, :remote_path, upload.remote_path)
  end

  defp validate_path_traversal(errors, task_name, %Download{} = download) do
    errors
    |> check_path_traversal(task_name, :download, :local_path, download.local_path)
    |> check_path_traversal(task_name, :download, :remote_path, download.remote_path)
  end

  defp validate_path_traversal(errors, task_name, %Template{} = template) do
    errors
    |> check_path_traversal(task_name, :template, :source, template.source)
    |> check_path_traversal(task_name, :template, :destination, template.destination)
  end

  defp validate_path_traversal(errors, _task_name, _command), do: errors

  defp check_path_traversal(errors, task_name, cmd_type, field, path) when is_binary(path) do
    # Normalize path and check for traversal attempts
    # We don't allow ".." components in paths as they could escape intended directories
    normalized = Path.expand(path)
    segments = Path.split(path)

    cond do
      # Check for explicit ".." in path segments
      Enum.member?(segments, "..") ->
        [
          {:path_traversal,
           "#{cmd_type} in task :#{task_name} has path traversal in #{field}: #{path}"}
          | errors
        ]

      # Check if path starts with ~ but expands outside home
      String.starts_with?(path, "~") and not String.starts_with?(normalized, System.user_home!()) ->
        [
          {:path_traversal,
           "#{cmd_type} in task :#{task_name} has suspicious home path in #{field}: #{path}"}
          | errors
        ]

      true ->
        errors
    end
  end

  defp check_path_traversal(errors, _task_name, _cmd_type, _field, _path), do: errors

  @doc """
  Returns a list of all hosts that a task will run on.
  """
  @spec resolve_task_hosts(Config.t(), Task.t()) ::
          {:ok, [Nexus.Types.Host.t()]} | {:error, String.t()}
  def resolve_task_hosts(%Config{} = config, %Task{} = task) do
    Config.resolve_hosts(config, task.on)
  end
end
