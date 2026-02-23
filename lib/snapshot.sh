#!/usr/bin/env bash
# vybn snapshot — Create a disk snapshot of the VM

main() {
    local snapshot_name=""
    local subcmd="${1:-create}"

    case "$subcmd" in
        create)
            shift || true
            snapshot_name="${1:-}"
            ;;
        list)
            _snapshot_list
            return
            ;;
        delete)
            shift || true
            snapshot_name="${1:-}"
            if [[ -z "$snapshot_name" ]]; then
                error "Usage: vybn snapshot delete <name>"
                exit 1
            fi
            _snapshot_delete "$snapshot_name"
            return
            ;;
        *)
            # If first arg doesn't look like a subcommand, treat it as a snapshot name
            if [[ "$subcmd" != -* ]]; then
                snapshot_name="$subcmd"
            else
                error "Unknown option: $subcmd"
                cmd_help >&2
                exit 1
            fi
            ;;
    esac

    require_provider

    if [[ "$VYBN_PROVIDER" == "ssh" ]]; then
        error "Snapshots are not supported for the SSH provider."
        exit 1
    fi

    require_vm_exists

    # Auto-generate snapshot name if not provided
    if [[ -z "$snapshot_name" ]]; then
        snapshot_name="${VYBN_VM_NAME}-$(date +%Y%m%d-%H%M%S)"
    fi

    # Validate snapshot name
    if ! [[ "$snapshot_name" =~ ^[a-z][a-z0-9-]{0,61}[a-z0-9]$ ]]; then
        error "Invalid snapshot name: '${snapshot_name}'"
        error "Must be 1-63 characters: lowercase letters, digits, hyphens."
        exit 1
    fi

    info "Creating snapshot '${snapshot_name}' of VM '${VYBN_VM_NAME}'..."
    gcloud compute disks snapshot "$VYBN_VM_NAME" \
        --snapshot-names="$snapshot_name" \
        --zone="$VYBN_ZONE" --project="$VYBN_PROJECT" \
        --quiet

    success "Snapshot '${snapshot_name}' created."
}

_snapshot_list() {
    require_provider

    if [[ "$VYBN_PROVIDER" == "ssh" ]]; then
        error "Snapshots are not supported for the SSH provider."
        exit 1
    fi

    info "Snapshots for '${VYBN_VM_NAME}':"
    gcloud compute snapshots list \
        --filter="sourceDisk ~ .*/${VYBN_VM_NAME}$" \
        --project="$VYBN_PROJECT" \
        --format='table(name, diskSizeGb, creationTimestamp.date(), status)'
}

_snapshot_delete() {
    local name="$1"

    require_provider

    if [[ "$VYBN_PROVIDER" == "ssh" ]]; then
        error "Snapshots are not supported for the SSH provider."
        exit 1
    fi

    info "Deleting snapshot '${name}'..."
    gcloud compute snapshots delete "$name" \
        --project="$VYBN_PROJECT" \
        --quiet

    success "Snapshot '${name}' deleted."
}

cmd_help() {
    cat <<'EOF'
vybn snapshot — Create and manage disk snapshots

Usage:
  vybn snapshot [name]          Create a snapshot (auto-names if omitted)
  vybn snapshot create [name]   Same as above
  vybn snapshot list            List snapshots for this VM
  vybn snapshot delete <name>   Delete a snapshot

Creates a point-in-time snapshot of the VM's boot disk. Requires GCP provider.

Examples:
  vybn snapshot                           # Auto-named: vm-name-20250601-143022
  vybn snapshot before-upgrade            # Custom name
  vybn snapshot list                      # Show all snapshots
  vybn snapshot delete old-snapshot       # Clean up
EOF
}
