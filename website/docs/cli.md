---
sidebar_position: 4
---

# CLI Reference

Complete command-line interface documentation for Nexus.

## Overview

Nexus provides a simple yet powerful CLI for executing tasks, validating configurations, and managing deployments.

```bash
nexus <command> [options] [arguments]
```

## Global Behavior

### Exit Codes

Nexus uses standard exit codes:

| Code | Meaning |
|------|---------|
| `0` | Success - all tasks completed without errors |
| `1` | Failure - one or more tasks failed, or invalid arguments |

### Config File Discovery

By default, Nexus looks for `nexus.exs` in the current directory. Override with `--config`:

```bash
nexus run deploy                      # Uses ./nexus.exs
nexus run deploy -c /path/to/nexus.exs  # Uses specified file
```

---

## Commands

### nexus run

Execute one or more tasks with their dependencies.

#### Syntax

```bash
nexus run <tasks> [options]
```

#### Arguments

| Argument | Description |
|----------|-------------|
| `tasks` | One or more task names (space or comma separated) |

#### Options

| Option | Short | Default | Description |
|--------|-------|---------|-------------|
| `--config FILE` | `-c` | `nexus.exs` | Path to configuration file |
| `--dry-run` | `-n` | | Show execution plan without running |
| `--verbose` | `-v` | | Show detailed output including timings |
| `--quiet` | `-q` | | Minimal output (only errors) |
| `--continue-on-error` | | | Continue executing if a task fails |
| `--identity FILE` | `-i` | | SSH private key file |
| `--user USER` | `-u` | | SSH username |
| `--parallel-limit N` | `-p` | `10` | Maximum concurrent tasks |
| `--format FORMAT` | | `text` | Output format: `text` or `json` |
| `--plain` | | | Disable colors and formatting |

#### Examples

```bash
# Run a single task
nexus run deploy

# Run multiple tasks
nexus run build test deploy
nexus run build,test,deploy

# Preview execution plan
nexus run deploy --dry-run

# Use specific SSH key
nexus run deploy -i ~/.ssh/deploy_key

# Override SSH user
nexus run deploy -u admin

# Continue despite failures
nexus run deploy --continue-on-error

# Verbose output with timing
nexus run deploy --verbose

# JSON output for scripting
nexus run deploy --format json

# Limit concurrent tasks
nexus run deploy --parallel-limit 5
```

#### Output Examples

**Standard output:**

```
[ok] Task: build
  Host: local (ok)
    [+] $ mix compile
        Compiling 42 files (.ex)
        Generated myapp app

[ok] Task: deploy
  Host: web1 (ok)
    [+] $ git pull origin main
        Already up to date.
    [+] $ systemctl restart myapp
  Host: web2 (ok)
    [+] $ git pull origin main
        Already up to date.
    [+] $ systemctl restart myapp

========================================
Status: SUCCESS
Duration: 12453ms
Tasks: 2/2 succeeded
```

**Verbose output (`--verbose`):**

```
[ok] Task: build
  Host: local (ok)
    [+] $ mix compile
        Compiling 42 files (.ex)
        Generated myapp app
        (exit: 0, 5234ms, attempts: 1)

[ok] Task: deploy
  Host: web1 (ok)
    [+] $ git pull origin main
        Already up to date.
        (exit: 0, 342ms, attempts: 1)
    [+] $ systemctl restart myapp
        (exit: 0, 1204ms, attempts: 1)
```

**Quiet output (`--quiet`):**

```
SUCCESS
```

**JSON output (`--format json`):**

```json
{
  "status": "ok",
  "duration_ms": 12453,
  "tasks_run": 2,
  "tasks_succeeded": 2,
  "tasks_failed": 0,
  "aborted_at": null
}
```

**Dry run output (`--dry-run`):**

```
Execution Plan
========================================
Total tasks: 3

Phase 1: deps
Phase 2: compile
Phase 3: deploy (parallel)
```

**Failure output:**

```
[ok] Task: build
  Host: local (ok)
    [+] $ mix compile
        Compiling 42 files (.ex)

[FAILED] Task: deploy
  Host: web1 (ok)
    [+] $ git pull origin main
        Already up to date.
  Host: web2 (failed)
    [x] $ git pull origin main
        fatal: Could not read from remote repository.
        (exit: 128, 234ms, attempts: 1)

========================================
Status: FAILED
Duration: 3421ms
Tasks: 1/2 succeeded
Aborted at: deploy
```

---

### nexus list

List all defined tasks in the configuration.

#### Syntax

```bash
nexus list [options]
```

#### Options

| Option | Short | Default | Description |
|--------|-------|---------|-------------|
| `--config FILE` | `-c` | `nexus.exs` | Path to configuration file |
| `--format FORMAT` | | `text` | Output format: `text` or `json` |
| `--plain` | | | Disable colors and formatting |

#### Examples

```bash
# List all tasks
nexus list

# JSON output
nexus list --format json

# Use different config file
nexus list -c production.exs
```

#### Output Examples

**Text output:**

```
Tasks
========================================
  deps
    1 command
  compile (deps: deps)
    1 command
  test (deps: compile)
    1 command
  deploy (deps: test)
    on: webservers (parallel)
    3 commands
  restart
    on: webservers (serial)
    2 commands

Hosts: 3
Groups: 2
```

**JSON output (`--format json`):**

```json
{
  "tasks": [
    {
      "name": "deps",
      "on": "local",
      "deps": [],
      "commands": 1,
      "strategy": "parallel"
    },
    {
      "name": "compile",
      "on": "local",
      "deps": ["deps"],
      "commands": 1,
      "strategy": "parallel"
    },
    {
      "name": "deploy",
      "on": "webservers",
      "deps": ["test"],
      "commands": 3,
      "strategy": "parallel"
    }
  ],
  "hosts": ["web1", "web2", "web3"],
  "groups": {
    "webservers": ["web1", "web2", "web3"]
  }
}
```

---

### nexus validate

Validate the configuration file for errors.

#### Syntax

```bash
nexus validate [options]
```

#### Options

| Option | Short | Default | Description |
|--------|-------|---------|-------------|
| `--config FILE` | `-c` | `nexus.exs` | Path to configuration file |

#### Examples

```bash
# Validate default config
nexus validate

# Validate specific config
nexus validate -c staging.exs
```

#### Output Examples

**Valid configuration:**

```
Configuration valid: nexus.exs

Summary:
  Tasks:  8
  Hosts:  5
  Groups: 3
```

**Invalid configuration:**

```
Configuration invalid: nexus.exs

Errors:
  - [task_deps] task :deploy depends on unknown task :build
  - [group_members] group :webservers references unknown host :web4
  - [config] command_timeout must be at least 1, got: 0
```

---

### nexus preflight

Run pre-flight checks before executing tasks.

Checks include:
- Configuration validation
- Host reachability (TCP connection)
- SSH authentication
- Sudo availability (if needed)
- Task existence

#### Syntax

```bash
nexus preflight [tasks] [options]
```

#### Arguments

| Argument | Description |
|----------|-------------|
| `tasks` | Optional: Tasks to check (validates hosts used by these tasks) |

#### Options

| Option | Short | Default | Description |
|--------|-------|---------|-------------|
| `--config FILE` | `-c` | `nexus.exs` | Path to configuration file |
| `--skip CHECKS` | | | Checks to skip (comma-separated: `config,hosts,ssh,tasks`) |
| `--verbose` | `-v` | | Show detailed check results |
| `--format FORMAT` | | `text` | Output format: `text` or `json` |
| `--plain` | | | Disable colors and formatting |

#### Examples

```bash
# Full preflight check
nexus preflight

# Check specific tasks
nexus preflight deploy migrate

# Skip host connectivity check
nexus preflight --skip hosts

# Skip multiple checks
nexus preflight --skip hosts,ssh

# Verbose output
nexus preflight --verbose
```

#### Output Examples

**All checks passing:**

```
Pre-flight Checks
----------------------------------------
[ok] config: Configuration is valid
     Tasks: 8, Hosts: 5, Groups: 3
[ok] hosts: All 5 host(s) reachable
[ok] ssh: SSH authentication OK for 5 host(s)
[ok] tasks: 8 task(s) available

Execution Plan
----------------------------------------
Phase 1:
  - deps [local] (1 cmd, parallel)
Phase 2:
  - compile [local] (1 cmd, parallel)
Phase 3:
  - deploy [web1, web2, web3] (3 cmd, parallel)

========================================
All checks passed (2341ms)
```

**With failures:**

```
Pre-flight Checks
----------------------------------------
[ok] config: Configuration is valid
     Tasks: 8, Hosts: 5, Groups: 3
[FAILED] hosts: 1 host(s) unreachable
     web1: reachable
     web2: reachable
     web3: unreachable (connection refused)
[FAILED] ssh: SSH auth failed for 1 host(s)
     web1: ok
     web2: authentication failed
     web3: skipped (unreachable)
[ok] tasks: All requested tasks found

========================================
Pre-flight checks failed (3421ms)
```

**Verbose output (`--verbose`):**

```
Pre-flight Checks
----------------------------------------
[ok] config: Configuration is valid
     Path: /home/deploy/myapp/nexus.exs
     Parse time: 12ms
     Tasks: 8
     Hosts: 5
     Groups: 3
     
[ok] hosts: All 5 host(s) reachable
     web1 (192.168.1.10:22): reachable (23ms)
     web2 (192.168.1.11:22): reachable (45ms)
     web3 (192.168.1.12:2222): reachable (31ms)
     db1 (192.168.2.10:22): reachable (28ms)
     db2 (192.168.2.11:22): reachable (34ms)
     
[ok] ssh: SSH authentication OK for 5 host(s)
     web1: OK (key: ~/.ssh/id_ed25519) - 102ms
     web2: OK (key: ~/.ssh/id_ed25519) - 98ms
     web3: OK (key: ~/.ssh/id_ed25519) - 104ms
     db1: OK (agent) - 87ms
     db2: OK (agent) - 91ms
```

**JSON output (`--format json`):**

```json
{
  "status": "ok",
  "duration_ms": 2341,
  "checks": [
    {
      "name": "config",
      "status": "passed",
      "message": "Configuration is valid",
      "details": {
        "tasks": 8,
        "hosts": 5,
        "groups": 3
      }
    },
    {
      "name": "hosts",
      "status": "passed",
      "message": "All 5 host(s) reachable",
      "details": [
        {"host": "web1", "status": "reachable"},
        {"host": "web2", "status": "reachable"}
      ]
    }
  ],
  "execution_plan": [
    {
      "phase": 1,
      "tasks": [{"name": "deps", "on": "local", "commands": 1}]
    }
  ]
}
```

---

### nexus init

Create a template `nexus.exs` configuration file.

#### Syntax

```bash
nexus init [options]
```

#### Options

| Option | Short | Default | Description |
|--------|-------|---------|-------------|
| `--output FILE` | `-o` | `nexus.exs` | Output file path |
| `--force` | `-f` | | Overwrite existing file |

#### Examples

```bash
# Create default nexus.exs
nexus init

# Create with different name
nexus init -o production.exs

# Overwrite existing file
nexus init --force
```

#### Output Examples

**Success:**

```
Created nexus.exs

Next steps:
  1. Edit nexus.exs to define your hosts and tasks
  2. Validate with: nexus validate
  3. Run with: nexus run <task>
```

**File exists (without `--force`):**

```
Error: nexus.exs already exists. Use --force to overwrite.
```

---

### nexus version

Display version information.

#### Syntax

```bash
nexus version
```

#### Output

```
nexus <version>
```

---

### nexus help

Display help information.

#### Syntax

```bash
nexus help [command]
nexus --help
nexus <command> --help
```

#### Examples

```bash
# General help
nexus help
nexus --help

# Command-specific help
nexus help run
nexus run --help
```

---

## Option Details

### --config / -c

Specifies the path to the configuration file.

```bash
# Relative path
nexus run deploy -c configs/production.exs

# Absolute path
nexus run deploy -c /etc/nexus/production.exs

# Home directory expansion works
nexus run deploy -c ~/configs/nexus.exs
```

### --dry-run / -n

Shows what would be executed without actually running commands.

```bash
nexus run deploy --dry-run
```

This is useful for:
- Verifying dependency resolution
- Confirming execution phases
- Understanding parallel vs serial execution
- Safe previewing before deployment

### --verbose / -v

Enables detailed output including:
- Command exit codes
- Execution duration per command
- Retry attempt counts
- Connection details

```bash
nexus run deploy --verbose
```

### --quiet / -q

Suppresses all output except errors. Useful for scripts:

```bash
if nexus run deploy --quiet; then
  echo "Deploy succeeded"
else
  echo "Deploy failed"
fi
```

### --continue-on-error

By default, Nexus stops on the first task failure. This flag continues execution:

```bash
# Stop on first failure (default)
nexus run deploy

# Continue despite failures
nexus run deploy --continue-on-error
```

Use cases:
- Running independent tasks where one failure shouldn't block others
- Gathering results from all hosts even if some fail
- Non-critical tasks like log collection

### --identity / -i

Specifies an SSH private key file for authentication:

```bash
nexus run deploy -i ~/.ssh/deploy_key
```

This is equivalent to `ssh -i ~/.ssh/deploy_key`. The key is used for all SSH connections in the run.

### --user / -u

Overrides the SSH username for all connections:

```bash
nexus run deploy -u admin
```

This overrides:
- The `default_user` in config
- The user specified in host definitions

### --parallel-limit / -p

Limits the number of concurrent tasks:

```bash
# Run at most 5 tasks in parallel
nexus run deploy --parallel-limit 5
```

Default is `10`. Lower values reduce load on your machine and target hosts but increase total execution time.

### --format

Controls output format:

```bash
# Human-readable text (default)
nexus run deploy --format text

# Machine-readable JSON
nexus run deploy --format json
```

JSON format is useful for:
- CI/CD pipeline integration
- Parsing results programmatically
- Log aggregation systems

### --plain

Disables ANSI colors and formatting:

```bash
nexus run deploy --plain
```

Useful for:
- Terminals that don't support colors
- Logging to files
- CI systems with basic output handling

---

## Environment Variables

Nexus respects these environment variables:

| Variable | Description |
|----------|-------------|
| `NO_COLOR` | If set, disables colored output (same as `--plain`) |
| `SSH_AUTH_SOCK` | Path to SSH agent socket (used for SSH agent authentication) |
| `USER` | Default SSH username if not specified |
| `HOME` | Used for `~` expansion in paths |

Example:

```bash
# Disable colors
NO_COLOR=1 nexus run deploy

# Use specific SSH agent
SSH_AUTH_SOCK=/tmp/my-agent.sock nexus run deploy
```

---

## Scripting Examples

### CI/CD Integration

```bash
#!/bin/bash
set -e

# Run tests
nexus run test --quiet || {
  echo "Tests failed!"
  exit 1
}

# Deploy with JSON output for parsing
result=$(nexus run deploy --format json)
status=$(echo "$result" | jq -r '.status')

if [ "$status" = "ok" ]; then
  echo "Deployment successful!"
  exit 0
else
  echo "Deployment failed!"
  echo "$result" | jq '.task_results[] | select(.status != "ok")'
  exit 1
fi
```

### Automated Preflight

```bash
#!/bin/bash

# Run preflight checks
if nexus preflight deploy --format json | jq -e '.status == "ok"' > /dev/null; then
  echo "All systems ready"
  nexus run deploy
else
  echo "Preflight failed - aborting deployment"
  nexus preflight deploy  # Show human-readable output
  exit 1
fi
```

### Parallel Task Runner

```bash
#!/bin/bash

# Run multiple independent tasks in parallel
nexus run task1,task2,task3 --parallel-limit 3 --continue-on-error --format json \
  | jq -r '.task_results[] | "\(.task): \(.status)"'
```

---

## See Also

- [Getting Started](getting-started.md) - Initial setup guide
- [Configuration Reference](configuration.md) - DSL documentation
- [SSH Configuration](ssh.md) - SSH authentication details
- [Examples](examples.md) - Real-world usage examples
- [Troubleshooting](troubleshooting.md) - Common issues and solutions
