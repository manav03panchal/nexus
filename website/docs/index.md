---
slug: /
sidebar_position: 1
title: Introduction
---

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

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/manav03panchal/nexus/main/scripts/install.sh | bash
```

Requires [Elixir](https://elixir-lang.org/install.html) 1.15+.

## Quick Start

```bash
# Create a config file
nexus init

# Validate it
nexus validate

# Run a task
nexus run build
```

## Example

```elixir
# nexus.exs

host :web1, "deploy@192.168.1.10"
host :web2, "deploy@192.168.1.11"

group :web, [:web1, :web2]

task :build do
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

## Next Steps

- [Getting Started](getting-started.md) - Full tutorial
- [Configuration](configuration.md) - DSL reference
- [CLI Reference](cli.md) - All commands
- [Examples](examples.md) - Real-world configs
