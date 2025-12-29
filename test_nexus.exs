# Nexus Test Configuration
# Tests various features: local tasks, dependencies, groups, strategies

# =============================================================================
# HOSTS (use localhost for testing without real remotes)
# =============================================================================

host :local1, "localhost"
host :local2, "localhost"
host :fake_remote, "user@192.168.1.100"

# =============================================================================
# GROUPS
# =============================================================================

group :local_hosts, [:local1, :local2]

# =============================================================================
# CONFIGURATION
# =============================================================================

config :nexus,
  command_timeout: 30_000,
  max_connections: 5

# =============================================================================
# LOCAL TASKS - Basic
# =============================================================================

# Simple echo
task :hello do
  run "echo 'Hello from Nexus!'"
end

# Multiple commands
task :info do
  run "echo 'System info:'"
  run "uname -a"
  run "pwd"
  run "date"
end

# Task that takes time
task :slow do
  run "echo 'Starting slow task...'"
  run "sleep 2"
  run "echo 'Slow task complete!'"
end

# Task that fails
task :fail do
  run "echo 'About to fail...'"
  run "exit 1"
  run "echo 'This should not print'"
end

# Task with exit code
task :check_exit do
  run "test -f mix.exs && echo 'mix.exs exists' || echo 'mix.exs not found'"
end

# =============================================================================
# DEPENDENCY CHAIN
# =============================================================================

task :step1 do
  run "echo 'Step 1: Initialize'"
end

task :step2, deps: [:step1] do
  run "echo 'Step 2: Process'"
end

task :step3, deps: [:step2] do
  run "echo 'Step 3: Finalize'"
end

# Diamond dependency
#       start
#      /     \
#   left     right
#      \     /
#       finish

task :start do
  run "echo 'START'"
end

task :left, deps: [:start] do
  run "echo 'LEFT branch'"
end

task :right, deps: [:start] do
  run "echo 'RIGHT branch'"
end

task :finish, deps: [:left, :right] do
  run "echo 'FINISH - both branches complete'"
end

# =============================================================================
# PARALLEL EXECUTION
# =============================================================================

task :parallel_a do
  run "echo 'Parallel A starting' && sleep 1 && echo 'Parallel A done'"
end

task :parallel_b do
  run "echo 'Parallel B starting' && sleep 1 && echo 'Parallel B done'"
end

task :parallel_c do
  run "echo 'Parallel C starting' && sleep 1 && echo 'Parallel C done'"
end

# Run all parallel tasks
task :all_parallel, deps: [:parallel_a, :parallel_b, :parallel_c] do
  run "echo 'All parallel tasks completed'"
end

# =============================================================================
# FAILURE SCENARIOS
# =============================================================================

task :before_fail do
  run "echo 'This runs before failure'"
end

task :will_fail, deps: [:before_fail] do
  run "echo 'About to fail'"
  run "false"
end

task :after_fail, deps: [:will_fail] do
  run "echo 'This should NOT run (unless --continue-on-error)'"
end

# =============================================================================
# REMOTE TASKS (will fail without real SSH - for preflight testing)
# =============================================================================

task :remote_check, on: :fake_remote do
  run "hostname"
  run "whoami"
end

task :group_check, on: :local_hosts do
  run "echo 'Running on host'"
end

# =============================================================================
# REAL-WORLD SIMULATION
# =============================================================================

task :clean do
  run "echo 'Cleaning build artifacts...'"
  run "rm -rf _build/prod 2>/dev/null || true"
end

task :deps, deps: [:clean] do
  run "echo 'Fetching dependencies...'"
  run "mix deps.get --only prod 2>/dev/null || echo 'deps simulated'"
end

task :compile, deps: [:deps] do
  run "echo 'Compiling...'"
  run "mix compile 2>/dev/null || echo 'compile simulated'"
end

task :test_suite, deps: [:compile] do
  run "echo 'Running tests...'"
  run "echo 'All tests passed!'"
end

task :build, deps: [:test_suite] do
  run "echo 'Building release...'"
  run "echo 'Build complete!'"
end

task :deploy, deps: [:build] do
  run "echo 'Deploying...'"
  run "echo 'Deployment complete!'"
end
