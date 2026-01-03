---
sidebar_position: 3
---

# Configuration Reference

This document provides a complete reference for the Nexus DSL (Domain Specific Language) used in `nexus.exs` configuration files.

## Overview

Nexus uses an Elixir-based DSL for configuration, which means your config files are valid Elixir code. This provides:

- **Syntax highlighting** in any Elixir-aware editor
- **Environment variable access** via `System.get_env/1` or the `env()` helper
- **Conditional logic** using standard Elixir constructs
- **Code reuse** through variables and functions

## File Structure

A typical `nexus.exs` file has this structure:

```elixir
# =============================================================================
# CONFIGURATION - Global settings
# =============================================================================
config :nexus,
  default_user: "deploy",
  command_timeout: 60_000

# =============================================================================
# HOSTS - Define remote machines
# =============================================================================
host :web1, "deploy@web1.example.com"
host :web2, "deploy@web2.example.com:2222"

# =============================================================================
# GROUPS - Organize hosts into logical groups
# =============================================================================
group :webservers, [:web1, :web2]

# =============================================================================
# TASKS - Define units of work
# =============================================================================
task :deploy, on: :webservers, deps: [:build] do
  run "deploy.sh"
end
```

---

## config

The `config` macro sets global Nexus options.

### Syntax

```elixir
config :nexus, options
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `default_user` | `String.t()` | `nil` | Default SSH username when not specified in host |
| `default_port` | `pos_integer()` | `22` | Default SSH port when not specified in host |
| `connect_timeout` | `pos_integer()` | `10_000` | SSH connection timeout in milliseconds |
| `command_timeout` | `pos_integer()` | `60_000` | Default command execution timeout in milliseconds |
| `max_connections` | `pos_integer()` | `5` | Maximum SSH connections per host in the pool |
| `continue_on_error` | `boolean()` | `false` | Continue executing tasks if one fails |

### Examples

```elixir
# Basic configuration
config :nexus,
  default_user: "deploy",
  default_port: 22

# Production configuration with longer timeouts
config :nexus,
  default_user: "deploy",
  connect_timeout: 30_000,      # 30 seconds
  command_timeout: 300_000,     # 5 minutes
  max_connections: 20,
  continue_on_error: false

# Using environment variables
config :nexus,
  default_user: env("DEPLOY_USER") || "deploy",
  max_connections: String.to_integer(env("MAX_CONN") || "10")
```

### Option Details

#### `default_user`

The SSH username to use when not explicitly specified in a host definition:

```elixir
config :nexus,
  default_user: "deploy"

# This host will use "deploy" as the user
host :web1, "192.168.1.10"

# This host explicitly overrides to use "admin"
host :web2, "admin@192.168.1.11"
```

#### `default_port`

The SSH port to use when not explicitly specified:

```elixir
config :nexus,
  default_port: 2222

# All hosts will use port 2222 unless overridden
host :web1, "deploy@192.168.1.10"       # Uses port 2222
host :web2, "deploy@192.168.1.11:22"    # Explicitly uses port 22
```

#### `connect_timeout`

Maximum time to wait for SSH connection establishment:

```elixir
config :nexus,
  connect_timeout: 30_000   # 30 seconds

# Useful for hosts with slow network connections
# or when connecting through VPNs
```

#### `command_timeout`

Default maximum time for command execution:

```elixir
config :nexus,
  command_timeout: 300_000  # 5 minutes

# Can be overridden per-command:
task :long_running do
  run "backup.sh", timeout: 3_600_000  # 1 hour
end
```

#### `max_connections`

Maximum concurrent SSH connections per host:

```elixir
config :nexus,
  max_connections: 10

# Prevents overwhelming hosts with too many connections
# Connections are pooled and reused
```

#### `continue_on_error`

Controls pipeline behavior on task failure:

```elixir
# Stop immediately on first failure (default)
config :nexus,
  continue_on_error: false

# Continue executing remaining tasks
config :nexus,
  continue_on_error: true
```

---

## host

The `host` macro defines a remote machine for SSH connections.

### Syntax

```elixir
host name, connection_string
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | `atom()` | Unique identifier for this host |
| `connection_string` | `String.t()` | Connection details in various formats |

### Connection String Formats

```elixir
# Hostname only (uses defaults for user and port)
host :server1, "example.com"

# User and hostname
host :server2, "deploy@example.com"

# User, hostname, and port
host :server3, "deploy@example.com:2222"

# Hostname and port (no user)
host :server4, "example.com:2222"

# IP addresses work the same way
host :server5, "192.168.1.10"
host :server6, "admin@10.0.0.5:22"
```

### How Defaults Are Applied

When a connection string omits certain values, Nexus applies defaults:

```elixir
config :nexus,
  default_user: "deploy",
  default_port: 22

# Resulting host configurations:
host :h1, "example.com"
# → hostname: "example.com", user: "deploy", port: 22

host :h2, "admin@example.com"
# → hostname: "example.com", user: "admin", port: 22

host :h3, "example.com:2222"
# → hostname: "example.com", user: "deploy", port: 2222

host :h4, "admin@example.com:2222"
# → hostname: "example.com", user: "admin", port: 2222
```

### Host Names as Identifiers

The host name (first argument) is used to reference the host elsewhere:

```elixir
host :production_web, "deploy@web.prod.example.com"

# Reference in a group
group :production, [:production_web, :production_db]

# Reference in a task
task :deploy, on: :production_web do
  run "deploy.sh"
end
```

### Examples

```elixir
# Web servers
host :web1, "deploy@192.168.1.10"
host :web2, "deploy@192.168.1.11"
host :web3, "deploy@192.168.1.12:2222"

# Database servers
host :db_primary, "dba@db1.internal:5432"
host :db_replica, "dba@db2.internal:5432"

# Using environment variables for sensitive data
host :prod_web, "#{env("PROD_USER")}@#{env("PROD_HOST")}"

# Staging environment
host :staging, "deploy@staging.example.com"
```

---

## group

The `group` macro creates a named collection of hosts for targeting multiple machines with a single reference.

### Syntax

```elixir
group name, host_list
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | `atom()` | Unique identifier for this group |
| `host_list` | `[atom()]` | List of host names to include |

### Examples

```elixir
# Define hosts first
host :web1, "deploy@192.168.1.10"
host :web2, "deploy@192.168.1.11"
host :web3, "deploy@192.168.1.12"
host :db_primary, "admin@db1.example.com"
host :db_replica, "admin@db2.example.com"

# Create groups
group :webservers, [:web1, :web2, :web3]
group :databases, [:db_primary, :db_replica]
group :all_production, [:web1, :web2, :web3, :db_primary, :db_replica]

# Groups can reference the same hosts
group :tier1, [:web1, :db_primary]
group :tier2, [:web2, :db_replica]
```

### Using Groups in Tasks

```elixir
# Deploy to all web servers
task :deploy, on: :webservers do
  run "deploy.sh"
end

# Run on all production hosts
task :status, on: :all_production do
  run "systemctl status myapp"
end
```

### Validation

Nexus validates that all hosts referenced in a group exist:

```elixir
# This will fail validation - :web4 doesn't exist
group :webservers, [:web1, :web2, :web4]
# Error: group :webservers references unknown host :web4
```

---

## task

The `task` macro defines a unit of work containing one or more commands.

### Syntax

```elixir
task name, options \\ [] do
  run "command1"
  run "command2", command_options
end
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | `atom()` | Unique identifier for this task |
| `options` | `keyword()` | Task configuration (see below) |
| `block` | block | Contains `run` commands |

### Task Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `on` | `atom()` | `:local` | Host, group, or `:local` to run on |
| `deps` | `[atom()]` | `[]` | Tasks that must complete first |
| `strategy` | `:parallel \| :serial` | `:parallel` | How to execute across multiple hosts |
| `timeout` | `pos_integer()` | `300_000` | Overall task timeout in milliseconds |

### Basic Examples

```elixir
# Simple local task
task :build do
  run "mix compile"
  run "mix test"
end

# Task with dependencies
task :test, deps: [:compile] do
  run "mix test"
end

# Task on a specific host
task :deploy, on: :web1 do
  run "git pull origin main"
  run "mix deps.get --only prod"
end

# Task on a group of hosts
task :restart, on: :webservers do
  run "systemctl restart myapp", sudo: true
end
```

### The `on` Option

Specifies where the task runs:

```elixir
# Run locally (default)
task :build, on: :local do
  run "mix compile"
end

# Run on a single host
task :deploy, on: :web1 do
  run "deploy.sh"
end

# Run on all hosts in a group
task :status, on: :webservers do
  run "systemctl status myapp"
end
```

### The `deps` Option

Defines task dependencies (DAG):

```elixir
task :deps do
  run "mix deps.get"
end

task :compile, deps: [:deps] do
  run "mix compile"
end

task :test, deps: [:compile] do
  run "mix test"
end

# Multiple dependencies
task :deploy, deps: [:test, :build] do
  run "deploy.sh"
end
```

When you run `nexus run deploy`, Nexus will:
1. Build the dependency graph
2. Determine execution order: `deps` → `compile` → `test`/`build` → `deploy`
3. Execute tasks in phases (parallel within phases when possible)

### The `strategy` Option

Controls execution across multiple hosts:

```elixir
# Parallel execution (default)
# Runs on all hosts simultaneously
task :status, on: :webservers, strategy: :parallel do
  run "systemctl status myapp"
end

# Serial execution
# Runs on hosts one at a time (useful for rolling deployments)
task :restart, on: :webservers, strategy: :serial do
  run "systemctl restart myapp", sudo: true
  run "sleep 10"  # Wait for service to start
  run "curl -f http://localhost:4000/health"  # Health check
end
```

Serial execution is critical for zero-downtime deployments:

```elixir
task :rolling_deploy, on: :webservers, strategy: :serial do
  # Remove from load balancer
  run "consul maint -enable", sudo: true
  run "sleep 5"  # Drain connections
  
  # Deploy
  run "deploy.sh"
  
  # Health check
  run "curl -f http://localhost:4000/health"
  
  # Re-add to load balancer
  run "consul maint -disable", sudo: true
end
```

### The `timeout` Option

Sets the overall task timeout (in milliseconds):

```elixir
# Default: 5 minutes (300_000ms)
task :quick_task do
  run "echo hello"
end

# Custom timeout: 1 hour
task :long_backup, on: :db_primary, timeout: 3_600_000 do
  run "pg_dump myapp > /backups/dump.sql"
end
```

### Empty Tasks

Tasks can have no commands - useful for grouping dependencies:

```elixir
task :build do
  run "mix compile"
end

task :test, deps: [:build] do
  run "mix test"
end

task :lint, deps: [:build] do
  run "mix credo --strict"
end

# This task just ensures build, test, and lint all run
task :ci, deps: [:test, :lint] do
  # No commands - just a dependency aggregator
end
```

---

## Resources

Resources are **declarative, idempotent** primitives that describe the desired state of a system. Unlike imperative `run` commands, resources check current state before making changes.

### command

The `command` resource is the **recommended replacement for `run`** in task blocks. It supports idempotency guards that prevent unnecessary execution.

#### Syntax

```elixir
command cmd, options \\ []
```

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `creates` | `String.t()` | `nil` | Skip if this path exists |
| `removes` | `String.t()` | `nil` | Skip if this path doesn't exist |
| `unless` | `String.t()` | `nil` | Skip if this command succeeds (exit 0) |
| `onlyif` | `String.t()` | `nil` | Only run if this command succeeds (exit 0) |
| `sudo` | `boolean()` | `false` | Run with sudo |
| `user` | `String.t()` | `nil` | Run as specific user (with sudo) |
| `cwd` | `String.t()` | `nil` | Working directory |
| `env` | `map()` | `%{}` | Environment variables |
| `timeout` | `pos_integer()` | `60_000` | Timeout in milliseconds |
| `notify` | `atom()` | `nil` | Handler to trigger on change |

#### Examples

```elixir
task :setup, on: :webservers do
  # Always runs (like traditional run)
  command "echo hello"

  # Only runs if file doesn't exist (idempotent)
  command "tar -xzf app.tar.gz -C /opt/app",
    creates: "/opt/app/bin/app"

  # Only runs if file exists
  command "rm -rf /tmp/cache",
    removes: "/tmp/cache"

  # Only runs if check command fails (0 = skip)
  command "mix deps.get",
    unless: "mix deps.check",
    cwd: "/opt/app"

  # Only runs if check command succeeds (0 = run)
  command "systemctl restart app",
    onlyif: "systemctl is-active app"

  # With environment variables
  command "mix release",
    env: %{"MIX_ENV" => "prod"},
    cwd: "/opt/app"

  # With handler notification
  command "nginx -t", notify: :reload_nginx
end
```

### package

Manages system packages using the appropriate package manager (apt, yum, pacman, brew).

#### Syntax

```elixir
package name, options \\ []
```

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ensure` | `:present \| :absent \| :latest` | `:present` | Desired state |
| `version` | `String.t()` | `nil` | Specific version to install |
| `notify` | `atom()` | `nil` | Handler to trigger on change |

#### Examples

```elixir
task :install_deps, on: :webservers do
  package "nginx", ensure: :present
  package "postgresql-client", ensure: :latest
  package "old-package", ensure: :absent
  package "redis", version: "6.2.0"
end
```

### service

Manages system services (systemd, launchd, etc.).

#### Syntax

```elixir
service name, options \\ []
```

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ensure` | `:running \| :stopped` | `:running` | Desired state |
| `enable` | `boolean()` | `true` | Start on boot |
| `notify` | `atom()` | `nil` | Handler to trigger on change |

#### Examples

```elixir
task :configure_services, on: :webservers do
  service "nginx", ensure: :running, enable: true
  service "postgresql", ensure: :running
  service "old-service", ensure: :stopped, enable: false
end
```

### file

Manages files with content, permissions, and ownership.

#### Syntax

```elixir
file path, options
```

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ensure` | `:present \| :absent` | `:present` | Whether file should exist |
| `content` | `String.t()` | `nil` | File contents |
| `source` | `String.t()` | `nil` | Source file path |
| `mode` | `integer()` | `nil` | File permissions (e.g., `0o644`) |
| `owner` | `String.t()` | `nil` | File owner |
| `group` | `String.t()` | `nil` | File group |
| `notify` | `atom()` | `nil` | Handler to trigger on change |

#### Examples

```elixir
task :configure, on: :webservers do
  file "/etc/myapp/config.json",
    content: ~s({"port": 4000, "env": "production"}),
    mode: 0o644,
    owner: "deploy",
    notify: :restart_app

  file "/tmp/old-file", ensure: :absent
end
```

### directory

Manages directories with permissions and ownership.

#### Syntax

```elixir
directory path, options \\ []
```

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ensure` | `:present \| :absent` | `:present` | Whether directory should exist |
| `mode` | `integer()` | `nil` | Directory permissions |
| `owner` | `String.t()` | `nil` | Directory owner |
| `group` | `String.t()` | `nil` | Directory group |
| `recursive` | `boolean()` | `false` | Create parent directories |

#### Examples

```elixir
task :setup_dirs, on: :webservers do
  directory "/opt/myapp",
    owner: "deploy",
    group: "deploy",
    mode: 0o755

  directory "/opt/myapp/releases",
    recursive: true

  directory "/tmp/old-dir", ensure: :absent
end
```

### user

Manages system users.

#### Syntax

```elixir
user name, options \\ []
```

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ensure` | `:present \| :absent` | `:present` | Whether user should exist |
| `uid` | `integer()` | `nil` | User ID |
| `gid` | `integer()` | `nil` | Primary group ID |
| `home` | `String.t()` | `nil` | Home directory |
| `shell` | `String.t()` | `nil` | Login shell |
| `groups` | `[String.t()]` | `[]` | Supplementary groups |
| `system` | `boolean()` | `false` | Create as system user |

#### Examples

```elixir
task :setup_users, on: :webservers do
  user "deploy",
    home: "/home/deploy",
    shell: "/bin/bash",
    groups: ["sudo", "docker"]

  user "myapp",
    system: true,
    home: "/opt/myapp",
    shell: "/usr/sbin/nologin"
end
```

### group

Manages system groups.

#### Syntax

```elixir
group name, options \\ []
```

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ensure` | `:present \| :absent` | `:present` | Whether group should exist |
| `gid` | `integer()` | `nil` | Group ID |
| `system` | `boolean()` | `false` | Create as system group |

#### Examples

```elixir
task :setup_groups, on: :webservers do
  group "deploy", gid: 1001
  group "myapp", system: true
end
```

---

## run (Legacy)

:::warning Deprecated in Task Blocks
The `run` macro is **deprecated for use in task blocks**. Use the `command` resource instead for idempotent execution. `run` is still valid in handler blocks.
:::

The `run` macro adds a command to the current task.

### Syntax

```elixir
run command, options \\ []
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `command` | `String.t()` | Shell command to execute |
| `options` | `keyword()` | Command configuration (see below) |

### Command Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `sudo` | `boolean()` | `false` | Run command with sudo |
| `user` | `String.t()` | `nil` | User to run as (with sudo) |
| `timeout` | `pos_integer()` | `60_000` | Command timeout in milliseconds |
| `retries` | `non_neg_integer()` | `0` | Number of retry attempts on failure |
| `retry_delay` | `pos_integer()` | `1_000` | Delay between retries in milliseconds |

### Basic Examples

```elixir
# In handlers, run is still the recommended approach
handler :reload_nginx do
  run "systemctl reload nginx", sudo: true
end

# In tasks, prefer command resource instead
task :example do
  command "echo 'Hello, World!'"
  command "apt-get update", sudo: true
end
```

### The `sudo` Option

Runs the command with elevated privileges:

```elixir
task :maintenance, on: :webservers do
  # Standard sudo (as root)
  run "systemctl restart nginx", sudo: true
  
  # Sudo as specific user
  run "whoami", sudo: true, user: "postgres"
  # Runs: sudo -u postgres whoami
  
  # Multiple sudo commands
  run "apt-get update", sudo: true
  run "apt-get upgrade -y", sudo: true
end
```

**Important**: For sudo to work without password prompts, configure `/etc/sudoers`:

```
# Allow deploy user to run specific commands without password
deploy ALL=(ALL) NOPASSWD: /bin/systemctl restart nginx, /usr/bin/apt-get
```

### The `timeout` Option

Sets command-specific timeout:

```elixir
task :mixed_commands do
  # Quick command (default 60s timeout)
  run "echo 'Starting'"
  
  # Long command with extended timeout
  run "pg_dump database > backup.sql", timeout: 1_800_000  # 30 minutes
  
  # Quick verification
  run "ls -la backup.sql"
end
```

If a command exceeds its timeout:
- The process is killed
- The command is marked as failed
- Retry logic applies if configured

### The `retries` Option

Automatically retry failed commands:

```elixir
task :resilient_deploy do
  # Retry up to 3 times with 5 second delay
  run "curl -f https://api.example.com/health", retries: 3, retry_delay: 5_000
  
  # Retry with longer delay for slower operations
  run "deploy.sh", retries: 2, retry_delay: 30_000
end
```

Retry behavior:
- Uses **exponential backoff**: delay × 2^(attempt-1)
- Adds **20% jitter** to prevent thundering herd
- Example with `retry_delay: 5_000`:
  - Attempt 1: immediate
  - Attempt 2: ~5 seconds later
  - Attempt 3: ~10 seconds later
  - Attempt 4: ~20 seconds later

### Shell Features

Commands are executed in a shell, so you can use:

```elixir
task :shell_features do
  # Environment variables
  run "echo $HOME"
  run "export MY_VAR=value && echo $MY_VAR"
  
  # Pipes
  run "cat /var/log/syslog | grep error | tail -10"
  
  # Redirects
  run "echo 'log entry' >> /var/log/myapp.log"
  
  # Command substitution
  run "echo \"Current date: $(date)\""
  
  # Conditionals
  run "[ -f /tmp/lock ] && echo 'locked' || echo 'free'"
  
  # Multiple commands
  run "cd /opt/myapp && git pull && mix deps.get"
end
```

### Exit Codes

Commands are considered:
- **Successful**: Exit code 0
- **Failed**: Any non-zero exit code

```elixir
task :check_exit_codes do
  run "exit 0"    # Success
  run "exit 1"    # Failure - stops task (unless continue_on_error)
  run "false"     # Failure (false returns exit code 1)
  run "true"      # Success (true returns exit code 0)
end
```

---

## Tailscale Host Discovery

Nexus can automatically discover hosts from your Tailscale network using ACL tags.

### Syntax

```elixir
tailscale_hosts tag: "tag_name", as: :group_name, options
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `tag` | `String.t()` | **required** | Tailscale ACL tag to filter by (without "tag:" prefix) |
| `as` | `atom()` | **required** | Group name to assign discovered hosts to |
| `user` | `String.t()` | `nil` | SSH user for all discovered hosts |
| `online_only` | `boolean()` | `true` | Only include online peers |

### Requirements

- Tailscale must be installed and running on the local machine
- The `tailscale` CLI must be in PATH
- Hosts must have ACL tags configured in Tailscale admin console

### Examples

```elixir
# Discover all hosts with tag:webserver and add them to :web group
tailscale_hosts tag: "webserver", as: :web

# Discover database hosts with a specific SSH user
tailscale_hosts tag: "database", as: :db, user: "postgres"

# Include offline hosts too
tailscale_hosts tag: "all-servers", as: :fleet, online_only: false

# Use discovered groups in tasks
task :deploy, on: :web do
  command "deploy.sh"
end

task :backup, on: :db do
  command "pg_dump myapp > /backups/dump.sql"
end
```

### How It Works

1. Nexus runs `tailscale status --json` to get connected peers
2. Filters peers by the specified ACL tag
3. Creates a `Host` struct for each matching peer (using DNS name or Tailscale IP)
4. Adds all hosts to a group with the specified name

---

## Facts

Facts are automatically gathered system information about hosts. Use them for conditional logic based on OS, architecture, or other host properties.

### Available Facts

| Fact | Type | Description |
|------|------|-------------|
| `:os` | `atom()` | Operating system (`:linux`, `:darwin`, `:freebsd`) |
| `:os_family` | `atom()` | OS family (`:debian`, `:rhel`, `:arch`, `:alpine`, `:darwin`) |
| `:os_version` | `String.t()` | OS version (e.g., `"22.04"`, `"14.0"`) |
| `:hostname` | `String.t()` | Short hostname |
| `:fqdn` | `String.t()` | Fully qualified domain name |
| `:cpu_count` | `pos_integer()` | Number of CPU cores |
| `:memory_mb` | `non_neg_integer()` | Total memory in MB |
| `:arch` | `atom()` | CPU architecture (`:x86_64`, `:aarch64`, `:arm`) |
| `:kernel_version` | `String.t()` | Kernel version string |
| `:user` | `String.t()` | Current SSH user |

### Usage

```elixir
task :install_packages, on: :webservers do
  # Facts are available via the facts() function
  # Use conditional resources based on OS family
  
  # Debian/Ubuntu
  command "apt-get update && apt-get install -y nginx",
    onlyif: "test $(cat /etc/os-release | grep -c 'ID=ubuntu\\|ID=debian') -gt 0",
    sudo: true

  # RHEL/CentOS
  command "yum install -y nginx",
    onlyif: "test -f /etc/redhat-release",
    sudo: true
end

# Or use the package resource which auto-detects the package manager
task :install, on: :webservers do
  package "nginx"  # Uses apt, yum, or pacman automatically
end
```

### Gathering Facts

Facts are gathered lazily on first access per host and cached for the pipeline run.

```elixir
# Local facts (no SSH required)
{:ok, facts} = Nexus.Facts.Gatherer.gather_local()
# => %{os: :darwin, os_family: :darwin, cpu_count: 10, memory_mb: 32768, ...}
```

---

## Secrets

Nexus provides encrypted secret storage using AES-256-GCM. Secrets are stored in `~/.nexus/secrets.enc`.

### CLI Commands

```bash
# Initialize the secrets vault (first time only)
nexus secret init

# Set a secret
nexus secret set API_KEY sk-1234567890

# Get a secret
nexus secret get API_KEY

# List all secrets
nexus secret list

# Delete a secret
nexus secret delete API_KEY
```

### Using Secrets in Configuration

```elixir
# Access secrets via the secret() function
config :nexus,
  default_user: "deploy"

task :deploy, on: :webservers do
  # Secrets are retrieved at parse time
  command "curl -H 'Authorization: Bearer #{secret("API_KEY")}' https://api.example.com/deploy"
  
  # For runtime secrets, use environment variables
  command "deploy.sh",
    env: %{"API_KEY" => secret("API_KEY")}
end
```

### Security

- Secrets are encrypted with AES-256-GCM (authenticated encryption)
- Unique 12-byte IV for each encryption operation
- 16-byte authentication tag prevents tampering
- Master key derived from passphrase using PBKDF2-HMAC-SHA256 (100k iterations)
- Secrets file has restricted permissions (0600)

---

## Notifications

Send notifications to Slack, Discord, Microsoft Teams, or generic webhooks after pipeline completion.

### Syntax

```elixir
notify :name, options
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` | `String.t()` | **required** | Webhook URL |
| `on` | `:success \| :failure \| :always` | `:always` | When to send |
| `template` | `:slack \| :discord \| :teams \| :generic` | `:generic` | Message format |
| `headers` | `map()` | `%{}` | Additional HTTP headers |

### Examples

```elixir
# Slack notification on failure
notify :slack_alerts,
  url: env("SLACK_WEBHOOK_URL"),
  on: :failure,
  template: :slack

# Discord notification always
notify :discord_deploys,
  url: env("DISCORD_WEBHOOK_URL"),
  on: :always,
  template: :discord

# Microsoft Teams
notify :teams_channel,
  url: env("TEAMS_WEBHOOK_URL"),
  on: :success,
  template: :teams

# Generic JSON webhook with custom headers
notify :custom_webhook,
  url: "https://api.example.com/webhooks/deploy",
  on: :always,
  template: :generic,
  headers: %{"X-API-Key" => secret("WEBHOOK_API_KEY")}
```

### Message Templates

#### Slack
```json
{
  "attachments": [{
    "color": "#36a64f",
    "title": "Pipeline Succeeded",
    "fields": [
      {"title": "Duration", "value": "45s", "short": true},
      {"title": "Tasks", "value": "5", "short": true}
    ],
    "footer": "Nexus",
    "ts": 1234567890
  }]
}
```

#### Discord
```json
{
  "embeds": [{
    "title": "Pipeline Succeeded",
    "color": 3066993,
    "fields": [
      {"name": "Duration", "value": "45s", "inline": true},
      {"name": "Tasks", "value": "5", "inline": true}
    ],
    "footer": {"text": "Nexus"}
  }]
}
```

---

## env

The `env` function retrieves environment variable values.

### Syntax

```elixir
env(variable_name)
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `variable_name` | `String.t() \| atom()` | Name of the environment variable |

### Return Value

- Returns the variable value as a string if set
- Returns empty string `""` if not set

### Examples

```elixir
# In configuration
config :nexus,
  default_user: env("DEPLOY_USER") || "deploy",
  max_connections: String.to_integer(env("MAX_CONN") || "5")

# In host definitions
host :production, "#{env("PROD_USER")}@#{env("PROD_HOST")}"

# In tasks (at parse time, not runtime!)
task :deploy do
  run "echo Deploying as #{env("USER")}"
end
```

### Important: Parse Time vs Runtime

**`env()` is evaluated when the config file is parsed**, not when commands run:

```elixir
# This captures MY_VAR at parse time
task :example do
  run "echo #{env("MY_VAR")}"  # Evaluated when nexus.exs is loaded
end

# For runtime environment variables, use shell syntax:
task :runtime_example do
  run "echo $MY_VAR"            # Evaluated when command runs
end
```

### Common Patterns

```elixir
# Required environment variable with error
deploy_user = env("DEPLOY_USER")
if deploy_user == "", do: raise "DEPLOY_USER not set!"

config :nexus,
  default_user: deploy_user

# Optional with fallback
config :nexus,
  default_user: env("DEPLOY_USER") || "deploy",
  max_connections: String.to_integer(env("MAX_CONN") || "5")

# Conditional hosts based on environment
if env("ENVIRONMENT") == "production" do
  host :web1, "deploy@prod-web1.example.com"
  host :web2, "deploy@prod-web2.example.com"
else
  host :web1, "deploy@staging-web1.example.com"
end
```

---

## Validation

Nexus validates your configuration for:

### 1. Syntax Errors

Invalid Elixir syntax is caught at parse time:

```elixir
# Missing 'do'
task :broken
  run "echo hello"
end
# Error: syntax error: missing 'do' in 'task'
```

### 2. Unknown Config Options

```elixir
config :nexus,
  invalid_option: "value"
# Error: unknown config option: invalid_option
```

### 3. Task Dependency Validation

```elixir
task :deploy, deps: [:nonexistent] do
  run "deploy.sh"
end
# Error: task :deploy depends on unknown task :nonexistent
```

### 4. Host/Group Reference Validation

```elixir
task :deploy, on: :unknown_host do
  run "deploy.sh"
end
# Error: task :deploy references unknown host or group :unknown_host
```

### 5. Group Member Validation

```elixir
group :webservers, [:web1, :nonexistent]
# Error: group :webservers references unknown host :nonexistent
```

### 6. Circular Dependency Detection

```elixir
task :a, deps: [:b] do
  run "a"
end

task :b, deps: [:a] do
  run "b"
end
# Error: circular dependency detected: a -> b -> a
```

### 7. Value Range Validation

```elixir
config :nexus,
  default_port: 99999  # Invalid port number
# Error: default_port must be at most 65535, got: 99999
```

---

## Advanced Patterns

### Environment-Based Configuration

```elixir
# Determine environment
environment = env("NEXUS_ENV") || "development"

# Environment-specific settings
case environment do
  "production" ->
    config :nexus,
      default_user: "deploy",
      max_connections: 20,
      command_timeout: 300_000
      
    host :web1, "deploy@prod-web1.example.com"
    host :web2, "deploy@prod-web2.example.com"
    host :web3, "deploy@prod-web3.example.com"
    
  "staging" ->
    config :nexus,
      default_user: "deploy",
      max_connections: 5
      
    host :web1, "deploy@staging-web1.example.com"
    
  _ ->  # development
    config :nexus,
      default_user: System.get_env("USER"),
      max_connections: 2
end
```

### Generating Hosts Dynamically

```elixir
# Generate hosts from a range
for i <- 1..10 do
  host_name = :"web#{i}"
  host_string = "deploy@192.168.1.#{10 + i}"
  host(host_name, host_string)
end

# Generate group from the same range
group :webservers, Enum.map(1..10, &:"web#{&1}")
```

### Shared Command Options

```elixir
# Define reusable options
@sudo_opts [sudo: true]
@retry_opts [retries: 3, retry_delay: 5_000]
@long_timeout [timeout: 600_000]

task :maintenance, on: :webservers do
  run "apt-get update", @sudo_opts
  run "apt-get upgrade -y", @sudo_opts ++ @retry_opts
  run "reboot", @sudo_opts
end

task :backup, on: :db_primary do
  run "pg_dump myapp > /backups/dump.sql", @long_timeout
end
```

### Including External Files

```elixir
# In nexus.exs
Code.require_file("nexus/hosts.exs")
Code.require_file("nexus/tasks.exs")

# Or use Code.eval_file for simple includes
{hosts, _} = Code.eval_file("hosts.exs")
Enum.each(hosts, fn {name, conn} -> host(name, conn) end)
```

### Parameterized Tasks

```elixir
# Define a function that creates tasks
defmodule NexusTasks do
  defmacro deploy_to(env, hosts) do
    quote do
      task unquote(:"deploy_#{env}"), on: unquote(hosts), deps: [:build] do
        run "deploy.sh --env #{unquote(env)}"
      end
    end
  end
end

import NexusTasks

deploy_to(:staging, :staging_servers)
deploy_to(:production, :production_servers)
```

---

## Complete Example

Here's a complete, production-ready `nexus.exs`:

```elixir
# =============================================================================
# nexus.exs - Production Deployment Configuration
# =============================================================================

# -----------------------------------------------------------------------------
# Environment Configuration
# -----------------------------------------------------------------------------
environment = env("NEXUS_ENV") || "production"
deploy_user = env("DEPLOY_USER") || "deploy"

config :nexus,
  default_user: deploy_user,
  default_port: 22,
  connect_timeout: 10_000,
  command_timeout: 120_000,
  max_connections: 10,
  continue_on_error: false

# -----------------------------------------------------------------------------
# Hosts
# -----------------------------------------------------------------------------
host :web1, "#{deploy_user}@10.0.1.10"
host :web2, "#{deploy_user}@10.0.1.11"
host :web3, "#{deploy_user}@10.0.1.12"

host :db_primary, "admin@10.0.2.10"
host :db_replica, "admin@10.0.2.11"

host :cache1, "#{deploy_user}@10.0.3.10"
host :cache2, "#{deploy_user}@10.0.3.11"

# -----------------------------------------------------------------------------
# Groups
# -----------------------------------------------------------------------------
group :web, [:web1, :web2, :web3]
group :database, [:db_primary, :db_replica]
group :cache, [:cache1, :cache2]
group :all, [:web1, :web2, :web3, :db_primary, :db_replica, :cache1, :cache2]

# -----------------------------------------------------------------------------
# Build Tasks (Local)
# -----------------------------------------------------------------------------
task :deps do
  run "mix deps.get --only prod"
end

task :compile, deps: [:deps] do
  run "MIX_ENV=prod mix compile"
end

task :assets, deps: [:deps] do
  run "cd assets && npm ci && npm run deploy"
  run "MIX_ENV=prod mix phx.digest"
end

task :release, deps: [:compile, :assets] do
  run "MIX_ENV=prod mix release --overwrite"
end

# -----------------------------------------------------------------------------
# Deployment Tasks
# -----------------------------------------------------------------------------
task :upload, on: :web, deps: [:release] do
  run "mkdir -p /opt/myapp/releases"
  # Note: actual file upload would use scp or similar
  run "echo 'Upload complete'"
end

task :deploy, on: :web, deps: [:upload], strategy: :serial do
  # Remove from load balancer
  run "consul maint -enable -reason 'deploying'", sudo: true
  run "sleep 5"
  
  # Stop old version
  run "systemctl stop myapp", sudo: true
  
  # Link new release
  run "cd /opt/myapp && ln -sfn releases/latest current"
  
  # Start new version
  run "systemctl start myapp", sudo: true
  
  # Wait and health check
  run "sleep 10"
  run "curl -f http://localhost:4000/health", retries: 5, retry_delay: 2_000
  
  # Re-enable in load balancer
  run "consul maint -disable", sudo: true
end

task :migrate, on: :db_primary, deps: [:deploy] do
  run "/opt/myapp/current/bin/myapp eval 'MyApp.Release.migrate()'"
end

task :full_deploy, deps: [:migrate] do
  run "echo 'Deployment complete!'"
end

# -----------------------------------------------------------------------------
# Operations Tasks
# -----------------------------------------------------------------------------
task :status, on: :all do
  run "hostname && uptime"
  run "systemctl status myapp 2>/dev/null || echo 'myapp not installed'"
end

task :logs, on: :web do
  run "journalctl -u myapp -n 50 --no-pager"
end

task :restart, on: :web, strategy: :serial do
  run "systemctl restart myapp", sudo: true
  run "sleep 5"
  run "curl -f http://localhost:4000/health", retries: 3, retry_delay: 2_000
end

task :rollback, on: :web, strategy: :serial do
  run "consul maint -enable", sudo: true
  run "sleep 5"
  run "cd /opt/myapp && ln -sfn releases/previous current"
  run "systemctl restart myapp", sudo: true
  run "sleep 10"
  run "curl -f http://localhost:4000/health"
  run "consul maint -disable", sudo: true
end

# -----------------------------------------------------------------------------
# Maintenance Tasks
# -----------------------------------------------------------------------------
task :backup, on: :db_primary do
  run "pg_dump myapp_prod | gzip > /backups/myapp-$(date +%Y%m%d-%H%M%S).sql.gz",
      timeout: 3_600_000  # 1 hour
end

task :cleanup, on: :all do
  run "docker system prune -f", sudo: true
  run "journalctl --vacuum-time=7d", sudo: true
end
```

---

## See Also

- [Getting Started](getting-started.md) - Initial setup and first steps
- [CLI Reference](cli.md) - Command-line interface documentation
- [SSH Configuration](ssh.md) - SSH authentication and troubleshooting
- [Examples](examples.md) - More real-world examples
