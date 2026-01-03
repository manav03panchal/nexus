# Nexus v0.2 Example - Localhost Demo
#
# This example runs commands on your local machine via SSH loopback.
# No remote server required!
#
# Prerequisites:
#   1. Enable "Remote Login" in System Preferences > Sharing
#   2. Add your SSH key to ~/.ssh/authorized_keys

config :nexus,
  default_user: System.get_env("USER"),  # Uses your current username
  connect_timeout: 10_000

# Connect to localhost
host :local, "127.0.0.1"

# Basic status check
task :status, on: :local do
  run "hostname"
  run "uptime"
  run "whoami"
end

# File operations demo
task :file_demo, on: :local do
  # Upload a file
  upload "examples/hello.txt", "/tmp/nexus_hello.txt"
  run "cat /tmp/nexus_hello.txt"

  # Download it back
  download "/tmp/nexus_hello.txt", "/tmp/nexus_downloaded.txt"
  run "diff examples/hello.txt /tmp/nexus_downloaded.txt && echo 'Files match!'"
end

# Template rendering demo
task :template_demo, on: :local do
  template "examples/config.env.eex", "/tmp/nexus_config.env",
    vars: %{
      app_name: "demo_app",
      port: 3000,
      environment: "development"
    }

  run "echo '--- Generated config ---'"
  run "cat /tmp/nexus_config.env"
end

# Health check demo
task :health_demo, on: :local do
  # Check SSH port is open
  wait_for :tcp, "localhost:22", timeout: 5_000
  run "echo 'SSH port is open!'"

  # Check a command succeeds
  wait_for :command, "test -f /etc/hosts", timeout: 5_000
  run "echo '/etc/hosts exists!'"
end

# Handler demo
handler :cleanup do
  run "rm -f /tmp/nexus_*.txt /tmp/nexus_*.env"
  run "echo 'Cleanup complete!'"
end

task :full_demo, on: :local do
  run "echo '=== Nexus v0.2 Full Demo ==='"

  # Upload
  upload "examples/hello.txt", "/tmp/nexus_demo.txt"
  run "cat /tmp/nexus_demo.txt"

  # Template
  template "examples/config.env.eex", "/tmp/nexus_demo.env",
    vars: %{app_name: "nexus_demo", port: 4000, environment: "demo"}
  run "cat /tmp/nexus_demo.env"

  # This triggers the cleanup handler
  upload "examples/hello.txt", "/tmp/nexus_final.txt", notify: :cleanup
end


# === Rolling Deployment Demo ===
#
# To demo rolling deployment, you'd define multiple hosts:
#
# host :web1, "server1.example.com"
# host :web2, "server2.example.com"
# host :web3, "server3.example.com"
# group :web, [:web1, :web2, :web3]
#
# task :rolling_deploy, on: :web, strategy: :rolling, batch_size: 1 do
#   run "systemctl restart myapp", sudo: true
#   wait_for :http, "http://localhost:4000/health", timeout: 30_000
# end
