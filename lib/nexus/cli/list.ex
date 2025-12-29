defmodule Nexus.CLI.List do
  @moduledoc """
  Handles the `nexus list` command.

  Lists all tasks defined in the configuration.
  """

  alias Nexus.DAG
  alias Nexus.DSL.Parser

  @doc """
  Executes the list command with parsed arguments.
  """
  def execute(parsed) do
    config_path = parsed.options[:config]
    format = parsed.options[:format] || :text

    case load_config(config_path) do
      {:ok, config} ->
        print_tasks(config, format)
        {:ok, 0}

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{format_error(reason)}")
        {:error, 1}
    end
  end

  defp load_config(path) do
    if File.exists?(path) do
      Parser.parse_file(path)
    else
      {:error, {:file_not_found, path}}
    end
  end

  defp print_tasks(config, :json) do
    tasks =
      Map.new(config.tasks, fn {name, task} ->
        {Atom.to_string(name),
         %{
           deps: Enum.map(task.deps, &Atom.to_string/1),
           on: Atom.to_string(task.on),
           commands: length(task.commands),
           strategy: Atom.to_string(task.strategy)
         }}
      end)

    hosts =
      Map.new(config.hosts, fn {name, host} ->
        {Atom.to_string(name),
         %{
           hostname: host.hostname,
           user: host.user,
           port: host.port
         }}
      end)

    groups =
      Map.new(config.groups, fn {name, group} ->
        {Atom.to_string(name), Enum.map(group.hosts, &Atom.to_string/1)}
      end)

    data = %{
      tasks: tasks,
      hosts: hosts,
      groups: groups
    }

    IO.puts(Jason.encode!(data, pretty: true))
  end

  defp print_tasks(config, :text) do
    IO.puts("\nTasks")
    IO.puts(String.duplicate("=", 40))

    if map_size(config.tasks) == 0 do
      IO.puts("  No tasks defined")
    else
      # Get execution order if possible
      case DAG.build(config) do
        {:ok, graph} ->
          sorted = DAG.topological_sort(graph)
          print_sorted_tasks(config, sorted)

        {:error, _} ->
          # Cycle exists, just print alphabetically
          config.tasks
          |> Map.keys()
          |> Enum.sort()
          |> Enum.each(&print_task(config.tasks[&1]))
      end
    end

    if map_size(config.hosts) > 0 do
      IO.puts("\nHosts")
      IO.puts(String.duplicate("=", 40))

      config.hosts
      |> Map.values()
      |> Enum.sort_by(& &1.name)
      |> Enum.each(&print_host/1)
    end

    if map_size(config.groups) > 0 do
      IO.puts("\nGroups")
      IO.puts(String.duplicate("=", 40))

      config.groups
      |> Map.values()
      |> Enum.sort_by(& &1.name)
      |> Enum.each(&print_group/1)
    end

    IO.puts("")
  end

  defp print_sorted_tasks(config, sorted) do
    Enum.each(sorted, fn name ->
      task = Map.get(config.tasks, name)
      if task, do: print_task(task)
    end)
  end

  defp print_task(task) do
    deps_str =
      if Enum.empty?(task.deps) do
        ""
      else
        " (deps: #{Enum.map_join(task.deps, ", ", &Atom.to_string/1)})"
      end

    on_str =
      if task.on == :local do
        ""
      else
        " [on: #{task.on}]"
      end

    cmd_count = length(task.commands)
    cmd_str = if cmd_count == 1, do: "1 command", else: "#{cmd_count} commands"

    IO.puts("  #{task.name}#{deps_str}#{on_str}")
    IO.puts("    #{cmd_str}")
  end

  defp print_host(host) do
    user_str = if host.user, do: "#{host.user}@", else: ""
    port_str = if host.port != 22, do: ":#{host.port}", else: ""
    IO.puts("  #{host.name}: #{user_str}#{host.hostname}#{port_str}")
  end

  defp print_group(group) do
    hosts_str = Enum.map_join(group.hosts, ", ", &Atom.to_string/1)
    IO.puts("  #{group.name}: [#{hosts_str}]")
  end

  defp format_error({:file_not_found, path}) do
    "Config file not found: #{path}"
  end

  defp format_error(reason) do
    inspect(reason)
  end
end
