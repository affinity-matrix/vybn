---
title: Tailscale Setup
description: Set up Tailscale, the default network backend, for mesh networking and multi-device access.
---

Tailscale is the default network backend for vybn. It lets you access your VM from any device on your tailnet — laptops, phones, tablets — using a WireGuard mesh network. This guide walks through the full setup.

## 1. Install Tailscale locally

Download and install Tailscale on your local machine: [tailscale.com/download](https://tailscale.com/download)

Make sure you're logged in:

```bash
tailscale status
```

## 2. Generate an auth key

Go to the [Tailscale admin console](https://login.tailscale.com/admin/settings/keys) and generate an auth key.

- Use a **reusable** key if you plan to redeploy frequently
- Set an appropriate expiration

## 3. Configure vybn

Add the Tailscale settings to `~/.vybnrc`:

```bash
cat >> ~/.vybnrc << 'EOF'
VYBN_TAILSCALE_AUTHKEY="tskey-auth-..."
EOF
```

Tailscale is the default, so no `VYBN_NETWORK` setting is needed.

Optional settings:

```bash
# Custom hostname on your tailnet (auto-generates a petname like claude-bright-falcon if unset)
VYBN_TAILSCALE_HOSTNAME="claude-work"

# ACL tags for access control
VYBN_TAILSCALE_TAGS="tag:vybn"
```

## 4. Deploy

```bash
vybn deploy
```

The VM will:
1. Install Tailscale
2. Authenticate with your auth key
3. Join your tailnet
4. Become reachable via MagicDNS using an auto-generated petname (e.g., `claude-bright-falcon`)

## 5. Connect

```bash
vybn auth
vybn connect
```

You can also SSH directly from any device on your tailnet:

```bash
ssh -i ~/.vybn/ssh/id_ed25519 claude@<petname>
```

## Mobile access

For a complete guide to connecting from iOS and Android — including SSH key setup with Termius and SSH.id — see the [Mobile SSH guide](/guides/mobile-ssh).

## How it works

Tailscale creates a direct WireGuard mesh between your devices. The VM's firewall denies all ingress traffic — Tailscale uses outbound NAT traversal, so no inbound rules are needed. Your VM is reachable by hostname via MagicDNS from any device on your tailnet.

vybn uses standard SSH over Tailscale (not Tailscale SSH) to preserve SSH agent forwarding, which is needed for Git operations.
