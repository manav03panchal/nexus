defmodule NexusWeb.PreflightLive do
  @moduledoc """
  LiveView for running preflight checks before execution.
  """

  use NexusWeb, :live_view

  alias Nexus.DSL.Parser

  @impl true
  def mount(_params, _session, socket) do
    config_file = Application.get_env(:nexus, :web_config_file)

    socket =
      socket
      |> assign(:config_file, config_file)
      |> assign(:check_status, :idle)
      |> assign(:check_results, [])
      |> assign(:execution_plan, [])
      |> assign(:overall_status, nil)
      |> assign(:duration_ms, 0)

    {:ok, socket}
  end

  @impl true
  def handle_event("run_checks", _params, socket) do
    socket = assign(socket, :check_status, :running)
    send(self(), :run_preflight)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:run_preflight, socket) do
    start_time = System.monotonic_time(:millisecond)

    results = run_preflight_checks(socket.assigns.config_file)

    duration = System.monotonic_time(:millisecond) - start_time
    overall = if Enum.all?(results, &(&1.status == :ok)), do: :ok, else: :error

    {:noreply,
     socket
     |> assign(:check_status, :completed)
     |> assign(:check_results, results)
     |> assign(:overall_status, overall)
     |> assign(:duration_ms, duration)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp run_preflight_checks(config_file) do
    checks = [
      {:config, "Configuration", &check_config/1},
      {:hosts, "Host Definitions", &check_hosts/1},
      {:tasks, "Task Definitions", &check_tasks/1}
    ]

    Enum.map(checks, fn {id, name, check_fn} ->
      case check_fn.(config_file) do
        :ok -> %{id: id, name: name, status: :ok, message: "Passed"}
        {:ok, msg} -> %{id: id, name: name, status: :ok, message: msg}
        {:error, msg} -> %{id: id, name: name, status: :error, message: msg}
      end
    end)
  end

  defp check_config(config_file) do
    case Parser.parse_file(config_file) do
      {:ok, _} -> {:ok, "Configuration parsed successfully"}
      {:error, reason} -> {:error, "Parse error: #{inspect(reason)}"}
    end
  end

  defp check_hosts(config_file) do
    case Parser.parse_file(config_file) do
      {:ok, config} ->
        count = map_size(config.hosts)
        {:ok, "#{count} host(s) defined"}

      {:error, _} ->
        {:error, "Could not check hosts"}
    end
  end

  defp check_tasks(config_file) do
    case Parser.parse_file(config_file) do
      {:ok, config} ->
        count = map_size(config.tasks)
        {:ok, "#{count} task(s) defined"}

      {:error, _} ->
        {:error, "Could not check tasks"}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-[#0a0a0a] text-gray-100">
      <header class="bg-[#111] border-b border-[#222] px-6 py-3 shrink-0">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <span class="text-sm font-medium text-white">Preflight Checks</span>
          </div>
          <.button
            phx-click="run_checks"
            variant={:primary}
            size={:sm}
            disabled={@check_status == :running}
          >
            <%= if @check_status == :running do %>
              <.spinner class="h-4 w-4 mr-1" /> Running...
            <% else %>
              <.icon name="hero-play" class="h-4 w-4 mr-1" /> Run Checks
            <% end %>
          </.button>
        </div>
      </header>

      <div class="flex-1 overflow-auto p-6">
        <%= if @check_status == :idle do %>
          <div class="flex items-center justify-center h-full text-gray-500">
            <div class="text-center">
              <.icon name="hero-clipboard-document-check" class="h-12 w-12 mx-auto mb-3 opacity-50" />
              <p>Run preflight checks before executing</p>
              <p class="text-sm mt-1">Validates configuration, hosts, and tasks</p>
            </div>
          </div>
        <% else %>
          <!-- Overall Status -->
          <%= if @overall_status do %>
            <div class={[
              "mb-6 p-4 border",
              @overall_status == :ok && "bg-[#00e599]/10 border-[#00e599]/50",
              @overall_status == :error && "bg-red-950 border-red-500/50"
            ]}>
              <div class="flex items-center gap-2">
                <%= if @overall_status == :ok do %>
                  <.icon name="hero-check-circle" class="h-5 w-5 text-[#00e599]" />
                  <span class="text-[#00e599] font-medium">All checks passed</span>
                <% else %>
                  <.icon name="hero-x-circle" class="h-5 w-5 text-red-400" />
                  <span class="text-red-400 font-medium">Some checks failed</span>
                <% end %>
                <span class="text-gray-500 text-sm ml-auto">{@duration_ms}ms</span>
              </div>
            </div>
          <% end %>
          
    <!-- Check Results -->
          <div class="space-y-3">
            <%= for result <- @check_results do %>
              <div class={[
                "p-4 border",
                result.status == :ok && "bg-[#111] border-[#222]",
                result.status == :error && "bg-red-950/50 border-red-500/50"
              ]}>
                <div class="flex items-center gap-3">
                  <%= if result.status == :ok do %>
                    <.icon name="hero-check-circle" class="h-5 w-5 text-[#00e599]" />
                  <% else %>
                    <.icon name="hero-x-circle" class="h-5 w-5 text-red-400" />
                  <% end %>
                  <div>
                    <div class="font-medium text-white">{result.name}</div>
                    <div class="text-sm text-gray-400">{result.message}</div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
