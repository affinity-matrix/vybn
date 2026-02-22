#!/usr/bin/env bash
# vybn status — Show VM state and tmux sessions

_render_sessions_tree() {
    source "${VYBN_DIR}/lib/sessions_conf.sh"

    echo "=== Sessions ==="
    # Single SSH call: get all sessions and windows in one shot
    local raw
    raw="$(vybn_ssh "
        conf=/home/${VYBN_USER}/.vybn/sessions.conf
        tmux list-sessions -F 'SESSION|#{session_name}|#{session_windows}|#{?session_attached,attached,detached}' 2>/dev/null | while IFS='|' read -r prefix name wins status; do
            path=\"\"
            if [ -f \"\$conf\" ]; then
                path=\$(grep \"^\${name}=\" \"\$conf\" 2>/dev/null | head -1 | cut -d= -f2-)
            fi
            echo \"SESSION|\${name}|\${wins}|\${status}|\${path}\"
            tmux list-windows -t \"\${name}\" -F 'WINDOW|#{window_index}|#{window_name}|#{?window_active,*,}' 2>/dev/null
        done
    " 2>/dev/null)" || true

    if [[ -z "$raw" ]]; then
        echo "  No active tmux sessions."
        return
    fi

    while IFS='|' read -r tag rest; do
        case "$tag" in
            SESSION)
                local name _wins status path
                IFS='|' read -r name _wins status path <<< "$rest"
                path="${path/#\/home\/${VYBN_USER}/\~}"
                local marker=" "
                if [[ "$status" == "attached" ]]; then
                    marker="*"
                fi
                printf "  %s %-20s" "$marker" "$name"
                if [[ -n "$path" ]]; then
                    printf "  (%s)" "$path"
                fi
                printf "  [%s]\n" "$status"
                ;;
            WINDOW)
                local idx wname active
                IFS='|' read -r idx wname active <<< "$rest"
                local active_marker=""
                if [[ "$active" == "*" ]]; then
                    active_marker=" (*)"
                fi
                printf "      %s: %s%s\n" "$idx" "$wname" "$active_marker"
                ;;
        esac
    done <<< "$raw"
}

main() {
    require_provider

    if [[ "$VYBN_PROVIDER" == "ssh" ]]; then
        echo "=== Server: ${VYBN_SSH_HOST} ==="
        provider_vm_info
        echo

        # Network connectivity
        net_status
        echo

        # tmux sessions tree
        _render_sessions_tree
        return
    fi

    # Check if VM exists
    if ! provider_vm_exists; then
        info "VM '${VYBN_VM_NAME}' does not exist."
        info "Run 'vybn deploy' to create it."
        return
    fi

    # VM details
    local vm_info
    vm_info="$(provider_vm_info)"

    local status
    status="$(provider_vm_status)"

    echo "=== VM: ${VYBN_VM_NAME} ==="
    echo "$vm_info"
    echo

    # Network connectivity
    net_status
    echo

    # tmux sessions tree (only if running)
    if [[ "$status" == "RUNNING" ]]; then
        _render_sessions_tree
    fi
}

cmd_help() {
    cat <<'EOF'
vybn status — Show VM state and tmux sessions

Usage: vybn status

Displays:
  - VM status, machine type, and external IP
  - Network connectivity info
  - Tree view of all tmux sessions with windows and paths
EOF
}
