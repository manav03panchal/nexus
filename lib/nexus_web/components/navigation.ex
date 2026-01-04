defmodule NexusWeb.Navigation do
  @moduledoc """
  Sidebar navigation component for the Nexus web dashboard.
  """

  use Phoenix.Component
  use NexusWeb, :verified_routes

  import NexusWeb.CoreComponents, only: [icon: 1]

  @doc """
  Renders the sidebar navigation.
  """
  attr :current_path, :string, required: true

  def sidebar(assigns) do
    ~H"""
    <nav
      id="sidebar"
      class="w-56 bg-[#0a0a0a] border-r border-[#222] flex flex-col h-full shrink-0 transition-all duration-200"
    >
      <!-- Logo & Toggle -->
      <div class="h-12 flex items-center justify-between border-b border-[#222] px-3">
        <a href={~p"/"} class="sidebar-logo">
          <img src="/assets/nexus-logo.png" class="h-5" alt="Nexus" />
        </a>
        <button
          type="button"
          id="sidebar-toggle"
          class="p-1.5 text-gray-500 hover:text-white hover:bg-[#1a1a1a] transition-colors"
          title="Toggle sidebar"
        >
          <.icon name="hero-chevron-left" class="chevron-left h-4 w-4" />
          <.icon name="hero-chevron-right" class="chevron-right h-4 w-4" />
        </button>
      </div>
      
    <!-- Navigation Items -->
      <div class="flex-1 py-3 space-y-1">
        <.nav_item path="/" icon="hero-squares-2x2" label="Pipeline" current={@current_path} />
        <.nav_item path="/hosts" icon="hero-server-stack" label="Hosts" current={@current_path} />
        <.nav_item
          path="/preflight"
          icon="hero-clipboard-document-check"
          label="Preflight"
          current={@current_path}
        />
        <.nav_item path="/secrets" icon="hero-key" label="Secrets" current={@current_path} />
        <.nav_item path="/history" icon="hero-clock" label="History" current={@current_path} />
        <.nav_item path="/config" icon="hero-cog-6-tooth" label="Config" current={@current_path} />
      </div>
      
    <!-- Footer -->
      <div class="h-12 flex items-center border-t border-[#222] px-3 text-xs text-gray-500">
        <span class="sidebar-version">v{Application.spec(:nexus, :vsn) |> to_string()}</span>
      </div>
    </nav>
    """
  end

  @doc false
  attr :path, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :current, :string, required: true

  defp nav_item(assigns) do
    active = active?(assigns.path, assigns.current)
    assigns = assign(assigns, :active, active)

    ~H"""
    <a
      href={@path}
      title={@label}
      class={[
        "sidebar-nav-item flex items-center gap-3 px-3 py-2 mx-2 text-sm font-medium transition-colors",
        @active && "bg-[#00e599]/10 text-[#00e599]",
        !@active && "text-gray-400 hover:text-white hover:bg-[#111]"
      ]}
    >
      <.icon name={@icon} class="h-4 w-4 shrink-0" />
      <span class="sidebar-label">{@label}</span>
    </a>
    """
  end

  defp active?("/", current), do: current == "/" or String.starts_with?(current, "/task/")
  defp active?(path, current), do: String.starts_with?(current, path)
end
