#!/usr/bin/env bash
# Tailscale network backend for vybn
# Implements the net_* and vybn_ssh* interface using Tailscale mesh + standard SSH.
#
# Tailscale provides encrypted WireGuard transport; standard SSH handles
# authentication and agent forwarding (-A) which Tailscale SSH doesn't support.

# macOS App Store bundles the CLI inside the .app
if [[ "$(uname)" == "Darwin" && -x "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]]; then
    export PATH="/Applications/Tailscale.app/Contents/MacOS:$PATH"
fi

# --- Internal Helpers ---

_ts_ssh_host() {
    local state_file="$HOME/.vybn/tailscale-hostname"
    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        echo "${VYBN_TAILSCALE_HOSTNAME:-$VYBN_VM_NAME}"
    fi
}

_ts_ssh_opts() {
    local key_dir="${VYBN_SSH_KEY_DIR:-$HOME/.vybn/ssh}"
    local known_hosts="${key_dir}/known_hosts"
    local hostname
    hostname="$(_ts_ssh_host)"

    # If we have a pinned key, enforce strict checking; otherwise fall back to TOFU
    local host_check="yes"
    if [[ ! -f "$known_hosts" ]] || ! grep -q "^${hostname} " "$known_hosts" 2>/dev/null; then
        host_check="accept-new"
    fi

    _TS_SSH_OPTS=(
        -i "${key_dir}/id_ed25519"
        -o "StrictHostKeyChecking=${host_check}"
        -o "UserKnownHostsFile=${known_hosts}"
        -o ConnectTimeout=5
        -o ServerAliveInterval=5
        -o ServerAliveCountMax=3
    )
}

_ts_ensure_ssh_key() {
    local key_dir="${VYBN_SSH_KEY_DIR:-$HOME/.vybn/ssh}"
    local key_file="${key_dir}/id_ed25519"

    if [[ -f "$key_file" ]]; then
        return 0
    fi

    info "Generating vybn SSH keypair at ${key_file}..."
    mkdir -p "$key_dir"
    chmod 700 "$key_dir"
    ssh-keygen -t ed25519 -f "$key_file" -N "" -C "vybn@$(hostname -s)"
    chmod 600 "$key_file"
    chmod 644 "${key_file}.pub"
    success "SSH keypair generated."
}

# --- Tailscale requires an external IP ---
# Outbound internet is needed during VM setup (package installation, Tailscale
# coordination servers, nvm, npm). Without Cloud NAT, this needs an external IP.
# The deny-all firewall rule still blocks all inbound traffic, so security
# posture is maintained — Tailscale provides the actual boundary.
#
# Set at source time (not inside net_setup) so the deploy summary reflects reality.
# shellcheck disable=SC2034  # used by providers/*.sh and lib/deploy.sh
VYBN_EXTERNAL_IP="true"

# --- Network Interface ---

net_setup() {
    # Validate Tailscale CLI is available and running
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

    # Validate auth key is set (needed for VM enrollment)
    if [[ -z "${VYBN_TAILSCALE_AUTHKEY:-}" ]]; then
        error "VYBN_TAILSCALE_AUTHKEY is not set."
        error "Generate one at: https://login.tailscale.com/admin/settings/keys"
        error "Set it in ~/.vybnrc: VYBN_TAILSCALE_AUTHKEY=\"tskey-auth-...\""
        exit 1
    fi

    # Generate SSH keypair if missing
    _ts_ensure_ssh_key

    # Default Tailscale hostname to the unified VM name (or use explicit override)
    local state_file="$HOME/.vybn/tailscale-hostname"
    if [[ -z "${VYBN_TAILSCALE_HOSTNAME:-}" ]]; then
        VYBN_TAILSCALE_HOSTNAME="$VYBN_VM_NAME"
    fi
    mkdir -p "$HOME/.vybn"
    echo "$VYBN_TAILSCALE_HOSTNAME" > "$state_file"

    local hostname="$VYBN_TAILSCALE_HOSTNAME"
    info "Tailscale hostname: ${hostname}"

    # Warn about any existing devices matching the hostname
    if tailscale status 2>/dev/null | grep -qF "$hostname"; then
        echo
        warn "Existing device(s) matching '${hostname}' found on your tailnet."
        warn "Consider removing stale devices to keep your tailnet clean:"
        warn "  tailscale status | grep '${hostname}'"
        warn "  https://login.tailscale.com/admin/machines"
        echo
    fi

    # Create deny-all firewall rule (Tailscale uses outbound NAT traversal, no inbound needed)
    if ! gcloud compute firewall-rules describe vybn-deny-all-ingress \
        --project="$VYBN_PROJECT" &>/dev/null; then
        info "Creating firewall rule: vybn-deny-all-ingress..."
        _retry gcloud compute firewall-rules create vybn-deny-all-ingress \
            --project="$VYBN_PROJECT" \
            --direction=INGRESS \
            --action=DENY \
            --rules=all \
            --source-ranges=0.0.0.0/0 \
            --target-tags=vybn-vm \
            --priority=1000 \
            --description="Deny all inbound traffic to vybn VMs" &>/dev/null
    else
        info "Firewall rule vybn-deny-all-ingress already exists."
    fi

    # Clear stale known_hosts entry for this hostname
    local key_dir="${VYBN_SSH_KEY_DIR:-$HOME/.vybn/ssh}"
    local known_hosts="${key_dir}/known_hosts"
    if [[ -f "$known_hosts" ]]; then
        ssh-keygen -R "$hostname" -f "$known_hosts" 2>/dev/null || true
    fi
}

net_teardown() {
    if gcloud compute firewall-rules describe vybn-deny-all-ingress \
        --project="$VYBN_PROJECT" &>/dev/null; then
        info "Deleting firewall rule 'vybn-deny-all-ingress'..."
        _retry gcloud compute firewall-rules delete vybn-deny-all-ingress \
            --project="$VYBN_PROJECT" --quiet
    fi

    # Device deregistration is handled in destroy.sh via `tailscale logout`.
    # Only remind the user if there's still a device on the tailnet (logout failed or was skipped).
    local hostname
    hostname="$(_ts_ssh_host)"
    if tailscale status 2>/dev/null | grep -qF "$hostname"; then
        echo
        warn "Device '${hostname}' still appears on your tailnet."
        warn "Remove it to avoid hostname conflicts on next deploy:"
        warn "  https://login.tailscale.com/admin/machines"
    fi

    # Clean up state file so next deploy generates a fresh petname
    rm -f "$HOME/.vybn/tailscale-hostname"
}

net_status() {
    local hostname
    hostname="$(_ts_ssh_host)"

    echo "=== Network: Tailscale ==="
    info "SSH via Tailscale mesh (hostname: ${hostname})"
    echo
    info "Tailscale device status:"
    tailscale status 2>/dev/null | grep -F "$hostname" || warn "Device '${hostname}' not found on tailnet."
}

net_ssh_raw() {
    local user="$1"
    shift
    local hostname
    hostname="$(_ts_ssh_host)"
    _ts_ssh_opts

    ssh "${_TS_SSH_OPTS[@]}" -o BatchMode=yes "${user}@${hostname}" "$@"
}

vybn_ssh() {
    local hostname
    hostname="$(_ts_ssh_host)"
    _ts_ssh_opts

    ssh "${_TS_SSH_OPTS[@]}" -A "${VYBN_USER}@${hostname}" "$@"
}

vybn_ssh_interactive() {
    local hostname
    hostname="$(_ts_ssh_host)"
    _ts_ssh_opts

    # Explicit -t for PTY allocation (IAP's gcloud does this automatically)
    ssh "${_TS_SSH_OPTS[@]}" -A -t "${VYBN_USER}@${hostname}" "$@"
}

net_tunnel() {
    local remote_port="$1"
    local local_port="$2"
    local hostname
    hostname="$(_ts_ssh_host)"
    _ts_ssh_opts

    ssh "${_TS_SSH_OPTS[@]}" -N -L "localhost:${local_port}:localhost:${remote_port}" "${VYBN_USER}@${hostname}"
}

net_inject_config() {
    # Emit single-quoted shell variable assignments for the startup script header.
    # These are read by the variant script instead of fetching from GCP metadata.
    local key_dir="${VYBN_SSH_KEY_DIR:-$HOME/.vybn/ssh}"
    local pubkey
    pubkey="$(cat "${key_dir}/id_ed25519.pub")"

    # Validate no single quotes in values (would break single-quoted assignment)
    _validate_no_single_quotes() {
        local name="$1" value="$2"
        if [[ "$value" == *"'"* ]]; then
            error "${name} contains single quotes — not allowed in config injection"
            exit 1
        fi
    }

    _validate_no_single_quotes "VYBN_TAILSCALE_AUTHKEY" "$VYBN_TAILSCALE_AUTHKEY"
    _validate_no_single_quotes "SSH public key" "$pubkey"

    echo "VYBN_TAILSCALE_AUTHKEY='${VYBN_TAILSCALE_AUTHKEY}'"
    echo "VYBN_SSH_PUBKEY='${pubkey}'"

    # Optional values
    local hostname="${VYBN_TAILSCALE_HOSTNAME:-}"
    if [[ -n "$hostname" ]]; then
        _validate_no_single_quotes "VYBN_TAILSCALE_HOSTNAME" "$hostname"
        echo "VYBN_TAILSCALE_HOSTNAME='${hostname}'"
    fi

    local tags="${VYBN_TAILSCALE_TAGS:-}"
    if [[ -n "$tags" ]]; then
        _validate_no_single_quotes "VYBN_TAILSCALE_TAGS" "$tags"
        echo "VYBN_TAILSCALE_TAGS='${tags}'"
    fi

    local sshid="${VYBN_SSHID:-}"
    if [[ -n "$sshid" ]]; then
        _validate_no_single_quotes "VYBN_SSHID" "$sshid"
        echo "VYBN_SSHID='${sshid}'"
    fi
}
