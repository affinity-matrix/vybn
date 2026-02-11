# vybn

CLI for managing [Claude Code](https://docs.anthropic.com/en/docs/claude-code) on a cloud virtual machine. Run Claude Code in persistent tmux sessions on a cloud VM, connect from anywhere, and pick up where you left off.

## Why

Claude Code runs best with a stable, always-on environment. Running it on a cloud VM gives you:

- **Persistent sessions** — tmux keeps Claude Code running even when you disconnect
- **Consistent environment** — same OS, same tools, no laptop-specific quirks
- **Multiple projects** — each in its own tmux window, all on one VM
- **Low cost** — stop the VM when not in use, pay only for disk storage

## Prerequisites

- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (`gcloud`) — authenticated with a project
- SSH client — comes with macOS/Linux
- A GCP project with billing enabled
- [Tailscale](https://tailscale.com/download) — installed and logged in on your local machine
- A Tailscale auth key — generate at [admin console](https://login.tailscale.com/admin/settings/keys)

**For IAP networking** (alternative to Tailscale): no additional prerequisites beyond `gcloud`.

## Installation

```bash
git clone https://github.com/affinity-matrix/vybn.git
cd vybn && ./install.sh
```

Or symlink manually:

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

This removes the `/usr/local/bin/vybn` symlink and optionally cleans up `~/.vybn/` (SSH keys, tunnel state).

## Quick Start

### Tailscale (default)

```bash
# 1. Add your Tailscale auth key to ~/.vybnrc
cat >> ~/.vybnrc << 'EOF'
VYBN_TAILSCALE_AUTHKEY="tskey-auth-..."
EOF

# 2. Deploy — the VM joins your tailnet automatically
vybn deploy

# 3. Connect
vybn connect
```

After deploy, the VM is reachable from any device on your tailnet — including iOS via [Termius](https://termius.com/) or any SSH client.

### IAP

```bash
# 1. Set the network backend to IAP in ~/.vybnrc
cat >> ~/.vybnrc << 'EOF'
VYBN_NETWORK="iap"
EOF

# 2. Deploy, authenticate, and connect
vybn deploy --connect
```

## Commands

| Command | Description |
|---------|-------------|
| `vybn deploy [--connect] [-y]` | Create the VM with Claude Code pre-installed |
| `vybn connect [window]` | SSH + tmux attach (optionally to a specific window) |
| `vybn session <name> [path]` | Create a new Claude Code tmux window |
| `vybn sync-skills` | Copy installed skills to the VM |
| `vybn start` | Start a stopped VM |
| `vybn stop` | Stop the VM (preserves disk) |
| `vybn destroy` | Delete VM and network infrastructure |
| `vybn status` | Show VM state and tmux sessions |
| `vybn check` | Validate prerequisites before deploying |
| `vybn ssh [--batch] [command]` | Raw SSH to the VM |
| `vybn switch-network <net>` | Switch network backend (iap or tailscale) |
| `vybn logs [-n N] [-f]` | View VM setup log |
| `vybn update [version]` | Update Claude Code on the VM |
| `vybn tunnel <port> [local]` | Forward a TCP port (background); also: `list`, `kill` |
| `vybn version` | Show version |
| `vybn help` | Show usage |

Use `vybn <command> --help` for details on any command.

## Configuration

Create `~/.vybnrc` to override defaults. See [vybnrc.example](vybnrc.example) for all options.

```bash
cp vybnrc.example ~/.vybnrc
# Edit to taste
```

Key settings:

| Variable | Default | Description |
|----------|---------|-------------|
| `VYBN_PROVIDER` | `gcp` | Cloud provider backend |
| `VYBN_NETWORK` | `tailscale` | Network backend (`tailscale` or `iap`) |
| `VYBN_VM_NAME` | *(auto-generated)* | VM instance name (`claude-<adj>-<animal>` petname) |
| `VYBN_ZONE` | `us-west1-a` | GCP zone |
| `VYBN_MACHINE_TYPE` | `e2-standard-2` | Machine type (CPU/RAM) |
| `VYBN_DISK_SIZE` | `30` | Boot disk size in GB |
| `VYBN_USER` | `claude` | VM user account |
| `VYBN_PROJECT` | *(auto-detected)* | GCP project ID |
| `VYBN_TMUX_SESSION` | `claude` | tmux session name |
| `VYBN_QUIET` | `false` | Suppress info/success messages |
| `VYBN_VERBOSE` | `false` | Enable trace output (`set -x`) |

Tailscale settings (used with the default Tailscale network backend):

| Variable | Default | Description |
|----------|---------|-------------|
| `VYBN_TAILSCALE_AUTHKEY` | *(none, required)* | Auth key for VM enrollment on your tailnet |
| `VYBN_TAILSCALE_HOSTNAME` | `$VYBN_VM_NAME` | Tailscale device hostname |
| `VYBN_TAILSCALE_TAGS` | *(none)* | ACL tags (e.g., `tag:vybn`) |
| `VYBN_SSH_KEY_DIR` | `~/.vybn/ssh` | Directory for vybn-managed SSH keys |

## Architecture

vybn uses a modular architecture with swappable provider and network backends:

- **Provider** (`VYBN_PROVIDER`): Manages VM lifecycle (create, start, stop, delete). Default: `gcp`
- **Network** (`VYBN_NETWORK`): Manages SSH connectivity and file transfer. Default: `tailscale`

Provider backends live in `providers/` and network backends in `networks/`. VM setup uses `vm-setup/base.sh` (shared functions) concatenated with a variant script `vm-setup/${VYBN_PROVIDER}-${VYBN_NETWORK}.sh` at deploy time.

All commands (`deploy`, `connect`, `ssh`, `session`, etc.) work identically regardless of which network backend is active.

The VM runs Ubuntu 24.04 with:
- Node.js (via nvm) and Claude Code CLI
- tmux for persistent sessions

### Tailscale Network Backend

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

SSH connections go over [Tailscale's WireGuard mesh](https://tailscale.com/). The VM joins your tailnet on first boot and is reachable by hostname via MagicDNS (e.g., `ssh claude@claude-bright-falcon`).

- Works from **any device** on your tailnet, including iOS and Android
- Uses standard SSH (not Tailscale SSH) — preserves agent forwarding (`-A`) for Git
- Dedicated SSH keypair generated at `~/.vybn/ssh/id_ed25519` on first deploy
- Firewall denies all ingress — Tailscale uses outbound NAT traversal, no inbound rules needed
- VM automatically reconnects to the tailnet after stop/start

### IAP Network Backend

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

- Requires `gcloud` CLI on the client
- Firewall allows IAP SSH range (`35.235.240.0/20`) + deny-all for everything else
- Not available from iOS (no `gcloud`)

## Troubleshooting

### General

**SSH connection timeout**
- The VM may be starting up. Wait and retry, or check: `vybn status`

**Startup script not completing**
- Check the log: `vybn ssh 'cat /var/log/vybn-setup.log'`

**tmux sessions lost after stop/start**
- This is expected. tmux runs in memory and doesn't survive VM shutdown.
- Repos and files on disk persist. Create new sessions with `vybn connect` or `vybn session`.

### Tailscale

**"Tailscale is not running or not logged in"**
- Run `tailscale up` on your local machine.

**Deploy times out waiting for SSH**
- The auth key may be invalid or expired. Generate a new one at the [Tailscale admin console](https://login.tailscale.com/admin/settings/keys).
- Check the startup log: once the VM is running, use `gcloud compute ssh root@<vm-name> -- cat /var/log/vybn-setup.log` to see if Tailscale connected.

**"Host key verification failed"**
- After redeploying, the host key changes. `vybn deploy` clears stale entries automatically, but if it persists: `ssh-keygen -R <hostname> -f ~/.vybn/ssh/known_hosts`

**VM not visible on tailnet after stop/start**
- Tailscale reconnects automatically, but it may take a moment. Check with `tailscale status`.

**Connecting from iOS**
- Install the [Tailscale app](https://apps.apple.com/app/tailscale/id1470499037) and join the same tailnet.
- Use any SSH client (e.g., [Termius](https://termius.com/)) to connect to `claude@claude-bright-falcon` (or your `VYBN_VM_NAME`).
- Import the private key from `~/.vybn/ssh/id_ed25519` into the SSH client.

### IAP

**"gcloud credentials are expired"**
- Run `gcloud auth login` to re-authenticate.

## Using Git and GitHub from the VM

vybn forwards your local SSH agent to the VM automatically, so you can push to GitHub (or any Git remote) using the SSH keys on your local machine — no credentials need to be stored on the VM.

### Setup

1. **Add an SSH key to your GitHub account** (if you haven't already):
   - [Generate a new SSH key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent) or use an existing one
   - [Add the public key to your GitHub account](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account)

2. **Make sure your key is loaded in your local SSH agent** before connecting:

   ```bash
   # Check if your key is loaded
   ssh-add -l

   # If not, add it
   ssh-add ~/.ssh/id_ed25519
   ```

3. **Connect to the VM** as usual:

   ```bash
   vybn connect
   ```

4. **Use Git normally** on the VM — pushes, pulls, and clones over SSH just work:

   ```bash
   git clone git@github.com:youruser/yourrepo.git
   git push origin main
   ```

### Notes

- Agent forwarding only lasts for the duration of your SSH session. If you disconnect and reconnect, forwarding resumes automatically as long as your local agent still has the key loaded.
- Use SSH URLs (`git@github.com:...`) for remotes, not HTTPS URLs.
- If `ssh-add -l` shows "The agent has no identities" on your local machine, your key isn't loaded and forwarding won't work.

## Cost Estimates

These are rough estimates for `us-central1`. Actual costs vary by region and usage.

| Resource | Cost | Notes |
|----------|------|-------|
| `e2-micro` (running) | ~$6/month | 2 vCPU (shared), 1 GB RAM, 24/7 |
| `e2-small` (running) | ~$12/month | 2 vCPU (shared), 2 GB RAM, 24/7 |
| `e2-medium` (running) | ~$25/month | 2 vCPU (shared), 4 GB RAM, 24/7 |
| `e2-standard-2` (running) | ~$49/month | 2 vCPU, 8 GB RAM, 24/7 |
| `e2-standard-4` (running) | ~$97/month | 4 vCPU, 16 GB RAM, 24/7 |
| `e2-standard-8` (running) | ~$194/month | 8 vCPU, 32 GB RAM, 24/7 |
| `e2-highmem-2` (running) | ~$66/month | 2 vCPU, 16 GB RAM, 24/7 |
| `n2-standard-2` (running) | ~$57/month | 2 vCPU, 8 GB RAM, 24/7 |
| SSD disk (30 GB) | ~$5.10/month | Charged even when VM is stopped |
| VM stopped | $0/month | No compute charges, only disk |

Stop the VM when not in use (`vybn stop`) to avoid compute charges.

## License

[MIT](LICENSE)
