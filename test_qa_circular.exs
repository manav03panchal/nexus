# QA: Test circular dependency detection
host :local, "localhost"

task :task_a, on: :local, deps: [:task_b] do
  command "echo a"
end

task :task_b, on: :local, deps: [:task_c] do
  command "echo b"
end

task :task_c, on: :local, deps: [:task_a] do
  command "echo c"
end
