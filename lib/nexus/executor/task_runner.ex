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

  alias Nexus.Conditions.Evaluator
  alias Nexus.Executor.{HealthCheck, Local}
  alias Nexus.Executor.Strategies.Rolling
  alias Nexus.Facts.{Cache, Gatherer}
  alias Nexus.Resources.Executor, as: ResourceExecutor
  alias Nexus.Resources.Types.Command, as: ResourceCommand
  alias Nexus.Resources.Types.{Directory, Group, Package, Service, User}
  alias Nexus.Resources.Types.File, as: ResourceFile
  alias Nexus.SSH.{Connection, Pool, SFTP}
  alias Nexus.Telemetry
  alias Nexus.Template.Renderer
  alias Nexus.Types.{Command, Download, Host, Template, Upload, WaitFor}
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

        {:ok,
         %{
           task: task.name,
           status: overall_status,
           duration_ms: duration,
           host_results: host_results
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Local task execution
  defp run_local_task(%NexusTask{} = task, opts) do
    continue_on_error = Keyword.get(opts, :continue_on_error, false)

    {:ok, command_results} = run_commands_locally(task.commands, continue_on_error)
    status = determine_status(command_results)
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
        :rolling -> run_rolling(task, hosts, opts)
        :canary -> run_canary(task, hosts, opts)
      end
    end
  end

  defp run_rolling(%NexusTask{} = task, hosts, opts) do
    rolling_opts =
      opts
      |> Keyword.put(:batch_size, task.batch_size)

    Rolling.run(task, hosts, rolling_opts)
  end

  defp run_canary(%NexusTask{} = task, hosts, opts) do
    alias Nexus.Executor.Strategies.Canary

    canary_opts =
      opts
      |> Keyword.put(:canary_hosts, task.canary_hosts)
      |> Keyword.put(:canary_wait, task.canary_wait)
      |> Keyword.put(:batch_size, task.batch_size)

    Canary.run(task, hosts, canary_opts)
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
           fn conn ->
             # Gather facts for this host if not already cached
             context = get_or_gather_facts(conn, host)
             run_commands_remotely(conn, task.commands, continue_on_error, context)
           end,
           pool_opts
         ) do
      {:ok, command_results} ->
        status = determine_status(command_results)
        {:ok, %{host: host.name, status: status, commands: command_results}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_or_gather_facts(conn, host) do
    host_id = host.name

    facts =
      if Cache.cached?(host_id) do
        Cache.get_all(host_id)
      else
        case Gatherer.gather_all(conn) do
          {:ok, gathered_facts} ->
            Cache.put_all(host_id, gathered_facts)
            gathered_facts

          {:error, _} ->
            %{}
        end
      end

    Evaluator.build_context(host_id, facts)
  end

  defp run_commands_locally(commands, continue_on_error) do
    # For local execution, gather local facts
    {:ok, facts} = Gatherer.gather_local()
    context = Evaluator.build_context(:local, facts)
    resource_context = %{facts: facts, check_mode: false, host_id: :local}

    run_commands(
      commands,
      continue_on_error,
      &execute_local_command(&1, resource_context),
      context
    )
  end

  # Determine overall status: :ok if all commands succeeded or were skipped, :error otherwise
  defp determine_status(command_results) do
    Enum.all?(command_results, fn result ->
      result.status in [:ok, :skipped]
    end)
    |> if(do: :ok, else: :error)
  end

  defp run_commands_remotely(conn, commands, continue_on_error, context) do
    # Extract facts from the Evaluator context for resource execution
    facts = Map.get(context, :facts, %{})
    host_id = Map.get(context, :host_id, :unknown)
    resource_context = %{facts: facts, check_mode: false, host_id: host_id}

    run_commands(
      commands,
      continue_on_error,
      &execute_remote_command(&1, conn, resource_context),
      context
    )
  end

  defp run_commands(commands, continue_on_error, executor, context) do
    {results, _} =
      Enum.reduce_while(commands, {[], :continue}, fn cmd, {acc, _} ->
        run_single_command(cmd, continue_on_error, executor, context, acc)
      end)

    {:ok, Enum.reverse(results)}
  end

  defp run_single_command(cmd, continue_on_error, executor, context, acc) do
    condition = get_condition(cmd)

    if Evaluator.evaluate(condition, context) do
      result = execute_with_retry(cmd, executor)
      handle_command_result(result, continue_on_error, acc)
    else
      result = make_skipped_result(cmd)
      {:cont, {[result | acc], :continue}}
    end
  end

  defp handle_command_result(result, continue_on_error, acc) do
    if result.status == :error and not continue_on_error do
      {:halt, {[result | acc], :stopped}}
    else
      {:cont, {[result | acc], :continue}}
    end
  end

  defp get_condition(%Command{when: condition}), do: condition
  defp get_condition(%Upload{when: condition}), do: condition
  defp get_condition(%Download{when: condition}), do: condition
  defp get_condition(%Template{when: condition}), do: condition
  defp get_condition(%WaitFor{when: condition}), do: condition
  # Resource types
  defp get_condition(%Package{when: condition}), do: condition
  defp get_condition(%Service{when: condition}), do: condition
  defp get_condition(%ResourceFile{when: condition}), do: condition
  defp get_condition(%Directory{when: condition}), do: condition
  defp get_condition(%User{when: condition}), do: condition
  defp get_condition(%Group{when: condition}), do: condition
  defp get_condition(%ResourceCommand{when: condition}), do: condition
  defp get_condition(_), do: true

  defp make_skipped_result(%Command{cmd: cmd}) do
    %{
      cmd: cmd,
      status: :skipped,
      output: "condition not met",
      exit_code: 0,
      attempts: 0,
      duration_ms: 0
    }
  end

  defp make_skipped_result(%Upload{local_path: local, remote_path: remote}) do
    %{
      cmd: "upload #{local} -> #{remote}",
      status: :skipped,
      output: "condition not met",
      exit_code: 0,
      attempts: 0,
      duration_ms: 0
    }
  end

  defp make_skipped_result(%Download{remote_path: remote, local_path: local}) do
    %{
      cmd: "download #{remote} -> #{local}",
      status: :skipped,
      output: "condition not met",
      exit_code: 0,
      attempts: 0,
      duration_ms: 0
    }
  end

  defp make_skipped_result(%Template{source: src, destination: dest}) do
    %{
      cmd: "template #{src} -> #{dest}",
      status: :skipped,
      output: "condition not met",
      exit_code: 0,
      attempts: 0,
      duration_ms: 0
    }
  end

  defp make_skipped_result(%WaitFor{type: type, target: target}) do
    %{
      cmd: "wait_for #{type} #{target}",
      status: :skipped,
      output: "condition not met",
      exit_code: 0,
      attempts: 0,
      duration_ms: 0
    }
  end

  # Resource types - use describe function
  defp make_skipped_result(%Package{} = r) do
    %{
      cmd: Package.describe(r),
      status: :skipped,
      output: "condition not met",
      exit_code: 0,
      attempts: 0,
      duration_ms: 0
    }
  end

  defp make_skipped_result(%Service{} = r) do
    %{
      cmd: Service.describe(r),
      status: :skipped,
      output: "condition not met",
      exit_code: 0,
      attempts: 0,
      duration_ms: 0
    }
  end

  defp make_skipped_result(%ResourceFile{} = r) do
    %{
      cmd: ResourceFile.describe(r),
      status: :skipped,
      output: "condition not met",
      exit_code: 0,
      attempts: 0,
      duration_ms: 0
    }
  end

  defp make_skipped_result(%Directory{} = r) do
    %{
      cmd: Directory.describe(r),
      status: :skipped,
      output: "condition not met",
      exit_code: 0,
      attempts: 0,
      duration_ms: 0
    }
  end

  defp make_skipped_result(%User{} = r) do
    %{
      cmd: User.describe(r),
      status: :skipped,
      output: "condition not met",
      exit_code: 0,
      attempts: 0,
      duration_ms: 0
    }
  end

  defp make_skipped_result(%Group{} = r) do
    %{
      cmd: Group.describe(r),
      status: :skipped,
      output: "condition not met",
      exit_code: 0,
      attempts: 0,
      duration_ms: 0
    }
  end

  defp make_skipped_result(%ResourceCommand{} = r) do
    %{
      cmd: ResourceCommand.describe(r),
      status: :skipped,
      output: "condition not met",
      exit_code: 0,
      attempts: 0,
      duration_ms: 0
    }
  end

  defp execute_with_retry(command, executor) do
    execute_with_retry(command, executor, 1)
  end

  defp execute_with_retry(%Command{} = cmd, executor, attempt) do
    start_time = System.monotonic_time(:millisecond)
    result = executor.(cmd)
    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, output, 0} ->
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
          delay = calculate_retry_delay(cmd.retry_delay, attempt)
          cmd_preview = String.slice(cmd.cmd, 0, 40)
          IO.puts("    ↻ Retry #{attempt}/#{cmd.retries}: #{cmd_preview} (waiting #{delay}ms)")
          Telemetry.emit_command_retry(cmd.cmd, attempt, cmd.retries, delay, exit_code)
          Process.sleep(delay)
          execute_with_retry(cmd, executor, attempt + 1)
        else
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
          delay = calculate_retry_delay(cmd.retry_delay, attempt)
          cmd_preview = String.slice(cmd.cmd, 0, 40)
          IO.puts("    ↻ Retry #{attempt}/#{cmd.retries}: #{cmd_preview} (waiting #{delay}ms)")
          Telemetry.emit_command_retry(cmd.cmd, attempt, cmd.retries, delay, -1)
          Process.sleep(delay)
          execute_with_retry(cmd, executor, attempt + 1)
        else
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

  defp execute_with_retry(%Upload{} = upload, executor, attempt) do
    start_time = System.monotonic_time(:millisecond)
    result = executor.(upload)
    duration = System.monotonic_time(:millisecond) - start_time
    cmd_desc = "upload #{upload.local_path} -> #{upload.remote_path}"

    case result do
      {:ok, output, 0} ->
        %{
          cmd: cmd_desc,
          status: :ok,
          output: output,
          exit_code: 0,
          attempts: attempt,
          duration_ms: duration
        }

      {:error, reason} ->
        %{
          cmd: cmd_desc,
          status: :error,
          output: inspect(reason),
          exit_code: -1,
          attempts: attempt,
          duration_ms: duration
        }
    end
  end

  defp execute_with_retry(%Download{} = download, executor, attempt) do
    start_time = System.monotonic_time(:millisecond)
    result = executor.(download)
    duration = System.monotonic_time(:millisecond) - start_time
    cmd_desc = "download #{download.remote_path} -> #{download.local_path}"

    case result do
      {:ok, output, 0} ->
        %{
          cmd: cmd_desc,
          status: :ok,
          output: output,
          exit_code: 0,
          attempts: attempt,
          duration_ms: duration
        }

      {:error, reason} ->
        %{
          cmd: cmd_desc,
          status: :error,
          output: inspect(reason),
          exit_code: -1,
          attempts: attempt,
          duration_ms: duration
        }
    end
  end

  defp execute_with_retry(%Template{} = template, executor, attempt) do
    start_time = System.monotonic_time(:millisecond)
    result = executor.(template)
    duration = System.monotonic_time(:millisecond) - start_time
    cmd_desc = "template #{template.source} -> #{template.destination}"

    case result do
      {:ok, output, 0} ->
        %{
          cmd: cmd_desc,
          status: :ok,
          output: output,
          exit_code: 0,
          attempts: attempt,
          duration_ms: duration
        }

      {:error, reason} ->
        %{
          cmd: cmd_desc,
          status: :error,
          output: inspect(reason),
          exit_code: -1,
          attempts: attempt,
          duration_ms: duration
        }
    end
  end

  defp execute_with_retry(%WaitFor{} = wait_for, executor, attempt) do
    start_time = System.monotonic_time(:millisecond)
    result = executor.(wait_for)
    duration = System.monotonic_time(:millisecond) - start_time
    cmd_desc = "wait_for #{wait_for.type} #{wait_for.target}"

    case result do
      {:ok, output, 0} ->
        %{
          cmd: cmd_desc,
          status: :ok,
          output: output,
          exit_code: 0,
          attempts: attempt,
          duration_ms: duration
        }

      {:error, reason} ->
        %{
          cmd: cmd_desc,
          status: :error,
          output: inspect(reason),
          exit_code: -1,
          attempts: attempt,
          duration_ms: duration
        }
    end
  end

  # Resource types - delegate to ResourceExecutor
  defp execute_with_retry(resource, executor, attempt) when is_struct(resource) do
    # Check if this is a resource type
    if resource_type?(resource) do
      # executor contains either {:local, context} or {:remote, conn, context}
      result = executor.(resource)
      format_resource_result(resource, result, attempt)
    else
      # Unknown type - should not happen
      %{
        cmd: "unknown",
        status: :error,
        output: "Unknown command type: #{inspect(resource.__struct__)}",
        exit_code: -1,
        attempts: attempt,
        duration_ms: 0
      }
    end
  end

  defp resource_type?(%Package{}), do: true
  defp resource_type?(%Service{}), do: true
  defp resource_type?(%ResourceFile{}), do: true
  defp resource_type?(%Directory{}), do: true
  defp resource_type?(%User{}), do: true
  defp resource_type?(%Group{}), do: true
  defp resource_type?(%ResourceCommand{}), do: true
  defp resource_type?(_), do: false

  defp format_resource_result(resource, {:ok, result}, attempt) do
    status = normalize_result_status(result.status)

    %{
      cmd: get_resource_description(resource),
      status: status,
      output: extract_result_output(result),
      exit_code: status_to_exit_code(status),
      attempts: attempt,
      duration_ms: result.duration_ms
    }
  end

  defp format_resource_result(resource, {:error, reason}, attempt) do
    cmd_desc = get_resource_description(resource)

    %{
      cmd: cmd_desc,
      status: :error,
      output: inspect(reason),
      exit_code: -1,
      attempts: attempt,
      duration_ms: 0
    }
  end

  defp normalize_result_status(:ok), do: :ok
  defp normalize_result_status(:changed), do: :ok
  defp normalize_result_status(:skipped), do: :skipped
  defp normalize_result_status(:failed), do: :error

  defp extract_result_output(%{message: message}) when is_binary(message), do: message

  defp extract_result_output(%{diff: %{changes: changes}}) when changes != [],
    do: Enum.join(changes, ", ")

  defp extract_result_output(_), do: ""

  defp status_to_exit_code(:error), do: 1
  defp status_to_exit_code(_), do: 0

  defp get_resource_description(%Package{} = r), do: Package.describe(r)
  defp get_resource_description(%Service{} = r), do: Service.describe(r)
  defp get_resource_description(%ResourceFile{} = r), do: ResourceFile.describe(r)
  defp get_resource_description(%Directory{} = r), do: Directory.describe(r)
  defp get_resource_description(%User{} = r), do: User.describe(r)
  defp get_resource_description(%Group{} = r), do: Group.describe(r)
  defp get_resource_description(%ResourceCommand{} = r), do: ResourceCommand.describe(r)

  @doc """
  Executes a single command and returns a result map.

  Used by rolling deployment strategy to execute individual commands.
  """
  @spec execute_command(term(), term(), map()) :: command_result()
  def execute_command(
        command,
        conn,
        resource_context \\ %{facts: %{}, check_mode: false, host_id: :unknown}
      ) do
    executor = fn cmd -> execute_remote_command(cmd, conn, resource_context) end
    execute_with_retry(command, executor, 1)
  end

  defp execute_local_command(%Command{} = cmd, _resource_context) do
    if cmd.sudo do
      Local.run_sudo(cmd)
    else
      Local.run(cmd)
    end
  end

  defp execute_local_command(%Upload{} = _upload, _resource_context) do
    # Local upload doesn't make sense - it's a copy
    {:error, :upload_not_supported_locally}
  end

  defp execute_local_command(%Download{} = _download, _resource_context) do
    # Local download doesn't make sense - it's a copy
    {:error, :download_not_supported_locally}
  end

  defp execute_local_command(%Template{} = _template, _resource_context) do
    # Local template doesn't make sense - templates are for remote hosts
    {:error, :template_not_supported_locally}
  end

  defp execute_local_command(%WaitFor{} = wait_for, _resource_context) do
    case HealthCheck.wait(wait_for, []) do
      :ok -> {:ok, "health check passed", 0}
      {:error, reason} -> {:error, reason}
    end
  end

  # Resource types - execute locally via ResourceExecutor
  # Dialyzer false positive: the context map type is compatible with Executor.execute/3
  @dialyzer {:nowarn_function, execute_local_command: 2}
  defp execute_local_command(resource, resource_context) when is_struct(resource) do
    if resource_type?(resource) do
      ResourceExecutor.execute(resource, nil, resource_context)
    else
      {:error, {:unknown_command_type, resource.__struct__}}
    end
  end

  defp execute_remote_command(%Command{} = cmd, conn, _resource_context) do
    if cmd.sudo do
      Connection.exec_sudo(conn, cmd.cmd, timeout: cmd.timeout, sudo_user: cmd.user)
    else
      Connection.exec(conn, cmd.cmd, timeout: cmd.timeout)
    end
  end

  defp execute_remote_command(%Upload{} = upload, conn, _resource_context) do
    opts = [sudo: upload.sudo, mode: upload.mode]

    case SFTP.upload(conn, upload.local_path, upload.remote_path, opts) do
      :ok -> {:ok, "uploaded #{upload.local_path} -> #{upload.remote_path}", 0}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_remote_command(%Download{} = download, conn, _resource_context) do
    opts = [sudo: download.sudo]

    case SFTP.download(conn, download.remote_path, download.local_path, opts) do
      :ok -> {:ok, "downloaded #{download.remote_path} -> #{download.local_path}", 0}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_remote_command(%Template{} = template, conn, _resource_context) do
    # First, render the template locally
    case Renderer.render_file(template.source, template.vars) do
      {:ok, content} ->
        # Write to a temp file, then upload
        upload_rendered_template(conn, content, template)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_remote_command(%WaitFor{} = wait_for, conn, _resource_context) do
    case HealthCheck.wait(wait_for, conn: conn) do
      :ok -> {:ok, "health check passed", 0}
      {:error, reason} -> {:error, reason}
    end
  end

  # Resource types - execute remotely via ResourceExecutor
  defp execute_remote_command(resource, conn, resource_context) when is_struct(resource) do
    if resource_type?(resource) do
      ResourceExecutor.execute(resource, conn, resource_context)
    else
      {:error, {:unknown_command_type, resource.__struct__}}
    end
  end

  defp upload_rendered_template(conn, content, template) do
    # Create a temp file with the rendered content
    temp_path =
      System.tmp_dir!() |> Path.join("nexus_template_#{:erlang.unique_integer([:positive])}")

    try do
      File.write!(temp_path, content)
      opts = [sudo: template.sudo, mode: template.mode]

      case SFTP.upload(conn, temp_path, template.destination, opts) do
        :ok -> {:ok, "template #{template.source} -> #{template.destination}", 0}
        {:error, reason} -> {:error, reason}
      end
    after
      File.rm(temp_path)
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
