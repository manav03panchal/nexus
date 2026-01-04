defmodule NexusWeb.HistoryLive do
  @moduledoc """
  LiveView for viewing execution history.
  """

  use NexusWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:sessions, [])
      |> assign(:selected_session, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"session_id" => session_id}, _uri, socket) do
    {:noreply, assign(socket, :selected_session, session_id)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :selected_session, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-[#0a0a0a] text-gray-100">
      <header class="bg-[#111] border-b border-[#222] px-4 h-12 flex items-center shrink-0">
        <div class="flex items-center justify-between w-full">
          <div class="flex items-center gap-3">
            <span class="text-sm font-medium text-white">History</span>
            <span class="text-xs text-gray-500">
              Execution history (session only)
            </span>
          </div>
        </div>
      </header>

      <div class="flex-1 overflow-auto p-6">
        <div class="flex items-center justify-center h-full text-gray-500">
          <div class="text-center">
            <.icon name="hero-clock" class="h-12 w-12 mx-auto mb-3 opacity-50" />
            <p>Execution history</p>
            <p class="text-sm mt-1">History is stored in memory during this session</p>
            <p class="text-xs mt-3 text-gray-600">
              Run tasks from the Pipeline view to see history here
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
