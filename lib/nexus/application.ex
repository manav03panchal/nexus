defmodule Nexus.Application do
  @moduledoc """
  The Nexus OTP Application.

  Starts and supervises core Nexus services.
  """

  use Application

  @impl true
  def start(_type, _args) do
    # Create ETS table for SSH pool management
    # Owned by the Application process to ensure it outlives individual pools
    create_pool_table()

    # Enable telemetry event handlers
    Nexus.Telemetry.setup()

    children = [
      # Dynamic supervisor for task execution processes
      {Nexus.Executor.Supervisor, []}
    ]

    opts = [strategy: :one_for_one, name: Nexus.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp create_pool_table do
    # Create the ETS table for SSH pool registry
    # Using :public so Pool module can read/write
    # Using :set for fast key lookups
    :ets.new(:nexus_ssh_pools, [:named_table, :public, :set, {:read_concurrency, true}])
  end
end
