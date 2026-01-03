---
slug: /
sidebar_position: 1
title: Introduction
---

# Nexus

> **Last updated:** January 3, 2026

**Nexus** is a distributed task runner built in Elixir for deploying applications and running automation tasks across local and remote hosts.

## Why Nexus?

- **Declarative Resources** - Define desired state with idempotent resources (package, service, file, etc.)
- **Simple DSL** - Define tasks in readable Elixir syntax
- **DAG Dependencies** - Tasks execute in optimal order based on dependencies
- **SSH Execution** - Run commands on remote hosts with connection pooling
- **Parallel Execution** - Execute independent tasks concurrently across hosts
- **Zero-Downtime Deploys** - Serial/rolling execution strategies
- **Built-in Resilience** - Retry logic with exponential backoff
- **Tailscale Integration** - Auto-discover hosts from your Tailscale network
- **Secrets Management** - Encrypted vault for sensitive credentials
- **Notifications** - Slack, Discord, Teams webhooks on completion
- **Minimal Dependencies** - Single binary, no agents on remote hosts

## Features at a Glance

| Feature | Description |
|---------|-------------|
| **Declarative Resources** | `package`, `service`, `file`, `directory`, `user`, `group`, `command` |
| **Idempotent Commands** | `command` resource with `creates:`, `unless:`, `onlyif:` guards |
| **Facts Gathering** | Auto-detect OS, architecture, memory, CPU for conditional logic |
| **Tailscale Discovery** | `tailscale_hosts tag: "web", as: :webservers` |
| **Encrypted Secrets** | AES-256-GCM vault with `nexus secret set/get` |
| **Webhook Notifications** | Slack, Discord, Teams, or custom JSON webhooks |
| **Local & Remote Execution** | Run commands locally or on remote hosts via SSH |
| **Task Dependencies** | Define task ordering with `deps: [:task1, :task2]` |
| **Host Groups** | Organize hosts into named groups for targeting |
| **Parallel & Serial Modes** | Control execution strategy per task |
| **Rolling Deploys** | Canary deployments with configurable batch sizes |
| **Connection Pooling** | Efficient SSH connection reuse |
| **Pre-flight Checks** | Validate config, connectivity, and auth before running |
| **Dry-run Mode** | Preview execution plan without running commands |
| **JSON Output** | Machine-readable output for CI/CD integration |

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/manav03panchal/nexus/main/scripts/install.sh | bash
```

Requires [Elixir](https://elixir-lang.org/install.html) 1.15+. The script clones, builds, and installs to `/usr/local/bin`.

### Verify Installation

```bash
nexus --version
# nexus 0.1.0
```

## 5-Minute Quick Start

### 1. Create a Configuration

```bash
nexus init
```

### 2. Edit `nexus.exs`

```elixir
# nexus.exs

# Define remote hosts
host :web1, "deploy@192.168.1.10"
host :web2, "deploy@192.168.1.11"

# Or auto-discover from Tailscale
tailscale_hosts tag: "webserver", as: :web

# Group them
group :web, [:web1, :web2]

# Notifications on completion
notify :slack,
  url: env("SLACK_WEBHOOK_URL"),
  on: :failure,
  template: :slack

# Local build task
task :build do
  command "mix deps.get --only prod"
  command "MIX_ENV=prod mix release"
end

# Deploy with declarative resources
task :setup, on: :web do
  # Ensure packages are installed
  package "nginx"
  
  # Ensure directories exist
  directory "/opt/myapp", owner: "deploy", mode: 0o755
  
  # Manage services
  service "nginx", ensure: :running, enable: true
end

# Deploy to all web servers (runs in parallel by default)
task :deploy, on: :web, deps: [:build, :setup] do
  command "systemctl stop myapp", sudo: true
  
  # Idempotent extraction - only runs if target doesn't exist
  command "tar -xzf /tmp/release.tar.gz -C /opt/myapp",
    creates: "/opt/myapp/bin/myapp"
  
  command "systemctl start myapp", sudo: true
end

# Rolling restart (one server at a time)
task :restart, on: :web, strategy: :serial do
  command "systemctl restart myapp", sudo: true
  command "sleep 10"
  command "curl -sf http://localhost:4000/health"
end
```

### 3. Validate

```bash
nexus validate
# Configuration valid: nexus.exs
# Summary: Tasks: 3, Hosts: 2, Groups: 1
```

### 4. Pre-flight Check

```bash
nexus preflight deploy
# [ok] config: Configuration is valid
# [ok] hosts: All 2 host(s) reachable
# [ok] ssh: SSH authentication OK for 2 host(s)
```

### 5. Deploy

```bash
nexus run deploy -i ~/.ssh/deploy_key
```

Output:
```
[ok] Task: build
  Host: local (ok)
    [+] $ mix deps.get --only prod
    [+] $ MIX_ENV=prod mix release

[ok] Task: deploy
  Host: web1 (ok)
    [+] $ systemctl stop myapp
    [+] $ cp -r /tmp/release /opt/myapp
    [+] $ systemctl start myapp
  Host: web2 (ok)
    [+] $ systemctl stop myapp
    [+] $ cp -r /tmp/release /opt/myapp
    [+] $ systemctl start myapp

========================================
Status: SUCCESS
Duration: 12453ms
Tasks: 2/2 succeeded
```

## Common Commands

```bash
# Execute tasks
nexus run deploy                    # Run deploy task
nexus run build test deploy         # Run multiple tasks
nexus run deploy --dry-run          # Preview without executing
nexus run deploy --verbose          # Detailed output

# Information
nexus list                          # List all tasks
nexus validate                      # Validate configuration
nexus preflight deploy              # Pre-flight checks

# Options
nexus run deploy -i ~/.ssh/key      # Specify SSH key
nexus run deploy -u admin           # Override SSH user
nexus run deploy --continue-on-error # Don't stop on failure
nexus run deploy --format json      # JSON output
```

## Documentation

### Getting Started
- [**Getting Started**](getting-started.md) - Complete installation and first steps tutorial

### Reference
- [**Configuration Reference**](configuration.md) - Complete DSL documentation (`config`, `host`, `group`, `task`, `run`)
- [**CLI Reference**](cli.md) - All commands, flags, and options

### Guides
- [**Examples**](examples.md) - Real-world deployment configurations
- [**SSH Configuration**](ssh.md) - SSH keys, agents, config file integration
- [**Architecture**](architecture.md) - How Nexus works internally
- [**Troubleshooting**](troubleshooting.md) - Common issues and solutions

## Example Configurations

### Phoenix Deployment with Resources

```elixir
# Notify on completion
notify :discord,
  url: env("DISCORD_WEBHOOK"),
  on: :always,
  template: :discord

task :release, deps: [:test] do
  command "MIX_ENV=prod mix release"
end

task :setup, on: :web do
  package "libssl-dev"
  directory "/opt/myapp", owner: "deploy"
  service "myapp", ensure: :stopped  # Stop before deploy
end

task :deploy, on: :web, deps: [:release, :setup], strategy: :serial do
  # Only extract if binary doesn't exist (idempotent)
  command "tar -xzf /tmp/myapp.tar.gz -C /opt/myapp",
    creates: "/opt/myapp/bin/myapp"
  
  service "myapp", ensure: :running, enable: true
  
  # Health check with retries
  command "curl -sf http://localhost:4000/health",
    unless: "curl -sf http://localhost:4000/health"
end

task :migrate, on: :db, deps: [:deploy] do
  command "/opt/myapp/bin/myapp eval 'MyApp.Release.migrate()'"
end
```

### Tailscale + Secrets

```elixir
# Auto-discover hosts from Tailscale network
tailscale_hosts tag: "webserver", as: :web, user: "deploy"
tailscale_hosts tag: "database", as: :db, user: "postgres"

task :deploy, on: :web do
  # Use secrets from encrypted vault
  command "deploy.sh",
    env: %{
      "API_KEY" => secret("API_KEY"),
      "DB_PASSWORD" => secret("DB_PASSWORD")
    }
end
```

### Docker Compose

```elixir
task :build do
  command "docker build -t myapp:latest ."
  command "docker push registry.example.com/myapp:latest"
end

task :deploy, on: :docker_hosts, deps: [:build] do
  command "docker compose pull"
  command "docker compose up -d --remove-orphans"
  command "docker compose ps"
end
```

### Multi-Environment with Facts

```elixir
env = System.get_env("NEXUS_ENV") || "staging"

if env == "production" do
  host :web1, "deploy@prod-web1.example.com"
  host :web2, "deploy@prod-web2.example.com"
  
  notify :pagerduty,
    url: env("PAGERDUTY_WEBHOOK"),
    on: :failure,
    template: :generic
else
  host :web1, "deploy@staging.example.com"
end

task :install, on: :web do
  # Package resource auto-detects apt/yum/pacman
  package "nginx"
  package "postgresql-client"
end
```

## System Requirements

- **Elixir** 1.15+ with Erlang/OTP 25+
- **SSH** access to remote hosts (for remote execution)
- **Linux/macOS** (primary platforms)

## Contributing

Nexus is open source. Contributions welcome!

- [GitHub Repository](https://github.com/manav03panchal/nexus)
- [Report Issues](https://github.com/manav03panchal/nexus/issues)

## License

MIT License - See [LICENSE](https://github.com/manav03panchal/nexus/blob/main/LICENSE) for details.


<!-- Deployment test: Mon 29 Dec 2025 21:56:59 MST -->
