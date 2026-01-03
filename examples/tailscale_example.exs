# Nexus v0.2 Example - Using Tailscale
#
# Your Tailscale network:
#   - manavs-macbook-pro (this machine)
#   - decaflab (linux server)
#   - iphone171 (iOS)

config :nexus,
  default_user: "decafcoffee",
  connect_timeout: 30_000

# Option 1: Define host manually using Tailscale DNS name
host :decaflab, "decaflab.tailc4b71d.ts.net"

# Option 2: Or use the Tailscale IP directly
# host :decaflab, "100.112.64.66"

# Option 3: If you add tags in Tailscale Admin Console, use auto-discovery:
# tailscale_hosts tag: "server", as: :servers

# Simple task - check what's running on decaflab
task :status, on: :decaflab do
  run "hostname"
  run "uptime"
  run "df -h /"
end

# Check Docker status (if installed)
task :docker_status, on: :decaflab do
  run "docker ps", sudo: true
end

# Deploy a simple app
task :deploy_app, on: :decaflab do
  # Upload a file
  upload "examples/hello.txt", "/tmp/hello.txt"

  # Run a command
  run "cat /tmp/hello.txt"
end

# Template example - create a config file
task :configure, on: :decaflab do
  template "examples/config.env.eex", "/tmp/myapp.env",
    vars: %{
      app_name: "myapp",
      port: 8080,
      environment: "production"
    }

  run "cat /tmp/myapp.env"
end

# Health check example
task :check_ssh, on: :decaflab do
  wait_for :tcp, "localhost:22", timeout: 5_000
  run "echo 'SSH is running!'"
end

# Handler example
handler :notify_complete do
  run "echo 'Deployment complete at $(date)'"
end

task :full_deploy, on: :decaflab do
  run "echo 'Starting deployment...'"
  upload "examples/hello.txt", "/tmp/deployed.txt", notify: :notify_complete
end
