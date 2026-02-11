---
title: Toolchains
description: Configure which languages, runtimes, and tools are installed on your VM.
---

vybn uses composable toolchain modules to set up your VM's development environment. Instead of a fixed set of tools, you choose which toolchains to install — only what you need, nothing more.

## Available Toolchains

| Name | What it installs |
|------|-----------------|
| `node` | nvm + Node.js LTS (default) |
| `python` | pyenv + latest Python 3 |
| `rust` | rustup + stable toolchain |
| `go` | Official Go binary (latest) |
| `docker` | Docker CE + Compose plugin |

By default, only `node` is installed. To change this, set `VYBN_TOOLCHAINS` in `~/.vybnrc`.

## Configuration

Set `VYBN_TOOLCHAINS` to a comma-separated list of module names:

```bash
# ~/.vybnrc

# Node.js and Python
VYBN_TOOLCHAINS="node,python"
```

To install no toolchains at all, set it to an empty string:

```bash
VYBN_TOOLCHAINS=""
```

Changes take effect on the next `vybn deploy`.

## Extra Packages

Beyond toolchains, you can install additional system packages and npm globals:

```bash
# ~/.vybnrc

# Extra apt packages
VYBN_APT_PACKAGES="ripgrep fd-find sqlite3 jq"

# Extra global npm packages (requires node toolchain)
VYBN_NPM_PACKAGES="typescript tsx prettier"
```

`VYBN_APT_PACKAGES` are installed via `apt-get`. `VYBN_NPM_PACKAGES` are installed via `npm install -g` and require the `node` toolchain.

## Custom Setup Script

For anything beyond packages — cloning repos, configuring tools, setting environment variables — use a custom setup script:

```bash
# ~/.vybnrc
VYBN_SETUP_SCRIPT="$HOME/.vybn/setup.sh"
```

The script runs after all standard setup completes, in a subshell with `set +e` so failures don't abort the deploy. Example:

```bash
#!/usr/bin/env bash
# ~/.vybn/setup.sh

# Clone project repos
sudo -u claude git clone https://github.com/myorg/myapp.git /home/claude/myapp

# Install project dependencies
cd /home/claude/myapp && sudo -u claude npm install
```

## Preset Examples

### Full-stack web development

```bash
VYBN_TOOLCHAINS="node,docker"
VYBN_NPM_PACKAGES="typescript tsx"
```

### Data science / ML

```bash
VYBN_TOOLCHAINS="node,python"
VYBN_APT_PACKAGES="libopenblas-dev"
```

### Systems programming

```bash
VYBN_TOOLCHAINS="rust,go"
VYBN_APT_PACKAGES="protobuf-compiler"
```

### Everything

```bash
VYBN_TOOLCHAINS="node,python,rust,go,docker"
```

## How It Works

During `vybn deploy`, the startup script is assembled by concatenating several layers:

1. **Config header** — your `VYBN_TOOLCHAINS`, `VYBN_APT_PACKAGES`, and other settings baked as shell variables
2. **Network config** — Tailscale auth key and other network-specific values
3. **base.sh** — core setup functions (user creation, Claude Code installation, tmux, SSH hardening)
4. **Toolchain modules** — one file per enabled toolchain from `vm-setup/toolchains/`
5. **Provider-network variant** — e.g., `vm-setup/gcp-tailscale.sh` orchestrates the setup order
6. **User script** — your `VYBN_SETUP_SCRIPT`, if configured

Each toolchain module defines a `setup_toolchain_<name>()` function. The variant script calls these functions for each enabled toolchain. Modules are idempotent — they check whether the tool is already installed before doing anything.
