# QA: Test permission denied scenarios
host :decaflab, "decafcoffee@100.112.64.66"

task :test_permission_denied, on: :decaflab do
  # Try to write to a root-owned directory without sudo
  file "/etc/nexus_test_should_fail.txt",
    state: :present,
    content: "this should fail"
end

task :test_sudo_file, on: :decaflab do
  # Same but with sudo
  file "/tmp/nexus_sudo_test.txt",
    state: :present,
    content: "created with sudo",
    sudo: true

  command "cat /tmp/nexus_sudo_test.txt", sudo: true

  file "/tmp/nexus_sudo_test.txt", state: :absent, sudo: true
end
