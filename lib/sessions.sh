#!/usr/bin/env bash
# vybn sessions — List tmux sessions on the VM

main() {
    require_provider
    require_vm_running

    source "${VYBN_DIR}/lib/sessions_conf.sh"

    # Read session registry and tmux session list
    local conf sessions
    conf="$(_remote_sessions_conf_read)"
    sessions="$(_remote_tmux_list_sessions)"

    if [[ -z "$sessions" ]]; then
        info "No active tmux sessions on the VM."
        info "Start one with: vybn connect <name>"
        return
    fi

    printf "%-20s  %-8s  %-10s  %s\n" "SESSION" "WINDOWS" "STATUS" "PATH"
    printf "%-20s  %-8s  %-10s  %s\n" "-------" "-------" "------" "----"

    while IFS='|' read -r name windows status; do
        [[ -z "$name" ]] && continue
        # Look up path from sessions.conf
        local path=""
        if [[ -n "$conf" ]]; then
            path="$(echo "$conf" | grep "^${name}=" | head -1 | cut -d= -f2-)"
        fi
        # Shorten home directory for display
        path="${path/#\/home\/${VYBN_USER}/\~}"
        printf "%-20s  %-8s  %-10s  %s\n" "$name" "$windows" "$status" "$path"
    done <<< "$sessions"
}

cmd_help() {
    cat <<'EOF'
vybn sessions — List tmux sessions on the VM

Usage: vybn sessions

Aliases: vybn list

Displays all active tmux sessions with window count, attached/detached
status, and working directory (from session registry).

Examples:
  vybn sessions         # List all sessions
  vybn list             # Same thing
EOF
}
