defmodule Nexus.Resources.HandlerQueue do
  @moduledoc """
  Manages handler queueing and execution during task runs.

  Handlers are triggered when resources with `notify:` option change.
  By default, handlers are queued and executed at the end of the task.
  Use `timing: :immediate` for immediate execution.

  ## Usage

      # Start the queue (typically done by TaskRunner)
      HandlerQueue.start_link()

      # Queue a handler (done by resource executor when resource changes)
      HandlerQueue.enqueue(:reload_nginx)

      # Queue with immediate timing (executes right away)
      {:immediate, :reload_nginx} = HandlerQueue.enqueue(:reload_nginx, timing: :immediate)

      # Get and clear all queued handlers (at end of task)
      handlers = HandlerQueue.flush()

      # Clean up
      HandlerQueue.stop()

  ## Deduplication

  Handlers are deduplicated - if the same handler is notified multiple
  times during a task, it only runs once at the end.

  """

  use Agent

  @type handler_name :: atom()
  @type timing :: :end | :immediate

  defstruct queued: MapSet.new()

  @doc """
  Starts the handler queue agent.

  Returns `{:ok, pid}` or `{:error, reason}`.
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %__MODULE__{} end, name: name)
  end

  @doc """
  Stops the handler queue agent.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server \\ __MODULE__) do
    Agent.stop(server)
  end

  @doc """
  Enqueues a handler to be run.

  Duplicates are ignored - each handler runs at most once per task.

  ## Options

    * `:timing` - When to execute (`:end` or `:immediate`). Default `:end`.

  ## Returns

    * `:queued` - Handler was queued for end of task
    * `{:immediate, handler_name}` - Handler should be executed immediately

  """
  @spec enqueue(handler_name(), keyword()) :: :queued | {:immediate, handler_name()}
  def enqueue(handler_name, opts \\ []) do
    enqueue(__MODULE__, handler_name, opts)
  end

  @doc """
  Enqueues a handler on a specific queue server.
  """
  @spec enqueue(GenServer.server(), handler_name(), keyword()) ::
          :queued | {:immediate, handler_name()}
  def enqueue(server, handler_name, opts) do
    timing = Keyword.get(opts, :timing, :end)

    Agent.update(server, fn state ->
      %{state | queued: MapSet.put(state.queued, handler_name)}
    end)

    if timing == :immediate do
      {:immediate, handler_name}
    else
      :queued
    end
  end

  @doc """
  Returns all queued handlers and clears the queue.

  This is typically called at the end of a task to get all
  handlers that need to run.
  """
  @spec flush() :: [handler_name()]
  def flush, do: flush(__MODULE__)

  @doc """
  Flushes handlers from a specific queue server.
  """
  @spec flush(GenServer.server()) :: [handler_name()]
  def flush(server) do
    Agent.get_and_update(server, fn state ->
      handlers = MapSet.to_list(state.queued)
      {handlers, %{state | queued: MapSet.new()}}
    end)
  end

  @doc """
  Returns all currently queued handlers without clearing.
  """
  @spec list() :: [handler_name()]
  def list, do: list(__MODULE__)

  @doc """
  Lists handlers from a specific queue server.
  """
  @spec list(GenServer.server()) :: [handler_name()]
  def list(server) do
    Agent.get(server, fn state ->
      MapSet.to_list(state.queued)
    end)
  end

  @doc """
  Checks if any handlers are queued.
  """
  @spec any_queued?() :: boolean()
  def any_queued?, do: any_queued?(__MODULE__)

  @doc """
  Checks if any handlers are queued on a specific server.
  """
  @spec any_queued?(GenServer.server()) :: boolean()
  def any_queued?(server) do
    Agent.get(server, fn state ->
      MapSet.size(state.queued) > 0
    end)
  end

  @doc """
  Checks if a specific handler is queued.
  """
  @spec queued?(handler_name()) :: boolean()
  def queued?(handler_name), do: queued?(__MODULE__, handler_name)

  @doc """
  Checks if a specific handler is queued on a specific server.
  """
  @spec queued?(GenServer.server(), handler_name()) :: boolean()
  def queued?(server, handler_name) do
    Agent.get(server, fn state ->
      MapSet.member?(state.queued, handler_name)
    end)
  end

  @doc """
  Clears all queued handlers without returning them.
  """
  @spec clear() :: :ok
  def clear, do: clear(__MODULE__)

  @doc """
  Clears handlers from a specific queue server.
  """
  @spec clear(GenServer.server()) :: :ok
  def clear(server) do
    Agent.update(server, fn state ->
      %{state | queued: MapSet.new()}
    end)
  end

  @doc """
  Returns the count of queued handlers.
  """
  @spec count() :: non_neg_integer()
  def count, do: count(__MODULE__)

  @doc """
  Returns the count from a specific server.
  """
  @spec count(GenServer.server()) :: non_neg_integer()
  def count(server) do
    Agent.get(server, fn state ->
      MapSet.size(state.queued)
    end)
  end
end
