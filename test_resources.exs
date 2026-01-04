# Test resources feature
host :decaflab, "decafcoffee@100.112.64.66"

task :test_resources, on: :decaflab do
  # Test directory resource - create a directory
  directory "/tmp/nexus_test_dir",
    state: :present,
    mode: 0o755

  # Test file resource - create a file with content
  file "/tmp/nexus_test_dir/hello.txt",
    state: :present,
    content: "Hello from Nexus!\nThis file was created by the file resource.",
    mode: 0o644

  # Verify what we created
  command "ls -la /tmp/nexus_test_dir/"
  command "cat /tmp/nexus_test_dir/hello.txt"

  # Test file resource - remove the file
  file "/tmp/nexus_test_dir/hello.txt",
    state: :absent

  # Test directory resource - remove the directory
  directory "/tmp/nexus_test_dir",
    state: :absent

  # Verify cleanup
  command "test -d /tmp/nexus_test_dir && echo 'dir exists' || echo 'dir removed'"
end
