# Test all idempotency guards

host :decaflab, "decafcoffee@100.112.64.66"

task :test_unless, on: :decaflab do
  # unless: skip if check command succeeds (exit 0)
  command "echo 'Installing nginx (simulated)'",
    unless: "which nginx"
  
  command "echo 'Unless test done'"
end

task :test_onlyif, on: :decaflab do
  # onlyif: only run if check command succeeds
  command "echo 'Restarting service that exists'",
    onlyif: "which bash"
  
  command "echo 'This should skip - no such service'",
    onlyif: "which nonexistent_binary_12345"
  
  command "echo 'Onlyif test done'"
end

task :test_removes, on: :decaflab do
  # removes: skip if path doesn't exist
  command "rm -f /tmp/nexus_to_remove"
  
  command "echo 'Removing file that does not exist - should skip'",
    removes: "/tmp/nexus_to_remove"
  
  # Create it
  command "touch /tmp/nexus_to_remove"
  
  # Now it exists, should run
  command "echo 'Removing file that exists - should run' && rm /tmp/nexus_to_remove",
    removes: "/tmp/nexus_to_remove"
  
  command "echo 'Removes test done'"
end

task :all_guards, deps: [:test_unless, :test_onlyif, :test_removes] do
  command "echo 'All guard tests complete!'"
end
