# QA: Test invalid config - missing host reference
host :web1, "user@host.com"

task :broken_task, on: :nonexistent_host do
  command "echo test"
end
