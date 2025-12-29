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

Requires [Elixir](https://elixir-lang.org/install.html) 1.15+.

```bash
curl -fsSL https://raw.githubusercontent.com/manav03panchal/nexus/main/scripts/install.sh | bash
```

Or build from source:

```bash
git clone https://github.com/manav03panchal/nexus.git
cd nexus
mix deps.get
mix escript.build
sudo mv nexus /usr/local/bin/
```

## Quick Start

```bash
# Create a config file
nexus init

# Edit nexus.exs, then validate
nexus validate

# List tasks
nexus list

# Run a task
nexus run build
```

## Documentation

- [Getting Started](docs/getting-started.md)
- [Configuration Reference](docs/configuration.md)
- [CLI Reference](docs/cli.md)
- [Examples](docs/examples.md)

## Example

```elixir
# nexus.exs

host :web1, "deploy@192.168.1.10"
host :web2, "deploy@192.168.1.11"

group :web, [:web1, :web2]

task :build, on: :local do
  run "mix release"
end

task :deploy, on: :web, deps: [:build] do
  run "systemctl restart myapp", sudo: true
end
```

```bash
$ nexus run deploy -i ~/.ssh/deploy_key

[ok] Task: build
  Host: local (ok)
    [+] $ mix release
        Release created!

[ok] Task: deploy
  Host: web1 (ok)
    [+] $ systemctl restart myapp
  Host: web2 (ok)
    [+] $ systemctl restart myapp

========================================
Status: SUCCESS
Duration: 2340ms
Tasks: 2/2 succeeded
```

## License

MIT
