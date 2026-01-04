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
    <nav class="w-56 bg-[#0a0a0a] border-r border-[#222] flex flex-col h-full shrink-0">
      <!-- Logo -->
      <div class="px-4 py-4 border-b border-[#222]">
        <a href={~p"/"} class="flex items-center gap-2">
          <img src="/assets/nexus-logo.png" class="h-5" alt="Nexus" />
        </a>
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
      <div class="px-4 py-3 border-t border-[#222] text-xs text-gray-500">
        v{Application.spec(:nexus, :vsn) |> to_string()}
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
    active = is_active?(assigns.path, assigns.current)
    assigns = assign(assigns, :active, active)

    ~H"""
    <a
      href={@path}
      class={[
        "flex items-center gap-3 px-4 py-2 mx-2 text-sm font-medium transition-colors",
        @active && "bg-[#00e599]/10 text-[#00e599] border-l-2 border-[#00e599] -ml-[2px] pl-[18px]",
        !@active && "text-gray-400 hover:text-white hover:bg-[#111]"
      ]}
    >
      <.icon name={@icon} class="h-4 w-4 shrink-0" />
      <span>{@label}</span>
    </a>
    """
  end

  defp is_active?("/", current), do: current == "/" or String.starts_with?(current, "/task/")
  defp is_active?(path, current), do: String.starts_with?(current, path)
end
