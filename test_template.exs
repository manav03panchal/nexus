# Test template rendering
host :decaflab, "decafcoffee@100.112.64.66"

task :test_template, on: :decaflab do
  template "test_templates/config.txt.eex", "/tmp/nexus_config.txt",
    vars: %{
      timestamp: DateTime.utc_now() |> DateTime.to_string(),
      app_name: "my_app",
      environment: "production",
      port: 8080,
      debug: false,
      db_host: "localhost",
      db_name: "my_app_prod"
    }

  command "cat /tmp/nexus_config.txt"
  command "rm /tmp/nexus_config.txt"
end
