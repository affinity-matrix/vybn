---
title: Getting Started
description: Install vybn and deploy your first cloud VM with Claude Code.
---

## Prerequisites

Need help setting these up? See the [Prerequisites guide](/guides/prerequisites/) for a full walkthrough.

- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (`gcloud`) — authenticated with a project
- SSH client — comes with macOS/Linux
- A GCP project with billing enabled
- [Tailscale](https://tailscale.com/download) — installed and logged in on your local machine
- A Tailscale auth key — generate at the [admin console](https://login.tailscale.com/admin/settings/keys)

:::note[Using IAP instead of Tailscale?]
For IAP networking (alternative to Tailscale): no additional prerequisites beyond `gcloud`. See the [IAP Setup guide](/guides/iap/).
:::

## Installation

Clone the repo and run the installer:

```bash
git clone https://github.com/affinity-matrix/vybn.git
cd vybn && ./install.sh
```

The installer will offer to set up **tab completion** for bash or zsh. If you skip it, you can add completions manually later:

```bash
# Bash
echo 'source /path/to/vybn/completions/vybn.bash' >> ~/.bashrc

# Zsh
echo 'source /path/to/vybn/completions/vybn.zsh' >> ~/.zshrc
```

Or symlink manually (without the installer):

```bash
ln -s "$(pwd)/vybn/vybn" /usr/local/bin/vybn
```

## Upgrading

Pull the latest changes and re-run the installer:

```bash
cd ~/vybn && git pull && ./install.sh
```

The symlink approach means the new version takes effect immediately.

## Uninstalling

```bash
./install.sh --uninstall
```

Removes the `/usr/local/bin/vybn` symlink and optionally cleans up `~/.vybn/`.

:::tip
Run `vybn check` after installation to verify all prerequisites are met before deploying.
:::

## Quick Start

vybn uses Tailscale by default, giving you access from any device on your tailnet — laptops, phones, tablets.

```bash
# 1. Run the setup wizard (picks network, project, machine type, etc.)
vybn init

# 2. Deploy — the VM joins your tailnet automatically
vybn deploy

# 3. Connect
vybn connect
```

The wizard asks for your Tailscale auth key, GCP project, machine type, and other settings. It writes a validated `~/.vybnrc` for you.

After deploy, the VM is reachable from any device on your tailnet — including iOS via [Termius](https://termius.com/) or any SSH client.

:::tip
You can combine deploy and connect into one command with `vybn deploy --connect`.
:::

## Quick Start (IAP)

IAP tunnels SSH through Google's infrastructure using your `gcloud` credentials — no Tailscale account needed.

```bash
# 1. Run the setup wizard and select "iap" as the network backend
vybn init

# 2. Deploy a VM
vybn deploy

# 3. Connect
vybn connect
```

`vybn init` handles the network choice — select `iap` when prompted for the network backend.

## What happens on deploy

When you run `vybn deploy`, the following happens:

1. A GCP VM is created running Ubuntu 24.04
2. A startup script installs Claude Code CLI (native binary with checksum verification), selected toolchains (Node.js by default), and tmux
3. Any extra apt/npm packages from your config are installed
4. Network infrastructure is configured (Tailscale enrollment or IAP firewall rules)
5. The VM becomes reachable via the selected network backend

After deploy completes, run `vybn connect` to drop into a tmux session. Claude Code will prompt you to log in on first launch.

## Sessions persist across disconnects

Everything runs inside a tmux session on the VM. Close your laptop, switch Wi-Fi, or reboot — your session keeps running. Reconnect whenever you're ready:

```bash
vybn connect
```

You're back exactly where you left off: same output, same running processes, same Claude Code conversation.

## Working on multiple projects

Use `vybn session` to create named windows, each running Claude Code in its own directory:

```bash
vybn session frontend ~/projects/frontend
vybn session backend ~/projects/backend
```

Later, jump straight to the one you need:

```bash
vybn connect frontend
```

Inside the session, switch between windows with `Ctrl-b n` / `Ctrl-b p`, or jump by number with `Ctrl-b 1`, `Ctrl-b 2`, etc. See [Working with tmux](/guides/tmux/) for more shortcuts.
