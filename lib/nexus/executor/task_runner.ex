defmodule Nexus.Executor.TaskRunner do
  @moduledoc """
  Executes a single task across one or more hosts.

  Handles command execution with retry logic, timeout enforcement,
  and result aggregation. Supports both local and remote execution.

  ## Execution Strategies

  - `:parallel` - Run on all hosts concurrently (default)
  - `:serial` - Run on hosts one at a time

  ## Examples

      # Run a local task
      task = %Task{name: :build, on: :local, commands: [%Command{cmd: "make build"}]}
      {:ok, result} = TaskRunner.run(task, [], [])

      # Run on multiple hosts in parallel
      task = %Task{name: :deploy, on: :web, commands: [%Command{cmd: "restart app"}]}
      hosts = [%Host{name: :web1, hostname: "web1.example.com"}, ...]
      {:ok, result} = TaskRunner.run(task, hosts, [])

  """

  alias Nexus.Executor.Local
  alias Nexus.Resources.Types.Command, as: ResourceCommand
  alias Nexus.SSH.{Connection, Pool}
  alias Nexus.Telemetry
  alias Nexus.Types.{Command, Host}
  alias Nexus.Types.Task, as: NexusTask

  @type task_result :: %{
          task: atom(),
          status: :ok | :error,
          duration_ms: non_neg_integer(),
          host_results: [host_result()]
        }

  @type host_result :: %{
          host: atom() | :local,
          status: :ok | :error,
          commands: [command_result()]
        }

  @type command_result :: %{
          cmd: String.t(),
          status: :ok | :error,
          output: String.t(),
          exit_code: integer(),
          attempts: pos_integer(),
          duration_ms: non_neg_integer()
        }

  @type run_opts :: [
          timeout: pos_integer(),
          continue_on_error: boolean(),
          ssh_opts: keyword()
        ]

  @doc """
  Runs a task across the specified hosts.

  For local tasks (where `task.on == :local`), the hosts list is ignored.
  For remote tasks, commands are executed on each host according to the
  task's strategy (`:parallel` or `:serial`).

  ## Options

    * `:timeout` - Overall task timeout in milliseconds
    * `:continue_on_error` - Continue executing on other hosts if one fails
    * `:ssh_opts` - Options to pass to SSH connections

  ## Returns

    * `{:ok, task_result}` - Task completed (check individual host results for status)
    * `{:error, reason}` - Task failed to start or was aborted

  """
  @spec run(NexusTask.t(), [Host.t()], run_opts()) :: {:ok, task_result()} | {:error, term()}
  def run(%NexusTask{} = task, hosts, opts \\ []) do
    Telemetry.emit_task_start(task.name, task.on)
    start_time = System.monotonic_time(:millisecond)

    result =
      if task.on == :local do
        run_local_task(task, opts)
      else
        run_remote_task(task, hosts, opts)
      end

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, host_results} ->
        overall_status = if Enum.all?(host_results, &(&1.status == :ok)), do: :ok, else: :error
        Telemetry.emit_task_stop(task.name, duration, overall_status)

        {:ok,
         %{
           task: task.name,
           status: overall_status,
           duration_ms: duration,
           host_results: host_results
         }}

      {:error, reason} ->
        Telemetry.emit_task_exception(task.name, duration, :error, reason)
        {:error, reason}
    end
  end

  # Local task execution
  defp run_local_task(%NexusTask{} = task, opts) do
    continue_on_error = Keyword.get(opts, :continue_on_error, false)

    {:ok, command_results} = run_commands_locally(task.commands, continue_on_error)
    status = if Enum.all?(command_results, &(&1.status == :ok)), do: :ok, else: :error
    {:ok, [%{host: :local, status: status, commands: command_results}]}
  end

  # Remote task execution
  defp run_remote_task(%NexusTask{} = task, hosts, opts) do
    if Enum.empty?(hosts) do
      {:error, {:no_hosts, task.on}}
    else
      case task.strategy do
        :parallel -> run_parallel(task, hosts, opts)
        :serial -> run_serial(task, hosts, opts)
      end
    end
  end

  defp run_parallel(%NexusTask{} = task, hosts, opts) do
    continue_on_error = Keyword.get(opts, :continue_on_error, false)

    results =
      hosts
      |> Task.async_stream(
        fn host -> run_on_host(task, host, opts) end,
        timeout: task.timeout,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {:error, :timeout}
      end)

    # Check if any host failed
    has_error = Enum.any?(results, fn r -> match?({:error, _}, r) end)

    if has_error and not continue_on_error do
      # Return partial results with error
      host_results = format_parallel_results(results, hosts)
      {:ok, host_results}
    else
      host_results = format_parallel_results(results, hosts)
      {:ok, host_results}
    end
  end

  defp run_serial(%NexusTask{} = task, hosts, opts) do
    continue_on_error = Keyword.get(opts, :continue_on_error, false)

    {results, _} =
      Enum.reduce_while(hosts, {[], :continue}, fn host, {acc, _} ->
        host_result = execute_on_host_with_fallback(task, host, opts)
        handle_serial_result(host_result, acc, continue_on_error)
      end)

    {:ok, Enum.reverse(results)}
  end

  defp execute_on_host_with_fallback(task, host, opts) do
    case run_on_host(task, host, opts) do
      {:ok, result} -> result
      {:error, reason} -> make_connection_error_result(host.name, reason)
    end
  end

  defp make_connection_error_result(host_name, reason) do
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

  defp handle_serial_result(host_result, acc, continue_on_error) do
    should_continue = host_result.status == :ok or continue_on_error

    if should_continue do
      {:cont, {[host_result | acc], :continue}}
    else
      {:halt, {[host_result | acc], :stopped}}
    end
  end

  defp run_on_host(%NexusTask{} = task, %Host{} = host, opts) do
    ssh_opts = Keyword.get(opts, :ssh_opts, [])
    continue_on_error = Keyword.get(opts, :continue_on_error, false)

    # Pool.checkout expects connect_opts key for SSH authentication
    pool_opts = [connect_opts: ssh_opts]

    case Pool.checkout(
           host,
           &run_commands_remotely(&1, task.commands, continue_on_error),
           pool_opts
         ) do
      {:ok, command_results} ->
        status = if Enum.all?(command_results, &(&1.status == :ok)), do: :ok, else: :error
        {:ok, %{host: host.name, status: status, commands: command_results}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_commands_locally(commands, continue_on_error) do
    run_commands(commands, continue_on_error, &execute_local_command/1)
  end

  defp run_commands_remotely(conn, commands, continue_on_error) do
    run_commands(commands, continue_on_error, &execute_remote_command(&1, conn))
  end

  defp run_commands(commands, continue_on_error, executor) do
    {results, _} =
      Enum.reduce_while(commands, {[], :continue}, fn cmd, {acc, _} ->
        result = execute_with_retry(cmd, executor)

        if result.status == :error and not continue_on_error do
          {:halt, {[result | acc], :stopped}}
        else
          {:cont, {[result | acc], :continue}}
        end
      end)

    {:ok, Enum.reverse(results)}
  end

  defp execute_with_retry(%Command{} = cmd, executor) do
    execute_with_retry(cmd, executor, 1, :local)
  end

  # Handle Resources.Types.Command by converting to standard Command format
  defp execute_with_retry(%ResourceCommand{} = cmd, executor) do
    # ResourceCommand doesn't have retries/retry_delay, so use defaults
    standard_cmd = %Command{
      cmd: cmd.cmd,
      sudo: cmd.sudo,
      user: cmd.user,
      timeout: cmd.timeout,
      retries: 0,
      retry_delay: 1_000,
      when: cmd.when
    }

    execute_with_retry(standard_cmd, executor, 1, :local)
  end

  defp execute_with_retry(%Command{} = cmd, executor, attempt, host) do
    # Only emit start event on first attempt
    if attempt == 1, do: Telemetry.emit_command_start(cmd.cmd, host)

    start_time = System.monotonic_time(:millisecond)
    result = executor.(cmd)
    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, output, 0} ->
        Telemetry.emit_command_stop(cmd.cmd, duration, 0)

        %{
          cmd: cmd.cmd,
          status: :ok,
          output: output,
          exit_code: 0,
          attempts: attempt,
          duration_ms: duration
        }

      {:ok, output, exit_code} ->
        if attempt <= cmd.retries do
          Process.sleep(calculate_retry_delay(cmd.retry_delay, attempt))
          execute_with_retry(cmd, executor, attempt + 1, host)
        else
          Telemetry.emit_command_stop(cmd.cmd, duration, exit_code)

          %{
            cmd: cmd.cmd,
            status: :error,
            output: output,
            exit_code: exit_code,
            attempts: attempt,
            duration_ms: duration
          }
        end

      {:error, reason} ->
        if attempt <= cmd.retries do
          Process.sleep(calculate_retry_delay(cmd.retry_delay, attempt))
          execute_with_retry(cmd, executor, attempt + 1, host)
        else
          Telemetry.emit_command_stop(cmd.cmd, duration, -1)

          %{
            cmd: cmd.cmd,
            status: :error,
            output: inspect(reason),
            exit_code: -1,
            attempts: attempt,
            duration_ms: duration
          }
        end
    end
  end

  defp execute_local_command(%Command{} = cmd) do
    if cmd.sudo do
      Local.run_sudo(cmd)
    else
      Local.run(cmd)
    end
  end

  defp execute_remote_command(%Command{} = cmd, conn) do
    if cmd.sudo do
      Connection.exec_sudo(conn, cmd.cmd, timeout: cmd.timeout, sudo_user: cmd.user)
    else
      Connection.exec(conn, cmd.cmd, timeout: cmd.timeout)
    end
  end

  # Exponential backoff with jitter
  defp calculate_retry_delay(base_delay, attempt) do
    # 2^(attempt-1) * base_delay with 20% jitter
    multiplier = :math.pow(2, attempt - 1)
    delay = round(multiplier * base_delay)
    jitter = :rand.uniform(round(delay * 0.2))
    delay + jitter
  end

  defp format_parallel_results(results, hosts) do
    Enum.zip(hosts, results)
    |> Enum.map(fn
      {_host, {:ok, host_result}} ->
        host_result

      {host, {:error, reason}} ->
        %{
          host: host.name,
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
    end)
  end
end
