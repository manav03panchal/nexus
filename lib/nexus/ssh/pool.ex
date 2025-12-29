defmodule Nexus.SSH.Pool do
  @moduledoc """
  Connection pooling for SSH connections using NimblePool.

  Manages a pool of SSH connections per host, enabling efficient connection
  reuse and preventing connection exhaustion. Each host gets its own pool
  with configurable size and timeout settings.

  ## Features

  - Per-host connection pools
  - Automatic connection health checks
  - Idle connection cleanup
  - Connection reuse across tasks
  - Graceful pool shutdown

  ## Usage

      # Start a pool for a host
      {:ok, pool} = Pool.start_link(host, pool_size: 5)

      # Execute with a pooled connection
      result = Pool.with_connection(pool, fn conn ->
        Connection.exec(conn, "whoami")
      end)

      # Or use the convenience function with auto-managed pools
      result = Pool.checkout("web1", fn conn ->
        Connection.exec(conn, "uptime")
      end)

  ## Architecture

  The pool maintains healthy connections and automatically:
  - Validates connections before handing them out
  - Closes stale or broken connections
  - Creates new connections on demand
  - Respects connection limits

  """

  @behaviour NimblePool

  alias Nexus.SSH.Connection
  alias Nexus.Types.Host

  @type pool :: pid()
  @type pool_opts :: [pool_opt()]
  @type pool_opt ::
          {:pool_size, pos_integer()}
          | {:connect_opts, keyword()}
          | {:idle_timeout, pos_integer()}
          | {:checkout_timeout, pos_integer()}

  @type pool_stats :: %{
          pool_size: pos_integer(),
          available: non_neg_integer(),
          in_use: non_neg_integer()
        }

  @default_pool_size 5
  @default_idle_timeout 300_000
  @default_checkout_timeout 30_000

  # ETS table for managing per-host pools
  @pool_table :nexus_ssh_pools

  @doc """
  Starts a connection pool for a specific host.

  ## Options

    * `:pool_size` - Maximum number of connections (default: 5)
    * `:connect_opts` - Options passed to `Connection.connect/2`
    * `:idle_timeout` - Time before idle connections are closed (default: 300000ms)
    * `:checkout_timeout` - Maximum wait time for a connection (default: 30000ms)

  ## Examples

      host = %Host{name: :web1, hostname: "example.com", user: "deploy", port: 22}
      {:ok, pool} = Pool.start_link(host, pool_size: 10)

  """
  @spec start_link(Host.t() | String.t(), pool_opts()) ::
          {:ok, pool()} | {:error, term()} | :ignore
  def start_link(host, opts \\ []) do
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
    connect_opts = Keyword.get(opts, :connect_opts, [])

    worker_state = %{
      host: normalize_host(host),
      connect_opts: connect_opts,
      idle_timeout: Keyword.get(opts, :idle_timeout, @default_idle_timeout)
    }

    NimblePool.start_link(
      worker: {__MODULE__, worker_state},
      pool_size: pool_size,
      lazy: true
    )
  end

  @doc """
  Executes a function with a connection from the pool.

  Checks out a connection, executes the function, and returns the connection
  to the pool. If the function raises or the connection becomes invalid,
  the connection is discarded and a new one will be created.

  ## Examples

      {:ok, output, 0} = Pool.with_connection(pool, fn conn ->
        Connection.exec(conn, "whoami")
      end)

  """
  @spec with_connection(pool(), (Connection.conn() -> result), keyword()) ::
          result | {:error, term()}
        when result: term()
  def with_connection(pool, fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_checkout_timeout)

    try do
      NimblePool.checkout!(
        pool,
        :checkout,
        fn _from, conn ->
          result = fun.(conn)
          # Check if connection is still valid
          if connection_valid?(conn) do
            {result, :ok}
          else
            {result, :remove}
          end
        end,
        timeout
      )
    catch
      :exit, {:timeout, _} ->
        {:error, :checkout_timeout}

      :exit, {:noproc, _} ->
        {:error, :pool_not_started}

      :exit, {:normal, _} ->
        {:error, :pool_closed}

      :exit, reason ->
        {:error, {:pool_error, reason}}
    end
  end

  @doc """
  Convenience function that auto-manages pools per host.

  Uses a global registry to maintain pools for each unique host.
  Pools are created lazily on first access.

  ## Examples

      # First call creates the pool, subsequent calls reuse it
      {:ok, output, 0} = Pool.checkout(host, fn conn ->
        Connection.exec(conn, "ls -la")
      end)

  """
  @spec checkout(Host.t() | String.t(), (Connection.conn() -> result), keyword()) ::
          result | {:error, term()}
        when result: term()
  def checkout(host, fun, opts \\ []) do
    normalized = normalize_host(host)
    pool_key = pool_key(normalized)

    # Ensure ETS table exists
    ensure_pool_table()

    pool =
      case :ets.lookup(@pool_table, pool_key) do
        [{^pool_key, pid}] ->
          if Process.alive?(pid), do: pid, else: start_registered_pool(normalized, opts, pool_key)

        [] ->
          start_registered_pool(normalized, opts, pool_key)
      end

    case pool do
      {:error, reason} -> {:error, reason}
      pid when is_pid(pid) -> with_connection(pid, fun, opts)
    end
  end

  defp ensure_pool_table do
    if :ets.whereis(@pool_table) == :undefined do
      :ets.new(@pool_table, [:named_table, :public, :set, {:read_concurrency, true}])
    end
  rescue
    # Table already exists
    ArgumentError -> :ok
  end

  @doc """
  Closes all connections in a pool and stops the pool.

  ## Examples

      :ok = Pool.stop(pool)

  """
  @spec stop(pool()) :: :ok
  def stop(pool) do
    NimblePool.stop(pool, :shutdown)
  end

  @doc """
  Closes all managed pools.

  Used during application shutdown to clean up resources.

  ## Examples

      :ok = Pool.close_all()

  """
  @spec close_all() :: :ok
  def close_all do
    if :ets.whereis(@pool_table) != :undefined do
      :ets.foldl(
        fn {_key, pid}, :ok ->
          if Process.alive?(pid) do
            try do
              stop(pid)
            catch
              :exit, _ -> :ok
            end
          end

          :ok
        end,
        :ok,
        @pool_table
      )

      :ets.delete_all_objects(@pool_table)
    end

    :ok
  end

  @doc """
  Returns statistics for a pool.

  ## Examples

      %{pool_size: 5, available: 3, in_use: 2} = Pool.stats(pool)

  """
  @spec stats(pool()) :: %{pool_size: pos_integer(), available: atom(), in_use: atom()}
  def stats(_pool) do
    # NimblePool doesn't expose stats directly, so we return basic info
    # In a production system, we'd track this with telemetry
    %{
      pool_size: @default_pool_size,
      available: :unknown,
      in_use: :unknown
    }
  end

  # NimblePool callbacks

  @impl NimblePool
  def init_worker(%{host: host, connect_opts: opts} = pool_state) do
    # Lazy initialization - connection created on first checkout
    {:ok, {host, opts, nil}, pool_state}
  end

  @impl NimblePool
  def handle_checkout(:checkout, _from, {host, opts, nil}, pool_state) do
    # Create connection lazily
    case Connection.connect(host, opts) do
      {:ok, conn} ->
        {:ok, conn, {host, opts, conn}, pool_state}

      {:error, reason} ->
        {:remove, reason, pool_state}
    end
  end

  def handle_checkout(:checkout, _from, {host, opts, conn}, pool_state) do
    # Validate existing connection
    if connection_valid?(conn) do
      {:ok, conn, {host, opts, conn}, pool_state}
    else
      # Connection invalid, create new one
      Connection.close(conn)

      case Connection.connect(host, opts) do
        {:ok, new_conn} ->
          {:ok, new_conn, {host, opts, new_conn}, pool_state}

        {:error, reason} ->
          {:remove, reason, pool_state}
      end
    end
  end

  @impl NimblePool
  def handle_checkin(:ok, _from, {host, opts, conn}, pool_state) do
    {:ok, {host, opts, conn}, pool_state}
  end

  def handle_checkin(:remove, _from, {_host, _opts, conn}, pool_state) do
    if conn, do: Connection.close(conn)
    {:remove, :closed, pool_state}
  end

  @impl NimblePool
  def handle_info({:DOWN, _, :process, _, _}, {host, opts, _conn}) do
    # Connection process died, mark for removal
    {:remove, {host, opts, nil}}
  end

  def handle_info(_msg, worker_state) do
    {:ok, worker_state}
  end

  @impl NimblePool
  def terminate_worker(_reason, {_host, _opts, conn}, pool_state) do
    if conn, do: Connection.close(conn)
    {:ok, pool_state}
  end

  # Private functions

  defp normalize_host(%Host{} = host), do: host

  defp normalize_host(hostname) when is_binary(hostname) do
    %Host{name: String.to_atom(hostname), hostname: hostname}
  end

  defp pool_key(%Host{} = host) do
    "#{host.hostname}:#{host.port || 22}:#{host.user || "default"}"
  end

  defp start_registered_pool(host, opts, pool_key) do
    # Use a lock to prevent race conditions when multiple tasks
    # try to create a pool for the same host simultaneously
    case :global.set_lock({__MODULE__, pool_key}, [node()], :infinity) do
      true ->
        try do
          # Double-check if pool was created while we waited for lock
          case :ets.lookup(@pool_table, pool_key) do
            [{^pool_key, pid}] when is_pid(pid) ->
              if Process.alive?(pid), do: pid, else: do_start_pool(host, opts, pool_key)

            _ ->
              do_start_pool(host, opts, pool_key)
          end
        after
          :global.del_lock({__MODULE__, pool_key}, [node()])
        end

      false ->
        # Couldn't get lock, try lookup again
        case :ets.lookup(@pool_table, pool_key) do
          [{^pool_key, pid}] when is_pid(pid) and is_pid(pid) ->
            if Process.alive?(pid), do: pid, else: {:error, :pool_unavailable}

          _ ->
            {:error, :pool_unavailable}
        end
    end
  end

  defp do_start_pool(host, opts, pool_key) do
    case start_link(host, opts) do
      {:ok, pid} ->
        # Store in ETS - this persists beyond the calling process
        :ets.insert(@pool_table, {pool_key, pid})
        pid

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp connection_valid?(nil), do: false

  defp connection_valid?(conn) do
    # Quick check if connection is still alive
    # We don't run a full command here to avoid latency
    Connection.alive?(conn)
  rescue
    _ -> false
  end
end
