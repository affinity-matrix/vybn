#!/usr/bin/env bash
# VM setup base — shared functions for all provider-network variants.
# Variant scripts (e.g., gcp-iap.sh, gcp-tailscale.sh) are appended after
# this file at deploy time and call these functions in order.
set -Eeuo pipefail

# No-op stub — variant scripts override with provider-specific implementation.
_publish_guest_attr() { :; }

trap '_publish_guest_attr setup-status failed; touch /var/log/vybn-setup-failed' ERR

# Skip if setup already completed (remove /var/log/vybn-setup-complete to force re-run)
if [[ -f /var/log/vybn-setup-complete ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Setup already complete, skipping." | tee -a /var/log/vybn-setup.log
    exit 0
fi

CLAUDE_USER="claude"
CLAUDE_HOME="/home/${CLAUDE_USER}"
LOG="/var/log/vybn-setup.log"
NVM_VERSION="v0.40.1"
NVM_SHA256="abdb525ee9f5b48b34d8ed9fc67c6013fb0f659712e401ecd88ab989b3af8f53"

# Config variables injected by deploy.sh header (with fallback defaults)
CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-2.1.38}"
VYBN_TOOLCHAINS="${VYBN_TOOLCHAINS:-node}"
VYBN_APT_PACKAGES="${VYBN_APT_PACKAGES:-}"
VYBN_NPM_PACKAGES="${VYBN_NPM_PACKAGES:-}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

setup_system_packages() {
    log "Installing system packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq \
        build-essential git curl wget jq unzip htop \
        tmux ca-certificates gnupg lsb-release \
        software-properties-common apt-transport-https
}

setup_user() {
    if ! id "$CLAUDE_USER" &>/dev/null; then
        log "Creating user ${CLAUDE_USER}..."
        useradd -m -s /bin/bash "$CLAUDE_USER"
        # Claude Code needs broad system access for development work.
        # This is acceptable because the VM is single-purpose and ephemeral.
        echo "${CLAUDE_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${CLAUDE_USER}"
        chmod 440 "/etc/sudoers.d/${CLAUDE_USER}"
    else
        log "User ${CLAUDE_USER} already exists."
    fi
}

setup_toolchains() {
    local IFS=','
    for tc in $VYBN_TOOLCHAINS; do
        if declare -f "setup_toolchain_${tc}" &>/dev/null; then
            log "Installing toolchain: ${tc}..."
            "setup_toolchain_${tc}"
        else
            log "ERROR: Unknown toolchain '${tc}' — no setup_toolchain_${tc}() function found"
            exit 1
        fi
    done
}

setup_extra_packages() {
    if [[ -n "$VYBN_APT_PACKAGES" ]]; then
        log "Installing extra apt packages: ${VYBN_APT_PACKAGES}..."
        # shellcheck disable=SC2086
        apt-get install -y -qq $VYBN_APT_PACKAGES
    fi

    if [[ -n "$VYBN_NPM_PACKAGES" ]]; then
        # Only install npm packages if node toolchain is present
        if [[ ",$VYBN_TOOLCHAINS," == *",node,"* ]]; then
            log "Installing extra npm packages: ${VYBN_NPM_PACKAGES}..."
            # shellcheck disable=SC2086
            sudo -u "$CLAUDE_USER" bash -c '
                export NVM_DIR="$HOME/.nvm"
                [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
                npm install -g '"$VYBN_NPM_PACKAGES"'
            '
        else
            log "WARNING: VYBN_NPM_PACKAGES set but node toolchain not selected — skipping npm packages"
        fi
    fi
}

_verify_claude_checksum() {
    local version="$1"
    local claude_bin="${CLAUDE_HOME}/.local/bin/claude"

    if [[ ! -f "$claude_bin" ]]; then
        log "Checksum: SKIP — claude binary not found at ${claude_bin}"
        return 0
    fi

    local arch
    case "$(uname -m)" in
        x86_64)  arch="linux-x64" ;;
        aarch64) arch="linux-arm64" ;;
        *)       log "Checksum: SKIP — unsupported architecture $(uname -m)"; return 0 ;;
    esac

    local manifest_url="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/manifest.json"
    local manifest
    manifest="$(curl -fsSL --max-time 15 "$manifest_url" 2>/dev/null)" || {
        log "Checksum: WARN — could not fetch manifest (${manifest_url})"
        return 0
    }

    local expected_checksum
    expected_checksum="$(echo "$manifest" | jq -r ".platforms.\"${arch}\".checksum // empty" 2>/dev/null)" || true

    if [[ -z "$expected_checksum" ]]; then
        log "Checksum: WARN — no checksum found in manifest for ${arch}"
        return 0
    fi

    local actual_checksum
    actual_checksum="$(sha256sum "$claude_bin" | awk '{print $1}')"

    if [[ "$actual_checksum" == "$expected_checksum" ]]; then
        log "Checksum: PASS — claude binary verified (${arch})"
    else
        log "Checksum: FAIL — expected ${expected_checksum}, got ${actual_checksum}"
        exit 1
    fi
}

setup_claude_code() {
    log "Installing Claude Code CLI (native installer, v${CLAUDE_CODE_VERSION})..."

    # Install as claude user — binary lands at ~/.local/bin/claude
    # Wrapped in if-check to prevent the ERR trap from aborting setup if the
    # installer exits non-zero but the binary was still placed successfully.
    if ! sudo -u "$CLAUDE_USER" bash -c "curl -fsSL https://claude.ai/install.sh | bash -s -- ${CLAUDE_CODE_VERSION}"; then
        if [[ -f "${CLAUDE_HOME}/.local/bin/claude" ]]; then
            log "WARNING: Claude Code installer exited with error, but binary is present — continuing"
        else
            log "ERROR: Claude Code installation failed — binary not found"
            return 1
        fi
    fi

    # Symlink to /usr/local/bin so it's available in non-interactive SSH sessions
    if [[ -f "${CLAUDE_HOME}/.local/bin/claude" ]]; then
        ln -sf "${CLAUDE_HOME}/.local/bin/claude" /usr/local/bin/claude
        log "Symlinked claude to /usr/local/bin/claude"
    else
        log "WARNING: claude binary not found at ${CLAUDE_HOME}/.local/bin/claude after install"
    fi

    _verify_claude_checksum "$CLAUDE_CODE_VERSION"
}

setup_tmux() {
    local tmux_conf="${CLAUDE_HOME}/.tmux.conf"
    if [[ ! -f "$tmux_conf" ]]; then
        log "Writing tmux config..."
        cat > "$tmux_conf" << 'TMUXEOF'
# Sensible defaults for Claude Code sessions
set -g default-terminal "screen-256color"
set -ga terminal-overrides ",xterm-256color:Tc"
set -g mouse on
set -g history-limit 50000
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g set-titles on
set -g set-titles-string "#S:#W"
set -g status-style "bg=colour235,fg=colour136"
set -g status-left "#[fg=colour46]#S #[fg=colour240]| "
set -g status-right "#[fg=colour240]%H:%M"
set -g status-left-length 30
setw -g window-status-current-style "fg=colour166,bold"
# Bell: highlight window tab when Claude Code is waiting for input
set -g visual-bell off
set -g bell-action other
setw -g monitor-bell on
set -g window-status-bell-style "fg=colour255,bg=colour196,bold"
# Faster escape (for vim/claude)
set -sg escape-time 10
TMUXEOF
        chown "${CLAUDE_USER}:${CLAUDE_USER}" "$tmux_conf"
    else
        log "tmux config already exists."
    fi
}

setup_claude_hooks() {
    local claude_dir="${CLAUDE_HOME}/.claude"
    local settings="${claude_dir}/settings.json"

    mkdir -p "$claude_dir"

    if [[ -f "$settings" ]]; then
        # Skip if notification hooks are already configured
        if jq -e '.hooks.Notification' "$settings" &>/dev/null; then
            log "Claude Code notification hooks already configured."
            return
        fi
        # Merge notification hook into existing settings
        local tmp
        tmp="$(mktemp)"
        jq --arg cmd "printf '\\a' > /dev/tty 2>/dev/null || true" '
            .hooks = (.hooks // {}) + {
                "Notification": [{
                    "matcher": "idle_prompt",
                    "hooks": [{"type": "command", "command": $cmd}]
                }]
            }
        ' "$settings" > "$tmp" && mv "$tmp" "$settings"
    else
        cat > "$settings" << 'HOOKEOF'
{
  "hooks": {
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "printf '\\a' > /dev/tty 2>/dev/null || true"
          }
        ]
      }
    ]
  }
}
HOOKEOF
    fi

    chown -R "${CLAUDE_USER}:${CLAUDE_USER}" "$claude_dir"
    log "Claude Code notification hook configured (bell on idle)."
}

setup_ssh_hardening() {
    log "Hardening SSH configuration..."
    cat > /etc/ssh/sshd_config.d/99-vybn.conf << 'SSHDEOF'
PermitRootLogin no
PasswordAuthentication no
MaxAuthTries 6
ClientAliveInterval 300
ClientAliveCountMax 2
SSHDEOF
    systemctl reload ssh

    # Ensure .ssh dir exists for claude user
    local ssh_dir="${CLAUDE_HOME}/.ssh"
    if [[ ! -d "$ssh_dir" ]]; then
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        chown "${CLAUDE_USER}:${CLAUDE_USER}" "$ssh_dir"
    fi
}

setup_bashrc() {
    # Ensure ~/.local/bin is in PATH for login shells (SSH sessions).
    # The default /etc/skel/.profile may include this, but not all VM images
    # ship the standard skeleton — so we add it explicitly.
    local profile="${CLAUDE_HOME}/.profile"
    if ! grep -q 'vybn-setup' "$profile" 2>/dev/null; then
        cat >> "$profile" << 'PROFILEEOF'

# Added by vybn-setup
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi
PROFILEEOF
        chown "${CLAUDE_USER}:${CLAUDE_USER}" "$profile"
    fi

    local bashrc="${CLAUDE_HOME}/.bashrc"
    if ! grep -q "vybn-setup" "$bashrc" 2>/dev/null; then
        log "Adding shell customizations..."
        cat >> "$bashrc" << 'BASHEOF'

# Added by vybn-setup

# Native Claude Code binary
export PATH="$HOME/.local/bin:$PATH"

# Claude Code alias
alias cc='claude'
BASHEOF

        # Conditional toolchain PATH/source entries
        if [[ ",$VYBN_TOOLCHAINS," == *",node,"* ]]; then
            cat >> "$bashrc" << 'BASHEOF'

# Node.js (nvm)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
BASHEOF
        fi

        if [[ ",$VYBN_TOOLCHAINS," == *",python,"* ]]; then
            cat >> "$bashrc" << 'BASHEOF'

# Python (pyenv)
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
BASHEOF
        fi

        if [[ ",$VYBN_TOOLCHAINS," == *",rust,"* ]]; then
            cat >> "$bashrc" << 'BASHEOF'

# Rust (cargo)
. "$HOME/.cargo/env"
BASHEOF
        fi

        if [[ ",$VYBN_TOOLCHAINS," == *",go,"* ]]; then
            cat >> "$bashrc" << 'BASHEOF'

# Go
export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"
BASHEOF
        fi
    fi
}

setup_complete() {
    _publish_guest_attr setup-status complete
    touch /var/log/vybn-setup-complete
    chmod 644 "$LOG"
    chmod 644 /var/log/vybn-setup-complete
    log "=== vybn VM setup complete ==="
}
