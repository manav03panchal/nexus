# Demo Nexus Configuration
# Non-invasive tasks for testing the web dashboard

host :decaflab, "decafcoffee@100.112.64.66"

# Discord webhook notification - sends on pipeline completion
notify "https://discord.com/api/webhooks/1456722127423144096/KsN_NYJzPxKmMMlKHmI1035Lcy5zLIGXyJdsm0qjrb6bTbKRAycBlz-ND1rZ3by5WAhK",
  template: :discord,
  on: :always

# ============================================
# System Info Tasks (Read-only, non-invasive)
# ============================================

task :system_info, on: :decaflab do
  command "uname -a"
  command "uptime"
  command "hostname"
end

task :disk_usage, on: :decaflab, deps: [:system_info] do
  command "df -h"
end

task :memory_info, on: :decaflab, deps: [:system_info] do
  command "free -h"
end

task :network_info, on: :decaflab, deps: [:system_info] do
  command "ip addr show | head -30"
end

task :process_list, on: :decaflab, deps: [:memory_info] do
  command "ps aux --sort=-%mem | head -10"
end

# ============================================
# Temp File Tasks (Creates and cleans up)
# ============================================

task :create_marker, on: :decaflab, deps: [:system_info] do
  command "echo 'Nexus was here at $(date)' > /tmp/nexus_marker.txt"
  command "cat /tmp/nexus_marker.txt"
end

task :cleanup_marker, on: :decaflab, deps: [:create_marker] do
  command "rm -f /tmp/nexus_marker.txt"
  command "echo 'Cleanup complete'"
end

# ============================================
# Final Summary
# ============================================

task :summary, on: :decaflab, deps: [:disk_usage, :memory_info, :network_info, :process_list, :cleanup_marker] do
  command "echo '========================================'"
  command "echo 'Nexus Demo Complete!'"
  command "echo 'Server: decaflab'"
  command "echo 'Time: '$(date)"
  command "echo '========================================'"
end
