# Test secrets in tasks
host :local, "localhost"

task :test_secret, on: :local do
  command "echo 'The password is: #{secret("DB_PASSWORD")}'"
end
