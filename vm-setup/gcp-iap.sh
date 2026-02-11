# VM setup variant: GCP + IAP
# Appended after base.sh at deploy time — no shebang needed.

# GCP guest attributes implementation (overrides base.sh no-op)
_publish_guest_attr() {
    local key="$1" value="$2"
    curl -sf -X PUT --data "$value" \
        "http://metadata.google.internal/computeMetadata/v1/instance/guest-attributes/vybn/${key}" \
        -H "Metadata-Flavor: Google" 2>/dev/null || true
}

_publish_guest_attr setup-status running

log "=== vybn VM setup starting (iap) ==="

setup_system_packages
setup_user
setup_toolchains
setup_claude_code
setup_extra_packages
setup_tmux
setup_claude_hooks
setup_ssh_hardening
setup_bashrc
setup_complete
