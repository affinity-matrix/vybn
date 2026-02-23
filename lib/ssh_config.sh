#!/usr/bin/env bash
# vybn ssh-config — Generate SSH config block for the VM

_ssh_config_block() {
    local host_alias="${VYBN_VM_NAME}"
    local user="${VYBN_USER}"

    local block=""
    block+="# vybn-ssh-start — managed by vybn, do not edit"$'\n'
    block+="Host ${host_alias}"$'\n'
    block+="  User ${user}"$'\n'

    case "$VYBN_NETWORK" in
        tailscale)
            local hostname="${VYBN_TAILSCALE_HOSTNAME:-$VYBN_VM_NAME}"
            local key_dir="${VYBN_SSH_KEY_DIR:-$HOME/.vybn/ssh}"
            block+="  HostName ${hostname}"$'\n'
            if [[ -f "${key_dir}/id_ed25519" ]]; then
                block+="  IdentityFile ${key_dir}/id_ed25519"$'\n'
            fi
            if [[ -f "${key_dir}/known_hosts" ]]; then
                block+="  UserKnownHostsFile ${key_dir}/known_hosts"$'\n'
            fi
            block+="  StrictHostKeyChecking accept-new"$'\n'
            ;;
        iap)
            block+="  ProxyCommand gcloud compute ssh %r@${VYBN_VM_NAME} --zone=${VYBN_ZONE} --project=${VYBN_PROJECT} --tunnel-through-iap --plain -- -W %h:%p"$'\n'
            ;;
        ssh)
            block+="  HostName ${VYBN_SSH_HOST}"$'\n'
            if [[ "${VYBN_SSH_PORT:-22}" != "22" ]]; then
                block+="  Port ${VYBN_SSH_PORT}"$'\n'
            fi
            if [[ -n "${VYBN_SSH_KEY:-}" ]]; then
                block+="  IdentityFile ${VYBN_SSH_KEY}"$'\n'
            fi
            ;;
    esac

    block+="# vybn-ssh-end"

    printf '%s' "$block"
}

main() {
    local append=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --append) append=true; shift ;;
            *) error "Unknown option: $1"; exit 1 ;;
        esac
    done

    require_provider

    if [[ "$append" == true ]]; then
        local ssh_config="$HOME/.ssh/config"
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"

        local block
        block="$(_ssh_config_block)"

        # Idempotent: remove old managed block if present, then write new
        if [[ -f "$ssh_config" ]]; then
            local tmpfile="${ssh_config}.vybn.tmp.$$"
            sed '/^# vybn-ssh-start/,/^# vybn-ssh-end/d' "$ssh_config" > "$tmpfile"
            # Remove trailing blank lines left by removal
            {
                cat "$tmpfile"
                echo ""
                echo "$block"
            } > "$ssh_config"
            rm -f "$tmpfile"
        else
            echo "$block" > "$ssh_config"
        fi

        chmod 600 "$ssh_config"
        success "SSH config for '${VYBN_VM_NAME}' written to ${ssh_config}"
    else
        _ssh_config_block
        echo
    fi
}

cmd_help() {
    cat <<'EOF'
vybn ssh-config — Generate SSH config block for the VM

Usage: vybn ssh-config [OPTIONS]

Outputs an SSH config block that lets you connect with plain `ssh <vm-name>`
instead of `vybn connect`. Supports tailscale, iap, and ssh network backends.

Options:
  --append    Write to ~/.ssh/config (idempotent — replaces existing block)

The managed block is delimited by `# vybn-ssh-start` / `# vybn-ssh-end`
markers, distinct from the `vybn code` block.

Examples:
  vybn ssh-config                      # Print config block
  vybn ssh-config --append             # Write to ~/.ssh/config
  vybn ssh-config >> ~/.ssh/config     # Manual append
EOF
}
