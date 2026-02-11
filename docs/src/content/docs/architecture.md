---
title: Architecture
description: How vybn is structured and how the provider/network backends work.
---

vybn uses a modular architecture with swappable provider and network backends.

## Core Concepts

- **Provider** (`VYBN_PROVIDER`): Manages VM lifecycle — create, start, stop, delete. Default: `gcp`
- **Network** (`VYBN_NETWORK`): Manages SSH connectivity and file transfer. Default: `tailscale`

Provider backends live in `providers/` and network backends in `networks/`. The VM setup script is selected based on the combination: `vm-setup/${VYBN_PROVIDER}-${VYBN_NETWORK}.sh`.

All commands (`deploy`, `connect`, `ssh`, `session`, etc.) work identically regardless of which backends are active.

## VM Environment

The VM runs Ubuntu 24.04 with:

- **Claude Code** — native binary installed via `claude.ai/install.sh`, with SHA-256 checksum verification
- **Toolchains** — composable modules: Node.js (nvm), Python (pyenv), Rust (rustup), Go, Docker. Default: Node.js only. Configure via `VYBN_TOOLCHAINS`.
- **tmux** for persistent sessions

## Tailscale Network Backend

```
┌─────────┐                     ┌──────────────────────────┐
│  Laptop  │   Tailscale mesh    │       GCP VM             │
│  Phone   │◄──────────────────►│                          │
│  Tablet  │  (WireGuard)        │  tmux session "claude"   │
│          │                     │  ├─ window 1: myapp     │
│  vybn /  │  MagicDNS:          │  │  └─ claude            │
│  Termius │  claude-bright-falcon│  ├─ window 2: backend   │
│          │                     │  │  └─ claude            │
└─────────┘                     │  └─ window 3: docs       │
                                │     └─ claude            │
                                └──────────────────────────┘
```

SSH connections go over [Tailscale's WireGuard mesh](https://tailscale.com/). The VM joins your tailnet on first boot and is reachable by hostname via MagicDNS.

**Characteristics:**

- Works from **any device** on your tailnet, including iOS and Android
- Uses standard SSH (not Tailscale SSH) — preserves agent forwarding for Git
- Dedicated SSH keypair generated at `~/.vybn/ssh/id_ed25519` on first deploy
- Firewall denies all ingress — Tailscale uses outbound NAT traversal
- VM automatically reconnects to the tailnet after stop/start

## IAP Network Backend

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

SSH connections go through [GCP Identity-Aware Proxy](https://cloud.google.com/iap/docs/using-tcp-forwarding), which tunnels SSH through Google's infrastructure. No public IP or VPN required — IAP authenticates using your `gcloud` credentials.

**Characteristics:**

- Requires `gcloud` CLI on the client
- Firewall allows IAP SSH range (`35.235.240.0/20`) + deny-all for everything else
- Not available from iOS (no `gcloud`)

## Project Structure

```
vybn/
├── vybn                  # Main CLI entry point
├── install.sh            # Installation script
├── lib/                  # Command implementations
│   ├── config.sh         # Shared configuration and helpers
│   ├── deploy.sh         # deploy command
│   ├── connect.sh        # connect command
│   ├── session.sh        # session command
│   ├── sync_skills.sh    # sync-skills command
│   ├── start.sh          # start command
│   ├── stop.sh           # stop command
│   ├── destroy.sh        # destroy command
│   ├── status.sh         # status command
│   ├── ssh.sh            # ssh command
│   ├── tunnel.sh         # tunnel command
│   ├── check.sh          # check command
│   ├── update.sh         # update command
│   ├── logs.sh           # logs command
│   ├── switch_network.sh # switch-network command
│   └── add_key.sh        # add-key command
├── providers/            # Cloud provider backends
│   └── gcp.sh            # Google Cloud Platform
├── networks/             # Network connectivity backends
│   ├── iap.sh            # Identity-Aware Proxy
│   └── tailscale.sh      # Tailscale mesh
├── vm-setup/             # VM startup scripts
│   ├── base.sh           # Shared setup functions
│   ├── gcp-iap.sh        # GCP + IAP variant
│   ├── gcp-tailscale.sh  # GCP + Tailscale variant
│   └── toolchains/       # Composable toolchain modules
│       ├── node.sh       # nvm + Node.js LTS
│       ├── python.sh     # pyenv + Python 3
│       ├── rust.sh       # rustup + stable toolchain
│       ├── go.sh         # Official Go binary
│       └── docker.sh     # Docker CE + Compose
└── test/                 # Test suite
    └── smoke.sh          # Smoke tests (offline)
```

Each command is a separate module in `lib/` that exports `main()` and `cmd_help()` functions. The main `vybn` script dispatches to the appropriate module based on the subcommand.

## Startup Script Assembly

At deploy time, the VM's startup script is assembled by concatenating several layers into a single script:

1. **Config header** — `VYBN_TOOLCHAINS`, `VYBN_APT_PACKAGES`, `VYBN_NPM_PACKAGES`, `CLAUDE_CODE_VERSION`, and other settings baked as shell variable assignments
2. **Network config** — network-specific values (e.g., Tailscale auth key)
3. **base.sh** — core setup functions: user creation, Claude Code native binary installation (with checksum verification), tmux, SSH hardening
4. **Toolchain modules** — one file from `vm-setup/toolchains/` for each enabled toolchain, each defining a `setup_toolchain_<name>()` function
5. **Provider-network variant** — e.g., `vm-setup/gcp-iap.sh` — orchestrates the call order of all setup functions
6. **User script** — contents of `VYBN_SETUP_SCRIPT`, if configured

Configuration is baked directly into the script header rather than read from cloud metadata at runtime. This makes the startup script self-contained and debuggable — you can read the full assembled script in the GCP serial console or setup log.
