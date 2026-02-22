#!/usr/bin/env bash
# vybn connect — Attach to a per-project tmux session

main() {
    local session_name=""
    local session_path=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path)
                if [[ -z "${2:-}" ]]; then
                    error "--path requires an argument"
                    exit 1
                fi
                session_path="$2"
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

    require_provider
    require_vm_running

    source "${VYBN_DIR}/lib/sessions_conf.sh"

    if [[ -n "$session_name" ]]; then
        # Mode 1: Named session
        _connect_named "$session_name" "$session_path"
    else
        # Mode 2/3: Auto-attach or picker
        _connect_auto
    fi
}

_connect_named() {
    local name="$1"
    local path="$2"

    _validate_session_name "$name" || exit 1

    local safe_name="${name//\'/\'\\\'\'}"

    # Check if tmux session already exists on VM
    local exists
    exists="$(vybn_ssh "tmux has-session -t '${safe_name}' 2>/dev/null && echo yes || echo no")"

    if [[ "$exists" == "yes" ]]; then
        info "Attaching to session '${name}'..."
        vybn_ssh_interactive \
            "export TERM='${VYBN_TERM}'; tmux attach -t '${safe_name}'"
        return
    fi

    # Resolve path: --path flag → sessions.conf → VYBN_PROJECTS_DIR/<name>
    if [[ -z "$path" ]]; then
        path="$(_remote_session_path "$name")"
    fi
    if [[ -z "$path" ]]; then
        path="${VYBN_PROJECTS_DIR}/${name}"
    fi

    # Validate path is absolute
    if [[ "$path" != /* ]]; then
        error "Session path must be absolute: '${path}'"
        exit 1
    fi

    local safe_path="${path//\'/\'\\\'\'}"

    info "Creating session '${name}' at ${path}..."

    # Build a startup script that launches Claude Code in the session directory.
    # Base64-encoded to avoid nested quoting issues across SSH + tmux layers.
    local window_script='#!/bin/bash
source "$HOME/.nvm/nvm.sh" 2>/dev/null || true
exec claude'

    local encoded
    encoded="$(printf '%s' "$window_script" | base64 | tr -d '\n')"

    vybn_ssh "\
        mkdir -p '${safe_path}' && \
        tmux new-session -d -s '${safe_name}' -c '${safe_path}' 'echo ${encoded} | base64 -d | bash'"

    # Register in sessions.conf
    _remote_sessions_conf_write "$name" "$path"

    info "Attaching to session '${name}'..."
    vybn_ssh_interactive \
        "export TERM='${VYBN_TERM}'; tmux attach -t '${safe_name}'"
}

_connect_auto() {
    local sessions
    sessions="$(_remote_tmux_list_sessions)"

    # Count sessions
    local count=0
    local session_lines=()
    if [[ -n "$sessions" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            session_lines+=("$line")
            count=$((count + 1))
        done <<< "$sessions"
    fi

    case "$count" in
        0)
            # No sessions — create default
            _connect_named "$VYBN_DEFAULT_SESSION" ""
            ;;
        1)
            # One session — auto-attach
            local name
            name="$(echo "${session_lines[0]}" | cut -d'|' -f1)"
            info "Attaching to session '${name}'..."
            local safe_name="${name//\'/\'\\\'\'}"
            vybn_ssh_interactive \
                "export TERM='${VYBN_TERM}'; tmux attach -t '${safe_name}'"
            ;;
        *)
            # Multiple sessions — show picker
            _show_picker "${session_lines[@]}"
            ;;
    esac
}

_show_picker() {
    local lines=("$@")
    local conf
    conf="$(_remote_sessions_conf_read)"

    echo "Active sessions:"
    echo
    local i=1
    for line in "${lines[@]}"; do
        local name windows status
        IFS='|' read -r name windows status <<< "$line"
        local path=""
        if [[ -n "$conf" ]]; then
            path="$(echo "$conf" | grep "^${name}=" | head -1 | cut -d= -f2-)"
            path="${path/#\/home\/${VYBN_USER}/\~}"
        fi
        local status_label
        if [[ "$status" == "attached" ]]; then
            status_label="attached"
        else
            status_label="detached"
        fi
        printf "  %d) %-20s  %s windows  [%s]" "$i" "$name" "$windows" "$status_label"
        if [[ -n "$path" ]]; then
            printf "  %s" "$path"
        fi
        echo
        i=$((i + 1))
    done
    echo "  n) Create new session"
    echo

    local choice
    read -rp "Select session: " choice

    if [[ "$choice" == "n" || "$choice" == "N" ]]; then
        local new_name
        read -rp "Session name: " new_name
        if [[ -z "$new_name" ]]; then
            error "Session name cannot be empty"
            exit 1
        fi
        _connect_named "$new_name" ""
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#lines[@]} )); then
        error "Invalid selection: ${choice}"
        exit 1
    fi

    local selected="${lines[$((choice - 1))]}"
    local name
    name="$(echo "$selected" | cut -d'|' -f1)"
    local safe_name="${name//\'/\'\\\'\'}"
    info "Attaching to session '${name}'..."
    vybn_ssh_interactive \
        "export TERM='${VYBN_TERM}'; tmux attach -t '${safe_name}'"
}

cmd_help() {
    cat <<'EOF'
vybn connect — Attach to a per-project tmux session

Usage:
  vybn connect <name> [--path /abs/path]   Create/attach to named session
  vybn connect                             Auto-attach or show picker

With a session name, creates a new tmux session (if needed) with its own
working directory and launches Claude Code. The session directory defaults
to $VYBN_PROJECTS_DIR/<name> but can be overridden with --path.

With no arguments:
  - If no sessions exist, creates the default session (scratchpad)
  - If one session exists, attaches to it
  - If multiple sessions exist, shows an interactive picker

Options:
  --path <path>    Set the session's working directory (absolute path on VM)

Examples:
  vybn connect                           # Auto-attach or picker
  vybn connect myproject                 # Create/attach "myproject" session
  vybn connect myproject --path /opt/app # Use custom directory
EOF
}
