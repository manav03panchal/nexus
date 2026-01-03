host :decaflab, "decafcoffee@100.112.64.66"

handler :restart_service do
  run "echo 'Handler: Restarting service...'"
end

handler :notify_complete do
  run "echo 'Handler: Deployment complete notification'"
end

task :deploy_with_handlers, on: :decaflab do
  command "echo 'Updating config...'", notify: :restart_service
  command "echo 'Deploy finished'", notify: :notify_complete
end
