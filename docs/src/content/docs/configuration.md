---
title: Configuration
description: All vybn configuration options and how to set them.
---

The easiest way to configure vybn is with the init wizard:

```bash
vybn init
```

This walks you through network backend, GCP project, machine type, Tailscale auth key, and other settings, then writes `~/.vybnrc` for you.

You can also create the file manually from the included template:

```bash
cp vybnrc.example ~/.vybnrc
```

All settings can also be set as environment variables.

## General Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `VYBN_PROVIDER` | `gcp` | Cloud provider backend |
| `VYBN_NETWORK` | `tailscale` | Network backend (`tailscale` or `iap`) |
| `VYBN_VM_NAME` | *(auto-generated petname)* | VM instance name (`claude-<adj>-<animal>`) |
| `VYBN_ZONE` | `us-west1-a` | GCP zone |
| `VYBN_MACHINE_TYPE` | `e2-standard-2` | Machine type (CPU/RAM) |
| `VYBN_DISK_SIZE` | `30` | Boot disk size in GB |
| `VYBN_USER` | `claude` | VM user account |
| `VYBN_PROJECT` | *(auto-detected)* | GCP project ID |
| `VYBN_TMUX_SESSION` | `claude` | tmux session name |
| `VYBN_TERM` | `xterm-256color` | Terminal type for tmux sessions |
| `VYBN_EXTERNAL_IP` | `false` | Assign public IP to VM (forced `true` for Tailscale) |
| `VYBN_QUIET` | `false` | Suppress info/success output (`--quiet` flag) |
| `VYBN_VERBOSE` | `false` | Enable trace output (`--verbose` flag) |

## GCP Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `VYBN_GCP_SCOPES` | `compute-ro,logging-write,storage-ro` | GCP API scopes assigned to the VM |

## Claude Code

| Variable | Default | Description |
|----------|---------|-------------|
| `VYBN_CLAUDE_CODE_VERSION` | `2.1.38` | Claude Code version to install (native binary) |

## Toolchains

| Variable | Default | Description |
|----------|---------|-------------|
| `VYBN_TOOLCHAINS` | `node` | Comma-separated toolchain modules to install |
| `VYBN_APT_PACKAGES` | *(none)* | Extra apt packages to install on the VM |
| `VYBN_NPM_PACKAGES` | *(none)* | Extra global npm packages (requires `node` toolchain) |
| `VYBN_SETUP_SCRIPT` | *(none)* | Path to a custom setup script to run after all setup |

Available toolchains: `node`, `python`, `rust`, `go`, `docker`.

## Tailscale Settings

These apply when using the default Tailscale network backend.

| Variable | Default | Description |
|----------|---------|-------------|
| `VYBN_TAILSCALE_AUTHKEY` | *(none, required)* | Auth key for VM enrollment on your tailnet |
| `VYBN_TAILSCALE_HOSTNAME` | *(auto-generated petname)* | Tailscale device hostname (e.g., `claude-bright-falcon`) |
| `VYBN_TAILSCALE_TAGS` | *(none)* | ACL tags (e.g., `tag:vybn`) |
| `VYBN_SSH_KEY_DIR` | `~/.vybn/ssh` | Directory for vybn-managed SSH keys |
| `VYBN_SSHID` | *(none)* | [SSH.id](https://sshid.io/) username — imports mobile device keys at deploy time |

## Machine Types

Pick a machine type based on your workload:

### Shared-core (burstable)

| Machine Type | vCPUs | RAM | ~Cost (24/7) |
|-------------|-------|-----|-------------|
| `e2-micro` | 0.25 | 1 GB | ~$6/month |
| `e2-small` | 0.5 | 2 GB | ~$12/month |
| `e2-medium` | 1 | 4 GB | ~$25/month |

### Standard (balanced)

| Machine Type | vCPUs | RAM | ~Cost (24/7) |
|-------------|-------|-----|-------------|
| `e2-standard-2` | 2 | 8 GB | ~$49/month |
| `e2-standard-4` | 4 | 16 GB | ~$97/month |
| `e2-standard-8` | 8 | 32 GB | ~$194/month |
| `e2-standard-16` | 16 | 64 GB | ~$388/month |

### High-memory

| Machine Type | vCPUs | RAM | ~Cost (24/7) |
|-------------|-------|-----|-------------|
| `e2-highmem-2` | 2 | 16 GB | ~$66/month |
| `e2-highmem-4` | 4 | 32 GB | ~$131/month |
| `e2-highmem-8` | 8 | 64 GB | ~$262/month |
| `e2-highmem-16` | 16 | 128 GB | ~$524/month |

### High-CPU

| Machine Type | vCPUs | RAM | ~Cost (24/7) |
|-------------|-------|-----|-------------|
| `e2-highcpu-2` | 2 | 2 GB | ~$36/month |
| `e2-highcpu-4` | 4 | 4 GB | ~$73/month |
| `e2-highcpu-8` | 8 | 8 GB | ~$146/month |
| `e2-highcpu-16` | 16 | 16 GB | ~$292/month |

### N2 (newer generation)

| Machine Type | vCPUs | RAM | ~Cost (24/7) |
|-------------|-------|-----|-------------|
| `n2-standard-2` | 2 | 8 GB | ~$57/month |
| `n2-standard-4` | 4 | 16 GB | ~$113/month |
| `n2-standard-8` | 8 | 32 GB | ~$226/month |

Disk storage costs ~$0.17/GB/month regardless of whether the VM is running.

:::tip
Stop the VM when not in use (`vybn stop`). A stopped VM costs nothing for compute — you only pay for disk (~$5.10/month for 30 GB).
:::

## Example Configuration

```bash
# ~/.vybnrc

# Tailscale auth key (required for deploy)
VYBN_TAILSCALE_AUTHKEY="tskey-auth-..."

# Import mobile SSH keys from SSH.id at deploy time
VYBN_SSHID="your-sshid-username"

# Bigger machine for heavy workloads
VYBN_MACHINE_TYPE="e2-standard-4"

# Deploy in Europe
VYBN_ZONE="europe-west1-b"

# Custom VM name
VYBN_VM_NAME="claude-work"
```

### Custom Setup Script

For project-specific configuration beyond packages and toolchains, point `VYBN_SETUP_SCRIPT` to a local shell script:

```bash
# ~/.vybnrc
VYBN_SETUP_SCRIPT="$HOME/.vybn/setup.sh"
```

The script runs after all standard setup, in a subshell with `set +e` so failures don't abort the deploy. Use it for cloning repos, installing project dependencies, or any other custom configuration. See the [Toolchains guide](/guides/toolchains/#custom-setup-script) for examples.

### Multi-Toolchain Setup

```bash
# ~/.vybnrc

# Install Node.js, Python, and Rust
VYBN_TOOLCHAINS="node,python,rust"

# Extra system packages
VYBN_APT_PACKAGES="ripgrep fd-find sqlite3"

# Extra npm packages (requires node toolchain)
VYBN_NPM_PACKAGES="typescript tsx"
```
