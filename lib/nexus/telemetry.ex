defmodule Nexus.Telemetry do
  @moduledoc """
  Telemetry event definitions and default handlers for Nexus.

  Emits telemetry events for all major operations, enabling:
  - Performance monitoring
  - Custom logging integrations
  - Metrics collection

  ## Events

  All events are prefixed with `[:nexus, ...]`.

  ### Pipeline Events

    * `[:nexus, :pipeline, :start]` - Pipeline execution started
      - Measurements: `%{system_time: integer()}`
      - Metadata: `%{tasks: [atom()], config: config()}`

    * `[:nexus, :pipeline, :stop]` - Pipeline execution completed
      - Measurements: `%{duration: integer()}`
      - Metadata: `%{status: :ok | :error, tasks_run: integer(), ...}`

    * `[:nexus, :pipeline, :exception]` - Pipeline raised an exception
      - Measurements: `%{duration: integer()}`
      - Metadata: `%{kind: atom(), reason: term(), stacktrace: list()}`

  ### Task Events

    * `[:nexus, :task, :start]` - Task execution started
      - Measurements: `%{system_time: integer()}`
      - Metadata: `%{task: atom(), on: atom()}`

    * `[:nexus, :task, :stop]` - Task execution completed
      - Measurements: `%{duration: integer()}`
      - Metadata: `%{task: atom(), status: :ok | :error}`

    * `[:nexus, :task, :exception]` - Task raised an exception
      - Measurements: `%{duration: integer()}`
      - Metadata: `%{task: atom(), kind: atom(), reason: term()}`

  ### Command Events

    * `[:nexus, :command, :start]` - Command execution started
      - Measurements: `%{system_time: integer()}`
      - Metadata: `%{command: String.t(), host: atom()}`

    * `[:nexus, :command, :stop]` - Command execution completed
      - Measurements: `%{duration: integer()}`
      - Metadata: `%{command: String.t(), exit_code: integer()}`

    * `[:nexus, :command, :retry]` - Command retry attempt
      - Measurements: `%{attempt: integer(), delay_ms: integer()}`
      - Metadata: `%{command: String.t(), max_attempts: integer(), exit_code: integer()}`

  ### SSH Events

    * `[:nexus, :ssh, :connect, :start]` - SSH connection started
      - Measurements: `%{system_time: integer()}`
      - Metadata: `%{host: String.t(), port: integer()}`

    * `[:nexus, :ssh, :connect, :stop]` - SSH connection completed
      - Measurements: `%{duration: integer()}`
      - Metadata: `%{host: String.t(), status: :ok | :error}`

    * `[:nexus, :ssh, :pool, :checkout]` - Connection checked out from pool
      - Measurements: `%{count: integer()}`
      - Metadata: `%{host: String.t()}`

  """

  require Logger

  @doc """
  Sets up telemetry event handlers.

  Call this in your application's start/2 function to enable
  default telemetry handling.
  """
  @spec setup() :: :ok
  def setup do
    attach_default_handlers()
  end

  @doc """
  Attaches default telemetry handlers for logging.
  """
  @spec attach_default_handlers() :: :ok
  def attach_default_handlers do
    events = [
      [:nexus, :pipeline, :start],
      [:nexus, :pipeline, :stop],
      [:nexus, :pipeline, :exception],
      [:nexus, :task, :start],
      [:nexus, :task, :stop],
      [:nexus, :task, :exception],
      [:nexus, :command, :start],
      [:nexus, :command, :stop],
      [:nexus, :command, :retry],
      [:nexus, :ssh, :connect, :start],
      [:nexus, :ssh, :connect, :stop]
    ]

    :telemetry.attach_many(
      "nexus-default-handler",
      events,
      &__MODULE__.handle_event/4,
      nil
    )

    :ok
  end

  @doc """
  Detaches the default telemetry handlers.
  """
  @spec detach_default_handlers() :: :ok | {:error, :not_found}
  def detach_default_handlers do
    :telemetry.detach("nexus-default-handler")
  end

  @doc """
  Emits a pipeline start event.
  """
  @spec emit_pipeline_start(list(), map()) :: :ok
  def emit_pipeline_start(tasks, config) do
    :telemetry.execute(
      [:nexus, :pipeline, :start],
      %{system_time: System.system_time()},
      %{tasks: tasks, config: config}
    )
  end

  @doc """
  Emits a pipeline stop event.
  """
  @spec emit_pipeline_stop(integer(), map()) :: :ok
  def emit_pipeline_stop(duration, result) do
    :telemetry.execute(
      [:nexus, :pipeline, :stop],
      %{duration: duration},
      result
    )
  end

  @doc """
  Emits a pipeline exception event.
  """
  @spec emit_pipeline_exception(integer(), atom(), term(), list()) :: :ok
  def emit_pipeline_exception(duration, kind, reason, stacktrace) do
    :telemetry.execute(
      [:nexus, :pipeline, :exception],
      %{duration: duration},
      %{kind: kind, reason: reason, stacktrace: stacktrace}
    )
  end

  @doc """
  Emits a task start event.
  """
  @spec emit_task_start(atom(), atom()) :: :ok
  def emit_task_start(task_name, on) do
    :telemetry.execute(
      [:nexus, :task, :start],
      %{system_time: System.system_time()},
      %{task: task_name, on: on}
    )
  end

  @doc """
  Emits a task stop event.
  """
  @spec emit_task_stop(atom(), integer(), atom()) :: :ok
  def emit_task_stop(task_name, duration, status) do
    :telemetry.execute(
      [:nexus, :task, :stop],
      %{duration: duration},
      %{task: task_name, status: status}
    )
  end

  @doc """
  Emits a task exception event.
  """
  @spec emit_task_exception(atom(), integer(), atom(), term()) :: :ok
  def emit_task_exception(task_name, duration, kind, reason) do
    :telemetry.execute(
      [:nexus, :task, :exception],
      %{duration: duration},
      %{task: task_name, kind: kind, reason: reason}
    )
  end

  @doc """
  Emits a command start event.
  """
  @spec emit_command_start(String.t(), atom()) :: :ok
  def emit_command_start(command, host) do
    :telemetry.execute(
      [:nexus, :command, :start],
      %{system_time: System.system_time()},
      %{command: command, host: host}
    )
  end

  @doc """
  Emits a command stop event.
  """
  @spec emit_command_stop(String.t(), integer(), integer(), String.t(), atom()) :: :ok
  def emit_command_stop(command, duration, exit_code, output \\ "", host \\ :local) do
    :telemetry.execute(
      [:nexus, :command, :stop],
      %{duration: duration},
      %{command: command, exit_code: exit_code, output: output, host: host}
    )
  end

  @doc """
  Emits a command retry event.
  """
  @spec emit_command_retry(String.t(), integer(), integer(), integer(), integer()) :: :ok
  def emit_command_retry(command, attempt, max_attempts, delay_ms, exit_code) do
    :telemetry.execute(
      [:nexus, :command, :retry],
      %{attempt: attempt, delay_ms: delay_ms},
      %{command: command, max_attempts: max_attempts, exit_code: exit_code}
    )
  end

  @doc """
  Emits an SSH connect start event.
  """
  @spec emit_ssh_connect_start(String.t(), integer()) :: :ok
  def emit_ssh_connect_start(host, port) do
    :telemetry.execute(
      [:nexus, :ssh, :connect, :start],
      %{system_time: System.system_time()},
      %{host: host, port: port}
    )
  end

  @doc """
  Emits an SSH connect stop event.
  """
  @spec emit_ssh_connect_stop(String.t(), integer(), atom()) :: :ok
  def emit_ssh_connect_stop(host, duration, status) do
    :telemetry.execute(
      [:nexus, :ssh, :connect, :stop],
      %{duration: duration},
      %{host: host, status: status}
    )
  end

  @doc """
  Wraps a function with telemetry span events.

  Emits start, stop, and exception events automatically.
  """
  @spec span(list(), map(), (-> result)) :: result when result: term()
  def span(event_prefix, metadata, fun) do
    :telemetry.span(event_prefix, metadata, fn ->
      result = fun.()
      {result, metadata}
    end)
  end

  @doc false
  # Default event handler - logs events at debug level
  # Made public to avoid telemetry local function warning
  def handle_event([:nexus, :pipeline, :start], _measurements, metadata, _config) do
    task_names = Enum.map(metadata.tasks, &Atom.to_string/1)
    Logger.debug("Pipeline started with tasks: #{Enum.join(task_names, ", ")}")
  end

  def handle_event([:nexus, :pipeline, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    Logger.debug("Pipeline completed: status=#{metadata.status} duration=#{duration_ms}ms")
  end

  def handle_event([:nexus, :pipeline, :exception], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.error(
      "Pipeline exception: #{metadata.kind} - #{inspect(metadata.reason)} (#{duration_ms}ms)"
    )
  end

  def handle_event([:nexus, :task, :start], _measurements, metadata, _config) do
    Logger.debug("Task started: #{metadata.task} on #{metadata.on}")
  end

  def handle_event([:nexus, :task, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.debug(
      "Task completed: #{metadata.task} status=#{metadata.status} duration=#{duration_ms}ms"
    )
  end

  def handle_event([:nexus, :task, :exception], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.error(
      "Task exception: #{metadata.task} - #{metadata.kind}: #{inspect(metadata.reason)} (#{duration_ms}ms)"
    )
  end

  def handle_event([:nexus, :command, :start], _measurements, metadata, _config) do
    cmd_preview = String.slice(metadata.command, 0, 50)
    Logger.debug("Command started on #{metadata.host}: #{cmd_preview}")
  end

  def handle_event([:nexus, :command, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    Logger.debug("Command completed: exit_code=#{metadata.exit_code} duration=#{duration_ms}ms")
  end

  def handle_event([:nexus, :command, :retry], measurements, metadata, _config) do
    cmd_preview = String.slice(metadata.command, 0, 40)

    Logger.debug(
      "Retry #{measurements.attempt}/#{metadata.max_attempts}: #{cmd_preview} (exit_code=#{metadata.exit_code}, waiting #{measurements.delay_ms}ms)"
    )
  end

  def handle_event([:nexus, :ssh, :connect, :start], _measurements, metadata, _config) do
    Logger.debug("SSH connecting to #{metadata.host}:#{metadata.port}")
  end

  def handle_event([:nexus, :ssh, :connect, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    Logger.debug("SSH connection #{metadata.status}: #{metadata.host} (#{duration_ms}ms)")
  end
end
