---
sidebar_position: 5
---

# Examples

Real-world examples of Nexus configurations.

## Phoenix Deployment

Deploy a Phoenix application to multiple servers.

```elixir
# nexus.exs

host :web1, "deploy@web1.myapp.com"
host :web2, "deploy@web2.myapp.com"
host :db, "deploy@db.myapp.com"

group :web, [:web1, :web2]

config :nexus,
  default_user: "deploy",
  command_timeout: 120_000

# Build locally
task :deps do
  run "mix deps.get --only prod"
end

task :compile, deps: [:deps] do
  run "MIX_ENV=prod mix compile"
end

task :assets, deps: [:compile] do
  run "MIX_ENV=prod mix assets.deploy"
end

task :release, deps: [:assets] do
  run "MIX_ENV=prod mix release --overwrite"
  run "tar -czf myapp.tar.gz -C _build/prod/rel myapp"
end

# Deploy to servers
task :upload, on: :web, deps: [:release] do
  run "mkdir -p /opt/myapp/releases"
end

task :extract, on: :web, deps: [:upload] do
  run "tar -xzf /tmp/myapp.tar.gz -C /opt/myapp/releases/"
  run "ln -sfn /opt/myapp/releases/myapp /opt/myapp/current"
end

task :migrate, on: :db, deps: [:extract] do
  run "/opt/myapp/current/bin/myapp eval 'MyApp.Release.migrate()'"
end

task :restart, on: :web, deps: [:migrate] do
  run "systemctl restart myapp", sudo: true
end

task :deploy, deps: [:restart] do
  run "echo 'Deployment complete!'"
end
```

**Usage:**

```bash
# Full deployment
nexus run deploy -i ~/.ssh/deploy_key

# Just restart
nexus run restart -i ~/.ssh/deploy_key

# Dry run
nexus run deploy --dry-run
```

## Docker Compose Deployment

Deploy Docker containers to servers.

```elixir
# nexus.exs

host :prod1, "ubuntu@prod1.example.com"
host :prod2, "ubuntu@prod2.example.com"

group :prod, [:prod1, :prod2]

task :pull, on: :prod do
  run "docker-compose -f /opt/app/docker-compose.yml pull"
end

task :stop, on: :prod, deps: [:pull] do
  run "docker-compose -f /opt/app/docker-compose.yml down"
end

task :start, on: :prod, deps: [:stop] do
  run "docker-compose -f /opt/app/docker-compose.yml up -d"
end

task :logs, on: :prod do
  run "docker-compose -f /opt/app/docker-compose.yml logs --tail=50"
end

task :deploy, deps: [:start] do
end
```

## Multi-Environment Setup

Separate configs for staging and production.

```elixir
# nexus.staging.exs

host :staging, "deploy@staging.example.com"

task :deploy, on: :staging do
  run "cd /opt/app && git pull"
  run "cd /opt/app && mix deps.get"
  run "cd /opt/app && MIX_ENV=prod mix release --overwrite"
  run "systemctl restart myapp", sudo: true
end
```

```elixir
# nexus.prod.exs

host :prod1, "deploy@prod1.example.com"
host :prod2, "deploy@prod2.example.com"

group :prod, [:prod1, :prod2]

task :deploy, on: :prod do
  run "cd /opt/app && git pull"
  run "cd /opt/app && mix deps.get"
  run "cd /opt/app && MIX_ENV=prod mix release --overwrite"
  run "systemctl restart myapp", sudo: true
end
```

**Usage:**

```bash
# Deploy to staging
nexus run deploy -c nexus.staging.exs

# Deploy to production
nexus run deploy -c nexus.prod.exs
```

## Rolling Deployment

Deploy to servers one at a time.

```elixir
# nexus.exs

host :web1, "deploy@web1.example.com"
host :web2, "deploy@web2.example.com"
host :web3, "deploy@web3.example.com"

group :web, [:web1, :web2, :web3]

task :deploy, on: :web, strategy: :serial do
  run "systemctl stop myapp", sudo: true
  run "cd /opt/app && git pull"
  run "cd /opt/app && mix deps.get --only prod"
  run "cd /opt/app && MIX_ENV=prod mix release --overwrite"
  run "systemctl start myapp", sudo: true
  run "sleep 5"  # Wait for health check
  run "curl -f http://localhost:4000/health"
end
```

The `strategy: :serial` ensures each server completes before moving to the next.

## Database Backup

Backup database before deployment.

```elixir
# nexus.exs

host :db, "admin@db.example.com"
host :web, "deploy@web.example.com"

task :backup, on: :db do
  run "pg_dump myapp_prod > /backups/myapp_$(date +%Y%m%d_%H%M%S).sql"
  run "gzip /backups/myapp_*.sql"
  run "find /backups -name '*.gz' -mtime +7 -delete"  # Keep 7 days
end

task :migrate, on: :db, deps: [:backup] do
  run "/opt/app/bin/myapp eval 'MyApp.Release.migrate()'"
end

task :deploy, on: :web, deps: [:migrate] do
  run "systemctl restart myapp", sudo: true
end
```

## Health Checks

Verify deployment succeeded.

```elixir
# nexus.exs

host :web1, "deploy@web1.example.com"
host :web2, "deploy@web2.example.com"

group :web, [:web1, :web2]

task :deploy, on: :web do
  run "systemctl restart myapp", sudo: true
end

task :health, on: :web, deps: [:deploy] do
  run "sleep 5"
  run "curl -f http://localhost:4000/health", retries: 3, retry_delay: 2000
end

task :verify, deps: [:health] do
  run "echo 'All servers healthy!'"
end
```

## Cleanup Tasks

Maintenance tasks.

```elixir
# nexus.exs

host :web1, "deploy@web1.example.com"
host :web2, "deploy@web2.example.com"

group :web, [:web1, :web2]

task :clean_logs, on: :web do
  run "find /var/log/myapp -name '*.log' -mtime +30 -delete"
end

task :clean_releases, on: :web do
  run "ls -t /opt/app/releases | tail -n +4 | xargs -I {} rm -rf /opt/app/releases/{}"
end

task :disk_usage, on: :web do
  run "df -h"
  run "du -sh /opt/app/*"
end

task :cleanup, deps: [:clean_logs, :clean_releases] do
end
```

## CI/CD Integration

Use with GitHub Actions.

```yaml
# .github/workflows/deploy.yml

name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'
      
      - name: Install Nexus
        run: |
          curl -fsSL https://raw.githubusercontent.com/manav03panchal/nexus/main/scripts/install.sh | bash
      
      - name: Setup SSH
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.DEPLOY_KEY }}" > ~/.ssh/deploy_key
          chmod 600 ~/.ssh/deploy_key
      
      - name: Deploy
        run: |
          nexus run deploy -i ~/.ssh/deploy_key
```
