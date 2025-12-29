---
sidebar_position: 3
---

# Configuration Reference

Nexus uses an Elixir DSL in `nexus.exs` for configuration.

## Hosts

Define SSH hosts for remote execution.

```elixir
# Basic: hostname only (uses current user)
host :server, "example.com"

# With user
host :web1, "deploy@example.com"

# With user and port
host :web2, "deploy@example.com:2222"
```

### Host Options

The host string format is: `[user@]hostname[:port]`

| Part | Required | Default |
|------|----------|---------|
| user | No | Current user or `default_user` from config |
| hostname | Yes | - |
| port | No | 22 or `default_port` from config |

## Groups

Organize hosts into groups for targeting.

```elixir
host :web1, "deploy@web1.example.com"
host :web2, "deploy@web2.example.com"
host :db1, "admin@db1.example.com"

group :web, [:web1, :web2]
group :database, [:db1]
group :all, [:web1, :web2, :db1]
```

## Configuration

Global settings for Nexus.

```elixir
config :nexus,
  default_user: "deploy",
  default_port: 22,
  connect_timeout: 5_000,
  command_timeout: 30_000,
  max_connections: 10,
  continue_on_error: false
```

### Config Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `default_user` | string | current user | SSH user when not specified in host |
| `default_port` | integer | 22 | SSH port when not specified in host |
| `connect_timeout` | integer | 5000 | SSH connection timeout (ms) |
| `command_timeout` | integer | 30000 | Default command timeout (ms) |
| `max_connections` | integer | 10 | Max SSH connections per host |
| `continue_on_error` | boolean | false | Continue on task failure |

## Tasks

Define tasks with commands to execute.

```elixir
task :name do
  run "command"
end
```

### Task Options

```elixir
task :deploy,
  on: :web,              # Target: :local, host name, or group name
  deps: [:build, :test], # Dependencies (run first)
  timeout: 60_000,       # Task timeout in ms
  strategy: :parallel    # :parallel or :serial for multi-host
do
  run "command"
end
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `on` | atom | `:local` | Execution target |
| `deps` | list | `[]` | Task dependencies |
| `timeout` | integer | 30000 | Task timeout (ms) |
| `strategy` | atom | `:parallel` | Multi-host strategy |

### Execution Targets

- `:local` - Run on the local machine
- `:hostname` - Run on a specific host
- `:groupname` - Run on all hosts in a group

### Strategy

When running on multiple hosts:

- `:parallel` - Run on all hosts concurrently (default)
- `:serial` - Run on hosts one at a time

## Commands

Commands are defined inside tasks with `run`.

```elixir
task :example do
  # Basic command
  run "echo hello"
  
  # With sudo
  run "systemctl restart app", sudo: true
  
  # With specific sudo user
  run "command", sudo: true, user: "postgres"
  
  # With timeout
  run "long-command", timeout: 120_000
  
  # With retries
  run "flaky-command", retries: 3, retry_delay: 1_000
end
```

### Command Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `sudo` | boolean | false | Run with sudo |
| `user` | string | nil | Sudo user (requires `sudo: true`) |
| `timeout` | integer | 30000 | Command timeout (ms) |
| `retries` | integer | 0 | Number of retry attempts |
| `retry_delay` | integer | 1000 | Delay between retries (ms) |

## Environment Variables

Access environment variables with `env/1`:

```elixir
config :nexus,
  default_user: env("DEPLOY_USER")

host :prod, env("PROD_SERVER")

task :deploy do
  run "echo Deploying version #{env("VERSION")}"
end
```

## Full Example

```elixir
# nexus.exs

# Hosts
host :web1, "deploy@web1.prod.example.com"
host :web2, "deploy@web2.prod.example.com"
host :db, "admin@db.prod.example.com:2222"

# Groups
group :web, [:web1, :web2]
group :all, [:web1, :web2, :db]

# Config
config :nexus,
  default_user: "deploy",
  connect_timeout: 10_000,
  command_timeout: 60_000

# Tasks
task :deps do
  run "mix deps.get --only prod"
end

task :compile, deps: [:deps] do
  run "MIX_ENV=prod mix compile"
end

task :test, deps: [:compile] do
  run "mix test"
end

task :release, deps: [:test] do
  run "MIX_ENV=prod mix release --overwrite"
end

task :upload, on: :web, deps: [:release] do
  run "scp _build/prod/rel/myapp.tar.gz deploy@{host}:/opt/myapp/"
end

task :migrate, on: :db, deps: [:upload] do
  run "/opt/myapp/bin/myapp eval 'MyApp.Release.migrate()'"
end

task :restart, on: :web, deps: [:migrate] do
  run "systemctl restart myapp", sudo: true
end

task :deploy, deps: [:restart] do
  # Empty task that triggers the full pipeline
end
```

Run the full deployment:

```bash
nexus run deploy -i ~/.ssh/deploy_key
```
