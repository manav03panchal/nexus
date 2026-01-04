defmodule NexusWeb.HostsLive do
  @moduledoc """
  LiveView for managing and monitoring hosts.

  Displays host inventory with real-time connection status
  and provides connectivity testing functionality.
  """

  use NexusWeb, :live_view

  alias Nexus.DSL.Parser
  alias NexusWeb.HostMonitor
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    config_file = Application.get_env(:nexus, :web_config_file)

    socket =
      socket
      |> assign(:config_file, config_file)
      |> assign(:hosts, %{})
      |> assign(:groups, %{})
      |> assign(:host_statuses, %{})
      |> assign(:selected_host, nil)
      |> assign(:error, nil)

    if connected?(socket) do
      PubSub.subscribe(NexusWeb.PubSub, "hosts:status")
      send(self(), :load_config)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"host_name" => host_name}, _uri, socket) do
    host_atom = String.to_atom(host_name)
    {:noreply, assign(socket, :selected_host, host_atom)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :selected_host, nil)}
  end

  @impl true
  def handle_info(:load_config, socket) do
    case Parser.parse_file(socket.assigns.config_file) do
      {:ok, config} ->
        # Update host monitor with hosts
        HostMonitor.update_hosts(config.hosts)

        # Get current statuses
        statuses =
          HostMonitor.get_all_statuses()
          |> Enum.map(fn s -> {s.name, s.status} end)
          |> Map.new()

        {:noreply,
         socket
         |> assign(:hosts, config.hosts)
         |> assign(:groups, config.groups)
         |> assign(:host_statuses, statuses)
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Failed to load config: #{inspect(reason)}")}
    end
  end

  def handle_info({:host_status, host_name, status}, socket) do
    host_statuses = Map.put(socket.assigns.host_statuses, host_name, status)
    {:noreply, assign(socket, :host_statuses, host_statuses)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("check_host", %{"host" => host_name}, socket) do
    HostMonitor.check_host(String.to_atom(host_name))
    {:noreply, socket}
  end

  def handle_event("check_all", _params, socket) do
    HostMonitor.check_all()
    {:noreply, put_flash(socket, :info, "Checking all hosts...")}
  end

  def handle_event("select_host", %{"host" => host_name}, socket) do
    {:noreply, push_patch(socket, to: "/hosts/#{host_name}")}
  end

  def handle_event("close_panel", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_host, nil)
     |> push_patch(to: "/hosts")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-[#0a0a0a] text-gray-100">
      <!-- Header -->
      <header class="bg-[#111] border-b border-[#222] px-6 py-3 shrink-0">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <span class="text-sm font-medium text-white">Hosts</span>
            <span class="text-xs text-gray-500">
              {map_size(@hosts)} host(s) configured
            </span>
          </div>
          <div class="flex items-center gap-3">
            <.button phx-click="check_all" variant={:primary} size={:sm}>
              <.icon name="hero-signal" class="h-4 w-4 mr-1" /> Check All
            </.button>
          </div>
        </div>
      </header>
      
    <!-- Main Content -->
      <div class="flex-1 flex overflow-hidden">
        <!-- Host List -->
        <div class="flex-1 overflow-auto p-6">
          <%= if @error do %>
            <div class="bg-red-900/50 border border-red-500 p-4 mb-4">
              <p class="text-red-200 text-sm">{@error}</p>
            </div>
          <% end %>

          <%= if map_size(@hosts) == 0 do %>
            <div class="flex items-center justify-center h-full text-gray-500">
              <div class="text-center">
                <.icon name="hero-server-stack" class="h-12 w-12 mx-auto mb-3 opacity-50" />
                <p>No hosts configured</p>
                <p class="text-sm mt-1">Add hosts to your config file to see them here</p>
              </div>
            </div>
          <% else %>
            <!-- Groups Section -->
            <%= if map_size(@groups) > 0 do %>
              <div class="mb-6">
                <h3 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-3">
                  Groups
                </h3>
                <div class="flex flex-wrap gap-2">
                  <%= for {name, group} <- @groups do %>
                    <div class="px-3 py-2 bg-[#111] border border-[#222]">
                      <span class="text-sm font-medium text-white">{name}</span>
                      <span class="ml-2 text-xs text-gray-500">
                        {length(group.hosts)} host(s)
                      </span>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
            
    <!-- Hosts Grid -->
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for {name, host} <- @hosts do %>
                <.host_card
                  name={name}
                  host={host}
                  status={Map.get(@host_statuses, name, :unknown)}
                  selected={@selected_host == name}
                />
              <% end %>
            </div>
          <% end %>
        </div>
        
    <!-- Host Detail Panel -->
        <%= if @selected_host && Map.has_key?(@hosts, @selected_host) do %>
          <.host_panel
            name={@selected_host}
            host={Map.get(@hosts, @selected_host)}
            status={Map.get(@host_statuses, @selected_host, :unknown)}
            groups={@groups}
          />
        <% end %>
      </div>
    </div>
    """
  end

  attr :name, :atom, required: true
  attr :host, :map, required: true
  attr :status, :atom, required: true
  attr :selected, :boolean, required: true

  defp host_card(assigns) do
    ~H"""
    <div
      class={[
        "p-4 bg-[#111] border cursor-pointer transition-all hover:border-[#00e599]/50",
        @selected && "border-[#00e599]",
        !@selected && "border-[#222]"
      ]}
      phx-click="select_host"
      phx-value-host={@name}
    >
      <div class="flex items-start justify-between mb-3">
        <div class="flex items-center gap-2">
          <.icon name="hero-server" class="h-5 w-5 text-gray-400" />
          <span class="font-medium text-white">{@name}</span>
        </div>
        <.host_status_badge status={@status} />
      </div>

      <div class="space-y-1 text-sm">
        <div class="flex items-center gap-2 text-gray-400">
          <span class="text-gray-500">Host:</span>
          <span class="font-mono">{@host.hostname}</span>
        </div>
        <div class="flex items-center gap-2 text-gray-400">
          <span class="text-gray-500">User:</span>
          <span class="font-mono">{@host.user || "default"}</span>
        </div>
        <div class="flex items-center gap-2 text-gray-400">
          <span class="text-gray-500">Port:</span>
          <span class="font-mono">{@host.port}</span>
        </div>
      </div>

      <div class="mt-3 pt-3 border-t border-[#222]">
        <button
          type="button"
          class="text-xs text-[#00e599] hover:underline"
          phx-click="check_host"
          phx-value-host={@name}
        >
          Test Connection
        </button>
      </div>
    </div>
    """
  end

  attr :name, :atom, required: true
  attr :host, :map, required: true
  attr :status, :atom, required: true
  attr :groups, :map, required: true

  defp host_panel(assigns) do
    # Find groups this host belongs to
    member_groups =
      Enum.filter(assigns.groups, fn {_name, group} ->
        assigns.name in group.hosts
      end)
      |> Enum.map(fn {name, _} -> name end)

    assigns = assign(assigns, :member_groups, member_groups)

    ~H"""
    <div class="w-96 bg-[#111] border-l border-[#222] flex flex-col h-full shrink-0">
      <div class="flex items-center justify-between px-4 py-3 border-b border-[#222]">
        <div class="flex items-center gap-3">
          <h2 class="font-semibold text-white">{@name}</h2>
          <.host_status_badge status={@status} />
        </div>
        <button
          type="button"
          phx-click="close_panel"
          class="text-gray-400 hover:text-white transition-colors"
        >
          <.icon name="hero-x-mark" class="h-5 w-5" />
        </button>
      </div>

      <div class="flex-1 overflow-auto p-4 space-y-6">
        <!-- Connection Info -->
        <div>
          <h3 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-2">
            Connection
          </h3>
          <div class="space-y-2 text-sm">
            <div class="flex justify-between">
              <span class="text-gray-500">Hostname</span>
              <span class="font-mono text-white">{@host.hostname}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-500">User</span>
              <span class="font-mono text-white">{@host.user || "default"}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-500">Port</span>
              <span class="font-mono text-white">{@host.port}</span>
            </div>
            <%= if @host.identity do %>
              <div class="flex justify-between">
                <span class="text-gray-500">Identity</span>
                <span class="font-mono text-white text-xs truncate max-w-[200px]">
                  {@host.identity}
                </span>
              </div>
            <% end %>
            <%= if @host.proxy do %>
              <div class="flex justify-between">
                <span class="text-gray-500">Proxy</span>
                <span class="font-mono text-[#00e599]">{@host.proxy}</span>
              </div>
            <% end %>
          </div>
        </div>
        
    <!-- Privilege Escalation -->
        <%= if @host.become do %>
          <div>
            <h3 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-2">
              Privilege Escalation
            </h3>
            <div class="space-y-2 text-sm">
              <div class="flex justify-between">
                <span class="text-gray-500">Become</span>
                <span class="text-[#00e599]">Enabled</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-500">Become User</span>
                <span class="font-mono text-white">{@host.become_user}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-500">Method</span>
                <span class="font-mono text-white">{@host.become_method}</span>
              </div>
            </div>
          </div>
        <% end %>
        
    <!-- Groups -->
        <div>
          <h3 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-2">
            Groups
          </h3>
          <div class="flex flex-wrap gap-1">
            <%= if Enum.empty?(@member_groups) do %>
              <span class="text-sm text-gray-500 italic">No groups</span>
            <% else %>
              <%= for group <- @member_groups do %>
                <span class="px-2 py-0.5 bg-[#1a1a1a] border border-[#333] text-xs text-gray-300">
                  {group}
                </span>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
      
    <!-- Actions -->
      <div class="p-4 border-t border-[#222]">
        <.button
          phx-click="check_host"
          phx-value-host={@name}
          variant={:primary}
          class="w-full"
        >
          <.icon name="hero-signal" class="h-4 w-4 mr-2" /> Test Connection
        </.button>
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp host_status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 px-2 py-0.5 text-xs font-medium border",
      status_class(@status)
    ]}>
      <span class={["w-1.5 h-1.5 rounded-full", dot_class(@status)]}></span>
      {status_label(@status)}
    </span>
    """
  end

  defp status_class(:reachable), do: "bg-[#00e599]/10 text-[#00e599] border-[#00e599]/50"
  defp status_class(:checking), do: "bg-blue-500/10 text-blue-400 border-blue-500/50"
  defp status_class(:tcp_failed), do: "bg-red-950 text-red-400 border-red-500/50"
  defp status_class(:ssh_auth_failed), do: "bg-orange-950 text-orange-400 border-orange-500/50"
  defp status_class(:ssh_timeout), do: "bg-yellow-950 text-yellow-400 border-yellow-500/50"
  defp status_class(:command_failed), do: "bg-red-950 text-red-400 border-red-500/50"
  defp status_class(_), do: "bg-[#1a1a1a] text-gray-400 border-[#333]"

  defp dot_class(:reachable), do: "bg-[#00e599]"
  defp dot_class(:checking), do: "bg-blue-400 animate-pulse"
  defp dot_class(:tcp_failed), do: "bg-red-400"
  defp dot_class(:ssh_auth_failed), do: "bg-orange-400"
  defp dot_class(:ssh_timeout), do: "bg-yellow-400"
  defp dot_class(:command_failed), do: "bg-red-400"
  defp dot_class(_), do: "bg-gray-500"

  defp status_label(:reachable), do: "Reachable"
  defp status_label(:checking), do: "Checking..."
  defp status_label(:tcp_failed), do: "TCP Failed"
  defp status_label(:ssh_auth_failed), do: "Auth Failed"
  defp status_label(:ssh_timeout), do: "Timeout"
  defp status_label(:command_failed), do: "Cmd Failed"
  defp status_label(_), do: "Unknown"
end
