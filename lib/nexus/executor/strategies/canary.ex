defmodule Nexus.Executor.Strategies.Canary do
  @moduledoc """
  Canary deployment strategy for safe, gradual rollouts.

  Deploys to a small subset of hosts first (the "canaries"), waits
  for a specified period to detect issues, then proceeds with the
  rest if health checks pass.

  ## Options

    * `:canary_hosts` - Number of canary hosts (default: 1)
    * `:canary_wait` - Seconds to wait after canary deploy (default: 60)
    * `:continue_on_error` - Continue on failure (default: false)

  ## Example

      task :deploy, on: :web, strategy: :canary, canary_hosts: 1, canary_wait: 60 do
        run "systemctl restart app", sudo: true
        wait_for :http, "http://localhost:4000/health"
      end

  """

  alias Nexus.Executor.HealthCheck
  alias Nexus.Executor.Strategies.Rolling
  alias Nexus.SSH.Pool
  alias Nexus.Types.Host
  alias Nexus.Types.Task, as: NexusTask

  require Logger

  @type canary_opts :: [
          canary_hosts: pos_integer(),
          canary_wait: pos_integer(),
          continue_on_error: boolean(),
          ssh_opts: keyword()
        ]

  @doc """
  Executes a canary deployment.

  1. Deploys to canary hosts (first N hosts)
  2. Waits for canary_wait seconds
  3. Runs health checks on canary hosts
  4. If successful, deploys to remaining hosts using rolling strategy

  ## Returns

    * `{:ok, [host_result]}` - Deployment completed
    * `{:error, reason}` - Deployment aborted (canary failed)

  """
  @spec run(NexusTask.t(), [Host.t()], canary_opts()) ::
          {:ok, [map()]} | {:error, term()}
  def run(%NexusTask{} = task, hosts, opts \\ []) do
    canary_count = Keyword.get(opts, :canary_hosts, 1)
    canary_wait = Keyword.get(opts, :canary_wait, 60)

    # Split hosts into canaries and main fleet
    {canary_hosts, main_hosts} = Enum.split(hosts, canary_count)

    # Phase 1: Deploy to canary hosts
    Logger.info("Deploying to #{length(canary_hosts)} canary host(s)...")

    with {:ok, canary_results} <- deploy_canaries(task, canary_hosts, opts),
         :ok <- check_canary_success(canary_results),
         :ok <- wait_and_verify_health(task, canary_hosts, canary_wait, opts) do
      # Phase 4: Deploy to main fleet
      Logger.info("Canary healthy. Deploying to remaining #{length(main_hosts)} host(s)...")
      deploy_main_fleet(task, main_hosts, canary_results, opts)
    else
      {:error, {:canary_failed, _} = error} -> {:error, error}
      {:error, {:canary_unhealthy, _} = error} -> {:error, error}
    end
  end

  defp check_canary_success(canary_results) do
    if all_successful?(canary_results) do
      :ok
    else
      Logger.error("Canary deployment failed. Aborting.")
      {:error, {:canary_failed, canary_results}}
    end
  end

  defp wait_and_verify_health(task, canary_hosts, canary_wait, opts) do
    # Phase 2: Wait and observe
    Logger.info("Canary deployed. Waiting #{canary_wait}s for observation...")
    Process.sleep(canary_wait * 1000)

    # Phase 3: Verify canary health
    case verify_canary_health(task, canary_hosts, opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Canary health check failed: #{inspect(reason)}")
        {:error, {:canary_unhealthy, reason}}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp deploy_canaries(task, hosts, opts) do
    rolling_opts = Keyword.merge(opts, batch_size: length(hosts))
    Rolling.run(task, hosts, rolling_opts)
  end

  defp all_successful?(results) do
    Enum.all?(results, fn result ->
      result.status == :ok
    end)
  end

  defp verify_canary_health(task, hosts, opts) do
    # Re-run health checks to verify canaries are still healthy
    health_checks = extract_health_checks(task.commands)

    if Enum.empty?(health_checks) do
      :ok
    else
      check_hosts_health(hosts, health_checks, opts)
    end
  end

  defp extract_health_checks(commands) do
    Enum.filter(commands, fn cmd ->
      match?(%Nexus.Types.WaitFor{}, cmd)
    end)
  end

  defp check_hosts_health(hosts, health_checks, opts) do
    ssh_opts = Keyword.get(opts, :ssh_opts, [])

    results =
      Enum.map(hosts, fn host ->
        case Pool.checkout(host, &run_checks(&1, health_checks), connect_opts: ssh_opts) do
          {:ok, :ok} -> :ok
          {:ok, {:error, reason}} -> {:error, host.name, reason}
          {:error, reason} -> {:error, host.name, reason}
        end
      end)

    case Enum.find(results, &match?({:error, _, _}, &1)) do
      nil -> :ok
      {:error, host, reason} -> {:error, {host, reason}}
    end
  end

  defp run_checks(conn, health_checks) do
    Enum.reduce_while(health_checks, :ok, fn check, _acc ->
      case HealthCheck.wait(check, conn: conn) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp deploy_main_fleet(_task, [], canary_results, _opts) do
    # No main fleet - just return canary results
    {:ok, canary_results}
  end

  defp deploy_main_fleet(task, hosts, canary_results, opts) do
    {:ok, main_results} = Rolling.run(task, hosts, opts)
    {:ok, canary_results ++ main_results}
  end
end
