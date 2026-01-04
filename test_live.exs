host :decaflab, "decafcoffee@100.112.64.66"

# Test Tailscale discovery - discover hosts with user decafcoffee
# tailscale_hosts tag: "linux", as: :ts_linux, user: "decafcoffee"

# ======================
# Phase 7: Handlers (PASSED)
# ======================
handler :restart_service do
  run "echo 'Handler: Restarting service...'"
end

handler :notify_complete do
  run "echo 'Handler: Deployment complete notification'"
end

task :test_handlers, on: :decaflab do
  command "echo 'Updating config...'", notify: :restart_service
  command "echo 'Deploy finished'", notify: :notify_complete
end

# ======================
# Phase 8: Upload
# ======================
task :test_upload, on: :decaflab do
  # First create a local test file
  command "echo 'test content from nexus' > /tmp/nexus_upload_test.txt", sudo: false
  upload "/tmp/nexus_upload_test.txt", "/tmp/nexus_uploaded.txt"
  command "cat /tmp/nexus_uploaded.txt"
  command "rm /tmp/nexus_uploaded.txt"
end

# ======================
# Phase 9: Download
# ======================
task :test_download, on: :decaflab do
  # Create a file on remote, then download it
  command "echo 'remote content' > /tmp/nexus_remote_file.txt"
  download "/tmp/nexus_remote_file.txt", "/tmp/nexus_downloaded.txt"
  command "rm /tmp/nexus_remote_file.txt"
end

# ======================
# Phase 10: Template
# ======================
task :test_template, on: :decaflab do
  template "test_template.eex", "/tmp/nexus_rendered.txt",
    vars: %{app_name: "MyApp", version: "1.0.0", port: 8080}
  command "cat /tmp/nexus_rendered.txt"
  command "rm /tmp/nexus_rendered.txt"
end

# ======================
# Phase 11: Wait For
# ======================
# Test wait_for tcp (SSH should be listening on 22)
task :test_wait_for_tcp, on: :decaflab do
  wait_for :tcp, "localhost:22", timeout: 5_000
  command "echo 'Port 22 is open!'"
end

# Test wait_for command
task :test_wait_for_cmd, on: :decaflab do
  command "touch /tmp/nexus_wait_test.txt"
  wait_for :command, "test -f /tmp/nexus_wait_test.txt", timeout: 5_000
  command "rm /tmp/nexus_wait_test.txt"
end

# ======================
# Phase 12: Idempotency guards
# ======================
task :test_idempotency, on: :decaflab do
  # creates: should skip if file exists
  command "echo 'creating marker'", creates: "/tmp/nexus_marker.txt"
  command "touch /tmp/nexus_marker.txt"
  command "echo 'this should be skipped'", creates: "/tmp/nexus_marker.txt"

  # unless: should skip if command succeeds
  command "echo 'this runs because test fails'", unless: "test -f /tmp/nonexistent"
  command "echo 'this skipped because test succeeds'", unless: "test -f /tmp/nexus_marker.txt"

  # onlyif: should run only if command succeeds
  command "echo 'this runs because marker exists'", onlyif: "test -f /tmp/nexus_marker.txt"
  command "echo 'this skipped because no such file'", onlyif: "test -f /tmp/nonexistent"

  # cleanup
  command "rm -f /tmp/nexus_marker.txt"
end

# ======================
# Phase 13: Resources - Directory
# ======================
task :test_directory, on: :decaflab do
  directory "/tmp/nexus_test_dir", state: :present
  command "test -d /tmp/nexus_test_dir && echo 'Directory created!'"
  directory "/tmp/nexus_test_dir", state: :absent
end

# ======================
# Phase 14: Resources - File
# ======================
task :test_file_resource, on: :decaflab do
  file "/tmp/nexus_test_file.txt", state: :present, content: "Hello from Nexus!"
  command "cat /tmp/nexus_test_file.txt"
  file "/tmp/nexus_test_file.txt", state: :absent
end

# ======================
# Phase 15: Resources - Package (requires sudo)
# ======================
task :test_package, on: :decaflab do
  # Install a small package, then remove it
  package "cowsay", state: :present
  command "which cowsay"
  package "cowsay", state: :absent
end

# ======================
# Phase 16: Resources - Service
# ======================
task :test_service, on: :decaflab do
  # Check status of ssh service
  service "ssh", state: :running
  command "systemctl is-active ssh"
end

# ======================
# Phase 17: Facts gathering
# ======================
task :test_facts, on: :decaflab do
  command "echo 'OS: ' && uname -s"
  command "echo 'Hostname: ' && hostname"
  command "echo 'User: ' && whoami"
  command "echo 'Arch: ' && uname -m"
  command "echo 'CPU count: ' && nproc"
  command "cat /etc/os-release | grep -E '^(ID|VERSION_ID)='"
end

# ======================
# All phases combined
# ======================
task :test_all, on: :decaflab, deps: [:test_idempotency, :test_wait_for_tcp] do
  command "echo 'All tests passed!'"
end
