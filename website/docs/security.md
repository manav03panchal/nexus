---
sidebar_position: 8
---

# Security

This document describes the security model and best practices for Nexus.

## DSL Security Model

:::warning Important
Nexus DSL files (e.g., `nexus.exs`) are **executable Elixir code**. When you run `nexus run`, the DSL file is evaluated, which means any Elixir code in the file will be executed.
:::

### Implications

- **Only run DSL files from sources you trust**
- Treat DSL files like shell scripts or other executable code
- Review DSL files before running them, especially from external sources
- Consider code review requirements for DSL changes in production environments

### What the DSL Can Do

Since DSL files are full Elixir code, they can:
- Execute arbitrary shell commands via `System.cmd/3`
- Read and write files via the `File` module
- Make network requests
- Access environment variables
- Import and execute other Elixir code

This is by design - it allows powerful dynamic configuration. However, it means you should treat DSL files with the same caution as any executable code.

## SSH Security

### Host Key Verification

By default, Nexus verifies SSH host keys and will reject connections to unknown hosts. This protects against Man-in-the-Middle (MITM) attacks.

```bash
# Secure default - verifies host keys
nexus run deploy

# Insecure mode - only use when you understand the risks
nexus run deploy --insecure
```

:::caution
Only use `--insecure` when you understand the risks:
- CI/CD environments with ephemeral hosts
- Initial setup before host keys are known
- Isolated test environments

Never use `--insecure` in production without additional network security.
:::

### SSH Key File Permissions

Nexus validates that SSH private key files have secure permissions. Keys with group or world-readable permissions will be rejected:

```bash
# This will fail if key has insecure permissions
nexus run deploy -i ~/.ssh/my_key

# Fix permissions
chmod 600 ~/.ssh/my_key
```

Valid permissions are:
- `0600` - Owner read/write only
- `0400` - Owner read only

### Password Authentication

Password authentication is supported but discouraged for automated deployments:

```bash
# Interactive password prompt
nexus run deploy --password -

# Password from environment (less secure)
nexus run deploy --password "$SSH_PASSWORD"
```

**Prefer SSH key authentication with:**
- Ed25519 keys (recommended)
- ECDSA keys
- RSA keys (2048+ bits)

## Secrets Management

### Encrypted Vault

Nexus provides an encrypted secrets vault for sensitive credentials:

```bash
# Initialize the vault (creates master key)
nexus secret init

# Store a secret
nexus secret set API_KEY

# Use in DSL
env: %{"API_KEY" => secret("API_KEY")}
```

Secrets are encrypted using:
- **AES-256-GCM** for encryption
- **PBKDF2** with 100,000 iterations for key derivation
- Random 256-bit salt per encryption

### Master Key Security

The master key file (`~/.nexus/master.key`) must be protected:

```bash
# Verify permissions
ls -la ~/.nexus/master.key
# Should show: -rw------- (0600)

# Fix if needed
chmod 600 ~/.nexus/master.key
```

**Best practices:**
- Add `master.key` to `.gitignore`
- In CI/CD, inject via environment variable
- Rotate periodically
- Back up securely

## Path Security

### Path Traversal Protection

Nexus validates paths in `upload`, `download`, and `template` commands to prevent path traversal attacks:

```elixir
# This will be rejected during validation
upload "../../../etc/passwd", "/tmp/test"

# Error: upload in task :example has path traversal in local_path
```

Paths containing `..` components are rejected during configuration validation.

### Artifact Storage

Artifact names are validated to contain only safe characters:
- Alphanumeric characters
- Dash (`-`)
- Underscore (`_`)
- Dot (`.`)

Directory separators are not allowed in artifact names.

## Privilege Escalation

### Sudo Handling

Nexus uses `sudo -n` (non-interactive mode) by default:

```elixir
# If NOPASSWD is not configured, this fails immediately
# rather than hanging on a password prompt
command "systemctl restart nginx", sudo: true
```

**Configure NOPASSWD for automation:**

```sudoers
# /etc/sudoers.d/deploy
deploy ALL=(ALL) NOPASSWD: /bin/systemctl restart nginx
deploy ALL=(ALL) NOPASSWD: /bin/systemctl restart myapp
```

### Sudo User Validation

Sudo usernames are validated against a strict pattern to prevent command injection:

```elixir
# Valid
command "whoami", sudo: true, user: "www-data"

# Invalid - will raise an error
command "whoami", sudo: true, user: "root; malicious"
```

## Secure Defaults

Nexus is configured with secure defaults:

| Setting | Default | Notes |
|---------|---------|-------|
| Host key verification | Enabled | Use `--insecure` to disable |
| SSH key permissions | Validated | Keys with insecure permissions are rejected |
| Path traversal check | Enabled | Paths with `..` are rejected |
| Sudo mode | Non-interactive | Fails fast if password required |
| Temp file names | Cryptographic random | Prevents prediction attacks |

## Security Checklist

Before deploying to production:

- [ ] DSL files are from trusted sources and reviewed
- [ ] SSH keys have `0600` permissions
- [ ] Master key is excluded from version control
- [ ] NOPASSWD is configured for required sudo commands
- [ ] Host keys are verified (not using `--insecure`)
- [ ] Secrets are stored in the vault, not in DSL files
- [ ] Remote hosts have minimal required permissions
- [ ] SSH access is limited to deployment user

## Reporting Security Issues

If you discover a security vulnerability, please report it responsibly:

1. **Do not** open a public GitHub issue
2. Email the maintainers directly
3. Include details to reproduce the issue
4. Allow time for a fix before public disclosure

## See Also

- [SSH Configuration](ssh.md) - SSH authentication details
- [Configuration Reference](configuration.md) - DSL documentation
- [Troubleshooting](troubleshooting.md) - Common issues and solutions
