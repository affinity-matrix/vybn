---
title: Mobile SSH
description: Access your vybn VM from iOS and Android using Tailscale and Termius.
---

Connect to your cloud Claude Code VM from your phone or tablet. This guide covers the recommended path using Tailscale for networking and Termius with SSH.id for key management.

## Prerequisites

- A running vybn VM with the Tailscale backend (the default)
- A [Tailscale](https://tailscale.com/) account (your VM is already on your tailnet)

## 1. Install Tailscale on your device

Download the Tailscale app and sign in with the same account used for your VM:

- [iOS](https://apps.apple.com/app/tailscale/id1470499037)
- [Android](https://play.google.com/store/apps/details?id=com.tailscale.ipn)

Once connected, your phone joins the same tailnet as your VM. You can verify by checking that your VM's hostname appears in the Tailscale app's device list.

## 2. Install Termius

[Termius](https://termius.com/) is a mobile SSH client that works well on both iOS and Android. Install it from your device's app store.

Other SSH clients work too (e.g., Prompt, Blink Shell) — the key setup steps are the same.

## 3. Set up SSH.id (recommended)

[SSH.id](https://sshid.io/) is a Termius service that publishes your device's SSH public keys at a URL like `https://sshid.io/your-username`. This makes it easy to get mobile keys onto your VM without manually transferring files.

### In Termius

1. Go to **Settings > SSH.id**
2. Create an SSH.id username (e.g., `johndoe`)
3. Your device keys are now published at `https://sshid.io/johndoe`

### Add keys to your VM

**Option A: At deploy time** — set `VYBN_SSHID` in `~/.vybnrc` before deploying:

```bash
echo 'VYBN_SSHID="johndoe"' >> ~/.vybnrc
vybn deploy
```

The VM will fetch your keys from sshid.io during setup.

**Option B: Post-deploy** — use `vybn add-key` from any machine with vybn installed:

```bash
vybn add-key --sshid johndoe
```

This fetches keys from sshid.io on your local machine and installs them on the VM via SSH.

## 4. Configure the host in Termius

Create a new host in Termius:

| Field | Value |
|-------|-------|
| Hostname | Your VM's Tailscale hostname (e.g., `claude-bright-falcon`) |
| Username | `claude` (or your `VYBN_USER` value) |
| Key | Select the key that matches what SSH.id published |

## 5. Connect

Tap the host in Termius to connect. Once in, attach to the tmux session:

```bash
tmux attach -t claude
```

You're now running Claude Code from your phone.

## Alternative: manual key import

If you don't use Termius or SSH.id, you can add any SSH public key to the VM:

```bash
# From a file
vybn add-key --file /path/to/mobile_key.pub

# Or inline
vybn add-key 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... mobile@phone'
```

Transfer the public key from your mobile device to a machine with vybn installed (email, AirDrop, clipboard, etc.), then run the command above.

## How it works

```
Phone/Tablet
  |
  | Tailscale (WireGuard mesh)
  |
  v
GCP VM (claude-bright-falcon)
  |
  | SSH (key auth via authorized_keys)
  |
  v
tmux session -> Claude Code
```

1. **Tailscale** provides the network layer — your mobile device and VM are on the same encrypted mesh, regardless of NAT or firewalls.
2. **SSH** handles authentication using the public keys you imported via SSH.id or `vybn add-key`.
3. **tmux** keeps Claude Code running persistently — you can disconnect and reconnect without losing state.
