#!/usr/bin/env bash
# vybn switch-network — Switch network backend on a running VM

# --- Helper: update VYBN_NETWORK in ~/.vybnrc ---

_update_vybnrc() {
    local target="$1"
    local rcfile="$HOME/.vybnrc"
    local tmpfile="${rcfile}.tmp.$$"

    if [[ ! -f "$rcfile" ]]; then
        echo "VYBN_NETWORK=${target}" > "$tmpfile"
    elif grep -q '^VYBN_NETWORK=' "$rcfile"; then
        # Use awk to replace the first occurrence and remove duplicates
        awk -v target="${target}" '
            /^VYBN_NETWORK=/ && !replaced { print "VYBN_NETWORK=" target; replaced=1; next }
            /^VYBN_NETWORK=/ { next }
            { print }
        ' "$rcfile" > "$tmpfile"
    else
        cp "$rcfile" "$tmpfile"
        echo "VYBN_NETWORK=${target}" >> "$tmpfile"
    fi

    mv "$tmpfile" "$rcfile"
    chmod 600 "$rcfile"
}

# --- IAP -> Tailscale ---

_switch_to_tailscale() {
    trap 'echo; warn "Interrupted. Config NOT updated — previous backend still active."; exit 130' INT TERM

    # macOS App Store bundles the CLI inside the .app
    if [[ "$(uname)" == "Darwin" && -x "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]]; then
        export PATH="/Applications/Tailscale.app/Contents/MacOS:$PATH"
    fi

    # 1. Validate prerequisites
    if ! command -v tailscale &>/dev/null; then
        error "tailscale CLI not found."
        error "Install: https://tailscale.com/download"
        exit 1
    fi

    if ! tailscale status &>/dev/null; then
        error "Tailscale is not running or not logged in."
        error "Run: tailscale up"
        exit 1
    fi

    if [[ -z "${VYBN_TAILSCALE_AUTHKEY:-}" ]]; then
        error "VYBN_TAILSCALE_AUTHKEY is not set."
        error "Generate one at: https://login.tailscale.com/admin/settings/keys"
        error "Set it in ~/.vybnrc: VYBN_TAILSCALE_AUTHKEY=\"tskey-auth-...\""
        exit 1
    fi

    if ! [[ "$VYBN_TAILSCALE_AUTHKEY" =~ ^tskey-auth-[A-Za-z0-9]+-[A-Za-z0-9]+$ ]]; then
        error "VYBN_TAILSCALE_AUTHKEY has an unexpected format."
        error "Expected: tskey-auth-<id>-<secret>"
        exit 1
    fi

    # 2. Generate SSH keypair if missing
    local key_dir="${VYBN_SSH_KEY_DIR:-$HOME/.vybn/ssh}"
    local key_file="${key_dir}/id_ed25519"

    if [[ ! -f "$key_file" ]]; then
        info "Generating vybn SSH keypair at ${key_file}..."
        mkdir -p "$key_dir"
        chmod 700 "$key_dir"
        ssh-keygen -t ed25519 -f "$key_file" -N "" -C "vybn@$(hostname -s)"
        chmod 600 "$key_file"
        chmod 644 "${key_file}.pub"
        success "SSH keypair generated."
    fi

    local pubkey
    pubkey="$(cat "${key_file}.pub")"

    # 3. Check for hostname conflicts on the tailnet
    local hostname="${VYBN_TAILSCALE_HOSTNAME:-$VYBN_VM_NAME}"
    if tailscale status 2>/dev/null | grep -qF "$hostname"; then
        local device_status
        device_status="$(tailscale status 2>/dev/null | grep -F "$hostname" | awk '{print $2}')"
        if [[ "$device_status" == "-" ]] || [[ "$device_status" == "offline" ]]; then
            error "Stale device '${hostname}' exists on your tailnet."
            error "Remove it first: https://login.tailscale.com/admin/machines"
            exit 1
        else
            warn "Device '${hostname}' is active on your tailnet."
            warn "The VM will replace it once Tailscale connects."
        fi
    fi

    # Base64-encode values for safe heredoc transport (prevents shell injection)
    local ts_authkey_b64 ts_hostname_b64="" ts_tags_b64=""
    ts_authkey_b64="$(printf '%s' "$VYBN_TAILSCALE_AUTHKEY" | base64 | tr -d '\n')"
    [[ -n "${VYBN_TAILSCALE_HOSTNAME:-}" ]] && ts_hostname_b64="$(printf '%s' "$VYBN_TAILSCALE_HOSTNAME" | base64 | tr -d '\n')"
    [[ -n "${VYBN_TAILSCALE_TAGS:-}" ]] && ts_tags_b64="$(printf '%s' "$VYBN_TAILSCALE_TAGS" | base64 | tr -d '\n')"

    # 4. SSH into VM via IAP and install Tailscale + SSH key
    info "Installing Tailscale on VM via IAP..."
    if ! net_ssh_raw root "bash -s" <<REMOTE_EOF; then
set -euo pipefail
LOG="/var/log/vybn-setup.log"
log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*" | tee -a "\$LOG"; }

# Install Tailscale (via apt repo — avoids piping curl to sh)
if ! command -v tailscale &>/dev/null; then
    log "Installing Tailscale..."
    mkdir -p /usr/share/keyrings
    chmod 0755 /usr/share/keyrings
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
        -o /usr/share/keyrings/tailscale-archive-keyring.gpg

    # Verify GPG key fingerprint
    EXPECTED_TS_FP="2596A99EAAB33821893C0A79458CA832957F5868"
    ACTUAL_TS_FP="\$(gpg --with-colons --import-options show-only --import \
        /usr/share/keyrings/tailscale-archive-keyring.gpg 2>/dev/null \
        | awk -F: '/^pub/{found=1} found && /^fpr/{print \$10; exit}')"
    if [[ "\$ACTUAL_TS_FP" != "\$EXPECTED_TS_FP" ]]; then
        log "ERROR: Tailscale GPG key fingerprint mismatch (expected \$EXPECTED_TS_FP, got \$ACTUAL_TS_FP)"
        exit 1
    fi
    log "Tailscale GPG key verified: \$EXPECTED_TS_FP"

    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list \
        -o /etc/apt/sources.list.d/tailscale.list
    apt-get update -qq
    apt-get install -y -qq tailscale
else
    log "Tailscale already installed."
fi

# Decode base64-encoded values (safe transport — no shell metacharacter risk)
TS_AUTHKEY="\$(echo '${ts_authkey_b64}' | base64 -d)"
TS_HOSTNAME="\$(echo '${ts_hostname_b64}' | base64 -d)" || true
TS_TAGS="\$(echo '${ts_tags_b64}' | base64 -d)" || true

# Build tailscale up args as a proper array
TS_ARGS=(--authkey="\$TS_AUTHKEY" --ssh=false)
[[ -n "\$TS_HOSTNAME" ]] && TS_ARGS+=(--hostname="\$TS_HOSTNAME")
[[ -n "\$TS_TAGS" ]] && TS_ARGS+=(--advertise-tags="\$TS_TAGS")

# Connect to tailnet
log "Connecting to Tailscale..."
tailscale up "\${TS_ARGS[@]}"
log "Tailscale connected."

# Install SSH public key for claude user
CLAUDE_USER="claude"
CLAUDE_HOME="/home/\${CLAUDE_USER}"
CLAUDE_SSH_DIR="\${CLAUDE_HOME}/.ssh"
PUBKEY="${pubkey}"

# Validate SSH public key format
PUBKEY_LINE_COUNT="\$(echo "\$PUBKEY" | wc -l)"
if [[ "\$PUBKEY_LINE_COUNT" -ne 1 ]]; then
    log "ERROR: SSH public key contains multiple lines — rejecting"
    exit 1
elif ! [[ "\$PUBKEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+)\ [A-Za-z0-9+/=]+( .+)?$ ]]; then
    log "ERROR: SSH public key has invalid format — rejecting"
    exit 1
fi

mkdir -p "\$CLAUDE_SSH_DIR"
chmod 700 "\$CLAUDE_SSH_DIR"

CLAUDE_AUTH_KEYS="\${CLAUDE_SSH_DIR}/authorized_keys"
if ! grep -qF "\$PUBKEY" "\$CLAUDE_AUTH_KEYS" 2>/dev/null; then
    echo "\$PUBKEY" >> "\$CLAUDE_AUTH_KEYS"
fi
chmod 600 "\$CLAUDE_AUTH_KEYS"
chown -R "\${CLAUDE_USER}:\${CLAUDE_USER}" "\$CLAUDE_SSH_DIR"
log "SSH key installed for \${CLAUDE_USER}."
log "=== switch-network: tailscale setup complete ==="
REMOTE_EOF
        error "Failed to configure Tailscale on VM."
        error "The VM is still reachable via IAP. You can retry."
        exit 1
    fi

    success "Tailscale installed and connected on VM."

    # 5. Clean up IAP firewall rule (deny-all stays, it's needed by both)
    if gcloud compute firewall-rules describe vybn-allow-iap-ssh \
        --project="$VYBN_PROJECT" &>/dev/null; then
        info "Removing IAP SSH firewall rule (no longer needed)..."
        gcloud compute firewall-rules delete vybn-allow-iap-ssh \
            --project="$VYBN_PROJECT" --quiet
    fi

    # 6. Clear stale known_hosts for the Tailscale hostname
    local known_hosts="${key_dir}/known_hosts"
    if [[ -f "$known_hosts" ]]; then
        ssh-keygen -R "$hostname" -f "$known_hosts" 2>/dev/null || true
    fi

    # 7. Verify reachability via Tailscale SSH
    info "Verifying Tailscale connectivity..."

    # Source the Tailscale backend to use its SSH functions for verification
    source "${VYBN_DIR}/networks/tailscale.sh"

    local attempts=0
    local max_attempts=18  # 18 * 5s = 90s timeout
    while (( attempts < max_attempts )); do
        if net_ssh_raw "$VYBN_USER" "echo ok" &>/dev/null; then
            break
        fi
        attempts=$((attempts + 1))
        printf "\r$(_color 34)[info]$(_reset) Waiting for Tailscale connectivity... (%ds)" "$((attempts * 5))"
        sleep 5
    done
    printf "\n"

    if (( attempts >= max_attempts )); then
        warn "Could not verify Tailscale connectivity within 90s."
        warn "Tailscale is installed on the VM but may still be connecting."
        warn "The IAP firewall rule has been removed. If needed, re-add it with:"
        warn "  gcloud compute firewall-rules create vybn-allow-iap-ssh \\"
        warn "    --project=${VYBN_PROJECT} --direction=INGRESS --action=ALLOW \\"
        warn "    --rules=tcp:22 --source-ranges=35.235.240.0/20 \\"
        warn "    --target-tags=vybn-vm --priority=900"
        warn "Config NOT updated. Retry with: vybn switch-network tailscale"
        exit 1
    fi

    success "VM reachable via Tailscale."

    # 8. Update ~/.vybnrc
    _update_vybnrc tailscale
    success "Switched to Tailscale network backend."
    info "Run 'vybn connect' to connect via Tailscale."
}

# --- Tailscale -> IAP ---

_switch_to_iap() {
    trap 'echo; warn "Interrupted. Config NOT updated — previous backend still active."; exit 130' INT TERM

    # 1. Validate prerequisites (gcloud is already validated by require_provider)

    # 2. Ensure IAP firewall rule exists
    if ! gcloud compute firewall-rules describe vybn-allow-iap-ssh \
        --project="$VYBN_PROJECT" &>/dev/null; then
        info "Creating firewall rule: vybn-allow-iap-ssh..."
        gcloud compute firewall-rules create vybn-allow-iap-ssh \
            --project="$VYBN_PROJECT" \
            --direction=INGRESS \
            --action=ALLOW \
            --rules=tcp:22 \
            --source-ranges=35.235.240.0/20 \
            --target-tags=vybn-vm \
            --priority=900 \
            --description="Allow SSH via IAP to vybn VMs" &>/dev/null
    else
        info "Firewall rule vybn-allow-iap-ssh already exists."
    fi

    # 3. SSH into VM via Tailscale and log out of Tailscale
    info "Logging VM out of Tailscale..."
    # shellcheck disable=SC2218 # net_ssh_raw is defined by the sourced network backend
    if ! net_ssh_raw "$VYBN_USER" "sudo tailscale logout" 2>/dev/null; then
        warn "Could not run 'tailscale logout' on VM (may already be disconnected)."
    else
        success "VM disconnected from Tailscale."
    fi

    # 4. Verify reachability via IAP
    info "Verifying IAP connectivity..."

    # Source the IAP backend to use its SSH functions for verification
    source "${VYBN_DIR}/networks/iap.sh"

    local attempts=0
    local max_attempts=12  # 12 * 5s = 60s timeout
    while (( attempts < max_attempts )); do
        if net_ssh_raw "$VYBN_USER" "echo ok" &>/dev/null; then
            break
        fi
        attempts=$((attempts + 1))
        printf "\r$(_color 34)[info]$(_reset) Waiting for IAP connectivity... (%ds)" "$((attempts * 5))"
        sleep 5
    done
    printf "\n"

    if (( attempts >= max_attempts )); then
        warn "Could not verify IAP connectivity within 60s."
        warn "The IAP firewall rule is in place. IAP tunneling may need a moment."
        warn "Config NOT updated. Retry with: vybn switch-network iap"
        exit 1
    fi

    success "VM reachable via IAP."

    # 5. Update ~/.vybnrc
    _update_vybnrc iap
    success "Switched to IAP network backend."
    info "Run 'vybn connect' to connect via IAP."
}

# --- Main ---

main() {
    local target="${1:-}"

    if [[ -z "$target" ]]; then
        error "Usage: vybn switch-network <iap|tailscale>"
        exit 1
    fi

    if [[ "$target" != "iap" && "$target" != "tailscale" ]]; then
        error "Unknown network backend: '${target}'"
        error "Available backends: iap, tailscale"
        exit 1
    fi

    require_provider
    require_vm_running

    # Check if already on target network
    if [[ "$VYBN_NETWORK" == "$target" ]]; then
        info "Already using '${target}' network backend."
        return
    fi

    # Confirmation
    info "Switch network summary:"
    info "  VM:        ${VYBN_VM_NAME}"
    info "  Current:   ${VYBN_NETWORK}"
    info "  Target:    ${target}"
    echo
    read -rp "Continue? [y/N] " confirm
    if [[ "$confirm" != [yY] ]]; then
        info "Cancelled."
        return
    fi

    case "$target" in
        tailscale)
            _switch_to_tailscale
            ;;
        iap)
            _switch_to_iap
            ;;
    esac
}

cmd_help() {
    cat <<'EOF'
vybn switch-network — Switch network backend on a running VM

Usage: vybn switch-network <iap|tailscale>

Switches the VM's network backend without destroying and redeploying.

IAP -> Tailscale:
  Installs Tailscale on the VM, provisions SSH keys, removes the IAP
  firewall rule, and verifies connectivity via Tailscale.

  Requires:
    - tailscale CLI installed locally and logged in
    - VYBN_TAILSCALE_AUTHKEY set in ~/.vybnrc or environment

Tailscale -> IAP:
  Logs the VM out of Tailscale, ensures the IAP firewall rule exists,
  and verifies connectivity via IAP.

On failure, the local config is NOT updated and the previous backend
remains functional. You can retry safely.
EOF
}
