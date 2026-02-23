#!/usr/bin/env bash
# vybn keygen — Generate SSH key on VM and print the public key

main() {
    local force=false
    local key_type="ed25519"
    local comment=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                force=true
                shift
                ;;
            --type|-t)
                key_type="${2:-}"
                if [[ -z "$key_type" ]]; then
                    error "--type requires a value (ed25519 or rsa)"
                    exit 1
                fi
                if [[ "$key_type" != "ed25519" && "$key_type" != "rsa" ]]; then
                    error "Unsupported key type: '${key_type}' (use ed25519 or rsa)"
                    exit 1
                fi
                shift 2
                ;;
            --comment|-C)
                comment="${2:-}"
                if [[ -z "$comment" ]]; then
                    error "--comment requires a value"
                    exit 1
                fi
                if ! [[ "$comment" =~ ^[a-zA-Z0-9@._:\ /-]+$ ]]; then
                    error "Invalid comment: contains disallowed characters"
                    exit 1
                fi
                shift 2
                ;;
            -*)
                error "Unknown option: $1"
                cmd_help >&2
                exit 1
                ;;
            *)
                error "Unexpected argument: $1"
                cmd_help >&2
                exit 1
                ;;
        esac
    done

    require_provider
    require_vm_running

    # Default comment uses VM name (resolved by require_provider)
    if [[ -z "$comment" ]]; then
        comment="claude@${VYBN_VM_NAME}"
    fi

    local key_file
    if [[ "$key_type" == "ed25519" ]]; then
        key_file='.ssh/id_ed25519'
    else
        key_file='.ssh/id_rsa'
    fi

    # Check if key already exists
    if vybn_ssh "test -f ~/${key_file}" 2>/dev/null; then
        if [[ "$force" == false ]]; then
            info "SSH key already exists on VM (~/${key_file})"
            info "Use --force to regenerate"
            echo
            vybn_ssh "cat ~/${key_file}.pub"
            return 0
        fi
        info "Removing existing key (--force)"
        vybn_ssh "rm -f ~/${key_file} ~/${key_file}.pub"
    fi

    info "Generating ${key_type} SSH key on VM..."
    vybn_ssh "ssh-keygen -t '${key_type}' -f ~/${key_file} -N '' -C '${comment}' -q"

    success "SSH key generated"
    echo
    info "Add this public key to GitHub: https://github.com/settings/ssh/new"
    echo
    vybn_ssh "cat ~/${key_file}.pub"
}

cmd_help() {
    cat <<'EOF'
vybn keygen — Generate SSH key on VM and print the public key

Usage: vybn keygen [OPTIONS]

Options:
  --force, -f            Overwrite existing key
  --type, -t <type>      Key algorithm: ed25519 (default) or rsa
  --comment, -C <text>   Key comment (default: claude@<VM name>)

Generates an SSH key pair on the VM and prints the public key.
If a key already exists, prints it without regenerating (use --force
to overwrite).

Quiet mode (vybn --quiet keygen) outputs only the raw public key,
suitable for piping to pbcopy.

Examples:
  vybn keygen                    # Generate ed25519 key, print pubkey
  vybn keygen --force            # Regenerate key
  vybn keygen --type rsa         # Generate RSA key instead
  vybn keygen --comment me@work  # Custom key comment
  vybn --quiet keygen | pbcopy   # Copy pubkey to clipboard
EOF
}
