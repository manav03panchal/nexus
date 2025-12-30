---
sidebar_position: 8
---

# Troubleshooting

Solutions to common issues when using Nexus.

## Quick Diagnostic Commands

```bash
# Validate configuration
nexus validate

# Run pre-flight checks
nexus preflight deploy --verbose

# Test with dry run
nexus run deploy --dry-run

# Verbose output for debugging
nexus run deploy --verbose
```

---

## Configuration Issues

### Config File Not Found

```
Error: Config file not found: nexus.exs
```

**Cause:** Nexus can't find the configuration file.

**Solutions:**

```bash
# Check if file exists
ls -la nexus.exs

# Create if missing
nexus init

# Specify path explicitly
nexus run deploy -c /path/to/nexus.exs

# Check current directory
pwd
```

### Syntax Error in Config

```
Error: syntax error: missing 'do' in 'task'
```

**Cause:** Invalid Elixir syntax in `nexus.exs`.

**Solutions:**

1. Check for missing `do`/`end` blocks:
   ```elixir
   # Wrong
   task :deploy
     run "echo hello"
   end
   
   # Correct
   task :deploy do
     run "echo hello"
   end
   ```

2. Check for missing commas:
   ```elixir
   # Wrong
   config :nexus
     default_user: "deploy"
     default_port: 22
   
   # Correct
   config :nexus,
     default_user: "deploy",
     default_port: 22
   ```

3. Validate syntax:
   ```bash
   elixir -e 'Code.compile_file("nexus.exs")'
   ```

### Unknown Config Option

```
Error: unknown config option: parallel_limit
```

**Cause:** Using an option that doesn't exist.

**Valid config options:**
- `default_user`
- `default_port`
- `connect_timeout`
- `command_timeout`
- `max_connections`
- `continue_on_error`

```elixir
# Correct options
config :nexus,
  default_user: "deploy",
  default_port: 22,
  connect_timeout: 10_000,
  command_timeout: 60_000,
  max_connections: 5,
  continue_on_error: false
```

### Task References Unknown Task

```
Error: task :deploy depends on unknown task :build
```

**Cause:** A task's `deps` references a task that doesn't exist.

**Solution:**

```elixir
# Make sure all dependencies exist
task :build do
  run "mix compile"
end

task :deploy, deps: [:build] do  # :build must exist
  run "deploy.sh"
end
```

### Host References Unknown

```
Error: task :deploy references unknown host or group :webservers
```

**Cause:** Task's `on` option references undefined host or group.

**Solution:**

```elixir
# Define hosts first
host :web1, "deploy@192.168.1.10"
host :web2, "deploy@192.168.1.11"

# Then define groups
group :webservers, [:web1, :web2]

# Now use in tasks
task :deploy, on: :webservers do
  run "deploy.sh"
end
```

### Circular Dependency

```
Error: circular dependency detected: a -> b -> c -> a
```

**Cause:** Tasks form a dependency cycle.

**Solution:** Restructure tasks to break the cycle:

```elixir
# Wrong: circular dependency
task :a, deps: [:c] do ... end
task :b, deps: [:a] do ... end
task :c, deps: [:b] do ... end

# Correct: no cycles
task :a do ... end
task :b, deps: [:a] do ... end
task :c, deps: [:b] do ... end
```

---

## Connection Issues

### Connection Refused

```
Error: {:connection_refused, "192.168.1.10"}
```

**Causes:**
- SSH server not running on target
- Wrong port
- Firewall blocking

**Solutions:**

```bash
# Test connectivity
nc -zv 192.168.1.10 22

# Check if SSH is running (on server)
sudo systemctl status sshd

# Check firewall (on server)
sudo ufw status
sudo iptables -L -n | grep 22

# Try different port
host :server, "deploy@192.168.1.10:2222"
```

### Connection Timeout

```
Error: {:connection_timeout, "192.168.1.10"}
```

**Causes:**
- Network unreachable
- Firewall dropping packets (not rejecting)
- VPN issues
- DNS resolution failing

**Solutions:**

```bash
# Test network
ping 192.168.1.10

# Test with TCP
nc -zv -w 10 192.168.1.10 22

# Increase timeout
config :nexus,
  connect_timeout: 30_000  # 30 seconds

# Check DNS
nslookup hostname.example.com
```

### Authentication Failed

```
Error: {:auth_failed, "192.168.1.10"}
```

**Causes:**
- Wrong SSH key
- Key not authorized on server
- Wrong username
- Key permissions wrong

**Solutions:**

```bash
# Test SSH directly with verbose output
ssh -vvv deploy@192.168.1.10

# Check which key is being used
ssh -v deploy@192.168.1.10 2>&1 | grep "Offering"

# Verify key is in authorized_keys on server
cat ~/.ssh/authorized_keys

# Check key permissions
ls -la ~/.ssh/
# Private keys should be 600
# .ssh directory should be 700

# Specify key explicitly
nexus run deploy -i ~/.ssh/specific_key
```

### Host Key Verification Failed

```
Host key verification failed.
```

**Cause:** Server's host key not in `known_hosts` or has changed.

**Solutions:**

```bash
# Add host key
ssh-keyscan -H 192.168.1.10 >> ~/.ssh/known_hosts

# If key legitimately changed, remove old and add new
ssh-keygen -R 192.168.1.10
ssh-keyscan -H 192.168.1.10 >> ~/.ssh/known_hosts
```

### SSH Agent Issues

```
Could not open a connection to your authentication agent.
```

**Solutions:**

```bash
# Start SSH agent
eval "$(ssh-agent -s)"

# Add key
ssh-add ~/.ssh/nexus_deploy

# Verify
ssh-add -l
echo $SSH_AUTH_SOCK
```

---

## Execution Issues

### Command Timeout

```
Error: {:command_timeout, "long_running_command"}
```

**Cause:** Command took longer than allowed timeout.

**Solutions:**

```elixir
# Increase command timeout
run "long_running_script.sh", timeout: 3_600_000  # 1 hour

# Or increase global timeout
config :nexus,
  command_timeout: 300_000  # 5 minutes
```

### Command Failed (Non-Zero Exit)

```
[FAILED] Task: deploy
  Host: web1 (failed)
    [x] $ deploy.sh
        Error: something went wrong
        (exit: 1, 234ms, attempts: 1)
```

**Cause:** Command returned non-zero exit code.

**Solutions:**

```bash
# Test command manually
ssh deploy@web1 'deploy.sh'
echo $?

# Check command output for errors
nexus run deploy --verbose

# Add error handling in script
run "deploy.sh || echo 'Deploy failed' && exit 1"

# Use retries for flaky commands
run "flaky_command.sh", retries: 3, retry_delay: 5_000
```

### Sudo Requires Password

```
Error: sudo: a password is required
```

**Cause:** Remote user needs password for sudo.

**Solutions:**

Configure passwordless sudo for specific commands:

```bash
# On the remote server, edit sudoers
sudo visudo

# Add line for deploy user (specific commands)
deploy ALL=(ALL) NOPASSWD: /bin/systemctl restart myapp, /bin/systemctl status myapp

# Or for all commands (less secure)
deploy ALL=(ALL) NOPASSWD: ALL
```

### Task Not Found

```
Error: Unknown tasks: deploy
```

**Cause:** Specified task doesn't exist in config.

**Solutions:**

```bash
# List available tasks
nexus list

# Check spelling
# Task names are atoms, case-sensitive

# Verify config file
nexus validate
```

---

## Output Issues

### No Output Displayed

**Cause:** Commands ran but output wasn't shown.

**Solutions:**

```bash
# Use verbose mode
nexus run deploy --verbose

# Check quiet mode isn't enabled
# Remove -q or --quiet flag

# For JSON output
nexus run deploy --format json
```

### Colors Not Displaying

**Cause:** Terminal doesn't support colors or `NO_COLOR` is set.

**Solutions:**

```bash
# Check NO_COLOR
echo $NO_COLOR

# Unset if needed
unset NO_COLOR

# Force colors (check terminal support)
TERM=xterm-256color nexus run deploy
```

### Output Garbled/Corrupted

**Cause:** Binary output or encoding issues.

**Solutions:**

```bash
# Use plain mode
nexus run deploy --plain

# Redirect output
nexus run deploy > output.log 2>&1
```

---

## Performance Issues

### Slow Execution

**Causes:**
- Many sequential connections
- Large parallel limit
- Network latency

**Solutions:**

```elixir
# Reduce parallel limit if overloading
nexus run deploy --parallel-limit 5

# Increase connection pool
config :nexus,
  max_connections: 20

# Use serial strategy for rolling deploys
task :deploy, on: :web, strategy: :serial do
  run "deploy.sh"
end
```

### Memory Issues

**Cause:** Too many concurrent connections.

**Solutions:**

```bash
# Reduce parallel limit
nexus run deploy --parallel-limit 5

# Reduce max connections per host
config :nexus,
  max_connections: 3
```

---

## Common Scenarios

### "Works in SSH but not in Nexus"

If a command works via manual SSH but fails in Nexus:

1. **Environment differences**: SSH login sessions may have different environment variables
   ```elixir
   # Explicitly set environment
   run "export PATH=/usr/local/bin:$PATH && my_command"
   ```

2. **Interactive vs non-interactive**: Some commands expect a terminal
   ```elixir
   # Force non-interactive
   run "DEBIAN_FRONTEND=noninteractive apt-get install -y package", sudo: true
   ```

3. **Shell differences**: Nexus uses `/bin/sh`, not your login shell
   ```elixir
   # Force bash if needed
   run "bash -c 'source ~/.bashrc && my_command'"
   ```

### "Preflight Passes but Deploy Fails"

Preflight only checks connectivity, not all command requirements.

```bash
# Run with verbose for more details
nexus run deploy --verbose

# Test commands individually
ssh deploy@server 'command1'
ssh deploy@server 'command2'
```

### "Task Runs on Wrong Hosts"

**Cause:** Wrong target specification or group membership.

```bash
# Check configuration
nexus list --format json | jq '.tasks[] | select(.name == "deploy")'

# Verify groups
nexus list --format json | jq '.groups'

# Use dry run
nexus run deploy --dry-run
```

---

## Debugging Tips

### Enable Verbose Output

```bash
nexus run deploy --verbose
```

### Use Dry Run

```bash
nexus run deploy --dry-run
```

### Test Manually

```bash
# Test SSH connection
ssh -v deploy@server 'echo test'

# Test specific command
ssh deploy@server 'exact_command_from_nexus.exs'
```

### Check Server Logs

```bash
# On the remote server
sudo tail -f /var/log/auth.log      # SSH auth issues
sudo journalctl -f                   # General system logs
sudo tail -f /var/log/syslog        # Syslog
```

### JSON Output for Parsing

```bash
# Capture structured output
nexus run deploy --format json > result.json

# Parse with jq
cat result.json | jq '.task_results[] | select(.status == "error")'
```

### Incremental Testing

```bash
# Test individual tasks
nexus run build
nexus run test
nexus run deploy

# Instead of
nexus run full_deploy
```

---

## Getting Help

If you're still stuck:

1. **Check the documentation:**
   - [Getting Started](getting-started.md)
   - [Configuration Reference](configuration.md)
   - [SSH Configuration](ssh.md)

2. **Validate your setup:**
   ```bash
   nexus validate
   nexus preflight deploy --verbose
   ```

3. **Search existing issues:**
   - [GitHub Issues](https://github.com/manav03panchal/nexus/issues)

4. **Open a new issue:**
   Include:
   - Nexus version (`nexus --version`)
   - Your `nexus.exs` (sanitized)
   - Full error message
   - Steps to reproduce
   - Output of `nexus preflight --verbose`

---

## See Also

- [Getting Started](getting-started.md) - Initial setup
- [Configuration Reference](configuration.md) - DSL documentation
- [SSH Configuration](ssh.md) - SSH details
- [Architecture](architecture.md) - Internal workings
