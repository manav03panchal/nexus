---
sidebar_position: 6
---

# Architecture

Deep dive into Nexus internals: how it parses configurations, resolves dependencies, manages SSH connections, and executes tasks.

## Overview

Nexus is built with a modular architecture following Elixir/OTP best practices:

```
┌─────────────────────────────────────────────────────────────────┐
│                           CLI Layer                              │
│  Nexus.CLI → Nexus.CLI.{Run, List, Validate, Init, Preflight}   │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Configuration Layer                         │
│         Nexus.DSL.Parser → Nexus.DSL.Validator                   │
│                    Nexus.Types.*                                 │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Execution Layer                            │
│     Nexus.DAG → Nexus.Executor.Pipeline → TaskRunner             │
└─────────────────────────────────────────────────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    ▼                       ▼
┌───────────────────────────┐   ┌───────────────────────────────┐
│      Local Executor       │   │        SSH Layer              │
│   Nexus.Executor.Local    │   │  Nexus.SSH.{Connection,Pool}  │
│                           │   │  Nexus.SSH.{Auth,ConfigParser}│
└───────────────────────────┘   └───────────────────────────────┘
```

## Module Overview

### Core Modules

| Module | Purpose |
|--------|---------|
| `Nexus.CLI` | Entry point, command routing, argument parsing |
| `Nexus.DSL.Parser` | Parses `nexus.exs` files into structured config |
| `Nexus.DSL.Validator` | Validates configuration for errors |
| `Nexus.Types` | Type definitions (Host, Task, Command, Config) |
| `Nexus.DAG` | Dependency graph construction and resolution |
| `Nexus.Executor.Pipeline` | Orchestrates task execution |
| `Nexus.Executor.TaskRunner` | Executes individual tasks |
| `Nexus.Executor.Local` | Local command execution |
| `Nexus.SSH.Connection` | SSH connection management |
| `Nexus.SSH.Pool` | Connection pooling with NimblePool |
| `Nexus.SSH.Auth` | Authentication resolution |
| `Nexus.SSH.ConfigParser` | `~/.ssh/config` parsing |
| `Nexus.Preflight.Checker` | Pre-flight validation checks |
| `Nexus.Output.Formatter` | Output formatting |
| `Nexus.Telemetry` | Telemetry events |

---

## Type System

Nexus uses structured types defined in `Nexus.Types`:

### Host

```elixir
defmodule Nexus.Types.Host do
  @type t :: %__MODULE__{
    name: atom(),           # :web1
    hostname: String.t(),   # "192.168.1.10"
    user: String.t() | nil, # "deploy"
    port: pos_integer()     # 22
  }
end
```

### Command

```elixir
defmodule Nexus.Types.Command do
  @type t :: %__MODULE__{
    cmd: String.t(),              # "echo hello"
    sudo: boolean(),              # false
    user: String.t() | nil,       # nil
    timeout: pos_integer(),       # 60_000
    retries: non_neg_integer(),   # 0
    retry_delay: pos_integer()    # 1_000
  }
end
```

### Task

```elixir
defmodule Nexus.Types.Task do
  @type t :: %__MODULE__{
    name: atom(),                      # :deploy
    deps: [atom()],                    # [:build, :test]
    on: atom(),                        # :webservers | :local
    commands: [Command.t()],           # [%Command{...}, ...]
    timeout: pos_integer(),            # 300_000
    strategy: :parallel | :serial      # :parallel
  }
end
```

### Config

```elixir
defmodule Nexus.Types.Config do
  @type t :: %__MODULE__{
    default_user: String.t() | nil,
    default_port: pos_integer(),
    connect_timeout: pos_integer(),
    command_timeout: pos_integer(),
    max_connections: pos_integer(),
    continue_on_error: boolean(),
    hosts: %{atom() => Host.t()},
    groups: %{atom() => HostGroup.t()},
    tasks: %{atom() => Task.t()}
  }
end
```

---

## DSL Parser

The DSL parser (`Nexus.DSL.Parser`) transforms `nexus.exs` files into `Config` structs.

### How It Works

1. **File Reading**: Read the `nexus.exs` file content
2. **DSL Wrapping**: Wrap content in a module that provides DSL macros
3. **Evaluation**: Use `Code.eval_string/3` to evaluate the wrapped code
4. **State Tracking**: Use process dictionary to accumulate config during evaluation
5. **Return**: Return the final `Config` struct

### DSL Implementation

```elixir
# The DSL module provides macros like:
defmodule Nexus.DSL.Parser.DSL do
  defmacro host(name, connection_string) do
    quote do
      Nexus.DSL.Parser.DSL.do_host(unquote(name), unquote(connection_string))
    end
  end
  
  def do_host(name, connection_string) do
    config = Process.get(:nexus_config)
    {:ok, host} = Host.parse(name, connection_string)
    Process.put(:nexus_config, Config.add_host(config, host))
  end
  
  defmacro task(name, opts \\ [], do: block) do
    quote do
      Nexus.DSL.Parser.DSL.do_task(unquote(name), unquote(opts), fn ->
        unquote(block)
      end)
    end
  end
  
  # ... similar for config, group, run
end
```

### Host String Parsing

The `Host.parse/2` function handles various connection string formats:

```elixir
def parse(name, host_string) do
  cond do
    # user@hostname:port
    String.match?(host_string, ~r/^[^@]+@[^:]+:\d+$/) ->
      [user_host, port] = String.split(host_string, ":", parts: 2)
      [user, hostname] = String.split(user_host, "@", parts: 2)
      {:ok, %Host{name: name, hostname: hostname, user: user, port: String.to_integer(port)}}
    
    # user@hostname
    String.match?(host_string, ~r/^[^@]+@[^:]+$/) ->
      [user, hostname] = String.split(host_string, "@", parts: 2)
      {:ok, %Host{name: name, hostname: hostname, user: user, port: 22}}
    
    # hostname:port
    String.match?(host_string, ~r/^[^@:]+:\d+$/) ->
      [hostname, port] = String.split(host_string, ":", parts: 2)
      {:ok, %Host{name: name, hostname: hostname, user: nil, port: String.to_integer(port)}}
    
    # hostname only
    String.match?(host_string, ~r/^[^@:]+$/) ->
      {:ok, %Host{name: name, hostname: host_string, user: nil, port: 22}}
  end
end
```

---

## DAG (Directed Acyclic Graph)

The DAG module (`Nexus.DAG`) handles dependency resolution using the `libgraph` library.

### Graph Construction

```elixir
def build(%Config{tasks: tasks}) do
  graph = tasks
    |> Map.values()
    |> Enum.reduce(Graph.new(), fn task, g ->
      g = Graph.add_vertex(g, task.name)
      
      # Add edges from dependencies to this task
      Enum.reduce(task.deps, g, fn dep, acc ->
        Graph.add_edge(acc, dep, task.name)
      end)
    end)
  
  if Graph.is_acyclic?(graph) do
    {:ok, graph}
  else
    cycle = find_cycle_path(graph)
    {:error, {:cycle, cycle}}
  end
end
```

### Execution Phases

Tasks are grouped into phases where:
- Tasks in the same phase have no dependencies on each other
- Phases are executed sequentially
- Tasks within a phase can run in parallel

```elixir
def execution_phases(graph) do
  # Calculate depth (longest path from root) for each vertex
  depths = calculate_depths(graph)
  
  # Group vertices by depth
  graph
  |> Graph.vertices()
  |> Enum.group_by(fn v -> Map.get(depths, v, 0) end)
  |> Enum.sort_by(fn {depth, _} -> depth end)
  |> Enum.map(fn {_, tasks} -> Enum.sort(tasks) end)
end
```

### Example

Given tasks:
```
build (no deps)
lint (no deps)
test (deps: build)
deploy (deps: test, lint)
```

Produces:
```
Phase 1: [build, lint]    # Can run in parallel
Phase 2: [test]           # Depends on build
Phase 3: [deploy]         # Depends on test and lint
```

---

## Pipeline Execution

The pipeline executor (`Nexus.Executor.Pipeline`) orchestrates task execution.

### Execution Flow

```
1. Build execution plan
   └── Resolve target tasks and dependencies
   └── Build DAG and compute phases

2. Execute phases sequentially
   └── For each phase:
       └── Run tasks in parallel (up to parallel_limit)
       └── For each task:
           └── Resolve hosts
           └── Use TaskRunner to execute

3. Aggregate results
   └── Track success/failure counts
   └── Handle continue_on_error
```

### Code Flow

```elixir
def run(%Config{} = config, target_tasks, opts) do
  with {:ok, plan} <- build_execution_plan(config, target_tasks) do
    execute_plan(config, plan, opts)
  end
end

defp execute_plan(config, plan, opts) do
  Enum.reduce_while(plan.phases, initial_state, fn phase, state ->
    {:ok, results} = execute_phase(config, phase, plan.task_details, opts)
    
    if has_failures?(results) and not opts[:continue_on_error] do
      {:halt, state_with_abort}
    else
      {:cont, updated_state}
    end
  end)
end

defp execute_phase(config, phase, task_details, opts) do
  phase
  |> Task.async_stream(fn task_name ->
    task = Map.fetch!(task_details, task_name)
    hosts = resolve_task_hosts(config, task)
    TaskRunner.run(task, hosts, opts)
  end, max_concurrency: opts[:parallel_limit])
  |> collect_results()
end
```

---

## Task Runner

The task runner (`Nexus.Executor.TaskRunner`) executes a single task across hosts.

### Execution Strategies

**Parallel** (default):
```elixir
defp run_parallel(task, hosts, opts) do
  hosts
  |> Task.async_stream(fn host -> 
    run_on_host(task, host, opts)
  end, timeout: task.timeout)
  |> collect_results()
end
```

**Serial**:
```elixir
defp run_serial(task, hosts, opts) do
  Enum.reduce_while(hosts, [], fn host, acc ->
    result = run_on_host(task, host, opts)
    
    if result.status == :error and not opts[:continue_on_error] do
      {:halt, [result | acc]}
    else
      {:cont, [result | acc]}
    end
  end)
end
```

### Command Execution with Retry

```elixir
defp execute_with_retry(command, executor, attempt) do
  result = executor.(command)
  
  case result do
    {:ok, output, 0} ->
      success_result(command, output, attempt)
    
    {:ok, output, exit_code} when attempt <= command.retries ->
      Process.sleep(calculate_retry_delay(command.retry_delay, attempt))
      execute_with_retry(command, executor, attempt + 1)
    
    {:ok, output, exit_code} ->
      failure_result(command, output, exit_code, attempt)
    
    {:error, reason} when attempt <= command.retries ->
      Process.sleep(calculate_retry_delay(command.retry_delay, attempt))
      execute_with_retry(command, executor, attempt + 1)
    
    {:error, reason} ->
      error_result(command, reason, attempt)
  end
end

# Exponential backoff with jitter
defp calculate_retry_delay(base_delay, attempt) do
  multiplier = :math.pow(2, attempt - 1)
  delay = round(multiplier * base_delay)
  jitter = :rand.uniform(round(delay * 0.2))
  delay + jitter
end
```

---

## SSH Layer

### Connection Management

`Nexus.SSH.Connection` wraps SSHKit for SSH operations:

```elixir
def connect(%Host{} = host, opts) do
  ssh_opts = build_ssh_opts(opts)
  
  case SSH.connect(host.hostname, ssh_opts) do
    {:ok, conn} -> {:ok, conn}
    {:error, :timeout} -> {:error, {:connection_timeout, host.hostname}}
    {:error, :econnrefused} -> {:error, {:connection_refused, host.hostname}}
    {:error, reason} -> {:error, {:connection_failed, host.hostname, reason}}
  end
end

def exec(conn, command, opts) do
  timeout = Keyword.get(opts, :timeout, 60_000)
  
  case SSH.run(conn, command, timeout: timeout) do
    {:ok, output_list, exit_code} ->
      {:ok, format_output(output_list), exit_code}
    {:error, :timeout} ->
      {:error, {:command_timeout, command}}
    {:error, reason} ->
      {:error, {:exec_failed, command, reason}}
  end
end
```

### Connection Pooling

`Nexus.SSH.Pool` uses NimblePool for efficient connection reuse with async initialization:

```elixir
defmodule Nexus.SSH.Pool do
  @behaviour NimblePool
  
  def checkout(host, fun, opts) do
    pool = get_or_create_pool(host, opts)
    
    NimblePool.checkout!(pool, :checkout, fn _from, conn ->
      result = fun.(conn)
      
      if connection_valid?(conn) do
        {result, :ok}
      else
        {result, :remove}
      end
    end)
  end
  
  @impl NimblePool
  def init_worker(%{host: host, connect_opts: opts} = pool_state) do
    # Async initialization to avoid blocking the pool process
    {:async, fn -> async_connect(host, opts) end, pool_state}
  end
  
  defp async_connect(host, opts) do
    case Connection.connect(host, opts) do
      {:ok, conn} -> {host, opts, conn}
      {:error, _reason} -> {host, opts, nil}
    end
  end
  
  @impl NimblePool
  def handle_checkout(:checkout, _from, {_host, _opts, nil}, pool_state) do
    # Connection failed during async init, remove worker
    {:remove, :connection_failed, pool_state}
  end
  
  def handle_checkout(:checkout, _from, {host, opts, conn}, pool_state) do
    if connection_valid?(conn) do
      {:ok, conn, {host, opts, conn}, pool_state}
    else
      Connection.close(conn)
      {:remove, :connection_invalid, pool_state}
    end
  end
end
```

### Pool Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Pool Registry (ETS)                       │
│  "host1:22:deploy" → Pool PID                                │
│  "host2:22:deploy" → Pool PID                                │
│  "host3:2222:admin" → Pool PID                               │
│  (Table created by Application, owned by supervisor)         │
└─────────────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────┐
│                   NimblePool per Host                        │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐        │
│  │  Conn 1  │ │  Conn 2  │ │  Conn 3  │ │  Conn 4  │ ...    │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘        │
│     idle        in_use       idle         idle              │
│                                                              │
│  - Connections created asynchronously via init_worker        │
│  - Idle connections cleaned up via handle_ping callback      │
│  - Invalid connections removed on next checkout              │
└─────────────────────────────────────────────────────────────┘
```

### Authentication Resolution

`Nexus.SSH.Auth` resolves authentication in priority order:

```elixir
def resolve(hostname, opts) do
  cond do
    # 1. Explicit identity file
    opts[:identity] != nil ->
      resolve_identity(opts[:identity])
    
    # 2. Explicit password
    opts[:password] != nil ->
      {:ok, {:password, opts[:password]}}
    
    # 3. SSH agent (if available)
    agent_available?() ->
      {:ok, :agent}
    
    # 4. Default key files
    true ->
      resolve_default_key(hostname)
  end
end

def agent_available? do
  case System.get_env("SSH_AUTH_SOCK") do
    nil -> false
    "" -> false
    sock_path -> File.exists?(sock_path)
  end
end

@default_key_names ["id_ed25519", "id_ecdsa", "id_rsa", "id_dsa"]

defp resolve_default_key(_hostname) do
  ssh_dir = Path.expand("~/.ssh")
  
  @default_key_names
  |> Enum.map(&Path.join(ssh_dir, &1))
  |> Enum.find(&key_exists?/1)
  |> case do
    nil -> {:ok, :none}
    path -> {:ok, {:identity, path}}
  end
end
```

---

## Local Execution

`Nexus.Executor.Local` handles local command execution:

```elixir
def run(command, opts) do
  timeout = Keyword.get(opts, :timeout, 60_000)
  shell_opts = build_shell_opts(opts)
  
  task = Task.async(fn ->
    {output, exit_code} = System.shell(command, shell_opts)
    {:ok, output, exit_code}
  end)
  
  case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
    {:ok, result} -> result
    nil -> {:error, :timeout}
  end
end

def run_streaming(command, opts, callback) do
  port = Port.open({:spawn, shell_command}, port_opts)
  stream_loop(port, callback)
end

defp stream_loop(port, callback) do
  receive do
    {^port, {:data, {:eol, line}}} ->
      callback.({:stdout, line <> "\n"})
      stream_loop(port, callback)
    
    {^port, {:exit_status, code}} ->
      callback.({:exit, code})
      {:ok, code}
  end
end
```

---

## Telemetry

Nexus emits telemetry events for observability:

```elixir
# Event: [:nexus, :task, :start]
# Measurements: %{system_time: ...}
# Metadata: %{task: :deploy, on: :webservers}

# Event: [:nexus, :task, :stop]
# Measurements: %{duration: ..., system_time: ...}
# Metadata: %{task: :deploy, status: :ok, hosts_succeeded: 3, hosts_failed: 0}

# Event: [:nexus, :command, :start]
# Measurements: %{system_time: ...}
# Metadata: %{command: "echo hello", host: :web1}

# Event: [:nexus, :command, :stop]
# Measurements: %{duration: ...}
# Metadata: %{command: "echo hello", host: :web1, exit_code: 0}

# Event: [:nexus, :ssh, :connect]
# Measurements: %{duration: ...}
# Metadata: %{host: "192.168.1.10", port: 22, user: "deploy"}
```

### Attaching Handlers

```elixir
:telemetry.attach_many(
  "nexus-logger",
  [
    [:nexus, :task, :start],
    [:nexus, :task, :stop],
    [:nexus, :command, :start],
    [:nexus, :command, :stop]
  ],
  &handle_event/4,
  nil
)

def handle_event([:nexus, :task, :stop], measurements, metadata, _config) do
  Logger.info("Task #{metadata.task} completed in #{measurements.duration}ms")
end
```

---

## Error Handling

### Error Types

```elixir
# Configuration errors
{:error, "syntax error: ..."}
{:error, [{:task_deps, "task :deploy depends on unknown task :build"}]}

# Connection errors
{:error, {:connection_timeout, "192.168.1.10"}}
{:error, {:connection_refused, "192.168.1.10"}}
{:error, {:auth_failed, "192.168.1.10"}}

# Execution errors
{:error, {:command_timeout, "long_running_command"}}
{:error, {:exec_failed, "command", :reason}}

# DAG errors
{:error, {:cycle, [:a, :b, :c, :a]}}
{:error, {:unknown_tasks, [:missing1, :missing2]}}
```

### Error Propagation

```
Command fails
    ↓
TaskRunner records failure, optionally retries
    ↓
If retries exhausted, mark command as failed
    ↓
If continue_on_error is false, stop task
    ↓
Pipeline receives task failure
    ↓
If continue_on_error is false, stop pipeline
    ↓
CLI displays error and exits with code 1
```

---

## Performance Characteristics

### Benchmarks

From our test suite:

| Operation | Time | Notes |
|-----------|------|-------|
| SSH connection | ~100ms | Includes TCP + auth |
| Command execution overhead | ~1.5ms | After connection established |
| DAG resolution (100 tasks) | &lt;100ms | Using libgraph |
| DAG resolution (1000 tasks) | &lt;2s | Using libgraph |

### Connection Pooling Impact

Without pooling:
```
10 commands × 5 hosts = 50 connections
Connection time: 50 × 100ms = 5000ms overhead
```

With pooling:
```
10 commands × 5 hosts = 5 connections (reused)
Connection time: 5 × 100ms = 500ms overhead
```

### Memory Usage

- Base memory: ~50MB (Erlang VM + Nexus)
- Per SSH connection: ~2-5MB
- 100 concurrent connections: ~300-500MB total

---

## Extension Points

### Custom Authentication

Implement the `Nexus.SSH.Behaviour`:

```elixir
defmodule MyApp.CustomSSH do
  @behaviour Nexus.SSH.Behaviour
  
  @impl true
  def connect(host, opts) do
    # Custom connection logic
  end
  
  @impl true
  def exec(conn, command, opts) do
    # Custom execution logic
  end
  
  @impl true
  def close(conn) do
    # Custom cleanup
  end
end
```

### Custom Output Handlers

Use telemetry to capture and format output:

```elixir
defmodule MyApp.OutputHandler do
  def setup do
    :telemetry.attach("custom-output", [:nexus, :command, :stop], &handle/4, nil)
  end
  
  def handle(_, measurements, metadata, _) do
    # Send to logging service, Slack, etc.
    MyApp.Slack.notify("Command #{metadata.command} completed in #{measurements.duration}ms")
  end
end
```

---

## See Also

- [Getting Started](getting-started.md) - Usage guide
- [Configuration Reference](configuration.md) - DSL documentation
- [SSH Configuration](ssh.md) - SSH details
- [Troubleshooting](troubleshooting.md) - Common issues
