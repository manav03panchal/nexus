defmodule Nexus.Application do
  @moduledoc """
  The Nexus OTP Application.

  Starts and supervises core Nexus services.
  """

  use Application

  @impl true
  def start(_type, _args) do
    # Attach telemetry handlers before starting supervision tree
    Nexus.Telemetry.setup()

    children = [
      # Dynamic supervisor for task execution processes
      {Nexus.Executor.Supervisor, []}
    ]

    opts = [strategy: :one_for_one, name: Nexus.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
