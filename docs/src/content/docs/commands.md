---
title: Commands
description: Complete reference for all vybn CLI commands.
---

## Overview

| Command | Description |
|---------|-------------|
| `vybn init [--force]` | Interactive configuration wizard |
| `vybn deploy [--connect] [-y]` | Create the VM with Claude Code pre-installed |
| `vybn connect [window]` | SSH + tmux attach (optionally to a specific window) |
| `vybn session <name> [path]` | Create a new Claude Code tmux window |
| `vybn sync-skills` | Copy installed Claude Code skills to the VM |
| `vybn start` | Start a stopped VM |
| `vybn stop [-y]` | Stop the VM (preserves disk) |
| `vybn destroy [-y]` | Delete VM and network infrastructure |
| `vybn status` | Show VM state and tmux sessions |
| `vybn check` | Validate prerequisites before deploying |
| `vybn ssh [--batch] [command]` | Raw SSH to the VM |
| `vybn add-key <key\|opts>` | Add SSH public key(s) to the VM |
| `vybn tunnel <port> [local]` | Forward a TCP port (background); also: `list`, `kill` |
| `vybn update [version]` | Update Claude Code on the VM |
| `vybn logs` | View the VM setup log |
| `vybn switch-network <backend>` | Switch the network backend on a running VM |
| `vybn version` | Show version |
| `vybn help` | Show usage |

Use `vybn <command> --help` for details on any command.

## init

Interactive configuration wizard. Walks through every setting and writes a validated `~/.vybnrc`.

```bash
vybn init
```

**Options:**

- `-f, --force` — back up and overwrite existing `~/.vybnrc` without prompting

The wizard prompts for:
- Network backend (Tailscale or IAP)
- GCP project and zone
- VM name, machine type, and disk size
- Tailscale auth key (if using Tailscale)
- Toolchains, extra packages, and custom setup scripts

Re-run `vybn init` to update your configuration — existing values are pre-filled as defaults.

## deploy

Create a new VM with Claude Code pre-installed.

```bash
vybn deploy
```

**Options:**

- `-y, --yes` — skip the confirmation prompt
- `--connect` — after deploy completes, attach to the tmux session

Before creating the VM, `deploy` shows a summary with estimated monthly cost (based on the selected machine type and disk size) and asks for confirmation. Use `-y` to skip this.

This provisions a GCP VM, runs the setup script (installs Claude Code native binary, selected toolchains, extra packages, tmux), and configures the network backend. The VM is ready to use once the command completes.

## connect

Attach to the tmux session on the VM. If the session doesn't exist, one is created automatically.

```bash
# Attach to the default session
vybn connect

# Attach and jump to a named window (created if it doesn't exist)
vybn connect myproject
```

The `[window]` argument is a shortcut: if a window with that name already exists, `connect` selects it; if it doesn't, `connect` creates it and then attaches. This means you can always run `vybn connect myproject` without worrying about whether the window is there yet.

Because sessions are persistent on the VM, you can close your laptop, switch networks, or even reboot your local machine — then `vybn connect` picks up exactly where you left off.

## session

Create a new tmux window with Claude Code running in a specific directory.

```bash
# New window named "backend" in the default home directory
vybn session backend

# New window with a specific working directory
vybn session backend ~/projects/backend
```

Each window runs an independent Claude Code instance, so you can work on multiple projects simultaneously. Pair this with `connect` to jump between them:

```bash
# Set up two project windows
vybn session frontend ~/projects/frontend
vybn session backend ~/projects/backend

# Later, reconnect straight to the one you need
vybn connect backend
```

## sync-skills

Copy your locally installed Claude Code skills to the VM.

```bash
vybn sync-skills
```

Syncs all skill directories from `~/.claude/skills/` on your local machine to the VM. Run this after installing or updating skills locally.

## start

Start a stopped VM. Waits until the VM is reachable via SSH before returning.

```bash
vybn start
```

## stop

Stop the VM to save on compute costs. Disk is preserved.

```bash
vybn stop
```

**Options:**

- `-y, --yes` — skip the confirmation prompt

:::note
tmux sessions run in memory and don't survive a stop/start cycle. Your repos and files on disk persist. Create new sessions with `vybn connect` or `vybn session` after restarting.
:::

## destroy

Delete the VM and all associated network infrastructure.

```bash
vybn destroy
```

**Options:**

- `-y, --yes` — skip the confirmation prompt (which normally requires typing the VM name)

:::caution
This deletes the VM's boot disk and all data on it. This action is not reversible.
:::

## status

Show the VM's current state and list active tmux sessions.

```bash
vybn status
```

## check

Validate that all prerequisites are met before deploying.

```bash
vybn check
```

Runs all checks and reports pass/fail for each:
- gcloud CLI installed
- gcloud authenticated (prints account)
- GCP project configured (prints project ID)
- Compute Engine API enabled
- Network-specific checks (Tailscale CLI, auth key, etc.)
- VM setup script exists for the provider/network combination

Exits 0 if all checks pass, 1 if any fail. Run this before `vybn deploy` to catch configuration issues early.

## ssh

Raw SSH passthrough to the VM. Useful for running one-off commands.

```bash
# Interactive shell
vybn ssh

# Run a command
vybn ssh 'cat /var/log/vybn-setup.log'

# Batch mode (no PTY, no interactive prompts — useful in scripts)
vybn ssh --batch 'cat /etc/os-release'
```

**Options:**

- `-b, --batch` — batch mode: disables PTY allocation and interactive prompts, suitable for scripted use

## tunnel

Forward TCP ports from the VM to your local machine. Tunnels run in the background by default and are tracked so you can list and kill them.

### Open a tunnel

```bash
# Background (default): returns immediately, tunnel runs in background
vybn tunnel 8080              # localhost:8080 -> VM:8080
vybn tunnel 3000 9000         # localhost:9000 -> VM:3000

# Foreground: blocks until Ctrl-C (useful for quick one-off tunnels)
vybn tunnel 8080 -f
```

If the local port is omitted, it defaults to the same as the remote port.

### List active tunnels

```bash
vybn tunnel list
```

Shows all tracked tunnels with their local port, remote port, VM name, PID, and uptime. Stale entries (where the process has exited) are cleaned up automatically.

### Kill tunnels

```bash
# Stop a specific tunnel by local port
vybn tunnel kill 8080

# Stop all tunnels
vybn tunnel kill all
```

## add-key

Add SSH public key(s) to the VM's `authorized_keys`. Three modes are available:

### From SSH.id

Fetch public keys from [sshid.io](https://sshid.io/), which exposes device-bound keys from Termius. This is the easiest way to authorize mobile devices.

```bash
vybn add-key --sshid johndoe
```

The fetch happens on your local machine (not the VM), so this works even if the VM has restricted outbound access.

### From a file

Read one or more keys from a local file (one per line, blank lines and `#comments` are skipped):

```bash
vybn add-key --file ~/.ssh/id_ed25519.pub
```

### Inline key

Pass a single public key directly:

```bash
vybn add-key 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... user@device'
```

Duplicate keys are detected and skipped. All keys are validated against standard SSH public key format before being added.

## update

Update Claude Code on the VM.

```bash
# Update to the latest version
vybn update

# Install a specific version
vybn update 2.1.38
```

For `latest`, this uses `claude update`. For a specific version, it uses the native installer (`claude.ai/install.sh`). The `/usr/local/bin/claude` symlink is updated automatically.

## logs

View the VM's setup log (`/var/log/vybn-setup.log`). Useful for debugging deploy issues or checking what the startup script did.

```bash
# Last 50 lines (default)
vybn logs

# Last 100 lines
vybn logs -n 100

# Follow in real time (Ctrl-C to stop)
vybn logs -f
```

## switch-network

Switch the network backend on a running VM. This reconfigures the VM in-place without redeploying.

```bash
# Switch from Tailscale to IAP
vybn switch-network iap

# Switch from IAP to Tailscale
vybn switch-network tailscale
```

The command handles all the necessary setup on the VM (installing Tailscale, updating firewall rules, etc.) and updates `~/.vybnrc` to persist the change.
