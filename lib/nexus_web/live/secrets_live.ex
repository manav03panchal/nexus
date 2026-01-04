defmodule NexusWeb.SecretsLive do
  @moduledoc """
  LiveView for managing secrets vault.
  """

  use NexusWeb, :live_view

  alias Nexus.Secrets.Vault

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:secrets, [])
      |> assign(:vault_status, :checking)
      |> assign(:adding_secret, false)
      |> assign(:form, to_form(%{"name" => "", "value" => ""}))
      |> assign(:error, nil)

    if connected?(socket) do
      send(self(), :load_secrets)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_secrets, socket) do
    case load_vault() do
      {:ok, secrets} ->
        {:noreply,
         socket
         |> assign(:secrets, secrets)
         |> assign(:vault_status, :ready)}

      {:error, :not_initialized} ->
        {:noreply, assign(socket, :vault_status, :not_initialized)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:vault_status, :error)
         |> assign(:error, "Failed to load vault: #{inspect(reason)}")}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp load_vault do
    if Vault.exists?() do
      case Vault.list() do
        {:ok, secrets} -> {:ok, secrets}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :not_initialized}
    end
  end

  @impl true
  def handle_event("show_add_form", _params, socket) do
    {:noreply, assign(socket, :adding_secret, true)}
  end

  def handle_event("cancel_add", _params, socket) do
    {:noreply,
     socket
     |> assign(:adding_secret, false)
     |> assign(:form, to_form(%{"name" => "", "value" => ""}))}
  end

  def handle_event("save_secret", %{"name" => name, "value" => value}, socket) do
    if String.trim(name) == "" or String.trim(value) == "" do
      {:noreply, put_flash(socket, :error, "Name and value are required")}
    else
      case Vault.set(name, value) do
        :ok ->
          send(self(), :load_secrets)

          {:noreply,
           socket
           |> assign(:adding_secret, false)
           |> assign(:form, to_form(%{"name" => "", "value" => ""}))
           |> put_flash(:info, "Secret '#{name}' saved")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to save: #{inspect(reason)}")}
      end
    end
  end

  def handle_event("delete_secret", %{"name" => name}, socket) do
    case Vault.delete(name) do
      :ok ->
        send(self(), :load_secrets)
        {:noreply, put_flash(socket, :info, "Secret '#{name}' deleted")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete: #{inspect(reason)}")}
    end
  end

  def handle_event("init_vault", _params, socket) do
    case Vault.init() do
      :ok ->
        send(self(), :load_secrets)
        {:noreply, put_flash(socket, :info, "Vault initialized")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to initialize: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-[#0a0a0a] text-gray-100">
      <header class="bg-[#111] border-b border-[#222] px-4 h-12 flex items-center shrink-0">
        <div class="flex items-center justify-between w-full">
          <div class="flex items-center gap-3">
            <span class="text-sm font-medium text-white">Secrets</span>
            <span class="text-xs text-gray-500">
              {length(@secrets)} secret(s)
            </span>
          </div>
          <%= if @vault_status == :ready do %>
            <.button phx-click="show_add_form" variant={:primary} size={:sm}>
              <.icon name="hero-plus" class="h-4 w-4 mr-1" /> Add Secret
            </.button>
          <% end %>
        </div>
      </header>

      <div class="flex-1 overflow-auto p-6">
        <%= if @vault_status == :checking do %>
          <div class="flex items-center justify-center h-full">
            <.spinner class="h-8 w-8 text-[#00e599]" />
          </div>
        <% end %>

        <%= if @vault_status == :not_initialized do %>
          <div class="flex items-center justify-center h-full text-gray-500">
            <div class="text-center">
              <.icon name="hero-key" class="h-12 w-12 mx-auto mb-3 opacity-50" />
              <p>Vault not initialized</p>
              <p class="text-sm mt-1 mb-4">Initialize the vault to start storing secrets</p>
              <.button phx-click="init_vault" variant={:primary}>
                Initialize Vault
              </.button>
            </div>
          </div>
        <% end %>

        <%= if @vault_status == :ready do %>
          <!-- Add Secret Form -->
          <%= if @adding_secret do %>
            <div class="mb-6 p-4 bg-[#111] border border-[#222]">
              <h3 class="text-sm font-medium text-white mb-4">Add New Secret</h3>
              <form phx-submit="save_secret" class="space-y-4">
                <div>
                  <label class="block text-xs text-gray-400 mb-1">Name</label>
                  <input
                    type="text"
                    name="name"
                    value={@form[:name].value}
                    class="w-full bg-[#0a0a0a] border border-[#333] px-3 py-2 text-white text-sm focus:border-[#00e599] focus:outline-none"
                    placeholder="SECRET_NAME"
                    autocomplete="off"
                  />
                </div>
                <div>
                  <label class="block text-xs text-gray-400 mb-1">Value</label>
                  <input
                    type="password"
                    name="value"
                    value={@form[:value].value}
                    class="w-full bg-[#0a0a0a] border border-[#333] px-3 py-2 text-white text-sm focus:border-[#00e599] focus:outline-none"
                    placeholder="secret value"
                    autocomplete="off"
                  />
                </div>
                <div class="flex gap-2">
                  <.button type="submit" variant={:primary} size={:sm}>
                    Save Secret
                  </.button>
                  <.button type="button" phx-click="cancel_add" variant={:ghost} size={:sm}>
                    Cancel
                  </.button>
                </div>
              </form>
            </div>
          <% end %>
          
    <!-- Secrets List -->
          <%= if Enum.empty?(@secrets) and not @adding_secret do %>
            <div class="flex items-center justify-center h-full text-gray-500">
              <div class="text-center">
                <.icon name="hero-key" class="h-12 w-12 mx-auto mb-3 opacity-50" />
                <p>No secrets stored</p>
                <p class="text-sm mt-1">Add secrets to use in your tasks</p>
              </div>
            </div>
          <% else %>
            <div class="space-y-2">
              <%= for secret <- @secrets do %>
                <div class="flex items-center justify-between p-3 bg-[#111] border border-[#222] hover:border-[#333]">
                  <div class="flex items-center gap-3">
                    <.icon name="hero-key" class="h-4 w-4 text-[#00e599]" />
                    <span class="font-mono text-sm text-white">{secret}</span>
                  </div>
                  <button
                    type="button"
                    phx-click="delete_secret"
                    phx-value-name={secret}
                    data-confirm={"Delete secret '#{secret}'? This cannot be undone."}
                    class="text-red-400 hover:text-red-300 p-1"
                  >
                    <.icon name="hero-trash" class="h-4 w-4" />
                  </button>
                </div>
              <% end %>
            </div>
            
    <!-- Usage Hint -->
            <div class="mt-6 p-4 bg-[#111] border border-[#222]">
              <h4 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-2">
                Usage in Tasks
              </h4>
              <code class="text-sm text-[#00e599]">secret("SECRET_NAME")</code>
              <p class="text-xs text-gray-500 mt-2">
                Use this macro in your task definitions to reference secrets
              </p>
            </div>
          <% end %>
        <% end %>

        <%= if @vault_status == :error do %>
          <div class="bg-red-900/50 border border-red-500 p-4">
            <p class="text-red-200 text-sm">{@error}</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
