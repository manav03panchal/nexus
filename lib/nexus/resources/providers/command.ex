defmodule Nexus.Resources.Providers.Command do
  @moduledoc """
  Command provider - executes shell commands with idempotency guards.

  Unlike simple shell execution, this provider supports:
  - `creates:` - Skip if path exists
  - `removes:` - Skip if path doesn't exist
  - `unless:` - Skip if command succeeds
  - `onlyif:` - Only run if command succeeds

  Works on all platforms (Unix-based).
  """

  @behaviour Nexus.Resources.Resource

  alias Nexus.Resources.Result
  alias Nexus.Resources.Types.Command
  alias Nexus.SSH.Connection

  @doc """
  Command provider works on all platforms.
  """
  @impl true
  @spec provider_for(map()) :: {:ok, module()}
  def provider_for(_facts), do: {:ok, __MODULE__}

  @impl true
  def check(%Command{} = cmd, conn, _context) do
    initial_state()
    |> check_creates(cmd, conn)
    |> check_removes(cmd, conn)
    |> check_unless(cmd, conn)
    |> check_onlyif(cmd, conn)
    |> then(&{:ok, &1})
  end

  defp initial_state, do: %{should_run: true, skip_reason: nil}

  defp check_creates(state, %Command{creates: nil}, _conn), do: state

  defp check_creates(state, %Command{creates: path}, conn) do
    case exec(conn, "test -e #{escape(path)}") do
      {:ok, _, 0} ->
        %{state | should_run: false, skip_reason: "creates path exists: #{path}"}

      _ ->
        state
    end
  end

  defp check_removes(state, %Command{removes: nil}, _conn), do: state
  defp check_removes(%{should_run: false} = state, _cmd, _conn), do: state

  defp check_removes(state, %Command{removes: path}, conn) do
    case exec(conn, "test -e #{escape(path)}") do
      {:ok, _, 0} ->
        state

      _ ->
        %{state | should_run: false, skip_reason: "removes path absent: #{path}"}
    end
  end

  defp check_unless(state, %Command{unless: nil}, _conn), do: state
  defp check_unless(%{should_run: false} = state, _cmd, _conn), do: state

  defp check_unless(state, %Command{unless: check_cmd}, conn) do
    case exec(conn, check_cmd) do
      {:ok, _, 0} ->
        %{state | should_run: false, skip_reason: "unless command succeeded"}

      _ ->
        state
    end
  end

  defp check_onlyif(state, %Command{onlyif: nil}, _conn), do: state
  defp check_onlyif(%{should_run: false} = state, _cmd, _conn), do: state

  defp check_onlyif(state, %Command{onlyif: check_cmd}, conn) do
    case exec(conn, check_cmd) do
      {:ok, _, 0} ->
        state

      _ ->
        %{state | should_run: false, skip_reason: "onlyif command failed"}
    end
  end

  @impl true
  def diff(%Command{} = _cmd, current) do
    if current.should_run do
      %{
        changed: true,
        before: %{executed: false},
        after: %{executed: true},
        changes: ["execute command"]
      }
    else
      %{
        changed: false,
        before: %{skipped: true, reason: current.skip_reason},
        after: %{skipped: true, reason: current.skip_reason},
        changes: []
      }
    end
  end

  @impl true
  def apply(%Command{} = cmd, conn, context) do
    start_time = System.monotonic_time(:millisecond)

    # Re-check state
    {:ok, state} = check(cmd, conn, context)

    cond do
      not state.should_run ->
        duration = System.monotonic_time(:millisecond) - start_time

        {:ok,
         Result.ok(Command.describe(cmd),
           message: state.skip_reason,
           duration_ms: duration
         )}

      context.check_mode ->
        {:ok, Result.skipped(Command.describe(cmd), "check mode")}

      true ->
        result = execute_command(cmd, conn)
        duration = System.monotonic_time(:millisecond) - start_time

        case result do
          {:ok, output, 0} ->
            diff = %{
              before: %{executed: false},
              after: %{executed: true, output: truncate(output, 500)},
              changes: ["executed command"]
            }

            {:ok,
             Result.changed(Command.describe(cmd), diff,
               notify: cmd.notify,
               duration_ms: duration
             )}

          {:ok, output, code} ->
            {:ok,
             Result.failed(Command.describe(cmd), "exit code #{code}: #{truncate(output, 200)}",
               duration_ms: duration
             )}

          {:error, reason} ->
            {:ok, Result.failed(Command.describe(cmd), inspect(reason), duration_ms: duration)}
        end
    end
  end

  defp execute_command(cmd, conn) do
    full_cmd = build_command(cmd)

    if cmd.sudo do
      exec(conn, full_cmd, sudo: true, user: cmd.user, timeout: cmd.timeout)
    else
      exec(conn, full_cmd, timeout: cmd.timeout)
    end
  end

  defp build_command(%Command{} = cmd) do
    parts = []

    # Environment variables
    parts =
      if cmd.env != %{} do
        env_str =
          Enum.map_join(cmd.env, " ", fn {k, v} ->
            "#{k}=#{escape(v)}"
          end)

        [env_str | parts]
      else
        parts
      end

    # Change directory
    parts =
      if cmd.cwd do
        ["cd #{escape(cmd.cwd)} &&" | parts]
      else
        parts
      end

    # The actual command
    parts = parts ++ [cmd.cmd]

    Enum.join(parts, " ")
  end

  @impl true
  def describe(cmd), do: Command.describe(cmd)

  defp truncate(str, max) do
    if String.length(str) > max do
      String.slice(str, 0, max - 3) <> "..."
    else
      str
    end
  end

  defp escape(str), do: "'" <> String.replace(to_string(str), "'", "'\\''") <> "'"

  defp exec(conn, cmd, opts \\ [])

  defp exec(nil, cmd, opts) do
    full_cmd =
      cond do
        Keyword.get(opts, :sudo, false) && Keyword.get(opts, :user) ->
          "sudo -u #{Keyword.get(opts, :user)} sh -c #{escape(cmd)}"

        Keyword.get(opts, :sudo, false) ->
          "sudo sh -c #{escape(cmd)}"

        true ->
          cmd
      end

    timeout = Keyword.get(opts, :timeout, 60_000)

    task =
      Task.async(fn ->
        System.cmd("sh", ["-c", full_cmd], stderr_to_stdout: true)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, code}} -> {:ok, output, code}
      nil -> {:error, :timeout}
    end
  end

  defp exec(conn, cmd, opts) do
    if Keyword.get(opts, :sudo, false) do
      user = Keyword.get(opts, :user)

      if user do
        Connection.exec_sudo(conn, "su - #{user} -c #{escape(cmd)}")
      else
        Connection.exec_sudo(conn, cmd)
      end
    else
      Connection.exec(conn, cmd)
    end
  end
end
