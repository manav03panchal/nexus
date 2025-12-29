# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
