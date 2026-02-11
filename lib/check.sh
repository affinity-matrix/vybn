#!/usr/bin/env bash
# vybn check — Preflight validation of prerequisites

main() {
    local failures=0
    local gcloud_available=true

    info "Checking prerequisites for provider=${VYBN_PROVIDER}, network=${VYBN_NETWORK}..."
    echo

    if [[ "$VYBN_PROVIDER" == "ssh" ]]; then
        # SSH provider checks
        if command -v ssh &>/dev/null; then
            success "SSH client installed"
        else
            error "SSH client not found. Install an OpenSSH client."
            failures=$((failures + 1))
        fi

        if [[ -n "${VYBN_SSH_HOST:-}" ]]; then
            success "VYBN_SSH_HOST is set: ${VYBN_SSH_HOST}"
        else
            error "VYBN_SSH_HOST is not set. Set it in ~/.vybnrc or via environment."
            failures=$((failures + 1))
        fi

        if [[ -n "${VYBN_SSH_KEY:-}" ]]; then
            if [[ -r "$VYBN_SSH_KEY" ]]; then
                success "SSH key: ${VYBN_SSH_KEY}"
            else
                error "VYBN_SSH_KEY '${VYBN_SSH_KEY}' is not a readable file."
                failures=$((failures + 1))
            fi
        else
            info "No VYBN_SSH_KEY set (will use SSH agent or default keys)."
        fi

        # Test SSH connectivity
        if [[ -n "${VYBN_SSH_HOST:-}" ]]; then
            if _ssh_bootstrap_cmd "true" 2>/dev/null; then
                success "SSH connection to ${VYBN_SSH_HOST} succeeded"
            else
                error "Cannot connect to ${VYBN_SSH_HOST} via SSH."
                error "Check host, user (${VYBN_SSH_USER}), port (${VYBN_SSH_PORT}), and key settings."
                failures=$((failures + 1))
            fi
        fi
    else
        # GCP provider checks
        # 1. gcloud CLI
        if command -v gcloud &>/dev/null; then
            success "gcloud CLI installed ($(gcloud version --format='value(Google Cloud SDK)' 2>/dev/null || echo 'unknown version'))"
        else
            error "gcloud CLI not found. Install: https://cloud.google.com/sdk/docs/install"
            gcloud_available=false
            failures=$((failures + 1))
        fi

        # 2. gcloud authenticated (requires gcloud)
        if [[ "$gcloud_available" == true ]]; then
            local account
            account="$(gcloud auth list --filter='status:ACTIVE' --format='value(account)' 2>/dev/null || true)"
            if [[ -n "$account" ]]; then
                success "gcloud authenticated as ${account}"
            else
                error "gcloud not authenticated. Run: gcloud auth login"
                failures=$((failures + 1))
            fi
        fi

        # 3. GCP project set
        if [[ -n "$VYBN_PROJECT" ]]; then
            success "GCP project: ${VYBN_PROJECT}"
        else
            error "No GCP project set. Run: gcloud config set project <PROJECT_ID>"
            failures=$((failures + 1))
        fi

        # 4. Compute Engine API enabled (requires gcloud)
        if [[ "$gcloud_available" == true ]]; then
            if gcloud services list --enabled --filter='name:compute.googleapis.com' --format='value(name)' 2>/dev/null | grep -q 'compute.googleapis.com'; then
                success "Compute Engine API enabled"
            else
                error "Compute Engine API not enabled. Run: gcloud services enable compute.googleapis.com"
                failures=$((failures + 1))
            fi
        fi
    fi

    # 5. Network-specific checks
    if [[ "$VYBN_NETWORK" == "tailscale" ]]; then
        echo
        info "Tailscale checks:"

        if command -v tailscale &>/dev/null; then
            success "Tailscale CLI installed"
        else
            error "Tailscale CLI not found. Install: https://tailscale.com/download"
            failures=$((failures + 1))
        fi

        if tailscale status &>/dev/null; then
            success "Tailscale is running"
        else
            error "Tailscale is not running. Run: tailscale up"
            failures=$((failures + 1))
        fi

        if [[ -n "$VYBN_TAILSCALE_AUTHKEY" ]]; then
            success "Tailscale auth key is set"
        else
            error "VYBN_TAILSCALE_AUTHKEY not set. Generate at: https://login.tailscale.com/admin/settings/keys"
            failures=$((failures + 1))
        fi

        if [[ "${VYBN_EXTERNAL_IP}" != "true" ]]; then
            info "External IP will be enabled automatically (required for outbound internet during setup)."
        fi
    fi

    # 6. VM setup scripts exist (base + variant)
    local base_script="${VYBN_DIR}/vm-setup/base.sh"
    if [[ -f "$base_script" ]]; then
        success "VM setup base script found: vm-setup/base.sh"
    else
        error "VM setup base script missing: ${base_script}"
        failures=$((failures + 1))
    fi

    local variant_script="${VYBN_DIR}/vm-setup/${VYBN_PROVIDER}-${VYBN_NETWORK}.sh"
    if [[ -f "$variant_script" ]]; then
        success "VM setup variant script found: vm-setup/${VYBN_PROVIDER}-${VYBN_NETWORK}.sh"
    else
        error "VM setup variant script missing: ${variant_script}"
        failures=$((failures + 1))
    fi

    # Summary
    echo
    if (( failures == 0 )); then
        success "All checks passed. Ready to deploy."
    else
        error "${failures} check(s) failed. Fix the issues above before deploying."
        exit 1
    fi
}

cmd_help() {
    cat <<'EOF'
vybn check — Preflight validation

Usage: vybn check

Verifies that all prerequisites are met before deploying:
  - gcloud CLI installed and authenticated
  - GCP project configured
  - Compute Engine API enabled
  - Network-specific requirements (Tailscale CLI, auth key, etc.)
  - VM setup script exists for the provider/network combination

Exits 0 if all checks pass, 1 if any fail.
EOF
}
