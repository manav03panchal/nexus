defmodule Nexus.SSH.SFTP do
  @moduledoc """
  SFTP operations using Erlang's built-in :ssh_sftp module.

  Provides file upload and download capabilities over existing SSH connections.
  Supports sudo operations by using temporary files and shell commands.

  ## Examples

      # Upload a file
      {:ok, conn} = Connection.connect(host, opts)
      :ok = SFTP.upload(conn, "local/file.txt", "/remote/file.txt")

      # Download a file
      :ok = SFTP.download(conn, "/remote/file.txt", "local/file.txt")

      # Upload with sudo (for protected directories)
      :ok = SFTP.upload(conn, "config.txt", "/etc/app/config.txt", sudo: true)

  """

  alias Nexus.SSH.Connection

  # Use struct type directly for dialyzer compatibility
  @type conn :: %SSHKit.SSH.Connection{}

  @type upload_opts :: [
          sudo: boolean(),
          mode: non_neg_integer() | nil
        ]

  @type download_opts :: [
          sudo: boolean()
        ]

  @temp_prefix "/tmp/nexus_transfer_"

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Uploads a local file to the remote host.

  ## Options

    * `:sudo` - Upload to a location requiring root access. Uses a temp file
      and `sudo mv` to place it in the final location.
    * `:mode` - File permissions to set after upload (e.g., 0o644)

  ## Examples

      SFTP.upload(conn, "dist/app.tar.gz", "/opt/app/release.tar.gz")
      SFTP.upload(conn, "nginx.conf", "/etc/nginx/nginx.conf", sudo: true, mode: 0o644)

  """
  @spec upload(conn(), String.t(), String.t(), upload_opts()) :: :ok | {:error, term()}
  def upload(conn, local_path, remote_path, opts \\ []) do
    sudo = Keyword.get(opts, :sudo, false)
    mode = Keyword.get(opts, :mode)

    case File.read(local_path) do
      {:ok, data} ->
        if sudo do
          upload_with_sudo(conn, data, remote_path, mode)
        else
          upload_direct(conn, data, remote_path, mode)
        end

      {:error, reason} ->
        {:error, {:local_file_error, reason}}
    end
  end

  @doc """
  Downloads a file from the remote host to a local path.

  ## Options

    * `:sudo` - Download from a location requiring root access. Uses
      `sudo cat` to read the file content.

  ## Examples

      SFTP.download(conn, "/var/log/app.log", "logs/app.log")
      SFTP.download(conn, "/etc/shadow", "shadow.bak", sudo: true)

  """
  @spec download(conn(), String.t(), String.t(), download_opts()) :: :ok | {:error, term()}
  def download(conn, remote_path, local_path, opts \\ []) do
    sudo = Keyword.get(opts, :sudo, false)

    result =
      if sudo do
        download_with_sudo(conn, remote_path)
      else
        download_direct(conn, remote_path)
      end

    case result do
      {:ok, data} ->
        local_dir = Path.dirname(local_path)
        File.mkdir_p!(local_dir)
        File.write(local_path, data)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Lists files in a remote directory.

  ## Examples

      {:ok, files} = SFTP.list_dir(conn, "/opt/app/releases")

  """
  @spec list_dir(conn(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def list_dir(conn, remote_path) do
    with {:ok, sftp_channel} <- start_sftp_channel(conn) do
      result = do_list_dir(sftp_channel, remote_path)
      :ssh_sftp.stop_channel(sftp_channel)
      result
    end
  end

  @doc """
  Gets file info from the remote host.

  ## Examples

      {:ok, info} = SFTP.stat(conn, "/opt/app/release.tar.gz")

  """
  @spec stat(conn(), String.t()) :: {:ok, map()} | {:error, term()}
  def stat(conn, remote_path) do
    with {:ok, sftp_channel} <- start_sftp_channel(conn) do
      result = do_stat(sftp_channel, remote_path)
      :ssh_sftp.stop_channel(sftp_channel)
      result
    end
  end

  @doc """
  Checks if a remote file exists.

  ## Examples

      true = SFTP.exists?(conn, "/opt/app/release.tar.gz")

  """
  @spec exists?(conn(), String.t()) :: boolean()
  def exists?(conn, remote_path) do
    case stat(conn, remote_path) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Creates a remote directory (with parents if needed).

  ## Examples

      :ok = SFTP.mkdir_p(conn, "/opt/app/releases/v1.0.0")

  """
  @spec mkdir_p(conn(), String.t()) ::
          :ok
          | {:error,
             :connection_closed
             | {:command_timeout, term()}
             | {:exec_failed, term(), term()}
             | {:mkdir_failed, pos_integer(), binary()}}
  def mkdir_p(conn, remote_path) do
    case Connection.exec(conn, "mkdir -p #{escape_path(remote_path)}") do
      {:ok, _, 0} -> :ok
      {:ok, output, code} -> {:error, {:mkdir_failed, code, output}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Removes a remote file.

  ## Examples

      :ok = SFTP.rm(conn, "/tmp/old_file.txt")

  """
  @spec rm(conn(), String.t()) :: :ok | {:error, term()}
  def rm(conn, remote_path) do
    with {:ok, sftp_channel} <- start_sftp_channel(conn) do
      result = do_rm(sftp_channel, remote_path)
      :ssh_sftp.stop_channel(sftp_channel)
      result
    end
  end

  # ============================================================================
  # Private Functions - Channel Operations
  # ============================================================================

  defp start_sftp_channel(conn) do
    ssh_conn = Connection.get_ssh_connection(conn)

    case :ssh_sftp.start_channel(ssh_conn) do
      {:ok, channel_pid} -> {:ok, channel_pid}
      {:error, reason} -> {:error, {:sftp_channel_error, reason}}
    end
  end

  defp do_list_dir(sftp_channel, remote_path) do
    case :ssh_sftp.list_dir(sftp_channel, String.to_charlist(remote_path)) do
      {:ok, files} -> {:ok, Enum.map(files, &to_string/1)}
      {:error, reason} -> {:error, {:sftp_error, reason}}
    end
  end

  defp do_stat(sftp_channel, remote_path) do
    case :ssh_sftp.read_file_info(sftp_channel, String.to_charlist(remote_path)) do
      {:ok, file_info} -> {:ok, parse_file_info(file_info)}
      {:error, reason} -> {:error, {:sftp_error, reason}}
    end
  end

  defp do_rm(sftp_channel, remote_path) do
    case :ssh_sftp.delete(sftp_channel, String.to_charlist(remote_path)) do
      :ok -> :ok
      {:error, reason} -> {:error, {:sftp_error, reason}}
    end
  end

  # ============================================================================
  # Private Functions - Upload
  # ============================================================================

  defp upload_direct(conn, data, remote_path, mode) do
    with {:ok, sftp_channel} <- start_sftp_channel(conn),
         :ok <- ensure_remote_dir(sftp_channel, Path.dirname(remote_path)),
         :ok <- write_file(sftp_channel, remote_path, data),
         :ok <- maybe_set_mode_via_shell(conn, remote_path, mode) do
      :ssh_sftp.stop_channel(sftp_channel)
      :ok
    end
  end

  defp upload_with_sudo(conn, data, remote_path, mode) do
    # Use cryptographic random for temp filename to prevent prediction attacks
    random_suffix = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    temp_path = "#{@temp_prefix}#{random_suffix}"

    with {:ok, sftp_channel} <- start_sftp_channel(conn),
         :ok <- write_file(sftp_channel, temp_path, data) do
      :ssh_sftp.stop_channel(sftp_channel)
      move_with_sudo(conn, temp_path, remote_path, mode)
    end
  end

  defp move_with_sudo(conn, temp_path, remote_path, mode) do
    mv_cmd = "sudo mv #{escape_path(temp_path)} #{escape_path(remote_path)}"

    case Connection.exec(conn, mv_cmd) do
      {:ok, _, 0} ->
        maybe_chmod_with_sudo(conn, remote_path, mode)

      {:ok, output, code} ->
        cleanup_temp_file(conn, temp_path)
        {:error, {:sudo_mv_failed, code, output}}

      {:error, reason} ->
        cleanup_temp_file(conn, temp_path)
        {:error, reason}
    end
  end

  defp maybe_chmod_with_sudo(_conn, _remote_path, nil), do: :ok

  defp maybe_chmod_with_sudo(conn, remote_path, mode) do
    chmod_cmd = "sudo chmod #{Integer.to_string(mode, 8)} #{escape_path(remote_path)}"

    case Connection.exec(conn, chmod_cmd) do
      {:ok, _, 0} -> :ok
      {:ok, output, code} -> {:error, {:chmod_failed, code, output}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp cleanup_temp_file(conn, temp_path) do
    Connection.exec(conn, "rm -f #{escape_path(temp_path)}")
  end

  # ============================================================================
  # Private Functions - Download
  # ============================================================================

  defp download_direct(conn, remote_path) do
    with {:ok, sftp_channel} <- start_sftp_channel(conn) do
      result = read_file(sftp_channel, remote_path)
      :ssh_sftp.stop_channel(sftp_channel)
      result
    end
  end

  defp download_with_sudo(conn, remote_path) do
    cmd = "sudo cat #{escape_path(remote_path)}"

    case Connection.exec(conn, cmd) do
      {:ok, output, 0} -> {:ok, output}
      {:ok, output, code} -> {:error, {:sudo_cat_failed, code, output}}
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================================================
  # Private Functions - File Operations
  # ============================================================================

  defp write_file(sftp_channel, remote_path, data) do
    path_charlist = String.to_charlist(remote_path)

    case :ssh_sftp.write_file(sftp_channel, path_charlist, data) do
      :ok -> :ok
      {:error, reason} -> {:error, {:sftp_write_error, reason}}
    end
  end

  defp read_file(sftp_channel, remote_path) do
    path_charlist = String.to_charlist(remote_path)

    case :ssh_sftp.read_file(sftp_channel, path_charlist) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, {:sftp_read_error, reason}}
    end
  end

  defp ensure_remote_dir(sftp_channel, dir_path) do
    path_charlist = String.to_charlist(dir_path)

    case :ssh_sftp.read_file_info(sftp_channel, path_charlist) do
      {:ok, _} -> :ok
      {:error, :no_such_file} -> create_dir_recursive(sftp_channel, dir_path)
      {:error, reason} -> {:error, {:sftp_error, reason}}
    end
  end

  defp create_dir_recursive(sftp_channel, dir_path) do
    parts = Path.split(dir_path)
    do_create_dirs(sftp_channel, parts, "")
  end

  defp do_create_dirs(_sftp_channel, [], _acc), do: :ok

  defp do_create_dirs(sftp_channel, [part | rest], acc) do
    current = Path.join(acc, part)

    case check_or_create_dir(sftp_channel, current) do
      :ok -> do_create_dirs(sftp_channel, rest, current)
      {:error, _} = error -> error
    end
  end

  defp check_or_create_dir(sftp_channel, path) do
    path_charlist = String.to_charlist(path)

    case :ssh_sftp.read_file_info(sftp_channel, path_charlist) do
      {:ok, _} ->
        :ok

      {:error, :no_such_file} ->
        case :ssh_sftp.make_dir(sftp_channel, path_charlist) do
          :ok -> :ok
          {:error, reason} -> {:error, {:mkdir_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:sftp_error, reason}}
    end
  end

  defp maybe_set_mode_via_shell(_conn, _remote_path, nil), do: :ok

  defp maybe_set_mode_via_shell(conn, remote_path, mode) do
    chmod_cmd = "chmod #{Integer.to_string(mode, 8)} #{escape_path(remote_path)}"

    case Connection.exec(conn, chmod_cmd) do
      {:ok, _, 0} -> :ok
      # Ignore chmod failures - not critical
      _ -> :ok
    end
  end

  defp parse_file_info(file_info) do
    # file_info record fields: size, type, access, atime, mtime, ctime, mode, links, etc.
    case :erlang.tuple_to_list(file_info) do
      [
        :file_info,
        size,
        type,
        access,
        atime,
        mtime,
        ctime,
        mode,
        links,
        _major,
        _minor,
        _inode,
        uid,
        gid
      ] ->
        %{
          size: size,
          type: type,
          access: access,
          atime: atime,
          mtime: mtime,
          ctime: ctime,
          mode: mode,
          links: links,
          uid: uid,
          gid: gid
        }

      _ ->
        %{}
    end
  end

  defp escape_path(path) do
    escaped = String.replace(path, "'", "'\\''")
    "'#{escaped}'"
  end
end
