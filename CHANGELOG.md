# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-01-01

### Added

- **Secrets Management**
  - AES-256-GCM encrypted secret storage in `~/.nexus/secrets.enc`
  - PBKDF2 key derivation with 100k iterations
  - Master key sources: environment variable, key file, or interactive prompt
  - CLI commands: `nexus secret set`, `get`, `list`, `delete`, `init`
  - DSL function: `secret("name")` for secure credential access in tasks

- **File Transfer (SFTP)**
  - Built-in SFTP support using Erlang's `:ssh_sftp` module
  - `upload` macro for local-to-remote file transfers
  - `download` macro for remote-to-local file transfers
  - Options: `sudo`, `mode` (permissions), `notify` (trigger handlers)

- **EEx Templates**
  - Template rendering with variable substitution
  - `template` macro for rendering and uploading configuration files
  - Variables available as `@var_name` in templates
  - Options: `vars`, `sudo`, `mode`, `notify`

- **Deployment Strategies**
  - Rolling deployment with `strategy: :rolling` and `batch_size` options
  - Health checks with `wait_for` macro
  - HTTP health checks (status code, body pattern matching)
  - TCP port connectivity checks
  - Command-based health checks (exit code 0)
  - Configurable timeout and retry intervals

- **Handlers**
  - Notification-based command execution with `handler` macro
  - Trigger handlers via `notify:` option on upload, download, template
  - Ideal for service restarts after configuration changes

- **Tailscale Host Discovery**
  - Auto-discover hosts from Tailscale network
  - `tailscale_hosts` macro with tag filtering
  - Options: `tag`, `as` (group name), `user`, `online_only`
  - Queries local Tailscale daemon via `tailscale status --json`

### Dependencies

- Added `{:req, "~> 0.5"}` for HTTP health checks

### Technical Details

- 490 unit tests (up from 394)
- 31 property-based tests (up from 21)
- All existing v0.1 configurations remain compatible

## [0.1.0] - 2024-12-28

### Added

- **DSL Configuration**
  - Elixir-based DSL for defining hosts, groups, and tasks
  - `host` macro for defining remote hosts with user@host:port syntax
  - `group` macro for organizing hosts into logical groups
  - `task` macro with dependency support and command blocks
  - `config` macro for global settings
  - `env()` function for environment variable access

- **DAG-based Dependency Resolution**
  - Automatic topological sorting of tasks
  - Cycle detection with clear error messages
  - Execution phase calculation for parallel execution
  - Support for complex dependency graphs

- **Local Execution**
  - Execute commands on the local machine
  - Real-time streaming output
  - Timeout enforcement
  - Environment variable passthrough

- **SSH Remote Execution**
  - Connection pooling with NimblePool
  - Support for key-based and password authentication
  - SSH agent integration
  - ~/.ssh/config parsing
  - Automatic connection reuse and cleanup

- **Pipeline Execution**
  - Parallel execution of independent tasks
  - Serial execution within task phases
  - Retry logic with exponential backoff and jitter
  - Continue-on-error mode
  - Configurable parallel limits

- **CLI Interface**
  - `nexus run` - Execute tasks
  - `nexus list` - List available tasks
  - `nexus validate` - Validate configuration
  - `nexus init` - Create template configuration
  - `nexus preflight` - Pre-flight checks
  - Support for `--dry-run`, `--verbose`, `--quiet` flags
  - JSON output format option

- **Pre-flight Checks**
  - Configuration validation
  - Host reachability (TCP ping)
  - SSH authentication verification
  - Sudo availability detection
  - Execution plan preview

- **Output & Telemetry**
  - Colored terminal output with NO_COLOR support
  - Multiple verbosity levels
  - Telemetry events for monitoring
  - Structured JSON output option

- **Quality & Testing**
  - 394 unit tests
  - 21 property-based tests
  - 80%+ code coverage
  - Dialyzer type checking
  - Credo strict mode compliance
  - Sobelow security scanning

### Technical Details

- Built with Elixir 1.15+
- Uses libgraph for DAG operations
- NimblePool for SSH connection pooling
- Optimus for CLI argument parsing
- Telemetry for observability
- Cross-platform binary support via Burrito
