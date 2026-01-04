defmodule NexusWeb.Application do
  @moduledoc """
  Supervisor for the Nexus web dashboard.

  This module manages the Phoenix endpoint and related processes
  for the interactive DAG visualization and execution dashboard.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 4000)
    host = Keyword.get(opts, :host, {127, 0, 0, 1})
    config_file = Keyword.get(opts, :config_file)

    # Store config in application env for access by LiveViews
    if config_file do
      Application.put_env(:nexus, :web_config_file, config_file)
    end

    children = [
      # PubSub for real-time updates
      {Phoenix.PubSub, name: NexusWeb.PubSub},

      # Session supervisor for managing execution sessions
      {DynamicSupervisor, name: NexusWeb.SessionSupervisor, strategy: :one_for_one},

      # Telemetry broadcaster - bridges Nexus telemetry to PubSub
      NexusWeb.Broadcaster,

      # Phoenix endpoint
      {NexusWeb.Endpoint,
       [
         http: [ip: host, port: port],
         server: true,
         secret_key_base: generate_secret_key_base()
       ]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp generate_secret_key_base do
    # Generate a random secret for each run (web dashboard is ephemeral)
    :crypto.strong_rand_bytes(64) |> Base.encode64() |> binary_part(0, 64)
  end
end
