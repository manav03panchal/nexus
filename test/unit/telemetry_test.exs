defmodule Nexus.TelemetryTest do
  use ExUnit.Case, async: false

  alias Nexus.Telemetry

  # We use async: false because telemetry handlers are global

  setup do
    # Detach any existing handlers to ensure clean state
    :telemetry.detach("nexus-default-handler")
    :telemetry.detach("test-handler")

    on_exit(fn ->
      :telemetry.detach("nexus-default-handler")
      :telemetry.detach("test-handler")
    end)

    :ok
  end

  describe "setup/0" do
    test "attaches default handlers" do
      assert :ok = Telemetry.setup()

      # Verify handlers are attached by checking handler list
      handlers = :telemetry.list_handlers([:nexus, :pipeline, :start])
      assert Enum.any?(handlers, fn h -> h.id == "nexus-default-handler" end)
    end

    test "is idempotent" do
      assert :ok = Telemetry.setup()
      # Second call should not raise
      assert :ok = Telemetry.setup()
    end
  end

  describe "attach_default_handlers/0" do
    test "attaches handlers for all events" do
      assert :ok = Telemetry.attach_default_handlers()

      events = [
        [:nexus, :pipeline, :start],
        [:nexus, :pipeline, :stop],
        [:nexus, :pipeline, :exception],
        [:nexus, :task, :start],
        [:nexus, :task, :stop],
        [:nexus, :task, :exception],
        [:nexus, :command, :start],
        [:nexus, :command, :stop],
        [:nexus, :ssh, :connect, :start],
        [:nexus, :ssh, :connect, :stop]
      ]

      for event <- events do
        handlers = :telemetry.list_handlers(event)

        assert Enum.any?(handlers, fn h -> h.id == "nexus-default-handler" end),
               "Handler not found for event: #{inspect(event)}"
      end
    end
  end

  describe "detach_default_handlers/0" do
    test "detaches handlers when attached" do
      Telemetry.attach_default_handlers()
      assert :ok = Telemetry.detach_default_handlers()

      handlers = :telemetry.list_handlers([:nexus, :pipeline, :start])
      refute Enum.any?(handlers, fn h -> h.id == "nexus-default-handler" end)
    end

    test "returns error when not attached" do
      assert {:error, :not_found} = Telemetry.detach_default_handlers()
    end
  end

  describe "emit_pipeline_start/2" do
    test "emits pipeline start event" do
      test_pid = self()

      :telemetry.attach(
        "test-handler",
        [:nexus, :pipeline, :start],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      tasks = [:build, :test, :deploy]
      config = %{hosts: [], tasks: []}

      Telemetry.emit_pipeline_start(tasks, config)

      assert_receive {:telemetry_event, [:nexus, :pipeline, :start], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.tasks == [:build, :test, :deploy]
      assert metadata.config == config
    end
  end

  describe "emit_pipeline_stop/2" do
    test "emits pipeline stop event" do
      test_pid = self()

      :telemetry.attach(
        "test-handler",
        [:nexus, :pipeline, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      result = %{status: :ok, tasks_run: 3}
      Telemetry.emit_pipeline_stop(1_000_000, result)

      assert_receive {:telemetry_event, [:nexus, :pipeline, :stop], measurements, metadata}
      assert measurements.duration == 1_000_000
      assert metadata.status == :ok
      assert metadata.tasks_run == 3
    end
  end

  describe "emit_pipeline_exception/4" do
    test "emits pipeline exception event" do
      test_pid = self()

      :telemetry.attach(
        "test-handler",
        [:nexus, :pipeline, :exception],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      stacktrace = [{__MODULE__, :test, 0, []}]
      Telemetry.emit_pipeline_exception(500_000, :error, :timeout, stacktrace)

      assert_receive {:telemetry_event, [:nexus, :pipeline, :exception], measurements, metadata}
      assert measurements.duration == 500_000
      assert metadata.kind == :error
      assert metadata.reason == :timeout
      assert metadata.stacktrace == stacktrace
    end
  end

  describe "emit_task_start/2" do
    test "emits task start event" do
      test_pid = self()

      :telemetry.attach(
        "test-handler",
        [:nexus, :task, :start],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      Telemetry.emit_task_start(:deploy, :web_servers)

      assert_receive {:telemetry_event, [:nexus, :task, :start], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.task == :deploy
      assert metadata.on == :web_servers
    end
  end

  describe "emit_task_stop/3" do
    test "emits task stop event" do
      test_pid = self()

      :telemetry.attach(
        "test-handler",
        [:nexus, :task, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      Telemetry.emit_task_stop(:deploy, 2_000_000, :ok)

      assert_receive {:telemetry_event, [:nexus, :task, :stop], measurements, metadata}
      assert measurements.duration == 2_000_000
      assert metadata.task == :deploy
      assert metadata.status == :ok
    end
  end

  describe "emit_task_exception/4" do
    test "emits task exception event" do
      test_pid = self()

      :telemetry.attach(
        "test-handler",
        [:nexus, :task, :exception],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      Telemetry.emit_task_exception(:deploy, 1_500_000, :error, :connection_refused)

      assert_receive {:telemetry_event, [:nexus, :task, :exception], measurements, metadata}
      assert measurements.duration == 1_500_000
      assert metadata.task == :deploy
      assert metadata.kind == :error
      assert metadata.reason == :connection_refused
    end
  end

  describe "emit_command_start/2" do
    test "emits command start event" do
      test_pid = self()

      :telemetry.attach(
        "test-handler",
        [:nexus, :command, :start],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      Telemetry.emit_command_start("echo hello", :web1)

      assert_receive {:telemetry_event, [:nexus, :command, :start], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.command == "echo hello"
      assert metadata.host == :web1
    end
  end

  describe "emit_command_stop/3" do
    test "emits command stop event" do
      test_pid = self()

      :telemetry.attach(
        "test-handler",
        [:nexus, :command, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      Telemetry.emit_command_stop("echo hello", 100_000, 0)

      assert_receive {:telemetry_event, [:nexus, :command, :stop], measurements, metadata}
      assert measurements.duration == 100_000
      assert metadata.command == "echo hello"
      assert metadata.exit_code == 0
    end
  end

  describe "emit_ssh_connect_start/2" do
    test "emits SSH connect start event" do
      test_pid = self()

      :telemetry.attach(
        "test-handler",
        [:nexus, :ssh, :connect, :start],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      Telemetry.emit_ssh_connect_start("server.example.com", 22)

      assert_receive {:telemetry_event, [:nexus, :ssh, :connect, :start], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.host == "server.example.com"
      assert metadata.port == 22
    end
  end

  describe "emit_ssh_connect_stop/3" do
    test "emits SSH connect stop event" do
      test_pid = self()

      :telemetry.attach(
        "test-handler",
        [:nexus, :ssh, :connect, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      Telemetry.emit_ssh_connect_stop("server.example.com", 50_000_000, :ok)

      assert_receive {:telemetry_event, [:nexus, :ssh, :connect, :stop], measurements, metadata}
      assert measurements.duration == 50_000_000
      assert metadata.host == "server.example.com"
      assert metadata.status == :ok
    end
  end

  describe "span/3" do
    test "wraps function with telemetry events" do
      test_pid = self()

      :telemetry.attach_many(
        "test-handler",
        [[:test, :span, :start], [:test, :span, :stop]],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      result =
        Telemetry.span([:test, :span], %{custom: "data"}, fn ->
          :test_result
        end)

      assert result == :test_result

      assert_receive {:telemetry_event, [:test, :span, :start], start_measurements,
                      start_metadata}

      assert is_integer(start_measurements.system_time)
      assert start_metadata.custom == "data"

      assert_receive {:telemetry_event, [:test, :span, :stop], stop_measurements, _stop_metadata}
      assert is_integer(stop_measurements.duration)
    end

    test "emits exception event on error" do
      test_pid = self()

      :telemetry.attach_many(
        "test-handler",
        [[:test, :span, :start], [:test, :span, :exception]],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      assert_raise RuntimeError, "test error", fn ->
        Telemetry.span([:test, :span], %{}, fn ->
          raise "test error"
        end)
      end

      assert_receive {:telemetry_event, [:test, :span, :start], _, _}
      assert_receive {:telemetry_event, [:test, :span, :exception], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.kind == :error
      assert %RuntimeError{message: "test error"} = metadata.reason
    end
  end

  describe "default handler logging" do
    import ExUnit.CaptureLog

    setup do
      # Save original log level and set to debug for these tests
      original_level = Logger.level()
      Logger.configure(level: :debug)

      on_exit(fn ->
        Logger.configure(level: original_level)
      end)

      :ok
    end

    test "logs pipeline start at debug level" do
      Telemetry.attach_default_handlers()

      log =
        capture_log(fn ->
          Telemetry.emit_pipeline_start([:build, :test], %{})
        end)

      assert log =~ "Pipeline started"
      assert log =~ "build"
      assert log =~ "test"
    end

    test "logs pipeline stop at debug level" do
      Telemetry.attach_default_handlers()

      log =
        capture_log(fn ->
          Telemetry.emit_pipeline_stop(1_000_000_000, %{status: :ok})
        end)

      assert log =~ "Pipeline completed"
      assert log =~ "ok"
    end

    test "logs pipeline exception at error level" do
      Telemetry.attach_default_handlers()

      log =
        capture_log(fn ->
          Telemetry.emit_pipeline_exception(500_000_000, :error, :timeout, [])
        end)

      assert log =~ "Pipeline exception"
      assert log =~ "timeout"
    end

    test "logs task events at debug level" do
      Telemetry.attach_default_handlers()

      log =
        capture_log(fn ->
          Telemetry.emit_task_start(:deploy, :local)
          Telemetry.emit_task_stop(:deploy, 1_000_000_000, :ok)
        end)

      assert log =~ "Task started: deploy"
      assert log =~ "Task completed: deploy"
    end

    test "logs command events at debug level" do
      Telemetry.attach_default_handlers()

      log =
        capture_log(fn ->
          Telemetry.emit_command_start("echo hello", :local)
          Telemetry.emit_command_stop("echo hello", 100_000_000, 0)
        end)

      assert log =~ "Command started"
      assert log =~ "Command completed"
      assert log =~ "exit_code=0"
    end

    test "logs SSH events at debug level" do
      Telemetry.attach_default_handlers()

      log =
        capture_log(fn ->
          Telemetry.emit_ssh_connect_start("server.example.com", 22)
          Telemetry.emit_ssh_connect_stop("server.example.com", 50_000_000, :ok)
        end)

      assert log =~ "SSH connecting"
      assert log =~ "server.example.com:22"
      assert log =~ "SSH connection ok"
    end
  end
end
