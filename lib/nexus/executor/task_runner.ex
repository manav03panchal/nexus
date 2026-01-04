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
  alias Nexus.Resources.Executor, as: ResourceExecutor
  alias Nexus.Resources.Types.Command, as: ResourceCommand
  alias Nexus.Resources.Types.{Directory, Group, Package, Service, User}
  alias Nexus.Resources.Types.File, as: FileResource
  alias Nexus.SSH.{Connection, Pool, SFTP}
  alias Nexus.Telemetry
  alias Nexus.Types.{Command, Download, Host, Template, Upload, WaitFor}
  alias Nexus.Types.Task, as: NexusTask

  @type task_result :: %{
          task: atom(),
          status: :ok | :error,
          duration_ms: non_neg_integer(),
          host_results: [host_result()],
          triggered_handlers: [atom()]
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

        # Collect triggered handlers from successful commands
        triggered_handlers = collect_triggered_handlers(host_results)

        {:ok,
         %{
           task: task.name,
           status: overall_status,
           duration_ms: duration,
           host_results: host_results,
           triggered_handlers: triggered_handlers
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
           &run_commands_remotely(&1, task.commands, continue_on_error, host.name),
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
    run_commands(commands, continue_on_error, :local, nil, :local)
  end

  defp run_commands_remotely(conn, commands, continue_on_error, host_name) do
    run_commands(commands, continue_on_error, :remote, conn, host_name)
  end

  defp run_commands(commands, continue_on_error, mode, conn, host_name) do
    {results, _} =
      Enum.reduce_while(commands, {[], :continue}, fn cmd, {acc, _} ->
        result = execute_command(cmd, mode, conn, host_name)

        if result.status == :error and not continue_on_error do
          {:halt, {[result | acc], :stopped}}
        else
          {:cont, {[result | acc], :continue}}
        end
      end)

    {:ok, Enum.reverse(results)}
  end

  # Dispatch to appropriate executor based on command type
  defp execute_command(%Command{} = cmd, mode, conn, host_name) do
    executor =
      if mode == :local, do: &execute_local_command/1, else: &execute_remote_command(&1, conn)

    execute_with_retry(cmd, executor, 1, host_name)
  end

  defp execute_command(%ResourceCommand{} = cmd, mode, conn, host_name) do
    executor =
      if mode == :local, do: &execute_local_command/1, else: &execute_remote_command(&1, conn)

    execute_with_retry(cmd, executor, host_name)
  end

  defp execute_command(%Upload{} = upload, mode, conn, host_name) do
    execute_upload(upload, mode, conn, host_name)
  end

  defp execute_command(%Download{} = download, mode, conn, host_name) do
    execute_download(download, mode, conn, host_name)
  end

  defp execute_command(%Template{} = template, mode, conn, host_name) do
    execute_template(template, mode, conn, host_name)
  end

  defp execute_command(%WaitFor{} = wait_for, mode, conn, host_name) do
    execute_wait_for(wait_for, mode, conn, host_name)
  end

  # Resource types - delegate to Resources.Executor
  defp execute_command(%Package{} = resource, mode, conn, host_name) do
    execute_resource(resource, mode, conn, host_name)
  end

  defp execute_command(%Service{} = resource, mode, conn, host_name) do
    execute_resource(resource, mode, conn, host_name)
  end

  defp execute_command(%FileResource{} = resource, mode, conn, host_name) do
    execute_resource(resource, mode, conn, host_name)
  end

  defp execute_command(%Directory{} = resource, mode, conn, host_name) do
    execute_resource(resource, mode, conn, host_name)
  end

  defp execute_command(%User{} = resource, mode, conn, host_name) do
    execute_resource(resource, mode, conn, host_name)
  end

  defp execute_command(%Group{} = resource, mode, conn, host_name) do
    execute_resource(resource, mode, conn, host_name)
  end

  # Handle Resources.Types.Command with idempotency guards
  defp execute_with_retry(%ResourceCommand{} = cmd, executor, host_name) do
    start_time = System.monotonic_time(:millisecond)
    Telemetry.emit_command_start(cmd.cmd, host_name)

    # Check idempotency guards first
    case check_idempotency_guards(cmd, executor) do
      {:skip, reason} ->
        duration = System.monotonic_time(:millisecond) - start_time
        skip_output = "(skipped: #{reason})"
        Telemetry.emit_command_stop(cmd.cmd, duration, 0, skip_output, host_name)

        %{
          cmd: cmd.cmd,
          status: :ok,
          output: skip_output,
          exit_code: 0,
          attempts: 0,
          duration_ms: duration,
          skipped: true
        }

      :run ->
        execute_resource_command(cmd, executor, start_time, host_name)
    end
  end

  defp execute_resource_command(cmd, executor, start_time, host_name) do
    # Build the full command with env and cwd
    full_cmd = build_resource_command(cmd)

    # Create a temporary Command struct for execution
    exec_cmd = %Command{
      cmd: full_cmd,
      sudo: cmd.sudo,
      user: cmd.user,
      timeout: cmd.timeout,
      retries: 0,
      retry_delay: 1_000,
      when: cmd.when
    }

    result = executor.(exec_cmd)
    duration = System.monotonic_time(:millisecond) - start_time

    handle_resource_command_result(result, cmd, duration, host_name)
  end

  defp handle_resource_command_result({:ok, output, 0}, cmd, duration, host_name) do
    Telemetry.emit_command_stop(cmd.cmd, duration, 0, output, host_name)

    base_result = %{
      cmd: cmd.cmd,
      status: :ok,
      output: output,
      exit_code: 0,
      attempts: 1,
      duration_ms: duration
    }

    # Add notify handler if specified and command succeeded
    if cmd.notify, do: Map.put(base_result, :notify, cmd.notify), else: base_result
  end

  defp handle_resource_command_result({:ok, output, exit_code}, cmd, duration, host_name) do
    Telemetry.emit_command_stop(cmd.cmd, duration, exit_code, output, host_name)

    %{
      cmd: cmd.cmd,
      status: :error,
      output: output,
      exit_code: exit_code,
      attempts: 1,
      duration_ms: duration
    }
  end

  defp handle_resource_command_result({:error, reason}, cmd, duration, host_name) do
    error_output = inspect(reason)
    Telemetry.emit_command_stop(cmd.cmd, duration, -1, error_output, host_name)

    %{
      cmd: cmd.cmd,
      status: :error,
      output: error_output,
      exit_code: -1,
      attempts: 1,
      duration_ms: duration
    }
  end

  # Check idempotency guards for ResourceCommand
  defp check_idempotency_guards(%ResourceCommand{} = cmd, executor) do
    check_creates(cmd, executor)
    |> check_removes(cmd, executor)
    |> check_unless(cmd, executor)
    |> check_onlyif(cmd, executor)
  end

  defp check_creates(%ResourceCommand{creates: nil}, _executor), do: :run

  defp check_creates(%ResourceCommand{creates: path}, executor) do
    if path_exists?(path, executor), do: {:skip, "creates path exists: #{path}"}, else: :run
  end

  defp check_removes({:skip, _} = skip, _cmd, _executor), do: skip
  defp check_removes(:run, %ResourceCommand{removes: nil}, _executor), do: :run

  defp check_removes(:run, %ResourceCommand{removes: path}, executor) do
    if path_exists?(path, executor), do: :run, else: {:skip, "removes path absent: #{path}"}
  end

  defp check_unless({:skip, _} = skip, _cmd, _executor), do: skip
  defp check_unless(:run, %ResourceCommand{unless: nil}, _executor), do: :run

  defp check_unless(:run, %ResourceCommand{unless: check}, executor) do
    if command_succeeds?(check, executor), do: {:skip, "unless command succeeded"}, else: :run
  end

  defp check_onlyif({:skip, _} = skip, _cmd, _executor), do: skip
  defp check_onlyif(:run, %ResourceCommand{onlyif: nil}, _executor), do: :run

  defp check_onlyif(:run, %ResourceCommand{onlyif: check}, executor) do
    if command_succeeds?(check, executor), do: :run, else: {:skip, "onlyif command failed"}
  end

  defp path_exists?(path, executor) do
    check_cmd = %Command{
      cmd: "test -e #{shell_escape(path)}",
      sudo: false,
      user: nil,
      timeout: 10_000,
      retries: 0,
      retry_delay: 1_000,
      when: true
    }

    case executor.(check_cmd) do
      {:ok, _, 0} -> true
      _ -> false
    end
  end

  defp command_succeeds?(check_cmd_str, executor) do
    check_cmd = %Command{
      cmd: check_cmd_str,
      sudo: false,
      user: nil,
      timeout: 30_000,
      retries: 0,
      retry_delay: 1_000,
      when: true
    }

    case executor.(check_cmd) do
      {:ok, _, 0} -> true
      _ -> false
    end
  end

  defp build_resource_command(%ResourceCommand{} = cmd) do
    # Build command - env vars require sh -c wrapper to work
    base_cmd = cmd.cmd

    # Add cd prefix if cwd specified
    cmd_with_cwd =
      if cmd.cwd do
        "cd #{shell_escape(cmd.cwd)} && #{base_cmd}"
      else
        base_cmd
      end

    # Add environment variables - requires sh -c wrapper
    if cmd.env != %{} do
      env_str =
        Enum.map_join(cmd.env, " ", fn {k, v} ->
          "#{k}=#{shell_escape(v)}"
        end)

      # Wrap in sh -c so env vars are available to the command
      "#{env_str} sh -c #{shell_escape(cmd_with_cwd)}"
    else
      cmd_with_cwd
    end
  end

  defp shell_escape(str), do: "'" <> String.replace(to_string(str), "'", "'\\''") <> "'"

  defp execute_with_retry(%Command{} = cmd, executor, attempt, host) do
    # Only emit start event on first attempt
    if attempt == 1, do: Telemetry.emit_command_start(cmd.cmd, host)

    start_time = System.monotonic_time(:millisecond)
    result = executor.(cmd)
    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, output, 0} ->
        Telemetry.emit_command_stop(cmd.cmd, duration, 0, output)

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
          Telemetry.emit_command_stop(cmd.cmd, duration, exit_code, output)

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
          error_output = inspect(reason)
          Telemetry.emit_command_stop(cmd.cmd, duration, -1, error_output)

          %{
            cmd: cmd.cmd,
            status: :error,
            output: error_output,
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

  # Collect triggered handler names from successful commands
  defp collect_triggered_handlers(host_results) do
    host_results
    |> Enum.flat_map(& &1.commands)
    |> Enum.filter(&(&1.status == :ok and Map.has_key?(&1, :notify)))
    |> Enum.map(& &1.notify)
    |> Enum.uniq()
  end

  # ============================================================================
  # Upload execution
  # ============================================================================

  defp execute_upload(%Upload{} = upload, :local, _conn, _host_name) do
    # Local upload is just a file copy
    start_time = System.monotonic_time(:millisecond)
    cmd_desc = "upload #{upload.local_path} -> #{upload.remote_path}"
    Telemetry.emit_command_start(cmd_desc, :local)

    result =
      case File.cp(upload.local_path, upload.remote_path) do
        :ok ->
          if upload.mode do
            File.chmod(upload.remote_path, upload.mode)
          end

          {:ok, "uploaded"}

        {:error, reason} ->
          {:error, reason}
      end

    duration = System.monotonic_time(:millisecond) - start_time
    build_file_op_result(cmd_desc, result, duration, upload.notify)
  end

  defp execute_upload(%Upload{} = upload, :remote, conn, host_name) do
    start_time = System.monotonic_time(:millisecond)
    cmd_desc = "upload #{upload.local_path} -> #{upload.remote_path}"
    Telemetry.emit_command_start(cmd_desc, host_name)

    result =
      SFTP.upload(conn, upload.local_path, upload.remote_path,
        sudo: upload.sudo,
        mode: upload.mode
      )

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      :ok ->
        Telemetry.emit_command_stop(cmd_desc, duration, 0, "uploaded")
        build_file_op_result(cmd_desc, {:ok, "uploaded"}, duration, upload.notify)

      {:error, reason} ->
        Telemetry.emit_command_stop(cmd_desc, duration, 1, inspect(reason))
        build_file_op_result(cmd_desc, {:error, reason}, duration, nil)
    end
  end

  # ============================================================================
  # Download execution
  # ============================================================================

  defp execute_download(%Download{} = download, :local, _conn, _host_name) do
    # Local download is just a file copy (reverse direction)
    start_time = System.monotonic_time(:millisecond)
    cmd_desc = "download #{download.remote_path} -> #{download.local_path}"
    Telemetry.emit_command_start(cmd_desc, :local)

    result =
      case File.cp(download.remote_path, download.local_path) do
        :ok -> {:ok, "downloaded"}
        {:error, reason} -> {:error, reason}
      end

    duration = System.monotonic_time(:millisecond) - start_time
    build_file_op_result(cmd_desc, result, duration, nil)
  end

  defp execute_download(%Download{} = download, :remote, conn, host_name) do
    start_time = System.monotonic_time(:millisecond)
    cmd_desc = "download #{download.remote_path} -> #{download.local_path}"
    Telemetry.emit_command_start(cmd_desc, host_name)

    result = SFTP.download(conn, download.remote_path, download.local_path, sudo: download.sudo)

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      :ok ->
        Telemetry.emit_command_stop(cmd_desc, duration, 0, "downloaded")
        build_file_op_result(cmd_desc, {:ok, "downloaded"}, duration, nil)

      {:error, reason} ->
        Telemetry.emit_command_stop(cmd_desc, duration, 1, inspect(reason))
        build_file_op_result(cmd_desc, {:error, reason}, duration, nil)
    end
  end

  # ============================================================================
  # Template execution
  # ============================================================================

  defp execute_template(%Template{} = template, mode, conn, host_name) do
    start_time = System.monotonic_time(:millisecond)
    cmd_desc = "template #{template.source} -> #{template.destination}"
    Telemetry.emit_command_start(cmd_desc, host_name)

    # Read and render template
    result =
      with {:ok, content} <- File.read(template.source),
           {:ok, rendered} <- render_template(content, template.vars) do
        # Write to temp file, then upload
        # Use cryptographic random for temp filename to prevent prediction attacks
        random_suffix = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
        temp_path = System.tmp_dir!() |> Path.join("nexus_template_#{random_suffix}")

        File.write!(temp_path, rendered)

        upload_result =
          if mode == :local do
            case File.cp(temp_path, template.destination) do
              :ok ->
                if template.mode, do: File.chmod(template.destination, template.mode)
                :ok

              error ->
                error
            end
          else
            SFTP.upload(conn, temp_path, template.destination,
              sudo: template.sudo,
              mode: template.mode
            )
          end

        File.rm(temp_path)
        upload_result
      end

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      :ok ->
        Telemetry.emit_command_stop(cmd_desc, duration, 0, "rendered and uploaded")
        build_file_op_result(cmd_desc, {:ok, "rendered and uploaded"}, duration, template.notify)

      {:error, reason} ->
        Telemetry.emit_command_stop(cmd_desc, duration, 1, inspect(reason))
        build_file_op_result(cmd_desc, {:error, reason}, duration, nil)
    end
  end

  # sobelow_skip ["RCE.EEx"]
  defp render_template(content, vars) do
    # Convert map to keyword list for EEx bindings
    bindings = Enum.map(vars, fn {k, v} -> {k, v} end)
    rendered = EEx.eval_string(content, assigns: bindings)
    {:ok, rendered}
  rescue
    e -> {:error, {:template_error, Exception.message(e)}}
  end

  # ============================================================================
  # WaitFor execution
  # ============================================================================

  defp execute_wait_for(%WaitFor{} = wait_for, mode, conn, host_name) do
    start_time = System.monotonic_time(:millisecond)
    cmd_desc = "wait_for #{wait_for.type} #{wait_for.target}"
    Telemetry.emit_command_start(cmd_desc, host_name)

    result = do_wait_for(wait_for, mode, conn, start_time)

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      :ok ->
        Telemetry.emit_command_stop(cmd_desc, duration, 0, "condition met")

        %{
          cmd: cmd_desc,
          status: :ok,
          output: "condition met",
          exit_code: 0,
          attempts: 1,
          duration_ms: duration
        }

      {:error, :timeout} ->
        Telemetry.emit_command_stop(cmd_desc, duration, 1, "timeout waiting for condition")

        %{
          cmd: cmd_desc,
          status: :error,
          output: "timeout waiting for condition",
          exit_code: 1,
          attempts: 1,
          duration_ms: duration
        }
    end
  end

  defp do_wait_for(%WaitFor{} = wait_for, mode, conn, start_time) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed > wait_for.timeout do
      {:error, :timeout}
    else
      case check_wait_condition(wait_for, mode, conn) do
        true ->
          :ok

        false ->
          Process.sleep(wait_for.interval)
          do_wait_for(wait_for, mode, conn, start_time)
      end
    end
  end

  defp check_wait_condition(%WaitFor{type: :tcp, target: target}, :local, _conn) do
    # Parse host:port and check locally
    case String.split(target, ":") do
      [host, port_str] ->
        port = String.to_integer(port_str)
        check_tcp_connection(host, port)

      _ ->
        false
    end
  end

  defp check_wait_condition(%WaitFor{type: :tcp, target: target}, :remote, conn) do
    # Use nc or bash to check port on remote host
    case String.split(target, ":") do
      [host, port_str] ->
        # Use bash's /dev/tcp for portability
        check_cmd =
          "timeout 1 bash -c 'cat < /dev/null > /dev/tcp/#{host}/#{port_str}' 2>/dev/null"

        case Connection.exec(conn, check_cmd, timeout: 5_000) do
          {:ok, _, 0} -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp check_wait_condition(%WaitFor{type: :http, target: url}, :local, _conn) do
    check_http_endpoint(url)
  end

  defp check_wait_condition(%WaitFor{type: :http, target: url}, :remote, conn) do
    # Use curl on remote host
    check_cmd = "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 '#{url}'"

    case Connection.exec(conn, check_cmd, timeout: 5_000) do
      {:ok, status_str, 0} ->
        status = String.trim(status_str) |> String.to_integer()
        status >= 200 and status < 300

      _ ->
        false
    end
  end

  defp check_wait_condition(%WaitFor{type: :command, target: cmd}, mode, conn) do
    check_cmd = %Command{
      cmd: cmd,
      sudo: false,
      user: nil,
      timeout: 10_000,
      retries: 0,
      retry_delay: 1_000,
      when: true
    }

    executor =
      if mode == :local do
        &execute_local_command/1
      else
        &execute_remote_command(&1, conn)
      end

    case executor.(check_cmd) do
      {:ok, _, 0} -> true
      _ -> false
    end
  end

  defp check_tcp_connection(host, port) do
    case :gen_tcp.connect(String.to_charlist(host), port, [], 1_000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  defp check_http_endpoint(url) do
    # Simple HTTP check using httpc
    :inets.start()
    :ssl.start()

    case :httpc.request(:get, {String.to_charlist(url), []}, [timeout: 5_000], []) do
      {:ok, {{_, status, _}, _, _}} when status >= 200 and status < 300 ->
        true

      _ ->
        false
    end
  end

  # ============================================================================
  # Resource execution (Package, Service, File, Directory, User, Group)
  # ============================================================================

  defp execute_resource(resource, mode, conn, host_name) do
    start_time = System.monotonic_time(:millisecond)
    resource_desc = describe_resource(resource)
    Telemetry.emit_command_start(resource_desc, host_name)

    # Build context with facts - need to detect OS
    context = build_resource_context(mode, conn)

    # Execute via Resources.Executor
    {:ok, result} = ResourceExecutor.execute(resource, conn, context)

    duration = System.monotonic_time(:millisecond) - start_time
    output = result.message || status_to_message(result.status)

    Telemetry.emit_command_stop(
      resource_desc,
      duration,
      if(result.status in [:ok, :changed], do: 0, else: 1),
      output
    )

    # Convert Resources.Result to command_result format
    convert_resource_result(result, resource_desc, duration)
  end

  defp build_resource_context(:local, _conn) do
    %{
      facts: detect_local_facts(),
      host_id: :local
    }
  end

  defp build_resource_context(:remote, conn) do
    %{
      facts: detect_remote_facts(conn),
      host_id: :remote
    }
  end

  defp detect_local_facts do
    # Detect local OS family
    case :os.type() do
      {:unix, :darwin} -> %{os_family: :darwin, os: :macos}
      {:unix, :linux} -> detect_linux_family_local()
      {:win32, _} -> %{os_family: :windows, os: :windows}
      _ -> %{os_family: :unknown, os: :unknown}
    end
  end

  defp detect_linux_family_local do
    cond do
      File.exists?("/etc/debian_version") -> %{os_family: :debian, os: :linux}
      File.exists?("/etc/redhat-release") -> %{os_family: :redhat, os: :linux}
      File.exists?("/etc/arch-release") -> %{os_family: :arch, os: :linux}
      File.exists?("/etc/alpine-release") -> %{os_family: :alpine, os: :linux}
      true -> %{os_family: :linux, os: :linux}
    end
  end

  defp detect_remote_facts(conn) do
    # Try to detect OS family on remote host
    case Connection.exec(conn, "cat /etc/os-release 2>/dev/null || echo 'unknown'",
           timeout: 5_000
         ) do
      {:ok, output, 0} ->
        parse_os_release(output)

      _ ->
        # Fallback: try uname
        case Connection.exec(conn, "uname -s", timeout: 5_000) do
          {:ok, "Darwin" <> _, 0} -> %{os_family: :darwin, os: :macos}
          {:ok, "Linux" <> _, 0} -> %{os_family: :linux, os: :linux}
          _ -> %{os_family: :unknown, os: :unknown}
        end
    end
  end

  defp parse_os_release(output) do
    lines = String.split(output, "\n")
    id = find_os_release_value(lines, "ID=")
    id_like = find_os_release_value(lines, "ID_LIKE=")

    os_family =
      cond do
        id in ["debian", "ubuntu", "raspbian"] -> :debian
        id_like =~ "debian" -> :debian
        id in ["rhel", "centos", "fedora", "rocky", "alma"] -> :redhat
        id_like =~ "rhel" or id_like =~ "fedora" -> :redhat
        id == "arch" -> :arch
        id == "alpine" -> :alpine
        true -> :linux
      end

    %{os_family: os_family, os: :linux}
  end

  defp find_os_release_value(lines, prefix) do
    case Enum.find(lines, &String.starts_with?(&1, prefix)) do
      nil -> ""
      line -> line |> String.replace(prefix, "") |> String.trim() |> String.replace("\"", "")
    end
  end

  defp describe_resource(%Package{name: name}), do: "package[#{name}]"
  defp describe_resource(%Service{name: name}), do: "service[#{name}]"
  defp describe_resource(%FileResource{path: path}), do: "file[#{path}]"
  defp describe_resource(%Directory{path: path}), do: "directory[#{path}]"
  defp describe_resource(%User{name: name}), do: "user[#{name}]"
  defp describe_resource(%Group{name: name}), do: "group[#{name}]"
  defp describe_resource(r), do: inspect(r)

  defp convert_resource_result(result, cmd_desc, duration) do
    base = %{
      cmd: cmd_desc,
      status: if(result.status in [:ok, :changed, :skipped], do: :ok, else: :error),
      output: result.message || status_to_message(result.status),
      exit_code: if(result.status == :failed, do: 1, else: 0),
      attempts: 1,
      duration_ms: duration
    }

    # Add notify if present and changed
    if result.notify && result.status == :changed do
      Map.put(base, :notify, result.notify)
    else
      base
    end
  end

  defp status_to_message(:ok), do: "already in desired state"
  defp status_to_message(:changed), do: "changed"
  defp status_to_message(:skipped), do: "skipped"
  defp status_to_message(:failed), do: "failed"

  # ============================================================================
  # Helpers
  # ============================================================================

  defp build_file_op_result(cmd_desc, result, duration, notify) do
    base_result =
      case result do
        {:ok, output} ->
          %{
            cmd: cmd_desc,
            status: :ok,
            output: output,
            exit_code: 0,
            attempts: 1,
            duration_ms: duration
          }

        {:error, reason} ->
          %{
            cmd: cmd_desc,
            status: :error,
            output: inspect(reason),
            exit_code: 1,
            attempts: 1,
            duration_ms: duration
          }
      end

    if notify && match?({:ok, _}, result) do
      Map.put(base_result, :notify, notify)
    else
      base_result
    end
  end
end
