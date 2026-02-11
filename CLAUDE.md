# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**vybn** is a Bash CLI tool for managing Claude Code on cloud virtual machines. It creates and manages persistent tmux sessions on GCP VMs, letting developers connect from anywhere and resume work.

## Architecture

The codebase is pure Bash with a pluggable backend architecture:

```
vybn (entry point) → lib/config.sh (shared config + helpers)
                   → providers/{provider}.sh (cloud provider backend)
                   → networks/{network}.sh (network connectivity backend)
                   → lib/{command}.sh (individual command modules)
                   → vm-setup/base.sh + vm-setup/{provider}-{network}.sh
```

**Provider backends** (`providers/`) implement a standard interface: `provider_require_cli`, `provider_detect_project`, `provider_vm_exists`, `provider_vm_status`, `provider_vm_info`, `provider_vm_create`, `provider_vm_start`, `provider_vm_stop`, `provider_vm_delete`. Currently only `gcp.sh` exists.

**Network backends** (`networks/`) implement: `net_setup`, `net_teardown`, `net_status`, `net_ssh_raw`, `vybn_ssh`, `vybn_ssh_interactive`, `net_tunnel`. Two backends exist: `tailscale.sh` (default, WireGuard mesh) and `iap.sh` (Google IAP tunneling).

**VM setup scripts** (`vm-setup/`) use a base + variant pattern. `base.sh` defines shared functions (`setup_system_packages`, `setup_user`, `setup_nodejs`, `setup_claude_code`, `setup_tmux`, `setup_ssh_hardening`, `setup_bashrc`, `setup_complete`). Variant scripts (e.g., `gcp-iap.sh`, `gcp-tailscale.sh`) call these functions and add network-specific setup. At deploy time, `base.sh` and the variant are concatenated into a single startup script.

**Command modules** (`lib/`) each export a `main()` function and optional `cmd_help()`. The entry point dispatches based on the first argument, sourcing the matching module.

**Configuration flow:** defaults in `lib/config.sh` → user overrides from `~/.vybnrc` → provider/network backends loaded → command module executed. Project detection and GCP parameter validation are lazy (deferred until `require_provider()` is called), so `vybn help` and `vybn version` work without gcloud installed.

## Shell Conventions

- All scripts use `#!/usr/bin/env bash` with `set -euo pipefail`
- Output helpers: `info()`, `warn()`, `error()`, `success()` (defined in `lib/config.sh`)
- `info()` and `success()` are suppressed when `VYBN_QUIET=true`
- Validation helpers: `require_provider`, `require_vm_exists`, `require_vm_running`
- Hyphens in command names map to underscores in filenames (`add-key` → `lib/add_key.sh`)

## CI

GitHub Actions runs on push/PR to `main`:
- **ShellCheck** (`--severity=warning`) on all `.sh` files + `vybn`
- **Smoke tests** (`test/smoke.sh`) — runs without cloud credentials

## Documentation Site

The `docs/` directory contains an Astro + Starlight static site (separate from the CLI).

```bash
cd docs && npm run dev      # Development server
cd docs && npm run build    # Production build
```
