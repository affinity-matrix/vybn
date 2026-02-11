#!/usr/bin/env bash
# vybn stop — Stop VM (preserves disk)

main() {
    local skip_confirm=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes) skip_confirm=true; shift ;;
            *) error "Unknown option: $1"; exit 1 ;;
        esac
    done

    require_provider
    require_vm_exists

    local status
    status="$(provider_vm_status)"

    if [[ "$status" == "TERMINATED" ]]; then
        info "VM '${VYBN_VM_NAME}' is already stopped."
        return
    fi

    if [[ "$skip_confirm" != true ]]; then
        warn "Stopping VM will terminate all tmux sessions."
        warn "Repos and files on disk will persist."
        read -rp "Stop VM '${VYBN_VM_NAME}'? [y/N] " confirm
        if [[ "$confirm" != [yY] ]]; then
            info "Cancelled."
            return
        fi
    fi

    info "Stopping VM '${VYBN_VM_NAME}'..."
    provider_vm_stop

    success "VM '${VYBN_VM_NAME}' stopped. Disk preserved."
    info "Restart with: vybn start"
}

cmd_help() {
    cat <<'EOF'
vybn stop — Stop the VM (preserves disk)

Usage: vybn stop [OPTIONS]

Options:
  -y, --yes    Skip confirmation prompt

Stops the VM after confirmation. The boot disk is preserved, but
tmux sessions will be lost. Restart with 'vybn start'.

While stopped, you are only charged for disk storage (no compute costs).
EOF
}
