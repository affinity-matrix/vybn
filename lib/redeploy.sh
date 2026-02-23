#!/usr/bin/env bash
# vybn redeploy — Destroy and recreate the VM

main() {
    local skip_confirm=false
    local auto_connect=false
    local extra_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes) skip_confirm=true; shift ;;
            --connect) auto_connect=true; shift ;;
            *) extra_args+=("$1"); shift ;;
        esac
    done

    require_provider

    if [[ "$skip_confirm" != true ]]; then
        warn "This will DESTROY the existing VM and all data on it,"
        warn "then create a fresh VM with the current configuration."
        echo
        read -rp "Continue? [y/N] " confirm
        if [[ "$confirm" != [yY] ]]; then
            info "Cancelled."
            return
        fi
    fi

    _run_hook pre-redeploy

    # Destroy (source and call directly to stay in-process)
    source "${VYBN_DIR}/lib/destroy.sh"
    info "Destroying existing VM..."
    main -y 2>/dev/null || true

    # Deploy
    source "${VYBN_DIR}/lib/deploy.sh"
    local deploy_args=(-y)
    if [[ "$auto_connect" == true ]]; then
        deploy_args+=(--connect)
    fi
    deploy_args+=("${extra_args[@]}")
    main "${deploy_args[@]}"

    _run_hook post-redeploy
}

cmd_help() {
    cat <<'EOF'
vybn redeploy — Destroy and recreate the VM

Usage: vybn redeploy [OPTIONS]

Destroys the existing VM and creates a fresh one with the current
configuration. This is a shortcut for `vybn destroy -y && vybn deploy`.

Options:
  -y, --yes     Skip confirmation prompt
  --connect     Connect to tmux session after deploy

Examples:
  vybn redeploy                 # Interactive confirmation
  vybn redeploy -y --connect    # Non-interactive, connect after
EOF
}
