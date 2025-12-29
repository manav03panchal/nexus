# Nexus v0.1 Implementation Plan

## Overview

**Goal:** Build the production-ready core of Nexus - a distributed task runner with local execution, SSH remote execution, DAG dependencies, and comprehensive testing from day one.

**Estimated LOC:** ~2,500 (production) + ~2,000 (tests)  
**Test Coverage Target:** 80%+ from the start

---

## Phase 1: Project Foundation ✅ COMPLETE

### 1.1 Project Setup

```
nexus/
├── lib/
│   └── nexus/
│       ├── application.ex
│       └── ...
├── test/
│   ├── unit/
│   ├── integration/
│   ├── property/
│   ├── performance/
│   └── support/
├── config/
├── mix.exs
├── .formatter.exs
├── .credo.exs
├── dialyzer.ignore-warnings
└── nexus.exs.example
```

### 1.2 Dependencies (mix.exs)

```elixir
defp deps do
  [
    # Core
    {:optimus, "~> 0.5"},
    {:owl, "~> 0.12"},
    {:sshkit, "~> 0.3"},
    {:sftp_client, "~> 2.0"},
    {:nimble_pool, "~> 1.1"},
    {:libgraph, "~> 0.16"},
    {:nimble_options, "~> 1.1"},
    {:telemetry, "~> 1.3"},
    {:telemetry_metrics, "~> 1.0"},
    {:fuse, "~> 2.5"},
    {:hammer, "~> 6.2"},
    
    # Dev & Test
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:ex_doc, "~> 0.34", only: :dev, runtime: false},
    {:mox, "~> 1.2", only: :test},
    {:stream_data, "~> 1.1", only: [:dev, :test]},
    {:benchee, "~> 1.3", only: [:dev, :test]},
    {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
    {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
    {:excoveralls, "~> 0.18", only: :test}
  ]
end
```

### 1.3 CI/CD Setup (.github/workflows/ci.yml)

- [x] Run unit tests on every PR
- [x] Run integration tests with Docker SSH
- [x] Dialyzer, Credo, Sobelow checks
- [ ] Coverage reporting with Coveralls (requires repo setup at coveralls.io)

### 1.4 Deliverables
- [x] `mix new nexus` with umbrella-free structure
- [x] All dependencies added and compiling
- [x] CI pipeline running (GitHub Actions)
- [x] Dialyzer, Credo, Sobelow passing with zero issues
- [x] Test scaffolding in place
- [x] nexus.exs.example template
- [x] docker-compose.test.yml for SSH integration tests
- [x] Hammer rate limiter configured

---

## Phase 2: DSL & Configuration ✅ COMPLETE

### 2.1 Core Types

```elixir
# lib/nexus/types.ex
defmodule Nexus.Types do
  @type task :: %{
    name: atom(),
    deps: [atom()],
    on: atom() | :local,
    commands: [command()],
    timeout: pos_integer(),
    strategy: :parallel | :serial
  }
  
  @type command :: %{
    cmd: String.t(),
    sudo: boolean(),
    user: String.t() | nil,
    timeout: pos_integer(),
    retries: non_neg_integer(),
    retry_delay: pos_integer()
  }
  
  @type host :: %{
    hostname: String.t(),
    user: String.t(),
    port: pos_integer()
  }
end
```

### 2.2 DSL Parser

```elixir
# lib/nexus/dsl/parser.ex
defmodule Nexus.DSL.Parser do
  @spec parse_file(Path.t()) :: {:ok, config()} | {:error, term()}
  @spec parse_string(String.t()) :: {:ok, config()} | {:error, term()}
end

# lib/nexus/dsl/validator.ex
defmodule Nexus.DSL.Validator do
  @spec validate(config()) :: :ok | {:error, [validation_error()]}
end
```

### 2.3 Tests Required

**Unit Tests:**
- [x] Parse valid task definitions
- [x] Parse host definitions (all formats: hostname, user@host, user@host:port)
- [x] Parse config blocks
- [x] Handle env() function calls
- [x] Reject invalid syntax with clear errors
- [x] Validate task references exist
- [x] Validate host group references exist

**Property Tests:**
- [x] Any valid atom is a valid task name
- [x] Host string parsing roundtrips correctly
- [x] Config validation is deterministic

### 2.4 Deliverables
- [x] `Nexus.DSL.Parser` - parse nexus.exs files
- [x] `Nexus.DSL.Validator` - validate configuration
- [x] `Nexus.Types` - typed structs for all data
- [x] 95%+ coverage on DSL modules
- [x] Property tests for parsing

---

## Phase 3: DAG Resolution ✅ COMPLETE

### 3.1 Implementation

```elixir
# lib/nexus/dag.ex
defmodule Nexus.DAG do
  @spec build([task()]) :: {:ok, Graph.t()} | {:error, :cycle, [atom()]}
  @spec topological_sort(Graph.t()) :: [atom()]
  @spec execution_phases(Graph.t()) :: [[atom()]]
  @spec dependencies(Graph.t(), atom()) :: [atom()]
  @spec dependents(Graph.t(), atom()) :: [atom()]
end
```

### 3.2 Tests Required

**Unit Tests:**
- [x] Build graph from tasks with deps
- [x] Detect circular dependencies
- [x] Topological sort produces valid order
- [x] Execution phases group independent tasks
- [x] Single task with no deps
- [x] Complex diamond dependencies
- [x] Long chains

**Property Tests:**
- [x] Topological order always valid (deps before dependents)
- [x] Execution phases cover all tasks exactly once
- [x] Cycle detection is correct

**Performance Tests:**
- [x] 100 tasks with random deps: ~148μs (target <100ms) ✓
- [x] 500 tasks: ~1.15ms (target <500ms) ✓
- [x] 1000 tasks: ~2.25ms (target <2s) ✓

### 3.3 Deliverables
- [x] `Nexus.DAG` module with libgraph
- [x] Cycle detection with helpful error messages
- [x] Execution phase calculation
- [x] 90%+ coverage
- [x] Benchmark suite

---

## Phase 4: Local Execution ✅ COMPLETE

### 4.1 Implementation

```elixir
# lib/nexus/executor/local.ex
defmodule Nexus.Executor.Local do
  @spec run(command(), keyword()) :: {:ok, output(), exit_code()} | {:error, term()}
  @spec run_streaming(command(), keyword(), (chunk() -> any())) :: result()
end
```

### 4.2 Features
- Execute shell commands locally
- Stream stdout/stderr in real-time
- Capture exit codes
- Handle timeouts
- Support working directory
- Environment variable passthrough

### 4.3 Tests Required

**Unit Tests:**
- [x] Run simple command, capture output
- [x] Handle non-zero exit codes
- [x] Timeout kills process
- [x] Streaming output works
- [x] Environment variables passed
- [x] Working directory respected
- [x] Handle commands with special characters

**Integration Tests:**
- [x] Long-running command with streaming
- [x] Command that produces large output
- [x] Concurrent local executions

**Performance Tests:**
- [x] 100 sequential commands: ~518ms baseline
- [x] 100 parallel commands: ~90ms (5.7x speedup)
- [x] Large output (1MB): ~22ms, stable memory

### 4.4 Deliverables
- [x] `Nexus.Executor.Local` module
- [x] Streaming output support
- [x] Timeout handling
- [x] 85%+ coverage

---

## Phase 5: SSH Connection Management ✅ COMPLETE

### 5.1 Implementation

```elixir
# lib/nexus/ssh/connection.ex
defmodule Nexus.SSH.Connection do
  @spec connect(host(), keyword()) :: {:ok, conn()} | {:error, term()}
  @spec exec(conn(), String.t(), keyword()) :: {:ok, output(), exit_code()} | {:error, term()}
  @spec close(conn()) :: :ok
end

# lib/nexus/ssh/pool.ex
defmodule Nexus.SSH.Pool do
  @spec checkout(host(), (conn() -> result())) :: result()
  @spec pool_status(host()) :: pool_stats()
  @spec close_all() :: :ok
end

# lib/nexus/ssh/auth.ex
defmodule Nexus.SSH.Auth do
  @spec resolve_auth(host(), keyword()) :: {:ok, auth_method()} | {:error, term()}
end

# lib/nexus/ssh/config_parser.ex
defmodule Nexus.SSH.ConfigParser do
  @spec parse(Path.t()) :: {:ok, [host_config()]} | {:error, term()}
  @spec lookup(String.t(), [host_config()]) :: host_config()
end
```

### 5.2 Features
- SSH key authentication (Ed25519, RSA, ECDSA)
- SSH agent support
- Password authentication (interactive)
- Connection pooling with NimblePool
- Idle connection cleanup
- Keepalive handling
- ~/.ssh/config parsing
- Known hosts verification

### 5.3 Tests Required

**Unit Tests:**
- [x] Auth resolution priority (key > agent > password)
- [x] SSH config parsing (Host, User, Port, IdentityFile)
- [x] Host pattern matching
- [x] Pool checkout/checkin
- [x] Connection reuse

**Integration Tests (Docker SSH):**
- [x] Connect with password
- [x] Connect with key
- [x] Execute command, get output
- [x] Handle connection refused
- [x] Handle auth failure
- [x] Pool reuses connections
- [x] Concurrent connections to same host
- [x] Concurrent connections to different hosts

**Performance Tests:**
- [x] Connection establishment time: ~102ms (target <2s) ✓
- [x] Command overhead: ~1.4ms (target <50ms) ✓
- [x] 10 sequential commands: ~14ms
- [x] 10 parallel connections: ~177ms

### 5.4 Docker SSH Test Infrastructure

```yaml
# docker-compose.test.yml
services:
  ssh-password:
    image: linuxserver/openssh-server:latest
    ports: ["2232:2222"]
    environment:
      - PASSWORD_ACCESS=true
      - USER_PASSWORD=testpass
      - USER_NAME=testuser
  
  ssh-key:
    image: linuxserver/openssh-server:latest
    ports: ["2233:2222"]
    environment:
      - PUBLIC_KEY_FILE=/keys/id_ed25519.pub
      - USER_NAME=testuser
    volumes:
      - ./test/fixtures/ssh_keys:/keys:ro
```

### 5.5 Deliverables
- [x] `Nexus.SSH.Connection` - connection management (SSHKit wrapper)
- [x] `Nexus.SSH.Pool` - NimblePool-based pooling with PoolRegistry
- [x] `Nexus.SSH.Auth` - authentication resolution
- [x] `Nexus.SSH.ConfigParser` - ~/.ssh/config parsing
- [x] `Nexus.SSH.Behaviour` - behaviour for mocking
- [x] Docker-based integration tests
- [x] CI auto-generates SSH keys (no keys in repo)
- [x] 80%+ coverage

### 5.6 Implementation Notes
- Changed ports from 2222/2223 to 2232/2233 (avoid Vagrant conflict)
- Erlang SSH requires standard key names (id_ed25519, id_rsa) in user_dir
- NimblePool requires `@behaviour NimblePool`, not `use NimblePool`
- CI uses `docker compose` (not `docker-compose`) for GitHub Actions

---

## Phase 6: Pipeline Execution ✅ COMPLETE

### 6.1 Implementation

```elixir
# lib/nexus/executor/pipeline.ex
defmodule Nexus.Executor.Pipeline do
  @spec run(config(), [atom()], keyword()) :: {:ok, result()} | {:error, term()}
end

# lib/nexus/executor/task_runner.ex
defmodule Nexus.Executor.TaskRunner do
  @spec run(task(), hosts(), keyword()) :: {:ok, task_result()} | {:error, term()}
end

# lib/nexus/executor/supervisor.ex
defmodule Nexus.Executor.Supervisor do
  use DynamicSupervisor
end
```

### 6.2 Features
- Execute tasks in DAG order
- Parallel execution within phases
- Per-host parallel execution
- Retry logic with exponential backoff
- Timeout enforcement
- Error aggregation
- Pipeline abort on failure (configurable)

### 6.3 Tests Required

**Unit Tests:**
- [x] Single local task execution
- [x] Task with dependencies
- [x] Parallel task execution
- [x] Serial strategy execution
- [x] Retry on failure
- [x] Timeout handling
- [x] Continue-on-error mode

**Integration Tests:**
- [x] Full pipeline: build → test → deploy
- [x] Pipeline with SSH tasks
- [x] Mixed local and remote tasks
- [x] Failure mid-pipeline
- [x] Parallel remote execution

**Performance Tests:**
- [ ] 10 hosts × 10 commands: measure throughput
- [ ] 100 hosts × 1 command: connection efficiency
- [ ] Memory stability over long pipeline

### 6.4 Deliverables
- [x] `Nexus.Executor.Pipeline` - orchestration with DAG-based phase execution
- [x] `Nexus.Executor.TaskRunner` - task execution with retry and jitter
- [x] `Nexus.Executor.Supervisor` - DynamicSupervisor for task processes
- [x] Retry with exponential backoff and 20% jitter
- [x] 85%+ coverage

### 6.5 Implementation Notes
- Uses `Task.async_stream` for parallel execution within phases
- TaskRunner supports both `:parallel` and `:serial` host strategies
- Pipeline respects both CLI options and config-level `continue_on_error`
- Supervisor added to Application for task lifecycle management

---

## Phase 7: CLI Interface ✅ COMPLETE

### 7.1 Implementation

```elixir
# lib/nexus/cli.ex
defmodule Nexus.CLI do
  @spec main([String.t()]) :: no_return()
end

# lib/nexus/cli/run.ex
# lib/nexus/cli/list.ex
# lib/nexus/cli/validate.ex
# lib/nexus/cli/init.ex
# lib/nexus/cli/preflight.ex
```

### 7.2 Commands
- `nexus run <task> [tasks...]` - execute tasks
- `nexus list` - list defined tasks
- `nexus validate` - validate nexus.exs
- `nexus init` - create template nexus.exs
- `nexus preflight <task>` - pre-flight checks
- `nexus version` - show version
- `nexus help [command]` - help

### 7.3 Flags
- `--dry-run, -n` - show what would execute
- `--verbose, -v` - increase verbosity
- `--quiet, -q` - minimal output
- `--continue-on-error` - don't stop on failure
- `--identity, -i` - SSH key path
- `--user, -u` - SSH user
- `--parallel-limit, -p` - max concurrent tasks
- `--config, -c` - config file path
- `--plain` - no colors/formatting
- `--format` - output format (text/json)

### 7.4 Tests Required

**Unit Tests:**
- [x] Argument parsing for each command
- [x] Flag handling
- [x] Exit codes
- [x] Help text generation
- [x] Error message formatting

**Integration Tests:**
- [x] Full CLI flow: run task
- [x] Dry-run output format
- [x] Quiet vs verbose modes
- [x] JSON output format
- [x] Invalid arguments handling

### 7.5 Deliverables
- [x] `Nexus.CLI` with Optimus
- [x] All commands implemented (run, list, validate, init)
- [x] Exit codes per spec
- [x] 75%+ coverage (50 CLI tests)
- [x] Escript binary for local execution
- [x] JSON output format support
- [x] Added Jason dependency for JSON encoding

### 7.6 Implementation Notes
- Boolean flags (dry_run, verbose, quiet, continue_on_error) moved from options to flags
- Template simplified to only include working DSL syntax (no config block yet)
- Handles :help and :version returns from Optimus

---

## Phase 8: Output & Telemetry ✅ COMPLETE

### 8.1 Implementation

```elixir
# lib/nexus/output/formatter.ex
defmodule Nexus.Output.Formatter do
  @spec format_task_start(task()) :: String.t()
  @spec format_task_complete(task(), result()) :: String.t()
  @spec format_error(error()) :: String.t()
end

# lib/nexus/output/renderer.ex
defmodule Nexus.Output.Renderer do
  @spec render(formattable(), keyword()) :: :ok
end

# lib/nexus/telemetry.ex
defmodule Nexus.Telemetry do
  @spec setup() :: :ok
  @spec attach_default_handlers() :: :ok
end
```

### 8.2 Features
- Normal/verbose/quiet modes
- Color support (respecting NO_COLOR)
- Progress indicators
- Streaming command output
- Structured JSON output
- Telemetry events for all operations

### 8.3 Tests Required

**Unit Tests:**
- [x] Format various message types
- [x] Color stripping when NO_COLOR set
- [x] JSON output structure
- [x] Telemetry event emission

**Integration Tests:**
- [x] Full pipeline output formatting
- [x] Streaming output display
- [x] Error display with context

### 8.4 Deliverables
- [x] `Nexus.Output.Formatter` - message formatting
- [x] `Nexus.Output.Renderer` - terminal rendering with IO.ANSI
- [x] `Nexus.Telemetry` - event setup with default handlers
- [x] 70%+ coverage (102 tests for Output/Telemetry)

### 8.5 Implementation Notes
- Formatter supports :text and :json output formats
- Formatter supports :quiet/:normal/:verbose verbosity levels
- Renderer respects NO_COLOR and TERM=dumb environment variables
- Telemetry handlers made public to avoid local function warning
- All telemetry events follow [:nexus, :component, :action] naming

---

## Phase 9: Pre-flight & Dry-run

### 9.1 Implementation

```elixir
# lib/nexus/preflight/checker.ex
defmodule Nexus.Preflight.Checker do
  @spec run(pipeline(), keyword()) :: {:ok, report()} | {:error, report()}
end
```

### 9.2 Checks
- Config validation
- Host reachability (TCP ping)
- SSH authentication
- Sudo availability (if needed)
- Dry-run execution plan

### 9.3 Tests Required

**Unit Tests:**
- [ ] Each check type
- [ ] Report generation
- [ ] Skip logic for disabled checks

**Integration Tests:**
- [ ] Full preflight against Docker SSH
- [ ] Preflight with unreachable host
- [ ] Preflight with auth failure

### 9.4 Deliverables
- [ ] `Nexus.Preflight.Checker` module
- [ ] Dry-run execution plan display
- [ ] 80%+ coverage

---

## Phase 10: Packaging & Polish

### 10.1 Binary Packaging

```elixir
# mix.exs
def releases do
  [
    nexus: [
      steps: [:assemble, &Burrito.wrap/1],
      burrito: [
        targets: [
          linux_x86_64: [os: :linux, cpu: :x86_64],
          linux_aarch64: [os: :linux, cpu: :aarch64],
          darwin_x86_64: [os: :darwin, cpu: :x86_64],
          darwin_aarch64: [os: :darwin, cpu: :aarch64]
        ]
      ]
    ]
  ]
end
```

### 10.2 Final Polish
- [ ] README.md with quick start
- [ ] CHANGELOG.md
- [ ] nexus.exs.example with common patterns
- [ ] Shell completions (bash, zsh, fish)
- [ ] Install script (curl | sh)

### 10.3 Final Test Suite Run
- [ ] All unit tests passing
- [ ] All integration tests passing
- [ ] All property tests passing
- [ ] Performance benchmarks documented
- [ ] Coverage >= 80%
- [ ] Zero Dialyzer warnings
- [ ] Zero Credo issues
- [ ] Zero Sobelow findings

### 10.4 Deliverables
- [ ] Cross-platform binaries
- [ ] Installation documentation
- [ ] Shell completions
- [ ] All quality gates passing

---

## Future: Idempotency System (v0.2+)

> **Rationale:** Shell commands are error-prone. Users forget `mkdir -p` vs `mkdir`, 
> or append to files on retry. Nexus should provide built-in idempotent primitives
> so users don't have to think about it.

### Built-in Idempotent Commands

```elixir
task :setup do
  # Instead of: run "mkdir -p /opt/app"
  ensure_dir "/opt/app"
  
  # Instead of: run "id deploy || useradd deploy"  
  ensure_user "deploy", groups: ["sudo", "docker"]
  
  # Instead of: run "apt-get install -y nginx"
  ensure_package "nginx"
  
  # Instead of: run "systemctl enable --now nginx"
  ensure_service "nginx", state: :running, enabled: true
  
  # Instead of: run "cp config.conf /etc/app/"
  ensure_file "/etc/app/config.conf",
    source: "config.conf",
    mode: 0o644,
    owner: "deploy"
  
  # Instead of: run "echo 'line' >> /etc/file" (dangerous!)
  ensure_line "/etc/sudoers", "deploy ALL=(ALL) NOPASSWD:ALL"
  
  # Instead of: run "ln -sf /opt/app/bin /usr/local/bin/app"
  ensure_link "/usr/local/bin/app", to: "/opt/app/bin"
end
```

### How It Works

Each `ensure_*` command:
1. Checks current state on target
2. Compares to desired state
3. Only acts if different
4. Reports: `ok` (no change), `changed`, or `failed`

### Implementation Phases

**v0.2:** Core idempotent commands
- `ensure_dir`, `ensure_file`, `ensure_link`
- `ensure_line`, `ensure_block` (in file)
- `ensure_absent` (remove file/dir)

**v0.3:** System commands  
- `ensure_user`, `ensure_group`
- `ensure_package` (apt/yum/brew detection)
- `ensure_service` (systemd/launchd detection)

**v0.4:** Advanced
- `ensure_template` (EEx templating)
- `ensure_git` (clone/pull repo)
- `ensure_cron` (manage cron entries safely)
- Custom `ensure` macro for user-defined checks

### Annotation for Raw Commands

```elixir
task :deploy do
  # Idempotent commands - safe to retry
  ensure_dir "/opt/app"
  ensure_service "app", state: :stopped
  
  # Raw command - user asserts idempotency
  run "git pull", idempotent: true
  
  # Raw command - warn on retry, prompt on crash recovery
  run "curl -X POST https://slack.com/webhook", idempotent: false
  
  ensure_service "app", state: :running
end
```

### Dry-run Support

All `ensure_*` commands support dry-run mode:
```
$ nexus run setup --dry-run

[dry-run] ensure_dir /opt/app -> would create
[dry-run] ensure_user deploy -> already exists (ok)
[dry-run] ensure_file /etc/app/config.conf -> would update (content differs)
[dry-run] ensure_service nginx -> would start
```

---

## Test Infrastructure Summary

### Directory Structure

```
test/
├── unit/                          # Fast, isolated (~75% of tests)
│   ├── dsl/
│   │   ├── parser_test.exs
│   │   └── validator_test.exs
│   ├── dag_test.exs
│   ├── ssh/
│   │   ├── config_parser_test.exs
│   │   ├── auth_test.exs
│   │   └── pool_test.exs
│   ├── executor/
│   │   ├── local_test.exs
│   │   ├── task_runner_test.exs
│   │   └── pipeline_test.exs
│   ├── cli/
│   │   └── *_test.exs
│   └── output/
│       └── formatter_test.exs
├── integration/                   # Docker SSH required (~20%)
│   ├── ssh_connection_test.exs
│   ├── ssh_pool_test.exs
│   ├── remote_execution_test.exs
│   ├── full_pipeline_test.exs
│   └── preflight_test.exs
├── property/                      # StreamData property tests
│   ├── dsl_parser_test.exs
│   ├── dag_test.exs
│   └── host_parsing_test.exs
├── performance/                   # Benchmarks
│   ├── dag_benchmark.exs
│   ├── ssh_benchmark.exs
│   └── pipeline_benchmark.exs
└── support/
    ├── docker_ssh.ex              # Docker container helper
    ├── mocks.ex                   # Mox definitions
    ├── generators.ex              # StreamData generators
    ├── test_case.ex               # Custom test case
    └── fixtures/
        ├── valid_nexus.exs
        ├── invalid_cycle.exs
        └── ssh_keys/
```

### Test Commands

```bash
# Unit tests only (fast, no Docker)
mix test --only unit

# Integration tests (requires Docker)
docker-compose -f docker-compose.test.yml up -d
mix test --include integration

# Property tests
mix test --only property

# Performance benchmarks
mix run test/performance/dag_benchmark.exs
mix run test/performance/ssh_benchmark.exs

# Full suite with coverage
mix test --cover

# CI mode (all tests)
mix test --include integration
```

### Mox Behaviors

```elixir
# lib/nexus/ssh/behaviour.ex
defmodule Nexus.SSH.Behaviour do
  @callback connect(host(), opts()) :: {:ok, conn()} | {:error, term()}
  @callback exec(conn(), command(), opts()) :: {:ok, output(), exit_code()} | {:error, term()}
  @callback close(conn()) :: :ok
end

# test/support/mocks.ex
Mox.defmock(Nexus.SSH.Mock, for: Nexus.SSH.Behaviour)
```

---

## Critical Files

### Core Modules (in implementation order)

1. `lib/nexus/types.ex` - Type definitions
2. `lib/nexus/dsl/parser.ex` - DSL parsing
3. `lib/nexus/dsl/validator.ex` - Config validation
4. `lib/nexus/dag.ex` - Dependency graph
5. `lib/nexus/executor/local.ex` - Local execution
6. `lib/nexus/ssh/connection.ex` - SSH connections
7. `lib/nexus/ssh/pool.ex` - Connection pooling
8. `lib/nexus/ssh/auth.ex` - Authentication
9. `lib/nexus/ssh/config_parser.ex` - SSH config parsing
10. `lib/nexus/executor/task_runner.ex` - Task execution
11. `lib/nexus/executor/pipeline.ex` - Pipeline orchestration
12. `lib/nexus/cli.ex` - CLI entry point
13. `lib/nexus/output/formatter.ex` - Output formatting
14. `lib/nexus/telemetry.ex` - Telemetry setup
15. `lib/nexus/preflight/checker.ex` - Pre-flight checks

### Test Files (parallel with implementation)

Each module gets corresponding test files in unit/, integration/, and property/ as appropriate.

---

## Success Criteria for v0.1

- [ ] All PRD v0.1 requirements implemented
- [ ] 80%+ test coverage
- [ ] Zero Dialyzer warnings
- [ ] Zero Credo issues (strict mode)
- [ ] Zero Sobelow security findings
- [ ] Performance targets met:
  - SSH connection: <2s
  - Command overhead: <50ms
  - 100 concurrent connections stable
- [ ] Cross-platform binaries for Linux/macOS (x64/arm64)
- [ ] Documentation: README, examples, --help for all commands
