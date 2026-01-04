# Imported task file
task :imported_hello, on: :imported_host do
  command "echo 'Hello from imported task!'"
end
