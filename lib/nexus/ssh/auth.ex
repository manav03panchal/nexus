defmodule Nexus.SSH.Auth do
  @moduledoc """
  SSH authentication resolution for Nexus.

  Handles the discovery and resolution of SSH authentication methods,
  supporting multiple authentication strategies in priority order:

  1. Explicit identity file (passed via options)
  2. SSH agent (if SSH_AUTH_SOCK is set)
  3. Default key files (~/.ssh/id_ed25519, ~/.ssh/id_rsa, etc.)
  4. Password authentication (interactive, if enabled)

  ## Usage

      {:ok, auth_opts} = Nexus.SSH.Auth.resolve("example.com", user: "deploy")
      # auth_opts can be passed directly to SSH.Connection.connect/2

  """

  @type auth_method ::
          {:identity, Path.t()}
          | :agent
          | {:password, String.t()}
          | :none

  @type auth_opts :: keyword()

  @type resolve_opts :: [resolve_opt()]
  @type resolve_opt ::
          {:user, String.t()}
          | {:identity, Path.t()}
          | {:password, String.t()}
          | {:prefer_agent, boolean()}

  # Default SSH key filenames in priority order
  @default_key_names [
    "id_ed25519",
    "id_ecdsa",
    "id_rsa",
    "id_dsa"
  ]

  @doc """
  Resolves authentication options for connecting to a host.

  Attempts to find a working authentication method by checking:
  1. Explicit identity file (if provided)
  2. SSH agent (if available and prefer_agent is true)
  3. Default SSH keys in ~/.ssh/
  4. Falls back to no explicit auth (relies on SSH defaults)

  ## Options

    * `:user` - Username for authentication
    * `:identity` - Explicit path to SSH private key
    * `:password` - Password for authentication
    * `:prefer_agent` - Prefer SSH agent over key files (defaults to true)

  ## Examples

      # Auto-resolve authentication
      {:ok, opts} = Auth.resolve("example.com")

      # Use specific key
      {:ok, opts} = Auth.resolve("example.com", identity: "~/.ssh/deploy_key")

      # Force password auth
      {:ok, opts} = Auth.resolve("example.com", password: "secret")

  """
  @spec resolve(String.t(), resolve_opts()) :: {:ok, auth_opts()} | {:error, term()}
  def resolve(hostname, opts \\ []) do
    case resolve_auth_method(hostname, opts) do
      {:ok, auth_method} ->
        {:ok, build_auth_opts(auth_method, opts)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_auth_method(hostname, opts) do
    explicit_identity = Keyword.get(opts, :identity)
    password = Keyword.get(opts, :password)
    prefer_agent = Keyword.get(opts, :prefer_agent, true)

    cond do
      explicit_identity != nil ->
        resolve_identity(explicit_identity)

      password != nil ->
        {:ok, {:password, password}}

      prefer_agent and agent_available?() ->
        {:ok, :agent}

      true ->
        resolve_default_key(hostname, opts)
    end
  end

  defp resolve_default_key(hostname, opts) do
    user = Keyword.get(opts, :user)

    case find_default_key(hostname, user) do
      {:ok, key_path} -> {:ok, {:identity, key_path}}
      :not_found -> {:ok, :none}
    end
  end

  @doc """
  Returns the resolved authentication method as a descriptive atom or tuple.

  Useful for logging and debugging authentication issues.

  ## Examples

      {:identity, "/home/user/.ssh/id_ed25519"} = Auth.method(opts)
      :agent = Auth.method(opts)

  """
  @spec method(auth_opts()) :: auth_method()
  def method(opts) do
    cond do
      Keyword.has_key?(opts, :password) ->
        {:password, "***"}

      Keyword.has_key?(opts, :identity) ->
        {:identity, Keyword.get(opts, :identity)}

      agent_available?() ->
        :agent

      true ->
        :none
    end
  end

  @doc """
  Checks if SSH agent is available.

  Returns true if the SSH_AUTH_SOCK environment variable is set
  and points to an existing socket.

  ## Examples

      true = Auth.agent_available?()

  """
  @spec agent_available?() :: boolean()
  def agent_available? do
    case System.get_env("SSH_AUTH_SOCK") do
      nil -> false
      "" -> false
      sock_path -> File.exists?(sock_path)
    end
  end

  @doc """
  Lists available SSH keys in the default SSH directory.

  Returns a list of key paths that exist and are readable.

  ## Examples

      ["/home/user/.ssh/id_ed25519", "/home/user/.ssh/id_rsa"] = Auth.available_keys()

  """
  @spec available_keys() :: [Path.t()]
  def available_keys do
    ssh_dir = ssh_directory()

    @default_key_names
    |> Enum.map(&Path.join(ssh_dir, &1))
    |> Enum.filter(&key_exists?/1)
  end

  @doc """
  Returns the SSH directory for the current user.

  Defaults to ~/.ssh but respects the HOME environment variable.

  ## Examples

      "/home/user/.ssh" = Auth.ssh_directory()

  """
  @spec ssh_directory() :: Path.t()
  def ssh_directory do
    home = System.get_env("HOME") || "~"
    Path.expand("~/.ssh", home)
  end

  # Private functions

  defp resolve_identity(identity_path) do
    expanded = Path.expand(identity_path)

    cond do
      not File.exists?(expanded) ->
        {:error, {:identity_not_found, expanded}}

      not File.regular?(expanded) ->
        {:error, {:identity_not_file, expanded}}

      not readable?(expanded) ->
        {:error, {:identity_not_readable, expanded}}

      true ->
        {:ok, {:identity, expanded}}
    end
  end

  defp find_default_key(_hostname, _user) do
    ssh_dir = ssh_directory()

    @default_key_names
    |> Enum.map(&Path.join(ssh_dir, &1))
    |> Enum.find(&key_exists?/1)
    |> case do
      nil -> :not_found
      path -> {:ok, path}
    end
  end

  defp key_exists?(path) do
    File.exists?(path) and File.regular?(path) and readable?(path)
  end

  defp readable?(path) do
    case File.stat(path) do
      {:ok, %{access: access}} when access in [:read, :read_write] -> true
      _ -> false
    end
  end

  defp build_auth_opts(auth_method, base_opts) do
    base = Keyword.take(base_opts, [:user, :port, :timeout, :silently_accept_hosts])

    case auth_method do
      {:identity, path} ->
        Keyword.put(base, :identity, path)

      {:password, pass} ->
        Keyword.put(base, :password, pass)

      :agent ->
        # SSH agent is used automatically when no explicit auth is provided
        base

      :none ->
        base
    end
  end
end
