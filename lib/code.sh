#!/usr/bin/env bash
# vybn code — Open VS Code / Cursor on the VM via Remote SSH

# --- SSH config management ---

_ssh_config_file() {
    echo "$HOME/.ssh/config"
}

_ssh_config_current() {
    local cfg
    cfg="$(_ssh_config_file)"
    [[ -f "$cfg" ]] || return 0
    sed -n '/^# vybn-start/,/^# vybn-end/p' "$cfg"
}

_ssh_config_block() {
    local block=""
    block+="# vybn-start — managed by vybn, do not edit"$'\n'
    block+="Host vybn"$'\n'

    case "$VYBN_NETWORK" in
        tailscale)
            local hostname
            hostname="$(_ts_ssh_host)"
            local key_dir="${VYBN_SSH_KEY_DIR:-$HOME/.vybn/ssh}"
            block+="  HostName ${hostname}"$'\n'
            block+="  IdentityFile ${key_dir}/id_ed25519"$'\n'
            block+="  UserKnownHostsFile ${key_dir}/known_hosts"$'\n'
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

    block+="  User ${VYBN_USER}"$'\n'
    block+="  ForwardAgent yes"$'\n'
    block+="  ServerAliveInterval 5"$'\n'
    block+="  ServerAliveCountMax 3"$'\n'
    block+="# vybn-end"

    printf '%s' "$block"
}

_write_ssh_config() {
    local cfg
    cfg="$(_ssh_config_file)"

    local new_block
    new_block="$(_ssh_config_block)"

    local current
    current="$(_ssh_config_current)"

    # Idempotent: skip if unchanged
    if [[ "$new_block" == "$current" ]]; then
        return 0
    fi

    # Ensure ~/.ssh exists with correct permissions
    local ssh_dir
    ssh_dir="$(dirname "$cfg")"
    if [[ ! -d "$ssh_dir" ]]; then
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
    fi

    if [[ ! -f "$cfg" ]]; then
        touch "$cfg"
        chmod 600 "$cfg"
    fi

    # Remove old managed block if present
    if grep -q '^# vybn-start' "$cfg" 2>/dev/null; then
        # Use a temp file to avoid sed -i portability issues
        local tmp
        tmp="$(mktemp)"
        sed '/^# vybn-start/,/^# vybn-end/d' "$cfg" > "$tmp"
        mv "$tmp" "$cfg"
        chmod 600 "$cfg"
    fi

    # Append new block
    # Ensure file ends with a newline before appending
    if [[ -s "$cfg" ]] && [[ "$(tail -c1 "$cfg")" != "" ]]; then
        echo >> "$cfg"
    fi
    echo "$new_block" >> "$cfg"

    success "SSH config updated (~/.ssh/config)"
}

_remove_ssh_config() {
    local cfg
    cfg="$(_ssh_config_file)"
    [[ -f "$cfg" ]] || return 0
    grep -q '^# vybn-start' "$cfg" 2>/dev/null || return 0

    local tmp
    tmp="$(mktemp)"
    sed '/^# vybn-start/,/^# vybn-end/d' "$cfg" > "$tmp"
    mv "$tmp" "$cfg"
    chmod 600 "$cfg"
}

# --- Remote path resolution ---

_resolve_remote_path() {
    local session_name="${1:-}"
    local explicit_path="${2:-}"

    # Mode 1: explicit --path
    if [[ -n "$explicit_path" ]]; then
        echo "$explicit_path"
        return
    fi

    # Mode 2: session name given — look up in sessions.conf
    if [[ -n "$session_name" ]]; then
        local path
        path="$(_remote_session_path "$session_name")"
        if [[ -n "$path" ]]; then
            echo "$path"
        else
            echo "${VYBN_PROJECTS_DIR}/${session_name}"
        fi
        return
    fi

    # Mode 3: no args — try matching basename of CWD
    local basename
    basename="$(basename "$PWD")"
    local conf
    conf="$(_remote_sessions_conf_read)"
    if [[ -n "$conf" ]]; then
        local match
        match="$(echo "$conf" | grep "^${basename}=" | head -1 | cut -d= -f2-)"
        if [[ -n "$match" ]]; then
            local answer
            read -rp "Open '${match}' on VM? [Y/n] " answer
            if [[ -z "$answer" || "$answer" =~ ^[Yy] ]]; then
                echo "$match"
                return
            fi
        fi
    fi

    echo "$VYBN_PROJECTS_DIR"
}

# --- Editor detection and launch ---

_detect_editor() {
    if [[ -n "${VYBN_EDITOR:-}" ]]; then
        case "$VYBN_EDITOR" in
            code|cursor) ;;
            *)
                warn "VYBN_EDITOR='${VYBN_EDITOR}' is not recognized (expected 'code' or 'cursor')"
                return
                ;;
        esac
        if command -v "$VYBN_EDITOR" &>/dev/null; then
            echo "$VYBN_EDITOR"
            return
        fi
        # Try common macOS paths
        local app_path=""
        if [[ "$VYBN_EDITOR" == "cursor" ]]; then
            app_path="/Applications/Cursor.app/Contents/Resources/app/bin/cursor"
        elif [[ "$VYBN_EDITOR" == "code" ]]; then
            app_path="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
        fi
        if [[ -n "$app_path" && -x "$app_path" ]]; then
            echo "$app_path"
            return
        fi
        warn "VYBN_EDITOR='${VYBN_EDITOR}' not found in PATH"
        return
    fi

    # Auto-detect: prefer cursor, then code
    for cmd in cursor code; do
        if command -v "$cmd" &>/dev/null; then
            echo "$cmd"
            return
        fi
    done

    # Try common macOS application paths
    local -a app_paths=(
        "/Applications/Cursor.app/Contents/Resources/app/bin/cursor"
        "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
    )
    for app_path in "${app_paths[@]}"; do
        if [[ -x "$app_path" ]]; then
            echo "$app_path"
            return
        fi
    done
}

_launch_editor() {
    local remote_path="$1"
    local editor
    editor="$(_detect_editor)"

    if [[ -z "$editor" ]]; then
        echo
        info "SSH config is ready. Connect with:"
        echo "  ssh vybn"
        echo
        info "To open in VS Code or Cursor:"
        echo "  code --remote \"ssh-remote+vybn\" \"${remote_path}\""
        echo "  cursor --remote \"ssh-remote+vybn\" \"${remote_path}\""
        echo
        info "Or add 'vybn' as a host in the Remote SSH extension."
        return
    fi

    local editor_name
    editor_name="$(basename "$editor")"
    info "Opening ${editor_name} → vybn:${remote_path}"
    "$editor" --remote "ssh-remote+vybn" "$remote_path"
}

# --- Command entry point ---

main() {
    local session_name=""
    local explicit_path=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path)
                if [[ -z "${2:-}" ]]; then
                    error "--path requires an argument"
                    exit 1
                fi
                explicit_path="$2"
                shift 2
                ;;
            -*)
                error "Unknown option: $1"
                exit 1
                ;;
            *)
                if [[ -z "$session_name" ]]; then
                    session_name="$1"
                else
                    error "Unexpected argument: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate explicit path is absolute
    if [[ -n "$explicit_path" && "$explicit_path" != /* ]]; then
        error "Path must be absolute: '${explicit_path}'"
        exit 1
    fi

    require_provider
    require_vm_running

    source "${VYBN_DIR}/lib/sessions_conf.sh"

    _write_ssh_config

    local remote_path
    remote_path="$(_resolve_remote_path "$session_name" "$explicit_path")"

    _launch_editor "$remote_path"
}

cmd_help() {
    cat <<'EOF'
vybn code — Open VS Code / Cursor on the VM via Remote SSH

Usage:
  vybn code [name] [--path /abs/path]

Opens VS Code or Cursor connected to the VM using the Remote SSH extension.
Automatically manages an SSH config entry (Host vybn) in ~/.ssh/config.

Arguments:
  name           Session name — opens its registered directory from sessions.conf,
                 or falls back to $VYBN_PROJECTS_DIR/<name>
  --path <path>  Explicit absolute path on the VM to open

With no arguments, checks if basename of the current directory matches a
session name on the VM and prompts to open it. Otherwise opens $VYBN_PROJECTS_DIR.

Editor selection:
  Set VYBN_EDITOR=code or VYBN_EDITOR=cursor in ~/.vybnrc.
  Auto-detects if not set (prefers Cursor, then VS Code).
  If neither CLI is found, prints manual connection instructions.

Examples:
  vybn code                         # Auto-detect project or open home
  vybn code myproject               # Open myproject's directory
  vybn code --path /opt/app         # Open explicit path
EOF
}
