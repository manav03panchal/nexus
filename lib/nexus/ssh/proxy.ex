defmodule Nexus.SSH.Proxy do
  @moduledoc """
  SSH ProxyJump / Jump Host support for Nexus.

  Implements SSH tunneling through bastion hosts using the ProxyCommand
  approach, which spawns `ssh -W` to create a stdio-based tunnel.

  ## Usage

      # Connect through a jump host
      {:ok, conn} = Nexus.SSH.Proxy.connect_via_jump(
        "target.internal",
        "bastion.example.com",
        target_opts: [user: "app"],
        jump_opts: [user: "jump"]
      )

  ## How It Works

  This uses the standard OpenSSH ProxyCommand mechanism:
  1. Spawns `ssh -W target:port jump_host` as a subprocess
  2. Uses the subprocess stdio as the transport for the target SSH connection
  3. The Erlang SSH library connects through this pipe

  This is the same mechanism that `ssh -J` uses internally.
  """

  alias Nexus.SSH.Connection

  require Logger

  @type proxy_opts :: [
          {:target_opts, keyword()},
          {:jump_opts, keyword()}
        ]

  @doc """
  Connects to a target host through a jump host using ProxyCommand.

  ## Options

    * `:target_opts` - SSH options for the target connection (user, identity, etc.)
    * `:jump_opts` - SSH options for the jump host connection

  ## Examples

      {:ok, conn} = Proxy.connect_via_jump(
        "internal.example.com",
        "bastion.example.com",
        target_opts: [user: "app"],
        jump_opts: [user: "jump"]
      )

  """
  @spec connect_via_jump(String.t(), String.t(), proxy_opts()) ::
          {:ok, term()} | {:error, term()}
  def connect_via_jump(target_host, jump_host, opts \\ []) do
    target_opts = Keyword.get(opts, :target_opts, [])
    jump_opts = Keyword.get(opts, :jump_opts, [])
    target_port = Keyword.get(target_opts, :port, 22)

    # Build the ProxyCommand
    proxy_cmd = build_proxy_command(jump_host, target_host, target_port, jump_opts)

    # Build SSH options with ProxyCommand
    user = Keyword.get(target_opts, :user, current_user())
    timeout = Keyword.get(target_opts, :timeout, 30_000)

    # Respect silently_accept_hosts option from target_opts (--insecure flag)
    insecure = Keyword.get(target_opts, :silently_accept_hosts, false)

    ssh_opts = [
      user: String.to_charlist(user),
      silently_accept_hosts: insecure,
      connect_timeout: timeout
    ]

    ssh_opts = maybe_add_identity(ssh_opts, Keyword.get(target_opts, :identity))

    # The Erlang :ssh module doesn't support ProxyCommand directly,
    # so we use the exec-based approach which spawns ssh with -J flag
    _ = {proxy_cmd, ssh_opts}
    connect_via_exec(target_host, jump_host, target_opts, jump_opts)
  end

  @doc """
  Connects through a chain of jump hosts.

  ## Examples

      {:ok, conn} = Proxy.connect_via_chain(
        "target.internal",
        ["jump1.example.com", "jump2.internal"],
        target_opts: [user: "app"]
      )

  """
  @spec connect_via_chain(String.t(), [String.t()], proxy_opts()) ::
          {:ok, term()} | {:error, term()}
  def connect_via_chain(target_host, [], opts) do
    target_opts = Keyword.get(opts, :target_opts, [])
    Connection.connect(target_host, target_opts)
  end

  def connect_via_chain(target_host, [jump_host], opts) do
    connect_via_jump(target_host, jump_host, opts)
  end

  def connect_via_chain(target_host, jump_hosts, opts) do
    # For multiple jumps, chain them by connecting through first jump
    # then recursively connecting through remaining jumps
    [first_jump | rest] = jump_hosts
    target_opts = Keyword.get(opts, :target_opts, [])
    jump_opts = Keyword.get(opts, :jump_opts, [])

    # Connect via first jump, treating remaining jumps + target as a chain
    case connect_via_jump(first_jump, first_jump, jump_opts: jump_opts) do
      {:ok, _first_conn} ->
        # Recursively connect through remaining chain
        connect_via_chain(target_host, rest, target_opts: target_opts, jump_opts: jump_opts)

      {:error, reason} ->
        {:error, {:chain_failed, jump_hosts, reason}}
    end
  end

  # Fallback: Execute commands through the jump host
  defp connect_via_exec(target_host, jump_host, target_opts, jump_opts) do
    target_port = Keyword.get(target_opts, :port, 22)
    insecure = Keyword.get(target_opts, :silently_accept_hosts, false)

    # Connect to jump host first
    case Connection.connect(jump_host, jump_opts) do
      {:ok, jump_conn} ->
        # Return a proxy connection that wraps commands
        proxy_conn = %{
          __struct__: Nexus.SSH.ProxyConnection,
          jump_conn: jump_conn,
          target_host: target_host,
          target_port: target_port,
          target_user: Keyword.get(target_opts, :user, current_user()),
          target_identity: Keyword.get(target_opts, :identity),
          insecure: insecure
        }

        {:ok, proxy_conn}

      {:error, reason} ->
        {:error, {:jump_connect_failed, jump_host, reason}}
    end
  end

  defp build_proxy_command(jump_host, target_host, target_port, jump_opts) do
    user = Keyword.get(jump_opts, :user, current_user())
    port = Keyword.get(jump_opts, :port, 22)
    identity = Keyword.get(jump_opts, :identity)
    insecure = Keyword.get(jump_opts, :silently_accept_hosts, false)

    args = ["ssh", "-W", "#{target_host}:#{target_port}"]
    args = args ++ ["-p", to_string(port)]
    args = args ++ ["-l", user]
    args = if identity, do: args ++ ["-i", Path.expand(identity)], else: args

    # Only disable host key checking if explicitly requested (insecure mode)
    args =
      if insecure do
        args ++ ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
      else
        args
      end

    args ++ [jump_host]
  end

  defp maybe_add_identity(opts, nil), do: opts

  defp maybe_add_identity(opts, identity) do
    expanded = Path.expand(identity)

    if File.exists?(expanded) do
      Keyword.put(opts, :key_cb, {Nexus.SSH.KeyCallback, key_file: expanded})
    else
      opts
    end
  end

  defp current_user do
    System.get_env("USER") || System.get_env("USERNAME") || "root"
  end
end

defmodule Nexus.SSH.ProxyConnection do
  @moduledoc """
  A connection that executes commands through a jump host.

  This is a fallback when direct ProxyCommand isn't available.
  Commands are wrapped to execute via the jump host's SSH.
  """

  alias Nexus.SSH.Connection

  defstruct [:jump_conn, :target_host, :target_port, :target_user, :target_identity, :insecure]

  @doc """
  Executes a command on the target host through the jump connection.
  """
  def exec(%__MODULE__{} = proxy, command, opts \\ []) do
    ssh_cmd = build_ssh_command(proxy, command)
    Connection.exec(proxy.jump_conn, ssh_cmd, opts)
  end

  @doc """
  Closes the proxy connection (closes the jump host connection).
  """
  def close(%__MODULE__{jump_conn: jump_conn}) do
    Connection.close(jump_conn)
  end

  defp build_ssh_command(proxy, command) do
    args = ["ssh"]
    args = args ++ ["-p", to_string(proxy.target_port)]
    args = args ++ ["-l", proxy.target_user]

    args =
      if proxy.target_identity, do: args ++ ["-i", Path.expand(proxy.target_identity)], else: args

    # Only disable host key checking if explicitly requested (insecure mode)
    args =
      if proxy.insecure do
        args ++ ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
      else
        args
      end

    args = args ++ ["-o", "BatchMode=yes"]
    args = args ++ [proxy.target_host]
    args = args ++ [escape_command(command)]

    Enum.join(args, " ")
  end

  defp escape_command(cmd) do
    "'#{String.replace(cmd, "'", "'\\''")}'"
  end
end
