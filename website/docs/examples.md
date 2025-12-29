---
sidebar_position: 5
---

# Examples

Real-world examples of Nexus configurations for common deployment scenarios.

## Table of Contents

1. [Phoenix/Elixir Deployment](#phoenixelixir-deployment)
2. [Node.js Application](#nodejs-application)
3. [Docker Compose Deployment](#docker-compose-deployment)
4. [Multi-Environment Configuration](#multi-environment-configuration)
5. [Rolling Deployment with Health Checks](#rolling-deployment-with-health-checks)
6. [Database Operations](#database-operations)
7. [Static Site Deployment](#static-site-deployment)
8. [Server Maintenance](#server-maintenance)
9. [Blue-Green Deployment](#blue-green-deployment)
10. [Kubernetes Deployment](#kubernetes-deployment)

---

## Phoenix/Elixir Deployment

A complete deployment pipeline for a Phoenix application with database migrations.

```elixir
# nexus.exs - Phoenix Application Deployment

# =============================================================================
# Configuration
# =============================================================================
config :nexus,
  default_user: "deploy",
  connect_timeout: 10_000,
  command_timeout: 300_000,
  max_connections: 10

# =============================================================================
# Hosts
# =============================================================================
host :web1, "deploy@192.168.1.10"
host :web2, "deploy@192.168.1.11"
host :web3, "deploy@192.168.1.12"
host :db_primary, "postgres@192.168.2.10"

# =============================================================================
# Groups
# =============================================================================
group :web, [:web1, :web2, :web3]

# =============================================================================
# Build Tasks (Local)
# =============================================================================

task :clean do
  run "rm -rf _build/prod deps"
end

task :deps do
  run "mix deps.get --only prod"
end

task :compile, deps: [:deps] do
  run "MIX_ENV=prod mix compile"
end

task :assets, deps: [:deps] do
  run "cd assets && npm ci --silent"
  run "cd assets && npm run deploy"
  run "MIX_ENV=prod mix phx.digest"
end

task :release, deps: [:compile, :assets] do
  run "MIX_ENV=prod mix release --overwrite"
  run "ls -la _build/prod/rel/myapp/"
end

# =============================================================================
# Deployment Tasks
# =============================================================================

task :backup_current, on: :web do
  run "if [ -d /opt/myapp/current ]; then cp -r /opt/myapp/current /opt/myapp/rollback-$(date +%Y%m%d-%H%M%S); fi"
end

task :upload, on: :web, deps: [:release] do
  run "mkdir -p /opt/myapp/releases"
  # In practice, you'd use scp, rsync, or fetch from artifact storage
  run "echo 'Uploading release...'"
end

task :deploy, on: :web, deps: [:upload, :backup_current], strategy: :serial do
  # Drain connections from load balancer
  run "if command -v consul &> /dev/null; then consul maint -enable -reason 'deploying'; fi"
  run "sleep 5"
  
  # Stop current version
  run "systemctl stop myapp || true", sudo: true
  
  # Link new release
  run "cd /opt/myapp && rm -f current && ln -s releases/latest current"
  
  # Start new version
  run "systemctl start myapp", sudo: true
  
  # Wait for startup
  run "sleep 10"
  
  # Health check with retries
  run "curl -sf http://localhost:4000/health", retries: 5, retry_delay: 3_000
  
  # Re-enable in load balancer
  run "if command -v consul &> /dev/null; then consul maint -disable; fi"
end

task :migrate, on: :db_primary, deps: [:deploy] do
  run "/opt/myapp/current/bin/myapp eval 'MyApp.Release.migrate()'"
end

task :full_deploy, deps: [:migrate] do
  run "echo 'Deployment complete!'"
end

# =============================================================================
# Operations Tasks
# =============================================================================

task :rollback, on: :web, strategy: :serial do
  run "consul maint -enable -reason 'rollback'"
  run "sleep 5"
  run "systemctl stop myapp", sudo: true
  
  # Find most recent rollback
  run "cd /opt/myapp && LATEST=$(ls -td rollback-* | head -1) && rm -f current && ln -s $LATEST current"
  
  run "systemctl start myapp", sudo: true
  run "sleep 10"
  run "curl -sf http://localhost:4000/health"
  run "consul maint -disable"
end

task :logs, on: :web do
  run "journalctl -u myapp -n 100 --no-pager"
end

task :status, on: :web do
  run "systemctl status myapp"
  run "curl -s http://localhost:4000/health | jq ."
end

task :restart, on: :web, strategy: :serial do
  run "consul maint -enable"
  run "sleep 5"
  run "systemctl restart myapp", sudo: true
  run "sleep 10"
  run "curl -sf http://localhost:4000/health", retries: 3, retry_delay: 2_000
  run "consul maint -disable"
end
```

**Usage:**

```bash
# Full deployment pipeline
nexus run full_deploy

# Just build locally
nexus run release

# Rollback to previous version
nexus run rollback

# View logs across all web servers
nexus run logs
```

---

## Node.js Application

Deploying a Node.js application with PM2 process manager.

```elixir
# nexus.exs - Node.js Application Deployment

config :nexus,
  default_user: "nodejs",
  command_timeout: 120_000

host :app1, "nodejs@app1.example.com"
host :app2, "nodejs@app2.example.com"

group :app_servers, [:app1, :app2]

# Local build
task :install do
  run "npm ci"
end

task :build, deps: [:install] do
  run "npm run build"
  run "npm test"
end

task :package, deps: [:build] do
  run "tar -czf dist.tar.gz package.json package-lock.json dist/ node_modules/"
end

# Remote deployment
task :upload, on: :app_servers, deps: [:package] do
  run "mkdir -p /opt/myapp/releases/$(date +%Y%m%d-%H%M%S)"
end

task :deploy, on: :app_servers, deps: [:upload], strategy: :serial do
  # Extract release
  run "cd /opt/myapp/releases/$(ls /opt/myapp/releases | tail -1) && tar -xzf /tmp/dist.tar.gz"
  
  # Install production dependencies only
  run "cd /opt/myapp/releases/$(ls /opt/myapp/releases | tail -1) && npm ci --production"
  
  # Update symlink
  run "rm -f /opt/myapp/current && ln -s /opt/myapp/releases/$(ls /opt/myapp/releases | tail -1) /opt/myapp/current"
  
  # Reload PM2
  run "pm2 reload ecosystem.config.js --update-env"
  
  # Health check
  run "sleep 5"
  run "curl -sf http://localhost:3000/health"
end

task :rollback, on: :app_servers, strategy: :serial do
  # Link to previous release
  run "cd /opt/myapp/releases && PREV=$(ls -t | head -2 | tail -1) && rm -f /opt/myapp/current && ln -s /opt/myapp/releases/$PREV /opt/myapp/current"
  run "pm2 reload ecosystem.config.js --update-env"
  run "sleep 5"
  run "curl -sf http://localhost:3000/health"
end

task :logs, on: :app_servers do
  run "pm2 logs --lines 50 --nostream"
end

task :status, on: :app_servers do
  run "pm2 status"
end

# Cleanup old releases (keep last 5)
task :cleanup, on: :app_servers do
  run "cd /opt/myapp/releases && ls -t | tail -n +6 | xargs -r rm -rf"
end
```

---

## Docker Compose Deployment

Deploying applications using Docker Compose.

```elixir
# nexus.exs - Docker Compose Deployment

config :nexus,
  default_user: "deploy",
  command_timeout: 600_000  # 10 minutes for image pulls

host :docker1, "deploy@docker1.example.com"
host :docker2, "deploy@docker2.example.com"

group :docker_hosts, [:docker1, :docker2]

# Build and push images locally
task :build do
  run "docker build -t myregistry.com/myapp:$(git rev-parse --short HEAD) ."
  run "docker push myregistry.com/myapp:$(git rev-parse --short HEAD)"
end

# Deploy to Docker hosts
task :deploy, on: :docker_hosts, deps: [:build] do
  # Pull latest images
  run "docker compose pull"
  
  # Stop and recreate containers
  run "docker compose up -d --remove-orphans"
  
  # Wait for health
  run "sleep 10"
  
  # Verify containers are running
  run "docker compose ps"
  
  # Health check
  run "curl -sf http://localhost/health"
end

task :rollback, on: :docker_hosts do
  # Rollback to previous image
  run "docker compose down"
  run "docker tag myregistry.com/myapp:previous myregistry.com/myapp:latest"
  run "docker compose up -d"
end

task :logs, on: :docker_hosts do
  run "docker compose logs --tail 100"
end

task :status, on: :docker_hosts do
  run "docker compose ps"
  run "docker stats --no-stream"
end

task :cleanup, on: :docker_hosts do
  # Remove unused images and volumes
  run "docker system prune -af --volumes", sudo: true
end

task :restart, on: :docker_hosts, strategy: :serial do
  run "docker compose restart"
  run "sleep 10"
  run "curl -sf http://localhost/health"
end
```

---

## Multi-Environment Configuration

Managing multiple environments (staging, production) in one config.

```elixir
# nexus.exs - Multi-Environment Configuration

# Determine environment from environment variable
environment = System.get_env("NEXUS_ENV") || "staging"

# Environment-specific configuration
case environment do
  "production" ->
    config :nexus,
      default_user: "deploy",
      command_timeout: 300_000,
      max_connections: 20

    host :web1, "deploy@prod-web1.example.com"
    host :web2, "deploy@prod-web2.example.com"
    host :web3, "deploy@prod-web3.example.com"
    host :db, "postgres@prod-db.example.com"

    group :web, [:web1, :web2, :web3]

  "staging" ->
    config :nexus,
      default_user: "deploy",
      command_timeout: 120_000,
      max_connections: 5

    host :web1, "deploy@staging-web1.example.com"
    host :db, "postgres@staging-db.example.com"

    group :web, [:web1]

  _ ->
    raise "Unknown environment: #{environment}. Set NEXUS_ENV to 'staging' or 'production'"
end

# =============================================================================
# Tasks (same for all environments)
# =============================================================================

task :build do
  run "mix deps.get --only prod"
  run "MIX_ENV=prod mix release --overwrite"
end

task :deploy, on: :web, deps: [:build], strategy: :serial do
  run "systemctl stop myapp", sudo: true
  run "cd /opt/myapp && ln -sfn releases/latest current"
  run "systemctl start myapp", sudo: true
  run "sleep 10"
  run "curl -sf http://localhost:4000/health"
end

task :migrate, on: :db, deps: [:deploy] do
  run "/opt/myapp/current/bin/myapp eval 'MyApp.Release.migrate()'"
end

task :full_deploy, deps: [:migrate] do
  run "echo 'Deployed to #{environment}!'"
end

task :status, on: :web do
  run "hostname"
  run "systemctl status myapp"
end
```

**Usage:**

```bash
# Deploy to staging (default)
nexus run full_deploy

# Deploy to production
NEXUS_ENV=production nexus run full_deploy

# Check status in production
NEXUS_ENV=production nexus run status
```

---

## Rolling Deployment with Health Checks

Zero-downtime deployment with rolling updates.

```elixir
# nexus.exs - Rolling Deployment

config :nexus,
  default_user: "deploy",
  command_timeout: 300_000

host :web1, "deploy@web1.example.com"
host :web2, "deploy@web2.example.com"
host :web3, "deploy@web3.example.com"
host :web4, "deploy@web4.example.com"

group :web, [:web1, :web2, :web3, :web4]

task :build do
  run "mix deps.get --only prod"
  run "MIX_ENV=prod mix release --overwrite"
end

# Serial deployment ensures one host at a time
task :deploy, on: :web, deps: [:build], strategy: :serial do
  # Step 1: Remove from load balancer
  run "curl -X POST http://localhost:8500/v1/agent/service/deregister/myapp"
  run "sleep 10"  # Allow in-flight requests to complete
  
  # Step 2: Stop the service
  run "systemctl stop myapp", sudo: true
  
  # Step 3: Deploy new version
  run "cd /opt/myapp && ln -sfn releases/$(date +%Y%m%d-%H%M%S) current"
  
  # Step 4: Start the service
  run "systemctl start myapp", sudo: true
  
  # Step 5: Wait for service to be ready
  run "sleep 10"
  
  # Step 6: Health check with retries
  run """
  for i in {1..30}; do
    if curl -sf http://localhost:4000/health; then
      echo "Health check passed"
      exit 0
    fi
    echo "Attempt $i failed, retrying..."
    sleep 2
  done
  echo "Health check failed after 30 attempts"
  exit 1
  """
  
  # Step 7: Re-register with load balancer
  run """
  curl -X PUT http://localhost:8500/v1/agent/service/register -d '{
    "Name": "myapp",
    "Port": 4000,
    "Check": {
      "HTTP": "http://localhost:4000/health",
      "Interval": "10s"
    }
  }'
  """
  
  # Step 8: Verify service is receiving traffic
  run "sleep 5"
  run "curl -s http://localhost:4000/health | grep -q 'ok'"
end

task :status, on: :web do
  run "hostname"
  run "systemctl status myapp --no-pager"
  run "curl -s http://localhost:4000/health | jq ."
end

task :rollback, on: :web, strategy: :serial do
  run "curl -X POST http://localhost:8500/v1/agent/service/deregister/myapp"
  run "sleep 10"
  
  run "systemctl stop myapp", sudo: true
  
  # Link to previous release
  run "cd /opt/myapp && PREV=$(ls -td releases/*/ | head -2 | tail -1) && ln -sfn $PREV current"
  
  run "systemctl start myapp", sudo: true
  run "sleep 10"
  
  run "curl -sf http://localhost:4000/health", retries: 10, retry_delay: 2_000
  
  run """
  curl -X PUT http://localhost:8500/v1/agent/service/register -d '{
    "Name": "myapp",
    "Port": 4000,
    "Check": {"HTTP": "http://localhost:4000/health", "Interval": "10s"}
  }'
  """
end
```

---

## Database Operations

Common database maintenance tasks.

```elixir
# nexus.exs - Database Operations

config :nexus,
  default_user: "postgres",
  command_timeout: 3_600_000  # 1 hour for long operations

host :db_primary, "postgres@db-primary.example.com"
host :db_replica1, "postgres@db-replica1.example.com"
host :db_replica2, "postgres@db-replica2.example.com"

group :replicas, [:db_replica1, :db_replica2]
group :all_dbs, [:db_primary, :db_replica1, :db_replica2]

# Backup
task :backup, on: :db_primary do
  run "mkdir -p /backups/$(date +%Y%m)"
  run """
  pg_dump myapp_production \
    --format=custom \
    --compress=9 \
    --file=/backups/$(date +%Y%m)/myapp-$(date +%Y%m%d-%H%M%S).dump
  """
  run "ls -lh /backups/$(date +%Y%m)/ | tail -5"
end

# Restore (be careful!)
task :restore, on: :db_primary do
  run "echo 'WARNING: This will overwrite the database!'"
  run "pg_restore --clean --if-exists --dbname=myapp_production /backups/latest.dump"
end

# Vacuum and analyze
task :vacuum, on: :db_primary do
  run "vacuumdb --analyze --verbose myapp_production"
end

# Reindex
task :reindex, on: :db_primary do
  run "reindexdb --verbose myapp_production"
end

# Check replication status
task :replication_status, on: :db_primary do
  run """
  psql -c "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn,
           pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
           FROM pg_stat_replication;"
  """
end

# Check replica lag
task :check_lag, on: :replicas do
  run """
  psql -c "SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;"
  """
end

# Database size
task :db_size, on: :all_dbs do
  run "hostname"
  run """
  psql -c "SELECT pg_database.datname,
           pg_size_pretty(pg_database_size(pg_database.datname)) AS size
           FROM pg_database
           ORDER BY pg_database_size(pg_database.datname) DESC;"
  """
end

# Table sizes
task :table_sizes, on: :db_primary do
  run """
  psql myapp_production -c "
    SELECT schemaname, tablename,
           pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size,
           pg_size_pretty(pg_relation_size(schemaname || '.' || tablename)) AS table_size,
           pg_size_pretty(pg_indexes_size(schemaname || '.' || tablename)) AS index_size
    FROM pg_tables
    WHERE schemaname = 'public'
    ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC
    LIMIT 20;
  "
  """
end

# Long running queries
task :long_queries, on: :db_primary do
  run """
  psql -c "SELECT pid, now() - pg_stat_activity.query_start AS duration, query
           FROM pg_stat_activity
           WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes'
           AND state = 'active';"
  """
end

# Kill long running queries
task :kill_long_queries, on: :db_primary do
  run """
  psql -c "SELECT pg_terminate_backend(pid)
           FROM pg_stat_activity
           WHERE (now() - pg_stat_activity.query_start) > interval '1 hour'
           AND state = 'active'
           AND query NOT LIKE '%pg_stat_activity%';"
  """
end

# Cleanup old backups (keep last 7 days)
task :cleanup_backups, on: :db_primary do
  run "find /backups -name '*.dump' -mtime +7 -delete"
  run "df -h /backups"
end
```

---

## Static Site Deployment

Deploying a static site (Hugo, Jekyll, etc.) to multiple servers.

```elixir
# nexus.exs - Static Site Deployment

config :nexus,
  default_user: "www-data",
  command_timeout: 60_000

host :cdn1, "www-data@cdn1.example.com"
host :cdn2, "www-data@cdn2.example.com"

group :cdn, [:cdn1, :cdn2]

# Build static site locally
task :build do
  run "hugo --minify"
  run "tar -czf site.tar.gz -C public ."
end

# Deploy to CDN servers
task :deploy, on: :cdn, deps: [:build] do
  run "mkdir -p /var/www/mysite/releases/$(date +%Y%m%d-%H%M%S)"
end

task :activate, on: :cdn, deps: [:deploy] do
  # Extract to new release directory
  run "cd /var/www/mysite/releases/$(ls /var/www/mysite/releases | tail -1) && tar -xzf /tmp/site.tar.gz"
  
  # Update symlink
  run "ln -sfn /var/www/mysite/releases/$(ls /var/www/mysite/releases | tail -1) /var/www/mysite/current"
  
  # Reload nginx
  run "nginx -t && systemctl reload nginx", sudo: true
end

task :rollback, on: :cdn do
  run "cd /var/www/mysite/releases && PREV=$(ls -t | head -2 | tail -1) && ln -sfn /var/www/mysite/releases/$PREV /var/www/mysite/current"
  run "systemctl reload nginx", sudo: true
end

task :purge_cache, on: :cdn do
  run "rm -rf /var/cache/nginx/*"
  run "systemctl reload nginx", sudo: true
end

task :cleanup, on: :cdn do
  # Keep last 5 releases
  run "cd /var/www/mysite/releases && ls -t | tail -n +6 | xargs -r rm -rf"
end

task :full_deploy, deps: [:activate, :purge_cache] do
  run "echo 'Site deployed!'"
end
```

---

## Server Maintenance

Common server maintenance tasks.

```elixir
# nexus.exs - Server Maintenance

config :nexus,
  default_user: "admin",
  command_timeout: 600_000

host :server1, "admin@server1.example.com"
host :server2, "admin@server2.example.com"
host :server3, "admin@server3.example.com"

group :all, [:server1, :server2, :server3]

# System updates
task :update, on: :all do
  run "apt-get update", sudo: true
  run "apt-get upgrade -y", sudo: true
end

task :reboot, on: :all, strategy: :serial do
  run "shutdown -r +1 'Scheduled reboot'", sudo: true
end

# Disk usage
task :disk, on: :all do
  run "hostname"
  run "df -h"
end

# Memory usage
task :memory, on: :all do
  run "hostname"
  run "free -h"
end

# CPU usage
task :cpu, on: :all do
  run "hostname"
  run "top -bn1 | head -20"
end

# Process list
task :processes, on: :all do
  run "hostname"
  run "ps aux --sort=-%mem | head -20"
end

# Logs
task :syslog, on: :all do
  run "tail -100 /var/log/syslog"
end

task :auth_log, on: :all do
  run "tail -100 /var/log/auth.log", sudo: true
end

# Security updates only
task :security_update, on: :all do
  run "apt-get update", sudo: true
  run "apt-get install --only-upgrade -y $(apt-get -s upgrade | grep -i security | awk '{print $2}')", sudo: true
end

# Cleanup
task :cleanup, on: :all do
  run "apt-get autoremove -y", sudo: true
  run "apt-get autoclean", sudo: true
  run "journalctl --vacuum-time=7d", sudo: true
  run "find /tmp -type f -atime +7 -delete", sudo: true
end

# Check for failed services
task :check_services, on: :all do
  run "hostname"
  run "systemctl --failed"
end

# Uptime
task :uptime, on: :all do
  run "hostname && uptime"
end
```

---

## Blue-Green Deployment

Blue-green deployment pattern for zero-downtime updates.

```elixir
# nexus.exs - Blue-Green Deployment

config :nexus,
  default_user: "deploy",
  command_timeout: 300_000

# Blue environment
host :blue1, "deploy@blue1.example.com"
host :blue2, "deploy@blue2.example.com"

# Green environment  
host :green1, "deploy@green1.example.com"
host :green2, "deploy@green2.example.com"

# Load balancer
host :lb, "admin@lb.example.com"

group :blue, [:blue1, :blue2]
group :green, [:green1, :green2]

# Determine which environment is active
# In practice, you'd query your load balancer or use a state file
active_env = System.get_env("ACTIVE_ENV") || "blue"
inactive_env = if active_env == "blue", do: "green", else: "blue"
target_group = String.to_atom(inactive_env)

task :build do
  run "mix deps.get --only prod"
  run "MIX_ENV=prod mix release --overwrite"
end

# Deploy to inactive environment
task :deploy_inactive, on: target_group, deps: [:build] do
  run "systemctl stop myapp", sudo: true
  run "cd /opt/myapp && ln -sfn releases/latest current"
  run "systemctl start myapp", sudo: true
  run "sleep 15"
  run "curl -sf http://localhost:4000/health", retries: 5, retry_delay: 3_000
end

# Verify inactive environment
task :verify_inactive, on: target_group, deps: [:deploy_inactive] do
  run "curl -sf http://localhost:4000/health"
  run "curl -sf http://localhost:4000/api/version"
end

# Switch traffic
task :switch, on: :lb, deps: [:verify_inactive] do
  run """
  # Update nginx upstream to point to #{inactive_env}
  sed -i 's/upstream active/upstream #{active_env}_backup/g' /etc/nginx/sites-enabled/myapp
  sed -i 's/upstream #{inactive_env}/upstream active/g' /etc/nginx/sites-enabled/myapp
  nginx -t && systemctl reload nginx
  """, sudo: true
end

# Full blue-green deploy
task :blue_green_deploy, deps: [:switch] do
  run "echo 'Traffic switched to #{inactive_env}'"
  run "echo 'Previous active: #{active_env}'"
end

# Rollback (switch back)
task :rollback, on: :lb do
  run """
  # Switch back to #{active_env}
  sed -i 's/upstream active/upstream #{inactive_env}_backup/g' /etc/nginx/sites-enabled/myapp
  sed -i 's/upstream #{active_env}/upstream active/g' /etc/nginx/sites-enabled/myapp
  nginx -t && systemctl reload nginx
  """, sudo: true
end

task :status do
  run "echo 'Active environment: #{active_env}'"
  run "echo 'Inactive environment: #{inactive_env}'"
end
```

**Usage:**

```bash
# Deploy to inactive environment and switch
ACTIVE_ENV=blue nexus run blue_green_deploy

# Rollback to previous environment
ACTIVE_ENV=green nexus run rollback
```

---

## Kubernetes Deployment

Deploying to Kubernetes clusters.

```elixir
# nexus.exs - Kubernetes Deployment

config :nexus,
  default_user: "deploy",
  command_timeout: 600_000

host :k8s_bastion, "deploy@bastion.k8s.example.com"

# Build and push container
task :build do
  run "docker build -t myregistry.com/myapp:$(git rev-parse --short HEAD) ."
  run "docker push myregistry.com/myapp:$(git rev-parse --short HEAD)"
end

# Deploy to Kubernetes
task :deploy, on: :k8s_bastion, deps: [:build] do
  # Update image in deployment
  run """
  kubectl set image deployment/myapp \
    myapp=myregistry.com/myapp:$(git rev-parse --short HEAD) \
    --record
  """
  
  # Wait for rollout
  run "kubectl rollout status deployment/myapp --timeout=5m"
end

# Rollback
task :rollback, on: :k8s_bastion do
  run "kubectl rollout undo deployment/myapp"
  run "kubectl rollout status deployment/myapp --timeout=5m"
end

# Scale
task :scale_up, on: :k8s_bastion do
  run "kubectl scale deployment/myapp --replicas=5"
end

task :scale_down, on: :k8s_bastion do
  run "kubectl scale deployment/myapp --replicas=2"
end

# Status
task :status, on: :k8s_bastion do
  run "kubectl get pods -l app=myapp"
  run "kubectl get deployment myapp"
  run "kubectl get hpa myapp"
end

# Logs
task :logs, on: :k8s_bastion do
  run "kubectl logs -l app=myapp --tail=100"
end

# Exec into pod
task :shell, on: :k8s_bastion do
  run "kubectl exec -it $(kubectl get pods -l app=myapp -o jsonpath='{.items[0].metadata.name}') -- /bin/sh"
end

# Restart all pods
task :restart, on: :k8s_bastion do
  run "kubectl rollout restart deployment/myapp"
  run "kubectl rollout status deployment/myapp --timeout=5m"
end

# Health check
task :health, on: :k8s_bastion do
  run "kubectl get pods -l app=myapp -o jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{.status.phase}{\"\\n\"}{end}'"
end
```

---

## See Also

- [Getting Started](getting-started.md) - Initial setup guide
- [Configuration Reference](configuration.md) - Complete DSL documentation
- [CLI Reference](cli.md) - Command-line options
- [SSH Configuration](ssh.md) - SSH authentication details
