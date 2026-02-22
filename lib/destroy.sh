#!/usr/bin/env bash
# vybn destroy — Delete VM and network infrastructure

_maybe_remove_ssh_config() {
    local auto_yes="${1:-false}"
    local cfg="$HOME/.ssh/config"
    [[ -f "$cfg" ]] || return 0
    grep -q '^# vybn-start' "$cfg" 2>/dev/null || return 0

    if [[ "$auto_yes" != true ]]; then
        local answer
        read -rp "Remove VS Code SSH config for 'vybn'? [Y/n] " answer
        if [[ -n "$answer" && ! "$answer" =~ ^[Yy] ]]; then
            return 0
        fi
    fi

    local tmp
    tmp="$(mktemp)"
    sed '/^# vybn-start/,/^# vybn-end/d' "$cfg" > "$tmp"
    mv "$tmp" "$cfg"
    chmod 600 "$cfg"
    success "SSH config block removed from ~/.ssh/config"
}

main() {
    local skip_confirm=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes) skip_confirm=true; shift ;;
            *) error "Unknown option: $1"; exit 1 ;;
        esac
    done

    require_provider

    if [[ "$skip_confirm" != true ]]; then
        if [[ "$VYBN_PROVIDER" == "ssh" ]]; then
            warn "This will remove vybn from the remote host:"
            warn "  - Deregister from Tailscale"
            warn "  - Clean up local state files"
            warn "  (The remote server itself is not deleted.)"
        else
            warn "This will permanently delete:"
            warn "  - VM '${VYBN_VM_NAME}' and its boot disk"
            warn "  - Network infrastructure (firewall rules, etc.)"
        fi
        echo
        read -rp "Type '${VYBN_VM_NAME}' to confirm destruction: " confirm
        if [[ "$confirm" != "$VYBN_VM_NAME" ]]; then
            info "Cancelled."
            return
        fi
    fi

    if [[ "$VYBN_PROVIDER" == "ssh" ]]; then
        # Deregister from Tailscale via Tailscale SSH (if reachable)
        if [[ "$VYBN_NETWORK" == "tailscale" ]]; then
            info "Deregistering from Tailscale..."
            if timeout 30 net_ssh_raw "$VYBN_USER" "sudo tailscale logout" 2>/dev/null; then
                success "Device removed from tailnet."
            else
                warn "Could not deregister Tailscale (server may be unreachable)."
                warn "You may need to manually remove the device from:"
                warn "  https://login.tailscale.com/admin/machines"
            fi
        fi

        # Clean up local state
        provider_vm_delete

        # Clean up state files so next deploy gets a fresh name
        rm -f "$HOME/.vybn/tailscale-hostname"
        rm -f "$HOME/.vybn/vm-name"

        # Offer to remove SSH config block
        _maybe_remove_ssh_config "$skip_confirm"

        # Tear down network infrastructure
        net_teardown

        success "vybn resources cleaned up. Remote server was not modified."
    else
        # Delete VM
        if provider_vm_exists; then
            # Deregister from Tailscale before deleting the VM
            local status
            status="$(provider_vm_status)"
            if [[ "$status" == "RUNNING" ]] && [[ "$VYBN_NETWORK" == "tailscale" ]]; then
                info "Deregistering from Tailscale..."
                if timeout 30 net_ssh_raw "$VYBN_USER" "sudo tailscale logout" 2>/dev/null; then
                    success "Device removed from tailnet."
                else
                    warn "Could not deregister Tailscale (VM may be unreachable)."
                    warn "You may need to manually remove the device from:"
                    warn "  https://login.tailscale.com/admin/machines"
                fi
            fi

            info "Deleting VM '${VYBN_VM_NAME}'..."
            if ! provider_vm_delete; then
                error "Failed to delete VM '${VYBN_VM_NAME}'."
                error "Network teardown skipped to avoid orphaning resources."
                error "Check: gcloud compute instances list --zones=${VYBN_ZONE} --project=${VYBN_PROJECT}"
                exit 1
            fi
            success "VM deleted."
        else
            info "VM '${VYBN_VM_NAME}' not found (already deleted?)."
        fi

        # Clean up state files so next deploy gets a fresh name
        rm -f "$HOME/.vybn/tailscale-hostname"
        rm -f "$HOME/.vybn/vm-name"

        # Offer to remove SSH config block
        _maybe_remove_ssh_config "$skip_confirm"

        # Tear down network infrastructure
        net_teardown

        success "All vybn resources destroyed."
    fi
}

cmd_help() {
    cat <<'EOF'
vybn destroy — Delete VM and network infrastructure

Usage: vybn destroy [OPTIONS]

Options:
  -y, --yes    Skip confirmation prompt

Permanently deletes:
  - The VM and its boot disk
  - Network infrastructure (firewall rules, etc.)

Requires typing the VM name to confirm (unless --yes is used).
This cannot be undone.
EOF
}
