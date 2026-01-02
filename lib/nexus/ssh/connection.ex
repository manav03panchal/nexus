defmodule Nexus.SSH.Connection do
  @moduledoc """
  SSH connection management for Nexus.

  Provides a clean interface for establishing SSH connections, executing
  commands on remote hosts, and managing connection lifecycle. Built on
  top of SSHKit for the underlying SSH operations.

  ## Usage

      {:ok, conn} = Nexus.SSH.Connection.connect(host, user: "deploy")
      {:ok, output, 0} = Nexus.SSH.Connection.exec(conn, "whoami")
      :ok = Nexus.SSH.Connection.close(conn)

  ## Authentication

  Connections support multiple authentication methods:
  - SSH key files (Ed25519, RSA, ECDSA)
  - SSH agent forwarding
  - Password authentication

  See `Nexus.SSH.Auth` for authentication resolution.
  """

  @behaviour Nexus.SSH.Behaviour

  alias Nexus.Types.Host
  alias SSHKit.SSH

  @type conn :: %SSHKit.SSH.Connection{}
  @type output :: String.t()
  @type exit_code :: non_neg_integer()
  @type connect_opts :: [connect_opt()]
  @type connect_opt ::
          {:user, String.t()}
          | {:port, pos_integer()}
          | {:timeout, pos_integer()}
          | {:identity, Path.t()}
          | {:password, String.t()}
          | {:silently_accept_hosts, boolean()}

  @type exec_opts :: [exec_opt()]
  @type exec_opt ::
          {:timeout, pos_integer()}
          | {:env, map()}

  @default_timeout 30_000
  @default_port 22

  @doc """
  Establishes an SSH connection to a host.

  ## Options

    * `:user` - Username for authentication (defaults to current user)
    * `:port` - SSH port (defaults to 22)
    * `:timeout` - Connection timeout in milliseconds (defaults to 30000)
    * `:identity` - Path to SSH private key file
    * `:password` - Password for authentication (not recommended)
    * `:silently_accept_hosts` - Accept unknown host keys (defaults to false)

  ## Examples

      # Connect with default options
      {:ok, conn} = Connection.connect("example.com")

      # Connect with specific user and key
      {:ok, conn} = Connection.connect("example.com",
        user: "deploy",
        identity: "~/.ssh/deploy_key"
      )

      # Connect to a Host struct
      host = %Host{name: :web1, hostname: "example.com", user: "deploy", port: 22}
      {:ok, conn} = Connection.connect(host)

  """
  @impl Nexus.SSH.Behaviour
  @spec connect(Host.t() | String.t(), connect_opts()) :: {:ok, conn()} | {:error, term()}
  def connect(host, opts \\ [])

  def connect(%Host{} = host, opts) do
    merged_opts =
      opts
      |> maybe_put(:user, host.user)
      |> maybe_put(:port, host.port)

    connect(host.hostname, merged_opts)
  end

  def connect(hostname, opts) when is_binary(hostname) do
    ssh_opts = build_ssh_opts(opts)

    case SSH.connect(hostname, ssh_opts) do
      {:ok, conn} ->
        {:ok, conn}

      {:error, :timeout} ->
        {:error, {:connection_timeout, hostname}}

      {:error, :econnrefused} ->
        {:error, {:connection_refused, hostname}}

      {:error, :nxdomain} ->
        {:error, {:hostname_not_found, hostname}}

      {:error, :ehostunreach} ->
        {:error, {:host_unreachable, hostname}}

      {:error, reason} ->
        {:error, {:connection_failed, hostname, reason}}
    end
  end

  @doc """
  Executes a command on a connected SSH session.

  Returns `{:ok, output, exit_code}` on success, where `output` is the
  combined stdout and stderr, and `exit_code` is the command's exit status.

  ## Options

    * `:timeout` - Command execution timeout in milliseconds (defaults to 60000)
    * `:env` - Environment variables to set for the command

  ## Examples

      {:ok, output, 0} = Connection.exec(conn, "whoami")
      {:ok, output, 0} = Connection.exec(conn, "ls -la", timeout: 5_000)

  """
  @impl Nexus.SSH.Behaviour
  @spec exec(conn(), String.t(), exec_opts()) ::
          {:ok, output(), exit_code()} | {:error, term()}
  def exec(conn, command, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 60_000)
    env = Keyword.get(opts, :env, %{})

    # Prepend environment variable exports if any
    full_command = build_command_with_env(command, env)

    case SSH.run(conn, full_command, timeout: timeout) do
      {:ok, output_list, exit_code} ->
        output = format_output(output_list)
        {:ok, output, exit_code}

      {:error, :timeout} ->
        {:error, {:command_timeout, command}}

      {:error, :closed} ->
        {:error, :connection_closed}

      {:error, reason} ->
        {:error, {:exec_failed, command, reason}}
    end
  end

  @doc """
  Executes a command with streaming output.

  The callback function is called with each chunk of output as it arrives.
  Chunks are tuples of `{:stdout, data}` or `{:stderr, data}`.

  Returns `{:ok, exit_code}` on success.

  ## Examples

      callback = fn
        {:stdout, data} -> IO.write(data)
        {:stderr, data} -> IO.write([:red, data, :reset])
      end

      {:ok, 0} = Connection.exec_streaming(conn, "tail -f /var/log/app.log", callback)

  """
  @spec exec_streaming(conn(), String.t(), (term() -> any()), exec_opts()) ::
          {:ok, exit_code()} | {:error, term()}
  def exec_streaming(conn, command, callback, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, :infinity)
    env = Keyword.get(opts, :env, %{})
    full_command = build_command_with_env(command, env)
    handler = build_streaming_handler(callback)

    case SSH.run(conn, full_command, timeout: timeout, fun: handler, acc: {:cont, {nil}}) do
      {:ok, {exit_code}} ->
        {:ok, exit_code || 0}

      # Handler returns the accumulator directly when using custom fun
      {exit_code} when is_integer(exit_code) or is_nil(exit_code) ->
        {:ok, exit_code || 0}

      {:error, reason} ->
        {:error, {:exec_failed, command, reason}}
    end
  end

  defp build_streaming_handler(callback) do
    fn message, {status} ->
      handle_stream_message(message, status, callback)
    end
  end

  defp handle_stream_message({:data, _, 0, data}, status, callback) do
    callback.({:stdout, data})
    {:cont, {status}}
  end

  defp handle_stream_message({:data, _, 1, data}, status, callback) do
    callback.({:stderr, data})
    {:cont, {status}}
  end

  defp handle_stream_message({:exit_status, _, code}, _status, _callback) do
    {:cont, {code}}
  end

  defp handle_stream_message({:eof, _}, status, _callback) do
    {:cont, {status}}
  end

  defp handle_stream_message({:closed, _}, status, _callback) do
    {:halt, {status}}
  end

  defp handle_stream_message(_message, status, _callback) do
    {:cont, {status}}
  end

  @doc """
  Closes an SSH connection.

  Always returns `:ok`, even if the connection was already closed.

  ## Examples

      :ok = Connection.close(conn)

  """
  @impl Nexus.SSH.Behaviour
  @spec close(conn()) :: :ok
  def close(conn) do
    SSH.close(conn)
  end

  @doc """
  Executes a command with sudo privileges.

  This wraps the command with `sudo` and handles password input if needed.

  ## Options

    * `:sudo_user` - User to run as (defaults to root)
    * `:password` - Password for sudo (if required)
    * All options from `exec/3`

  ## Examples

      {:ok, output, 0} = Connection.exec_sudo(conn, "systemctl restart nginx")
      {:ok, output, 0} = Connection.exec_sudo(conn, "cat /etc/shadow", sudo_user: "root")

  """
  @spec exec_sudo(conn(), String.t(), keyword()) ::
          {:ok, output(), exit_code()} | {:error, term()}
  def exec_sudo(conn, command, opts \\ []) do
    {sudo_user, opts} = Keyword.pop(opts, :sudo_user)
    {_password, opts} = Keyword.pop(opts, :password)

    sudo_prefix =
      case sudo_user do
        nil -> "sudo"
        user -> "sudo -u #{user}"
      end

    # For non-interactive sudo, we assume NOPASSWD is configured
    # or the user has already authenticated
    sudo_command = "#{sudo_prefix} -- sh -c #{escape_shell_command(command)}"

    exec(conn, sudo_command, opts)
  end

  @doc """
  Checks if a connection is still alive.

  Attempts a simple command to verify the connection is responsive.

  ## Examples

      true = Connection.alive?(conn)

  """
  @spec alive?(conn()) :: boolean()
  def alive?(nil), do: false

  def alive?(conn) do
    case exec(conn, "echo ok", timeout: 5_000) do
      {:ok, _, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc """
  Returns the underlying Erlang SSH connection reference.

  This is used internally for SFTP operations that require
  direct access to the SSH connection.
  """
  @spec get_ssh_connection(conn()) :: term()
  def get_ssh_connection(%SSHKit.SSH.Connection{ref: ref}), do: ref

  # Private functions

  defp build_ssh_opts(opts) do
    user = Keyword.get(opts, :user, current_user())
    port = Keyword.get(opts, :port, @default_port)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    silently_accept_hosts = Keyword.get(opts, :silently_accept_hosts, false)

    base_opts = [
      user: String.to_charlist(user),
      port: port,
      connect_timeout: timeout,
      silently_accept_hosts: silently_accept_hosts
    ]

    base_opts
    |> maybe_add_identity(Keyword.get(opts, :identity))
    |> maybe_add_password(Keyword.get(opts, :password))
  end

  defp maybe_add_identity(opts, nil), do: opts

  defp maybe_add_identity(opts, identity) do
    # Set user_dir to the directory containing the key
    # Erlang SSH will look for standard key names (id_rsa, id_ed25519, etc.)
    expanded = Path.expand(identity)
    Keyword.put(opts, :user_dir, String.to_charlist(Path.dirname(expanded)))
  end

  defp maybe_add_password(opts, nil), do: opts

  defp maybe_add_password(opts, password) do
    Keyword.put(opts, :password, String.to_charlist(password))
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put_new(opts, key, value)

  defp current_user do
    System.get_env("USER") || System.get_env("USERNAME") || "root"
  end

  defp format_output(output_list) when is_list(output_list) do
    output_list
    |> Enum.reverse()
    |> Enum.map_join(fn
      {:stdout, data} -> data
      {:stderr, data} -> data
    end)
  end

  defp build_command_with_env(command, env) when map_size(env) == 0, do: command

  defp build_command_with_env(command, env) do
    exports =
      Enum.map_join(env, "; ", fn {key, value} ->
        "export #{key}=#{escape_shell_value(value)}"
      end)

    "#{exports}; #{command}"
  end

  defp escape_shell_value(value) when is_binary(value) do
    "'#{String.replace(value, "'", "'\\''")}'"
  end

  defp escape_shell_value(value), do: escape_shell_value(to_string(value))

  defp escape_shell_command(command) do
    "'#{String.replace(command, "'", "'\\''")}'"
  end
end
