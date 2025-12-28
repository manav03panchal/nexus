defmodule Nexus.Executor.Local do
  @moduledoc """
  Executes commands locally on the host machine.

  Provides both synchronous execution with captured output and
  streaming execution for real-time output processing.

  ## Examples

      # Simple command execution
      {:ok, output, 0} = Nexus.Executor.Local.run("echo hello")

      # With options
      {:ok, output, 0} = Nexus.Executor.Local.run("ls", cd: "/tmp", env: [{"FOO", "bar"}])

      # Streaming output
      Nexus.Executor.Local.run_streaming("make build", fn
        {:stdout, data} -> IO.write(data)
        {:exit, code} -> IO.puts("Build finished with code \#{code}")
      end)

  """

  alias Nexus.Types.Command

  @type output :: String.t()
  @type exit_code :: non_neg_integer()
  @type stream_chunk :: {:stdout, binary()} | {:exit, exit_code()}
  @type stream_callback :: (stream_chunk() -> any())

  @type run_opts :: [
          cd: Path.t(),
          env: [{String.t(), String.t()}],
          timeout: pos_integer()
        ]

  @type run_result :: {:ok, output(), exit_code()} | {:error, term()}
  @type stream_result :: {:ok, exit_code()} | {:error, term()}

  @default_timeout 60_000

  @doc """
  Executes a command and captures its output.

  Returns `{:ok, output, exit_code}` on completion or `{:error, reason}` on failure.

  ## Options

    * `:cd` - Working directory for the command
    * `:env` - List of `{name, value}` environment variables
    * `:timeout` - Maximum execution time in milliseconds (default: 60000)

  ## Examples

      iex> {:ok, output, 0} = Nexus.Executor.Local.run("echo hello")
      iex> String.trim(output)
      "hello"

      iex> {:ok, _, code} = Nexus.Executor.Local.run("exit 1")
      iex> code
      1

  """
  @spec run(String.t() | Command.t(), run_opts()) :: run_result()
  def run(command, opts \\ [])

  def run(%Command{} = command, opts) do
    merged_opts = Keyword.put_new(opts, :timeout, command.timeout)
    run(command.cmd, merged_opts)
  end

  def run(command, opts) when is_binary(command) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    shell_opts = build_shell_opts(opts)

    task =
      Task.async(fn ->
        {output, exit_code} = System.shell(command, shell_opts)
        {:ok, output, exit_code}
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  @doc """
  Executes a command with streaming output.

  Calls the callback function for each chunk of output received.
  The callback receives tagged tuples:

    * `{:stdout, data}` - Standard output data (includes stderr)
    * `{:exit, code}` - Process exit code

  Returns `{:ok, exit_code}` on completion or `{:error, reason}` on failure.

  ## Examples

      Nexus.Executor.Local.run_streaming("make build", fn
        {:stdout, data} -> IO.write(data)
        {:exit, code} -> IO.puts("Build finished with code \#{code}")
      end)

  """
  @spec run_streaming(String.t() | Command.t(), run_opts(), stream_callback()) :: stream_result()
  def run_streaming(command, opts \\ [], callback)

  def run_streaming(%Command{} = command, opts, callback) do
    merged_opts = Keyword.put_new(opts, :timeout, command.timeout)
    run_streaming(command.cmd, merged_opts, callback)
  end

  def run_streaming(command, opts, callback)
      when is_binary(command) and is_function(callback, 1) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    port_opts = build_port_opts(opts)
    shell_command = "/bin/sh -c " <> shell_escape(command)

    task =
      Task.async(fn ->
        port = Port.open({:spawn, shell_command}, port_opts)
        stream_loop(port, callback)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  @doc """
  Executes a command with sudo privileges.

  ## Options

  Same as `run/2` plus:

    * `:user` - Run as specific user (sudo -u)

  """
  @spec run_sudo(String.t() | Command.t(), run_opts()) :: run_result()
  def run_sudo(command, opts \\ [])

  def run_sudo(%Command{} = command, opts) do
    run_sudo(command.cmd, Keyword.merge([user: command.user], opts))
  end

  def run_sudo(command, opts) when is_binary(command) do
    user = Keyword.get(opts, :user)

    sudo_cmd =
      if user do
        "sudo -u #{user} #{command}"
      else
        "sudo #{command}"
      end

    run(sudo_cmd, opts)
  end

  # Private functions

  @spec build_shell_opts(run_opts()) :: keyword()
  defp build_shell_opts(opts) do
    base = [stderr_to_stdout: true]

    base
    |> add_if_present(:cd, opts)
    |> add_if_present(:env, opts)
  end

  @spec build_port_opts(run_opts()) :: list()
  defp build_port_opts(opts) do
    base = [:binary, :exit_status, :stderr_to_stdout, {:line, 4096}]

    base
    |> add_cd_if_present(opts)
    |> add_env_if_present(opts)
  end

  defp add_if_present(acc, key, opts) do
    case Keyword.get(opts, key) do
      nil -> acc
      value -> Keyword.put(acc, key, value)
    end
  end

  defp add_cd_if_present(acc, opts) do
    case Keyword.get(opts, :cd) do
      nil -> acc
      dir -> [{:cd, to_charlist(dir)} | acc]
    end
  end

  defp add_env_if_present(acc, opts) do
    case Keyword.get(opts, :env) do
      nil ->
        acc

      env_list ->
        charlist_env = Enum.map(env_list, fn {k, v} -> {to_charlist(k), to_charlist(v)} end)
        [{:env, charlist_env} | acc]
    end
  end

  defp stream_loop(port, callback) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        callback.({:stdout, line <> "\n"})
        stream_loop(port, callback)

      {^port, {:data, {:noeol, line}}} ->
        callback.({:stdout, line})
        stream_loop(port, callback)

      {^port, {:exit_status, code}} ->
        callback.({:exit, code})
        {:ok, code}
    end
  end

  defp shell_escape(command) do
    escaped = String.replace(command, "'", "'\"'\"'")
    "'#{escaped}'"
  end
end
