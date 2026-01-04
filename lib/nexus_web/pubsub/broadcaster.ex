defmodule NexusWeb.Broadcaster do
  @moduledoc """
  Bridges Nexus telemetry events to Phoenix PubSub.

  This module attaches to Nexus telemetry events and broadcasts
  them to PubSub topics for LiveView consumption.
  """

  use GenServer

  alias Phoenix.PubSub

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    attach_handlers()
    {:ok, %{}}
  end

  defp attach_handlers do
    # Only attach to pipeline and task events here.
    # Command events are handled by ExecutionSession which formats them as log lines.
    :telemetry.attach_many(
      "nexus_web_broadcaster",
      [
        [:nexus, :pipeline, :start],
        [:nexus, :pipeline, :stop],
        [:nexus, :task, :start],
        [:nexus, :task, :stop]
      ],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  @doc false
  def handle_event([:nexus, :pipeline, :start], _measurements, metadata, _config) do
    broadcast(:pipeline_started, %{
      tasks: metadata[:tasks] || []
    })
  end

  def handle_event([:nexus, :pipeline, :stop], measurements, metadata, _config) do
    broadcast(:pipeline_completed, %{
      duration_ms: measurements[:duration] || 0,
      success: is_nil(metadata[:error])
    })
  end

  def handle_event([:nexus, :task, :start], _measurements, metadata, _config) do
    broadcast(:task_started, %{
      task: metadata[:task],
      host: metadata[:host]
    })
  end

  def handle_event([:nexus, :task, :stop], measurements, metadata, _config) do
    broadcast(:task_completed, %{
      task: metadata[:task],
      host: metadata[:host],
      duration_ms: measurements[:duration] || 0,
      success: is_nil(metadata[:error]),
      error: metadata[:error]
    })
  end

  defp broadcast(event_type, payload) do
    PubSub.broadcast(
      NexusWeb.PubSub,
      "execution:updates",
      {event_type, payload}
    )
  end
end
