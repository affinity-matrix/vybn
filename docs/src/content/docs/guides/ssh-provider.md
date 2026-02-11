---
title: SSH Provider
description: Deploy vybn to an existing server you manage.
---

The SSH provider deploys Claude Code to a server you already have — no cloud account or API required. vybn uploads and runs the setup script over SSH, then connects through Tailscale like any other vybn VM.

## When to use the SSH provider

- You have existing servers (cloud VMs, bare metal, on-prem)
- You're on a non-GCP cloud (AWS, Azure, Hetzner, etc.)
- You want full control over the server's lifecycle and configuration
- You want to avoid GCP billing or `gcloud` dependencies

## Server requirements

- **OS:** Ubuntu 22.04+, Ubuntu 24.04, or Debian 12+
- **Access:** root, or a user with passwordless sudo
- **Network:** outbound internet access (to install packages and connect to Tailscale)
- **SSH:** reachable from your local machine

The setup script installs Claude Code, tmux, Tailscale, and selected toolchains — same as the GCP provider.

## Step-by-step

### 1. Configure

Run the setup wizard and select `ssh` as the provider:

```bash
vybn init
```

The wizard prompts for:
- **Server hostname or IP** — where to connect via SSH
- **SSH user** — must have root or sudo access
- **SSH key** — path to your private key (blank to use SSH agent)
- **SSH port** — defaults to 22
- **Tailscale auth key** — for enrolling the server on your tailnet

Or configure manually in `~/.vybnrc`:

```bash
# ~/.vybnrc
VYBN_PROVIDER="ssh"
VYBN_SSH_HOST="dev.example.com"
VYBN_SSH_USER="ubuntu"
VYBN_SSH_KEY="$HOME/.ssh/id_ed25519"
VYBN_TAILSCALE_AUTHKEY="tskey-auth-..."
```

### 2. Verify prerequisites

```bash
vybn check
```

This tests SSH connectivity to the server, validates your Tailscale auth key, and confirms the setup script exists for the `ssh-tailscale` combination.

### 3. Deploy

```bash
vybn deploy
```

vybn assembles the setup script locally, uploads it to the server via SCP, and executes it over SSH. The script installs everything and enrolls the server on your tailnet. After setup completes, vybn waits for the server to become reachable via Tailscale.

### 4. Connect

```bash
vybn connect
```

You're in a persistent tmux session with Claude Code, connected through Tailscale.

## How it works

1. **Script assembly** — the setup script is built locally from `base.sh`, toolchain modules, and `ssh-tailscale.sh`, with your config baked into the header
2. **Bootstrap SSH** — vybn connects to the server using the credentials you provided (`VYBN_SSH_HOST`, `VYBN_SSH_USER`, etc.) and uploads the script via SCP
3. **Setup execution** — the script runs on the server with sudo, installing Claude Code, tmux, toolchains, and Tailscale
4. **Tailscale enrollment** — the server joins your tailnet, making it reachable from any device
5. **Ongoing access** — all subsequent connections (`vybn connect`, `vybn ssh`, etc.) go through Tailscale, not the bootstrap SSH connection

## What `destroy` does

Running `vybn destroy` with the SSH provider:

- Deregisters the server from your Tailscale tailnet
- Cleans up local state files (`~/.vybn/ssh-provider-deployed`, etc.)

It does **not** delete or modify the remote server. The server continues running with all installed software intact.

## Differences from GCP

| | GCP | SSH |
|---|---|---|
| VM creation | vybn creates and manages the VM | You provide the server |
| `start`/`stop` | Available — manages VM power state | Not available — manage the server directly |
| `destroy` | Deletes VM and boot disk | Deregisters Tailscale, cleans local state |
| Cost estimate | Shown before deploy | Not applicable — you manage billing |
| Network backends | Tailscale or IAP | Tailscale only |
| `--script-only` | Outputs the setup script | Outputs the setup script |

## Tips

- Use `vybn deploy --script-only` to inspect the assembled setup script before running it on your server
- The setup log is written to `/var/log/vybn-setup.log` on the server — check it with `vybn logs` after deploy
- You can redeploy to the same server by running `vybn destroy` (to clean up Tailscale) followed by `vybn deploy`
