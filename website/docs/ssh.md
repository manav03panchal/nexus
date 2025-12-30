---
sidebar_position: 7
---

# SSH Configuration

Comprehensive guide to SSH authentication, key management, and troubleshooting for Nexus.

## Overview

Nexus uses SSH to execute commands on remote hosts. This guide covers:

- Authentication methods (keys, agent, password)
- Key generation and management
- SSH config file integration
- Connection pooling
- Troubleshooting common issues

---

## Authentication Methods

Nexus supports multiple authentication methods, tried in this order:

1. **Explicit identity file** (`-i` flag or `identity` option)
2. **Password** (if provided via `--password` flag)
3. **SSH agent** (if `SSH_AUTH_SOCK` is set)
4. **Default key files** (`~/.ssh/id_ed25519`, etc.)

### SSH Keys (Recommended)

SSH keys provide secure, password-less authentication.

#### Supported Key Types

| Type | File | Recommendation |
|------|------|----------------|
| Ed25519 | `id_ed25519` | **Recommended** - Most secure, best performance |
| ECDSA | `id_ecdsa` | Good - Modern standard |
| RSA | `id_rsa` | Good - Widely supported |
| DSA | `id_dsa` | Not recommended - Deprecated |

:::tip Key Recommendations
Ed25519 keys are recommended for best security and performance. All modern key formats (PEM and OpenSSH) are supported.
:::

#### Generating Keys

```bash
# Generate Ed25519 key (recommended)
ssh-keygen -t ed25519 -C "deploy@nexus" -f ~/.ssh/nexus_deploy

# Generate RSA key (if Ed25519 not supported)
ssh-keygen -t rsa -b 4096 -C "deploy@nexus" -f ~/.ssh/nexus_deploy

# Generate key without passphrase (for automation)
ssh-keygen -t ed25519 -C "deploy@nexus" -f ~/.ssh/nexus_deploy -N ""
```

#### Deploying Keys to Servers

```bash
# Copy key to server
ssh-copy-id -i ~/.ssh/nexus_deploy.pub user@server

# Or manually append to authorized_keys
cat ~/.ssh/nexus_deploy.pub | ssh user@server "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"

# For multiple servers
for server in web1 web2 web3; do
  ssh-copy-id -i ~/.ssh/nexus_deploy.pub deploy@$server
done
```

#### Key Permissions

SSH is strict about permissions:

```bash
# Private key must be readable only by owner
chmod 600 ~/.ssh/nexus_deploy

# Public key can be world-readable
chmod 644 ~/.ssh/nexus_deploy.pub

# .ssh directory
chmod 700 ~/.ssh

# authorized_keys on server
chmod 600 ~/.ssh/authorized_keys
```

#### Using Keys with Nexus

```bash
# Specify key on command line
nexus run deploy -i ~/.ssh/nexus_deploy

# Or configure in nexus.exs (at parse time)
host :web1, "deploy@web1.example.com"  # Uses default keys

# Key lookup order:
# 1. ~/.ssh/id_ed25519
# 2. ~/.ssh/id_ecdsa
# 3. ~/.ssh/id_rsa
# 4. ~/.ssh/id_dsa
```

### SSH Agent

SSH agent provides convenient key management, especially with passphrase-protected keys.

#### Starting the Agent

```bash
# Bash/Zsh
eval "$(ssh-agent -s)"

# Fish
eval (ssh-agent -c)

# Add to shell profile for persistence:
# ~/.bashrc or ~/.zshrc
if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)"
fi
```

#### Adding Keys

```bash
# Add default key
ssh-add

# Add specific key
ssh-add ~/.ssh/nexus_deploy

# Add with timeout (key expires after 1 hour)
ssh-add -t 3600 ~/.ssh/nexus_deploy

# List loaded keys
ssh-add -l
```

#### Persistent Agent (macOS)

macOS Keychain can store SSH keys persistently:

```bash
# Add key to Keychain
ssh-add --apple-use-keychain ~/.ssh/nexus_deploy

# Configure SSH to use Keychain
# ~/.ssh/config
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/nexus_deploy
```

#### Persistent Agent (Linux)

Use `keychain` for persistent agent:

```bash
# Install keychain
sudo apt install keychain

# Add to ~/.bashrc
eval $(keychain --eval --agents ssh nexus_deploy)
```

### Password Authentication

Password authentication is supported but not recommended for automation.

```bash
# Nexus will prompt for password if no key is found
# This is interactive and doesn't work well in scripts
```

For non-interactive password authentication (not recommended):

```elixir
# In nexus.exs - NOT RECOMMENDED, password in plain text
config :nexus,
  # Don't do this in production!
```

Instead, use SSH keys for automated deployments.

---

## SSH Config Integration

Nexus respects your `~/.ssh/config` file for host-specific settings.

### Supported Directives

| Directive | Description |
|-----------|-------------|
| `Host` | Host pattern for matching |
| `HostName` | Actual hostname/IP |
| `User` | SSH username |
| `Port` | SSH port |
| `IdentityFile` | Path to private key |
| `IdentitiesOnly` | Only use specified identity |
| `ConnectTimeout` | Connection timeout |
| `ProxyJump` | Jump host (bastion) |
| `ProxyCommand` | Proxy command |
| `ForwardAgent` | Forward SSH agent |
| `StrictHostKeyChecking` | Host key verification |

### Example SSH Config

```
# ~/.ssh/config

# Default settings for all hosts
Host *
  AddKeysToAgent yes
  IdentitiesOnly yes
  ServerAliveInterval 60
  ServerAliveCountMax 3

# Production web servers
Host prod-web*
  User deploy
  IdentityFile ~/.ssh/prod_deploy
  
Host prod-web1
  HostName 10.0.1.10

Host prod-web2
  HostName 10.0.1.11

Host prod-web3
  HostName 10.0.1.12
  Port 2222

# Staging
Host staging-*
  User deploy
  IdentityFile ~/.ssh/staging_deploy
  StrictHostKeyChecking no

Host staging-web
  HostName staging.example.com

# Database servers
Host db-*
  User postgres
  IdentityFile ~/.ssh/db_admin
  
Host db-primary
  HostName 10.0.2.10

Host db-replica
  HostName 10.0.2.11

# Jump host for private network
Host bastion
  HostName bastion.example.com
  User admin
  IdentityFile ~/.ssh/bastion_key

Host private-*
  ProxyJump bastion
  
Host private-app
  HostName 192.168.1.10
  User app
```

### Using SSH Config with Nexus

When you define hosts in `nexus.exs`, Nexus will look up settings in `~/.ssh/config`:

```elixir
# nexus.exs
# These hosts will use settings from ~/.ssh/config

host :web1, "prod-web1"     # Uses User=deploy, IdentityFile from config
host :web2, "prod-web2"     # Uses User=deploy, IdentityFile from config
host :staging, "staging-web" # Uses staging settings
host :db, "db-primary"       # Uses postgres user and db_admin key
```

### Jump Hosts (Bastion)

For servers behind a bastion/jump host:

```
# ~/.ssh/config
Host bastion
  HostName bastion.example.com
  User admin
  IdentityFile ~/.ssh/bastion_key

Host internal-*
  ProxyJump bastion
  User deploy
  IdentityFile ~/.ssh/internal_key

Host internal-web1
  HostName 192.168.1.10

Host internal-web2
  HostName 192.168.1.11
```

```elixir
# nexus.exs
host :web1, "internal-web1"  # Connects through bastion automatically
host :web2, "internal-web2"
```

---

## Connection Pooling

Nexus maintains connection pools to improve performance.

### How Pooling Works

```mermaid
flowchart LR
    subgraph Pool["Pool per Host (max_connections: 5)"]
        c1["Conn 1<br/>idle"]
        c2["Conn 2<br/>in use"]
        c3["Conn 3<br/>idle"]
        c4["Conn 4<br/>idle"]
        c5["..."]
    end
```

### Pool Configuration

```elixir
config :nexus,
  # Maximum connections per host
  max_connections: 10,
  
  # Connection timeout
  connect_timeout: 10_000  # 10 seconds
```

### Pool Behavior

1. **Lazy Creation**: Connections are created on first use
2. **Reuse**: Idle connections are reused for new commands
3. **Validation**: Connections are validated before use
4. **Cleanup**: Invalid connections are removed and recreated
5. **Limits**: Never exceed `max_connections` per host

### Performance Impact

| Scenario | Without Pooling | With Pooling |
|----------|-----------------|--------------|
| 10 commands on 1 host | 10 connections (~1s) | 1 connection (~0.1s) |
| 10 commands on 5 hosts | 50 connections (~5s) | 5 connections (~0.5s) |
| 100 commands on 10 hosts | 1000 connections (~100s) | 10 connections (~1s) |

---

## Security Best Practices

### Key Management

```bash
# Use separate keys for different environments
~/.ssh/
├── id_ed25519           # Personal key
├── prod_deploy          # Production deployments
├── staging_deploy       # Staging deployments
├── ci_deploy            # CI/CD pipelines
└── bastion_key          # Bastion/jump host

# Set restrictive permissions
chmod 700 ~/.ssh
chmod 600 ~/.ssh/*
chmod 644 ~/.ssh/*.pub
```

### Limit Key Capabilities

On remote servers, restrict what keys can do:

```
# ~/.ssh/authorized_keys on server
# Restrict to specific commands
command="/opt/deploy/run.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAA... deploy@nexus

# Restrict source IP
from="10.0.0.0/8",no-port-forwarding ssh-ed25519 AAAA... deploy@nexus
```

### Use Dedicated Deploy Users

```bash
# Create deploy user on each server
sudo useradd -m -s /bin/bash deploy
sudo mkdir -p /home/deploy/.ssh
sudo chmod 700 /home/deploy/.ssh

# Add authorized key
echo "ssh-ed25519 AAAA... deploy@nexus" | sudo tee /home/deploy/.ssh/authorized_keys
sudo chmod 600 /home/deploy/.ssh/authorized_keys
sudo chown -R deploy:deploy /home/deploy/.ssh

# Grant necessary sudo permissions (passwordless for specific commands)
echo "deploy ALL=(ALL) NOPASSWD: /bin/systemctl restart myapp, /bin/systemctl status myapp" | sudo tee /etc/sudoers.d/deploy
```

### Host Key Verification

By default, SSH verifies host keys. For automation:

```bash
# Add host key to known_hosts before deploying
ssh-keyscan -H server.example.com >> ~/.ssh/known_hosts

# Or in nexus.exs (less secure, but convenient for dynamic hosts)
# This is done automatically by the -i flag behavior
```

### Audit and Rotate Keys

```bash
# List all authorized keys on a server
cat ~/.ssh/authorized_keys

# Remove old/unused keys regularly
# Add comments with dates for tracking
ssh-ed25519 AAAA... deploy@nexus # Added 2024-01-15, expires 2025-01-15

# Rotate keys periodically
ssh-keygen -t ed25519 -f ~/.ssh/deploy_new
# Deploy new key
# Test access
# Remove old key from authorized_keys
```

---

## Troubleshooting

### Connection Refused

```
Error: {:connection_refused, "192.168.1.10"}
```

**Causes:**
- SSH server not running
- Wrong port
- Firewall blocking connection

**Solutions:**
```bash
# Check if SSH is running on server
sudo systemctl status sshd

# Check port
nc -zv 192.168.1.10 22

# Check firewall
sudo ufw status
sudo iptables -L -n | grep 22
```

### Authentication Failed

```
Error: {:auth_failed, "192.168.1.10"}
```

**Causes:**
- Wrong key
- Key not in authorized_keys
- Wrong username
- Key permissions

**Solutions:**
```bash
# Test with verbose SSH
ssh -vvv deploy@192.168.1.10

# Check key is loaded
ssh-add -l

# Verify authorized_keys on server
cat ~/.ssh/authorized_keys

# Check permissions on server
ls -la ~/.ssh/
# Should be:
# drwx------ .ssh
# -rw------- authorized_keys

# Try specific key
nexus run deploy -i ~/.ssh/specific_key
```

### Connection Timeout

```
Error: {:connection_timeout, "192.168.1.10"}
```

**Causes:**
- Network issues
- Host unreachable
- Firewall dropping packets

**Solutions:**
```bash
# Test connectivity
ping 192.168.1.10

# Test TCP connection
nc -zv -w 5 192.168.1.10 22

# Increase timeout in config
config :nexus,
  connect_timeout: 30_000  # 30 seconds
```

### Host Key Verification Failed

```
Host key verification failed.
```

**Causes:**
- Host not in known_hosts
- Host key changed

**Solutions:**
```bash
# Add host to known_hosts
ssh-keyscan -H 192.168.1.10 >> ~/.ssh/known_hosts

# If key changed legitimately
ssh-keygen -R 192.168.1.10
ssh-keyscan -H 192.168.1.10 >> ~/.ssh/known_hosts
```

### Permission Denied (publickey)

```
Permission denied (publickey)
```

**Causes:**
- Key not authorized
- Wrong username
- SSH config issue

**Solutions:**
```bash
# Check username
ssh -v deploy@192.168.1.10 2>&1 | grep "Trying private key"

# Check what keys are being tried
ssh -v deploy@192.168.1.10 2>&1 | grep "Offering"

# Force specific key
ssh -i ~/.ssh/deploy_key deploy@192.168.1.10

# Check server logs
sudo tail -f /var/log/auth.log
```

### Agent Not Found

```
Could not open a connection to your authentication agent.
```

**Solutions:**
```bash
# Start agent
eval "$(ssh-agent -s)"

# Add key
ssh-add ~/.ssh/nexus_deploy

# Check agent
echo $SSH_AUTH_SOCK
ssh-add -l
```

### Too Many Authentication Failures

```
Received disconnect: Too many authentication failures
```

**Causes:**
- Too many keys loaded in agent
- SSH trying all keys

**Solutions:**
```bash
# Limit keys offered
# ~/.ssh/config
Host *
  IdentitiesOnly yes

Host myserver
  IdentityFile ~/.ssh/specific_key

# Or clear agent and add only needed key
ssh-add -D
ssh-add ~/.ssh/specific_key
```

### Using Preflight to Diagnose

```bash
# Run preflight checks with verbose output
nexus preflight deploy --verbose

# Check specific hosts
nexus preflight --verbose 2>&1 | grep -A5 "ssh:"
```

---

## Advanced Configuration

### Custom SSH Options

Nexus passes options to the underlying SSH library:

```bash
# Command line
nexus run deploy \
  -i ~/.ssh/custom_key \
  -u custom_user
```

### Multiple Key Files

Use SSH config for host-specific keys:

```
# ~/.ssh/config
Host web*
  IdentityFile ~/.ssh/web_deploy

Host db*
  IdentityFile ~/.ssh/db_admin

Host *
  IdentityFile ~/.ssh/default_key
```

### SSH Over Non-Standard Ports

```elixir
# nexus.exs
host :secure_server, "deploy@server.example.com:2222"

# Or in SSH config
Host secure
  HostName server.example.com
  Port 2222
  User deploy
```

### Multiplexing (ControlMaster)

For even better performance, enable SSH multiplexing in `~/.ssh/config`:

```
Host *
  ControlMaster auto
  ControlPath ~/.ssh/sockets/%r@%h-%p
  ControlPersist 600
```

```bash
# Create socket directory
mkdir -p ~/.ssh/sockets
chmod 700 ~/.ssh/sockets
```

---

## See Also

- [Getting Started](getting-started.md) - Initial setup
- [Configuration Reference](configuration.md) - DSL documentation
- [Architecture](architecture.md) - How SSH pooling works internally
- [Troubleshooting](troubleshooting.md) - More debugging tips
