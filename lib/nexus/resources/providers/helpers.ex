defmodule Nexus.Resources.Providers.Helpers do
  @moduledoc """
  Shared helper functions for resource providers.

  Provides common utilities for:
  - Shell command execution (local and remote via SSH)
  - String escaping for safe shell commands
  - Path validation and manipulation
  """

  alias Nexus.SSH.Connection

  @doc """
  Executes a shell command either locally or via SSH connection.

  ## Options

    * `:sudo` - Run command with sudo (default: false)

  ## Examples

      # Local execution
      exec(nil, "whoami")
      {:ok, "root\\n", 0}

      # Remote execution
      exec(conn, "uname -a")
      {:ok, "Linux ...", 0}

      # With sudo
      exec(conn, "apt update", sudo: true)

  """
  @spec exec(Connection.conn() | nil, String.t(), keyword()) ::
          {:ok, String.t(), integer()} | {:error, term()}
  def exec(conn, cmd, opts \\ [])

  def exec(nil, cmd, opts) do
    full_cmd =
      if Keyword.get(opts, :sudo, false), do: "sudo sh -c #{escape_single(cmd)}", else: cmd

    case System.cmd("sh", ["-c", full_cmd], stderr_to_stdout: true) do
      {output, code} -> {:ok, output, code}
    end
  end

  def exec(conn, cmd, opts) when conn != nil do
    if Keyword.get(opts, :sudo, false) do
      Connection.exec_sudo(conn, cmd)
    else
      Connection.exec(conn, cmd)
    end
  end

  @doc """
  Escapes a string for safe use in single-quoted shell arguments.

  Wraps the string in single quotes and escapes any embedded single quotes.

  ## Examples

      iex> escape_single("hello world")
      "'hello world'"

      iex> escape_single("it's working")
      "'it'\\''s working'"

  """
  @spec escape_single(String.t()) :: String.t()
  def escape_single(str) when is_binary(str) do
    "'" <> String.replace(str, "'", "'\\''") <> "'"
  end

  @doc """
  Escapes a string for safe use as a package name or service name.

  Only allows alphanumeric characters, dots, underscores, plus, minus, and at signs.

  ## Examples

      iex> escape_name("nginx")
      "nginx"

      iex> escape_name("php8.1-fpm")
      "php8.1-fpm"

      iex> escape_name("bad;rm -rf /")
      "badrm-rf"

  """
  @spec escape_name(String.t()) :: String.t()
  def escape_name(str) when is_binary(str) do
    String.replace(str, ~r/[^a-zA-Z0-9._+@-]/, "")
  end

  @doc """
  Escapes a string for safe use as a path (allows forward slashes).

  ## Examples

      iex> escape_path("/usr/local/bin")
      "/usr/local/bin"

  """
  @spec escape_path(String.t()) :: String.t()
  def escape_path(str) when is_binary(str) do
    String.replace(str, ~r/[^a-zA-Z0-9._+@\/-]/, "")
  end

  @doc """
  Validates that a path is absolute.

  ## Examples

      iex> validate_absolute_path("/etc/nginx")
      :ok

      iex> validate_absolute_path("relative/path")
      {:error, "path must be absolute: relative/path"}

  """
  @spec validate_absolute_path(String.t()) :: :ok | {:error, String.t()}
  def validate_absolute_path(path) when is_binary(path) do
    if String.starts_with?(path, "/") do
      :ok
    else
      {:error, "path must be absolute: #{path}"}
    end
  end

  @doc """
  Validates file permission mode is within valid range.

  ## Examples

      iex> validate_mode(0o644)
      :ok

      iex> validate_mode(0o7777)
      :ok

      iex> validate_mode(0o10000)
      {:error, "invalid mode: 4096 (must be 0-7777 octal)"}

  """
  @spec validate_mode(integer() | nil) :: :ok | {:error, String.t()}
  def validate_mode(nil), do: :ok

  def validate_mode(mode) when is_integer(mode) do
    if mode >= 0 and mode <= 0o7777 do
      :ok
    else
      {:error, "invalid mode: #{mode} (must be 0-7777 octal)"}
    end
  end

  @doc """
  Formats a mode integer as an octal string for shell commands.

  ## Examples

      iex> format_mode(0o644)
      "644"

      iex> format_mode(0o755)
      "755"

  """
  @spec format_mode(integer()) :: String.t()
  def format_mode(mode) when is_integer(mode) do
    Integer.to_string(mode, 8)
  end

  @doc """
  Parses command output to extract exit code and output.

  Handles various output formats from SSH execution.
  """
  @spec parse_exit_code({:ok, String.t(), integer()} | {:error, term()}) ::
          {:ok, integer()} | {:error, term()}
  def parse_exit_code({:ok, _output, code}), do: {:ok, code}
  def parse_exit_code({:error, _} = error), do: error

  @doc """
  Checks if a command succeeded (exit code 0).
  """
  @spec command_succeeded?({:ok, String.t(), integer()} | {:error, term()}) :: boolean()
  def command_succeeded?({:ok, _output, 0}), do: true
  def command_succeeded?(_), do: false

  @doc """
  Joins multiple package/service names into a space-separated string.

  ## Examples

      iex> join_names(["nginx", "curl", "vim"])
      "nginx curl vim"

  """
  @spec join_names([String.t()]) :: String.t()
  def join_names(names) when is_list(names) do
    Enum.map_join(names, " ", &escape_name/1)
  end
end
