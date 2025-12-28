defmodule Nexus.SSH.PoolTest do
  use ExUnit.Case, async: true

  alias Nexus.SSH.Pool
  alias Nexus.Types.Host

  @moduletag :unit

  # Note: These are unit tests for pool logic that don't require SSH connections.
  # Integration tests with real connections are in test/integration/

  describe "start_link/2" do
    test "accepts Host struct" do
      host = %Host{
        name: :test,
        hostname: "example.com",
        user: "test",
        port: 22
      }

      # Pool starts even without actual connection (lazy init)
      assert {:ok, pool} = Pool.start_link(host)
      # Use GenServer.stop instead of Pool.stop to avoid exit signal issues
      GenServer.stop(pool, :normal)
    end

    test "accepts hostname string" do
      assert {:ok, pool} = Pool.start_link("example.com")
      GenServer.stop(pool, :normal)
    end

    test "accepts pool_size option" do
      assert {:ok, pool} = Pool.start_link("example.com", pool_size: 10)
      GenServer.stop(pool, :normal)
    end

    test "accepts connect_opts option" do
      opts = [
        pool_size: 3,
        connect_opts: [user: "deploy", port: 2222]
      ]

      assert {:ok, pool} = Pool.start_link("example.com", opts)
      GenServer.stop(pool, :normal)
    end
  end

  describe "stop/1" do
    test "stops a running pool" do
      # Trap exits so we don't crash when pool shuts down
      Process.flag(:trap_exit, true)

      {:ok, pool} = Pool.start_link("example.com")
      ref = Process.monitor(pool)

      # Stop the pool - this sends shutdown signal
      spawn(fn -> Pool.stop(pool) end)

      # Wait for the pool to terminate
      assert_receive {:DOWN, ^ref, :process, ^pool, _reason}, 1000
      refute Process.alive?(pool)
    end
  end

  describe "stats/1" do
    test "returns stats map" do
      {:ok, pool} = Pool.start_link("example.com")

      stats = Pool.stats(pool)

      assert is_map(stats)
      assert Map.has_key?(stats, :pool_size)
      assert Map.has_key?(stats, :available)
      assert Map.has_key?(stats, :in_use)

      GenServer.stop(pool, :normal)
    end
  end

  describe "with_connection/3" do
    test "returns error when pool is not started" do
      fake_pid = spawn(fn -> :ok end)
      Process.exit(fake_pid, :kill)

      # Wait for process to die
      :timer.sleep(10)

      result = Pool.with_connection(fake_pid, fn _conn -> :ok end)

      assert {:error, :pool_not_started} = result
    end
  end

  describe "close_all/0" do
    test "returns :ok even when no pools exist" do
      assert :ok = Pool.close_all()
    end
  end

  describe "module exports" do
    test "exports expected functions" do
      functions = Pool.__info__(:functions)

      assert {:start_link, 1} in functions
      assert {:start_link, 2} in functions
      assert {:with_connection, 2} in functions
      assert {:with_connection, 3} in functions
      assert {:checkout, 2} in functions
      assert {:checkout, 3} in functions
      assert {:stop, 1} in functions
      assert {:close_all, 0} in functions
      assert {:stats, 1} in functions
    end
  end

  describe "NimblePool behaviour" do
    test "implements NimblePool behaviour" do
      # The module should implement the NimblePool behaviour
      behaviours = Pool.__info__(:attributes)[:behaviour] || []
      assert NimblePool in behaviours
    end
  end
end
