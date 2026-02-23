#!/usr/bin/env bash
# vybn resize — Change the VM machine type

main() {
    local new_type="${1:-}"

    if [[ -z "$new_type" ]]; then
        error "Usage: vybn resize <machine-type>"
        error "Example: vybn resize e2-standard-4"
        exit 1
    fi

    # Validate machine type format
    if ! [[ "$new_type" =~ ^[a-z][a-z0-9-]+$ ]]; then
        error "Invalid machine type: '${new_type}'"
        exit 1
    fi

    require_provider

    if [[ "$VYBN_PROVIDER" == "ssh" ]]; then
        error "Resize is not supported for the SSH provider."
        error "Resize the server through your hosting provider instead."
        exit 1
    fi

    require_vm_exists

    local current_status
    current_status="$(provider_vm_status)"

    if [[ "$current_status" == "RUNNING" ]]; then
        info "VM must be stopped to resize. Stopping..."
        source "${VYBN_DIR}/lib/stop.sh"
        main
        info "Waiting for VM to stop..."
        local attempts=0
        while [[ "$(provider_vm_status)" != "TERMINATED" ]] && (( attempts < 30 )); do
            sleep 2
            attempts=$((attempts + 1))
        done
    fi

    info "Changing machine type to '${new_type}'..."
    gcloud compute instances set-machine-type "$VYBN_VM_NAME" \
        --machine-type="$new_type" \
        --zone="$VYBN_ZONE" --project="$VYBN_PROJECT" \
        --quiet

    success "Machine type changed to '${new_type}'."

    read -rp "Start the VM now? [Y/n] " start_confirm
    if [[ "$start_confirm" != [nN] ]]; then
        source "${VYBN_DIR}/lib/start.sh"
        main
    fi
}

cmd_help() {
    cat <<'EOF'
vybn resize — Change the VM machine type

Usage: vybn resize <machine-type>

Stops the VM (if running), changes its machine type, and offers to
restart it. Requires GCP provider.

Examples:
  vybn resize e2-standard-4     # Upgrade to 4 vCPU / 16 GB
  vybn resize e2-highmem-2      # Switch to memory-optimized
  vybn resize e2-micro           # Downgrade to save costs
EOF
}
