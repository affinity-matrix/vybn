#!/usr/bin/env bash
# vybn add-key — Add SSH public key(s) to the VM

# SSH public key format regex (matches ssh-ed25519, ssh-rsa, ecdsa-*, FIDO2 sk-*)
_PUBKEY_REGEX='^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com) [A-Za-z0-9+/=]+( .+)?$'

_add_single_key() {
    local key="$1"

    # Validate: must be a single line
    local line_count
    line_count="$(printf '%s\n' "$key" | wc -l)"
    if [[ "$line_count" -ne 1 ]]; then
        error "Key contains multiple lines — rejecting"
        return 1
    fi

    # Validate: must match SSH public key format
    if ! [[ "$key" =~ $_PUBKEY_REGEX ]]; then
        error "Invalid SSH public key format"
        error "Expected: ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp* <base64> [comment]"
        return 1
    fi

    # Extract base64 portion for duplicate checking (safe to single-quote: only [A-Za-z0-9+/=])
    local key_data
    key_data="$(printf '%s' "$key" | awk '{print $2}')"

    # Check for duplicate
    if vybn_ssh "grep -qF '${key_data}' ~/.ssh/authorized_keys 2>/dev/null"; then
        info "Key already present on VM (skipped)"
        return 0
    fi

    # Append via stdin to avoid quoting issues with key comments
    printf '%s\n' "$key" | vybn_ssh 'cat >> ~/.ssh/authorized_keys'
    success "Key added to VM"
}

_fetch_sshid_keys() {
    local username="$1"

    # Validate username format
    if ! [[ "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error "Invalid SSH.id username: '${username}' (must be alphanumeric, hyphens, underscores only)"
        exit 1
    fi

    info "Fetching keys from sshid.io/${username}..."
    local response
    response="$(curl -sf --max-time 10 "https://sshid.io/${username}")" || {
        error "Could not fetch keys from sshid.io/${username}"
        error "Check the username and try again."
        exit 1
    }

    if [[ -z "$response" ]]; then
        error "No keys found at sshid.io/${username}"
        exit 1
    fi

    local count=0
    local errors=0
    while IFS= read -r line; do
        # Strip trailing \r from HTTP responses with \r\n line endings
        line="${line%$'\r'}"
        # Skip blank lines and comments
        [[ -z "$line" || "$line" == \#* ]] && continue
        if _add_single_key "$line"; then
            count=$((count + 1))
        else
            errors=$((errors + 1))
        fi
    done <<< "$response"

    if (( count == 0 && errors == 0 )); then
        warn "No valid keys found at sshid.io/${username}"
    elif (( errors > 0 )); then
        warn "Processed ${count} key(s), ${errors} skipped due to errors"
    else
        success "Processed ${count} key(s) from sshid.io/${username}"
    fi
}

_read_keys_from_file() {
    local filepath="$1"

    if [[ ! -f "$filepath" ]]; then
        error "File not found: ${filepath}"
        exit 1
    fi

    local count=0
    local errors=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        if _add_single_key "$line"; then
            count=$((count + 1))
        else
            errors=$((errors + 1))
        fi
    done < "$filepath"

    if (( count == 0 && errors == 0 )); then
        warn "No valid keys found in ${filepath}"
    elif (( errors > 0 )); then
        warn "Processed ${count} key(s), ${errors} skipped due to errors"
    else
        success "Processed ${count} key(s) from ${filepath}"
    fi
}

main() {
    local mode=""
    local sshid_user=""
    local key_file=""
    local inline_key=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sshid)
                [[ -n "$mode" ]] && { error "Only one of --sshid, --file, or inline key allowed"; exit 1; }
                mode="sshid"
                sshid_user="${2:-}"
                [[ -z "$sshid_user" ]] && { error "--sshid requires a username"; exit 1; }
                shift 2
                ;;
            --file)
                [[ -n "$mode" ]] && { error "Only one of --sshid, --file, or inline key allowed"; exit 1; }
                mode="file"
                key_file="${2:-}"
                [[ -z "$key_file" ]] && { error "--file requires a path"; exit 1; }
                shift 2
                ;;
            -*)
                error "Unknown option: $1"
                cmd_help >&2
                exit 1
                ;;
            *)
                [[ -n "$mode" ]] && { error "Only one of --sshid, --file, or inline key allowed"; exit 1; }
                mode="inline"
                inline_key="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$mode" ]]; then
        error "No key source specified"
        echo
        cmd_help >&2
        exit 1
    fi

    require_provider
    require_vm_running

    # Ensure ~/.ssh/authorized_keys exists on the VM
    vybn_ssh 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'

    case "$mode" in
        sshid)  _fetch_sshid_keys "$sshid_user" ;;
        file)   _read_keys_from_file "$key_file" ;;
        inline) _add_single_key "$inline_key" ;;
    esac
}

cmd_help() {
    cat <<'EOF'
vybn add-key — Add SSH public key(s) to the VM

Usage:
  vybn add-key --sshid <username>         Fetch keys from sshid.io
  vybn add-key --file <path>              Read keys from a local file
  vybn add-key '<ssh-ed25519 AAAA...>'    Add a single inline key

Modes:
  --sshid <username>   Fetch public keys from https://sshid.io/<username>.
                       Useful for adding mobile device keys from Termius.
  --file <path>        Read one or more keys from a local file (one per line).
                       Blank lines and #comments are skipped.
  <key>                Add a single SSH public key passed as an argument.

Exactly one mode must be specified.

Examples:
  vybn add-key --sshid johndoe
  vybn add-key --file ~/.ssh/id_ed25519.pub
  vybn add-key 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... user@device'
EOF
}
