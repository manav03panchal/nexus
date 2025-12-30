# Live Chaos Testing Configuration
# Run with: ./nexus run <task> -c test_live.exs

# =============================================================================
# HOSTS - Docker SSH containers
# =============================================================================

# Key-based auth (preferred)
host :key_server, "testuser@127.0.0.1:2233"

# Password-based servers (ssh1-ssh5)
host :server1, "testuser@127.0.0.1:2221"
host :server2, "testuser@127.0.0.1:2226"
host :server3, "testuser@127.0.0.1:2223"
host :server4, "testuser@127.0.0.1:2224"
host :server5, "testuser@127.0.0.1:2225"

# =============================================================================
# GROUPS
# =============================================================================

group :web, [:server1, :server2, :server3]
group :db, [:server4, :server5]
group :all, [:server1, :server2, :server3, :server4, :server5]

# =============================================================================
# BASIC TESTS
# =============================================================================

# Simple local task
task :hello do
  run "echo 'Hello from Nexus!'"
end

# Remote task on single host (key auth)
task :remote_hello, on: :key_server do
  run "echo 'Hello from remote!'"
  run "hostname"
  run "whoami"
end

# =============================================================================
# PARALLEL EXECUTION TESTS
# =============================================================================

# Run on all web servers in parallel (default)
task :parallel_test, on: :web do
  run "echo 'Starting on' $(hostname)"
  run "sleep 1"
  run "echo 'Done on' $(hostname)"
end

# Run on all servers serially
task :serial_test, on: :all, strategy: :serial do
  run "echo 'Serial run on' $(hostname)"
  run "sleep 0.5"
end

# =============================================================================
# RETRY TESTS
# =============================================================================

# Command that fails and retries
task :retry_test do
  run "exit 1", retries: 3, retry_delay: 500
end

# Flaky command (fails sometimes) - simulated
task :flaky_test do
  # This will fail ~50% of the time
  run "test $(shuf -i 0-1 -n 1) -eq 1", retries: 5, retry_delay: 200
end

# Remote retry
task :remote_retry, on: :key_server do
  run "exit 1", retries: 2, retry_delay: 1000
end

# =============================================================================
# TIMEOUT TESTS
# =============================================================================

# Command that times out
task :timeout_test do
  run "sleep 10", timeout: 2000
end

# Remote timeout
task :remote_timeout, on: :key_server do
  run "sleep 5", timeout: 2000
end

# =============================================================================
# DEPENDENCY CHAIN TESTS
# =============================================================================

task :step1 do
  run "echo 'Step 1: Initialize'"
end

task :step2, deps: [:step1] do
  run "echo 'Step 2: Build'"
end

task :step3, deps: [:step2] do
  run "echo 'Step 3: Test'"
end

task :step4, deps: [:step3] do
  run "echo 'Step 4: Deploy'"
end

# Run the full chain
task :full_chain, deps: [:step4] do
  run "echo 'All steps complete!'"
end

# =============================================================================
# FAILURE HANDLING TESTS
# =============================================================================

# Fails on step 2
task :fail_step1 do
  run "echo 'This works'"
end

task :fail_step2, deps: [:fail_step1] do
  run "echo 'About to fail...'"
  run "exit 1"
end

task :fail_step3, deps: [:fail_step2] do
  run "echo 'This should not run'"
end

# Continue on error test
task :continue_test do
  run "echo 'First command'"
  run "exit 1"
  run "echo 'This runs anyway with --continue-on-error'"
end

# =============================================================================
# MULTI-HOST FAILURE TESTS
# =============================================================================

# One host fails, others succeed
task :partial_failure, on: :web do
  # server1 will fail, others succeed
  run "test $(hostname) != 'ssh1' && echo 'Success on' $(hostname) || exit 1"
end

# =============================================================================
# STRESS TESTS
# =============================================================================

# Many commands on one host
task :stress_single, on: :key_server do
  run "echo 'Command 1'"
  run "echo 'Command 2'"
  run "echo 'Command 3'"
  run "echo 'Command 4'"
  run "echo 'Command 5'"
  run "echo 'Command 6'"
  run "echo 'Command 7'"
  run "echo 'Command 8'"
  run "echo 'Command 9'"
  run "echo 'Command 10'"
end

# Many hosts, few commands
task :stress_multi, on: :all do
  run "echo 'Hello from' $(hostname)"
  run "uptime"
end

# =============================================================================
# REAL-WORLD SIMULATION
# =============================================================================

task :deploy_check do
  run "echo 'Checking deployment prerequisites...'"
  run "which git || echo 'git not found'"
end

task :deploy_pull, deps: [:deploy_check], on: :web do
  run "echo 'Would run: git pull origin main'"
  run "echo 'Simulating pull on' $(hostname)"
  run "sleep 1"
end

task :deploy_restart, deps: [:deploy_pull], on: :web do
  run "echo 'Would run: systemctl restart app'"
  run "echo 'Simulating restart on' $(hostname)"
end

task :deploy, deps: [:deploy_restart] do
  run "echo 'Deployment complete!'"
end
