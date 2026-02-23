#!/usr/bin/env bash
# vybn update — Update Claude Code on the VM

# shellcheck disable=SC2120  # main() is called with "$@" from entry point
main() {
    local version="latest"
    local check_only=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check) check_only=true; shift ;;
            -*)      error "Unknown option: $1"; exit 1 ;;
            *)       version="$1"; shift ;;
        esac
    done

    # Validate version format
    if [[ "$version" != "latest" ]]; then
        if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
            error "Invalid version: '${version}'"
            error "Expected semver (e.g., 1.0.33) or 'latest'"
            exit 1
        fi
    fi

    require_provider
    require_vm_exists

    # Check if VM is running; offer to start if stopped
    local status
    status="$(provider_vm_status)"
    if [[ "$status" != "RUNNING" ]]; then
        if [[ "$status" == "TERMINATED" || "$status" == "STOPPED" ]]; then
            warn "VM '${VYBN_VM_NAME}' is stopped."
            read -rp "Start it now? [Y/n] " start_confirm
            if [[ "$start_confirm" != [nN] ]]; then
                source "${VYBN_DIR}/lib/start.sh"
                main
                info "Waiting for VM to become reachable..."
                local attempts=0
                while ! vybn_ssh "true" 2>/dev/null && (( attempts < 30 )); do
                    sleep 2
                    attempts=$((attempts + 1))
                done
            else
                error "VM must be running to update Claude Code."
                exit 1
            fi
        else
            error "VM '$VYBN_VM_NAME' is ${status}. Cannot update."
            exit 1
        fi
    fi

    if [[ "$check_only" == true ]]; then
        info "Checking installed Claude Code version..."
        local installed
        installed="$(vybn_ssh 'claude --version' 2>/dev/null || echo 'unknown')"
        echo "Installed: ${installed}"
        echo "Configured: ${VYBN_CLAUDE_CODE_VERSION}"
        return
    fi

    info "Updating Claude Code to ${version} on VM '${VYBN_VM_NAME}'..."

    if [[ "$version" == "latest" ]]; then
        vybn_ssh 'claude update'
    else
        vybn_ssh "curl -fsSL https://claude.ai/install.sh | bash -s -- -v ${version}"
    fi

    # Update the /usr/local/bin/claude symlink
    vybn_ssh 'sudo ln -sf "$HOME/.local/bin/claude" /usr/local/bin/claude'

    # Print installed version
    local installed
    installed="$(vybn_ssh 'claude --version' 2>/dev/null || true)"
    if [[ -n "$installed" ]]; then
        success "Claude Code updated: ${installed}"
    else
        success "Claude Code updated."
    fi
}

cmd_help() {
    cat <<'EOF'
vybn update — Update Claude Code on the VM

Usage: vybn update [OPTIONS] [version]

  version    Semver (e.g., 2.1.38) or 'latest' (default: latest)

Options:
  --check    Show installed vs configured version without updating

Updates the Claude Code CLI on the VM to the specified version.
If the VM is stopped, offers to start it first.

Examples:
  vybn update                  # Update to latest
  vybn update 2.1.38           # Install specific version
  vybn update --check          # Compare versions without updating
EOF
}
