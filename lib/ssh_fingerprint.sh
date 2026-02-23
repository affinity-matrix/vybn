#!/usr/bin/env bash
# vybn ssh-fingerprint — Show the VM's SSH host key fingerprint

main() {
    local algo="ed25519"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type|-t)
                algo="${2:-}"
                if [[ -z "$algo" ]]; then
                    error "--type requires a value"
                    exit 1
                fi
                shift 2
                ;;
            *) error "Unknown option: $1"; exit 1 ;;
        esac
    done

    require_provider
    require_vm_running

    info "Fetching SSH host key fingerprint..."
    local fingerprint
    fingerprint="$(vybn_ssh "ssh-keygen -lf /etc/ssh/ssh_host_${algo}_key.pub" 2>/dev/null)" || {
        error "Could not read host key for algorithm '${algo}'"
        exit 1
    }

    echo "$fingerprint"
}

cmd_help() {
    cat <<'EOF'
vybn ssh-fingerprint — Show the VM's SSH host key fingerprint

Usage: vybn ssh-fingerprint [OPTIONS]

Options:
  --type, -t <algo>   Key algorithm (default: ed25519)

Fetches and displays the SSH host key fingerprint from the VM.
Useful for verifying the host identity before connecting.

Examples:
  vybn ssh-fingerprint                 # ed25519 fingerprint
  vybn ssh-fingerprint --type rsa      # RSA fingerprint
EOF
}
