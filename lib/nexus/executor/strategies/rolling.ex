defmodule Nexus.Executor.Strategies.Rolling do
  @moduledoc """
  Rolling deployment strategy for gradual host updates.

  Deploys to hosts in batches, waiting for health checks to pass
  before proceeding to the next batch. This minimizes downtime
  and allows for early failure detection.

  ## Options

    * `:batch_size` - Number of hosts per batch (default: 1)
    * `:continue_on_error` - Continue to next batch on failure (default: false)

  ## Example

      task :deploy, on: :web, strategy: :rolling, batch_size: 2 do
        run "systemctl restart app", sudo: true
        wait_for :http, "http://localhost:4000/health"
      end

  """

  alias Nexus.Executor.HealthCheck
  alias Nexus.SSH.{Connection, Pool}
  alias Nexus.Types.{Command, Host, WaitFor}
  alias Nexus.Types.Task, as: NexusTask

  @type rolling_opts :: [
          batch_size: pos_integer(),
          continue_on_error: boolean(),
          ssh_opts: keyword()
        ]

  @doc """
  Executes a rolling deployment across hosts.

  Divides hosts into batches and deploys to each batch sequentially.
  Health checks (WaitFor commands) are executed after each batch
  before proceeding to the next.

  ## Returns

    * `{:ok, [host_result]}` - Deployment completed (check individual results)
    * `{:error, reason}` - Deployment aborted

  """
  @type host_result :: %{
          host: atom() | :local,
          status: :ok | :error,
          commands: [map()]
        }

  @spec run(NexusTask.t(), [Host.t()], rolling_opts()) :: {:ok, [host_result()]}
  def run(%NexusTask{} = task, hosts, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 1)
    continue_on_error = Keyword.get(opts, :continue_on_error, false)

    # Split commands into regular commands and health checks
    {commands, health_checks} = partition_commands(task.commands)

    # Create a modified task with just the regular commands
    deploy_task = %{task | commands: commands, strategy: :parallel}

    # Batch the hosts
    batches = Enum.chunk_every(hosts, batch_size)

    state = %{
      task: deploy_task,
      health_checks: health_checks,
      continue_on_error: continue_on_error,
      opts: opts
    }

    execute_batches(batches, state, [])
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp partition_commands(commands) do
    Enum.split_with(commands, fn cmd ->
      not match?(%WaitFor{}, cmd)
    end)
  end

  defp execute_batches([], _state, acc) do
    {:ok, Enum.reverse(acc)}
  end

  defp execute_batches([batch | rest], state, acc) do
    batch_results = execute_batch(batch, state.task, state.opts)

    case run_health_checks(batch, state.health_checks, state.opts) do
      :ok ->
        execute_batches(rest, state, batch_results ++ acc)

      {:error, failed_host} ->
        handle_health_check_failure(rest, state, acc, batch_results, failed_host)
    end
  end

  defp handle_health_check_failure(rest, state, acc, batch_results, failed_host) do
    if state.continue_on_error do
      failed_results = mark_health_check_failed(batch_results, failed_host)
      execute_batches(rest, state, failed_results ++ acc)
    else
      {:ok, Enum.reverse(batch_results ++ acc)}
    end
  end

  defp execute_batch(hosts, task, opts) do
    ssh_opts = Keyword.get(opts, :ssh_opts, [])
    continue_on_error = Keyword.get(opts, :continue_on_error, false)

    hosts
    |> Task.async_stream(
      fn host -> run_on_host(task, host, ssh_opts, continue_on_error) end,
      timeout: task.timeout,
      on_timeout: :kill_task
    )
    |> Enum.zip(hosts)
    |> Enum.map(&format_host_result/1)
  end

  defp format_host_result({{:ok, {:ok, host_result}}, _host}), do: host_result

  defp format_host_result({{:ok, {:error, reason}}, host}) do
    make_error_result(host.name, reason)
  end

  defp format_host_result({{:exit, :timeout}, host}) do
    make_error_result(host.name, :timeout)
  end

  defp make_error_result(host_name, reason) do
    %{
      host: host_name,
      status: :error,
      commands: [
        %{
          cmd: "connect",
          status: :error,
          output: inspect(reason),
          exit_code: -1,
          attempts: 1,
          duration_ms: 0
        }
      ]
    }
  end

  defp run_on_host(task, host, ssh_opts, continue_on_error) do
    pool_opts = [connect_opts: ssh_opts]

    case Pool.checkout(host, &run_commands(&1, task.commands, continue_on_error), pool_opts) do
      {:ok, command_results} ->
        status = if Enum.all?(command_results, &(&1.status == :ok)), do: :ok, else: :error
        {:ok, %{host: host.name, status: status, commands: command_results}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_commands(conn, commands, continue_on_error) do
    {results, _} =
      Enum.reduce_while(commands, {[], :continue}, fn cmd, {acc, _} ->
        result = execute_command(cmd, conn)

        if result.status == :error and not continue_on_error do
          {:halt, {[result | acc], :stopped}}
        else
          {:cont, {[result | acc], :continue}}
        end
      end)

    {:ok, Enum.reverse(results)}
  end

  defp execute_command(%Command{} = cmd, conn) do
    start_time = System.monotonic_time(:millisecond)

    result =
      if cmd.sudo do
        Connection.exec_sudo(conn, cmd.cmd, timeout: cmd.timeout, sudo_user: cmd.user)
      else
        Connection.exec(conn, cmd.cmd, timeout: cmd.timeout)
      end

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, output, 0} ->
        %{
          cmd: cmd.cmd,
          status: :ok,
          output: output,
          exit_code: 0,
          attempts: 1,
          duration_ms: duration
        }

      {:ok, output, exit_code} ->
        %{
          cmd: cmd.cmd,
          status: :error,
          output: output,
          exit_code: exit_code,
          attempts: 1,
          duration_ms: duration
        }

      {:error, reason} ->
        %{
          cmd: cmd.cmd,
          status: :error,
          output: inspect(reason),
          exit_code: -1,
          attempts: 1,
          duration_ms: duration
        }
    end
  end

  defp run_health_checks(_hosts, [], _opts), do: :ok

  defp run_health_checks(hosts, health_checks, opts) do
    ssh_opts = Keyword.get(opts, :ssh_opts, [])

    results = Enum.map(hosts, &run_host_health_checks(&1, health_checks, ssh_opts))

    case Enum.find(results, fn {_host, result} -> result != :ok end) do
      nil -> :ok
      {host, _} -> {:error, host}
    end
  end

  defp run_host_health_checks(host, health_checks, ssh_opts) do
    pool_opts = [connect_opts: ssh_opts]
    result = Pool.checkout(host, &execute_health_checks(&1, health_checks), pool_opts)
    normalize_health_result(host, result)
  end

  defp execute_health_checks(conn, health_checks) do
    Enum.reduce_while(health_checks, :ok, fn check, _acc ->
      case HealthCheck.wait(check, conn: conn) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_health_result(host, {:ok, :ok}), do: {host, :ok}
  defp normalize_health_result(host, {:ok, {:error, reason}}), do: {host, {:error, reason}}
  defp normalize_health_result(host, {:error, reason}), do: {host, {:error, reason}}

  defp mark_health_check_failed(results, failed_host) do
    Enum.map(results, fn result ->
      if result.host == failed_host.name do
        %{result | status: :error}
      else
        result
      end
    end)
  end
end
