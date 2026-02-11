#!/usr/bin/env bash
# vybn start — Start a stopped VM

main() {
    require_provider

    if [[ "$VYBN_PROVIDER" == "ssh" ]]; then
        info "VM lifecycle is managed externally. Start your server directly."
        info "Once running, connect with: vybn connect"
        return
    fi

    require_vm_exists

    local status
    status="$(provider_vm_status)"

    if [[ "$status" == "RUNNING" ]]; then
        info "VM '${VYBN_VM_NAME}' is already running."
        return
    fi

    info "Starting VM '${VYBN_VM_NAME}'..."
    provider_vm_start

    # Wait for SSH to be available
    local attempts=0
    local max_attempts=30
    local start_time
    start_time=$(date +%s)
    while (( attempts < max_attempts )); do
        if vybn_ssh "true" 2>/dev/null; then
            break
        fi
        attempts=$((attempts + 1))
        local elapsed=$(( $(date +%s) - start_time ))
        printf "\r$(_color 34)[info]$(_reset) Waiting for VM to be reachable... (%s elapsed)" "$(format_duration "$elapsed")"
        sleep 5
    done
    printf "\n"

    if (( attempts >= max_attempts )); then
        warn "VM started but not yet reachable."
        warn "It may need a moment to reconnect. Try: vybn status"
    else
        success "VM '${VYBN_VM_NAME}' is running and reachable."

        # Check if tmux session survived the stop/start cycle
        local safe_session="${VYBN_TMUX_SESSION//\'/\'\\\'\'}"
        if vybn_ssh "tmux has-session -t '${safe_session}' 2>/dev/null" 2>/dev/null; then
            info "Existing tmux session found. Reconnect with: vybn connect"
        else
            info "No active tmux session. Create one with:"
            info "  vybn connect"
            info "  vybn session <name> [path]"
        fi
    fi
}

cmd_help() {
    cat <<'EOF'
vybn start — Start a stopped VM

Usage: vybn start

Starts the VM and waits for it to become reachable via SSH.
Checks whether a tmux session survived the stop/start cycle.

The VM's disk is preserved across stop/start, but tmux sessions
are typically lost when the VM is stopped.
EOF
}
