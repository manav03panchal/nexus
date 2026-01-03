defmodule Nexus.Resources.Types.Service do
  @moduledoc """
  Service resource for managing system services.

  Supports multiple init systems based on OS:
  - systemd (most modern Linux)
  - launchd (macOS)
  - openrc (Alpine, Gentoo)

  ## Examples

      # Ensure service is running
      service "nginx", state: :running

      # Ensure running and enabled at boot
      service "nginx", state: :running, enabled: true

      # Stop and disable service
      service "nginx", state: :stopped, enabled: false

      # Restart service
      service "nginx", action: :restart

      # Reload configuration
      service "nginx", action: :reload

      # With conditional
      service "nginx", state: :running, when: facts(:os) == :linux

  """

  @type state :: :running | :stopped | :restarted | :reloaded
  @type action :: :start | :stop | :restart | :reload | :enable | :disable
  @type condition :: term()

  @type t :: %__MODULE__{
          name: String.t(),
          state: state() | nil,
          enabled: boolean() | nil,
          action: action() | nil,
          when: condition(),
          notify: atom() | nil
        }

  @enforce_keys [:name]
  defstruct [
    :name,
    :state,
    :enabled,
    :action,
    :notify,
    when: true
  ]

  @doc """
  Creates a new Service resource.

  ## Options

    * `:state` - Target state (`:running`, `:stopped`, etc.)
    * `:enabled` - Enable/disable at boot
    * `:action` - One-time action (`:restart`, `:reload`)
    * `:notify` - Handler to trigger on change
    * `:when` - Condition for execution

  """
  @spec new(String.t(), keyword()) :: t()
  def new(name, opts \\ []) do
    %__MODULE__{
      name: name,
      state: Keyword.get(opts, :state),
      enabled: Keyword.get(opts, :enabled),
      action: Keyword.get(opts, :action),
      notify: Keyword.get(opts, :notify),
      when: Keyword.get(opts, :when, true)
    }
  end

  @doc """
  Returns a human-readable description of the resource.
  """
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{name: name, state: state, enabled: enabled, action: action}) do
    parts = ["service[#{name}]"]
    parts = if action, do: parts ++ ["action=#{action}"], else: parts
    parts = if state, do: parts ++ ["state=#{state}"], else: parts
    parts = if enabled != nil, do: parts ++ ["enabled=#{enabled}"], else: parts
    Enum.join(parts, " ")
  end
end
