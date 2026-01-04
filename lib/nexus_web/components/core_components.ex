defmodule NexusWeb.CoreComponents do
  @moduledoc """
  Core UI components for the Nexus web dashboard.

  Provides reusable components for the dashboard interface including
  flash messages, buttons, icons, and status indicators.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.
  """
  attr(:id, :string, doc: "the optional id of flash container")
  attr(:flash, :map, default: %{}, doc: "the map of flash messages to display")
  attr(:kind, :atom, values: [:info, :error], doc: "used for styling and icon")
  attr(:title, :string, default: nil)
  attr(:rest, :global, include: ~w(phx-connected phx-disconnected hidden))

  slot(:inner_block, doc: "the optional inner block that renders the flash message")

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed top-20 left-1/2 -translate-x-1/2 z-50 w-80 p-4 shadow-lg border",
        @kind == :info && "bg-[#0a2a1f] text-[#00e599] border-[#00e599]/50",
        @kind == :error && "bg-red-950 text-red-200 border-red-500/50"
      ]}
    >
      <p :if={@title} class="flex items-center gap-1.5 text-sm font-semibold leading-6">
        <.icon :if={@kind == :info} name="hero-information-circle-mini" class="h-4 w-4" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle-mini" class="h-4 w-4" />
        {@title}
      </p>
      <p class="mt-1 text-sm leading-5">{msg}</p>
      <button type="button" class="absolute top-2 right-2 group" aria-label="close">
        <.icon name="hero-x-mark-solid" class="h-5 w-5 opacity-60 group-hover:opacity-100" />
      </button>
    </div>
    """
  end

  @doc false
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :rest, :global, include: ~w(phx-connected phx-disconnected hidden)
  slot :inner_block

  def connection_flash(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed top-4 right-4 z-50 w-80 p-4 shadow-lg border bg-red-950 text-red-200 border-red-500/50"
      {@rest}
    >
      <p class="flex items-center gap-1.5 text-sm font-semibold leading-6">
        <.icon name="hero-exclamation-circle-mini" class="h-4 w-4" />
        {@title}
      </p>
      <p class="mt-1 text-sm leading-5">{render_slot(@inner_block)}</p>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles.
  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")

  def flash_group(assigns) do
    ~H"""
    <.flash kind={:info} title="Success!" flash={@flash} />
    <.flash kind={:error} title="Error!" flash={@flash} />
    <.connection_flash
      id="client-error"
      title="Connection Lost"
      phx-disconnected={show(".phx-client-error #client-error")}
      phx-connected={hide("#client-error")}
      hidden
    >
      Attempting to reconnect...
    </.connection_flash>
    <.connection_flash
      id="server-error"
      title="Server Error"
      phx-disconnected={show(".phx-server-error #server-error")}
      phx-connected={hide("#server-error")}
      hidden
    >
      Hang in there while we get back on track...
    </.connection_flash>
    """
  end

  @doc """
  Renders a button.
  """
  attr(:type, :string, default: "button")
  attr(:class, :string, default: nil)
  attr(:variant, :atom, default: :primary, values: [:primary, :secondary, :danger, :ghost])
  attr(:size, :atom, default: :md, values: [:sm, :md, :lg])
  attr(:disabled, :boolean, default: false)
  attr(:rest, :global, include: ~w(form name value phx-click phx-disable-with))

  slot(:inner_block, required: true)

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      disabled={@disabled}
      class={[
        "inline-flex items-center justify-center font-semibold transition-all",
        "focus:outline-none focus:ring-1 focus:ring-[#00e599] focus:ring-offset-1 focus:ring-offset-[#0a0a0a]",
        "disabled:opacity-50 disabled:cursor-not-allowed",
        size_class(@size),
        variant_class(@variant),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp size_class(:sm), do: "px-2.5 py-1.5 text-xs gap-1.5"
  defp size_class(:md), do: "px-4 py-2 text-sm gap-2"
  defp size_class(:lg), do: "px-6 py-3 text-base gap-2"

  defp variant_class(:primary),
    do: "bg-[#00e599] text-black hover:bg-[#00cc88] hover:shadow-[0_0_20px_rgba(0,229,153,0.3)]"

  defp variant_class(:secondary),
    do: "bg-[#1a1a1a] text-gray-200 border border-[#333] hover:bg-[#222] hover:border-[#444]"

  defp variant_class(:danger), do: "bg-red-600 text-white hover:bg-red-500"

  defp variant_class(:ghost),
    do: "bg-transparent text-gray-400 hover:text-white hover:bg-[#1a1a1a]"

  @doc """
  Renders a status badge.
  """
  attr(:status, :atom, required: true, values: [:pending, :running, :success, :failed, :skipped])
  attr(:class, :string, default: nil)

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 px-2 py-1 text-xs font-medium border",
      status_badge_class(@status),
      @class
    ]}>
      <span class={["w-1.5 h-1.5", status_dot_class(@status)]}></span>
      {status_label(@status)}
    </span>
    """
  end

  defp status_badge_class(:pending), do: "bg-[#1a1a1a] text-gray-400 border-[#333]"
  defp status_badge_class(:running), do: "bg-[#00e599]/10 text-[#00e599] border-[#00e599]/50"
  defp status_badge_class(:success), do: "bg-[#00e599]/10 text-[#00e599] border-[#00e599]/50"
  defp status_badge_class(:failed), do: "bg-red-950 text-red-400 border-red-500/50"
  defp status_badge_class(:skipped), do: "bg-yellow-950 text-yellow-400 border-yellow-500/50"

  defp status_dot_class(:pending), do: "bg-gray-500"
  defp status_dot_class(:running), do: "bg-[#00e599] animate-pulse"
  defp status_dot_class(:success), do: "bg-[#00e599]"
  defp status_dot_class(:failed), do: "bg-red-400"
  defp status_dot_class(:skipped), do: "bg-yellow-400"

  defp status_label(:pending), do: "Pending"
  defp status_label(:running), do: "Running"
  defp status_label(:success), do: "Success"
  defp status_label(:failed), do: "Failed"
  defp status_label(:skipped), do: "Skipped"

  @doc """
  Renders an icon from heroicons.
  """
  attr(:name, :string, required: true)
  attr(:class, :string, default: nil)

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders a spinner for loading states.
  """
  attr(:class, :string, default: "h-5 w-5")

  def spinner(assigns) do
    ~H"""
    <svg
      class={["animate-spin", @class]}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
    >
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4">
      </circle>
      <path
        class="opacity-75"
        fill="currentColor"
        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
      >
      </path>
    </svg>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 200,
      transition: {"transition-opacity ease-out duration-200", "opacity-0", "opacity-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition: {"transition-opacity ease-in duration-200", "opacity-100", "opacity-0"}
    )
  end
end
