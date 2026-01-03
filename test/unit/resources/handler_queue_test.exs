defmodule Nexus.Resources.HandlerQueueTest do
  use ExUnit.Case, async: true

  alias Nexus.Resources.HandlerQueue

  describe "start_link/1" do
    test "starts handler queue agent" do
      assert {:ok, pid} = HandlerQueue.start_link([])
      assert Process.alive?(pid)
      HandlerQueue.stop(pid)
    end

    test "starts with empty queue" do
      {:ok, pid} = HandlerQueue.start_link([])
      assert HandlerQueue.list(pid) == []
      HandlerQueue.stop(pid)
    end

    test "accepts name option" do
      {:ok, pid} = HandlerQueue.start_link(name: :test_queue)
      assert Process.alive?(pid)
      HandlerQueue.stop(pid)
    end
  end

  describe "enqueue/3" do
    setup do
      {:ok, pid} = HandlerQueue.start_link([])
      on_exit(fn -> if Process.alive?(pid), do: HandlerQueue.stop(pid) end)
      {:ok, queue: pid}
    end

    test "adds handler to queue", %{queue: pid} do
      :queued = HandlerQueue.enqueue(pid, :restart_nginx, [])
      assert :restart_nginx in HandlerQueue.list(pid)
    end

    test "allows multiple handlers", %{queue: pid} do
      :queued = HandlerQueue.enqueue(pid, :restart_nginx, [])
      :queued = HandlerQueue.enqueue(pid, :reload_config, [])
      handlers = HandlerQueue.list(pid)
      assert :restart_nginx in handlers
      assert :reload_config in handlers
    end

    test "deduplicates handlers", %{queue: pid} do
      :queued = HandlerQueue.enqueue(pid, :restart_nginx, [])
      :queued = HandlerQueue.enqueue(pid, :restart_nginx, [])
      assert HandlerQueue.count(pid) == 1
    end

    test "returns :queued for default timing", %{queue: pid} do
      result = HandlerQueue.enqueue(pid, :handler_a, [])
      assert result == :queued
    end

    test "returns immediate tuple for immediate timing", %{queue: pid} do
      result = HandlerQueue.enqueue(pid, :handler_a, timing: :immediate)
      assert result == {:immediate, :handler_a}
    end
  end

  describe "flush/1" do
    setup do
      {:ok, pid} = HandlerQueue.start_link([])
      on_exit(fn -> if Process.alive?(pid), do: HandlerQueue.stop(pid) end)
      {:ok, queue: pid}
    end

    test "returns all queued handlers", %{queue: pid} do
      HandlerQueue.enqueue(pid, :handler_a, [])
      HandlerQueue.enqueue(pid, :handler_b, [])

      handlers = HandlerQueue.flush(pid)
      assert :handler_a in handlers
      assert :handler_b in handlers
    end

    test "clears the queue after flush", %{queue: pid} do
      HandlerQueue.enqueue(pid, :handler_a, [])
      HandlerQueue.flush(pid)

      assert HandlerQueue.list(pid) == []
    end

    test "returns empty list when no handlers queued", %{queue: pid} do
      assert HandlerQueue.flush(pid) == []
    end
  end

  describe "list/1" do
    setup do
      {:ok, pid} = HandlerQueue.start_link([])
      on_exit(fn -> if Process.alive?(pid), do: HandlerQueue.stop(pid) end)
      {:ok, queue: pid}
    end

    test "returns queued handlers without clearing", %{queue: pid} do
      HandlerQueue.enqueue(pid, :handler_a, [])
      HandlerQueue.enqueue(pid, :handler_b, [])

      handlers = HandlerQueue.list(pid)
      assert :handler_a in handlers
      assert :handler_b in handlers
      # Call again to verify not cleared
      assert HandlerQueue.count(pid) == 2
    end
  end

  describe "any_queued?/1" do
    setup do
      {:ok, pid} = HandlerQueue.start_link([])
      on_exit(fn -> if Process.alive?(pid), do: HandlerQueue.stop(pid) end)
      {:ok, queue: pid}
    end

    test "returns false when queue is empty", %{queue: pid} do
      assert HandlerQueue.any_queued?(pid) == false
    end

    test "returns true when handlers are queued", %{queue: pid} do
      HandlerQueue.enqueue(pid, :handler_a, [])
      assert HandlerQueue.any_queued?(pid) == true
    end
  end

  describe "queued?/2" do
    setup do
      {:ok, pid} = HandlerQueue.start_link([])
      on_exit(fn -> if Process.alive?(pid), do: HandlerQueue.stop(pid) end)
      {:ok, queue: pid}
    end

    test "returns true when specific handler is queued", %{queue: pid} do
      HandlerQueue.enqueue(pid, :restart_nginx, [])
      assert HandlerQueue.queued?(pid, :restart_nginx) == true
    end

    test "returns false when handler is not queued", %{queue: pid} do
      HandlerQueue.enqueue(pid, :restart_nginx, [])
      assert HandlerQueue.queued?(pid, :reload_config) == false
    end

    test "returns false for empty queue", %{queue: pid} do
      assert HandlerQueue.queued?(pid, :restart_nginx) == false
    end
  end

  describe "clear/1" do
    setup do
      {:ok, pid} = HandlerQueue.start_link([])
      on_exit(fn -> if Process.alive?(pid), do: HandlerQueue.stop(pid) end)
      {:ok, queue: pid}
    end

    test "removes all handlers from queue", %{queue: pid} do
      HandlerQueue.enqueue(pid, :handler_a, [])
      HandlerQueue.enqueue(pid, :handler_b, [])
      HandlerQueue.clear(pid)

      assert HandlerQueue.list(pid) == []
    end

    test "returns :ok", %{queue: pid} do
      assert HandlerQueue.clear(pid) == :ok
    end
  end

  describe "count/1" do
    setup do
      {:ok, pid} = HandlerQueue.start_link([])
      on_exit(fn -> if Process.alive?(pid), do: HandlerQueue.stop(pid) end)
      {:ok, queue: pid}
    end

    test "returns 0 for empty queue", %{queue: pid} do
      assert HandlerQueue.count(pid) == 0
    end

    test "returns correct count", %{queue: pid} do
      HandlerQueue.enqueue(pid, :handler_a, [])
      HandlerQueue.enqueue(pid, :handler_b, [])
      HandlerQueue.enqueue(pid, :handler_c, [])

      assert HandlerQueue.count(pid) == 3
    end

    test "counts unique handlers only", %{queue: pid} do
      HandlerQueue.enqueue(pid, :handler_a, [])
      HandlerQueue.enqueue(pid, :handler_a, [])
      HandlerQueue.enqueue(pid, :handler_b, [])

      assert HandlerQueue.count(pid) == 2
    end
  end

  describe "stop/1" do
    test "stops the agent" do
      {:ok, pid} = HandlerQueue.start_link([])
      assert Process.alive?(pid)
      HandlerQueue.stop(pid)
      refute Process.alive?(pid)
    end
  end
end
