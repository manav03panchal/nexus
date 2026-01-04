defmodule Nexus.Executor.Pipeline do
  @moduledoc """
  Orchestrates the execution of multiple tasks in dependency order.

  The Pipeline module takes a configuration and a list of target tasks,
  resolves dependencies using the DAG, and executes tasks in phases.
  Tasks within the same phase can run in parallel.

  ## Examples

      # Run a single task with its dependencies
      {:ok, result} = Pipeline.run(config, [:deploy])

      # Run multiple tasks
      {:ok, result} = Pipeline.run(config, [:test, :deploy])

      # Dry run to see execution plan
      {:ok, plan} = Pipeline.dry_run(config, [:deploy])

  """

  alias Nexus.DAG
  alias Nexus.Executor.TaskRunner
  alias Nexus.Telemetry
  alias Nexus.Types.{Config, Handler}
  alias Nexus.Types.Task, as: NexusTask

  @type pipeline_result :: %{
          status: :ok | :error,
          duration_ms: non_neg_integer(),
          tasks_run: non_neg_integer(),
          tasks_succeeded: non_neg_integer(),
          tasks_failed: non_neg_integer(),
          task_results: [TaskRunner.task_result()],
          aborted_at: atom() | nil
        }

  @type execution_plan :: %{
          phases: [[atom()]],
          total_tasks: non_neg_integer(),
          task_details: %{atom() => Task.t()}
        }

  @type run_opts :: [
          continue_on_error: boolean(),
          parallel_limit: pos_integer(),
          dry_run: boolean(),
          ssh_opts: keyword()
        ]

  @doc """
  Runs the specified tasks and their dependencies.

  Tasks are executed in phases based on the dependency graph.
  Each phase contains tasks that can run in parallel (they have
  no dependencies on each other within the phase).

  ## Options

    * `:continue_on_error` - Continue executing other tasks if one fails (default: false)
    * `:parallel_limit` - Maximum number of tasks to run in parallel (default: 10)
    * `:ssh_opts` - Options to pass to SSH connections

  ## Returns

    * `{:ok, pipeline_result}` - Pipeline completed
    * `{:error, reason}` - Pipeline failed to start

  """
  @spec run(Config.t(), [atom()], run_opts()) :: {:ok, pipeline_result()} | {:error, term()}
  def run(%Config{} = config, target_tasks, opts \\ []) do
    with {:ok, plan} <- build_execution_plan(config, target_tasks) do
      execute_plan(config, plan, opts)
    end
  end

  @doc """
  Returns the execution plan without running anything.

  Useful for previewing what tasks would run and in what order.

  ## Examples

      {:ok, plan} = Pipeline.dry_run(config, [:deploy])
      # plan.phases might be [[:build], [:test], [:deploy]]

  """
  @spec dry_run(Config.t(), [atom()]) :: {:ok, execution_plan()} | {:error, term()}
  def dry_run(%Config{} = config, target_tasks) do
    build_execution_plan(config, target_tasks)
  end

  @doc """
  Validates that the target tasks exist and have valid dependencies.

  ## Returns

    * `:ok` - All tasks valid
    * `{:error, reason}` - Validation failed

  """
  @spec validate(Config.t(), [atom()]) :: :ok | {:error, term()}
  def validate(%Config{} = config, target_tasks) do
    # Check that all target tasks exist
    missing = Enum.filter(target_tasks, fn t -> not Map.has_key?(config.tasks, t) end)

    if Enum.empty?(missing) do
      # Check for cycles
      case DAG.build(config) do
        {:ok, _graph} -> :ok
        {:error, {:cycle, path}} -> {:error, {:cycle, path}}
      end
    else
      {:error, {:unknown_tasks, missing}}
    end
  end

  # Build the execution plan from target tasks
  defp build_execution_plan(%Config{} = config, target_tasks) do
    # Validate tasks exist
    missing = Enum.filter(target_tasks, fn t -> not Map.has_key?(config.tasks, t) end)

    if Enum.empty?(missing) do
      build_plan_from_dag(config, target_tasks)
    else
      {:error, {:unknown_tasks, missing}}
    end
  end

  defp build_plan_from_dag(config, target_tasks) do
    case DAG.build(config) do
      {:ok, graph} ->
        # Get all tasks that need to run (targets + their dependencies)
        all_tasks = collect_required_tasks(graph, target_tasks)

        # Build subgraph for just the required tasks
        subgraph = Graph.subgraph(graph, all_tasks)

        # Get execution phases
        phases = DAG.execution_phases(subgraph)

        # Collect task details
        task_details =
          all_tasks
          |> Enum.map(fn name -> {name, Map.fetch!(config.tasks, name)} end)
          |> Map.new()

        {:ok,
         %{
           phases: phases,
           total_tasks: length(all_tasks),
           task_details: task_details
         }}

      {:error, {:cycle, path}} ->
        {:error, {:cycle, path}}
    end
  end

  defp collect_required_tasks(graph, target_tasks) do
    target_tasks
    |> Enum.flat_map(fn task ->
      [task | DAG.dependencies(graph, task)]
    end)
    |> Enum.uniq()
  end

  # Execute the plan phase by phase
  defp execute_plan(%Config{} = config, plan, opts) do
    target_tasks = Map.keys(plan.task_details)
    Telemetry.emit_pipeline_start(target_tasks, %{total_tasks: plan.total_tasks})

    start_time = System.monotonic_time(:millisecond)
    continue_on_error = Keyword.get(opts, :continue_on_error, config.continue_on_error)
    parallel_limit = Keyword.get(opts, :parallel_limit, 10)

    initial_state = %{
      task_results: [],
      tasks_succeeded: 0,
      tasks_failed: 0,
      aborted_at: nil,
      triggered_handlers: MapSet.new()
    }

    final_state =
      Enum.reduce_while(plan.phases, initial_state, fn phase, state ->
        {:ok, phase_results} =
          execute_phase(config, phase, plan.task_details, opts, parallel_limit)

        succeeded = Enum.count(phase_results, &(&1.status == :ok))
        failed = length(phase_results) - succeeded

        # Collect triggered handlers from this phase
        phase_handlers =
          phase_results
          |> Enum.flat_map(&Map.get(&1, :triggered_handlers, []))
          |> MapSet.new()

        new_state = %{
          state
          | task_results: state.task_results ++ phase_results,
            tasks_succeeded: state.tasks_succeeded + succeeded,
            tasks_failed: state.tasks_failed + failed,
            triggered_handlers: MapSet.union(state.triggered_handlers, phase_handlers)
        }

        if failed > 0 and not continue_on_error do
          # Find the first failed task
          failed_task =
            phase_results
            |> Enum.find(&(&1.status == :error))
            |> Map.get(:task)

          {:halt, %{new_state | aborted_at: failed_task}}
        else
          {:cont, new_state}
        end
      end)

    # Execute triggered handlers after all tasks complete
    {handler_results, handler_succeeded, handler_failed} =
      execute_triggered_handlers(config, final_state.triggered_handlers, opts)

    duration = System.monotonic_time(:millisecond) - start_time

    total_failed = final_state.tasks_failed + handler_failed
    overall_status = if total_failed > 0, do: :error, else: :ok

    result = %{
      status: overall_status,
      duration_ms: duration,
      tasks_run: final_state.tasks_succeeded + final_state.tasks_failed,
      tasks_succeeded: final_state.tasks_succeeded,
      tasks_failed: final_state.tasks_failed,
      task_results: final_state.task_results,
      handler_results: handler_results,
      handlers_succeeded: handler_succeeded,
      handlers_failed: handler_failed,
      aborted_at: final_state.aborted_at
    }

    Telemetry.emit_pipeline_stop(duration, result)

    {:ok, result}
  end

  # Default timeout for individual task execution (10 minutes)
  @default_task_timeout 600_000

  defp execute_phase(config, phase, task_details, opts, parallel_limit) do
    # Use task timeout from config or opts, with a sensible default
    task_timeout = Keyword.get(opts, :task_timeout, @default_task_timeout)

    # Execute all tasks in the phase in parallel (up to the limit)
    phase
    |> Task.async_stream(
      fn task_name ->
        task = Map.fetch!(task_details, task_name)
        hosts = resolve_task_hosts(config, task)
        TaskRunner.run(task, hosts, opts)
      end,
      max_concurrency: parallel_limit,
      timeout: task_timeout
    )
    |> Enum.map(fn
      {:ok, {:ok, result}} ->
        result

      {:ok, {:error, reason}} ->
        %{task: :unknown, status: :error, duration_ms: 0, host_results: [], error: reason}

      {:exit, reason} ->
        %{
          task: :unknown,
          status: :error,
          duration_ms: 0,
          host_results: [],
          error: {:exit, reason}
        }
    end)
    |> then(&{:ok, &1})
  end

  defp resolve_task_hosts(%Config{} = config, %NexusTask{} = task) do
    case Config.resolve_hosts(config, task.on) do
      {:ok, hosts} -> hosts
      {:error, _} -> []
    end
  end

  # Execute triggered handlers after all tasks complete
  defp execute_triggered_handlers(_config, handlers, _opts) when handlers == %MapSet{} do
    {[], 0, 0}
  end

  defp execute_triggered_handlers(config, handler_names, opts) do
    if MapSet.size(handler_names) == 0 do
      {[], 0, 0}
    else
      results =
        handler_names
        |> MapSet.to_list()
        |> Enum.map(fn handler_name ->
          execute_handler(config, handler_name, opts)
        end)

      succeeded = Enum.count(results, &(&1.status == :ok))
      failed = length(results) - succeeded

      {results, succeeded, failed}
    end
  end

  defp execute_handler(%Config{} = config, handler_name, opts) do
    case Map.get(config.handlers, handler_name) do
      nil ->
        %{
          handler: handler_name,
          status: :error,
          error: :handler_not_found,
          duration_ms: 0,
          host_results: []
        }

      %Handler{} = handler ->
        # Create a synthetic task to run the handler commands
        # Handlers run on all hosts by default (could be improved to track which hosts triggered)
        all_hosts = Map.values(config.hosts)
        run_handler_on_hosts(handler, all_hosts, opts)
    end
  end

  defp run_handler_on_hosts(%Handler{} = handler, hosts, opts) do
    start_time = System.monotonic_time(:millisecond)

    # Create a synthetic task from the handler
    handler_task = %NexusTask{
      name: handler.name,
      on: :all,
      commands: handler.commands,
      strategy: :parallel,
      timeout: 300_000
    }

    result =
      case TaskRunner.run(handler_task, hosts, opts) do
        {:ok, task_result} ->
          %{
            handler: handler.name,
            status: task_result.status,
            duration_ms: task_result.duration_ms,
            host_results: task_result.host_results
          }

        {:error, reason} ->
          duration = System.monotonic_time(:millisecond) - start_time

          %{
            handler: handler.name,
            status: :error,
            error: reason,
            duration_ms: duration,
            host_results: []
          }
      end

    result
  end
end
