# QA: Test dry-run/check mode
host :decaflab, "decafcoffee@100.112.64.66"

task :test_dryrun, on: :decaflab do
  # Create a file that we'll verify doesn't actually get created
  file "/tmp/nexus_dryrun_test.txt",
    state: :present,
    content: "This should NOT be created in check mode"

  command "echo 'This command should show but not execute'"

  package "htop", state: :present
end
