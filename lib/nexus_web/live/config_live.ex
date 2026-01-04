defmodule NexusWeb.ConfigLive do
  @moduledoc """
  LiveView for viewing configuration details.
  """

  use NexusWeb, :live_view

  alias Nexus.DSL.Parser

  @impl true
  def mount(_params, _session, socket) do
    config_file = Application.get_env(:nexus, :web_config_file)

    socket =
      socket
      |> assign(:config_file, config_file)
      |> assign(:config, nil)
      |> assign(:error, nil)

    if connected?(socket) do
      send(self(), :load_config)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_config, socket) do
    case Parser.parse_file(socket.assigns.config_file) do
      {:ok, config} ->
        {:noreply, assign(socket, :config, config)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Failed to load: #{inspect(reason)}")}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("reload_config", _params, socket) do
    send(self(), :load_config)
    {:noreply, put_flash(socket, :info, "Configuration reloaded")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-[#0a0a0a] text-gray-100">
      <header class="bg-[#111] border-b border-[#222] px-4 h-12 flex items-center shrink-0">
        <div class="flex items-center justify-between w-full">
          <div class="flex items-center gap-3">
            <span class="text-sm font-medium text-white">Config</span>
            <span class="text-xs text-gray-500 font-mono">
              {if @config_file, do: Path.basename(@config_file), else: "No config"}
            </span>
          </div>
          <.button phx-click="reload_config" variant={:ghost} size={:sm}>
            <.icon name="hero-arrow-path" class="h-4 w-4 mr-1" /> Reload
          </.button>
        </div>
      </header>

      <div class="flex-1 overflow-auto p-6">
        <%= if @error do %>
          <div class="bg-red-900/50 border border-red-500 p-4 mb-4">
            <p class="text-red-200 text-sm">{@error}</p>
          </div>
        <% end %>

        <%= if @config do %>
          <div class="space-y-6">
            <!-- Global Settings -->
            <div class="bg-[#111] border border-[#222] p-4">
              <h3 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-3">
                Global Settings
              </h3>
              <div class="grid grid-cols-2 gap-4 text-sm">
                <div>
                  <span class="text-gray-500">Default User</span>
                  <span class="ml-2 font-mono text-white">
                    {@config.default_user || "system default"}
                  </span>
                </div>
                <div>
                  <span class="text-gray-500">Default Port</span>
                  <span class="ml-2 font-mono text-white">{@config.default_port}</span>
                </div>
                <div>
                  <span class="text-gray-500">Connect Timeout</span>
                  <span class="ml-2 font-mono text-white">{@config.connect_timeout}ms</span>
                </div>
                <div>
                  <span class="text-gray-500">Command Timeout</span>
                  <span class="ml-2 font-mono text-white">{@config.command_timeout}ms</span>
                </div>
                <div>
                  <span class="text-gray-500">Max Connections</span>
                  <span class="ml-2 font-mono text-white">{@config.max_connections}</span>
                </div>
                <div>
                  <span class="text-gray-500">Continue on Error</span>
                  <span class="ml-2 font-mono text-white">{@config.continue_on_error}</span>
                </div>
              </div>
            </div>
            
    <!-- Summary -->
            <div class="grid grid-cols-4 gap-4">
              <div class="bg-[#111] border border-[#222] p-4 text-center">
                <div class="text-2xl font-bold text-[#00e599]">{map_size(@config.tasks)}</div>
                <div class="text-xs text-gray-500 mt-1">Tasks</div>
              </div>
              <div class="bg-[#111] border border-[#222] p-4 text-center">
                <div class="text-2xl font-bold text-[#00e599]">{map_size(@config.hosts)}</div>
                <div class="text-xs text-gray-500 mt-1">Hosts</div>
              </div>
              <div class="bg-[#111] border border-[#222] p-4 text-center">
                <div class="text-2xl font-bold text-[#00e599]">{map_size(@config.groups)}</div>
                <div class="text-xs text-gray-500 mt-1">Groups</div>
              </div>
              <div class="bg-[#111] border border-[#222] p-4 text-center">
                <div class="text-2xl font-bold text-[#00e599]">{map_size(@config.handlers)}</div>
                <div class="text-xs text-gray-500 mt-1">Handlers</div>
              </div>
            </div>
            
    <!-- Handlers -->
            <%= if map_size(@config.handlers) > 0 do %>
              <div class="bg-[#111] border border-[#222] p-4">
                <h3 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-3">
                  Handlers
                </h3>
                <div class="space-y-2">
                  <%= for {name, handler} <- @config.handlers do %>
                    <div class="flex items-center justify-between p-2 bg-[#0a0a0a] border border-[#222]">
                      <span class="font-mono text-sm text-white">{name}</span>
                      <span class="text-xs text-gray-500">
                        {length(handler.commands)} command(s)
                      </span>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
            
    <!-- Notifications -->
            <%= if length(@config.notifications) > 0 do %>
              <div class="bg-[#111] border border-[#222] p-4">
                <h3 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-3">
                  Notifications
                </h3>
                <div class="space-y-2">
                  <%= for notif <- @config.notifications do %>
                    <div class="p-2 bg-[#0a0a0a] border border-[#222]">
                      <div class="flex items-center gap-2">
                        <span class="px-2 py-0.5 bg-[#1a1a1a] text-xs text-gray-300">
                          {notif.template}
                        </span>
                        <span class="text-xs text-gray-500">
                          on: {Enum.join(notif.on, ", ")}
                        </span>
                      </div>
                      <div class="font-mono text-xs text-gray-400 mt-1 truncate">
                        {mask_url(notif.url)}
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
            
    <!-- Config File Path -->
            <div class="text-xs text-gray-500">
              Config file: <span class="font-mono">{@config_file}</span>
            </div>
          </div>
        <% else %>
          <div class="flex items-center justify-center h-full">
            <.spinner class="h-8 w-8 text-[#00e599]" />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp mask_url(url) do
    uri = URI.parse(url)
    "#{uri.scheme}://#{uri.host}/..."
  end
end
