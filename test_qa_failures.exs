# QA: Test command failures and error handling
host :decaflab, "decafcoffee@100.112.64.66"
host :unreachable, "user@192.0.2.1"  # TEST-NET, should be unreachable

task :test_cmd_failure, on: :decaflab do
  command "echo 'before failure'"
  command "exit 1"  # This should fail
  command "echo 'after failure - should not run'"
end

task :test_cmd_failure_continue, on: :decaflab do
  command "echo 'before failure'"
  command "exit 1"  # This should fail but continue
  command "echo 'after failure - should run with continue_on_error'"
end

task :test_unreachable_host, on: :unreachable do
  command "echo 'this should never run'"
end
