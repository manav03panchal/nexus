# Docker SSH Test Configuration
# 5 SSH containers on ports 2221-2225

host :ssh1, "testuser@localhost:2221"
host :ssh2, "testuser@localhost:2226"
host :ssh3, "testuser@localhost:2223"
host :ssh4, "testuser@localhost:2224"
host :ssh5, "testuser@localhost:2225"

group :all_hosts, [:ssh1, :ssh2, :ssh3, :ssh4, :ssh5]
group :first_three, [:ssh1, :ssh2, :ssh3]

# Single host task
task :check_host, on: :ssh1 do
  run "hostname"
  run "whoami"
  run "uname -a"
end

# Run on all hosts
task :all_hostnames, on: :all_hosts do
  run "hostname"
end

# Run on group
task :group_info, on: :first_three do
  run "echo 'Host:' && hostname"
  run "echo 'User:' && whoami"
end

# Chain across hosts
task :step1_remote, on: :ssh1 do
  run "echo 'Step 1 on ssh1'"
end

task :step2_remote, on: :ssh2, deps: [:step1_remote] do
  run "echo 'Step 2 on ssh2'"
end

task :step3_remote, on: :ssh3, deps: [:step2_remote] do
  run "echo 'Step 3 on ssh3'"
end

# Parallel on all hosts
task :parallel_all, on: :all_hosts do
  run "echo 'Starting on' $(hostname)"
  run "sleep 1"
  run "echo 'Done on' $(hostname)"
end

# Local task
task :local_prep do
  run "echo 'Preparing locally...'"
end

# Mixed local + remote
task :deploy_sim, deps: [:local_prep], on: :all_hosts do
  run "echo 'Deploying to' $(hostname)"
end

# Failure test
task :will_fail_remote, on: :ssh1 do
  run "echo 'About to fail'"
  run "exit 1"
end
