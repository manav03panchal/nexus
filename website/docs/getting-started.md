---
sidebar_position: 2
---

# Getting Started

This comprehensive guide walks you through installing Nexus, understanding its core concepts, and running your first tasks both locally and on remote servers.

## What is Nexus?

Nexus is a **distributed task runner** built in Elixir that enables you to:

- **Execute commands locally** - Run build scripts, tests, and local automation
- **Execute commands on remote hosts via SSH** - Deploy to servers, run maintenance tasks
- **Manage dependencies between tasks** - Define task DAGs (Directed Acyclic Graphs) for complex pipelines
- **Run tasks in parallel** - Execute across multiple hosts concurrently for maximum efficiency
- **Handle failures gracefully** - Retry logic, continue-on-error, and detailed error reporting

Nexus uses a simple Elixir-based DSL for configuration, making it easy to define complex deployment pipelines while maintaining readability.

## Prerequisites

Before installing Nexus, ensure you have:

### Required

- **Elixir 1.15+** - Nexus is built with Elixir and requires the runtime
  ```bash
  # Check Elixir version
  elixir --version
  # Should show: Elixir 1.15.0 or later
  ```

- **Erlang/OTP 25+** - Required by Elixir
  ```bash
  # Check Erlang version
  erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell
  # Should show: "25" or later
  ```

### Optional (for remote execution)

- **SSH client** - For connecting to remote hosts
- **SSH keys** - Ed25519, ECDSA, RSA, or DSA keys in `~/.ssh/`
- **SSH agent** - For convenient key management (optional but recommended)

### Installing Elixir

If you don't have Elixir installed:

```bash
# macOS (Homebrew)
brew install elixir

# Ubuntu/Debian
sudo apt-get install elixir

# Fedora
sudo dnf install elixir

# Arch Linux
sudo pacman -S elixir

# Windows (Chocolatey)
choco install elixir

# Universal (via asdf version manager - recommended)
asdf plugin add elixir
asdf install elixir latest
asdf global elixir latest
```

## Installation

### Method 1: Quick Install (Recommended)

The install script automatically clones, builds, and installs Nexus:

```bash
curl -fsSL https://raw.githubusercontent.com/manav03panchal/nexus/main/scripts/install.sh | bash
```

This will:
1. Check for Elixir installation
2. Clone the repository to a temp directory
3. Build the escript binary
4. Install to `/usr/local/bin` (or custom `NEXUS_INSTALL_DIR`)

**Custom install location:**

```bash
NEXUS_INSTALL_DIR=~/.local/bin curl -fsSL https://raw.githubusercontent.com/manav03panchal/nexus/main/scripts/install.sh | bash
```

### Method 2: From Source (Manual)

If you prefer to build manually:

```bash
# Clone the repository
git clone https://github.com/manav03panchal/nexus.git
cd nexus

# Fetch dependencies
mix deps.get

# Build the escript binary
mix escript.build

# Move to your PATH
sudo mv nexus /usr/local/bin/

# Or add to local bin (no sudo required)
mkdir -p ~/.local/bin
mv nexus ~/.local/bin/
# Add to PATH in ~/.bashrc or ~/.zshrc:
# export PATH="$HOME/.local/bin:$PATH"
```

### Verify Installation

```bash
nexus --version
# nexus 0.1.0

nexus --help
# Shows available commands and options
```

## Core Concepts

Before diving into examples, let's understand Nexus's key concepts:

### Tasks

A **task** is a named unit of work containing one or more commands:

```elixir
task :build do
  run "mix compile"
  run "mix test"
end
```

Tasks can:
- Run on `:local` (default) or on remote hosts
- Depend on other tasks (run after dependencies complete)
- Execute commands in sequence

### Hosts

A **host** represents a remote machine you can SSH into:

```elixir
host :web1, "deploy@192.168.1.10"        # user@hostname
host :web2, "deploy@192.168.1.11:2222"   # with custom port
host :web3, "web3.example.com"            # hostname only (uses defaults)
```

### Groups

A **group** is a named collection of hosts for targeting multiple machines:

```elixir
group :webservers, [:web1, :web2, :web3]
group :databases, [:db_primary, db_replica]
```

### Dependencies

Tasks can depend on other tasks using the `deps` option:

```elixir
task :test, deps: [:compile] do
  run "mix test"
end

task :deploy, deps: [:test, :build] do
  run "deploy.sh"
end
```

Nexus automatically resolves dependencies using a DAG (Directed Acyclic Graph) and executes tasks in the correct order.

### Execution Strategies

When a task runs on multiple hosts, you can control execution:

- `:parallel` (default) - Run on all hosts concurrently
- `:serial` - Run on hosts one at a time

```elixir
task :restart, on: :webservers, strategy: :serial do
  run "systemctl restart app", sudo: true
end
```

## Your First Configuration

### Step 1: Initialize a Config File

Navigate to your project directory and create a configuration:

```bash
cd /path/to/your/project
nexus init
```

This creates a `nexus.exs` template. Let's replace it with a practical example.

### Step 2: Create a Simple Local Config

Create or edit `nexus.exs`:

```elixir
# nexus.exs - Local build pipeline example

# Configuration (optional - these are defaults)
config :nexus,
  command_timeout: 60_000,    # 60 seconds per command
  continue_on_error: false     # Stop on first failure

# Step 1: Install dependencies
task :deps do
  run "mix deps.get"
end

# Step 2: Compile (depends on deps)
task :compile, deps: [:deps] do
  run "mix compile --warnings-as-errors"
end

# Step 3: Run tests (depends on compile)
task :test, deps: [:compile] do
  run "mix test"
end

# Step 4: Build release (depends on test)
task :build, deps: [:test] do
  run "MIX_ENV=prod mix release --overwrite"
end

# Convenience task to run everything
task :all, deps: [:build] do
  run "echo 'Build complete!'"
end
```

### Step 3: Validate Your Configuration

Always validate before running:

```bash
nexus validate
```

Expected output:
```
Configuration valid: nexus.exs

Summary:
  Tasks:  5
  Hosts:  0
  Groups: 0
```

### Step 4: List Available Tasks

See what tasks are defined:

```bash
nexus list
```

Expected output:
```
Tasks
========================================
  deps
    1 command
  compile (deps: deps)
    1 command
  test (deps: compile)
    1 command
  build (deps: test)
    1 command
  all (deps: build)
    1 command
```

### Step 5: Preview Execution (Dry Run)

See what would happen without actually running:

```bash
nexus run all --dry-run
```

Expected output:
```
Execution Plan
========================================
Total tasks: 5

Phase 1: deps
Phase 2: compile
Phase 3: test
Phase 4: build
Phase 5: all
```

Note how Nexus resolved the dependency chain and organized tasks into phases.

### Step 6: Run Tasks

Execute the full pipeline:

```bash
nexus run all
```

Expected output:
```
[ok] Task: deps
  Host: local (ok)
    [+] $ mix deps.get
        Resolving Hex dependencies...
        ... output ...

[ok] Task: compile
  Host: local (ok)
    [+] $ mix compile --warnings-as-errors
        Compiling 42 files (.ex)
        Generated myapp app

[ok] Task: test
  Host: local (ok)
    [+] $ mix test
        Running ExUnit...
        42 tests, 0 failures

[ok] Task: build
  Host: local (ok)
    [+] $ MIX_ENV=prod mix release --overwrite
        * assembling myapp-0.1.0 on MIX_ENV=prod
        Release created at _build/prod/rel/myapp

[ok] Task: all
  Host: local (ok)
    [+] $ echo 'Build complete!'
        Build complete!

========================================
Status: SUCCESS
Duration: 45230ms
Tasks: 5/5 succeeded
```

### Step 7: Run Individual Tasks

You can run specific tasks (and their dependencies):

```bash
# Run just the compile task (will also run deps first)
nexus run compile

# Run tests (will run deps and compile first)
nexus run test

# Run multiple specific tasks
nexus run deps compile
```

## Adding Remote Hosts

Now let's extend our configuration to deploy to remote servers.

### Step 1: Define Hosts

Add hosts to your `nexus.exs`:

```elixir
# nexus.exs - With remote hosts

# Define your servers
host :web1, "deploy@192.168.1.10"
host :web2, "deploy@192.168.1.11"
host :web3, "deploy@192.168.1.12:2222"  # Custom SSH port

host :db_primary, "admin@db1.example.com"
host :db_replica, "admin@db2.example.com"

# Group hosts for convenience
group :web, [:web1, :web2, :web3]
group :database, [:db_primary, :db_replica]
group :all_servers, [:web1, :web2, :web3, :db_primary, :db_replica]

# Local build tasks
task :build do
  run "MIX_ENV=prod mix release --overwrite"
end

# Deploy to web servers (runs in parallel across all hosts by default)
task :deploy, on: :web, deps: [:build] do
  run "mkdir -p /opt/myapp/releases"
  run "echo 'Deploying to $(hostname)...'"
end

# Run database migrations (on primary only)
task :migrate, on: :db_primary, deps: [:deploy] do
  run "/opt/myapp/bin/myapp eval 'MyApp.Release.migrate()'"
end

# Restart services one at a time to avoid downtime
task :restart, on: :web, strategy: :serial do
  run "systemctl restart myapp", sudo: true
  run "sleep 5"  # Wait for service to start
  run "curl -f http://localhost:4000/health"  # Health check
end

# Check status on all servers
task :status, on: :all_servers do
  run "hostname && uptime"
end
```

### Step 2: Configure SSH Authentication

Nexus supports multiple authentication methods:

#### Using SSH Keys (Recommended)

Nexus automatically looks for keys in `~/.ssh/`:
- `~/.ssh/id_ed25519` (preferred)
- `~/.ssh/id_ecdsa`
- `~/.ssh/id_rsa`
- `~/.ssh/id_dsa`

```bash
# Generate an Ed25519 key (recommended)
ssh-keygen -t ed25519 -C "deploy@nexus" -f ~/.ssh/deploy_key

# Copy to your servers
ssh-copy-id -i ~/.ssh/deploy_key.pub deploy@192.168.1.10
ssh-copy-id -i ~/.ssh/deploy_key.pub deploy@192.168.1.11
```

#### Using SSH Agent

If you use an SSH agent, Nexus will automatically use it:

```bash
# Start agent (if not running)
eval "$(ssh-agent -s)"

# Add your key
ssh-add ~/.ssh/deploy_key
```

#### Specifying a Key on Command Line

```bash
nexus run deploy -i ~/.ssh/deploy_key
```

### Step 3: Run Pre-flight Checks

Before deploying, verify connectivity:

```bash
nexus preflight deploy
```

Expected output:
```
Pre-flight Checks
----------------------------------------
[ok] config: Configuration is valid
     Tasks: 4, Hosts: 5, Groups: 3
[ok] hosts: All 3 host(s) reachable
     web1: reachable
     web2: reachable
     web3: reachable
[ok] ssh: SSH authentication OK for 3 host(s)
     web1: ok
     web2: ok
     web3: ok
[ok] tasks: All requested tasks found

Execution Plan
----------------------------------------
Phase 1:
  - build [local] (1 cmd, parallel)
Phase 2:
  - deploy [web1, web2, web3] (2 cmd, parallel)

========================================
All checks passed (1245ms)
```

### Step 4: Deploy

```bash
# Preview first
nexus run deploy --dry-run

# Then execute
nexus run deploy -i ~/.ssh/deploy_key
```

Expected output:
```
[ok] Task: build
  Host: local (ok)
    [+] $ MIX_ENV=prod mix release --overwrite
        * assembling myapp-0.1.0 on MIX_ENV=prod
        Release created at _build/prod/rel/myapp

[ok] Task: deploy
  Host: web1 (ok)
    [+] $ mkdir -p /opt/myapp/releases
    [+] $ echo 'Deploying to $(hostname)...'
        Deploying to web1...
  Host: web2 (ok)
    [+] $ mkdir -p /opt/myapp/releases
    [+] $ echo 'Deploying to $(hostname)...'
        Deploying to web2...
  Host: web3 (ok)
    [+] $ mkdir -p /opt/myapp/releases
    [+] $ echo 'Deploying to $(hostname)...'
        Deploying to web3...

========================================
Status: SUCCESS
Duration: 3421ms
Tasks: 2/2 succeeded
```

## Command Options Reference

Here's a quick reference for common command-line options:

| Option | Short | Description |
|--------|-------|-------------|
| `--config FILE` | `-c` | Path to config file (default: `nexus.exs`) |
| `--dry-run` | `-n` | Show what would run without executing |
| `--verbose` | `-v` | Show detailed output including timings |
| `--quiet` | `-q` | Minimal output |
| `--identity FILE` | `-i` | SSH private key file |
| `--user USER` | `-u` | SSH username |
| `--parallel-limit N` | `-p` | Max parallel tasks (default: 10) |
| `--continue-on-error` | | Continue on task failure |
| `--format FORMAT` | | Output format: `text` or `json` |
| `--plain` | | Disable colors |

## Understanding Output

### Success Output

```
[ok] Task: taskname
  Host: hostname (ok)
    [+] $ command that was run
        output from command
        more output...
```

- `[ok]` - Task completed successfully
- `[+]` - Command succeeded (exit code 0)
- Indented lines show command output

### Failure Output

```
[FAILED] Task: taskname
  Host: hostname (failed)
    [x] $ command that failed
        error output...
        (exit: 1, 234ms, attempts: 3)
```

- `[FAILED]` - Task had errors
- `[x]` - Command failed (non-zero exit code)
- Shows exit code, duration, and retry attempts

### Verbose Mode

Add `--verbose` for extra details:

```bash
nexus run deploy --verbose
```

Shows:
- Connection information
- Timing for each command
- Retry attempts
- Exit codes

## Handling Failures

### Default Behavior

By default, Nexus stops on the first failure:

```bash
nexus run deploy
# If deploy fails, no subsequent tasks run
```

### Continue on Error

To continue despite failures:

```bash
nexus run deploy --continue-on-error
```

Or in config:

```elixir
config :nexus,
  continue_on_error: true
```

### Retry Logic

Commands can be configured to retry on failure:

```elixir
task :flaky_deploy, on: :web do
  run "deploy.sh", retries: 3, retry_delay: 5_000
end
```

This will:
1. Run `deploy.sh`
2. If it fails, wait 5 seconds
3. Retry up to 3 more times
4. Use exponential backoff (5s, 10s, 20s)

## JSON Output

For scripting and CI/CD integration:

```bash
nexus run deploy --format json
```

Output:
```json
{
  "status": "ok",
  "duration_ms": 3421,
  "tasks_run": 2,
  "tasks_succeeded": 2,
  "tasks_failed": 0,
  "aborted_at": null
}
```

## Troubleshooting

### "Command not found: nexus"

Ensure the binary is in your PATH:

```bash
# Check if nexus is in PATH
which nexus

# If not, add to PATH
export PATH="/usr/local/bin:$PATH"
```

### "Config file not found: nexus.exs"

Create a config file or specify the path:

```bash
nexus init                           # Create default
nexus run task -c /path/to/nexus.exs  # Or specify path
```

### "SSH connection refused"

1. Verify the host is reachable: `ping hostname`
2. Verify SSH port is open: `nc -zv hostname 22`
3. Check SSH config: `ssh -v user@hostname`

### "SSH authentication failed"

1. Ensure your key is added to the remote host's `~/.ssh/authorized_keys`
2. Check key permissions: `chmod 600 ~/.ssh/id_ed25519`
3. Use verbose mode: `nexus run task --verbose`
4. Specify key explicitly: `nexus run task -i ~/.ssh/mykey`

## Next Steps

Now that you're up and running, explore:

- **[Configuration Reference](configuration.md)** - Complete DSL documentation
- **[CLI Reference](cli.md)** - All commands, flags, and options
- **[SSH Configuration](ssh.md)** - Advanced SSH setup and troubleshooting
- **[Examples](examples.md)** - Real-world deployment pipelines
- **[Architecture](architecture.md)** - How Nexus works internally
- **[Troubleshooting](troubleshooting.md)** - Common issues and solutions
