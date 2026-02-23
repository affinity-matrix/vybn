#!/usr/bin/env bash
# vybn self-update — Update vybn itself

main() {
    local check_only=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check) check_only=true; shift ;;
            *) error "Unknown option: $1"; exit 1 ;;
        esac
    done

    # Detect install method
    local install_dir="${VYBN_DIR}"
    local update_method=""

    if [[ -d "${install_dir}/.git" ]]; then
        update_method="git"
    else
        update_method="manual"
    fi

    if [[ "$check_only" == true ]]; then
        case "$update_method" in
            git)
                info "Checking for updates..."
                (cd "$install_dir" && git fetch --quiet origin 2>/dev/null) || {
                    error "Could not check for updates (git fetch failed)"
                    exit 1
                }
                local behind
                behind="$(cd "$install_dir" && git rev-list --count HEAD..origin/main 2>/dev/null)" || behind=0
                if (( behind > 0 )); then
                    info "${behind} new commit(s) available."
                    info "Run 'vybn self-update' to update."
                else
                    success "vybn is up to date (${VYBN_VERSION})."
                fi
                ;;
            manual)
                warn "Cannot check for updates (not a git install)."
                info "Re-run the install script to update."
                ;;
        esac
        return
    fi

    case "$update_method" in
        git)
            info "Updating vybn via git pull..."
            (cd "$install_dir" && git pull --ff-only origin main) || {
                error "Update failed. You may need to resolve conflicts manually."
                error "  cd ${install_dir} && git status"
                exit 1
            }
            # Re-read version from updated config
            local new_version
            new_version="$(grep '^VYBN_VERSION=' "${install_dir}/lib/config.sh" | cut -d'"' -f2)" || new_version="unknown"
            success "vybn updated to ${new_version}."
            ;;
        manual)
            warn "vybn was not installed via git."
            info "To update, re-run the install script:"
            info "  curl -fsSL https://raw.githubusercontent.com/vybn-cli/vybn/main/install.sh | bash"
            ;;
    esac
}

cmd_help() {
    cat <<'EOF'
vybn self-update — Update vybn itself

Usage: vybn self-update [OPTIONS]

Options:
  --check    Check for updates without installing

Updates the vybn CLI to the latest version. Supports git-based installs
(via git pull) and notifies manual installs to re-run the installer.

Examples:
  vybn self-update           # Update now
  vybn self-update --check   # Just check for new versions
EOF
}
