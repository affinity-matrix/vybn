---
title: VS Code & Cursor
description: Edit files on your vybn VM using VS Code or Cursor with Remote SSH.
---

Open your vybn VM as a remote workspace in VS Code or Cursor — one command, no manual SSH config.

## Prerequisites

- A deployed and running vybn VM (`vybn deploy`)
- **VS Code** with the [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) extension, **or Cursor** (has Remote SSH built in)

## Setup

```bash
vybn code
```

That's it. On first run, vybn:

1. Writes a managed SSH config block to `~/.ssh/config`
2. Detects your editor (Cursor or VS Code)
3. Opens it connected to the VM

If neither editor CLI is found, vybn writes the SSH config and prints manual instructions.

## How it works

vybn adds a `Host vybn` block to your `~/.ssh/config`:

```
# vybn-start — managed by vybn, do not edit
Host vybn
  HostName bright-falcon
  User claude
  IdentityFile ~/.vybn/ssh/id_ed25519
  UserKnownHostsFile ~/.vybn/ssh/known_hosts
  StrictHostKeyChecking accept-new
  ForwardAgent yes
  ServerAliveInterval 5
  ServerAliveCountMax 3
# vybn-end
```

The block is managed between `# vybn-start` / `# vybn-end` markers. vybn updates it when your configuration changes and removes it when you run `vybn destroy`.

The Remote SSH extension reads `~/.ssh/config` and sees `vybn` as a connectable host.

## Opening specific projects

```bash
# Open a session's registered directory
vybn code myproject

# Open an explicit path
vybn code --path /opt/app

# No args — auto-detects from current directory name
vybn code
```

With no arguments, vybn checks if `basename $PWD` matches a session name on the VM. If it does, it prompts to open that path. Otherwise it opens `$VYBN_PROJECTS_DIR`.

## Editor selection

vybn auto-detects your editor — it looks for `cursor` first, then `code` in your PATH.

To choose explicitly, set `VYBN_EDITOR` in `~/.vybnrc`:

```bash
VYBN_EDITOR="code"     # Always use VS Code
VYBN_EDITOR="cursor"   # Always use Cursor
```

## Backend-specific notes

### Tailscale

Works out of the box. The SSH config uses your Tailscale hostname and vybn-managed SSH keys.

### IAP

The SSH config uses a `ProxyCommand` that invokes `gcloud compute ssh` with `--tunnel-through-iap`. This requires `gcloud` to be installed and authenticated on your local machine.

```
ProxyCommand gcloud compute ssh %r@vm-name --zone=us-west1-a --project=my-project --tunnel-through-iap --plain -- -W %h:%p
```

### SSH provider

Uses your configured `VYBN_SSH_HOST`, `VYBN_SSH_PORT`, and `VYBN_SSH_KEY` directly.

## Troubleshooting

### Verify SSH connectivity

Before debugging the editor, confirm that raw SSH works:

```bash
ssh vybn
```

If this connects successfully, the issue is with the editor extension, not the SSH config.

### Check the SSH config

```bash
# View the managed block
sed -n '/vybn-start/,/vybn-end/p' ~/.ssh/config
```

### Extension not connecting

- Make sure the Remote SSH extension is installed (VS Code) or up to date (Cursor)
- Try the VS Code command palette: **Remote-SSH: Connect to Host...** and select `vybn`
- Check the Remote SSH output panel for error details

### Regenerate SSH config

If the config is stale or corrupted, just run `vybn code` again — it rewrites the block if anything has changed.
