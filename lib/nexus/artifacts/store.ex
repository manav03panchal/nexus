defmodule Nexus.Artifacts.Store do
  @moduledoc """
  Manages local artifact storage during pipeline execution.

  Artifacts are stored in a temporary directory and cleaned up
  after the pipeline completes (unless configured otherwise).

  ## Storage Location

  Default: `~/.nexus/artifacts/<pipeline-id>/`

  """

  @type pipeline_id :: String.t()
  @type artifact_name :: String.t()

  @doc """
  Initializes artifact storage for a pipeline run.

  Creates the storage directory and returns the pipeline ID.
  """
  @spec init() :: {:ok, pipeline_id()} | {:error, {:mkdir_failed, binary(), atom()}}
  def init do
    pipeline_id = generate_pipeline_id()
    path = storage_path(pipeline_id)

    case File.mkdir_p(path) do
      :ok -> {:ok, pipeline_id}
      {:error, reason} -> {:error, {:mkdir_failed, path, reason}}
    end
  end

  @doc """
  Stores an artifact in the local store.

  The content is written to `<storage_path>/<pipeline_id>/<artifact_name>`.
  """
  @spec store(pipeline_id(), artifact_name(), binary()) :: :ok | {:error, term()}
  def store(pipeline_id, artifact_name, content) when is_binary(content) do
    path = artifact_path(pipeline_id, artifact_name)

    # Ensure parent directory exists
    path |> Path.dirname() |> File.mkdir_p!()

    case File.write(path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, {:write_failed, path, reason}}
    end
  end

  @doc """
  Stores an artifact from a local file path.
  """
  @spec store_file(pipeline_id(), artifact_name(), Path.t()) :: :ok | {:error, term()}
  def store_file(pipeline_id, artifact_name, source_path) do
    dest_path = artifact_path(pipeline_id, artifact_name)

    # Ensure parent directory exists
    dest_path |> Path.dirname() |> File.mkdir_p!()

    case File.cp(source_path, dest_path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:copy_failed, source_path, dest_path, reason}}
    end
  end

  @doc """
  Retrieves an artifact's content from the store.
  """
  @spec fetch(pipeline_id(), artifact_name()) :: {:ok, binary()} | {:error, term()}
  def fetch(pipeline_id, artifact_name) do
    path = artifact_path(pipeline_id, artifact_name)

    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, {:not_found, artifact_name}}
      {:error, reason} -> {:error, {:read_failed, path, reason}}
    end
  end

  @doc """
  Returns the local file path for an artifact.
  """
  @spec get_path(pipeline_id(), artifact_name()) :: Path.t()
  def get_path(pipeline_id, artifact_name) do
    artifact_path(pipeline_id, artifact_name)
  end

  @doc """
  Checks if an artifact exists in the store.
  """
  @spec exists?(pipeline_id(), artifact_name()) :: boolean()
  def exists?(pipeline_id, artifact_name) do
    path = artifact_path(pipeline_id, artifact_name)
    File.exists?(path)
  end

  @doc """
  Lists all artifacts for a pipeline.
  """
  @spec list(pipeline_id()) :: [artifact_name()]
  def list(pipeline_id) do
    path = storage_path(pipeline_id)

    case File.ls(path) do
      {:ok, files} -> files
      {:error, _} -> []
    end
  end

  @doc """
  Cleans up artifacts for a pipeline.
  """
  @spec cleanup(pipeline_id()) :: :ok | {:error, term()}
  def cleanup(pipeline_id) do
    path = storage_path(pipeline_id)

    case File.rm_rf(path) do
      {:ok, _} -> :ok
      {:error, reason, file} -> {:error, {:cleanup_failed, file, reason}}
    end
  end

  @doc """
  Cleans up all expired artifacts.

  Removes artifact directories older than the specified TTL.
  """
  @spec cleanup_expired(pos_integer()) :: :ok
  def cleanup_expired(ttl_seconds \\ 86_400) do
    base_path = base_storage_path()
    cutoff = System.system_time(:second) - ttl_seconds

    case File.ls(base_path) do
      {:ok, dirs} ->
        Enum.each(dirs, fn dir ->
          path = Path.join(base_path, dir)
          maybe_remove_expired_dir(path, cutoff)
        end)

      {:error, _} ->
        :ok
    end
  end

  defp maybe_remove_expired_dir(path, cutoff) do
    with {:ok, %{mtime: mtime}} <- File.stat(path),
         mtime_seconds = :calendar.datetime_to_gregorian_seconds(mtime) - 62_167_219_200,
         true <- mtime_seconds < cutoff do
      File.rm_rf(path)
    else
      _ -> :ok
    end
  end

  # Private functions

  defp base_storage_path do
    Path.expand("~/.nexus/artifacts")
  end

  defp storage_path(pipeline_id) do
    Path.join(base_storage_path(), pipeline_id)
  end

  defp artifact_path(pipeline_id, artifact_name) do
    # Validate artifact_name to prevent path traversal
    safe_name = validate_artifact_name!(artifact_name)
    Path.join(storage_path(pipeline_id), safe_name)
  end

  # Validate artifact name to prevent path traversal attacks
  # Only allows alphanumeric, dash, underscore, dot (no directory separators)
  @artifact_name_pattern ~r/^[a-zA-Z0-9._-]+$/
  defp validate_artifact_name!(name) when is_binary(name) do
    # Remove any directory components for safety
    basename = Path.basename(name)

    cond do
      name != basename ->
        raise ArgumentError,
              "artifact name cannot contain directory separators: #{inspect(name)}"

      String.contains?(name, "..") ->
        raise ArgumentError,
              "artifact name cannot contain path traversal: #{inspect(name)}"

      not Regex.match?(@artifact_name_pattern, name) ->
        raise ArgumentError,
              "artifact name contains invalid characters: #{inspect(name)}"

      String.length(name) > 255 ->
        raise ArgumentError,
              "artifact name too long (max 255 chars): #{inspect(name)}"

      true ->
        basename
    end
  end

  defp validate_artifact_name!(name) do
    raise ArgumentError, "artifact name must be a string, got: #{inspect(name)}"
  end

  defp generate_pipeline_id do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{timestamp}-#{random}"
  end
end
