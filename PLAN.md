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

## Phase 4: Local Execution

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
- [ ] Run simple command, capture output
- [ ] Handle non-zero exit codes
- [ ] Timeout kills process
- [ ] Streaming output works
- [ ] Environment variables passed
- [ ] Working directory respected
- [ ] Handle commands with special characters

**Integration Tests:**
- [ ] Long-running command with streaming
- [ ] Command that produces large output
- [ ] Concurrent local executions

**Performance Tests:**
- [ ] 100 sequential commands: baseline
- [ ] 100 parallel commands: measure speedup
- [ ] Large output (10MB): memory stability

### 4.4 Deliverables
- [ ] `Nexus.Executor.Local` module
- [ ] Streaming output support
- [ ] Timeout handling
- [ ] 85%+ coverage

---

## Phase 5: SSH Connection Management

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
- [ ] Auth resolution priority (key > agent > password)
- [ ] SSH config parsing (Host, User, Port, IdentityFile)
- [ ] Host pattern matching
- [ ] Pool checkout/checkin
- [ ] Connection reuse

**Integration Tests (Docker SSH):**
- [ ] Connect with password
- [ ] Connect with key
- [ ] Execute command, get output
- [ ] Handle connection refused
- [ ] Handle auth failure
- [ ] Pool reuses connections
- [ ] Idle connections cleaned up
- [ ] Concurrent connections to same host
- [ ] Concurrent connections to different hosts

**Performance Tests:**
- [ ] Connection establishment time (<2s)
- [ ] Command overhead (<50ms)
- [ ] Pool efficiency with high concurrency
- [ ] Memory usage with 100 connections

### 5.4 Docker SSH Test Infrastructure

```yaml
# docker-compose.test.yml
services:
  ssh-ubuntu:
    image: linuxserver/openssh-server:latest
    ports: ["2222:2222"]
    environment:
      - PASSWORD_ACCESS=true
      - USER_PASSWORD=testpass
      - USER_NAME=testuser
  
  ssh-key-only:
    image: linuxserver/openssh-server:latest
    ports: ["2223:2222"]
    environment:
      - PUBLIC_KEY_FILE=/keys/test_key.pub
    volumes:
      - ./test/fixtures/ssh_keys:/keys:ro
```

### 5.5 Deliverables
- [ ] `Nexus.SSH.Connection` - connection management
- [ ] `Nexus.SSH.Pool` - NimblePool-based pooling
- [ ] `Nexus.SSH.Auth` - authentication resolution
- [ ] `Nexus.SSH.ConfigParser` - ~/.ssh/config parsing
- [ ] Docker-based integration tests
- [ ] 80%+ coverage

---

## Phase 6: Pipeline Execution

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
- [ ] Single local task execution
- [ ] Task with dependencies
- [ ] Parallel task execution
- [ ] Serial strategy execution
- [ ] Retry on failure
- [ ] Timeout handling
- [ ] Continue-on-error mode

**Integration Tests:**
- [ ] Full pipeline: build → test → deploy
- [ ] Pipeline with SSH tasks
- [ ] Mixed local and remote tasks
- [ ] Failure mid-pipeline
- [ ] Parallel remote execution

**Performance Tests:**
- [ ] 10 hosts × 10 commands: measure throughput
- [ ] 100 hosts × 1 command: connection efficiency
- [ ] Memory stability over long pipeline

### 6.4 Deliverables
- [ ] `Nexus.Executor.Pipeline` - orchestration
- [ ] `Nexus.Executor.TaskRunner` - task execution
- [ ] `Nexus.Executor.Supervisor` - supervision
- [ ] Retry with jitter
- [ ] 85%+ coverage

---

## Phase 7: CLI Interface

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
- [ ] Argument parsing for each command
- [ ] Flag handling
- [ ] Exit codes
- [ ] Help text generation
- [ ] Error message formatting

**Integration Tests:**
- [ ] Full CLI flow: run task
- [ ] Dry-run output format
- [ ] Quiet vs verbose modes
- [ ] JSON output format
- [ ] Invalid arguments handling

### 7.5 Deliverables
- [ ] `Nexus.CLI` with Optimus
- [ ] All commands implemented
- [ ] Exit codes per spec
- [ ] 75%+ coverage

---

## Phase 8: Output & Telemetry

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
- [ ] Format various message types
- [ ] Color stripping when NO_COLOR set
- [ ] JSON output structure
- [ ] Telemetry event emission

**Integration Tests:**
- [ ] Full pipeline output formatting
- [ ] Streaming output display
- [ ] Error display with context

### 8.4 Deliverables
- [ ] `Nexus.Output.Formatter` - message formatting
- [ ] `Nexus.Output.Renderer` - terminal rendering
- [ ] `Nexus.Telemetry` - event setup
- [ ] 70%+ coverage

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
