# Test package resource
host :decaflab, "decafcoffee@100.112.64.66"

task :test_package, on: :decaflab do
  # Install cowsay (small package for testing)
  package "cowsay", state: :present

  # Verify it's installed
  command "cowsay 'Hello from Nexus!'"

  # Remove it
  package "cowsay", state: :absent

  # Verify removal
  command "which cowsay || echo 'cowsay removed'"
end
