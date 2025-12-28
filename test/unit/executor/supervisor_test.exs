defmodule Nexus.Executor.SupervisorTest do
  use ExUnit.Case, async: false

  alias Nexus.Executor.Supervisor, as: ExecSupervisor

  @moduletag :unit

  setup do
    # Start a test supervisor for each test
    {:ok, pid} = ExecSupervisor.start_link(name: :"test_supervisor_#{:rand.uniform(1_000_000)}")
    {:ok, supervisor: pid}
  end

  describe "start_task/2" do
    test "starts a task process", %{supervisor: sup} do
      {:ok, pid} = ExecSupervisor.start_task(fn -> :ok end, supervisor: sup)
      assert is_pid(pid)
    end

    test "task process runs the function", %{supervisor: sup} do
      test_pid = self()

      {:ok, _pid} =
        ExecSupervisor.start_task(
          fn ->
            send(test_pid, :task_ran)
          end,
          supervisor: sup
        )

      assert_receive :task_ran, 1000
    end

    test "task process exits after completion", %{supervisor: sup} do
      {:ok, pid} =
        ExecSupervisor.start_task(
          fn -> :ok end,
          supervisor: sup
        )

      # Wait for the process to exit
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000
    end
  end

  describe "start_named_task/3" do
    test "starts a named task", %{supervisor: sup} do
      {:ok, pid} = ExecSupervisor.start_named_task(:my_task, fn -> :ok end, supervisor: sup)
      assert is_pid(pid)
    end
  end

  describe "count_tasks/1" do
    test "returns 0 when no tasks running", %{supervisor: sup} do
      # Give a moment for any startup tasks to complete
      Process.sleep(50)
      assert ExecSupervisor.count_tasks(sup) == 0
    end

    test "counts running tasks", %{supervisor: sup} do
      test_pid = self()

      # Start tasks that wait for a signal
      for _ <- 1..3 do
        ExecSupervisor.start_task(
          fn ->
            send(test_pid, :started)
            receive do: (:done -> :ok)
          end,
          supervisor: sup
        )
      end

      # Wait for all tasks to start
      for _ <- 1..3 do
        assert_receive :started, 1000
      end

      assert ExecSupervisor.count_tasks(sup) == 3
    end
  end

  describe "list_tasks/1" do
    test "returns empty list when no tasks", %{supervisor: sup} do
      Process.sleep(50)
      assert ExecSupervisor.list_tasks(sup) == []
    end

    test "returns list of task pids", %{supervisor: sup} do
      test_pid = self()

      # Start tasks that wait for a signal
      for _ <- 1..2 do
        ExecSupervisor.start_task(
          fn ->
            send(test_pid, :started)
            receive do: (:done -> :ok)
          end,
          supervisor: sup
        )
      end

      for _ <- 1..2 do
        assert_receive :started, 1000
      end

      tasks = ExecSupervisor.list_tasks(sup)
      assert length(tasks) == 2
      assert Enum.all?(tasks, &is_pid/1)
    end
  end

  describe "terminate_all/1" do
    test "terminates all running tasks", %{supervisor: sup} do
      test_pid = self()

      # Start tasks that wait forever
      pids =
        for _ <- 1..3 do
          {:ok, pid} =
            ExecSupervisor.start_task(
              fn ->
                send(test_pid, :started)
                receive do: (:done -> :ok)
              end,
              supervisor: sup
            )

          pid
        end

      for _ <- 1..3 do
        assert_receive :started, 1000
      end

      assert ExecSupervisor.count_tasks(sup) == 3

      # Terminate all
      assert :ok = ExecSupervisor.terminate_all(sup)

      # Verify all are terminated
      Process.sleep(50)
      assert ExecSupervisor.count_tasks(sup) == 0

      # Verify pids are dead
      for pid <- pids do
        refute Process.alive?(pid)
      end
    end
  end

  describe "supervision" do
    test "tasks are temporary (not restarted)", %{supervisor: sup} do
      test_pid = self()

      {:ok, pid} =
        ExecSupervisor.start_task(
          fn ->
            send(test_pid, {:started, self()})
            raise "intentional crash"
          end,
          supervisor: sup
        )

      # Wait for initial start
      assert_receive {:started, ^pid}, 1000

      # Wait for crash
      Process.sleep(100)

      # Task should not be restarted (temporary)
      refute_receive {:started, _}, 500
      assert ExecSupervisor.count_tasks(sup) == 0
    end
  end
end
