# Nexus Configuration
# ===================
#
# This file defines tasks, hosts, and groups for Nexus.
# Run `nexus validate` to check this configuration.
# Run `nexus list` to see all defined tasks.
# Run `nexus run <task>` to execute a task.

# Hosts
# -----
# Define remote hosts for task execution.
# Hosts can be referenced by name in tasks.

# Example: Simple host definition
# host :web1, "web1.example.com"

# Example: Host with user
# host :web2, "deploy@web2.example.com"

# Example: Host with user and port
# host :web3, "deploy@web3.example.com:2222"

# Groups
# ------
# Group hosts together for parallel execution.

# Example: Web server group
# group :web, [:web1, :web2, :web3]

# Tasks
# -----
# Define tasks with commands to execute.

# Local task with no dependencies
task :build do
command "echo 'Building project...'"
end

# Task with dependencies
task :test, deps: [:build] do
command "echo 'Running tests...'"
end

# Example: Task running on a specific host
# task :deploy, deps: [:test], on: :web1 do
#   run "cd /app && git pull"
#   run "mix deps.get --only prod"
# end

# Example: Task running on a group of hosts (parallel)
# task :restart, deps: [:deploy], on: :web, strategy: :parallel do
#   run "sudo systemctl restart myapp"
# end
