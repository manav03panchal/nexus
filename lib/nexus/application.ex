defmodule Nexus.Application do
  @moduledoc """
  The Nexus OTP Application.

  Starts and supervises core Nexus services.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for SSH connection pools (per-host pools)
      {Registry, keys: :unique, name: Nexus.SSH.PoolRegistry}

      # Telemetry will be added in Phase 8
      # {Nexus.Telemetry, []}
    ]

    opts = [strategy: :one_for_one, name: Nexus.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
