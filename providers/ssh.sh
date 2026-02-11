#!/usr/bin/env bash
# SSH provider backend for vybn — Bring Your Own VM
# Implements the provider_* interface for pre-existing servers.
# The user provides SSH credentials; vybn deploys the setup script over SSH.

# --- Internal Helpers ---

_ssh_bootstrap_opts() {
    local opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes)

    if [[ -n "${VYBN_SSH_KEY:-}" ]]; then
        opts+=(-i "$VYBN_SSH_KEY")
    fi

    if [[ "${VYBN_SSH_PORT:-22}" != "22" ]]; then
        opts+=(-p "$VYBN_SSH_PORT")
    fi

    _BOOTSTRAP_SSH_OPTS=("${opts[@]}")
}

_ssh_bootstrap_cmd() {
    _ssh_bootstrap_opts
    ssh "${_BOOTSTRAP_SSH_OPTS[@]}" "${VYBN_SSH_USER}@${VYBN_SSH_HOST}" "$@"
}

_ssh_bootstrap_scp() {
    local src="$1" dst="$2"
    _ssh_bootstrap_opts

    local scp_opts=("${_BOOTSTRAP_SSH_OPTS[@]}")
    # Convert -p to -P for scp
    local i
    for i in "${!scp_opts[@]}"; do
        if [[ "${scp_opts[$i]}" == "-p" ]]; then
            scp_opts[$i]="-P"
        fi
    done

    scp "${scp_opts[@]}" "$src" "${VYBN_SSH_USER}@${VYBN_SSH_HOST}:${dst}"
}

# --- Provider Interface ---

provider_require_cli() {
    if ! command -v ssh &>/dev/null; then
        error "ssh not found. Install an OpenSSH client."
        exit 1
    fi

    if [[ -z "${VYBN_SSH_HOST:-}" ]]; then
        error "VYBN_SSH_HOST is not set."
        error "Set it in ~/.vybnrc or via environment: VYBN_SSH_HOST=your-server.example.com"
        exit 1
    fi

    if [[ -n "${VYBN_SSH_KEY:-}" ]] && [[ ! -r "$VYBN_SSH_KEY" ]]; then
        error "VYBN_SSH_KEY '${VYBN_SSH_KEY}' is not a readable file."
        exit 1
    fi
}

provider_detect_project() {
    # No project concept for SSH provider
    echo ""
}

provider_vm_exists() {
    # The VM always "exists" — the user manages it.
    # After deploy, we also check for the local marker.
    if [[ -f "$HOME/.vybn/ssh-provider-deployed" ]]; then
        return 0
    fi
    # Before deploy, still return true — the host is assumed to exist
    return 0
}

provider_vm_status() {
    # We can't check remote status — assume running
    echo "RUNNING"
}

provider_vm_info() {
    echo "  Provider: ssh (bring your own VM)"
    echo "  Host:     ${VYBN_SSH_HOST}"
    echo "  SSH user: ${VYBN_SSH_USER}"
    echo "  SSH port: ${VYBN_SSH_PORT}"
    if [[ -n "${VYBN_SSH_KEY:-}" ]]; then
        echo "  SSH key:  ${VYBN_SSH_KEY}"
    fi
    if [[ -f "$HOME/.vybn/ssh-provider-deployed" ]]; then
        echo "  Status:   deployed"
    else
        echo "  Status:   not yet deployed"
    fi
}

provider_vm_create() {
    local setup_script="$1"

    info "Uploading setup script to ${VYBN_SSH_HOST}..."
    _ssh_bootstrap_scp "$setup_script" "/tmp/vybn-setup.sh"

    info "Running setup script on ${VYBN_SSH_HOST}..."
    info "(This may take several minutes)"
    _ssh_bootstrap_cmd "chmod +x /tmp/vybn-setup.sh && sudo /tmp/vybn-setup.sh && rm -f /tmp/vybn-setup.sh"

    # Mark as deployed locally
    mkdir -p "$HOME/.vybn"
    touch "$HOME/.vybn/ssh-provider-deployed"
}

provider_vm_start() {
    error "VM lifecycle is managed externally. Start your server and run 'vybn connect'."
    exit 1
}

provider_vm_stop() {
    error "VM lifecycle is managed externally. Stop your server directly."
    exit 1
}

provider_vm_delete() {
    # Clean up local state only — never touch the remote server
    info "Cleaning up local state (remote server is not modified)..."
    rm -f "$HOME/.vybn/ssh-provider-deployed"
}
