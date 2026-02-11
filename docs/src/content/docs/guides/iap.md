---
title: IAP Setup
description: Configure vybn to use Google Identity-Aware Proxy for SSH tunneling.
---

IAP (Identity-Aware Proxy) tunnels SSH through Google's infrastructure using your `gcloud` credentials. No VPN or Tailscale account needed — if you have `gcloud` authenticated, IAP works out of the box.

## When to use IAP

- You only connect from machines with `gcloud` installed (laptops, desktops)
- You don't want to set up a Tailscale account
- You're in an environment that restricts outbound WireGuard traffic

IAP does **not** support mobile access (iOS/Android) because there's no `gcloud` CLI for those platforms. If you need mobile access, use the default [Tailscale backend](/guides/tailscale/).

## 1. Configure vybn

Set the network backend to `iap` in `~/.vybnrc`:

```bash
cat >> ~/.vybnrc << 'EOF'
VYBN_NETWORK="iap"
EOF
```

No auth keys or additional accounts are needed — IAP authenticates using your existing `gcloud` credentials.

## 2. Deploy

```bash
vybn deploy
```

The VM will:
1. Create a firewall rule allowing the IAP SSH range (`35.235.240.0/20`)
2. Apply a deny-all rule for everything else
3. Provision the VM with no public IP (IAP doesn't need one)

## 3. Connect

```bash
vybn auth
vybn connect
```

## How it works

```
┌─────────┐                     ┌──────────────────────────┐
│  Laptop  │     IAP tunnel      │       GCP VM             │
│          │◄──────────────────►│                          │
│  vybn    │  (Identity-Aware    │  tmux session "claude"   │
│  CLI     │   Proxy)            │  ├─ window 1: myapp     │
│          │                     │  │  └─ claude            │
└─────────┘                     │  ├─ window 2: backend   │
                                │  │  └─ claude            │
                                │  └─ window 3: docs       │
                                │     └─ claude            │
                                └──────────────────────────┘
```

SSH connections go through [GCP Identity-Aware Proxy](https://cloud.google.com/iap/docs/using-tcp-forwarding), which wraps SSH traffic in an HTTPS tunnel through Google's infrastructure. IAP authenticates using your `gcloud` credentials (OAuth) — no SSH keys or VPN needed on the client side.

The VM has no public IP address. The only allowed ingress is from Google's IAP range (`35.235.240.0/20`).

## Limitations

- **Requires `gcloud` CLI** on every client machine
- **No mobile access** — `gcloud` is not available on iOS or Android
- **Higher latency** than Tailscale for some regions (traffic routes through Google's IAP endpoints)
- **No multi-device mesh** — each connection requires `gcloud` authentication

## Switching from Tailscale to IAP

If you have an existing VM using Tailscale, you can switch in-place:

```bash
vybn switch-network iap
```

This reconfigures the VM's firewall rules and updates `~/.vybnrc`. No redeploy needed.
