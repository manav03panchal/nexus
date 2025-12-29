# Getting Started

This guide walks you through installing Nexus and running your first task.

## Prerequisites

- [Elixir](https://elixir-lang.org/install.html) 1.15 or later
- SSH access to remote hosts (for remote execution)

## Installation

### Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/manav03panchal/nexus/main/scripts/install.sh | bash
```

### From Source

```bash
git clone https://github.com/manav03panchal/nexus.git
cd nexus
mix deps.get
mix escript.build
sudo mv nexus /usr/local/bin/
```

### Verify Installation

```bash
nexus --version
```

## Your First Config

Create a `nexus.exs` file:

```bash
nexus init
```

This creates a template. Let's replace it with a simple example:

```elixir
# nexus.exs

# A simple local build task
task :build do
  run "echo 'Building...'"
  run "echo 'Done!'"
end

# Task with dependencies
task :test, deps: [:build] do
  run "echo 'Running tests...'"
end

# Full pipeline
task :deploy, deps: [:test] do
  run "echo 'Deploying...'"
end
```

## Validate Your Config

```bash
nexus validate
```

Output:
```
Configuration valid: nexus.exs

Summary:
  Tasks:  3
  Hosts:  0
  Groups: 0
```

## List Tasks

```bash
nexus list
```

Output:
```
Tasks
========================================
  build
    2 commands
  test (deps: build)
    1 command
  deploy (deps: test)
    1 command
```

## Run a Task

```bash
nexus run build
```

Output:
```
[ok] Task: build
  Host: local (ok)
    [+] $ echo 'Building...'
        Building...
    [+] $ echo 'Done!'
        Done!

========================================
Status: SUCCESS
Duration: 12ms
Tasks: 1/1 succeeded
```

## Run with Dependencies

When you run `deploy`, Nexus automatically runs `build` and `test` first:

```bash
nexus run deploy
```

Output:
```
[ok] Task: build
  Host: local (ok)
    [+] $ echo 'Building...'
        Building...
    [+] $ echo 'Done!'
        Done!

[ok] Task: test
  Host: local (ok)
    [+] $ echo 'Running tests...'
        Running tests...

[ok] Task: deploy
  Host: local (ok)
    [+] $ echo 'Deploying...'
        Deploying...

========================================
Status: SUCCESS
Duration: 18ms
Tasks: 3/3 succeeded
```

## Preview with Dry Run

See what would run without executing:

```bash
nexus run deploy --dry-run
```

Output:
```
Execution Plan
========================================
Total tasks: 3

Phase 1: build
Phase 2: test
Phase 3: deploy
```

## Adding Remote Hosts

Now let's add SSH hosts:

```elixir
# nexus.exs

# Define hosts
host :server1, "deploy@192.168.1.10"
host :server2, "deploy@192.168.1.11"

# Group them
group :servers, [:server1, :server2]

# Local build
task :build do
  run "echo 'Building...'"
end

# Deploy to all servers
task :deploy, on: :servers, deps: [:build] do
  run "hostname"
  run "echo 'Deployed!'"
end
```

## Pre-flight Checks

Before running remote tasks, verify connectivity:

```bash
nexus preflight deploy
```

Output:
```
Pre-flight Checks
----------------------------------------
[ok] config: Configuration is valid
[ok] hosts: All 2 host(s) reachable
[ok] ssh: SSH auth successful for 2 host(s)
[ok] tasks: 2 task(s) available

========================================
All checks passed (523ms)
```

## Run with SSH Key

```bash
nexus run deploy -i ~/.ssh/my_key
```

Output:
```
[ok] Task: build
  Host: local (ok)
    [+] $ echo 'Building...'
        Building...

[ok] Task: deploy
  Host: server1 (ok)
    [+] $ hostname
        server1
    [+] $ echo 'Deployed!'
        Deployed!
  Host: server2 (ok)
    [+] $ hostname
        server2
    [+] $ echo 'Deployed!'
        Deployed!

========================================
Status: SUCCESS
Duration: 245ms
Tasks: 2/2 succeeded
```

## Next Steps

- [Configuration Reference](configuration.md) - All DSL options
- [CLI Reference](cli.md) - All commands and flags
- [Examples](examples.md) - Real-world examples
