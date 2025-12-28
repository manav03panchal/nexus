# Nexus - Product Requirements Document

**Version:** 1.2
**Last Updated:** 2025-12-28
**Status:** Draft
**Author:** Initial Design Session
**Library Research:** Completed 2025-12-28
**Architecture Deep-Dive:** Completed 2025-12-28

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Vision & Goals](#2-vision--goals)
3. [User Personas](#3-user-personas)
4. [Product Principles](#4-product-principles)
5. [Version Roadmap Overview](#5-version-roadmap-overview)
6. [v0.1 - Core (Production Ready)](#6-v01---core-production-ready)
7. [v0.2 - Enhanced Operations](#7-v02---enhanced-operations)
8. [v0.3 - Distributed & Cloud](#8-v03---distributed--cloud)
9. [v0.4 - Enterprise](#9-v04---enterprise)
10. [Technical Architecture](#10-technical-architecture)
11. [State Management & Crash Recovery](#11-state-management--crash-recovery)
12. [Agent Communication Protocol](#12-agent-communication-protocol)
13. [Secrets & Key Management](#13-secrets--key-management)
14. [Non-Functional Requirements](#14-non-functional-requirements)
15. [Security Requirements](#15-security-requirements)
16. [Testing Strategy](#16-testing-strategy)
17. [Documentation Plan](#17-documentation-plan)
18. [Release & Upgrade Strategy](#18-release--upgrade-strategy)
19. [Telemetry & Observability](#19-telemetry--observability)
20. [Success Metrics](#20-success-metrics)
21. [Appendices](#21-appendices)
22. [Library Research & Recommendations](#22-library-research--recommendations)
23. [Operational Excellence](#23-operational-excellence)

---

## 1. Executive Summary

### 1.1 What is Nexus?

Nexus is a distributed task runner that unifies build automation (Make), infrastructure management (Ansible), and CI/CD pipelines into a single tool with a single syntax. Built on Elixir/OTP, it leverages the BEAM's distributed computing capabilities to provide fault-tolerant, self-healing task execution across heterogeneous infrastructure.

### 1.2 The Problem

Engineers currently juggle multiple tools for related tasks:

| Task | Tool | Config Format |
|------|------|---------------|
| Local builds | Make, npm scripts, Cargo | Makefile, package.json, Cargo.toml |
| Server config | Ansible, Puppet, Chef | YAML, Ruby DSL |
| CI/CD | GitHub Actions, Jenkins | YAML, Groovy |
| Deployment | Bash scripts, Capistrano | Shell, Ruby |

This creates:
- Configuration sprawl across 10+ files in 5+ syntaxes
- No unified view of the full pipeline
- Difficult debugging across tool boundaries
- Steep learning curves for each tool
- Slow feedback loops (especially with cloud CI)

### 1.3 The Solution

Nexus provides:
- **One syntax** - Elixir DSL for tasks, hosts, and pipelines
- **One tool** - Build, configure, and deploy from the same CLI
- **One cluster** - Local machines + cloud instances work together
- **Production-ready** - Fault-tolerant, with retries, timeouts, and proper error handling from v0.1

### 1.4 Tagline Options

- "Nexus: Make + Ansible + CI in one tool"
- "Nexus: Distributed task runner for the modern age"
- "Nexus: Your computers already talk to each other. Nexus makes them work together."

---

## 2. Vision & Goals

### 2.1 Vision Statement

Replace the fragmented DevOps toolchain with a single, unified task runner that scales from a solo developer's laptop to enterprise multi-cloud infrastructure, without sacrificing simplicity or requiring distributed systems expertise.

### 2.2 Primary Goals

1. **Simplicity** - A developer should be productive within 10 minutes of installation
2. **Production-Ready** - No "prototype quality" code; proper error handling, retries, and observability from day one
3. **Progressive Complexity** - Simple things are simple; complex things are possible
4. **Zero Infrastructure** - No central server, no database, no Kubernetes required
5. **Fault Tolerance** - Leverage OTP for self-healing distributed execution

### 2.3 Non-Goals (Explicit Exclusions)

1. **Not a container orchestrator** - We don't compete with Kubernetes for container scheduling
2. **Not a cloud provisioner** - We don't replace Terraform for infrastructure-as-code (though we integrate with cloud APIs for burst capacity)
3. **Not a monitoring system** - We emit telemetry but don't store/visualize metrics
4. **Not a web application** - CLI-first, no web UI in roadmap (TUI only)

---

## 3. User Personas

### 3.1 Solo Developer - "Maya"

**Background:**
- Indie SaaS founder in Lisbon
- Full-stack developer, runs own infrastructure
- 2 VPS instances + local dev machine
- Currently uses: Make, bash scripts, manual SSH

**Pain Points:**
- Deployment is a manual SSH + bash process
- No visibility into what ran where
- Afraid to automate because scripts are fragile

**Nexus Value:**
- Single `nexus run deploy` command
- Confidence from retries and proper error messages
- Gradual path to more automation

**Success Criteria:**
- Deploys to production with one command
- Knows immediately if something failed and why

---

### 3.2 Startup CTO - "Priya"

**Background:**
- CTO of 12-person startup in Austin
- 15 microservices across AWS
- Team of 4 backend engineers
- Currently uses: GitHub Actions, Ansible, Terraform

**Pain Points:**
- $800/month CI bill
- 15-minute feedback loops on CI
- Ansible playbooks are slow and YAML is error-prone
- Onboarding new engineers takes weeks

**Nexus Value:**
- Run tests locally across machines before pushing
- Replace Ansible for deployment
- One syntax for the team to learn

**Success Criteria:**
- CI costs reduced by 50%+
- New engineer productive in days, not weeks
- Deployment time cut in half

---

### 3.3 Home Lab Enthusiast - "Jake"

**Background:**
- DevOps engineer by day, tinkerer by night
- 8 Raspberry Pis + 2 NUCs at home
- Runs Plex, Home Assistant, various experiments
- Currently uses: Ansible, lots of SSH

**Pain Points:**
- Wants distributed builds but Kubernetes is overkill
- Ansible is slow for ad-hoc commands
- Difficult to parallelize work across Pis

**Nexus Value:**
- Distributed video encoding across Pis
- Quick ad-hoc commands across all machines
- Fun project that teaches distributed systems

**Success Criteria:**
- Parallel builds/encodes across Pi cluster
- One-liner for "run this on all Pis"

---

### 3.4 Enterprise Platform Engineer - "Raj"

**Background:**
- Senior Platform Engineer at Fortune 500 bank
- 200 RHEL9 VMs in Azure, domain-joined
- Strict security requirements (SOC2, audit logs)
- Currently uses: Ansible Tower, Jenkins, custom scripts

**Pain Points:**
- Ansible Tower license costs
- Slow playbook execution
- YAML errors cause production incidents
- Audit trail is difficult to maintain

**Nexus Value:**
- Faster execution (parallel by default)
- Type-checked DSL prevents errors
- Telemetry for audit trails
- Integrates with existing AD/Azure auth

**Success Criteria:**
- Passes security review
- Execution time reduced 3x
- Audit requirements met

---

## 4. Product Principles

### 4.1 Core Principles

1. **Explicit over implicit**
   - No magic behavior
   - Config is code, not convention
   - Errors are specific and actionable

2. **Parallel by default**
   - Independent tasks run concurrently
   - Serial execution is opt-in
   - Connection pooling maximizes throughput

3. **Fail fast, fail clearly**
   - Validate config before execution
   - First error stops pipeline (configurable)
   - Error messages include context and suggestions

4. **No YAML**
   - Elixir DSL provides full programming language
   - Syntax errors are caught at parse time
   - IDE support (ElixirLS) for autocomplete

5. **Progressive disclosure**
   - Simple tasks require minimal syntax
   - Advanced features are additive, not required
   - Sensible defaults everywhere

### 4.2 Technical Principles

1. **OTP for reliability**
   - Supervision trees for fault isolation
   - GenServers for state management
   - Process-per-task for isolation

2. **Telemetry from day one**
   - All operations emit telemetry events
   - Users can attach their own handlers
   - Foundation for observability

3. **Typed structs, not maps**
   - All data structures are typed
   - Dialyzer-clean codebase
   - Compile-time error detection

4. **Test everything**
   - Unit tests for business logic
   - Integration tests against real SSH
   - Property-based tests for parsers

---

## 5. Version Roadmap Overview

```
v0.1 - Core (Production Ready)
├── Local task execution
├── SSH remote execution
├── DAG dependencies
├── Parallel execution
├── Retries & timeouts
├── Connection pooling
├── Error handling
├── Logging & telemetry
└── Cross-platform binaries

v0.2 - Enhanced Operations
├── Tailscale auto-discovery
├── File upload/download
├── EEx templates
├── Artifacts
├── Secrets management
├── Rolling deployments
└── Handlers (notify)

v0.3 - Distributed & Cloud
├── Agent mode (daemon)
├── Mesh networking
├── Cloud bursting (AWS/GCP/Hetzner)
├── Spot instance management
├── Auto-scaling
└── TUI (Ratatouille)

v0.4 - Enterprise
├── Azure native integration
├── Azure AD / Kerberos auth
├── Azure Bastion / Run Command
├── RBAC
├── Audit logging
└── SSO integration
```

---

## 6. v0.1 - Core (Production Ready)

### 6.1 Overview

The minimum viable product that is genuinely production-ready. Not a prototype - a tool you can rely on for real workloads.

**Timeline:** 10 weeks
**Estimated LOC:** ~2,500

### 6.2 Functional Requirements

#### 6.2.1 DSL & Configuration

**REQ-0101: Task Definition**
```elixir
task :name, opts do
  run "command"
end
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| name | atom | Yes | - | Unique task identifier |
| deps | [atom] | No | [] | Tasks that must complete first |
| on | atom \| :local | No | :local | Host group or :local |
| timeout | integer | No | 300_000 | Task-level timeout (ms) |

**REQ-0102: Host Definition**
```elixir
hosts :name do
  "hostname-or-ip"
  "user@hostname"
  "user@hostname:port"
end
```

Hosts can be specified as:
- `"hostname"` - Uses current user, port 22
- `"user@hostname"` - Specified user, port 22
- `"user@hostname:2222"` - Specified user and port

**REQ-0103: Run Command**
```elixir
run "command", opts
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| sudo | boolean | false | Run with sudo |
| user | string | nil | Run as user (requires sudo) |
| timeout | integer | 60_000 | Command timeout (ms) |
| retries | integer | 0 | Number of retry attempts |
| retry_delay | integer | 1_000 | Delay between retries (ms) |
| continue_on_error | boolean | false | Don't fail task if command fails |

**REQ-0104: Global Configuration**
```elixir
config :nexus do
  ssh_user "deploy"
  ssh_identity "~/.ssh/deploy_key"
  ssh_port 22
  parallel_limit 10
  log_level :info
end
```

**REQ-0105: Environment Variables**
```elixir
task :deploy do
  run "echo #{env("DEPLOY_ENV", "production")}"
end
```
- `env("VAR")` - Required, fails if not set
- `env("VAR", "default")` - Optional with default

#### 6.2.2 Task Execution

**REQ-0110: Dependency Resolution**
- Tasks form a Directed Acyclic Graph (DAG)
- Nexus computes topological order
- Tasks with satisfied deps run in parallel
- Circular dependencies are detected at validation time

**REQ-0111: Parallel Execution**
- Independent tasks run concurrently
- Tasks within the same dependency level run in parallel
- `parallel_limit` config caps concurrent tasks
- Per-host connection pooling prevents SSH exhaustion

**REQ-0112: Local Execution**
- Tasks with `on: :local` run on the invoking machine
- Uses Erlang `:os.cmd/1` or Port for streaming
- Inherits environment from Nexus process
- Working directory is project root (location of nexus.exs)

**REQ-0113: Remote Execution**
- Tasks with `on: :group` run on all hosts in group
- Commands execute in parallel across hosts
- Each host gets its own SSH connection (pooled)
- Output is tagged with hostname

**REQ-0114: Execution Strategies**
```elixir
task :deploy, on: :web, strategy: :parallel do  # default
  run "..."
end

task :deploy, on: :web, strategy: :serial do
  run "..."  # One host at a time
end
```

#### 6.2.3 SSH

**REQ-0120: Connection Establishment**
- Support key-based authentication (RSA, Ed25519, ECDSA)
- Support SSH agent forwarding
- Support password auth (interactive prompt)
- Connection timeout: 10 seconds (configurable)
- Automatic retry on connection failure (3 attempts, exponential backoff)

**REQ-0121: Connection Pooling**
- Maintain pool of connections per host
- Default pool size: 4 connections per host
- Connections are reused across commands
- Idle connections closed after 60 seconds
- Graceful handling of stale connections

**REQ-0122: Command Execution**
- Execute via SSH exec channel
- Stream stdout/stderr in real-time
- Capture exit code
- Timeout handling with channel cleanup
- Support for PTY allocation (for sudo)

**REQ-0123: Authentication Priority**
1. Explicit `ssh_identity` in config
2. `SSH_AUTH_SOCK` (agent)
3. `~/.ssh/id_ed25519`
4. `~/.ssh/id_rsa`
5. Interactive password prompt

#### 6.2.4 Error Handling

**REQ-0130: Validation Errors**
Detected before execution begins:
- Circular dependencies
- References to undefined tasks
- References to undefined host groups
- Empty tasks (no commands)
- Invalid option values
- Syntax errors in nexus.exs

Error format:
```
Error: Validation failed

  nexus.exs:15: Task :deploy depends on undefined task :buld
                Did you mean :build?

  nexus.exs:23: Host group :databases is not defined
                Defined groups: :web, :workers
```

**REQ-0131: Connection Errors**
- Clear message indicating which host failed
- Reason (refused, timeout, auth failed)
- Suggestion for resolution
- Partial success handling (some hosts connected)

Error format:
```
Error: SSH connection failed

  Host: web-3.example.com
  Reason: Connection refused (port 22)

  Suggestions:
    - Verify the host is reachable: ping web-3.example.com
    - Check if SSH is running: nc -zv web-3.example.com 22
    - Verify firewall rules allow port 22
```

**REQ-0132: Command Errors**
- Show which host, which command
- Exit code and stderr
- Partial output context
- Commands that succeeded before failure

Error format:
```
Error: Command failed

  Host: web-2.example.com
  Task: :deploy
  Command: systemctl restart myapp
  Exit code: 1

  Output:
    Job for myapp.service failed because the control process exited with error code.
    See "systemctl status myapp.service" and "journalctl -xe" for details.

  Previous commands in this task succeeded:
    ✓ systemctl stop myapp
    ✓ cp -r /tmp/build/* /opt/myapp/
```

**REQ-0133: Timeout Errors**
- Indicate timeout value
- Show partial output
- Clean up resources (close channel)

**REQ-0134: Pipeline Behavior on Error**
- Default: Stop pipeline on first error
- Option: `--continue-on-error` to run all tasks
- Failed tasks prevent dependent tasks from running
- Summary shows what succeeded/failed/skipped

#### 6.2.5 CLI

**REQ-0140: Commands**

| Command | Description |
|---------|-------------|
| `nexus run <task> [tasks...]` | Execute task(s) and dependencies |
| `nexus preflight <task>` | Run pre-flight checks without executing |
| `nexus list` | List all defined tasks |
| `nexus validate` | Validate nexus.exs without executing |
| `nexus init` | Create template nexus.exs |
| `nexus version` | Show version info |
| `nexus help [command]` | Show help |

**REQ-0141: Run Options**

| Option | Short | Description |
|--------|-------|-------------|
| `--dry-run` | `-n` | Show what would execute |
| `--verbose` | `-v` | Increase output verbosity |
| `--quiet` | `-q` | Minimal output |
| `--continue-on-error` | | Don't stop on first failure |
| `--identity <path>` | `-i` | SSH private key path |
| `--user <name>` | `-u` | SSH user |
| `--parallel-limit <n>` | `-p` | Max concurrent tasks |
| `--hosts <list>` | `-h` | Override hosts (comma-separated) |
| `--config <path>` | `-c` | Path to nexus.exs |

**REQ-0142: Exit Codes**

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Task/command failure |
| 2 | Configuration/validation error |
| 3 | SSH/connection error |
| 4 | Timeout |
| 130 | Interrupted (Ctrl+C) |

**REQ-0143: Output Format**

Normal mode:
```
● :build
  └─ npm run build ✓ 12.3s

● :deploy [web-1, web-2]
  ├─ web-1 ✓ 4.2s
  └─ web-2 ✓ 4.1s

✓ Completed in 16.5s
```

Verbose mode (`-v`):
```
● :build
  ├─ npm run build
  │  > npm WARN deprecated...
  │  > added 523 packages in 12.3s
  └─ ✓ 12.3s

● :deploy [web-1, web-2]
  ├─ web-1
  │  ├─ systemctl stop myapp
  │  │  >
  │  ├─ cp -r /tmp/build/* /opt/myapp/
  │  │  >
  │  └─ systemctl start myapp
  │     >
  │  └─ ✓ 4.2s
  ...
```

Quiet mode (`-q`):
```
✓ build (12.3s)
✓ deploy (4.2s)
```

#### 6.2.6 Dry-Run & Pre-Flight Checks

**REQ-0170: Dry-Run Mode**
```bash
nexus run deploy --dry-run
# or
nexus run deploy -n
```

Dry-run mode shows exactly what would happen without executing anything.

**REQ-0171: Dry-Run Output**
```
$ nexus run deploy --dry-run

╔══════════════════════════════════════════════════════════════════╗
║                         DRY RUN MODE                             ║
║              No commands will be executed                        ║
╚══════════════════════════════════════════════════════════════════╝

┌─ PRE-FLIGHT CHECKS ──────────────────────────────────────────────┐
│                                                                  │
│ Configuration                                                    │
│   ✓ nexus.exs parsed successfully                               │
│   ✓ No circular dependencies                                    │
│   ✓ All task references valid                                   │
│   ✓ All host groups defined                                     │
│                                                                  │
│ Hosts                                                            │
│   ✓ web-1.example.com - reachable (23ms)                        │
│   ✓ web-2.example.com - reachable (31ms)                        │
│   ✓ web-3.example.com - reachable (28ms)                        │
│                                                                  │
│ SSH Authentication                                               │
│   ✓ web-1.example.com - key accepted                            │
│   ✓ web-2.example.com - key accepted                            │
│   ✓ web-3.example.com - key accepted                            │
│                                                                  │
│ Permissions                                                      │
│   ✓ web-1.example.com - sudo available                          │
│   ✓ web-2.example.com - sudo available                          │
│   ✓ web-3.example.com - sudo available                          │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘

┌─ EXECUTION PLAN ─────────────────────────────────────────────────┐
│                                                                  │
│ Phase 1 (parallel):                                              │
│   ● :build [local]                                              │
│     └─ npm run build                                            │
│   ● :backup_db [db.example.com]                                 │
│     └─ pg_dump myapp > /backups/pre-deploy.sql  [sudo:postgres] │
│                                                                  │
│ Phase 2 (rolling, 1 at a time):                                  │
│   ● :deploy [web-1, web-2, web-3]                               │
│     ├─ systemctl stop myapp                        [sudo]       │
│     ├─ cp -r /tmp/build/* /opt/myapp/                           │
│     ├─ systemctl start myapp                       [sudo]       │
│     └─ curl -f http://localhost:8080/health        [retries:5]  │
│                                                                  │
│ Phase 3:                                                         │
│   ● :migrate [db.example.com]                                   │
│     └─ cd /opt/myapp && ./migrate.sh              [sudo:myapp]  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘

┌─ SUMMARY ────────────────────────────────────────────────────────┐
│                                                                  │
│ Tasks:        4 tasks, 3 phases                                  │
│ Hosts:        4 unique hosts                                     │
│ Commands:     8 commands total                                   │
│ Strategy:     :deploy uses rolling (1 at a time)                │
│ Estimated:    ~45s (based on previous runs)                     │
│                                                                  │
│ Run without --dry-run to execute.                               │
└──────────────────────────────────────────────────────────────────┘
```

**REQ-0172: Pre-Flight Check Categories**

| Category | Checks Performed | Blocking |
|----------|------------------|----------|
| **Config Validation** | Syntax, types, references, cycles | Yes |
| **Host Reachability** | TCP ping to SSH port | Configurable |
| **SSH Authentication** | Key/password acceptance | Yes |
| **Sudo Availability** | Can execute sudo (if task needs it) | Yes |
| **Disk Space** | Remote disk space (if uploading) | Configurable |
| **Required Commands** | Binary exists on remote (v0.2+) | Configurable |
| **File Existence** | Source files exist locally | Yes |
| **Permissions** | RBAC checks (v0.4+) | Yes |

**REQ-0173: Pre-Flight Check Command**
```bash
# Run only pre-flight checks, no execution plan
nexus preflight deploy

# Check specific hosts
nexus preflight deploy --hosts web-1.example.com

# Skip specific checks
nexus preflight deploy --skip-sudo-check

# JSON output for CI
nexus preflight deploy --format json
```

**REQ-0174: Pre-Flight Check Output (Standalone)**
```
$ nexus preflight deploy

Pre-flight checks for: deploy

Configuration
  ✓ nexus.exs valid
  ✓ Task :deploy exists
  ✓ Dependencies resolved: build → deploy

Host Connectivity [3/3]
  ✓ web-1.example.com:22  (23ms, SSH-2.0-OpenSSH_8.9)
  ✓ web-2.example.com:22  (31ms, SSH-2.0-OpenSSH_8.9)
  ✓ web-3.example.com:22  (28ms, SSH-2.0-OpenSSH_8.9)

SSH Authentication [3/3]
  ✓ web-1.example.com  (key: ~/.ssh/deploy_key)
  ✓ web-2.example.com  (key: ~/.ssh/deploy_key)
  ✓ web-3.example.com  (key: ~/.ssh/deploy_key)

Sudo Access [3/3]
  ✓ web-1.example.com  (NOPASSWD confirmed)
  ✓ web-2.example.com  (NOPASSWD confirmed)
  ✓ web-3.example.com  (NOPASSWD confirmed)

Local Files
  ✓ dist/app.tar.gz exists (2.3MB)

✓ All pre-flight checks passed (12 checks in 1.2s)
```

**REQ-0175: Pre-Flight Check Failures**
```
$ nexus preflight deploy

Pre-flight checks for: deploy

Configuration
  ✓ nexus.exs valid
  ✓ Task :deploy exists
  ✓ Dependencies resolved

Host Connectivity [2/3]
  ✓ web-1.example.com:22  (23ms)
  ✓ web-2.example.com:22  (31ms)
  ✗ web-3.example.com:22  Connection refused

SSH Authentication [2/2]
  ✓ web-1.example.com
  ✓ web-2.example.com
  ⊘ web-3.example.com  (skipped - host unreachable)

Sudo Access [1/2]
  ✓ web-1.example.com
  ✗ web-2.example.com  "deploy is not in the sudoers file"
  ⊘ web-3.example.com  (skipped - host unreachable)

✗ Pre-flight checks failed (2 errors)

Errors:
  1. web-3.example.com: Connection refused (port 22)
     → Verify SSH is running: systemctl status sshd
     → Check firewall: ufw status / iptables -L

  2. web-2.example.com: Sudo not available for user 'deploy'
     → Add to sudoers: echo "deploy ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/deploy
     → Or use --skip-sudo-check if sudo not required

Run with --force to skip failed hosts and continue with available hosts.
```

**REQ-0176: Pre-Flight Options**

| Option | Description |
|--------|-------------|
| `--skip-connectivity` | Don't check host reachability |
| `--skip-auth` | Don't verify SSH authentication |
| `--skip-sudo-check` | Don't verify sudo access |
| `--skip-disk-check` | Don't check remote disk space |
| `--timeout <ms>` | Timeout for connectivity checks (default: 5000) |
| `--parallel <n>` | Parallel host checks (default: 10) |
| `--force` | Continue despite failures (mark hosts as unavailable) |
| `--format <fmt>` | Output format: text, json, quiet |

**REQ-0177: Pre-Flight in CI/CD**
```bash
# CI pipeline example
- name: Pre-flight checks
  run: |
    nexus preflight deploy --format json > preflight.json
    if [ $? -ne 0 ]; then
      echo "Pre-flight failed"
      cat preflight.json | jq '.errors'
      exit 1
    fi

- name: Deploy
  run: nexus run deploy
```

**REQ-0178: Diff Mode for Templates (v0.2+)**
```bash
nexus run configure --dry-run
```
```
● :configure [web-1.example.com]

  template: nginx.conf.eex → /etc/nginx/nginx.conf

  --- /etc/nginx/nginx.conf (current)
  +++ /etc/nginx/nginx.conf (proposed)
  @@ -12,7 +12,7 @@
       server {
           listen 80;
  -        server_name old.example.com;
  +        server_name new.example.com;
           
           location / {
  -            proxy_pass http://localhost:3000;
  +            proxy_pass http://localhost:8080;
           }
       }

  [y]es, [n]o, [d]iff, [a]ll: _
```

**REQ-0179: Interactive Dry-Run (v0.2+)**
```bash
nexus run deploy --dry-run --interactive
```
```
╔══════════════════════════════════════════════════════════════════╗
║                      INTERACTIVE DRY RUN                         ║
╚══════════════════════════════════════════════════════════════════╝

Pre-flight checks passed. Review execution plan:

Phase 1: :build [local]
  │ npm run build
  │
  └─ [Enter] continue, [s]kip task, [q]uit: _

Phase 2: :deploy [web-1, web-2, web-3] (rolling)
  │ Host: web-1.example.com
  │   systemctl stop myapp    [sudo]
  │   cp -r /tmp/build/* /opt/myapp/
  │   systemctl start myapp   [sudo]
  │
  └─ [Enter] continue, [s]kip host, [S]kip task, [q]uit: _
```

**REQ-0180: Pre-Flight Check Implementation**

```elixir
# lib/nexus/preflight/checker.ex
defmodule Nexus.Preflight.Checker do
  @type check_result :: :ok | {:error, String.t()} | {:skip, String.t()}
  
  @type check :: %{
    name: String.t(),
    category: atom(),
    host: String.t() | nil,
    status: :pending | :running | :passed | :failed | :skipped,
    duration_ms: non_neg_integer() | nil,
    error: String.t() | nil
  }
  
  @type report :: %{
    checks: [check()],
    passed: non_neg_integer(),
    failed: non_neg_integer(),
    skipped: non_neg_integer(),
    duration_ms: non_neg_integer(),
    errors: [String.t()]
  }
  
  @spec run(Pipeline.t(), keyword()) :: {:ok, report()} | {:error, report()}
  def run(pipeline, opts \\ [])
  
  @spec check_connectivity(Host.t(), keyword()) :: check_result()
  def check_connectivity(host, opts \\ [])
  
  @spec check_ssh_auth(Host.t(), keyword()) :: check_result()
  def check_ssh_auth(host, opts \\ [])
  
  @spec check_sudo(Host.t(), String.t(), keyword()) :: check_result()
  def check_sudo(host, user, opts \\ [])
  
  @spec check_disk_space(Host.t(), String.t(), non_neg_integer()) :: check_result()
  def check_disk_space(host, path, required_bytes)
  
  @spec check_command_exists(Host.t(), String.t()) :: check_result()
  def check_command_exists(host, command)
end
```

**REQ-0181: Pre-Flight Telemetry Events**

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:nexus, :preflight, :start]` | | pipeline, hosts |
| `[:nexus, :preflight, :stop]` | duration | passed, failed, skipped |
| `[:nexus, :preflight, :check, :start]` | | check_name, host |
| `[:nexus, :preflight, :check, :stop]` | duration | check_name, host, status |

**REQ-0182: Dry-Run with Cost Estimation (v0.3+)**
```bash
nexus run heavy-job --dry-run --scale cloud=5
```
```
╔══════════════════════════════════════════════════════════════════╗
║                         DRY RUN MODE                             ║
╚══════════════════════════════════════════════════════════════════╝

┌─ CLOUD RESOURCES ────────────────────────────────────────────────┐
│                                                                  │
│ Provider: AWS (us-west-2)                                        │
│ Instance Type: c6i.4xlarge (16 vCPU, 32GB RAM)                  │
│ Pricing: Spot @ $0.10/hr (current: $0.087/hr)                   │
│                                                                  │
│ Instances to provision: 5                                        │
│ Estimated runtime: 15 minutes                                    │
│ Estimated cost: $0.11 - $0.15                                   │
│                                                                  │
│ ⚠ Spot instances may be interrupted. Use --spot-fallback        │
│   on-demand to ensure completion.                                │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘

┌─ EXECUTION PLAN ─────────────────────────────────────────────────┐
│ ...                                                              │
└──────────────────────────────────────────────────────────────────┘
```

**REQ-0183: What-If Analysis (v0.3+)**
```bash
# What if a host is unavailable?
nexus run deploy --dry-run --simulate-failure web-2.example.com
```
```
╔══════════════════════════════════════════════════════════════════╗
║                      WHAT-IF ANALYSIS                            ║
║         Simulating failure of: web-2.example.com                 ║
╚══════════════════════════════════════════════════════════════════╝

With rolling strategy (:deploy):
  • web-1.example.com: Would execute normally
  • web-2.example.com: ✗ SIMULATED FAILURE
  • web-3.example.com: Would be SKIPPED (pipeline stops on failure)

Impact:
  • 1 of 3 hosts would be updated
  • Service would be partially deployed (version mismatch)
  
Recommendations:
  • Use --continue-on-error to update remaining hosts
  • Or use strategy: :parallel with health checks
  • Consider blue-green deployment for zero-downtime
```

#### 6.2.7 Logging & Telemetry

**REQ-0150: Log Levels**
- `:debug` - Internal details, SSH traffic
- `:info` - Task start/complete, connections
- `:warning` - Retries, non-fatal issues
- `:error` - Failures

**REQ-0151: Log Output**
- Stderr for logs, stdout for results
- Configurable via `--log-level` or config
- Structured format available via `--log-format json`

**REQ-0152: Telemetry Events**

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:nexus, :pipeline, :start]` | | tasks, hosts |
| `[:nexus, :pipeline, :stop]` | duration | status, tasks_completed |
| `[:nexus, :task, :start]` | | task, hosts |
| `[:nexus, :task, :stop]` | duration | task, status |
| `[:nexus, :command, :start]` | | task, host, command |
| `[:nexus, :command, :stop]` | duration | task, host, command, exit_code |
| `[:nexus, :ssh, :connect]` | | host |
| `[:nexus, :ssh, :disconnect]` | | host, reason |
| `[:nexus, :ssh, :error]` | | host, reason |

### 6.3 Non-Functional Requirements for v0.1

**REQ-0160: Performance**
- SSH connection establishment: <2s per host
- Command overhead: <50ms per command
- Support 100+ concurrent connections
- Memory usage: <100MB for typical workloads

**REQ-0161: Reliability**
- Zero crashes from malformed user input
- Graceful degradation on network issues
- Clean shutdown on SIGINT/SIGTERM
- No zombie processes

**REQ-0162: Compatibility**
- Elixir 1.15+
- OTP 25+
- Linux (x86_64, arm64)
- macOS (x86_64, arm64)
- Target SSH servers: OpenSSH 7.0+

**REQ-0163: Packaging**
- Self-contained binary via Burrito
- No runtime dependencies
- Install via curl | sh
- Escript alternative for Elixir users

### 6.4 File Structure for v0.1

```
lib/
├── nexus.ex                    # Main entry point
├── nexus/
│   ├── application.ex          # OTP Application
│   ├── cli.ex                  # CLI argument parsing
│   ├── cli/
│   │   ├── run.ex              # Run command
│   │   ├── preflight.ex        # Pre-flight checks command
│   │   ├── list.ex             # List command
│   │   ├── validate.ex         # Validate command
│   │   └── init.ex             # Init command
│   ├── preflight/
│   │   ├── checker.ex          # Pre-flight check orchestration
│   │   ├── connectivity.ex     # Host reachability checks
│   │   ├── auth.ex             # SSH auth verification
│   │   ├── sudo.ex             # Sudo availability checks
│   │   ├── disk.ex             # Disk space checks
│   │   └── report.ex           # Check result formatting
│   ├── config.ex               # Configuration loading
│   ├── dsl/
│   │   ├── parser.ex           # nexus.exs evaluation
│   │   ├── validator.ex        # Validation rules
│   │   └── types.ex            # Typed structs
│   ├── dag.ex                  # Dependency graph
│   ├── executor/
│   │   ├── supervisor.ex       # Execution supervision
│   │   ├── pipeline.ex         # Pipeline orchestration
│   │   ├── task_runner.ex      # Individual task execution
│   │   └── local.ex            # Local command execution
│   ├── ssh/
│   │   ├── pool.ex             # Connection pooling
│   │   ├── connection.ex       # Connection management
│   │   ├── channel.ex          # Channel operations
│   │   └── auth.ex             # Authentication handling
│   ├── output/
│   │   ├── formatter.ex        # Output formatting
│   │   ├── renderer.ex         # Terminal rendering
│   │   └── colors.ex           # ANSI colors
│   ├── telemetry.ex            # Telemetry setup
│   └── errors.ex               # Error types
test/
├── unit/
│   ├── dsl/
│   │   ├── parser_test.exs
│   │   └── validator_test.exs
│   ├── dag_test.exs
│   ├── preflight/
│   │   ├── checker_test.exs
│   │   ├── connectivity_test.exs
│   │   └── report_test.exs
│   └── executor/
│       └── pipeline_test.exs
├── integration/
│   ├── local_exec_test.exs
│   ├── ssh_test.exs
│   ├── preflight_test.exs
│   └── full_pipeline_test.exs
├── support/
│   ├── docker_ssh.ex           # SSH container helper
│   └── fixtures/
│       ├── valid_nexus.exs
│       ├── invalid_cycle.exs
│       └── ssh_keys/
└── test_helper.exs
```

### 6.5 Dependencies for v0.1

> **IMPORTANT**: Always use latest stable versions. Run `mix hex.outdated` regularly.
> Check [Hex.pm](https://hex.pm) and [GitHub Security Advisories](https://github.com/advisories) for CVEs.
> Use `mix deps.audit` (via `mix_audit`) to scan for known vulnerabilities.
>
> **Library Research Status:** All dependencies validated December 2025. See [Section 15](#15-library-research--recommendations) for detailed analysis.

```elixir
defp deps do
  [
    # ══════════════════════════════════════════════════════════════
    # CLI & Terminal
    # ══════════════════════════════════════════════════════════════
    
    # CLI argument parsing - full-featured with subcommands, auto-help
    # https://hex.pm/packages/optimus | https://github.com/funbox/optimus
    # Status: Active, well-maintained
    {:optimus, "~> 0.5"},

    # Terminal output (pretty printing, progress bars, colors, boxes)
    # https://hex.pm/packages/owl | https://github.com/fuelen/owl
    # Status: Active (v0.13+), feature-rich CLI toolkit
    {:owl, "~> 0.13"},

    # ══════════════════════════════════════════════════════════════
    # SSH - CRITICAL PATH
    # ══════════════════════════════════════════════════════════════
    
    # SSH toolkit built on Erlang's :ssh - PRIMARY SSH LIBRARY
    # https://hex.pm/packages/sshkit | https://github.com/bitcrowd/sshkit.ex
    # Status: Active (SSHEx was ARCHIVED Oct 2024, do NOT use)
    # Note: May need to extend for advanced features (PTY, streaming)
    {:sshkit, "~> 0.3"},
    
    # SFTP client for file transfers (upload/download)
    # https://hex.pm/packages/sftp_client
    # Status: Active, wraps Erlang's :ssh_sftp
    {:sftp_client, "~> 2.0"},
    
    # SSH client key API implementation (for custom key handling)
    # https://hex.pm/packages/ssh_client_key_api
    # Status: Active, useful for key management
    {:ssh_client_key_api, "~> 0.3"},

    # ══════════════════════════════════════════════════════════════
    # Core Infrastructure
    # ══════════════════════════════════════════════════════════════
    
    # Connection pooling - tiny footprint, resource-focused
    # https://hex.pm/packages/nimble_pool | https://github.com/dashbitco/nimble_pool
    # Status: Active, used by Finch/Ecto, ideal for SSH pools
    {:nimble_pool, "~> 1.1"},

    # DAG/Graph library for dependency resolution
    # https://hex.pm/packages/libgraph | https://github.com/bitwalker/libgraph
    # Status: Active, comprehensive API, by libcluster author
    {:libgraph, "~> 0.16"},

    # Configuration/option validation with auto-generated docs
    # https://hex.pm/packages/nimble_options | https://github.com/dashbitco/nimble_options
    # Status: Active (v1.1.1), perfect for DSL option validation
    {:nimble_options, "~> 1.1"},

    # ══════════════════════════════════════════════════════════════
    # Observability
    # ══════════════════════════════════════════════════════════════
    
    # Telemetry - core event emission
    # https://hex.pm/packages/telemetry
    # Status: Core Elixir ecosystem library
    {:telemetry, "~> 1.3"},
    
    # Telemetry metrics aggregation
    # https://hex.pm/packages/telemetry_metrics
    {:telemetry_metrics, "~> 1.0"},

    # ══════════════════════════════════════════════════════════════
    # Packaging & Distribution
    # ══════════════════════════════════════════════════════════════
    
    # Binary packaging (single executable) - uses Zig for cross-compilation
    # https://hex.pm/packages/burrito
    # Status: Active (Bakeware was ARCHIVED Sep 2024, do NOT use)
    {:burrito, "~> 1.0"},

    # ══════════════════════════════════════════════════════════════
    # Dev & Test
    # ══════════════════════════════════════════════════════════════
    
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:ex_doc, "~> 0.35", only: :dev, runtime: false},
    {:mox, "~> 1.2", only: :test},

    # Security auditing
    {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
    {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
  ]
end
```

**Dependency Security Policy:**
1. Pin to minor version (`~> 1.3`) not patch (`~> 1.3.0`) for auto security patches
2. Run `mix deps.audit` in CI on every build
3. Run `mix sobelow` for static security analysis
4. Subscribe to GitHub security advisories for all deps
5. Update deps monthly minimum, immediately for CVEs
6. Document reason for any version pins in `mix.exs` comments

**Critical Dependency Notes:**
- **SSH**: SSHKit is the only actively maintained high-level SSH wrapper. SSHEx was archived October 2024.
- **Packaging**: Burrito is the only option. Bakeware was archived September 2024.
- **DAG**: libgraph preferred over Erlang's `:digraph` for Elixir-native API.

---

## 7. v0.2 - Enhanced Operations

### 7.1 Overview

Builds on v0.1 with features needed for real-world infrastructure management. Adds Tailscale integration, file operations, and secrets.

**Timeline:** 6 weeks (after v0.1)
**Prerequisites:** v0.1 complete

### 7.2 Functional Requirements

#### 7.2.1 Tailscale Auto-Discovery

**REQ-0201: Tailscale Detection**
```elixir
cluster :tailscale do
  auto_discover true
  filter tags: ["tag:nexus-agent"]  # Optional filter
end
```

- Detect if running on a Tailscale network
- Query Tailscale API for peer list
- Auto-populate hosts based on MagicDNS names
- Refresh on each run (or cache with TTL)

**REQ-0202: Tailscale Authentication**
- Use Tailscale identity for auth (no separate SSH keys)
- Support ACL-based access control
- Fallback to SSH key auth if Tailscale unavailable

**REQ-0203: Host Filtering**
```elixir
cluster :tailscale do
  auto_discover true
  filter tags: ["tag:web"]
  filter os: "linux"
  exclude hostname: ~r/^test-/
end
```

#### 7.2.2 File Operations

**REQ-0210: Upload**
```elixir
task :deploy do
  upload "local/path/file.tar.gz", to: "/remote/path/"
  upload "local/dir/", to: "/remote/dir/", recursive: true
end
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| to | string | required | Remote destination path |
| recursive | boolean | false | Upload directory recursively |
| preserve | boolean | true | Preserve permissions/timestamps |
| sudo | boolean | false | Write as root |

- Use SFTP subsystem
- Show progress for large files
- Verify checksum after transfer
- Resume partial transfers

**REQ-0211: Download**
```elixir
task :backup do
  download "/var/log/app.log", to: "logs/app-#{hostname()}.log"
end
```

- SFTP-based download
- Support for dynamic local paths
- Create local directories as needed

**REQ-0212: Templates**
```elixir
task :configure do
  template "templates/nginx.conf.eex",
    to: "/etc/nginx/nginx.conf",
    vars: %{
      domain: "example.com",
      port: 8080,
      workers: System.schedulers_online()
    },
    sudo: true
end
```

- EEx (Elixir) template syntax
- Access to task context in templates
- Validation of template output before upload
- Diff display in dry-run mode

#### 7.2.3 Artifacts

**REQ-0220: Artifact Declaration**
```elixir
task :build, on: "build-server.tail" do
  run "make"
  artifact "build/output.tar.gz"
end

task :deploy, on: :web, deps: [:build] do
  # Artifact automatically available here
  run "tar -xzf build/output.tar.gz"
end
```

- Artifacts are files produced by tasks
- Automatically transferred to dependent tasks
- Stored temporarily during pipeline execution
- Cleaned up after pipeline completes

**REQ-0221: Artifact Storage**
- Default: Local temp directory on coordinator
- Option: S3/GCS for large artifacts
- Streaming transfer (don't buffer entire file)

#### 7.2.4 Secrets Management

**REQ-0230: Secret Definition**
```bash
# CLI
nexus secret set DB_PASSWORD
# Prompts for value, encrypts, stores in ~/.nexus/secrets.enc

nexus secret set API_KEY --from-file ./api_key.txt

nexus secret list
nexus secret delete DB_PASSWORD
```

**REQ-0231: Secret Usage**
```elixir
task :deploy do
  run "DATABASE_URL=#{secret("DB_PASSWORD")} ./migrate.sh"

  # Or write to file on remote
  secret "TLS_CERT", to: "/etc/ssl/app.crt", sudo: true
end
```

- Secrets encrypted at rest (AES-256-GCM)
- Master key derived from passphrase or keyfile
- Secrets never logged
- Secrets redacted in output

**REQ-0232: Secret Scoping**
```elixir
task :deploy, on: :web do
  # Only decrypted on target hosts, not coordinator
  secret "APP_SECRET", to: "/etc/app/secret", remote_only: true
end
```

#### 7.2.5 Deployment Strategies

**REQ-0240: Rolling Deployment**
```elixir
task :deploy, on: :web, strategy: :rolling do
  run "systemctl stop myapp"
  run "cp -r /tmp/build/* /opt/app/"
  run "systemctl start myapp"

  # Health check before proceeding to next host
  wait_for "curl -f http://localhost:8080/health",
    timeout: 30_000,
    interval: 1_000
end
```

- Execute on one host at a time
- Wait for health check before next host
- Configurable parallelism (e.g., 2 at a time)
- Rollback on failure (optional)

**REQ-0241: Canary Deployment**
```elixir
task :deploy, on: :web, strategy: :canary do
  canary_hosts 1  # Deploy to 1 host first
  canary_wait 60  # Wait 60s and check health

  run "..."
end
```

**REQ-0242: Blue-Green (Manual)**
```elixir
hosts :blue do
  "web-blue-1.tail"
  "web-blue-2.tail"
end

hosts :green do
  "web-green-1.tail"
  "web-green-2.tail"
end

task :deploy_blue, on: :blue do
  run "..."
end

task :deploy_green, on: :green do
  run "..."
end

task :switch_to_blue do
  run "update-lb --backend blue"
end
```

#### 7.2.6 Handlers (Notify)

**REQ-0250: Handler Definition**
```elixir
handler :restart_nginx do
  run "systemctl restart nginx", sudo: true
end

task :update_config do
  upload "nginx.conf", to: "/etc/nginx/nginx.conf",
    sudo: true,
    notify: :restart_nginx
end
```

- Handlers run once at end of task, even if notified multiple times
- Handlers run on same host as notifying command
- Handlers can notify other handlers

#### 7.2.7 Built-in Functions

**REQ-0260: Context Functions**
Available in DSL:

| Function | Returns | Description |
|----------|---------|-------------|
| `hostname()` | string | Current target hostname |
| `timestamp()` | string | ISO 8601 timestamp |
| `git_sha()` | string | Current git commit SHA |
| `git_branch()` | string | Current git branch |
| `env(name)` | string | Environment variable (required) |
| `env(name, default)` | string | Environment variable (optional) |
| `secret(name)` | string | Decrypted secret value |

### 7.3 File Additions for v0.2

```
lib/nexus/
├── tailscale/
│   ├── discovery.ex        # Peer discovery
│   ├── api.ex              # Tailscale API client
│   └── auth.ex             # Tailscale-based auth
├── transfer/
│   ├── sftp.ex             # SFTP operations
│   ├── upload.ex           # Upload logic
│   ├── download.ex         # Download logic
│   └── artifact.ex         # Artifact management
├── template/
│   ├── renderer.ex         # EEx rendering
│   └── validator.ex        # Template validation
├── secrets/
│   ├── store.ex            # Encrypted storage
│   ├── crypto.ex           # Encryption/decryption
│   └── cli.ex              # Secret CLI commands
└── strategy/
    ├── parallel.ex         # Parallel execution
    ├── serial.ex           # Serial execution
    ├── rolling.ex          # Rolling deployment
    └── canary.ex           # Canary deployment
```

### 7.4 New Dependencies for v0.2

> Always verify latest versions at [Hex.pm](https://hex.pm) before implementation.
> **Library Research Status:** All dependencies validated December 2025.

```elixir
# ══════════════════════════════════════════════════════════════
# HTTP & API Clients
# ══════════════════════════════════════════════════════════════

# HTTP client - batteries-included, built on Finch/Mint
# https://hex.pm/packages/req | https://github.com/wojtekmach/req
# Status: Very Active, becoming Phoenix default, recommended for all HTTP
# Used for: Tailscale API, future cloud provider APIs
{:req, "~> 0.5"},

# ══════════════════════════════════════════════════════════════
# Tailscale Integration
# ══════════════════════════════════════════════════════════════

# Tailscale libcluster strategy for node discovery
# https://hex.pm/packages/libcluster_tailscale | https://github.com/moomerman/libcluster_tailscale
# Status: Active, discovers nodes via Tailscale API
{:libcluster_tailscale, "~> 0.1"},

# Alternative: Full Tailscale Elixir library (optional)
# https://github.com/arjunbajaj/tailscale-elixir
# Status: Active, provides Tailnet state and event subscriptions
# {:tailscale, github: "arjunbajaj/tailscale-elixir"},

# ══════════════════════════════════════════════════════════════
# Template & Parsing
# ══════════════════════════════════════════════════════════════

# Parser combinator library for custom DSL parsing
# https://hex.pm/packages/nimble_parsec | https://github.com/dashbitco/nimble_parsec
# Status: Active, used throughout Elixir ecosystem
{:nimble_parsec, "~> 1.4"},

# Note: EEx templates are built into Elixir - no external dep needed

# ══════════════════════════════════════════════════════════════
# Encryption
# ══════════════════════════════════════════════════════════════

# Use Erlang :crypto (built-in, no external dep needed)
# AES-256-GCM for secrets at rest
# Key derivation: PBKDF2 or Argon2

# Optional: If using Argon2 for key derivation
# https://hex.pm/packages/argon2_elixir
# {:argon2_elixir, "~> 4.0"},
```

**v0.2 Dependency Notes:**
- **Req**: The modern HTTP client stack (Req → Finch → Mint). Use for all HTTP needs.
- **Tailscale**: Two options available - libcluster_tailscale for discovery only, or tailscale-elixir for full API access.
- **Encryption**: Built-in `:crypto` is sufficient. Consider Argon2 for key derivation if handling user passwords.

---

## 8. v0.3 - Distributed & Cloud

### 8.1 Overview

The distributed computing version. Nexus agents run as daemons, form a mesh, and cloud resources can be dynamically provisioned for burst capacity.

**Timeline:** 8 weeks (after v0.2)
**Prerequisites:** v0.2 complete

### 8.2 Functional Requirements

#### 8.2.1 Agent Mode

**REQ-0301: Agent Daemon**
```bash
# Start agent on a machine
nexus agent start

# Or with options
nexus agent start \
  --name web-1 \
  --tags web,prod \
  --join coordinator.tail \
  --port 7400

# Manage agent
nexus agent status
nexus agent stop
nexus agent restart
```

- Long-running daemon process
- Automatic restart on crash (systemd unit provided)
- Health endpoint for monitoring
- Graceful shutdown

**REQ-0302: Agent Configuration**
```elixir
# /etc/nexus/agent.exs or ~/.nexus/agent.exs
agent do
  name System.get_env("HOSTNAME")
  tags [:web, :prod]
  port 7400

  # Auto-join cluster on start
  join "coordinator.tail"

  # Or join via Tailscale
  join :tailscale

  # Resource limits
  max_concurrent_tasks 4
  max_memory_percent 80
end
```

**REQ-0303: Agent Registration**
- Agents register with coordinator on startup
- Heartbeat every 5 seconds
- Automatic deregistration on graceful shutdown
- Timeout-based deregistration on crash (30s)

#### 8.2.2 Mesh Networking

**REQ-0310: Peer Discovery**
```elixir
cluster :mesh do
  # Explicit peers
  peers ["node1.tail", "node2.tail"]

  # Or Tailscale auto-discovery
  discovery :tailscale

  # Or mDNS for local network
  discovery :mdns, service: "_nexus._tcp"
end
```

**REQ-0311: Coordinator Election**
- No single coordinator required
- Any node can initiate a pipeline
- Distributed coordination via Erlang distribution
- Leader election for cluster-wide operations

**REQ-0312: Work Distribution**
```elixir
task :build, on: {:any, 3} do
  # Run on any 3 available nodes
  run "make"
end

task :test, on: {:all} do
  # Run on all nodes
  run "make test"
end

task :heavy, on: {:tag, :beefy} do
  # Run on nodes tagged "beefy"
  run "heavy-computation"
end

task :compile, on: {:prefer, :fast} do
  # Prefer "fast" nodes, fall back to others
  run "compile.sh"
end
```

**REQ-0313: Load Balancing**
- Track CPU/memory usage per agent
- Prefer less-loaded agents for new tasks
- Configurable scheduling strategies

#### 8.2.3 Cloud Bursting

**REQ-0320: Cloud Provider Configuration**
```elixir
cluster :hybrid do
  # Local machines (always on)
  nodes "desktop.tail", "server.tail", tags: [:local]

  # AWS burst capacity
  cloud :aws do
    region "us-west-2"
    instance_type "c6i.4xlarge"
    ami "ami-0123456789"  # Or auto-detect latest AL2
    spot_price 0.10  # Max $/hr, nil for on-demand

    count 0..10  # Scale between 0-10

    # Networking
    subnet "subnet-xxx"
    security_group "sg-xxx"

    # Instance config
    key_name "nexus-key"
    iam_role "nexus-agent-role"

    # Nexus agent setup
    user_data """
    #!/bin/bash
    curl -fsSL https://nexus.run/install.sh | sh
    nexus agent start --join #{coordinator()}
    """

    # Auto-terminate
    idle_timeout 300  # Terminate after 5min idle

    tags [:cloud, :burst, :aws]
  end

  # Hetzner for EU
  cloud :hetzner do
    server_type "cpx51"
    location "fsn1"
    image "ubuntu-22.04"
    count 0..5
    tags [:cloud, :burst, :eu]
  end
end
```

**REQ-0321: Supported Cloud Providers**

| Provider | v0.3 | Instance Types |
|----------|------|----------------|
| AWS EC2 | Yes | On-demand, Spot |
| Hetzner | Yes | Cloud servers |
| GCP | Planned | Standard, Preemptible |
| Azure | v0.4 | Standard, Spot |
| DigitalOcean | Planned | Droplets |
| Fly.io | Planned | Machines |

**REQ-0322: Scaling Triggers**
```elixir
# Manual scaling
nexus cloud scale aws=5

# In nexus.exs - auto-scaling
cluster :hybrid do
  cloud :aws do
    count 1..10

    scale_up when: :queue_depth > 10
    scale_down when: :idle_time > 300
  end
end
```

**REQ-0323: Instance Lifecycle**
1. **Provision**: Create instance via cloud API
2. **Bootstrap**: Run user_data script, install Nexus agent
3. **Join**: Agent connects to cluster
4. **Work**: Execute tasks
5. **Idle**: No tasks for `idle_timeout` seconds
6. **Terminate**: Gracefully leave cluster, terminate instance

**REQ-0324: Cost Controls**
```elixir
cloud :aws do
  # Spending limits
  max_hourly_cost 10.00  # USD
  max_instances 10

  # Prefer spot
  spot_price 0.10
  spot_fallback :on_demand  # or :fail

  # Instance lifetime
  max_runtime 3600  # 1 hour max
end
```

#### 8.2.4 Task Sharding

**REQ-0330: Parallel Sharded Execution**
```elixir
task :process_files, on: {:all}, parallel: :sharded do
  # Each node gets a subset of work
  run "process.sh --shard #{shard_id()} --total #{shard_count()}"
end

task :encode_video, on: {:tag, :encoder}, parallel: :sharded do
  run "ffmpeg -i input.mp4 -ss #{shard_start()} -t #{shard_duration()} chunk_#{shard_id()}.mp4"
  artifact "chunk_#{shard_id()}.mp4"
end

task :concat, deps: [:encode_video], on: :local do
  # All chunks available here
  run "ffmpeg -f concat -i chunks.txt output.mp4"
end
```

**REQ-0331: Sharding Functions**

| Function | Returns | Description |
|----------|---------|-------------|
| `shard_id()` | integer | 0-indexed shard number |
| `shard_count()` | integer | Total number of shards |
| `shard_items(list)` | list | Items for this shard |
| `shard_start()` | varies | Start offset for this shard |
| `shard_end()` | varies | End offset for this shard |

#### 8.2.5 TUI (Terminal User Interface)

**REQ-0340: Real-time Dashboard**
```
┌─ NEXUS ────────────────────────────────────────────────────────┐
│ Pipeline: deploy │ Status: Running │ Elapsed: 1m 23s           │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│ ● :build [local]                                              │
│   └─ npm run build ████████████████████ 100% (45s)            │
│                                                                │
│ ● :test [local]                                               │
│   └─ npm test ██████████░░░░░░░░░░ 50% (running)              │
│                                                                │
│ ○ :deploy [web-1, web-2, web-3]                               │
│   └─ waiting for :test                                        │
│                                                                │
├─ CLUSTER ──────────────────────────────────────────────────────┤
│ desktop.tail    ● 15% │ web-1.tail   ● 2%  │ aws-1    ● 45%   │
│ macbook.tail    ● 8%  │ web-2.tail   ● 3%  │ aws-2    ● 38%   │
│                       │ web-3.tail   ● 5%  │                  │
├────────────────────────────────────────────────────────────────┤
│ [l]ogs │ [n]ode details │ [c]ancel │ [q]uit                   │
└────────────────────────────────────────────────────────────────┘
```

**REQ-0341: TUI Features**
- Real-time task progress
- Cluster node status
- Per-node logs (drill-down)
- Keyboard navigation
- Live streaming output
- Works over SSH

**REQ-0342: TUI Implementation**
- Use Ratatouille (Elixir wrapper for termbox)
- Fallback to simple output if terminal not supported
- `--no-tui` flag for CI environments

### 8.3 File Additions for v0.3

```
lib/nexus/
├── agent/
│   ├── server.ex           # Agent GenServer
│   ├── supervisor.ex       # Agent supervision
│   ├── heartbeat.ex        # Heartbeat to cluster
│   ├── worker.ex           # Task execution worker
│   └── systemd.ex          # Systemd unit generation
├── cluster/
│   ├── coordinator.ex      # Cluster coordination
│   ├── registry.ex         # Node registry
│   ├── topology.ex         # Network topology
│   └── scheduler.ex        # Task scheduling
├── cloud/
│   ├── provider.ex         # Provider behaviour
│   ├── aws.ex              # AWS EC2 provider
│   ├── hetzner.ex          # Hetzner provider
│   ├── instance.ex         # Instance lifecycle
│   └── cost.ex             # Cost tracking
├── sharding/
│   ├── strategy.ex         # Sharding strategies
│   └── functions.ex        # Shard helper functions
└── tui/
    ├── app.ex              # Ratatouille app
    ├── views/
    │   ├── pipeline.ex     # Pipeline view
    │   ├── cluster.ex      # Cluster view
    │   └── logs.ex         # Log viewer
    └── components/
        ├── progress.ex     # Progress bar
        └── table.ex        # Data table
```

### 8.4 New Dependencies for v0.3

> Always verify latest versions at [Hex.pm](https://hex.pm) before implementation.
> **Library Research Status:** All dependencies validated December 2025.

```elixir
# ══════════════════════════════════════════════════════════════
# Cloud Provider SDKs
# ══════════════════════════════════════════════════════════════

# AWS SDK - mature, very actively maintained (66M+ downloads)
# https://hex.pm/packages/ex_aws | https://github.com/ex-aws/ex_aws
# Status: Very Active (releases through Oct 2025)
# Note: Use ex_aws over aws-elixir for better community support
{:ex_aws, "~> 2.6"},
{:ex_aws_ec2, "~> 2.0"},
{:ex_aws_s3, "~> 2.0"},  # For artifact storage

# Hetzner Cloud API - community maintained
# https://hex.pm/packages/hcloud | https://github.com/Ahamtech/elixir-hcloud
# Status: Active
{:hcloud, "~> 1.0"},

# Hetzner libcluster strategy
# https://hex.pm/packages/libcluster_hcloud
# Status: Active, uses Hetzner API with label selectors
{:libcluster_hcloud, "~> 0.1"},

# GCP - Official Google API client (auto-generated)
# https://github.com/googleapis/elixir-google-api
# Select specific APIs needed:
{:google_api_compute, "~> 0.56"},

# HTTP client (shared with v0.2)
# https://hex.pm/packages/req
{:req, "~> 0.5"},

# ══════════════════════════════════════════════════════════════
# Distributed Systems
# ══════════════════════════════════════════════════════════════

# Cluster formation - automatic node discovery
# https://hex.pm/packages/libcluster | https://github.com/bitwalker/libcluster
# Status: Active, proven in production
# Strategies: DNS, Kubernetes, Gossip, EPMD, Tailscale, Hetzner
{:libcluster, "~> 3.4"},

# Distributed registry and supervisor (replaces Swarm)
# https://hex.pm/packages/horde | https://github.com/derekkraan/horde
# Status: Active (2025), handles process distribution across cluster
# Used for: Singleton processes, distributed task execution
{:horde, "~> 0.9"},

# ══════════════════════════════════════════════════════════════
# Parallel Processing (Optional - Consider for Task Execution)
# ══════════════════════════════════════════════════════════════

# Broadway - concurrent data processing pipelines
# https://hex.pm/packages/broadway | https://github.com/dashbitco/broadway
# Status: Active (v1.2.1), built-in batching, back-pressure, fault tolerance
# Consider for: Task execution pipeline orchestration
# {:broadway, "~> 1.2"},

# ══════════════════════════════════════════════════════════════
# TUI - Terminal User Interface
# ══════════════════════════════════════════════════════════════

# TUI toolkit - Elm Architecture for terminals
# https://hex.pm/packages/ratatouille | https://github.com/ndreynolds/ratatouille
# Status: Active, wraps termbox
# Note: Consider Garnish for TUI over SSH connections
{:ratatouille, "~> 0.5"},

# ══════════════════════════════════════════════════════════════
# Service Discovery
# ══════════════════════════════════════════════════════════════

# mDNS for local network discovery
# https://hex.pm/packages/mdns_lite | https://github.com/nerves-networking/mdns_lite
# Status: Active (v0.9.0), primarily for Nerves but works anywhere
{:mdns_lite, "~> 0.9"},
```

**v0.3 Dependency Notes:**
- **AWS**: Use `ex_aws` (not `aws-elixir`). More mature, better maintained, 66M+ downloads.
- **Hetzner**: Both `hcloud` API client and `libcluster_hcloud` strategy are available.
- **GCP**: Use official googleapis/elixir-google-api. Select only needed APIs to minimize deps.
- **Distributed**: libcluster + Horde is the proven combination. See [February 2025 article](https://planet.kde.org/davide-briani-2025-02-14-the-secret-weapon-for-processing-millions-of-messages-in-order-with-elixir/) for patterns.
- **TUI**: Ratatouille is the only viable option. Consider Garnish for SSH-based TUI.
- **Broadway**: Consider for task execution if complex pipeline orchestration is needed.

---

## 9. v0.4 - Enterprise

### 9.1 Overview

Enterprise features for large organizations: Azure-native integration, Active Directory authentication, RBAC, and audit logging.

**Timeline:** 8 weeks (after v0.3)
**Prerequisites:** v0.3 complete

### 9.2 Functional Requirements

#### 9.2.1 Azure Native Integration

**REQ-0401: Azure Resource Discovery**
```elixir
cluster :azure do
  provider :azure do
    subscription_id env("AZURE_SUBSCRIPTION_ID")
    resource_group "production-rg"

    # Discover VMs by tags
    discover tags: %{"app" => "myapp", "env" => "prod"}

    # Or by name pattern
    discover name_pattern: "vm-web-*"

    # Or explicit
    discover vm_names: ["vm-web-001", "vm-web-002"]
  end
end

hosts :web do
  azure_tag "role", "web"
end

hosts :db do
  azure_tag "role", "database"
end
```

**REQ-0402: Azure Authentication**
```elixir
cluster :azure do
  provider :azure do
    # Managed Identity (when running on Azure)
    auth :managed_identity

    # Or Service Principal
    auth :service_principal,
      tenant_id: env("AZURE_TENANT_ID"),
      client_id: env("AZURE_CLIENT_ID"),
      client_secret: env("AZURE_CLIENT_SECRET")

    # Or Azure CLI (for local dev)
    auth :cli
  end
end
```

**REQ-0403: Azure Connection Methods**
```elixir
cluster :azure do
  provider :azure do
    # Direct SSH (VMs have public IPs or VPN)
    connection :ssh

    # Via Azure Bastion
    connection :bastion do
      bastion_name "my-bastion"
    end

    # Via Azure Run Command (no SSH needed)
    connection :run_command
  end
end
```

**REQ-0404: Azure Run Command Integration**
- Execute commands via Azure Run Command API
- No SSH required, no open ports
- Uses Azure RBAC for authorization
- Supports Linux and Windows VMs

**REQ-0405: Azure VM Scale Sets**
```elixir
cloud :azure do
  scale_set "myapp-vmss"
  instance_count 2..20

  scale_up when: :queue_depth > 10
  scale_down when: :idle_time > 300
end
```

#### 9.2.2 Active Directory / Kerberos Authentication

**REQ-0410: SSSD/Kerberos SSH Auth**
```elixir
cluster :azure do
  ssh_auth :kerberos do
    principal "user@CORP.EXAMPLE.COM"
    # Uses existing Kerberos ticket from kinit
  end
end
```

```bash
# Workflow
kinit user@CORP.EXAMPLE.COM
nexus run deploy  # Uses Kerberos ticket for SSH
```

**REQ-0411: AD User/Group Authorization**
```elixir
# nexus.exs
authorization do
  # Only these AD groups can run deploy tasks
  allow task: :deploy, groups: ["DevOps", "SRE"]

  # Anyone can run read-only tasks
  allow task: :status, groups: :any

  # Specific user override
  allow task: :*, users: ["admin@corp.example.com"]
end
```

**REQ-0412: Azure AD SSO (for TUI/Web)**
- OAuth2 flow for interactive auth
- Token refresh handling
- Integrate with Azure AD groups for RBAC

#### 9.2.3 Role-Based Access Control (RBAC)

**REQ-0420: Role Definition**
```elixir
# nexus-rbac.exs
role :viewer do
  can :list
  can :status
  can :logs
end

role :deployer do
  inherit :viewer
  can :run, tasks: [:build, :test, :deploy]
  can :run, on: [:staging]
end

role :admin do
  can :*  # Full access
end

# Assignment
assign "alice@corp.com", role: :admin
assign "bob@corp.com", role: :deployer
assign group: "DevOps", role: :deployer
assign group: "Viewers", role: :viewer
```

**REQ-0421: Permission Checks**
- Check permissions before task execution
- Clear error message on permission denied
- Log all permission checks

**REQ-0422: RBAC Storage**
- Local file (nexus-rbac.exs)
- Azure AD groups (sync)
- LDAP (future)

#### 9.2.4 Audit Logging

**REQ-0430: Audit Events**

| Event | Data Captured |
|-------|---------------|
| Task started | User, task, hosts, timestamp |
| Task completed | User, task, hosts, duration, status |
| Command executed | User, task, host, command, exit_code |
| Secret accessed | User, task, secret_name |
| Auth success/failure | User, method, source_ip |
| Config changed | User, change_type, diff |
| Cloud instance provisioned | User, provider, instance_id, cost |

**REQ-0431: Audit Log Format**
```json
{
  "timestamp": "2025-12-27T10:30:00Z",
  "event": "task.completed",
  "user": "alice@corp.example.com",
  "source_ip": "10.0.1.50",
  "task": "deploy",
  "hosts": ["web-1", "web-2"],
  "duration_ms": 45000,
  "status": "success",
  "correlation_id": "abc-123-def"
}
```

**REQ-0432: Audit Log Destinations**
```elixir
config :nexus, :audit do
  # Local file (rotated)
  destination :file, path: "/var/log/nexus/audit.log"

  # Syslog
  destination :syslog, facility: :local0

  # Azure Log Analytics
  destination :azure_log_analytics,
    workspace_id: env("LOG_ANALYTICS_WORKSPACE"),
    shared_key: env("LOG_ANALYTICS_KEY")

  # Splunk
  destination :splunk,
    url: "https://splunk.corp.com:8088",
    token: env("SPLUNK_HEC_TOKEN")
end
```

**REQ-0433: Audit Log Retention**
- Configurable retention period
- Automatic rotation
- Compression of old logs
- Tamper-evident logging (optional, via signing)

#### 9.2.5 Compliance Features

**REQ-0440: Command Approval Workflow**
```elixir
task :dangerous_migration, approval: :required do
  run "DROP TABLE users;"  # Requires approval
end
```

```bash
$ nexus run dangerous_migration
This task requires approval.
Approval request sent to: alice@corp.com, bob@corp.com
Waiting for approval... (Ctrl+C to cancel)

# Approver receives notification, runs:
$ nexus approve abc-123-def --comment "Approved for maintenance window"

# Original command continues
Approved by alice@corp.com
Running dangerous_migration...
```

**REQ-0441: Change Windows**
```elixir
config :nexus, :compliance do
  # Only allow deployments during change windows
  change_window :production,
    days: [:tuesday, :thursday],
    hours: 10..16,  # 10am-4pm
    timezone: "America/New_York"
end

task :deploy, on: :production, change_window: :production do
  run "..."
end
```

**REQ-0442: Dry-Run Enforcement**
```elixir
config :nexus, :compliance do
  # Require dry-run before actual run
  require_dry_run tasks: [:deploy, :migrate]
  dry_run_ttl 3600  # 1 hour validity
end
```

### 9.3 File Additions for v0.4

```
lib/nexus/
├── azure/
│   ├── resource_graph.ex   # VM discovery
│   ├── auth.ex             # Azure AD auth
│   ├── bastion.ex          # Bastion tunneling
│   ├── run_command.ex      # Run Command API
│   └── scale_set.ex        # VMSS integration
├── auth/
│   ├── kerberos.ex         # Kerberos auth
│   ├── sssd.ex             # SSSD integration
│   └── oauth.ex            # Azure AD OAuth
├── rbac/
│   ├── policy.ex           # RBAC policy engine
│   ├── role.ex             # Role definitions
│   └── check.ex            # Permission checks
├── audit/
│   ├── logger.ex           # Audit event logging
│   ├── event.ex            # Event types
│   ├── destinations/
│   │   ├── file.ex
│   │   ├── syslog.ex
│   │   ├── azure.ex
│   │   └── splunk.ex
│   └── retention.ex        # Log retention
└── compliance/
    ├── approval.ex         # Approval workflow
    ├── change_window.ex    # Change windows
    └── dry_run.ex          # Dry-run enforcement
```

### 9.4 New Dependencies for v0.4

> Always verify latest versions at [Hex.pm](https://hex.pm) before implementation.
> **Library Research Status:** All dependencies validated December 2025.
>
> **CRITICAL: Azure SDK Gap** - No mature Elixir Azure SDK exists. Must build custom client with Req.

```elixir
# ══════════════════════════════════════════════════════════════
# Azure Integration - CUSTOM BUILD REQUIRED
# ══════════════════════════════════════════════════════════════

# IMPORTANT: There is NO mature Azure SDK for Elixir.
# ex_microsoft_azure_management is a prototype/generator, NOT production-ready.
# 
# RECOMMENDED APPROACH: Build custom Azure client using Req
# - Azure REST API: https://docs.microsoft.com/en-us/rest/api/azure/
# - Use Azure AD OAuth2 for authentication
# - Wrap specific APIs needed (Resource Graph, VMs, Run Command, Bastion)

# HTTP client for Azure REST APIs
# https://hex.pm/packages/req
{:req, "~> 0.5"},

# ══════════════════════════════════════════════════════════════
# Authentication & Authorization
# ══════════════════════════════════════════════════════════════

# OAuth2/OIDC multi-provider framework (for Azure AD SSO)
# https://hex.pm/packages/assent | https://github.com/pow-auth/assent
# Status: Active (Jul 2024), supports Azure AD, Google, GitHub, etc.
{:assent, "~> 0.2"},

# JWT library for Azure AD token handling
# https://hex.pm/packages/joken | https://github.com/joken-elixir/joken
# Status: Active (Dec 2024, v2.6.2)
{:joken, "~> 2.6"},

# JWKS (JSON Web Key Set) for token verification
# https://hex.pm/packages/joken_jwks
{:joken_jwks, "~> 1.6"},

# ══════════════════════════════════════════════════════════════
# Kerberos/GSSAPI - HIGH RISK
# ══════════════════════════════════════════════════════════════

# SASL SCRAM and GSSAPI (Kerberos) support
# https://github.com/kafka4beam/sasl_auth
# Status: Active, but focused on Kafka authentication
# NOTE: May need custom implementation for SSH Kerberos auth
# REQUIRES: libkrb5-dev on Linux, Kerberos.framework on macOS
{:sasl_auth, github: "kafka4beam/sasl_auth"},

# Alternative: Build custom NIF wrapper around libgssapi
# This is a significant undertaking - evaluate if truly needed

# ══════════════════════════════════════════════════════════════
# Audit Logging
# ══════════════════════════════════════════════════════════════

# Syslog client/server/logger backend
# https://hex.pm/packages/kvasir_syslog
# Status: Active (Feb 2025 v1.0.1) - most recently updated option
{:kvasir_syslog, "~> 1.0"},

# Alternative syslog backends (if kvasir_syslog doesn't fit):
# - ExSyslogger: https://github.com/slashmili/ex_syslogger (UDP/local)
# - Dumpster: https://github.com/uberbrodt/dumpster (TCP/UDP/UNIX socket)

# OpenTelemetry for distributed tracing and audit trails
# https://hex.pm/packages/opentelemetry
# Status: Active, standard for observability
{:opentelemetry, "~> 1.4"},
{:opentelemetry_api, "~> 1.3"},
{:opentelemetry_exporter, "~> 1.7"},
```

**v0.4 Dependency Notes & Risks:**

| Component | Risk Level | Notes |
|-----------|------------|-------|
| **Azure SDK** | HIGH | No mature SDK. Must build custom REST client with Req. |
| **Kerberos/GSSAPI** | HIGH | sasl_auth is Kafka-focused. May need custom NIF. |
| **Azure AD Auth** | MEDIUM | Assent + Joken works but needs custom Azure integration. |
| **Syslog** | LOW | kvasir_syslog is actively maintained (Feb 2025). |

**Azure Implementation Strategy:**
1. Use `Req` as HTTP client base
2. Implement Azure AD OAuth2 flow with Assent
3. Build thin wrappers for specific Azure APIs:
   - Azure Resource Graph (VM discovery)
   - Azure Compute (VM management)
   - Azure Run Command (agentless execution)
   - Azure Bastion (SSH tunneling)
4. Consider contributing back as `ex_azure` package

**Kerberos Implementation Strategy:**
1. Evaluate if SSSD on hosts can handle Kerberos SSH auth natively
2. If NIF needed, consider Rustler for safer native code
3. Start with password-based fallback, add Kerberos as enhancement

---

## 10. Technical Architecture

### 10.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         USER INTERFACE                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │    CLI      │  │    TUI      │  │   Programmatic API      │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         CORE ENGINE                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ DSL Parser  │  │    DAG      │  │   Executor              │  │
│  │ & Validator │  │  Resolver   │  │   (Pipeline Runner)     │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      EXECUTION LAYER                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   Local     │  │    SSH      │  │   Agent (Distributed)   │  │
│  │  Executor   │  │  Executor   │  │   Executor              │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      INFRASTRUCTURE                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │  Tailscale  │  │   Cloud     │  │   Azure / Enterprise    │  │
│  │  Discovery  │  │  Providers  │  │   Integration           │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     CROSS-CUTTING CONCERNS                      │
│  ┌─────────────┐  ┌─────────────┐  ┌───────────┐  ┌──────────┐  │
│  │  Telemetry  │  │   Logging   │  │  Secrets  │  │  RBAC    │  │
│  └─────────────┘  └─────────────┘  └───────────┘  └──────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 10.2 OTP Supervision Tree

```
Nexus.Application
├── Nexus.Config.Server                    # Config state
├── Nexus.Telemetry.Supervisor             # Telemetry handlers
├── Nexus.SSH.PoolSupervisor               # SSH connection pools
│   ├── Nexus.SSH.Pool (host-1)
│   ├── Nexus.SSH.Pool (host-2)
│   └── ...
├── Nexus.Executor.Supervisor              # Task execution
│   ├── Nexus.Executor.Pipeline (pipeline-1)
│   │   ├── Nexus.Executor.TaskRunner (task-1)
│   │   ├── Nexus.Executor.TaskRunner (task-2)
│   │   └── ...
│   └── ...
├── Nexus.Agent.Supervisor (v0.3+)         # Agent mode
│   ├── Nexus.Agent.Server                 # Agent logic
│   ├── Nexus.Agent.Heartbeat              # Cluster heartbeat
│   └── Nexus.Agent.WorkerSupervisor       # Task workers
├── Nexus.Cluster.Supervisor (v0.3+)       # Cluster coordination
│   ├── Nexus.Cluster.Registry             # Node registry
│   ├── Nexus.Cluster.Scheduler            # Task scheduling
│   └── Nexus.Cluster.Topology             # Network topology
├── Nexus.Cloud.Supervisor (v0.3+)         # Cloud providers
│   ├── Nexus.Cloud.AWS.Manager
│   ├── Nexus.Cloud.Hetzner.Manager
│   └── ...
└── Nexus.Output.Server                    # Terminal output
```

### 10.3 Data Flow

```
nexus run deploy
       │
       ▼
┌──────────────────┐
│  Parse CLI Args  │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐     ┌───────────────────┐
│  Load nexus.exs  │────►│  Validate Config  │
└────────┬─────────┘     └─────────┬─────────┘
         │                         │
         ▼                         ▼
┌──────────────────┐     ┌───────────────────┐
│   Build DAG      │────►│  Resolve Order    │
└────────┬─────────┘     └─────────┬─────────┘
         │                         │
         ▼                         ▼
┌──────────────────┐     ┌───────────────────┐
│  Resolve Hosts   │────►│  Establish SSH    │
└────────┬─────────┘     │  Connections      │
         │               └─────────┬─────────┘
         ▼                         │
┌──────────────────┐               │
│ Execute Pipeline │◄──────────────┘
│  (parallel)      │
└────────┬─────────┘
         │
         ├─────────────────┬──────────────────┐
         ▼                 ▼                  ▼
┌──────────────────┐ ┌──────────────┐ ┌──────────────┐
│  Task: build     │ │ Task: test   │ │   ...        │
│  (local)         │ │ (local)      │ │              │
└────────┬─────────┘ └──────┬───────┘ └──────────────┘
         │                  │
         ▼                  ▼
┌──────────────────────────────────────────────────┐
│                Task: deploy                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │  host-1  │  │  host-2  │  │  host-3  │       │
│  │ (SSH)    │  │ (SSH)    │  │ (SSH)    │       │
│  └──────────┘  └──────────┘  └──────────┘       │
└────────┬─────────────────────────────────────────┘
         │
         ▼
┌──────────────────┐
│  Collect Results │
│  Return Status   │
└──────────────────┘
```

### 10.4 SSH Connection Pool

```
┌─────────────────────────────────────────────────────────────┐
│                    SSH Pool Manager                          │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Host: web-1.example.com                              │   │
│  │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐                 │   │
│  │  │Conn 1│ │Conn 2│ │Conn 3│ │Conn 4│  Pool Size: 4   │   │
│  │  │ busy │ │ idle │ │ busy │ │ idle │                 │   │
│  │  └──────┘ └──────┘ └──────┘ └──────┘                 │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Host: web-2.example.com                              │   │
│  │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐                 │   │
│  │  │Conn 1│ │Conn 2│ │Conn 3│ │Conn 4│  Pool Size: 4   │   │
│  │  │ idle │ │ idle │ │ idle │ │ idle │                 │   │
│  │  └──────┘ └──────┘ └──────┘ └──────┘                 │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  Operations:                                                 │
│  - checkout(host) -> connection                             │
│  - checkin(host, connection)                                │
│  - health_check(connection) -> :ok | :stale                 │
│  - close_idle(timeout)                                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 11. State Management & Crash Recovery

### 11.1 Overview

This section addresses critical questions about pipeline state persistence, crash recovery, resumability, and artifact management.

### 11.2 Pipeline State Model

#### 11.2.1 State Structure

```elixir
defmodule Nexus.Pipeline.State do
  @type t :: %__MODULE__{
    id: String.t(),
    started_at: DateTime.t(),
    status: :pending | :running | :completed | :failed | :cancelled,
    tasks: %{atom() => task_state()},
    hosts: %{String.t() => host_state()},
    artifacts: %{String.t() => artifact_ref()},
    checkpoints: [checkpoint()],
    config_hash: String.t(),
    resume_token: String.t() | nil
  }

  @type task_state :: %{
    status: :pending | :running | :completed | :failed | :skipped,
    started_at: DateTime.t() | nil,
    completed_at: DateTime.t() | nil,
    attempts: non_neg_integer(),
    last_error: String.t() | nil,
    commands_completed: non_neg_integer()
  }

  @type host_state :: %{
    status: :connected | :disconnected | :failed,
    last_seen: DateTime.t(),
    commands_executed: non_neg_integer()
  }

  @type checkpoint :: %{
    task: atom(),
    command_index: non_neg_integer(),
    timestamp: DateTime.t(),
    state_snapshot: binary()
  }
end
```

#### 11.2.2 State Persistence

```
┌─────────────────────────────────────────────────────────────────┐
│                     STATE PERSISTENCE                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  v0.1 - Local Only                                              │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  ~/.nexus/state/                                         │    │
│  │  ├── pipelines/                                          │    │
│  │  │   ├── <pipeline-id>.state      # DETS file           │    │
│  │  │   └── <pipeline-id>.log        # Append-only log     │    │
│  │  └── current -> <pipeline-id>     # Symlink to active   │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  v0.3+ - Distributed                                            │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Option A: Mnesia (Erlang-native)                        │    │
│  │  - Replicated across cluster nodes                       │    │
│  │  - Automatic conflict resolution                         │    │
│  │                                                           │    │
│  │  Option B: CRDTs via Horde.DeltaCRDT                     │    │
│  │  - Eventually consistent                                  │    │
│  │  - No coordination overhead                               │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**State File Format (v0.1):**
- DETS (Disk Erlang Term Storage) for atomic updates
- Append-only log for crash recovery
- State is checksummed to detect corruption

### 11.3 Crash Recovery

#### 11.3.1 Coordinator Crash Scenarios

| Scenario | Impact | Recovery Action |
|----------|--------|-----------------|
| Crash before first command | No impact | Clean restart |
| Crash during local execution | Partial local state | Resume or restart |
| Crash during SSH execution | Remote commands may complete | Query hosts for status |
| Crash during artifact transfer | Partial artifacts | Re-transfer on resume |
| OOM kill | Same as crash | Resume from checkpoint |
| SIGKILL | Same as crash | Resume from checkpoint |

#### 11.3.2 Recovery Algorithm

```
On Startup:
  1. Check for ~/.nexus/state/current symlink
  2. If exists, load pipeline state
  3. Validate state integrity (checksum)
  4. Prompt user:
     - "Pipeline 'deploy' was interrupted. Resume? [Y/n/discard]"
  5. If resume:
     a. Reconnect to hosts
     b. Query incomplete tasks for actual state
     c. Continue from last checkpoint
  6. If discard:
     a. Archive state to ~/.nexus/state/archive/
     b. Clean up artifacts
     c. Start fresh

Recovery State Query (per host):
  1. Check if last command is still running (ps aux)
  2. Check if last command completed (exit code file)
  3. Verify file system state (checksums)
  4. Report actual state back to coordinator
```

#### 11.3.3 Checkpoint Strategy

```elixir
# Checkpoints are created:
# 1. After each task completes
# 2. After each command in a task completes (optional, for long tasks)
# 3. Before any destructive operation

defmodule Nexus.Checkpoint do
  @spec create(Pipeline.State.t(), atom(), non_neg_integer()) :: :ok
  def create(state, task, command_index) do
    checkpoint = %{
      task: task,
      command_index: command_index,
      timestamp: DateTime.utc_now(),
      state_snapshot: :erlang.term_to_binary(state)
    }
    
    # Write to append-only log (crash-safe)
    File.write!(log_path(state.id), checkpoint_to_line(checkpoint), [:append, :sync])
    
    # Update DETS state
    :dets.insert(state_table(state.id), {:checkpoint, checkpoint})
    :dets.sync(state_table(state.id))
  end
end
```

#### 11.3.4 Resume Command

```bash
# Automatic resume prompt
$ nexus run deploy
Pipeline 'deploy' (started 2025-12-28 10:30:00) was interrupted.
  ✓ :build completed
  ● :deploy in progress (2/3 hosts completed)
  ○ :migrate pending

Resume from checkpoint? [Y/n/discard]: y

Resuming pipeline...
● :deploy [web-3.example.com]
  └─ Checking host state...
  └─ Last command: systemctl start myapp (completed)
  └─ Continuing with health check...

# Explicit resume
$ nexus resume <pipeline-id>

# List interrupted pipelines
$ nexus pipelines --interrupted

# Discard and start fresh
$ nexus run deploy --no-resume
```

### 11.4 Artifact Storage

#### 11.4.1 Artifact Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                     ARTIFACT LIFECYCLE                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. CREATION                                                     │
│     Task produces artifact → Registered in state                 │
│     artifact "build/output.tar.gz"                              │
│                                                                  │
│  2. TRANSFER (if needed)                                         │
│     Source host → Coordinator (staging)                          │
│     Coordinator → Dependent task hosts                           │
│                                                                  │
│  3. STAGING LOCATION                                             │
│     Local: ~/.nexus/artifacts/<pipeline-id>/<artifact-name>     │
│     S3:    s3://nexus-artifacts/<pipeline-id>/<artifact-name>   │
│                                                                  │
│  4. CLEANUP                                                      │
│     On pipeline success: Immediate (configurable)                │
│     On pipeline failure: Retained for debugging                  │
│     TTL: 24 hours default, configurable                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### 11.4.2 Artifact Storage Configuration

```elixir
config :nexus do
  artifacts do
    # Local storage (default)
    storage :local,
      path: "~/.nexus/artifacts",
      max_size: "10GB"

    # S3 storage (for large artifacts or teams)
    storage :s3,
      bucket: env("NEXUS_ARTIFACT_BUCKET"),
      region: "us-west-2",
      prefix: "nexus/"

    # Cleanup policy
    retention :on_success, :immediate  # or :keep, or "24h"
    retention :on_failure, "7d"
    
    # Streaming (don't buffer entire file)
    streaming true
    chunk_size "1MB"
  end
end
```

#### 11.4.3 Artifact Transfer Flow

```
Producer Task                 Coordinator                Consumer Task
     │                            │                            │
     │  artifact "output.tar.gz"  │                            │
     ├───────────────────────────►│                            │
     │                            │                            │
     │                            │  (stream via SFTP)         │
     │◄───────────────────────────┤                            │
     │  SFTP download             │                            │
     │───────────────────────────►│                            │
     │                            │  store locally/S3          │
     │                            │                            │
     │                            │  (on consumer start)       │
     │                            ├───────────────────────────►│
     │                            │  SFTP upload               │
     │                            │───────────────────────────►│
     │                            │                            │
```

### 11.5 Distributed State (v0.3+)

#### 11.5.1 State Replication

```elixir
# Using Horde for distributed state
defmodule Nexus.Cluster.StateRegistry do
  use Horde.Registry

  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {Horde.Registry, :start_link, [[
        name: __MODULE__,
        keys: :unique,
        members: :auto
      ]]}
    }
  end
end

defmodule Nexus.Cluster.PipelineState do
  use Horde.DynamicSupervisor

  # Pipeline state is supervised and replicated
  # If a node dies, state process restarts on another node
end
```

#### 11.5.2 Split-Brain Handling

| Scenario | Detection | Resolution |
|----------|-----------|------------|
| Network partition | Heartbeat timeout | Pause non-quorum side |
| Node crash | Erlang :nodedown | Redistribute processes |
| Rejoin after split | Horde sync | CRDT merge |

---

## 12. Agent Communication Protocol

### 12.1 Overview

This section defines how Nexus agents communicate in distributed mode (v0.3+), including protocol choice, authentication, and NAT traversal.

### 12.2 Protocol Decision

#### 12.2.1 Options Analysis

| Protocol | Pros | Cons | Verdict |
|----------|------|------|---------|
| **Erlang Distribution** | Native, proven, efficient | Requires open ports, no built-in auth | **Primary** |
| gRPC | Type-safe, polyglot | Complexity, external dep | Future option |
| Custom TCP/TLS | Full control | Implementation burden | Not needed |
| QUIC | Modern, NAT-friendly | Limited Elixir support | Future |

**Decision:** Use **Erlang Distribution** as primary protocol with TLS encryption.

#### 12.2.2 Erlang Distribution Configuration

```elixir
# config/runtime.exs
config :kernel,
  inet_dist_listen_min: 9100,
  inet_dist_listen_max: 9110

# TLS for distribution
config :ssl,
  protocol_version: [:"tlsv1.3"]

# In releases/overlays/vm.args.eex
-proto_dist inet_tls
-ssl_dist_optfile <%= release_path %>/ssl_dist.conf
```

### 12.3 Agent Authentication

#### 12.3.1 Authentication Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                  AGENT AUTHENTICATION LAYERS                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Layer 1: TLS Certificate (Transport)                           │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  - Mutual TLS (mTLS) required                            │    │
│  │  - Certificates issued by Nexus CA                       │    │
│  │  - Auto-generated on `nexus agent init`                  │    │
│  │  - Stored in ~/.nexus/certs/                             │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  Layer 2: Cluster Cookie (Erlang)                               │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  - Standard Erlang cookie mechanism                      │    │
│  │  - Generated on cluster init                             │    │
│  │  - Distributed via nexus.exs or env var                  │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  Layer 3: Agent Token (Application)                             │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  - JWT token with agent identity                         │    │
│  │  - Contains: agent_id, tags, capabilities                │    │
│  │  - Short-lived, refreshed periodically                   │    │
│  │  - Signed by coordinator's private key                   │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### 12.3.2 Certificate Management

```bash
# Initialize agent with certificates
$ nexus agent init --coordinator nexus.example.com
Generating agent keypair...
Requesting certificate from coordinator...
Certificate received and stored in ~/.nexus/certs/
Agent ID: agent-abc123
Cookie stored in ~/.nexus/cookie

# On coordinator: approve agent
$ nexus agent approve agent-abc123 --tags web,prod

# Certificate structure
~/.nexus/certs/
├── ca.pem           # Cluster CA certificate
├── agent.pem        # This agent's certificate
├── agent-key.pem    # This agent's private key
└── known_agents/    # Trusted agent certificates (coordinator only)
```

#### 12.3.3 Authentication Flow

```
New Agent                    Coordinator
    │                            │
    │  1. TLS handshake          │
    │  (with self-signed cert)   │
    ├───────────────────────────►│
    │                            │
    │  2. Certificate request    │
    │  (includes agent info)     │
    ├───────────────────────────►│
    │                            │
    │  3. Out-of-band approval   │
    │  (operator runs approve)   │
    │                       ┌────┤
    │                       │    │
    │                       ▼    │
    │  4. Signed certificate     │
    │◄───────────────────────────┤
    │                            │
    │  5. Reconnect with         │
    │  signed certificate        │
    ├───────────────────────────►│
    │                            │
    │  6. Erlang distribution    │
    │  established               │
    │◄──────────────────────────►│
    │                            │
```

### 12.4 NAT Traversal

#### 12.4.1 Strategies

| Strategy | When to Use | How It Works |
|----------|-------------|--------------|
| **Tailscale** | Preferred | WireGuard mesh, handles everything |
| **Relay Server** | No Tailscale, NAT present | Coordinator acts as relay |
| **Direct** | No NAT, same network | Standard Erlang distribution |
| **STUN/TURN** | Future | ICE-style NAT traversal |

#### 12.4.2 Tailscale Integration (Recommended)

```elixir
cluster :mesh do
  discovery :tailscale

  # Tailscale handles:
  # - NAT traversal via DERP relays
  # - Encryption via WireGuard
  # - Authentication via Tailscale identity
  # - DNS via MagicDNS
end
```

#### 12.4.3 Relay Mode (Without Tailscale)

```
┌─────────────────────────────────────────────────────────────────┐
│                        RELAY MODE                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Agent A (behind NAT)      Coordinator        Agent B (NAT)    │
│          │                  (public IP)              │          │
│          │                       │                   │          │
│          │   Connect (outbound)  │                   │          │
│          ├──────────────────────►│                   │          │
│          │                       │◄──────────────────┤          │
│          │                       │   Connect          │          │
│          │                       │                   │          │
│          │◄─────────────────────►│◄─────────────────►│          │
│          │   Messages relayed    │   Messages relayed│          │
│          │   via coordinator     │   via coordinator │          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

```elixir
cluster :mesh do
  # If direct connection fails, relay through coordinator
  relay :coordinator

  # Or specify explicit relay server
  relay "relay.example.com:9000"

  # Connection timeout before fallback to relay
  direct_timeout 5_000
end
```

#### 12.4.4 Network Requirements

| Mode | Inbound Ports | Outbound | Notes |
|------|---------------|----------|-------|
| Direct | 9100-9110 (distribution) | Any | Same network |
| Tailscale | None | 41641/UDP (WireGuard) | Recommended |
| Relay | None (agents), 9100-9110 (coordinator) | 443/TCP | NAT-friendly |

### 12.5 Message Protocol

#### 12.5.1 Message Types

```elixir
defmodule Nexus.Protocol.Message do
  @type t ::
    # Agent lifecycle
    {:agent_join, agent_info()}
    | {:agent_leave, agent_id()}
    | {:heartbeat, agent_id(), metrics()}
    
    # Task execution
    | {:task_assign, task_id(), task_spec()}
    | {:task_status, task_id(), status()}
    | {:task_complete, task_id(), result()}
    | {:task_failed, task_id(), error()}
    
    # Artifact transfer
    | {:artifact_request, artifact_id()}
    | {:artifact_chunk, artifact_id(), offset(), binary()}
    | {:artifact_complete, artifact_id(), checksum()}
    
    # Cluster coordination
    | {:leader_election, node(), term()}
    | {:state_sync, state_delta()}
end
```

---

## 13. Secrets & Key Management

### 13.1 Overview

This section details secret storage, encryption key management, rotation procedures, and team sharing capabilities.

### 13.2 Key Storage Architecture

#### 13.2.1 Storage Locations

```
┌─────────────────────────────────────────────────────────────────┐
│                      KEY STORAGE LOCATIONS                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Personal (Single User)                                          │
│  ~/.nexus/                                                       │
│  ├── master.key          # Master key (encrypted with passphrase)│
│  ├── secrets.enc         # Encrypted secrets database            │
│  └── keyfile             # Optional: key derived from file       │
│                                                                  │
│  Project (Team)                                                  │
│  .nexus/                                                         │
│  ├── secrets.enc         # Project secrets (encrypted)           │
│  └── .gitignore          # Ensure secrets.enc is tracked,        │
│                          # but master.key is NOT                  │
│                                                                  │
│  Key Sources (Priority Order)                                    │
│  1. NEXUS_MASTER_KEY env var (base64 encoded)                   │
│  2. --keyfile CLI option                                         │
│  3. ~/.nexus/master.key (passphrase protected)                  │
│  4. Interactive passphrase prompt                                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### 13.2.2 Master Key Derivation

```elixir
defmodule Nexus.Secrets.KeyDerivation do
  @iterations 100_000
  @key_length 32  # 256 bits

  @doc """
  Derive a master key from a passphrase using Argon2id.
  """
  def derive_from_passphrase(passphrase, salt) do
    Argon2.hash_password(passphrase, salt,
      t_cost: 3,        # Time cost
      m_cost: 65536,    # Memory cost (64 MB)
      parallelism: 4,
      hashlen: @key_length,
      argon2_type: :argon2id
    )
  end

  @doc """
  Derive a master key from a keyfile.
  Uses the file contents as key material.
  """
  def derive_from_keyfile(path) do
    content = File.read!(Path.expand(path))
    :crypto.hash(:sha256, content)
  end
end
```

### 13.3 Secret Encryption

#### 13.3.1 Encryption Scheme

```
┌─────────────────────────────────────────────────────────────────┐
│                     ENCRYPTION SCHEME                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Algorithm: AES-256-GCM (Authenticated Encryption)               │
│                                                                  │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐      │
│  │ Master Key  │──────│ Derive KEK  │──────│   Key       │      │
│  │ (from pass/ │      │ (HKDF)      │      │ Encryption  │      │
│  │  keyfile)   │      │             │      │   Key       │      │
│  └─────────────┘      └─────────────┘      └──────┬──────┘      │
│                                                    │             │
│  ┌─────────────┐      ┌─────────────┐              │             │
│  │ Random DEK  │◄─────│ Generate    │              │             │
│  │ per secret  │      │ (32 bytes)  │              │             │
│  └──────┬──────┘      └─────────────┘              │             │
│         │                                          │             │
│         ▼                                          ▼             │
│  ┌─────────────┐                          ┌─────────────┐        │
│  │ Encrypt     │                          │ Encrypt DEK │        │
│  │ secret data │                          │ with KEK    │        │
│  │ with DEK    │                          │             │        │
│  └──────┬──────┘                          └──────┬──────┘        │
│         │                                        │               │
│         ▼                                        ▼               │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  secrets.enc:                                         │       │
│  │  { name: "DB_PASS",                                   │       │
│  │    encrypted_dek: <base64>,                           │       │
│  │    iv: <base64>,                                      │       │
│  │    ciphertext: <base64>,                              │       │
│  │    auth_tag: <base64> }                               │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### 13.3.2 secrets.enc Format

```json
{
  "version": 2,
  "kdf": "argon2id",
  "kdf_params": {
    "salt": "base64...",
    "t_cost": 3,
    "m_cost": 65536,
    "parallelism": 4
  },
  "secrets": [
    {
      "name": "DB_PASSWORD",
      "created_at": "2025-12-28T10:00:00Z",
      "updated_at": "2025-12-28T10:00:00Z",
      "encrypted_dek": "base64...",
      "iv": "base64...",
      "ciphertext": "base64...",
      "auth_tag": "base64..."
    }
  ]
}
```

### 13.4 Key Rotation

#### 13.4.1 Rotation Types

| Type | Trigger | Process |
|------|---------|---------|
| **Master Key** | Manual, compromise suspected | Re-encrypt all secrets with new key |
| **DEK per secret** | On secret update | Generate new DEK, re-encrypt |
| **Agent certs** | Scheduled (90 days) | Issue new cert, phase out old |

#### 13.4.2 Master Key Rotation Procedure

```bash
# Rotate master key (re-encrypts all secrets)
$ nexus secret rotate-key
Enter current passphrase: ********
Enter new passphrase: ********
Confirm new passphrase: ********

Rotating master key...
  ✓ Decrypted 15 secrets with old key
  ✓ Re-encrypted 15 secrets with new key
  ✓ Backed up old secrets.enc to secrets.enc.bak
  ✓ Updated secrets.enc

Master key rotated successfully.
Old backup: ~/.nexus/secrets.enc.bak (delete after verification)
```

#### 13.4.3 Automated Rotation Reminders

```elixir
config :nexus, :secrets do
  # Warn if master key hasn't been rotated in N days
  key_rotation_reminder 90

  # Warn if secrets haven't been rotated in N days
  secret_rotation_reminder 30

  # Check on every nexus run
  check_rotation_on_run true
end
```

### 13.5 Team Sharing

#### 13.5.1 Sharing Strategies

| Strategy | Use Case | Pros | Cons |
|----------|----------|------|------|
| **Shared keyfile** | Small team, trusted | Simple | Single point of failure |
| **Vault integration** | Enterprise | Audit, rotation | Complexity, infra needed |
| **Age/SOPS** | GitOps workflows | Git-native | External tooling |
| **Per-environment** | CI/CD | Isolation | Multiple key management |

#### 13.5.2 Shared Keyfile Approach

```bash
# Generate a shared keyfile
$ nexus secret init --team
Generated keyfile: .nexus/team.key
Generated secrets file: .nexus/secrets.enc

Add to .gitignore:
  .nexus/team.key

Distribute team.key securely to team members.
DO NOT commit team.key to git.

# Team member setup
$ nexus secret unlock --keyfile /path/to/team.key
Keyfile loaded successfully.
```

#### 13.5.3 HashiCorp Vault Integration (v0.4+)

```elixir
config :nexus, :secrets do
  # Use Vault as secret backend
  backend :vault do
    address env("VAULT_ADDR")
    auth :kubernetes  # or :token, :approle, :aws
    path "secret/data/nexus"
    
    # Cache secrets locally (encrypted) to avoid Vault dependency at runtime
    cache true
    cache_ttl 3600
  end
end
```

#### 13.5.4 SOPS Integration (v0.4+)

```yaml
# .sops.yaml
creation_rules:
  - path_regex: \.nexus/secrets\.yaml$
    age:
      - age1...  # Team member 1
      - age1...  # Team member 2
      - age1...  # CI/CD key
```

```bash
# Edit secrets with your editor
$ sops .nexus/secrets.yaml

# Nexus reads SOPS-encrypted files directly
$ nexus run deploy  # Decrypts using age key
```

### 13.6 Secret Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                      SECRET LIFECYCLE                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Creation                                                     │
│     nexus secret set DB_PASSWORD                                 │
│     - Prompt for value (no echo)                                 │
│     - Generate DEK                                               │
│     - Encrypt with KEK                                           │
│     - Store in secrets.enc                                       │
│                                                                  │
│  2. Usage (Runtime)                                              │
│     secret("DB_PASSWORD") in nexus.exs                          │
│     - Load secrets.enc                                           │
│     - Derive KEK from master key                                 │
│     - Decrypt DEK                                                │
│     - Decrypt secret value                                       │
│     - Clear from memory after use                                │
│                                                                  │
│  3. Rotation                                                     │
│     nexus secret set DB_PASSWORD  (update)                       │
│     - New DEK generated                                          │
│     - Old version not retained                                   │
│                                                                  │
│  4. Deletion                                                     │
│     nexus secret delete DB_PASSWORD                              │
│     - Remove from secrets.enc                                    │
│     - Secure overwrite not guaranteed (use full-disk encryption) │
│                                                                  │
│  5. Audit (v0.4+)                                                │
│     - All accesses logged                                        │
│     - secret_name, task, timestamp, host                         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 14. Non-Functional Requirements

### 14.1 Performance

| Metric | Target | Measurement |
|--------|--------|-------------|
| SSH connection time | <2s | 95th percentile |
| Command overhead | <50ms | Per command, excluding execution |
| Concurrent connections | 100+ | Stable operation |
| Memory (idle) | <50MB | Base process |
| Memory (100 hosts) | <200MB | Active pipeline |
| Startup time | <500ms | To first command |
| Config parse time | <100ms | 1000-line nexus.exs |

### 14.2 Reliability

| Requirement | Description |
|-------------|-------------|
| Crash recovery | No user data loss on crash |
| Graceful shutdown | Complete in-flight commands on SIGTERM |
| Network resilience | Retry on transient failures |
| Partial failure | Clear reporting of what succeeded/failed |
| Idempotency guidance | Docs on writing idempotent tasks |

### 14.3 Scalability

| Scenario | Target |
|----------|--------|
| Hosts per pipeline | 1,000 |
| Tasks per pipeline | 500 |
| Commands per task | 100 |
| Concurrent pipelines | 10 |
| Cluster size | 100 nodes |

### 14.4 Compatibility

**Operating Systems:**
- Linux (x86_64, arm64): Ubuntu 20.04+, RHEL 8+, Debian 11+
- macOS (x86_64, arm64): 12.0+
- Windows: WSL2 only for v0.1-0.3, native in future

**SSH Servers:**
- OpenSSH 7.0+
- Dropbear
- Windows OpenSSH

**Elixir/OTP:**
- Elixir 1.15+
- OTP 25+

### 14.5 Security

| Requirement | Implementation |
|-------------|----------------|
| Secrets at rest | AES-256-GCM encryption |
| Secrets in transit | SSH encryption |
| No secrets in logs | Automatic redaction |
| SSH key handling | No keys stored by Nexus |
| Audit trail | All operations logged |
| Least privilege | Configurable RBAC |

---

## 15. Security Requirements

### 15.1 Threat Model

| Threat | Mitigation |
|--------|------------|
| Credential theft | Secrets encrypted, memory cleared after use |
| MITM attacks | SSH host key verification |
| Log leakage | Automatic secret redaction |
| Unauthorized access | RBAC, authentication required |
| Supply chain | Signed releases, dependency audit |
| Code injection | DSL validation, no eval of user input |

### 15.2 Authentication

| Method | v0.1 | v0.2 | v0.3 | v0.4 |
|--------|------|------|------|------|
| SSH key | ✅ | ✅ | ✅ | ✅ |
| SSH agent | ✅ | ✅ | ✅ | ✅ |
| Password | ✅ | ✅ | ✅ | ✅ |
| Tailscale | | ✅ | ✅ | ✅ |
| Kerberos | | | | ✅ |
| Azure AD | | | | ✅ |

### 15.3 Encryption

| Data | Encryption |
|------|------------|
| Secrets at rest | AES-256-GCM |
| Config files | None (not secrets) |
| SSH traffic | SSH protocol encryption |
| Agent communication | TLS 1.3 or SSH |
| Cloud API calls | HTTPS |

### 15.4 Compliance Considerations

- **SOC 2**: Audit logging, access controls, encryption
- **HIPAA**: Audit trails, access controls (no PHI handling)
- **PCI-DSS**: Logging, encryption, access controls
- **GDPR**: No PII stored by Nexus itself

---

## 16. Testing Strategy

### 16.1 Overview

This section addresses the comprehensive testing approach for Nexus, including how to test SSH without real servers, property-based testing scope, and performance/load testing strategies.

### 16.2 Testing Pyramid

```
                    ┌─────────────────────┐
                    │    E2E Tests        │  < 5%
                    │  (Real SSH, Cloud)  │
                    ├─────────────────────┤
                    │  Integration Tests  │  ~20%
                    │   (Docker SSH)      │
                    ├─────────────────────┤
                    │    Unit Tests       │  ~75%
                    │  (Mocks, Stubs)     │
                    └─────────────────────┘
```

### 16.3 SSH Testing Without Real Servers

#### 16.3.1 Testing Layers

| Layer | Technique | Coverage |
|-------|-----------|----------|
| **Unit Tests** | Mox behaviors | Business logic, parsing, validation |
| **Integration** | Docker SSH containers | Real SSH protocol, full flows |
| **E2E** | Vagrant/Cloud VMs | Production-like scenarios |

#### 16.3.2 Docker SSH Container Strategy

```elixir
# test/support/docker_ssh.ex
defmodule Nexus.Test.DockerSSH do
  @moduledoc """
  Manages Docker containers running OpenSSH for integration testing.
  """

  @default_image "linuxserver/openssh-server:latest"
  @default_port 2222

  def start_container(opts \\ []) do
    port = Keyword.get(opts, :port, @default_port)
    image = Keyword.get(opts, :image, @default_image)

    # Start container with SSH
    {container_id, 0} = System.cmd("docker", [
      "run", "-d",
      "-p", "#{port}:2222",
      "-e", "PUID=1000",
      "-e", "PGID=1000",
      "-e", "PASSWORD_ACCESS=true",
      "-e", "USER_PASSWORD=testpass",
      "-e", "USER_NAME=testuser",
      image
    ])

    # Wait for SSH to be ready
    wait_for_ssh("localhost", port)

    {:ok, String.trim(container_id), port}
  end

  def stop_container(container_id) do
    System.cmd("docker", ["stop", container_id])
    System.cmd("docker", ["rm", container_id])
    :ok
  end

  defp wait_for_ssh(host, port, attempts \\ 30) do
    case :gen_tcp.connect(String.to_charlist(host), port, [], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, _} when attempts > 0 ->
        Process.sleep(1000)
        wait_for_ssh(host, port, attempts - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

#### 16.3.3 Mox Behavior for SSH

```elixir
# lib/nexus/ssh/behaviour.ex
defmodule Nexus.SSH.Behaviour do
  @callback connect(host :: String.t(), opts :: keyword()) ::
    {:ok, connection :: term()} | {:error, reason :: term()}

  @callback exec(connection :: term(), command :: String.t(), opts :: keyword()) ::
    {:ok, output :: String.t(), exit_code :: non_neg_integer()} | {:error, reason :: term()}

  @callback close(connection :: term()) :: :ok
end

# test/support/mocks.ex
Mox.defmock(Nexus.SSH.Mock, for: Nexus.SSH.Behaviour)

# test/unit/executor/pipeline_test.exs
defmodule Nexus.Executor.PipelineTest do
  use ExUnit.Case, async: true
  import Mox

  setup :verify_on_exit!

  test "executes commands on remote host" do
    expect(Nexus.SSH.Mock, :connect, fn "host.example.com", _opts ->
      {:ok, :mock_connection}
    end)

    expect(Nexus.SSH.Mock, :exec, fn :mock_connection, "echo hello", _opts ->
      {:ok, "hello\n", 0}
    end)

    expect(Nexus.SSH.Mock, :close, fn :mock_connection -> :ok end)

    # Test pipeline execution
    assert {:ok, _} = Nexus.Executor.Pipeline.run(pipeline, ssh_impl: Nexus.SSH.Mock)
  end
end
```

#### 16.3.4 Test Environment Matrix

| Environment | When Used | Setup |
|-------------|-----------|-------|
| **Local Mox** | Unit tests, CI fast lane | None |
| **Docker SSH** | Integration tests, CI | docker-compose up |
| **Vagrant VMs** | E2E, manual testing | vagrant up |
| **Cloud VMs** | Release validation | Terraform |

```yaml
# docker-compose.test.yml
version: "3.8"
services:
  ssh-ubuntu:
    image: linuxserver/openssh-server:latest
    ports:
      - "2222:2222"
    environment:
      - PUID=1000
      - PGID=1000
      - PASSWORD_ACCESS=true
      - USER_PASSWORD=testpass
      - USER_NAME=testuser

  ssh-alpine:
    image: lscr.io/linuxserver/openssh-server:alpine
    ports:
      - "2223:2222"
    environment:
      - PUID=1000
      - PGID=1000
      - PUBLIC_KEY_FILE=/keys/test_key.pub
      - USER_NAME=testuser
    volumes:
      - ./test/fixtures/ssh_keys:/keys:ro
```

### 16.4 Property-Based Testing

#### 16.4.1 Scope

| Component | Property Tests | Examples |
|-----------|---------------|----------|
| **DSL Parser** | Parsing roundtrips | Any valid DSL parses correctly |
| **DAG Resolution** | Ordering invariants | Deps always before dependents |
| **Host Parsing** | Format handling | All valid host formats parse |
| **Config Validation** | Type checking | Invalid types rejected |
| **Retry Logic** | Backoff calculations | Delays increase correctly |

#### 16.4.2 StreamData Examples

```elixir
# test/property/dsl_parser_test.exs
defmodule Nexus.DSL.ParserPropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  property "any valid task name is an atom" do
    check all name <- atom(:alphanumeric) do
      task_def = """
      task :#{name} do
        run "echo test"
      end
      """
      assert {:ok, _} = Nexus.DSL.Parser.parse(task_def)
    end
  end

  property "host strings parse consistently" do
    check all user <- string(:alphanumeric, min_length: 1, max_length: 20),
              host <- string(:alphanumeric, min_length: 1, max_length: 50),
              port <- integer(1..65535) do
      # user@host:port format
      full = "#{user}@#{host}:#{port}"
      assert {:ok, parsed} = Nexus.Host.parse(full)
      assert parsed.user == user
      assert parsed.hostname == host
      assert parsed.port == port
    end
  end

  property "DAG resolution produces valid topological order" do
    check all tasks <- list_of(task_generator(), min_length: 1, max_length: 20) do
      # Build DAG from tasks
      case Nexus.DAG.build(tasks) do
        {:ok, dag} ->
          order = Nexus.DAG.topological_sort(dag)
          # Verify: every task appears after all its dependencies
          Enum.each(order, fn task ->
            deps = Nexus.DAG.dependencies(dag, task)
            dep_indices = Enum.map(deps, fn d -> Enum.find_index(order, &(&1 == d)) end)
            task_index = Enum.find_index(order, &(&1 == task))
            assert Enum.all?(dep_indices, fn i -> i < task_index end)
          end)

        {:error, :cycle} ->
          # Cycles are expected for some inputs
          :ok
      end
    end
  end
end
```

#### 16.4.3 Generators for Domain Types

```elixir
# test/support/generators.ex
defmodule Nexus.Test.Generators do
  use ExUnitProperties

  def task_generator do
    gen all name <- atom(:alphanumeric),
            deps <- list_of(atom(:alphanumeric), max_length: 3),
            commands <- list_of(command_generator(), min_length: 1, max_length: 5) do
      %{name: name, deps: deps -- [name], commands: commands}
    end
  end

  def command_generator do
    gen all cmd <- string(:alphanumeric, min_length: 1, max_length: 100),
            sudo <- boolean(),
            timeout <- integer(1000..300_000) do
      %{command: cmd, sudo: sudo, timeout: timeout}
    end
  end

  def host_generator do
    gen all user <- one_of([constant(nil), string(:alphanumeric, min_length: 1)]),
            hostname <- string(:alphanumeric, min_length: 1, max_length: 50),
            port <- one_of([constant(22), integer(1..65535)]) do
      %{user: user, hostname: hostname, port: port}
    end
  end
end
```

### 16.5 Performance & Load Testing

#### 16.5.1 Performance Benchmarks

```elixir
# bench/ssh_benchmark.exs
defmodule Nexus.Bench.SSH do
  use Benchee

  @hosts Enum.map(1..10, fn i -> "host-#{i}.test" end)

  def run do
    Benchee.run(
      %{
        "sequential connections" => fn ->
          Enum.each(@hosts, fn host ->
            {:ok, conn} = Nexus.SSH.connect(host)
            Nexus.SSH.close(conn)
          end)
        end,
        "parallel connections" => fn ->
          @hosts
          |> Task.async_stream(fn host ->
            {:ok, conn} = Nexus.SSH.connect(host)
            Nexus.SSH.close(conn)
          end, max_concurrency: 10)
          |> Enum.to_list()
        end,
        "pooled connections" => fn ->
          Enum.each(@hosts, fn host ->
            Nexus.SSH.Pool.checkout(host, fn conn ->
              Nexus.SSH.exec(conn, "echo test")
            end)
          end)
        end
      },
      time: 10,
      memory_time: 2,
      formatters: [
        {Benchee.Formatters.HTML, file: "bench/output/ssh.html"},
        Benchee.Formatters.Console
      ]
    )
  end
end
```

#### 16.5.2 Load Testing Scenarios

| Scenario | Target | Measurement |
|----------|--------|-------------|
| **100 hosts, 1 command** | <30s total | Connection + execution time |
| **10 hosts, 100 commands** | Stable memory | Memory doesn't grow unbounded |
| **1000 concurrent tasks** | No OOM | Memory under 500MB |
| **Long-running (1hr)** | No degradation | Consistent latency |

```elixir
# test/load/concurrent_hosts_test.exs
defmodule Nexus.Load.ConcurrentHostsTest do
  use ExUnit.Case, async: false

  @tag :load
  @tag timeout: 300_000  # 5 minutes

  test "handles 100 concurrent host connections" do
    hosts = Enum.map(1..100, fn i -> "host-#{i}.test" end)

    start_time = System.monotonic_time(:millisecond)
    initial_memory = :erlang.memory(:total)

    results =
      hosts
      |> Task.async_stream(
        fn host ->
          {:ok, conn} = Nexus.SSH.connect(host)
          {:ok, output, 0} = Nexus.SSH.exec(conn, "echo hello")
          Nexus.SSH.close(conn)
          {host, output}
        end,
        max_concurrency: 50,
        timeout: 30_000
      )
      |> Enum.to_list()

    end_time = System.monotonic_time(:millisecond)
    final_memory = :erlang.memory(:total)

    # Assertions
    assert length(results) == 100
    assert Enum.all?(results, fn {:ok, {_host, output}} -> output =~ "hello" end)
    assert end_time - start_time < 30_000  # Under 30 seconds
    assert final_memory - initial_memory < 100_000_000  # Under 100MB growth
  end
end
```

#### 16.5.3 Continuous Performance Monitoring

```elixir
# In CI pipeline
# .github/workflows/bench.yml
name: Benchmarks

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  benchmark:
    runs-on: ubuntu-latest
    services:
      ssh:
        image: linuxserver/openssh-server:latest
        ports:
          - 2222:2222

    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.16'
          otp-version: '26'

      - run: mix deps.get
      - run: mix run bench/ssh_benchmark.exs

      - name: Compare with baseline
        run: |
          # Compare current results with stored baseline
          mix run bench/compare.exs --baseline bench/baseline.json

      - uses: actions/upload-artifact@v4
        with:
          name: benchmark-results
          path: bench/output/
```

### 16.6 Test Coverage Requirements

| Component | Coverage Target | Notes |
|-----------|----------------|-------|
| **DSL Parser** | 95% | Critical path, exhaustive testing |
| **DAG Resolution** | 90% | Algorithm correctness critical |
| **SSH Module** | 80% | Integration tests supplement |
| **Executor** | 85% | Core business logic |
| **CLI** | 70% | Integration tests cover gaps |
| **Cloud Providers** | 60% | Mocked; real tests in E2E |
| **Overall** | 80% | Minimum for release |

### 16.7 Test Organization

```
test/
├── unit/                       # Fast, isolated tests
│   ├── dsl/
│   │   ├── parser_test.exs
│   │   └── validator_test.exs
│   ├── dag_test.exs
│   ├── ssh/
│   │   ├── pool_test.exs
│   │   └── auth_test.exs
│   └── executor/
│       └── pipeline_test.exs
├── integration/                # Require Docker SSH
│   ├── ssh_test.exs
│   ├── file_transfer_test.exs
│   └── full_pipeline_test.exs
├── property/                   # StreamData property tests
│   ├── dsl_parser_test.exs
│   ├── dag_test.exs
│   └── host_parsing_test.exs
├── load/                       # Performance tests
│   ├── concurrent_hosts_test.exs
│   └── memory_test.exs
├── e2e/                        # Full system tests
│   ├── deploy_test.exs
│   └── cluster_test.exs
├── support/
│   ├── docker_ssh.ex
│   ├── generators.ex
│   ├── mocks.ex
│   └── fixtures/
│       ├── valid_nexus.exs
│       └── ssh_keys/
└── test_helper.exs
```

### 16.8 CI/CD Test Pipeline

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
      - run: mix deps.get
      - run: mix test test/unit --cover
      - run: mix test test/property

  integration:
    runs-on: ubuntu-latest
    needs: unit
    services:
      ssh-ubuntu:
        image: linuxserver/openssh-server
        ports: ["2222:2222"]
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
      - run: mix deps.get
      - run: mix test test/integration

  load:
    runs-on: ubuntu-latest
    needs: integration
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
      - run: mix deps.get
      - run: mix test test/load --timeout 300000

  e2e:
    runs-on: ubuntu-latest
    needs: integration
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
      - run: mix deps.get
      - run: mix test test/e2e
```

---

## 17. Documentation Plan

### 17.1 Overview

Comprehensive documentation strategy covering getting started guides, API documentation, cookbook patterns, and video tutorials.

### 17.2 Documentation Tiers

```
┌─────────────────────────────────────────────────────────────────┐
│                   DOCUMENTATION TIERS                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Tier 1: Getting Started (First 10 minutes)                     │
│  ├── Installation guide                                          │
│  ├── Quick start (hello world)                                   │
│  ├── First remote execution                                      │
│  └── First multi-host deployment                                 │
│                                                                  │
│  Tier 2: Core Documentation                                      │
│  ├── DSL reference                                               │
│  ├── CLI reference                                               │
│  ├── Configuration guide                                         │
│  └── Concepts (DAG, pools, strategies)                          │
│                                                                  │
│  Tier 3: Advanced Topics                                         │
│  ├── Distributed mode (agents)                                   │
│  ├── Cloud integration                                           │
│  ├── Enterprise features                                         │
│  └── Performance tuning                                          │
│                                                                  │
│  Tier 4: Cookbook & Examples                                     │
│  ├── Common deployment patterns                                  │
│  ├── CI/CD integration                                           │
│  ├── Troubleshooting guide                                       │
│  └── Migration guides (from Ansible, etc.)                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 17.3 Documentation Components

#### 17.3.1 Website Structure

```
docs.nexus.run/
├── /                          # Landing page with quick install
├── /getting-started/
│   ├── installation           # All platforms
│   ├── quick-start            # 5-minute hello world
│   ├── first-deploy           # First real deployment
│   └── concepts               # Core concepts explained
├── /reference/
│   ├── dsl                    # Complete DSL reference
│   ├── cli                    # All CLI commands
│   ├── config                 # Configuration options
│   └── api                    # Programmatic API (ExDoc)
├── /guides/
│   ├── hosts                  # Host configuration
│   ├── tasks                  # Task patterns
│   ├── secrets                # Secrets management
│   ├── ssh                    # SSH configuration
│   ├── distributed            # Agent mode
│   ├── cloud                  # Cloud integration
│   └── enterprise             # RBAC, audit, Azure
├── /cookbook/
│   ├── patterns               # Common patterns
│   ├── ci-cd                  # CI/CD integration
│   ├── migrations             # From other tools
│   └── troubleshooting        # Common issues
├── /videos/                   # Video tutorials
└── /community/
    ├── contributing
    ├── changelog
    └── roadmap
```

#### 17.3.2 API Documentation (ExDoc)

```elixir
# mix.exs
def project do
  [
    # ...
    docs: [
      main: "Nexus",
      logo: "assets/logo.svg",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/getting-started.md",
        "guides/dsl-reference.md"
      ],
      groups_for_modules: [
        "Core": [Nexus, Nexus.DSL, Nexus.DAG],
        "Execution": [Nexus.Executor, Nexus.SSH],
        "CLI": [Nexus.CLI],
        "Distributed": [Nexus.Agent, Nexus.Cluster],
        "Cloud": [Nexus.Cloud, Nexus.Cloud.AWS]
      ],
      groups_for_extras: [
        "Guides": Path.wildcard("guides/*.md")
      ]
    ]
  ]
end
```

### 17.4 Getting Started Guide

#### 17.4.1 Installation Page

```markdown
# Installation

## Quick Install (Recommended)

```bash
# macOS / Linux
curl -fsSL https://nexus.run/install.sh | sh

# Verify installation
nexus version
```

## Package Managers

```bash
# macOS (Homebrew)
brew install nexus

# Arch Linux (AUR)
yay -S nexus-bin

# From source (requires Elixir 1.15+)
git clone https://github.com/nexus-run/nexus
cd nexus
mix deps.get
mix escript.build
```

## Binary Downloads

| Platform | Architecture | Download |
|----------|--------------|----------|
| Linux | x86_64 | [nexus-linux-x64.tar.gz](link) |
| Linux | arm64 | [nexus-linux-arm64.tar.gz](link) |
| macOS | x86_64 | [nexus-darwin-x64.tar.gz](link) |
| macOS | arm64 | [nexus-darwin-arm64.tar.gz](link) |

## Shell Completions

```bash
# Bash
nexus completions bash > /etc/bash_completion.d/nexus

# Zsh
nexus completions zsh > ~/.zsh/completions/_nexus

# Fish
nexus completions fish > ~/.config/fish/completions/nexus.fish
```
```

#### 17.4.2 Quick Start (5 Minutes)

```markdown
# Quick Start

## Your First Nexus File

Create `nexus.exs` in your project:

```elixir
task :hello do
  run "echo Hello from Nexus!"
end
```

Run it:

```bash
nexus run hello
```

## Your First Remote Task

```elixir
hosts :servers do
  "user@your-server.com"
end

task :remote_hello, on: :servers do
  run "hostname"
  run "uptime"
end
```

Run it:

```bash
nexus run remote_hello
```

## Task Dependencies

```elixir
task :build do
  run "npm install"
  run "npm run build"
end

task :deploy, deps: [:build], on: :servers do
  run "systemctl restart myapp", sudo: true
end
```

Run deploy (build runs first automatically):

```bash
nexus run deploy
```

**Next:** [First Real Deployment →](/getting-started/first-deploy)
```

### 17.5 Video Tutorial Plan

#### 17.5.1 Video Series Outline

| # | Title | Duration | Content |
|---|-------|----------|---------|
| 1 | **Introduction to Nexus** | 5 min | What is Nexus, why use it |
| 2 | **Installation & Setup** | 8 min | Installing, first run |
| 3 | **Basic Tasks & DSL** | 12 min | Task syntax, commands |
| 4 | **Remote Execution** | 15 min | SSH setup, host groups |
| 5 | **Dependencies & Parallelism** | 10 min | DAG, parallel execution |
| 6 | **Error Handling & Retries** | 10 min | Robust deployments |
| 7 | **Secrets Management** | 12 min | Secure credential handling |
| 8 | **Deployment Strategies** | 15 min | Rolling, canary, blue-green |
| 9 | **Distributed Mode** | 20 min | Agents, mesh networking |
| 10 | **Cloud Integration** | 18 min | AWS, Hetzner bursting |

#### 17.5.2 Video Production Standards

- **Resolution:** 1080p minimum, 4K preferred
- **Audio:** Clear narration, minimal background noise
- **Captions:** Always include (accessibility)
- **Code examples:** Visible, syntax-highlighted
- **Pacing:** Comfortable speed, pausable
- **Hosting:** YouTube + embedded on docs site

### 17.6 Cookbook Examples

#### 17.6.1 Example Categories

```
cookbook/
├── deployment/
│   ├── simple-deploy.exs          # Basic deploy pattern
│   ├── rolling-deploy.exs         # Rolling with health checks
│   ├── blue-green.exs             # Blue-green deployment
│   ├── canary.exs                 # Canary releases
│   └── database-migration.exs     # Zero-downtime migrations
├── infrastructure/
│   ├── server-setup.exs           # Initial server provisioning
│   ├── ssl-renewal.exs            # Let's Encrypt renewal
│   ├── log-rotation.exs           # Log management
│   └── backup.exs                 # Automated backups
├── ci-cd/
│   ├── github-actions.exs         # GitHub Actions integration
│   ├── gitlab-ci.exs              # GitLab CI integration
│   └── local-ci.exs               # Run CI locally
├── homelab/
│   ├── raspberry-pi-cluster.exs   # Pi cluster management
│   ├── media-server.exs           # Plex/Jellyfin deploy
│   └── docker-swarm.exs           # Swarm orchestration
└── migration/
    ├── from-ansible.md            # Ansible → Nexus guide
    ├── from-make.md               # Makefile → Nexus
    └── from-bash.md               # Bash scripts → Nexus
```

### 17.7 Documentation Tooling

| Purpose | Tool | Notes |
|---------|------|-------|
| **Static Site** | VitePress or Starlight | Modern, fast |
| **API Docs** | ExDoc | Standard for Elixir |
| **Search** | Algolia DocSearch | Free for OSS |
| **Versioning** | Built-in | Docs per version |
| **Hosting** | Vercel/Netlify | Auto-deploy from GitHub |
| **Video** | YouTube | Embeddable, accessible |

### 17.8 Documentation Schedule

| Version | Documentation Milestone |
|---------|------------------------|
| v0.1-alpha | Basic README, inline docs |
| v0.1-beta | Getting started, DSL reference |
| v0.1-rc | Full Tier 1 & 2 documentation |
| v0.1 | Complete docs, first 3 videos |
| v0.2 | Secrets, templates, strategies guides |
| v0.3 | Distributed mode, cloud guides |
| v0.4 | Enterprise docs, full video series |

---

## 18. Release & Upgrade Strategy

### 18.1 Overview

This section covers versioning policy, agent upgrade procedures, breaking change handling, and configuration migration strategies.

### 18.2 Versioning Policy

#### 18.2.1 Semantic Versioning

Nexus follows [Semantic Versioning 2.0.0](https://semver.org/):

```
MAJOR.MINOR.PATCH

Examples:
  0.1.0  - First public release
  0.1.1  - Bug fixes
  0.2.0  - New features (backwards compatible)
  1.0.0  - Stable API guarantee
  2.0.0  - Breaking changes
```

#### 18.2.2 Pre-1.0 Guarantees

| Version Range | Stability |
|---------------|-----------|
| 0.x.y | API may change between minor versions |
| 0.x.y → 0.x.z | Patch versions are always compatible |
| 0.x → 0.y | Migration guide provided for breaking changes |

#### 18.2.3 Post-1.0 Guarantees

| Change Type | Version Bump |
|-------------|--------------|
| Bug fixes | PATCH (1.0.x) |
| New features (compatible) | MINOR (1.x.0) |
| Breaking changes | MAJOR (x.0.0) |
| Deprecations | MINOR (with warnings) |
| Removal of deprecated | MAJOR |

### 18.3 Agent Upgrade Procedures

#### 18.3.1 Version Compatibility Matrix

```
┌─────────────────────────────────────────────────────────────────┐
│                 VERSION COMPATIBILITY                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Coordinator v0.3.x can communicate with:                       │
│    ✓ Agent v0.3.x (same minor)                                  │
│    ✓ Agent v0.3.y where y ≤ x (older patch)                    │
│    ✗ Agent v0.2.x (older minor - may work, not guaranteed)     │
│    ✗ Agent v0.4.x (newer minor - unknown protocol)             │
│                                                                  │
│  Rule: Coordinator version ≥ Agent version                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### 18.3.2 Upgrade Strategies

| Strategy | Description | Use When |
|----------|-------------|----------|
| **Rolling** | Upgrade agents one at a time | Normal operation |
| **Blue-Green** | New cluster, switch traffic | Major version changes |
| **Canary** | Upgrade subset, validate | Critical environments |

#### 18.3.3 Rolling Agent Upgrade

```bash
# 1. Upgrade coordinator first
$ curl -fsSL https://nexus.run/install.sh | sh

# 2. Verify coordinator version
$ nexus version
Nexus 0.3.2

# 3. Check agent versions
$ nexus cluster status
AGENT           VERSION   STATUS
agent-1.tail    0.3.1     online
agent-2.tail    0.3.1     online
agent-3.tail    0.3.1     online

# 4. Rolling upgrade
$ nexus agent upgrade --rolling
Upgrading agent-1.tail from 0.3.1 to 0.3.2...
  ✓ Draining tasks...
  ✓ Downloading new version...
  ✓ Restarting agent...
  ✓ Health check passed
Upgrading agent-2.tail from 0.3.1 to 0.3.2...
  ...

# 5. Verify
$ nexus cluster status
AGENT           VERSION   STATUS
agent-1.tail    0.3.2     online
agent-2.tail    0.3.2     online
agent-3.tail    0.3.2     online
```

#### 18.3.4 Automatic Agent Updates

```elixir
# /etc/nexus/agent.exs
agent do
  # Check for updates hourly
  auto_update true
  update_channel :stable  # :stable, :beta, :nightly

  # Update during maintenance window
  update_window hours: 2..4, timezone: "UTC"

  # Require coordinator approval
  update_approval :coordinator  # or :auto
end
```

### 18.4 Breaking Change Policy

#### 18.4.1 Breaking Change Categories

| Category | Examples | Handling |
|----------|----------|----------|
| **DSL Syntax** | Keyword rename, new required field | Deprecation warnings first |
| **CLI Interface** | Flag rename, behavior change | Old flag kept as alias |
| **Config Format** | Schema change | Migration command provided |
| **Protocol** | Agent-coordinator protocol | Version negotiation |
| **Behavior** | Default value change | Document in CHANGELOG |

#### 18.4.2 Deprecation Process

```
Version N:
  - Feature works normally
  
Version N+1:
  - Feature works but emits deprecation warning
  - Warning includes migration path
  - Documented in CHANGELOG
  
Version N+2 (or MAJOR):
  - Feature removed
  - Error with helpful message
```

Example deprecation warning:
```
warning: `ssh_key` option is deprecated and will be removed in v0.4
         Use `ssh_identity` instead.
         
         config :nexus do
           # Before (deprecated)
           ssh_key "~/.ssh/id_rsa"
           
           # After
           ssh_identity "~/.ssh/id_rsa"
         end
         
         Location: nexus.exs:5
```

### 18.5 Configuration Migration

#### 18.5.1 Migration Command

```bash
# Check for config issues
$ nexus config check
Checking nexus.exs...

Deprecations found:
  - Line 5: `ssh_key` is deprecated, use `ssh_identity`
  - Line 12: `retry` is deprecated, use `retries`

Run `nexus config migrate` to automatically update.

# Automatic migration
$ nexus config migrate
Migrating nexus.exs...
  ✓ Renamed ssh_key → ssh_identity (line 5)
  ✓ Renamed retry → retries (line 12)

Original saved to: nexus.exs.bak
Migration complete. Please review changes.

# Dry-run mode
$ nexus config migrate --dry-run
Would make the following changes:
  - Line 5: ssh_key → ssh_identity
  - Line 12: retry → retries
```

#### 18.5.2 Config Version Tracking

```elixir
# nexus.exs
# config_version is automatically added on first migration
config_version 2

config :nexus do
  ssh_identity "~/.ssh/id_rsa"
  retries 3
end
```

#### 18.5.3 Migration Registry

```elixir
# lib/nexus/config/migrations.ex
defmodule Nexus.Config.Migrations do
  @migrations [
    {1, "0.1.0", &migrate_v1_to_v2/1},
    {2, "0.2.0", &migrate_v2_to_v3/1},
    # ...
  ]

  def migrate(config, from_version, to_version) do
    @migrations
    |> Enum.filter(fn {v, _, _} -> v > from_version and v <= to_version end)
    |> Enum.reduce(config, fn {_, _, migration_fn}, acc ->
      migration_fn.(acc)
    end)
  end

  defp migrate_v1_to_v2(config) do
    config
    |> rename_key(:ssh_key, :ssh_identity)
    |> rename_key(:retry, :retries)
  end
end
```

### 18.6 Release Channels

| Channel | Update Frequency | Stability | Use Case |
|---------|------------------|-----------|----------|
| **stable** | Every 2-4 weeks | Production-ready | Production |
| **beta** | Weekly | Feature-complete, testing | Staging |
| **nightly** | Daily | May break | Development |

```bash
# Check current channel
$ nexus version --verbose
Nexus 0.3.2-stable
Channel: stable
Built: 2025-12-28T10:00:00Z

# Switch channel
$ nexus update --channel beta
Switching to beta channel...
Downloading nexus 0.4.0-beta.3...
Updated successfully.

# Pin to specific version
$ nexus update --version 0.3.1
```

### 18.7 Release Checklist

```markdown
## Release Checklist for vX.Y.Z

### Pre-Release
- [ ] All tests passing on CI
- [ ] Dialyzer clean
- [ ] Credo clean
- [ ] CHANGELOG.md updated
- [ ] Documentation updated
- [ ] Migration guide written (if breaking changes)
- [ ] Deprecation warnings added (if needed)

### Build
- [ ] Tag release in Git
- [ ] Build binaries (Linux x64, Linux arm64, macOS x64, macOS arm64)
- [ ] Sign binaries
- [ ] Generate checksums

### Publish
- [ ] Upload to GitHub Releases
- [ ] Update Homebrew formula
- [ ] Update AUR package
- [ ] Publish to Hex.pm
- [ ] Update installation script

### Announce
- [ ] GitHub release notes
- [ ] Discord/Slack announcement
- [ ] Twitter/X post
- [ ] Blog post (major releases only)

### Post-Release
- [ ] Monitor for issues
- [ ] Update version in main branch
- [ ] Close milestone
```

---

## 19. Telemetry & Observability

### 19.1 Overview

This section covers the telemetry and observability strategy, including OpenTelemetry integration, Grafana dashboards, and Prometheus metrics.

### 19.2 Telemetry Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   TELEMETRY ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌───────────────┐                                              │
│  │    Nexus      │                                              │
│  │  Application  │                                              │
│  └───────┬───────┘                                              │
│          │                                                       │
│          ▼                                                       │
│  ┌───────────────┐     ┌───────────────┐     ┌───────────────┐  │
│  │  :telemetry   │────►│  Handlers     │────►│   Exporters   │  │
│  │   events      │     │               │     │               │  │
│  └───────────────┘     └───────────────┘     └───────┬───────┘  │
│                                                       │          │
│                              ┌────────────────────────┼──────┐   │
│                              ▼                        ▼      ▼   │
│                     ┌──────────────┐  ┌──────────┐  ┌─────────┐ │
│                     │  Prometheus  │  │  Jaeger  │  │  Logs   │ │
│                     └──────────────┘  └──────────┘  └─────────┘ │
│                              │               │            │      │
│                              ▼               ▼            ▼      │
│                     ┌──────────────────────────────────────────┐│
│                     │              Grafana                      ││
│                     └──────────────────────────────────────────┘│
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 19.3 Telemetry Events

#### 19.3.1 Complete Event Catalog

```elixir
# All telemetry events emitted by Nexus

# ══════════════════════════════════════════════════════════════
# Pipeline Events
# ══════════════════════════════════════════════════════════════

[:nexus, :pipeline, :start]
# Measurements: %{}
# Metadata: %{pipeline_id, tasks, hosts}

[:nexus, :pipeline, :stop]
# Measurements: %{duration}
# Metadata: %{pipeline_id, status, tasks_completed, tasks_failed}

[:nexus, :pipeline, :exception]
# Measurements: %{duration}
# Metadata: %{pipeline_id, kind, reason, stacktrace}

# ══════════════════════════════════════════════════════════════
# Task Events
# ══════════════════════════════════════════════════════════════

[:nexus, :task, :start]
# Measurements: %{}
# Metadata: %{task, hosts, attempt}

[:nexus, :task, :stop]
# Measurements: %{duration}
# Metadata: %{task, hosts, status, commands_executed}

[:nexus, :task, :retry]
# Measurements: %{delay}
# Metadata: %{task, attempt, max_attempts, reason}

# ══════════════════════════════════════════════════════════════
# Command Events
# ══════════════════════════════════════════════════════════════

[:nexus, :command, :start]
# Measurements: %{}
# Metadata: %{task, host, command, sudo}

[:nexus, :command, :stop]
# Measurements: %{duration}
# Metadata: %{task, host, command, exit_code}

# ══════════════════════════════════════════════════════════════
# SSH Events
# ══════════════════════════════════════════════════════════════

[:nexus, :ssh, :connect, :start]
# Measurements: %{}
# Metadata: %{host, user, port}

[:nexus, :ssh, :connect, :stop]
# Measurements: %{duration}
# Metadata: %{host, status}

[:nexus, :ssh, :pool, :checkout]
# Measurements: %{queue_time}
# Metadata: %{host, pool_size, available}

[:nexus, :ssh, :pool, :checkin]
# Measurements: %{use_time}
# Metadata: %{host}

# ══════════════════════════════════════════════════════════════
# Cluster Events (v0.3+)
# ══════════════════════════════════════════════════════════════

[:nexus, :cluster, :node, :join]
# Metadata: %{node, tags, capabilities}

[:nexus, :cluster, :node, :leave]
# Metadata: %{node, reason}

[:nexus, :cluster, :scheduler, :assign]
# Metadata: %{task, node, reason}

# ══════════════════════════════════════════════════════════════
# Cloud Events (v0.3+)
# ══════════════════════════════════════════════════════════════

[:nexus, :cloud, :instance, :provision]
# Measurements: %{duration}
# Metadata: %{provider, instance_type, region}

[:nexus, :cloud, :instance, :terminate]
# Measurements: %{runtime, cost}
# Metadata: %{provider, instance_id, reason}
```

### 19.4 OpenTelemetry Integration

#### 19.4.1 Configuration

```elixir
# config/runtime.exs
config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :otlp

config :opentelemetry_exporter,
  otlp_protocol: :grpc,
  otlp_endpoint: System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")

# Or for OTLP/HTTP
config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_endpoint: System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")
```

#### 19.4.2 Span Structure

```
Pipeline: deploy (trace_id: abc123)
├── Task: build (span_id: task-1)
│   ├── Command: npm install (span_id: cmd-1)
│   └── Command: npm run build (span_id: cmd-2)
├── Task: deploy (span_id: task-2)
│   ├── Host: web-1 (span_id: host-1)
│   │   ├── Command: systemctl stop (span_id: cmd-3)
│   │   └── Command: systemctl start (span_id: cmd-4)
│   └── Host: web-2 (span_id: host-2)
│       ├── Command: systemctl stop (span_id: cmd-5)
│       └── Command: systemctl start (span_id: cmd-6)
└── Task: verify (span_id: task-3)
    └── Command: curl health (span_id: cmd-7)
```

#### 19.4.3 Custom Span Attributes

```elixir
defmodule Nexus.Telemetry.OpenTelemetry do
  require OpenTelemetry.Tracer, as: Tracer

  def instrument_task(task, fun) do
    Tracer.with_span "nexus.task.#{task.name}", %{
      attributes: [
        {"nexus.task.name", task.name},
        {"nexus.task.hosts", length(task.hosts)},
        {"nexus.task.commands", length(task.commands)},
        {"nexus.task.strategy", task.strategy}
      ]
    } do
      fun.()
    end
  end
end
```

### 19.5 Prometheus Metrics

#### 19.5.1 Metric Definitions

```elixir
# lib/nexus/telemetry/prometheus.ex
defmodule Nexus.Telemetry.Prometheus do
  use PromEx

  @impl true
  def plugins do
    [
      Nexus.Telemetry.Prometheus.Pipeline,
      Nexus.Telemetry.Prometheus.SSH,
      Nexus.Telemetry.Prometheus.Cluster
    ]
  end
end

# Metrics defined
defmodule Nexus.Telemetry.Prometheus.Pipeline do
  use PromEx.Plugin

  @impl true
  def metrics(_opts) do
    [
      # Pipeline metrics
      counter("nexus.pipeline.total",
        event_name: [:nexus, :pipeline, :stop],
        tags: [:status]
      ),
      distribution("nexus.pipeline.duration.milliseconds",
        event_name: [:nexus, :pipeline, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:status]
      ),

      # Task metrics
      counter("nexus.task.total",
        event_name: [:nexus, :task, :stop],
        tags: [:task, :status]
      ),
      distribution("nexus.task.duration.milliseconds",
        event_name: [:nexus, :task, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:task]
      ),
      counter("nexus.task.retries.total",
        event_name: [:nexus, :task, :retry],
        tags: [:task]
      ),

      # Command metrics
      distribution("nexus.command.duration.milliseconds",
        event_name: [:nexus, :command, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:host]
      ),
      counter("nexus.command.failures.total",
        event_name: [:nexus, :command, :stop],
        filter: fn _event, %{exit_code: code} -> code != 0 end,
        tags: [:host, :task]
      )
    ]
  end
end
```

#### 19.5.2 Prometheus Endpoint

```elixir
# lib/nexus/telemetry/prometheus_plug.ex
defmodule Nexus.Telemetry.PrometheusPlug do
  use Plug.Router

  plug :match
  plug :dispatch

  get "/metrics" do
    metrics = Nexus.Telemetry.Prometheus.metrics()
    send_resp(conn, 200, metrics)
  end
end

# Start in agent mode
# http://localhost:9090/metrics
```

### 19.6 Grafana Dashboards

#### 19.6.1 Dashboard Overview

```json
{
  "title": "Nexus Overview",
  "panels": [
    {
      "title": "Pipeline Success Rate",
      "type": "stat",
      "targets": [{
        "expr": "sum(rate(nexus_pipeline_total{status=\"success\"}[5m])) / sum(rate(nexus_pipeline_total[5m])) * 100"
      }]
    },
    {
      "title": "Pipeline Duration (p95)",
      "type": "timeseries",
      "targets": [{
        "expr": "histogram_quantile(0.95, rate(nexus_pipeline_duration_milliseconds_bucket[5m]))"
      }]
    },
    {
      "title": "Tasks by Status",
      "type": "piechart",
      "targets": [{
        "expr": "sum by (status) (nexus_task_total)"
      }]
    },
    {
      "title": "SSH Connection Pool",
      "type": "gauge",
      "targets": [{
        "expr": "nexus_ssh_pool_available / nexus_ssh_pool_size * 100"
      }]
    },
    {
      "title": "Command Failure Rate by Host",
      "type": "table",
      "targets": [{
        "expr": "sum by (host) (rate(nexus_command_failures_total[5m]))"
      }]
    }
  ]
}
```

#### 19.6.2 Pre-Built Dashboards

| Dashboard | Contents |
|-----------|----------|
| **Overview** | Pipeline success rate, duration, task counts |
| **SSH Performance** | Connection times, pool utilization, errors |
| **Cluster Health** | Node status, task distribution, failures |
| **Cloud Costs** | Instance runtime, costs, spot interruptions |

#### 19.6.3 Dashboard Provisioning

```yaml
# grafana/provisioning/dashboards/nexus.yaml
apiVersion: 1
providers:
  - name: Nexus
    type: file
    folder: Nexus
    options:
      path: /var/lib/grafana/dashboards/nexus
```

### 19.7 Log Aggregation

#### 19.7.1 Structured Logging

```elixir
# All logs are structured JSON in production
config :logger, :default_handler,
  formatter: {LoggerJSON.Formatter, %{}}

# Log output example
{
  "time": "2025-12-28T10:30:00.000Z",
  "level": "info",
  "message": "Task completed",
  "metadata": {
    "task": "deploy",
    "host": "web-1.example.com",
    "duration_ms": 4523,
    "exit_code": 0,
    "pipeline_id": "abc-123",
    "trace_id": "def-456"
  }
}
```

#### 19.7.2 Log Levels Strategy

| Level | Use For | Examples |
|-------|---------|----------|
| **debug** | Detailed internal state | SSH packet contents, pool state |
| **info** | Normal operations | Task start/complete, connections |
| **warning** | Recoverable issues | Retries, slow operations |
| **error** | Failures | Command failures, connection errors |

### 19.8 Alerting

#### 19.8.1 Recommended Alerts

```yaml
# prometheus/alerts/nexus.yaml
groups:
  - name: nexus
    rules:
      - alert: NexusPipelineFailureRate
        expr: |
          sum(rate(nexus_pipeline_total{status="failed"}[5m])) 
          / sum(rate(nexus_pipeline_total[5m])) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High pipeline failure rate"
          description: "More than 10% of pipelines failing"

      - alert: NexusSSHPoolExhausted
        expr: nexus_ssh_pool_available == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "SSH connection pool exhausted"
          description: "No available SSH connections for {{ $labels.host }}"

      - alert: NexusAgentDown
        expr: up{job="nexus-agent"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Nexus agent down"
          description: "Agent {{ $labels.instance }} is not responding"
```

### 19.9 Observability Configuration

```elixir
# nexus.exs or config/runtime.exs
config :nexus, :observability do
  # Prometheus metrics endpoint
  prometheus enabled: true, port: 9090

  # OpenTelemetry tracing
  opentelemetry enabled: true,
    endpoint: env("OTEL_ENDPOINT", "http://localhost:4317")

  # Log shipping
  logs format: :json,
    level: :info,
    syslog: [host: "syslog.example.com", port: 514]

  # Grafana dashboard annotations
  grafana enabled: true,
    url: env("GRAFANA_URL"),
    api_key: env("GRAFANA_API_KEY")
end
```

---

## 20. Success Metrics

### 20.1 Adoption Metrics

| Metric | Target (6 months) | Target (1 year) |
|--------|-------------------|-----------------|
| GitHub stars | 1,000 | 5,000 |
| Monthly downloads | 5,000 | 25,000 |
| Discord/Slack members | 500 | 2,000 |
| Contributors | 10 | 50 |
| Production users | 100 | 1,000 |

### 20.2 Quality Metrics

| Metric | Target |
|--------|--------|
| Test coverage | >80% |
| Dialyzer warnings | 0 |
| Credo issues | 0 |
| Open bugs (P0/P1) | <5 |
| Documentation coverage | 100% public API |
| Time to first response | <24 hours |

### 20.3 User Satisfaction

| Metric | Target |
|--------|--------|
| NPS score | >50 |
| "Would recommend" | >80% |
| Issue resolution time | <7 days |
| Feature request implementation | Top 10 in 6 months |

---

## 21. Appendices

### 21.1 Glossary

| Term | Definition |
|------|------------|
| Agent | Long-running Nexus daemon on a node |
| Artifact | File produced by a task, transferred to dependents |
| Cluster | Collection of nodes running Nexus agents |
| Coordinator | Node initiating a pipeline |
| DAG | Directed Acyclic Graph (task dependencies) |
| Host | Target machine for remote execution |
| Host Group | Named collection of hosts |
| Node | Machine participating in Nexus cluster |
| Pipeline | Full execution of a task and its dependencies |
| Shard | Portion of work in parallel sharded execution |
| Task | Named unit of work with commands |
| Tailnet | Tailscale network |

### 21.2 Example nexus.exs Files

**Minimal:**
```elixir
task :hello do
  run "echo Hello, World!"
end
```

**Simple Deploy:**
```elixir
hosts :web do
  "web-1.example.com"
  "web-2.example.com"
end

task :build do
  run "npm install"
  run "npm run build"
end

task :deploy, on: :web, deps: [:build] do
  run "systemctl stop myapp", sudo: true
  run "cp -r dist/* /opt/myapp/"
  run "systemctl start myapp", sudo: true
end
```

**Full Production:**
```elixir
# Configuration
config :nexus do
  ssh_user "deploy"
  ssh_identity "~/.ssh/deploy_key"
  parallel_limit 10
  log_level :info
end

# Host groups
hosts :web do
  "web-1.example.com"
  "web-2.example.com"
  "web-3.example.com"
end

hosts :db do
  "db.example.com"
end

hosts :all do
  groups :web, :db
end

# Tasks
task :test do
  run "npm test"
  run "npm run lint"
end

task :build, deps: [:test] do
  run "npm run build"
  run "tar -czf dist.tar.gz dist/"
end

task :backup_db, on: :db do
  run "pg_dump myapp > /backups/pre-deploy.sql", sudo: true, user: "postgres"
end

task :deploy, on: :web, deps: [:build, :backup_db], strategy: :rolling do
  run "systemctl stop myapp", sudo: true
  run "rm -rf /opt/myapp/*"
  run "tar -xzf /tmp/dist.tar.gz -C /opt/myapp/"
  run "systemctl start myapp", sudo: true
  run "curl -f http://localhost:8080/health", retries: 5, retry_delay: 2000
end

task :migrate, on: :db, deps: [:deploy] do
  run "cd /opt/myapp && ./migrate.sh", sudo: true, user: "myapp"
end

task :ship, deps: [:migrate] do
  run "echo 'Deployment complete!'"
end
```

### 21.3 Comparison Matrix

| Feature | Nexus | Make | Ansible | GitHub Actions |
|---------|-------|------|---------|----------------|
| Local tasks | ✅ | ✅ | ❌ | ❌ |
| Remote tasks | ✅ | ❌ | ✅ | ❌ |
| Parallel execution | ✅ | ⚠️ | ⚠️ | ✅ |
| Dependencies | ✅ | ✅ | ⚠️ | ✅ |
| Typed config | ✅ | ❌ | ❌ | ❌ |
| Single syntax | ✅ | ✅ | ✅ | ✅ |
| No YAML | ✅ | ✅ | ❌ | ❌ |
| Self-hosted | ✅ | ✅ | ✅ | ⚠️ |
| Cloud burst | ✅ | ❌ | ❌ | ✅ |
| Fault tolerance | ✅ | ❌ | ❌ | ✅ |
| Zero infrastructure | ✅ | ✅ | ✅ | ❌ |

### 21.4 Future Considerations (Beyond v0.4)

- **Windows native support**: Full Windows execution, not just WSL
- **Web UI**: Optional browser dashboard
- **Terraform integration**: Read Terraform state for host discovery
- **Kubernetes integration**: Pod discovery and execution
- **Plugin system**: User-defined providers and strategies
- **Marketplace**: Shareable task libraries
- **SaaS offering**: Hosted Nexus with team features

---

## 22. Library Research & Recommendations

> **Research Date:** December 28, 2025
> **Methodology:** Web search of Hex.pm, GitHub, Elixir Forum, and community resources

### 22.1 Research Summary

This section documents the comprehensive library research conducted to validate all dependencies in this PRD. Each library was evaluated for:
- Active maintenance status (commits in last 6 months)
- Community adoption (downloads, stars)
- Production readiness
- Alternative options

### 22.2 Critical Path Libraries

#### 22.2.1 SSH Libraries - CRITICAL

| Library | Status | Stars | Last Release | Recommendation |
|---------|--------|-------|--------------|----------------|
| **SSHKit** | Active | ~200 | 2024 | **USE** - Only maintained high-level wrapper |
| SSHEx | **ARCHIVED** | ~150 | Oct 2024 | **DO NOT USE** - Archived |
| Librarian | Active | ~50 | 2020 | Consider for SCP streaming |
| sftp_client | Active | ~100 | 2024 | USE for file transfers |
| Erlang `:ssh` | Core OTP | N/A | Always | Fallback for advanced features |

**Decision:** Use **SSHKit** as primary SSH library. It's the only actively maintained high-level wrapper after SSHEx was archived in October 2024. May need to extend for PTY allocation and advanced streaming.

**Source:** [SSHKit GitHub](https://github.com/bitcrowd/sshkit.ex)

#### 22.2.2 Binary Packaging - CRITICAL

| Library | Status | Last Release | Recommendation |
|---------|--------|--------------|----------------|
| **Burrito** | Active | 2024 | **USE** - Only viable option |
| Bakeware | **ARCHIVED** | Sep 2024 | **DO NOT USE** - Archived |

**Decision:** Use **Burrito**. Bakeware was archived in September 2024.

**Source:** [Burrito Hex.pm](https://hex.pm/packages/burrito)

### 22.3 HTTP Client Stack

The Elixir HTTP client ecosystem has a clear layered architecture:

```
┌─────────────────────────────────────────────┐
│                    Req                       │  ← Use this (high-level)
│         (batteries-included client)          │
├─────────────────────────────────────────────┤
│                   Finch                      │  ← Connection pooling
│           (performance-focused)              │
├─────────────────────────────────────────────┤
│                   Mint                       │  ← Low-level, processless
│             (HTTP/1 & HTTP/2)                │
└─────────────────────────────────────────────┘
```

**Recommendation:** Use **Req** for all HTTP needs. It's becoming the Phoenix default and provides the best developer experience.

**Sources:**
- [Req GitHub](https://github.com/wojtekmach/req)
- [Finch GitHub](https://github.com/sneako/finch)
- [HTTP Client Comparison](https://elixirmerge.com/p/choosing-an-http-client-library-in-elixir)

### 22.4 Cloud Provider SDKs

| Provider | Library | Status | Downloads | Recommendation |
|----------|---------|--------|-----------|----------------|
| **AWS** | ex_aws | Very Active | 66M+ | **USE** - Mature, well-maintained |
| AWS | aws-elixir | Active | 1M+ | Alternative - auto-generated |
| **Hetzner** | hcloud | Active | ~50K | **USE** - Community maintained |
| **GCP** | elixir-google-api | Official | ~500K | **USE** - Official Google |
| **Azure** | ex_microsoft_azure_* | Prototype | <10K | **DO NOT USE** - Build custom with Req |

**Azure Gap:** There is no production-ready Azure SDK for Elixir. The `ex_microsoft_azure_*` packages are prototypes/generators. Must build custom REST client.

**Sources:**
- [ex_aws GitHub](https://github.com/ex-aws/ex_aws)
- [hcloud Hex.pm](https://hex.pm/packages/hcloud)
- [elixir-google-api GitHub](https://github.com/googleapis/elixir-google-api)

### 22.5 Distributed Systems

| Library | Purpose | Status | Recommendation |
|---------|---------|--------|----------------|
| **libcluster** | Cluster formation | Active | **USE** - Standard for Elixir |
| **Horde** | Distributed registry/supervisor | Active (2025) | **USE** - Replaces Swarm |
| libcluster_tailscale | Tailscale discovery | Active | USE for Tailscale |
| libcluster_hcloud | Hetzner discovery | Active | USE for Hetzner |
| Broadway | Pipeline processing | Active (v1.2.1) | CONSIDER for task execution |

**Pattern:** libcluster + Horde is the proven production pattern for distributed Elixir applications.

**Sources:**
- [libcluster GitHub](https://github.com/bitwalker/libcluster)
- [Horde GitHub](https://github.com/derekkraan/horde)
- [Distributed Systems Article (Feb 2025)](https://planet.kde.org/davide-briani-2025-02-14-the-secret-weapon-for-processing-millions-of-messages-in-order-with-elixir/)

### 22.6 Terminal & CLI

| Library | Purpose | Status | Recommendation |
|---------|---------|--------|----------------|
| **Optimus** | CLI arg parsing | Active | **USE** - Full-featured |
| **Owl** | Terminal output | Active (v0.13) | **USE** - Progress bars, colors |
| **Ratatouille** | TUI framework | Active | **USE** for v0.3 TUI |
| Garnish | TUI over SSH | New (2024) | Consider for SSH-based TUI |
| OptionParser | CLI parsing | Built-in | Basic needs only |

**Sources:**
- [Owl GitHub](https://github.com/fuelen/owl)
- [Ratatouille GitHub](https://github.com/ndreynolds/ratatouille)

### 22.7 Authentication & Security

| Library | Purpose | Status | Recommendation |
|---------|---------|--------|----------------|
| **Joken** | JWT tokens | Active (Dec 2024) | **USE** - Lightweight |
| Guardian | Full auth framework | Active | Alternative if needed |
| **Assent** | OAuth2/OIDC | Active (Jul 2024) | **USE** for Azure AD |
| Ueberauth | Auth strategies | Active | Alternative to Assent |
| sasl_auth | Kerberos/GSSAPI | Active | **CAUTION** - Kafka-focused |

**Kerberos Warning:** No production-ready Kerberos SSH library exists for Elixir. The sasl_auth library is focused on Kafka SASL authentication. Custom NIF may be required.

**Sources:**
- [Joken GitHub](https://github.com/joken-elixir/joken)
- [Assent GitHub](https://github.com/pow-auth/assent)

### 22.8 Logging & Telemetry

| Library | Purpose | Status | Recommendation |
|---------|---------|--------|----------------|
| **Telemetry** | Event emission | Core | **USE** - Standard |
| **Telemetry.Metrics** | Aggregation | Core | **USE** |
| **OpenTelemetry** | Distributed tracing | Active | **USE** for v0.4 |
| **kvasir_syslog** | Syslog | Active (Feb 2025) | **USE** - Most recent |
| ExSyslogger | Syslog backend | Active | Alternative |

**Sources:**
- [OpenTelemetry Elixir](https://opentelemetry.io/docs/languages/erlang/)
- [kvasir_syslog Hex.pm](https://hex.pm/packages/kvasir_syslog)

### 22.9 DAG & Graph Libraries

| Library | Status | Recommendation |
|---------|--------|----------------|
| **libgraph** | Active | **USE** - Comprehensive, by libcluster author |
| dag | Active | Alternative - simpler, struct-based |
| Erlang `:digraph` | Core OTP | Fallback for large graphs |

**Source:** [libgraph GitHub](https://github.com/bitwalker/libgraph)

### 22.10 Risk Assessment Matrix

| Dependency Area | Risk | Mitigation |
|-----------------|------|------------|
| SSH (SSHKit) | MEDIUM | May need to extend; Erlang `:ssh` as fallback |
| Binary Packaging (Burrito) | LOW | Well-maintained, only option |
| Azure SDK | **HIGH** | Must build custom; budget significant time |
| Kerberos/GSSAPI | **HIGH** | May need custom NIF; consider SSSD alternative |
| Cloud SDKs (AWS/GCP) | LOW | Mature libraries available |
| Hetzner SDK | LOW | Community maintained, works well |
| Distributed (libcluster/Horde) | LOW | Proven in production |
| TUI (Ratatouille) | MEDIUM | Only option; may need fixes |

### 22.11 Consolidated Dependencies List

Complete list of all dependencies across all versions:

```elixir
# mix.exs - Complete dependency list

defp deps do
  [
    # ════════════════════════════════════════════════════════════════════════
    # v0.1 - Core
    # ════════════════════════════════════════════════════════════════════════
    {:optimus, "~> 0.5"},              # CLI parsing
    {:owl, "~> 0.13"},                 # Terminal output
    {:sshkit, "~> 0.3"},               # SSH client
    {:sftp_client, "~> 2.0"},          # SFTP transfers
    {:ssh_client_key_api, "~> 0.3"},   # SSH key handling
    {:nimble_pool, "~> 1.1"},          # Connection pooling
    {:libgraph, "~> 0.16"},            # DAG resolution
    {:nimble_options, "~> 1.1"},       # Config validation
    {:telemetry, "~> 1.3"},            # Observability
    {:telemetry_metrics, "~> 1.0"},    # Metrics
    {:burrito, "~> 1.0"},              # Binary packaging

    # ════════════════════════════════════════════════════════════════════════
    # v0.2 - Enhanced Operations
    # ════════════════════════════════════════════════════════════════════════
    {:req, "~> 0.5"},                  # HTTP client
    {:libcluster_tailscale, "~> 0.1"}, # Tailscale discovery
    {:nimble_parsec, "~> 1.4"},        # Parsing

    # ════════════════════════════════════════════════════════════════════════
    # v0.3 - Distributed & Cloud
    # ════════════════════════════════════════════════════════════════════════
    {:ex_aws, "~> 2.6"},               # AWS SDK
    {:ex_aws_ec2, "~> 2.0"},           # AWS EC2
    {:ex_aws_s3, "~> 2.0"},            # AWS S3
    {:hcloud, "~> 1.0"},               # Hetzner
    {:libcluster_hcloud, "~> 0.1"},    # Hetzner discovery
    {:google_api_compute, "~> 0.56"},  # GCP
    {:libcluster, "~> 3.4"},           # Cluster formation
    {:horde, "~> 0.9"},                # Distributed registry
    {:ratatouille, "~> 0.5"},          # TUI
    {:mdns_lite, "~> 0.9"},            # mDNS discovery

    # ════════════════════════════════════════════════════════════════════════
    # v0.4 - Enterprise
    # ════════════════════════════════════════════════════════════════════════
    {:assent, "~> 0.2"},               # OAuth2/OIDC
    {:joken, "~> 2.6"},                # JWT
    {:joken_jwks, "~> 1.6"},           # JWKS
    {:kvasir_syslog, "~> 1.0"},        # Syslog
    {:opentelemetry, "~> 1.4"},        # OpenTelemetry
    {:opentelemetry_api, "~> 1.3"},
    {:opentelemetry_exporter, "~> 1.7"},
    {:sasl_auth, github: "kafka4beam/sasl_auth"}, # Kerberos (evaluate)

    # ════════════════════════════════════════════════════════════════════════
    # Dev & Test (all versions)
    # ════════════════════════════════════════════════════════════════════════
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:ex_doc, "~> 0.35", only: :dev, runtime: false},
    {:mox, "~> 1.2", only: :test},
    {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
    {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
  ]
end
```

### 22.12 Research Sources

All research was conducted on December 28, 2025 using the following sources:

**Primary Sources:**
- [Hex.pm](https://hex.pm) - Elixir package registry
- [GitHub](https://github.com) - Source repositories
- [Elixir Forum](https://elixirforum.com) - Community discussions
- [HexDocs](https://hexdocs.pm) - Package documentation

**Community Resources:**
- [Awesome Elixir](https://github.com/h4cc/awesome-elixir) - Curated library list
- [Elixir School](https://elixirschool.com) - Tutorials
- [Elixir Merge](https://elixirmerge.com) - Articles and guides

**Specific Articles Referenced:**
- [HTTP Client Comparison (Elixir Merge)](https://elixirmerge.com/p/choosing-an-http-client-library-in-elixir)
- [Distributed Elixir with Broadway/Horde (Feb 2025)](https://planet.kde.org/davide-briani-2025-02-14-the-secret-weapon-for-processing-millions-of-messages-in-order-with-elixir/)
- [Distributed Chat Application (BigThinkCode)](https://www.bigthinkcode.com/insights/distributed-chat-application)

---

## 23. Operational Excellence

> **Added:** December 28, 2025 (v1.3)
> **Purpose:** Address operational concerns, resilience patterns, and production hardening requirements identified during final PRD review.

### 23.1 SSH Advanced Configuration

#### 23.1.1 SSH Config File Integration

Nexus should respect and parse `~/.ssh/config` for maximum compatibility with existing SSH workflows.

**Supported Directives (v0.1):**
| Directive | Support | Notes |
|-----------|---------|-------|
| `Host` / `Match host` | ✅ | Pattern matching for host aliases |
| `HostName` | ✅ | Actual hostname resolution |
| `User` | ✅ | Default username |
| `Port` | ✅ | Non-standard ports |
| `IdentityFile` | ✅ | Key file paths |
| `IdentitiesOnly` | ✅ | Restrict to specified keys |
| `ProxyJump` / `-J` | v0.2 | Jump host support |
| `ProxyCommand` | v0.2 | Custom proxy commands |
| `Include` | ✅ | Include other config files |
| `StrictHostKeyChecking` | ✅ | Host key policy |
| `UserKnownHostsFile` | ✅ | Custom known_hosts |
| `ServerAliveInterval` | ✅ | Keepalive settings |
| `ConnectTimeout` | ✅ | Connection timeout |
| `Match exec` | v0.3 | Conditional matching |

**Implementation:**

```elixir
defmodule Nexus.SSH.ConfigParser do
  @moduledoc """
  Parser for OpenSSH config files (~/.ssh/config).
  Supports Host patterns, Include directives, and common options.
  """

  @spec parse(Path.t()) :: {:ok, [host_config()]} | {:error, term()}
  def parse(path \\ "~/.ssh/config")

  @spec lookup(String.t(), [host_config()]) :: host_config()
  def lookup(hostname, configs)
end
```

#### 23.1.2 Jump Host / Bastion Support (v0.2+)

```elixir
hosts :internal do
  "db.internal.corp"
  "cache.internal.corp"
end

config :nexus do
  # Global jump host
  ssh_jump "bastion.corp.com"
  
  # Or per-host group
  ssh_options :internal,
    jump: "bastion.corp.com",
    jump_user: "jumpuser"
end

# Alternative: Multi-hop
task :deep_internal, on: :internal do
  # Uses: local → bastion → internal-bastion → target
  run "hostname"
end
```

**Implementation Strategy:**
- Use `-J` flag for OpenSSH 7.3+
- Fall back to `ProxyCommand` for older versions
- Support multiple hops (comma-separated)
- Integrate with Tailscale (preferred, eliminates need for bastions)

#### 23.1.3 SSH Known Hosts Management

**Host Key Verification Policies:**

| Policy | Description | Use Case |
|--------|-------------|----------|
| `strict` | Reject unknown/changed keys | Production (default) |
| `accept_new` | Accept new, reject changed | Development |
| `tofu` | Trust On First Use | Initial setup |
| `off` | No verification | **Never in production** |

```elixir
config :nexus do
  # Host key verification policy
  ssh_host_key_verification :strict  # default

  # Custom known_hosts file
  ssh_known_hosts_file ".nexus/known_hosts"

  # Auto-update known_hosts on first connection
  ssh_auto_add_host_keys false  # default
end

# CLI commands
# Scan and add host keys before deployment
$ nexus hosts scan --add-to-known-hosts
Scanning 5 hosts...
  ✓ web-1.example.com (ssh-ed25519 SHA256:abc...)
  ✓ web-2.example.com (ssh-ed25519 SHA256:def...)
  ...
Added 5 host keys to .nexus/known_hosts

# Verify known hosts match
$ nexus hosts verify
All 5 host keys match known_hosts file.
```

**Best Practices:**
1. Pre-populate known_hosts in CI/CD pipelines
2. Use SSHFP DNS records with DNSSEC where possible
3. Store known_hosts in version control (without secrets)
4. Alert on host key changes (potential MITM)

### 23.2 Resilience Patterns

#### 23.2.1 Retry with Exponential Backoff and Jitter

All retry operations in Nexus use exponential backoff with jitter to prevent thundering herd problems.

```elixir
defmodule Nexus.Retry do
  @moduledoc """
  Retry logic with exponential backoff and jitter.
  Based on AWS best practices.
  """

  @type strategy :: :full_jitter | :equal_jitter | :decorrelated_jitter

  @default_opts [
    base_delay: 1_000,       # 1 second
    max_delay: 30_000,       # 30 seconds cap
    max_attempts: 5,
    strategy: :full_jitter,  # Best for distributed systems
    retryable: &retryable?/1
  ]

  @doc """
  Full Jitter: sleep = random(0, min(cap, base * 2^attempt))
  Provides best distribution of retry times.
  """
  def calculate_delay(attempt, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)
    base = opts[:base_delay]
    cap = opts[:max_delay]

    case opts[:strategy] do
      :full_jitter ->
        max_delay = min(cap, base * :math.pow(2, attempt))
        :rand.uniform(round(max_delay))

      :equal_jitter ->
        temp = min(cap, base * :math.pow(2, attempt))
        temp_half = temp / 2
        round(temp_half + :rand.uniform(round(temp_half)))

      :decorrelated_jitter ->
        # Requires tracking previous delay
        # sleep = min(cap, random(base, previous_delay * 3))
        raise "Requires stateful implementation"
    end
  end

  defp retryable?({:error, :timeout}), do: true
  defp retryable?({:error, :econnrefused}), do: true
  defp retryable?({:error, :closed}), do: true
  defp retryable?({:error, {:ssh_error, _}}), do: true
  defp retryable?(_), do: false
end
```

**Where Retries Apply:**
| Operation | Retries | Notes |
|-----------|---------|-------|
| SSH connection | 3 | Exponential backoff |
| SSH command execution | Configurable | Per-command setting |
| Cloud API calls | 5 | With rate limit awareness |
| Artifact transfers | 3 | Resume partial transfers |
| Health checks | Configurable | Per-task setting |

#### 23.2.2 Circuit Breaker Pattern

For cloud API calls and external services, Nexus implements circuit breakers to prevent cascade failures.

```elixir
# Using the fuse library
defmodule Nexus.CircuitBreaker do
  @moduledoc """
  Circuit breaker for external services using Erlang's fuse library.
  """

  @doc """
  Install a circuit breaker for a service.

  Options:
    - :tolerance - Number of failures before tripping (default: 5)
    - :window - Time window for failures in ms (default: 10_000)
    - :reset - Time before attempting reset in ms (default: 30_000)
  """
  def install(name, opts \\ []) do
    tolerance = Keyword.get(opts, :tolerance, 5)
    window = Keyword.get(opts, :window, 10_000)
    reset = Keyword.get(opts, :reset, 30_000)

    :fuse.install(name, {
      {:standard, tolerance, window},
      {:reset, reset}
    })
  end

  @doc """
  Run a function with circuit breaker protection.
  """
  def run(name, fun) do
    case :fuse.ask(name, :sync) do
      :ok ->
        try do
          result = fun.()
          {:ok, result}
        rescue
          e ->
            :fuse.melt(name)
            {:error, e}
        end

      :blown ->
        {:error, :circuit_open}

      {:error, :not_found} ->
        # Fuse not installed, run without protection
        {:ok, fun.()}
    end
  end
end

# Usage in cloud provider
defmodule Nexus.Cloud.AWS do
  def list_instances(opts) do
    CircuitBreaker.run(:aws_ec2, fn ->
      ExAws.EC2.describe_instances(opts)
      |> ExAws.request()
    end)
  end
end
```

**Circuit Breaker States:**
```
        ┌──────────────────────────────────────────────────┐
        │                                                   │
        ▼                                                   │
    ┌───────┐     failures >= threshold      ┌──────┐      │
    │ CLOSED│ ─────────────────────────────► │ OPEN │      │
    └───────┘                                └──┬───┘      │
        ▲                                       │          │
        │                                       │ timeout  │
        │                                       ▼          │
        │    success                      ┌──────────┐     │
        └──────────────────────────────── │HALF-OPEN │ ────┘
                                          └──────────┘
                                            failure
```

#### 23.2.3 Rate Limiting for Cloud APIs

```elixir
config :nexus, :rate_limits do
  # AWS EC2 API: 100 requests/second
  provider :aws, requests_per_second: 100

  # Hetzner API: 3600 requests/hour
  provider :hetzner, requests_per_hour: 3600

  # Azure: Varies by API, use conservative default
  provider :azure, requests_per_second: 10

  # Automatic backoff on 429 responses
  auto_backoff true

  # Honor Retry-After headers
  honor_retry_after true
end
```

**Implementation using Hammer:**

```elixir
defmodule Nexus.RateLimiter do
  @doc """
  Check and consume rate limit before making API call.
  """
  def check_and_proceed(provider, fun) do
    case Hammer.check_rate("cloud:#{provider}", 60_000, limit(provider)) do
      {:allow, _count} ->
        fun.()

      {:deny, retry_after} ->
        Process.sleep(retry_after)
        check_and_proceed(provider, fun)
    end
  end

  defp limit(:aws), do: 100 * 60  # 100/s * 60s
  defp limit(:hetzner), do: 60     # 3600/h / 60 = 60/min
  defp limit(:azure), do: 10 * 60  # 10/s * 60s
  defp limit(_), do: 30 * 60       # Conservative default
end
```

### 23.3 Graceful Shutdown & Signal Handling

#### 23.3.1 Signal Handling

```elixir
defmodule Nexus.SignalHandler do
  @moduledoc """
  Handles OS signals for graceful shutdown.
  Uses Erlang/OTP 20+ signal handling.
  """

  def setup do
    # SIGTERM: Graceful shutdown (Kubernetes, systemd)
    :os.set_signal(:sigterm, :handle)

    # SIGINT: Interactive interrupt (Ctrl+C)
    :os.set_signal(:sigint, :handle)

    # SIGHUP: Reload configuration
    :os.set_signal(:sighup, :handle)

    # SIGUSR1: Dump state for debugging
    :os.set_signal(:sigusr1, :handle)
  end

  def handle_signal(:sigterm) do
    Logger.info("Received SIGTERM, initiating graceful shutdown...")
    Nexus.Shutdown.graceful(timeout: 30_000)
  end

  def handle_signal(:sigint) do
    Logger.info("Received SIGINT, initiating graceful shutdown...")
    Nexus.Shutdown.graceful(timeout: 10_000)
  end

  def handle_signal(:sighup) do
    Logger.info("Received SIGHUP, reloading configuration...")
    Nexus.Config.reload()
  end

  def handle_signal(:sigusr1) do
    Logger.info("Received SIGUSR1, dumping state...")
    Nexus.Debug.dump_state()
  end
end
```

#### 23.3.2 Graceful Shutdown Procedure

```
Graceful Shutdown Sequence (30s default timeout):

┌─────────────────────────────────────────────────────────────┐
│ 1. STOP ACCEPTING NEW WORK (immediate)                      │
│    - Mark node as draining in cluster                       │
│    - Stop accepting new pipeline requests                   │
│    - Stop agent heartbeats                                   │
├─────────────────────────────────────────────────────────────┤
│ 2. COMPLETE IN-FLIGHT WORK (up to timeout)                  │
│    - Allow running commands to complete                     │
│    - Stream final output                                     │
│    - Save checkpoints for resumability                      │
├─────────────────────────────────────────────────────────────┤
│ 3. CLEANUP RESOURCES (5s)                                   │
│    - Close SSH connections gracefully                       │
│    - Flush telemetry/logs                                   │
│    - Release cloud instances (if ephemeral)                 │
├─────────────────────────────────────────────────────────────┤
│ 4. FINAL SHUTDOWN                                           │
│    - Call Application.stop/1                                │
│    - Exit with code 0 (success) or 1 (error)               │
└─────────────────────────────────────────────────────────────┘
```

```elixir
defmodule Nexus.Shutdown do
  use GenServer
  require Logger

  @default_timeout 30_000
  @cleanup_timeout 5_000

  def graceful(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    Logger.info("Starting graceful shutdown (timeout: #{timeout}ms)")

    # Phase 1: Stop accepting work
    Nexus.Cluster.mark_draining()
    Nexus.Agent.stop_heartbeat()

    # Phase 2: Wait for in-flight work
    case wait_for_completion(timeout - @cleanup_timeout) do
      :ok ->
        Logger.info("All tasks completed")
      :timeout ->
        Logger.warning("Shutdown timeout, some tasks may be incomplete")
        # Create checkpoints for resumability
        Nexus.Pipeline.checkpoint_all()
    end

    # Phase 3: Cleanup
    cleanup()

    # Phase 4: Stop application
    System.stop(0)
  end

  defp wait_for_completion(timeout) do
    # Wait for all running pipelines/tasks
    Nexus.Executor.Supervisor
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_, pid, _, _} -> Process.monitor(pid) end)
    |> wait_all_down(timeout)
  end

  defp cleanup do
    Logger.info("Cleaning up resources...")

    # Close SSH connections
    Nexus.SSH.Pool.close_all()

    # Flush telemetry
    :telemetry.execute([:nexus, :shutdown], %{}, %{})

    # Sync logs
    Logger.flush()

    Process.sleep(@cleanup_timeout)
  end
end
```

#### 23.3.3 Kubernetes Integration

```yaml
# kubernetes/deployment.yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      terminationGracePeriodSeconds: 60
      containers:
        - name: nexus-agent
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "nexus agent drain && sleep 5"]
          livenessProbe:
            httpGet:
              path: /health/live
              port: 9090
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 9090
            initialDelaySeconds: 5
            periodSeconds: 5
```

### 23.4 CLI Accessibility & Standards

#### 23.4.1 Environment Variables to Honor

| Variable | Purpose | Behavior |
|----------|---------|----------|
| `NO_COLOR` | Disable color output | Standard, always honor |
| `FORCE_COLOR` | Force color even if not TTY | Override NO_COLOR |
| `TERM=dumb` | Minimal terminal | No formatting |
| `CI` | Running in CI | Non-interactive mode |
| `NEXUS_NO_EMOJI` | Disable emojis | Plain ASCII only |
| `NEXUS_LOG_LEVEL` | Override log level | debug/info/warn/error |
| `NEXUS_CONFIG` | Config file path | Override default |
| `SSH_AUTH_SOCK` | SSH agent socket | Standard SSH |

```elixir
defmodule Nexus.Output do
  def supports_color? do
    cond do
      System.get_env("NO_COLOR") -> false
      System.get_env("FORCE_COLOR") -> true
      System.get_env("TERM") == "dumb" -> false
      System.get_env("CI") -> false
      true -> IO.ANSI.enabled?()
    end
  end

  def supports_emoji? do
    not System.get_env("NEXUS_NO_EMOJI") and
    not System.get_env("CI") and
    supports_unicode?()
  end

  def interactive? do
    not System.get_env("CI") and
    :io.columns() != {:error, :enotsup}
  end
end
```

#### 23.4.2 Accessibility Features

```elixir
config :nexus, :accessibility do
  # Disable animations (for screen readers)
  animations false

  # Use ASCII instead of Unicode box-drawing
  ascii_only true

  # High contrast mode
  high_contrast true

  # Machine-readable output
  format :json
end
```

**CLI Flags:**
```bash
# Accessibility mode
$ nexus run deploy --a11y

# Plain output (no colors, no emojis, no boxes)
$ nexus run deploy --plain

# JSON output for scripting
$ nexus run deploy --format json

# Static output (no progress updates, clear for screen readers)
$ nexus run deploy --static
```

#### 23.4.3 Error Message Standards

All error messages follow this structure:

```
Error: <Short description>

  <Location or context>
  <What happened>

Suggestions:
  - <Actionable fix 1>
  - <Actionable fix 2>

Documentation: https://docs.nexus.run/errors/<error-code>
```

Example:
```
Error: SSH connection refused

  Host: web-3.example.com:22
  User: deploy

Suggestions:
  - Check if SSH server is running: ssh deploy@web-3.example.com
  - Verify firewall allows port 22: nc -zv web-3.example.com 22
  - Check host is reachable: ping web-3.example.com

Documentation: https://docs.nexus.run/errors/SSH001
```

### 23.5 Idempotency Guidelines

#### 23.5.1 Task Idempotency Principles

Since Nexus supports retries and crash recovery, tasks should be designed for idempotency when possible.

**Idempotent Patterns:**
```elixir
# Good: Declarative state
task :ensure_directory do
  run "mkdir -p /opt/myapp"  # Idempotent
end

# Good: Conditional execution
task :create_user do
  run "id deploy || useradd deploy"  # Only if not exists
end

# Good: Atomic replace
task :update_config do
  # Write to temp, atomic move
  run "cat > /tmp/config.new && mv /tmp/config.new /etc/app/config"
end

# Good: Use service managers
task :ensure_running do
  run "systemctl start myapp || true"  # Already running is OK
end
```

**Non-Idempotent (Use with Care):**
```elixir
# Caution: Append operations
task :add_cron do
  # This will duplicate on retry!
  run "echo '0 * * * * /usr/bin/backup' >> /etc/crontab"
end

# Better: Use cron.d with unique file
task :add_cron do
  run "echo '0 * * * * /usr/bin/backup' > /etc/cron.d/myapp-backup"
end

# Caution: Increment operations
task :increment_counter do
  run "echo $(($(cat counter) + 1)) > counter"  # Not idempotent
end
```

#### 23.5.2 Idempotency Annotations (v0.2+)

```elixir
# Mark task as idempotent (safe to retry)
task :deploy, idempotent: true do
  run "systemctl restart myapp"
end

# Mark task as non-idempotent (warn on retry)
task :send_notification, idempotent: false do
  run "curl -X POST https://slack.com/webhook"
end

# On resume after crash, non-idempotent tasks prompt:
# "Task :send_notification may have side effects. Re-run? [y/N]"
```

### 23.6 Windows & Cross-Platform Support

#### 23.6.1 Platform Support Matrix

| Feature | Linux | macOS | Windows Native | WSL2 |
|---------|-------|-------|----------------|------|
| Core execution | ✅ | ✅ | v0.5+ | ✅ |
| SSH client | ✅ | ✅ | ✅ | ✅ |
| Agent mode | ✅ | ✅ | v0.5+ | ✅ |
| TUI | ✅ | ✅ | Limited | ✅ |
| File transfers | ✅ | ✅ | ✅ | ⚠️ Perf |
| Binary packaging | ✅ | ✅ | v0.5+ | N/A |

#### 23.6.2 Path Handling

```elixir
defmodule Nexus.Path do
  @doc """
  Normalize paths for cross-platform compatibility.
  """
  def normalize(path) do
    path
    |> Path.expand()
    |> String.replace("\\", "/")  # Normalize Windows paths
  end

  @doc """
  Get appropriate config directory per platform.
  Follows XDG Base Directory Specification on Linux.
  """
  def config_dir do
    case :os.type() do
      {:unix, :darwin} ->
        Path.join(System.get_env("HOME"), ".nexus")

      {:unix, _} ->
        xdg = System.get_env("XDG_CONFIG_HOME", Path.join(System.get_env("HOME"), ".config"))
        Path.join(xdg, "nexus")

      {:win32, _} ->
        Path.join(System.get_env("APPDATA"), "nexus")
    end
  end

  @doc """
  Get data directory (state, artifacts, etc).
  """
  def data_dir do
    case :os.type() do
      {:unix, _} ->
        xdg = System.get_env("XDG_DATA_HOME", Path.join(System.get_env("HOME"), ".local/share"))
        Path.join(xdg, "nexus")

      {:win32, _} ->
        Path.join(System.get_env("LOCALAPPDATA"), "nexus")
    end
  end
end
```

#### 23.6.3 WSL2 Considerations

```elixir
defmodule Nexus.Platform.WSL do
  @doc """
  Detect if running under WSL2.
  """
  def wsl? do
    case File.read("/proc/version") do
      {:ok, content} -> String.contains?(content, "microsoft")
      _ -> false
    end
  end

  @doc """
  WSL-specific recommendations.
  """
  def recommendations do
    if wsl?() do
      [
        "Store project files in WSL filesystem (~/...) not Windows (/mnt/c/...)",
        "Use 'wsl --shutdown' if experiencing network issues",
        "Consider Windows Terminal for better Unicode/emoji support"
      ]
    else
      []
    end
  end
end
```

### 23.7 Network Partition & Split-Brain Handling

#### 23.7.1 Detection Strategies

```elixir
defmodule Nexus.Cluster.PartitionDetector do
  @moduledoc """
  Detect and handle network partitions in distributed mode.
  """

  # Heartbeat interval
  @heartbeat_interval 5_000

  # Node considered down after N missed heartbeats
  @failure_threshold 3

  def handle_nodedown(node) do
    Logger.warning("Node #{node} appears down")

    # Check if we're in the minority partition
    if in_minority_partition?() do
      Logger.warning("In minority partition, pausing operations")
      Nexus.Cluster.pause_operations()
    else
      # Redistribute work from down node
      Nexus.Cluster.Scheduler.redistribute(node)
    end
  end

  defp in_minority_partition? do
    known_nodes = length(Node.list()) + 1
    original_cluster_size = Nexus.Cluster.original_size()
    known_nodes < original_cluster_size / 2
  end
end
```

#### 23.7.2 Partition Strategies

| Strategy | Behavior | Use When |
|----------|----------|----------|
| `pause_minority` | Minority partition stops accepting work | Default, safest |
| `continue_all` | All partitions continue | Stateless tasks only |
| `leader_only` | Only leader partition works | Strong consistency needed |

```elixir
config :nexus, :cluster do
  partition_strategy :pause_minority

  # How long to wait for partition to heal
  partition_timeout 60_000

  # Action if partition doesn't heal
  partition_timeout_action :shutdown  # or :continue_degraded
end
```

### 23.8 Container & Orchestration Support

#### 23.8.1 Docker Support

```dockerfile
# Dockerfile
FROM elixir:1.16-alpine AS builder

WORKDIR /app
COPY . .
RUN mix deps.get --only prod
RUN MIX_ENV=prod mix release

FROM alpine:3.19
RUN apk add --no-cache openssl ncurses-libs libstdc++

COPY --from=builder /app/_build/prod/rel/nexus /opt/nexus

ENV NEXUS_HOME=/opt/nexus
ENV PATH="${NEXUS_HOME}/bin:${PATH}"

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD nexus agent health || exit 1

ENTRYPOINT ["nexus"]
CMD ["agent", "start", "--foreground"]
```

#### 23.8.2 Health Check Endpoints

```elixir
defmodule Nexus.Health do
  @moduledoc """
  Health check endpoints for orchestration platforms.
  """

  # GET /health/live - Is the process running?
  def live do
    %{status: :ok, timestamp: DateTime.utc_now()}
  end

  # GET /health/ready - Is the agent ready to accept work?
  def ready do
    checks = [
      {:ssh_pool, Nexus.SSH.Pool.healthy?()},
      {:cluster, Nexus.Cluster.connected?()},
      {:config, Nexus.Config.valid?()}
    ]

    status = if Enum.all?(checks, fn {_, v} -> v end), do: :ok, else: :degraded

    %{
      status: status,
      checks: Map.new(checks),
      timestamp: DateTime.utc_now()
    }
  end

  # GET /health/startup - Has initial setup completed?
  def startup do
    %{
      status: if(Nexus.Agent.initialized?(), do: :ok, else: :starting),
      timestamp: DateTime.utc_now()
    }
  end
end
```

### 23.9 Resource Limits & Tuning

#### 23.9.1 File Descriptor Limits

```elixir
defmodule Nexus.Limits do
  @doc """
  Check and warn about file descriptor limits.
  Each SSH connection uses ~3 file descriptors.
  """
  def check_fd_limit do
    case :os.type() do
      {:unix, _} ->
        {output, 0} = System.cmd("ulimit", ["-n"])
        limit = String.trim(output) |> String.to_integer()

        # Recommend: 4 * max_concurrent_connections + buffer
        recommended = 4 * Nexus.Config.get(:parallel_limit, 10) * 4 + 100

        if limit < recommended do
          Logger.warning("""
          File descriptor limit (#{limit}) may be too low.
          Recommended: #{recommended}
          Increase with: ulimit -n #{recommended}
          """)
        end

      _ -> :ok
    end
  end
end
```

#### 23.9.2 Memory Tuning

```elixir
# vm.args for releases
+P 1000000          # Max processes (default 262144)
+Q 65536            # Max ports/FDs (default 65536)
+S 4:4              # Schedulers (match CPU cores)
+sbwt very_short    # Scheduler busy wait (low latency)
+swt very_low       # Scheduler wakeup threshold

# For agents handling many connections
+hms 33554432       # Heap size 32MB (default varies)
+hmbs 46422016      # Binary heap size 44MB
```

### 23.10 Additional Dependencies for v0.1

Based on operational requirements, add these dependencies:

```elixir
# Additional deps for operational excellence
defp deps do
  [
    # Existing deps...

    # Circuit breaker
    {:fuse, "~> 2.5"},

    # Rate limiting
    {:hammer, "~> 6.2"},

    # Graceful shutdown hooks (optional, OTP 20+ has built-in)
    # {:graceful_stop, "~> 0.1"},

    # SSH config parser (may need custom implementation)
    # No existing library - implement custom parser
  ]
end
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-12-27 | Initial Design | Initial PRD |
| 1.1 | 2025-12-28 | Library Research | Comprehensive library research added. Updated all dependency sections with validated libraries. Added Section 22 (Library Research & Recommendations). Identified critical risks: SSHEx archived, Bakeware archived, Azure SDK gap, Kerberos gap. |
| 1.2 | 2025-12-28 | Architecture Deep-Dive | Added Section 11 (State Management & Crash Recovery): pipeline state model, DETS persistence, crash recovery algorithm, checkpoint strategy, resume command, artifact lifecycle. Added Section 12 (Agent Communication Protocol): Erlang distribution with TLS, 3-layer authentication (mTLS, cookie, JWT), NAT traversal strategies (Tailscale preferred, relay fallback). Added Section 13 (Secrets & Key Management): Argon2id key derivation, AES-256-GCM encryption, per-secret DEKs, rotation procedures, team sharing strategies (keyfile, Vault, SOPS). Added Section 16 (Testing Strategy): SSH testing with Docker containers, Mox behaviors, property-based testing with StreamData, performance benchmarks, load testing scenarios, CI/CD pipeline. Added Section 17 (Documentation Plan): 4-tier documentation structure, video tutorial series, cookbook examples, ExDoc integration. Added Section 18 (Release & Upgrade Strategy): semantic versioning, agent upgrade procedures, breaking change policy, config migration commands. Added Section 19 (Telemetry & Observability): OpenTelemetry integration, Prometheus metrics, Grafana dashboards, alerting rules. Renumbered sections 14-22 for consistency. |
| 1.3 | 2025-12-28 | Operational Excellence | Added Section 23 (Operational Excellence) covering production hardening requirements identified during final review. SSH Advanced Configuration: ~/.ssh/config parsing, Jump Host/Bastion support (v0.2+), known_hosts management policies. Resilience Patterns: exponential backoff with jitter (Full/Equal/Decorrelated), circuit breaker pattern using fuse library, rate limiting for cloud APIs with Hammer. Graceful Shutdown: SIGTERM/SIGINT/SIGHUP handling, 4-phase shutdown procedure, Kubernetes integration with health probes. CLI Accessibility: NO_COLOR/TERM=dumb support, screen reader considerations, structured error messages with documentation links. Idempotency Guidelines: idempotent vs non-idempotent task patterns, idempotency annotations (v0.2+). Cross-Platform: Windows/WSL2 support matrix, XDG-compliant path handling, WSL2-specific recommendations. Network Partition Handling: split-brain detection, partition strategies (pause_minority default). Container Support: Dockerfile, health check endpoints (live/ready/startup). Resource Limits: file descriptor checking, VM tuning parameters. Added fuse and hammer to dependency list. |

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Product Owner | | | |
| Tech Lead | | | |
| Engineering | | | |
