defmodule Nexus.Application do
  @moduledoc """
  The Nexus OTP Application.

  Starts and supervises core Nexus services.
  """

  use Application

  @impl true
  def start(_type, _args) do
    # Create ETS table for SSH pool registry
    # This must happen before any SSH operations
    create_pool_table()

    # Attach telemetry handlers before starting supervision tree
    Nexus.Telemetry.setup()

    children = [
      # Dynamic supervisor for task execution processes
      {Nexus.Executor.Supervisor, []}
    ]

    opts = [strategy: :one_for_one, name: Nexus.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp create_pool_table do
    # Create ETS table for SSH connection pool registry
    # Table is owned by the Application process to ensure it outlives individual pools
    if :ets.whereis(:nexus_ssh_pools) == :undefined do
      :ets.new(:nexus_ssh_pools, [:named_table, :public, :set, {:read_concurrency, true}])
    end
  rescue
    ArgumentError -> :ok
  end
end
