# QA: Test empty task
host :local, "localhost"

task :empty_task, on: :local do
  # No commands
end
