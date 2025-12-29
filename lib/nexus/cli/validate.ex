defmodule Nexus.CLI.Validate do
  @moduledoc """
  Handles the `nexus validate` command.

  Validates the nexus.exs configuration file for syntax errors,
  invalid references, and circular dependencies.
  """

  alias Nexus.DAG
  alias Nexus.DSL.Parser
  alias Nexus.DSL.Validator

  @doc """
  Executes the validate command with parsed arguments.
  """
  def execute(parsed) do
    config_path = parsed.options[:config]

    with :ok <- check_file_exists(config_path),
         {:ok, config} <- parse_config(config_path),
         :ok <- validate_config(config),
         :ok <- check_dag(config) do
      print_success(config_path, config)
      {:ok, 0}
    else
      {:error, reason} ->
        print_error(reason)
        {:error, 1}
    end
  end

  defp check_file_exists(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, {:file_not_found, path}}
    end
  end

  defp parse_config(path) do
    case Parser.parse_file(path) do
      {:ok, config} -> {:ok, config}
      {:error, reason} -> {:error, {:parse_error, reason}}
    end
  end

  defp validate_config(config) do
    case Validator.validate(config) do
      :ok -> :ok
      {:error, errors} -> {:error, {:validation_errors, errors}}
    end
  end

  defp check_dag(config) do
    case DAG.build(config) do
      {:ok, _graph} -> :ok
      {:error, {:cycle, path}} -> {:error, {:cycle, path}}
    end
  end

  defp print_success(path, config) do
    IO.puts("Configuration valid: #{path}")
    IO.puts("")
    IO.puts("Summary:")
    IO.puts("  Tasks:  #{map_size(config.tasks)}")
    IO.puts("  Hosts:  #{map_size(config.hosts)}")
    IO.puts("  Groups: #{map_size(config.groups)}")
  end

  defp print_error({:file_not_found, path}) do
    IO.puts(:stderr, "Error: Config file not found: #{path}")
  end

  defp print_error({:parse_error, reason}) do
    IO.puts(:stderr, "Error: Failed to parse configuration")
    IO.puts(:stderr, "")
    IO.puts(:stderr, "  #{reason}")
  end

  defp print_error({:validation_errors, errors}) do
    IO.puts(:stderr, "Error: Configuration validation failed")
    IO.puts(:stderr, "")
    Enum.each(errors, &print_validation_error/1)
  end

  defp print_error({:cycle, path}) do
    IO.puts(:stderr, "Error: Circular dependency detected")
    IO.puts(:stderr, "")
    cycle_str = Enum.map_join(path, " -> ", &Atom.to_string/1)
    IO.puts(:stderr, "  #{cycle_str}")
  end

  defp print_validation_error({:unknown_host, task, host}) do
    IO.puts(:stderr, "  Task '#{task}' references unknown host: #{host}")
  end

  defp print_validation_error({:unknown_group, task, group}) do
    IO.puts(:stderr, "  Task '#{task}' references unknown group: #{group}")
  end

  defp print_validation_error({:unknown_dependency, task, dep}) do
    IO.puts(:stderr, "  Task '#{task}' depends on unknown task: #{dep}")
  end

  defp print_validation_error({:empty_commands, task}) do
    IO.puts(:stderr, "  Task '#{task}' has no commands")
  end

  defp print_validation_error({:invalid_timeout, task, value}) do
    IO.puts(:stderr, "  Task '#{task}' has invalid timeout: #{value}")
  end

  defp print_validation_error(error) do
    IO.puts(:stderr, "  #{inspect(error)}")
  end
end
