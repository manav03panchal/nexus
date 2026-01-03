defmodule Nexus.DSL.Importer do
  @moduledoc """
  Handles importing external DSL files into the main configuration.

  Supports importing configuration, tasks, and handlers from separate files
  to enable modular project organization.

  ## Example

      # nexus.exs
      import_config "config/hosts.exs"
      import_config "config/settings.exs"
      import_tasks "tasks/*.exs"
      import_handlers "handlers/*.exs"

      task :deploy, deps: [:build] do
        run "deploy.sh"
      end

  """

  @doc """
  Resolves and reads all files matching a glob pattern.

  Returns a list of `{path, content}` tuples for all matching files,
  sorted alphabetically for deterministic ordering.

  ## Options

    * `:base_path` - The base directory for relative paths (required)

  ## Examples

      iex> Importer.resolve_glob("tasks/*.exs", base_path: "/project")
      {:ok, [{"/project/tasks/build.exs", "..."}, {"/project/tasks/deploy.exs", "..."}]}

  """
  @spec resolve_glob(String.t(), keyword()) ::
          {:ok, [{String.t(), String.t()}]} | {:error, String.t()}
  def resolve_glob(pattern, opts) do
    base_path = Keyword.fetch!(opts, :base_path)

    full_pattern = Path.join(base_path, pattern)

    paths = Path.wildcard(full_pattern) |> Enum.sort()

    if Enum.empty?(paths) and not glob_pattern?(pattern) do
      # If it's not a glob pattern and no files found, it's an error
      {:error, "file not found: #{pattern}"}
    else
      read_files(paths)
    end
  end

  @doc """
  Resolves and reads a single file.

  ## Options

    * `:base_path` - The base directory for relative paths (required)

  """
  @spec resolve_file(String.t(), keyword()) ::
          {:ok, String.t(), String.t()} | {:error, String.t()}
  def resolve_file(path, opts) do
    base_path = Keyword.fetch!(opts, :base_path)

    full_path =
      if Path.type(path) == :absolute do
        path
      else
        Path.join(base_path, path)
      end

    case File.read(full_path) do
      {:ok, content} ->
        {:ok, full_path, content}

      {:error, reason} ->
        {:error, "failed to read #{path}: #{:file.format_error(reason)}"}
    end
  end

  @doc """
  Checks if a pattern contains glob wildcards.
  """
  @spec glob_pattern?(String.t()) :: boolean()
  def glob_pattern?(pattern) do
    String.contains?(pattern, ["*", "?", "[", "{"])
  end

  @doc """
  Detects circular imports in the import chain.

  Returns `{:ok, updated_chain}` if no circular import detected,
  or `{:error, reason}` if a circular import is found.
  """
  @spec check_circular_import(String.t(), MapSet.t()) :: {:ok, MapSet.t()} | {:error, String.t()}
  def check_circular_import(path, import_chain) do
    normalized = Path.expand(path)

    if MapSet.member?(import_chain, normalized) do
      {:error, "circular import detected: #{path}"}
    else
      {:ok, MapSet.put(import_chain, normalized)}
    end
  end

  @doc """
  Extracts the directory containing a file path.
  Used to resolve relative imports from imported files.
  """
  @spec base_dir(String.t()) :: String.t()
  def base_dir(file_path) do
    Path.dirname(file_path)
  end

  # Private helpers

  defp read_files(paths) do
    results =
      Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, acc} ->
        case File.read(path) do
          {:ok, content} ->
            {:cont, {:ok, [{path, content} | acc]}}

          {:error, reason} ->
            {:halt, {:error, "failed to read #{path}: #{:file.format_error(reason)}"}}
        end
      end)

    case results do
      {:ok, files} -> {:ok, Enum.reverse(files)}
      error -> error
    end
  end
end
