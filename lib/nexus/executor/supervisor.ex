defmodule Nexus.Executor.Supervisor do
  @moduledoc """
  DynamicSupervisor for managing task execution processes.

  This supervisor manages the lifecycle of task execution processes,
  providing fault tolerance and clean shutdown semantics.

  ## Usage

  The supervisor is started as part of the Nexus application. You can
  start task processes under it using `start_task/2`.

  ## Example

      {:ok, pid} = Nexus.Executor.Supervisor.start_task(task, opts)

  """

  use DynamicSupervisor

  @doc """
  Starts the executor supervisor.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl DynamicSupervisor
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a task execution process under this supervisor.

  The task process is started as a `Task` that will execute the given
  function. The process is supervised and will be cleaned up on completion
  or failure.

  ## Options

    * `:supervisor` - The supervisor to use (default: `__MODULE__`)

  ## Examples

      {:ok, pid} = Supervisor.start_task(fn -> run_task(task) end)

  """
  @spec start_task((-> any()), keyword()) :: DynamicSupervisor.on_start_child()
  def start_task(fun, opts \\ []) when is_function(fun, 0) do
    supervisor = Keyword.get(opts, :supervisor, __MODULE__)

    spec = %{
      id: make_ref(),
      start: {Task, :start_link, [fun]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(supervisor, spec)
  end

  @doc """
  Starts a named task execution process.

  Similar to `start_task/2` but allows tracking the task by name.

  ## Examples

      {:ok, pid} = Supervisor.start_named_task(:deploy_web, fn -> deploy() end)

  """
  @spec start_named_task(atom(), (-> any()), keyword()) :: DynamicSupervisor.on_start_child()
  def start_named_task(name, fun, opts \\ []) when is_atom(name) and is_function(fun, 0) do
    supervisor = Keyword.get(opts, :supervisor, __MODULE__)

    spec = %{
      id: name,
      start: {Task, :start_link, [fun]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(supervisor, spec)
  end

  @doc """
  Returns the count of currently running task processes.
  """
  @spec count_tasks(atom()) :: non_neg_integer()
  def count_tasks(supervisor \\ __MODULE__) do
    DynamicSupervisor.count_children(supervisor).active
  end

  @doc """
  Terminates all running task processes.

  This is useful for pipeline abort scenarios where all in-flight
  tasks need to be stopped immediately.
  """
  @spec terminate_all(atom()) :: :ok
  def terminate_all(supervisor \\ __MODULE__) do
    DynamicSupervisor.which_children(supervisor)
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(supervisor, pid)
    end)

    :ok
  end

  @doc """
  Returns a list of currently running task process pids.
  """
  @spec list_tasks(atom()) :: [pid()]
  def list_tasks(supervisor \\ __MODULE__) do
    DynamicSupervisor.which_children(supervisor)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.filter(&is_pid/1)
  end
end
