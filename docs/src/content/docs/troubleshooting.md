---
title: Troubleshooting
description: Common issues and how to resolve them.
---

## First Steps

Before diving into specific issues, run the preflight check:

```bash
vybn check
```

This validates gcloud authentication, project configuration, API access, and network-specific prerequisites. It often catches the root cause immediately.

### Enable verbose output

Add `--verbose` to any command to enable shell trace output (`set -x`). This shows every command as it executes, which is useful for diagnosing failures:

```bash
vybn --verbose deploy
vybn --verbose connect
```

You can also set `VYBN_VERBOSE=true` in `~/.vybnrc` to enable it permanently.

## General

### SSH connection timeout

The VM may still be starting up. Wait and retry, or check its state:

```bash
vybn status
```

### Startup script not completing

If deploy times out, vybn automatically prints the last 30 lines of the setup log. To view the full log:

```bash
vybn ssh 'cat /var/log/vybn-setup.log'
```

### tmux sessions lost after stop/start

This is expected. tmux runs in memory and doesn't survive VM shutdown. Your repos and files on disk persist. Create new sessions after restarting:

```bash
vybn connect
# or
vybn session myproject
```

## Tailscale Issues

### "Tailscale is not running or not logged in"

Start Tailscale on your local machine:

```bash
tailscale up
```

### Deploy times out waiting for SSH

The auth key may be invalid or expired. Generate a new one at the [Tailscale admin console](https://login.tailscale.com/admin/settings/keys).

You can also check the startup log directly:

```bash
# GCP provider — via GCP serial console
gcloud compute ssh root@<vm-name> -- cat /var/log/vybn-setup.log

# SSH provider — via bootstrap SSH
ssh user@your-server cat /var/log/vybn-setup.log
```

### "Host key verification failed"

After redeploying, the host key changes. `vybn deploy` clears stale entries automatically, but if it persists:

```bash
ssh-keygen -R <hostname> -f ~/.vybn/ssh/known_hosts
```

### VM not visible on tailnet after stop/start

Tailscale reconnects automatically but it may take a moment. Check with:

```bash
tailscale status
```

### Connecting from iOS

1. Install the [Tailscale app](https://apps.apple.com/app/tailscale/id1470499037) and join the same tailnet
2. Use any SSH client (e.g., [Termius](https://termius.com/)) to connect to `claude@<petname>` (the Tailscale hostname shown during deploy)
3. Import the private key from `~/.vybn/ssh/id_ed25519` into the SSH client

## IAP Issues

### "gcloud credentials are expired"

Re-authenticate with the Google Cloud SDK:

```bash
gcloud auth login
```

## SSH Provider Issues

### "VYBN_SSH_HOST is not set"

Set the host in `~/.vybnrc` or run `vybn init` to configure the SSH provider:

```bash
vybn init
```

### Cannot connect to server via SSH

Verify you can reach the server directly:

```bash
ssh -o ConnectTimeout=10 user@your-server
```

Common causes:
- Wrong hostname, user, port, or key path
- Server firewall blocking your IP
- SSH service not running on the server

### Setup script fails on the server

The setup script requires root or sudo access. Check the log:

```bash
ssh user@your-server cat /var/log/vybn-setup.log
```

Ensure the server runs Ubuntu 22.04+, Ubuntu 24.04, or Debian 12+.

### "VM lifecycle is managed externally"

`vybn start` and `vybn stop` are not available for the SSH provider. Start and stop your server directly through your hosting provider or OS tools.

## Toolchain Issues

### "Unknown toolchain" error

The toolchain name must exactly match a file in `vm-setup/toolchains/`. Valid names are:

- `node`
- `python`
- `rust`
- `go`
- `docker`

Common mistakes: `nodejs` instead of `node`, `golang` instead of `go`, or uppercase names like `Node`. Names are case-sensitive and must be lowercase.

### Claude Code checksum verification failed

The downloaded binary didn't match the SHA-256 hash in Anthropic's manifest. This usually means a transient download error.

**Fix:** Re-run `vybn deploy` (or `vybn update`). The installer retries the download.

If the manifest itself is unreachable (e.g., network issue), the installer logs a warning and continues without verification. Check `vybn logs` for details.
