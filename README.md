# Nexus

A distributed task runner for Elixir with SSH remote execution, DAG-based dependencies, and a simple DSL.

## Features

- **Local & Remote Execution** - Run commands locally or on remote hosts via SSH
- **DAG Dependencies** - Define task dependencies with automatic parallel execution
- **Connection Pooling** - Efficient SSH connection reuse with NimblePool
- **Retry Logic** - Exponential backoff with jitter for failed commands
- **Simple DSL** - Define hosts, groups, and tasks in a single `nexus.exs` file

## Status

**Work in Progress** - Core functionality complete through Phase 6:

- [x] DSL Parser & Validator
- [x] DAG Resolution
- [x] Local Execution
- [x] SSH Connection Management
- [x] Pipeline Execution
- [ ] CLI Interface (Phase 7)
- [ ] Output & Telemetry (Phase 8)
- [ ] Pre-flight & Dry-run (Phase 9)
- [ ] Binary Packaging (Phase 10)

## Quick Example

```elixir
# nexus.exs

config :nexus,
  default_user: "deploy",
  connect_timeout: 10_000

host :web1, "web1.example.com"
host :web2, "web2.example.com"
group :web, [:web1, :web2]

task :build do
  run "mix deps.get"
  run "mix compile"
end

task :test, deps: [:build] do
  run "mix test"
end

task :deploy, deps: [:test], on: :web do
  run "cd /app && git pull"
  run "mix compile"
  run "sudo systemctl restart myapp", sudo: true
end
```

## Installation

```elixir
def deps do
  [
    {:nexus, "~> 0.1.0"}
  ]
end
```

## Usage

```bash
# Run a task
mix nexus run deploy

# Dry run (show execution plan)
mix nexus run deploy --dry-run

# Run with verbose output
mix nexus run deploy --verbose
```

## Configuration

See `nexus.exs.example` for a complete configuration reference.

### Hosts

```elixir
# Simple hostname
host :web1, "web1.example.com"

# With user
host :web2, "deploy@web2.example.com"

# With user and port
host :db, "admin@db.example.com:2222"
```

### Groups

```elixir
group :web, [:web1, :web2]
group :all, [:web1, :web2, :db]
```

### Tasks

```elixir
# Local task
task :build do
  run "mix compile"
end

# Remote task with dependencies
task :deploy, deps: [:build], on: :web do
  run "git pull"
  run "mix compile"
end

# Serial execution (one host at a time)
task :rolling_restart, on: :web, strategy: :serial do
  run "systemctl restart app"
end

# With retries
task :health_check, on: :web do
  run "curl -f http://localhost:4000/health",
    retries: 3,
    retry_delay: 5_000
end
```

## Development

```bash
# Run tests
mix test

# Run with integration tests (requires Docker)
docker compose -f docker-compose.test.yml up -d
mix test --include integration

# Run quality checks
mix format --check-formatted
mix credo --strict
mix dialyzer
```

## Performance

Benchmarks on M1 Pro:

| Metric | Result |
|--------|--------|
| SSH connection | ~102ms |
| Command overhead | ~1.4ms |
| 10 sequential commands | ~14ms |
| 10 parallel connections | ~177ms |

## License

MIT
