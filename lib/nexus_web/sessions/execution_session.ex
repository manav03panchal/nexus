defmodule NexusWeb.ExecutionSession do
  @moduledoc """
  GenServer managing a single pipeline execution session.

  Handles running the Nexus executor and broadcasting status updates
  to subscribers via PubSub.
  """

  use GenServer, restart: :temporary

  alias Nexus.DSL.Parser
  alias Nexus.Executor.Pipeline
  alias Nexus.Notifications.Sender, as: NotificationSender
  alias Phoenix.PubSub

  defstruct [:id, :config_file, :task, :subscriber, :check_mode, :tags, :skip_tags, :status]

  @doc """
  Starts an execution session.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Stops an execution session.
  """
  def stop(session_id) when is_binary(session_id) do
    # Find the session by ID
    case find_session(session_id) do
      {:ok, pid} -> GenServer.stop(pid, :normal)
      :error -> :ok
    end
  end

  def stop(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal)
  end

  defp find_session(session_id) do
    NexusWeb.SessionSupervisor.list_sessions()
    |> Enum.find(fn pid ->
      try do
        GenServer.call(pid, :get_id) == session_id
      catch
        :exit, _ -> false
      end
    end)
    |> case do
      nil -> :error
      pid -> {:ok, pid}
    end
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      id: Keyword.fetch!(opts, :id),
      config_file: Keyword.fetch!(opts, :config_file),
      task: Keyword.get(opts, :task),
      subscriber: Keyword.get(opts, :subscriber),
      check_mode: Keyword.get(opts, :check_mode, false),
      tags: Keyword.get(opts, :tags, []),
      skip_tags: Keyword.get(opts, :skip_tags, []),
      status: :pending
    }

    # Start execution asynchronously
    send(self(), :start_execution)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_id, _from, state) do
    {:reply, state.id, state}
  end

  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_info(:start_execution, state) do
    state = %{state | status: :running}
    broadcast(state, {:execution_started, state.id})

    # Run execution in a separate process so we can handle messages
    parent = self()

    Task.start(fn ->
      result = run_execution(state, parent)
      send(parent, {:execution_result, result})
    end)

    {:noreply, state}
  end

  def handle_info({:execution_result, result}, state) do
    new_status =
      case result do
        :ok -> :completed
        {:error, _} -> :failed
      end

    state = %{state | status: new_status}
    broadcast(state, {:execution_complete, state.id})
    notify_subscriber(state, {:execution_complete, state.id})

    # Stop after a delay to allow final messages to be sent
    Process.send_after(self(), :stop, 1000)
    {:noreply, state}
  end

  def handle_info({:task_event, event}, state) do
    broadcast(state, event)
    notify_subscriber(state, event)
    {:noreply, state}
  end

  def handle_info({:log_line, line}, state) do
    # Only notify subscriber directly, don't broadcast to avoid duplicates
    notify_subscriber(state, {:log_line, line})
    {:noreply, state}
  end

  def handle_info(:stop, state) do
    {:stop, :normal, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp run_execution(state, parent) do
    case Parser.parse_file(state.config_file) do
      {:ok, config} ->
        # Set up telemetry handlers to capture events
        handler_id = attach_telemetry_handlers(parent)

        opts = build_execution_opts(state, parent)

        # Get all task names from config if no specific task specified
        tasks =
          if state.task do
            [String.to_atom(state.task)]
          else
            Map.keys(config.tasks)
          end

        started_at = DateTime.utc_now()
        result = Pipeline.run(config, tasks, opts)
        finished_at = DateTime.utc_now()

        # Detach handlers
        detach_telemetry_handlers(handler_id)

        # Send notifications
        send_notifications(config, result, started_at, finished_at, parent)

        case result do
          {:ok, _} -> :ok
          error -> error
        end

      {:error, reason} ->
        send(
          parent,
          {:log_line, %{type: :stderr, content: "Failed to parse config: #{inspect(reason)}"}}
        )

        {:error, reason}
    end
  end

  defp build_execution_opts(state, parent) do
    [
      check_mode: state.check_mode,
      tags: state.tags,
      skip_tags: state.skip_tags,
      output_callback: fn type, content ->
        send(parent, {:log_line, %{type: type, content: content, timestamp: DateTime.utc_now()}})
      end
    ]
  end

  defp attach_telemetry_handlers(parent) do
    handler_id = "nexus_web_session_#{:erlang.unique_integer()}"

    :telemetry.attach_many(
      handler_id,
      [
        [:nexus, :task, :start],
        [:nexus, :task, :stop],
        [:nexus, :command, :start],
        [:nexus, :command, :stop],
        [:nexus, :pipeline, :start],
        [:nexus, :pipeline, :stop]
      ],
      &__MODULE__.handle_telemetry_event/4,
      %{parent: parent}
    )

    handler_id
  end

  defp detach_telemetry_handlers(handler_id) do
    :telemetry.detach(handler_id)
  end

  @doc false
  def handle_telemetry_event([:nexus, :task, :start], _measurements, metadata, %{parent: parent}) do
    send(parent, {:task_event, {:task_started, metadata.task}})
  end

  def handle_telemetry_event([:nexus, :task, :stop], _measurements, metadata, %{parent: parent}) do
    result = if metadata[:error], do: {:error, metadata.error}, else: :ok
    send(parent, {:task_event, {:task_completed, metadata.task, result}})
  end

  def handle_telemetry_event([:nexus, :command, :start], _measurements, metadata, %{
        parent: parent
      }) do
    host = metadata[:host] || "local"
    cmd = truncate_command(metadata[:command] || "")
    content = "[#{host}] $ #{cmd}"
    send(parent, {:log_line, %{type: :info, content: content, timestamp: DateTime.utc_now()}})
  end

  def handle_telemetry_event([:nexus, :command, :stop], _measurements, metadata, %{parent: parent}) do
    host = metadata[:host] || "local"

    # Show the output
    if metadata[:output] && String.trim(metadata[:output]) != "" do
      # Split output into lines and send each
      metadata[:output]
      |> String.split("\n")
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.each(fn line ->
        send(
          parent,
          {:log_line,
           %{type: :stdout, content: "[#{host}]   #{line}", timestamp: DateTime.utc_now()}}
        )
      end)
    end

    # Show errors
    if metadata[:error] do
      send(
        parent,
        {:log_line,
         %{
           type: :stderr,
           content: "[#{host}] Error: #{inspect(metadata.error)}",
           timestamp: DateTime.utc_now()
         }}
      )
    end
  end

  def handle_telemetry_event(_event, _measurements, _metadata, _config) do
    :ok
  end

  defp truncate_command(cmd) when byte_size(cmd) > 80 do
    String.slice(cmd, 0, 77) <> "..."
  end

  defp truncate_command(cmd), do: cmd

  defp broadcast(state, event) do
    PubSub.broadcast(NexusWeb.PubSub, "execution:updates", event)
    PubSub.broadcast(NexusWeb.PubSub, "execution:#{state.id}", event)
  end

  defp notify_subscriber(%{subscriber: nil}, _event), do: :ok
  defp notify_subscriber(%{subscriber: pid}, event), do: send(pid, event)

  defp send_notifications(config, result, started_at, finished_at, parent) do
    if config.notifications != [] do
      status = if match?({:ok, _}, result), do: :success, else: :failure
      duration_ms = DateTime.diff(finished_at, started_at, :millisecond)

      notification_result = %{
        status: status,
        duration_ms: duration_ms,
        started_at: started_at,
        finished_at: finished_at,
        tasks: build_task_results(result)
      }

      send(
        parent,
        {:log_line,
         %{type: :info, content: "Sending notifications...", timestamp: DateTime.utc_now()}}
      )

      NotificationSender.send_all(config.notifications, notification_result)

      send(
        parent,
        {:log_line,
         %{type: :success, content: "Notifications sent", timestamp: DateTime.utc_now()}}
      )
    end
  end

  defp build_task_results({:ok, %{task_results: task_results}}) when is_list(task_results) do
    Enum.map(task_results, fn task_result ->
      %{
        name: task_result.task,
        status: if(task_result.status == :ok, do: :success, else: :failure),
        hosts: []
      }
    end)
  end

  defp build_task_results(_), do: []
end
