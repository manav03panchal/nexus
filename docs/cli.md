# CLI Reference

## Commands

### nexus run

Execute one or more tasks.

```bash
nexus run <tasks> [options]
```

**Arguments:**
- `tasks` - Space-separated list of task names

**Options:**

| Flag | Description |
|------|-------------|
| `-n, --dry-run` | Show execution plan without running |
| `-v, --verbose` | Show detailed output (timing, attempts) |
| `-q, --quiet` | Minimal output (summary only) |
| `-c, --config FILE` | Config file path (default: nexus.exs) |
| `-i, --identity FILE` | SSH private key file |
| `-u, --user USER` | Override SSH user |
| `-p, --parallel-limit N` | Max concurrent tasks (default: 10) |
| `--continue-on-error` | Don't abort on task failure |
| `--format FORMAT` | Output format: text, json |
| `--plain` | Disable colors |

**Examples:**

```bash
# Run single task
nexus run build

# Run multiple tasks
nexus run build test deploy

# Dry run
nexus run deploy --dry-run

# With SSH key
nexus run deploy -i ~/.ssh/deploy_key

# Continue on failure
nexus run deploy --continue-on-error

# JSON output
nexus run build --format json

# Verbose
nexus run deploy --verbose
```

### nexus list

List all defined tasks.

```bash
nexus list [options]
```

**Options:**

| Flag | Description |
|------|-------------|
| `-c, --config FILE` | Config file path |
| `--format FORMAT` | Output format: text, json |
| `--plain` | Disable colors |

**Example:**

```bash
$ nexus list

Tasks
========================================
  build
    2 commands
  test (deps: build)
    1 command
  deploy (deps: test) [on: web]
    3 commands

Hosts
========================================
  web1: deploy@192.168.1.10
  web2: deploy@192.168.1.11

Groups
========================================
  web: [web1, web2]
```

### nexus validate

Validate configuration file.

```bash
nexus validate [options]
```

**Options:**

| Flag | Description |
|------|-------------|
| `-c, --config FILE` | Config file path |

**Example:**

```bash
$ nexus validate

Configuration valid: nexus.exs

Summary:
  Tasks:  5
  Hosts:  2
  Groups: 1
```

**Error example:**

```bash
$ nexus validate

Error: Configuration validation failed

  Task 'deploy' depends on unknown task: nonexistent
```

### nexus preflight

Run pre-flight checks before execution.

```bash
nexus preflight [tasks] [options]
```

**Arguments:**
- `tasks` - Optional tasks to check (checks all if omitted)

**Options:**

| Flag | Description |
|------|-------------|
| `-c, --config FILE` | Config file path |
| `-v, --verbose` | Show detailed check results |
| `--skip CHECKS` | Skip checks (comma-separated: config,hosts,ssh,tasks) |
| `--format FORMAT` | Output format: text, json |
| `--plain` | Disable colors |

**Checks performed:**
1. **config** - Validates configuration syntax and references
2. **hosts** - TCP connectivity to all hosts
3. **ssh** - SSH authentication to all hosts
4. **tasks** - Validates requested tasks exist

**Example:**

```bash
$ nexus preflight deploy

Pre-flight Checks
----------------------------------------
[ok] config: Configuration is valid
[ok] hosts: All 2 host(s) reachable
[ok] ssh: SSH auth successful for 2 host(s)
[ok] tasks: 3 task(s) available

Execution Plan
----------------------------------------
Phase 1: build
Phase 2: test
Phase 3: deploy

========================================
All checks passed (523ms)
```

**Skip SSH check:**

```bash
nexus preflight --skip ssh
```

### nexus init

Create a template configuration file.

```bash
nexus init [options]
```

**Options:**

| Flag | Description |
|------|-------------|
| `-o, --output FILE` | Output file (default: nexus.exs) |
| `-f, --force` | Overwrite existing file |

**Example:**

```bash
$ nexus init

Created: nexus.exs

Next steps:
  1. Edit nexus.exs to define your tasks and hosts
  2. Run 'nexus validate' to check your configuration
  3. Run 'nexus list' to see defined tasks
  4. Run 'nexus run <task>' to execute a task
```

### nexus --help

Show help for any command.

```bash
nexus --help
nexus run --help
nexus list --help
```

### nexus --version

Show version.

```bash
$ nexus --version
nexus 0.1.0
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Task failure or general error |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `NO_COLOR` | Disable colored output when set |

## Output Formats

### Text (default)

Human-readable output with colors and formatting.

### JSON

Machine-readable JSON output.

```bash
$ nexus run build --format json

{
  "status": "ok",
  "duration_ms": 45,
  "tasks_run": 1,
  "tasks_succeeded": 1,
  "tasks_failed": 0,
  "aborted_at": null
}
```

```bash
$ nexus list --format json

{
  "tasks": {
    "build": {
      "deps": [],
      "on": "local",
      "commands": 2,
      "strategy": "parallel"
    }
  },
  "hosts": {},
  "groups": {}
}
```
