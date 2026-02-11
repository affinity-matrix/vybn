#!/usr/bin/env bash
# vybn update — Update Claude Code on the VM

main() {
    local version="${1:-latest}"

    # Validate version format
    if [[ "$version" != "latest" ]]; then
        if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
            error "Invalid version: '${version}'"
            error "Expected semver (e.g., 1.0.33) or 'latest'"
            exit 1
        fi
    fi

    require_provider
    require_vm_running

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

Usage: vybn update [version]

  version    Semver (e.g., 2.1.38) or 'latest' (default: latest)

Updates the Claude Code CLI on the VM to the specified version.
Uses the native installer for specific versions, or `claude update` for latest.
Also updates the /usr/local/bin/claude symlink.

Examples:
  vybn update              # Update to latest
  vybn update 2.1.38       # Install specific version via native installer
  vybn update latest       # Explicit latest (uses claude update)
EOF
}
