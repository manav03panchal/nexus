defmodule Nexus.Application do
  @moduledoc """
  The Nexus OTP Application.

  Starts and supervises core Nexus services.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # SSH connection pool will be added in Phase 5
      # {Nexus.SSH.Pool, []}

      # Telemetry will be added in Phase 8
      # {Nexus.Telemetry, []}
    ]

    opts = [strategy: :one_for_one, name: Nexus.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
