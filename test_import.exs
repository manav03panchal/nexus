# Test imports
import_config "test_imports/hosts.exs"
import_tasks "test_imports/tasks/*.exs"

task :test_import_main, on: :imported_host do
  command "echo 'Main task using imported host!'"
end
