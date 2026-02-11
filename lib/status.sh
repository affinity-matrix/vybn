#!/usr/bin/env bash
# vybn status — Show VM state and tmux sessions

main() {
    require_provider

    # Check if VM exists
    if ! provider_vm_exists; then
        info "VM '${VYBN_VM_NAME}' does not exist."
        info "Run 'vybn deploy' to create it."
        return
    fi

    # VM details
    local vm_info
    vm_info="$(provider_vm_info)"

    local status
    status="$(provider_vm_status)"

    echo "=== VM: ${VYBN_VM_NAME} ==="
    echo "$vm_info"
    echo

    # Network connectivity
    net_status
    echo

    # tmux sessions (only if running)
    if [[ "$status" == "RUNNING" ]]; then
        echo "=== tmux sessions ==="
        local tmux_out
        tmux_out="$(vybn_ssh "tmux list-windows -t '${VYBN_TMUX_SESSION}' 2>/dev/null || echo 'No active tmux session'" 2>/dev/null || echo "SSH not available")"
        echo "$tmux_out"
    fi
}

cmd_help() {
    cat <<'EOF'
vybn status — Show VM state and tmux sessions

Usage: vybn status

Displays:
  - VM status, machine type, and external IP
  - Network connectivity info
  - Active tmux windows (if VM is running and reachable)
EOF
}
