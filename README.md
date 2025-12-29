# Nexus

A distributed task runner with SSH support, DAG-based dependency resolution, and parallel execution.

## Features

- **DAG-based dependencies** - Define task dependencies and execute in optimal order
- **SSH remote execution** - Run commands on remote hosts with connection pooling
- **Parallel execution** - Execute independent tasks concurrently
- **Host groups** - Organize hosts into groups for targeted deployment
- **Retry logic** - Automatic retries with exponential backoff
- **Pre-flight checks** - Validate configuration and connectivity before execution
- **Dry-run mode** - Preview execution plan without running commands

## Installation

### From Source (Recommended)

Requires Elixir 1.15+.

```bash
git clone https://github.com/manav03panchal/nexus.git
cd nexus
./scripts/build.sh
```

The `nexus` binary will be created in the current directory. Move it to your PATH:

```bash
sudo mv nexus /usr/local/bin/
# or
mv nexus ~/.local/bin/
```

### Pre-built Binaries

Download from the [releases page](https://github.com/manav03panchal/nexus/releases):

| Platform | Binary |
|----------|--------|
| Linux (Intel/AMD) | `nexus-linux-x86_64` |
| Linux (ARM) | `nexus-linux-aarch64` |
| macOS (Intel) | `nexus-darwin-x86_64` |
| macOS (Apple Silicon) | `nexus-darwin-aarch64` |

### Install Script

For automated installation (requires `GITHUB_TOKEN` for private repos):

```bash
# Clone and run install script
git clone https://github.com/manav03panchal/nexus.git
cd nexus
GITHUB_TOKEN=ghp_xxx ./scripts/install.sh
```

## Quick Start

### 1. Create a Configuration File

Create `nexus.exs` in your project:

```elixir
# Define hosts
host :web1, "deploy@192.168.1.10"
host :web2, "deploy@192.168.1.11:2222"

# Group hosts
group :web, [:web1, :web2]

# Configuration
config :nexus,
  parallel_limit: 10,
  default_timeout: 30_000

# Define tasks
task :build, on: :local do
  run "mix deps.get"
  run "mix compile"
  run "mix release"
end

task :upload, on: :web, deps: [:build] do
  run "scp _build/prod/rel/myapp.tar.gz {host}:/opt/myapp/"
end

task :deploy, on: :web, deps: [:upload] do
  run "cd /opt/myapp && tar -xzf myapp.tar.gz"
  run "systemctl restart myapp", sudo: true
end
```

### 2. Validate Configuration

```bash
nexus validate
```

### 3. Run Pre-flight Checks

```bash
nexus preflight deploy
```

### 4. Execute Tasks

```bash
# Run a single task
nexus run build

# Run multiple tasks
nexus run build deploy

# Dry-run to see execution plan
nexus run deploy --dry-run

# Continue on errors
nexus run deploy --continue-on-error

# Verbose output
nexus run deploy --verbose
```

## Commands

| Command | Description |
|---------|-------------|
| `nexus run <tasks>` | Execute one or more tasks |
| `nexus list` | List all defined tasks |
| `nexus validate` | Validate configuration file |
| `nexus preflight <tasks>` | Run pre-flight checks |
| `nexus init` | Create a template nexus.exs |
| `nexus --help` | Show help |
| `nexus --version` | Show version |

## CLI Options

### `nexus run`

| Option | Description |
|--------|-------------|
| `-n, --dry-run` | Show execution plan without running |
| `-v, --verbose` | Increase output verbosity |
| `-q, --quiet` | Minimal output |
| `-c, --config FILE` | Path to config file (default: nexus.exs) |
| `-i, --identity FILE` | SSH private key file |
| `-u, --user USER` | SSH user override |
| `-p, --parallel-limit N` | Max parallel tasks (default: 10) |
| `--continue-on-error` | Don't stop on task failure |
| `--format FORMAT` | Output format: text, json |
| `--plain` | Disable colors |

## DSL Reference

### Hosts

```elixir
# Simple host
host :server1, "user@hostname"

# With custom port
host :server2, "user@hostname:2222"
```

### Groups

```elixir
group :production, [:web1, :web2, :db1]
group :staging, [:staging1]
```

### Tasks

```elixir
task :name, on: :target, deps: [:dep1, :dep2] do
  # Run commands
  run "command"
  
  # With sudo
  run "systemctl restart app", sudo: true
  
  # With timeout (ms)
  run "long-command", timeout: 60_000
  
  # With retries
  run "flaky-command", retries: 3, retry_delay: 1_000
end
```

### Task Options

| Option | Description | Default |
|--------|-------------|---------|
| `on` | Target host, group, or `:local` | `:local` |
| `deps` | List of dependency task names | `[]` |
| `timeout` | Task timeout in ms | `30_000` |
| `strategy` | `:parallel` or `:serial` for multi-host | `:parallel` |

### Configuration

```elixir
config :nexus,
  parallel_limit: 10,        # Max concurrent tasks
  default_timeout: 30_000,   # Default task timeout (ms)
  ssh_options: [             # SSH connection options
    connect_timeout: 5_000
  ]
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `NEXUS_CONFIG` | Default config file path |
| `NO_COLOR` | Disable colored output |

## Exit Codes

| Code | Description |
|------|-------------|
| 0 | Success |
| 1 | General error / task failure |
| 2 | Configuration error |
| 3 | Connection error |

## Development

```bash
# Run tests
mix test

# Run with coverage
mix coveralls.html

# Quality checks
mix quality

# Build escript
mix escript.build

# Build release binaries (requires Zig)
MIX_ENV=prod mix release
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes with tests
4. Ensure all checks pass: `mix quality && mix test`
5. Submit a pull request
