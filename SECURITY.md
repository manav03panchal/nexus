# Security Model

This document describes the security model and considerations for Nexus.

## DSL Security

**Important**: Nexus DSL files (e.g., `nexus.exs`) are **executable Elixir code**. When you run `nexus run`, the DSL file is evaluated using `Code.eval_string/3`, which means any Elixir code in the file will be executed.

### Implications

- Only run DSL files from sources you trust
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

- Use `--insecure` flag only when you understand the risks (e.g., in CI environments with ephemeral hosts)
- Host keys are verified against the system's `~/.ssh/known_hosts` file

### SSH Key File Permissions

Nexus validates that SSH private key files have secure permissions (mode 0600 or 0400). Keys with group or world-readable permissions will be rejected.

### Password Authentication

Password authentication is supported but discouraged for automated deployments. Prefer SSH key authentication with:
- Ed25519 keys (recommended)
- ECDSA keys
- RSA keys (2048+ bits)

## Path Security

### Path Traversal Protection

Nexus validates paths in `upload`, `download`, and `template` commands to prevent path traversal attacks. Paths containing `..` components are rejected during configuration validation.

### Artifact Storage

Artifact names are validated to contain only safe characters (alphanumeric, dash, underscore, dot) and cannot contain directory separators.

## Privilege Escalation

### Sudo Handling

- Nexus uses `sudo -n` (non-interactive mode) to prevent hanging on password prompts
- Sudo usernames are validated against a strict pattern to prevent command injection
- If sudo requires a password and NOPASSWD is not configured, the command will fail immediately

## Secrets Management

### Vault Encryption

Secrets stored via `nexus secret set` are encrypted using:
- AES-256-GCM for encryption
- PBKDF2 with 100,000 iterations for key derivation
- Random 256-bit salt per encryption

### Master Key Security

- The master key file (`~/.nexus/master.key`) must have mode 0600
- The key should be excluded from version control (add to `.gitignore`)
- In CI/CD environments, inject the key via environment variables

## Secure Defaults

Nexus is configured with secure defaults:

| Setting | Default | Notes |
|---------|---------|-------|
| Host key verification | Enabled | Use `--insecure` to disable |
| SSH key permissions | Validated | Keys with insecure perms rejected |
| Path traversal check | Enabled | `..` paths rejected |
| Sudo mode | Non-interactive | Fails fast if password required |

## Reporting Security Issues

If you discover a security vulnerability, please report it responsibly by emailing the maintainers directly rather than opening a public issue.

## Security Checklist for Deployments

- [ ] DSL files are from trusted sources and reviewed
- [ ] SSH keys have 0600 permissions
- [ ] Master key is excluded from version control
- [ ] NOPASSWD is configured for sudo commands (if used)
- [ ] Host keys are verified (not using `--insecure` in production)
- [ ] Secrets are stored in the vault, not in DSL files
