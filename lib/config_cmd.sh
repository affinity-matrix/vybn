#!/usr/bin/env bash
# vybn config — Get, set, or show configuration values

_config_file() {
    echo "$HOME/.vybnrc"
}

_config_get() {
    local key="$1"
    local upper_key
    upper_key="VYBN_$(echo "$key" | tr '[:lower:]-' '[:upper:]_')"

    # Check current env value (includes defaults + .vybnrc overrides)
    local value="${!upper_key:-}"
    if [[ -n "$value" ]]; then
        echo "$value"
    else
        # Key not set
        return 1
    fi
}

_config_set() {
    local key="$1"
    local value="$2"
    local upper_key
    upper_key="VYBN_$(echo "$key" | tr '[:lower:]-' '[:upper:]_')"

    local rcfile
    rcfile="$(_config_file)"

    # Validate key name
    if ! [[ "$upper_key" =~ ^VYBN_[A-Z_]+$ ]]; then
        error "Invalid config key: '${key}'"
        exit 1
    fi

    # Validate value (no embedded newlines or shell metacharacters)
    if [[ "$value" =~ [$'\n\r'] ]]; then
        error "Config values cannot contain newlines"
        exit 1
    fi

    if [[ -f "$rcfile" ]]; then
        # Check if key exists (commented or uncommented)
        if grep -qE "^#?\s*${upper_key}=" "$rcfile"; then
            # Replace existing line
            local tmpfile="${rcfile}.tmp.$$"
            sed "s|^#*\s*${upper_key}=.*|${upper_key}=\"${value}\"|" "$rcfile" > "$tmpfile"
            mv "$tmpfile" "$rcfile"
            chmod 600 "$rcfile"
        else
            # Append
            echo "${upper_key}=\"${value}\"" >> "$rcfile"
        fi
    else
        # Create new rcfile
        {
            echo "# vybn configuration"
            echo "${upper_key}=\"${value}\""
        } > "$rcfile"
        chmod 600 "$rcfile"
    fi

    success "${upper_key}=${value}"
}

_config_show() {
    local rcfile
    rcfile="$(_config_file)"

    echo "=== Active Configuration ==="
    echo "  Provider:        ${VYBN_PROVIDER}"
    echo "  Network:         ${VYBN_NETWORK}"

    if [[ "$VYBN_PROVIDER" == "ssh" ]]; then
        echo "  SSH host:        ${VYBN_SSH_HOST:-<not set>}"
        echo "  SSH user:        ${VYBN_SSH_USER}"
        echo "  SSH port:        ${VYBN_SSH_PORT}"
    else
        echo "  Project:         ${VYBN_PROJECT:-<auto-detect>}"
        echo "  Zone:            ${VYBN_ZONE}"
        echo "  Machine type:    ${VYBN_MACHINE_TYPE}"
        echo "  Disk size:       ${VYBN_DISK_SIZE} GB"
        echo "  External IP:     ${VYBN_EXTERNAL_IP}"
    fi

    _resolve_vm_name
    echo "  VM name:         ${VYBN_VM_NAME:-<auto-generate>}"
    echo "  Toolchains:      ${VYBN_TOOLCHAINS}"
    echo "  Claude version:  ${VYBN_CLAUDE_CODE_VERSION}"

    if [[ -n "${VYBN_APT_PACKAGES}" ]]; then
        echo "  Apt packages:    ${VYBN_APT_PACKAGES}"
    fi
    if [[ -n "${VYBN_NPM_PACKAGES}" ]]; then
        echo "  Npm packages:    ${VYBN_NPM_PACKAGES}"
    fi
    if [[ -n "${VYBN_SETUP_SCRIPT}" ]]; then
        echo "  Setup script:    ${VYBN_SETUP_SCRIPT}"
    fi

    echo
    echo "=== Source ==="
    if [[ -f "$rcfile" ]]; then
        echo "  Config file: ${rcfile}"
    else
        echo "  Config file: ${rcfile} (not found — using defaults)"
    fi
    echo "  Hooks dir:   ${VYBN_HOOKS_DIR}"
    echo "  SSH keys:    ${VYBN_SSH_KEY_DIR}"
}

_config_edit() {
    local rcfile
    rcfile="$(_config_file)"

    if [[ ! -f "$rcfile" ]]; then
        info "No config file found. Run 'vybn init' to create one."
        exit 1
    fi

    local editor="${EDITOR:-${VISUAL:-vi}}"
    "$editor" "$rcfile"
}

main() {
    local subcmd="${1:-show}"
    shift || true

    case "$subcmd" in
        get)
            local key="${1:-}"
            if [[ -z "$key" ]]; then
                error "Usage: vybn config get <key>"
                exit 1
            fi
            _config_get "$key"
            ;;
        set)
            local key="${1:-}"
            local value="${2:-}"
            if [[ -z "$key" || -z "$value" ]]; then
                error "Usage: vybn config set <key> <value>"
                exit 1
            fi
            _config_set "$key" "$value"
            ;;
        show)
            _config_show
            ;;
        edit)
            _config_edit
            ;;
        path)
            _config_file
            ;;
        *)
            error "Unknown subcommand: ${subcmd}"
            echo
            cmd_help >&2
            exit 1
            ;;
    esac
}

cmd_help() {
    cat <<'EOF'
vybn config — View and modify configuration

Usage:
  vybn config              Show all active settings
  vybn config show         Show all active settings
  vybn config get <key>    Get a single config value
  vybn config set <k> <v>  Set a config value in ~/.vybnrc
  vybn config edit         Open ~/.vybnrc in $EDITOR
  vybn config path         Print path to config file

Keys use lowercase with hyphens (e.g., 'machine-type' for VYBN_MACHINE_TYPE).

Examples:
  vybn config get zone                      # → us-west1-a
  vybn config set machine-type e2-standard-4
  vybn config set disk-size 50
  vybn config edit
EOF
}
