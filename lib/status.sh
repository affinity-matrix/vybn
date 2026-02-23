#!/usr/bin/env bash
# vybn status — Show VM state and tmux sessions

_fetch_sessions_raw() {
    vybn_ssh "
        conf=/home/${VYBN_USER}/.vybn/sessions.conf
        tmux list-sessions -F 'SESSION|#{session_name}|#{session_windows}|#{?session_attached,attached,detached}' 2>/dev/null | while IFS='|' read -r prefix name wins status; do
            path=\"\"
            if [ -f \"\$conf\" ]; then
                path=\$(grep \"^\${name}=\" \"\$conf\" 2>/dev/null | head -1 | cut -d= -f2-)
            fi
            echo \"SESSION|\${name}|\${wins}|\${status}|\${path}\"
            tmux list-windows -t \"\${name}\" -F 'WINDOW|#{window_index}|#{window_name}|#{?window_active,*,}' 2>/dev/null
        done
    " 2>/dev/null || true
}

_render_sessions_tree() {
    source "${VYBN_DIR}/lib/sessions_conf.sh"

    echo "=== Sessions ==="
    local raw
    raw="$(_fetch_sessions_raw)"

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

_status_json() {
    local vm_status="$1"
    local raw="$2"

    # Build sessions JSON array from raw session data (no jq)
    local sessions_json="[]"
    if [[ -n "$raw" ]]; then
        sessions_json="["
        local first=true
        while IFS='|' read -r tag rest; do
            [[ "$tag" != "SESSION" ]] && continue
            local name wins status path
            IFS='|' read -r name wins status path <<< "$rest"
            # Escape double quotes in name and path
            name="${name//\"/\\\"}"
            path="${path//\"/\\\"}"
            if [[ "$first" == true ]]; then
                first=false
            else
                sessions_json+=","
            fi
            sessions_json+="{\"name\":\"${name}\",\"windows\":${wins},\"status\":\"${status}\",\"path\":\"${path}\"}"
        done <<< "$raw"
        sessions_json+="]"
    fi

    echo "{\"exists\":true,\"vm_name\":\"${VYBN_VM_NAME}\",\"status\":\"${vm_status}\",\"provider\":\"${VYBN_PROVIDER}\",\"network\":\"${VYBN_NETWORK}\",\"sessions\":${sessions_json}}"
}

main() {
    local json_output=false
    local quick=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output=true; shift ;;
            --quick) quick=true; shift ;;
            *) error "Unknown option: $1"; exit 1 ;;
        esac
    done

    require_provider

    if [[ "$VYBN_PROVIDER" == "ssh" ]]; then
        local raw=""
        if [[ "$quick" != true ]]; then
            raw="$(_fetch_sessions_raw)"
        fi

        if [[ "$json_output" == true ]]; then
            _status_json "RUNNING" "$raw"
            return
        fi

        echo "=== Server: ${VYBN_SSH_HOST} ==="
        provider_vm_info
        echo

        if [[ "$quick" != true ]]; then
            # Network connectivity
            net_status
            echo

            # tmux sessions tree
            _render_sessions_tree
        fi
        return
    fi

    # Check if VM exists
    if ! provider_vm_exists; then
        if [[ "$json_output" == true ]]; then
            echo "{\"exists\":false,\"vm_name\":\"${VYBN_VM_NAME}\"}"
        else
            info "VM '${VYBN_VM_NAME}' does not exist."
            info "Run 'vybn deploy' to create it."
        fi
        return
    fi

    # VM details
    local vm_info
    vm_info="$(provider_vm_info)"

    local status
    status="$(provider_vm_status)"

    local raw=""
    if [[ "$status" == "RUNNING" ]] && [[ "$quick" != true ]]; then
        raw="$(_fetch_sessions_raw)"
    fi

    if [[ "$json_output" == true ]]; then
        _status_json "$status" "$raw"
        return
    fi

    echo "=== VM: ${VYBN_VM_NAME} ==="
    echo "$vm_info"
    echo

    # Network connectivity
    if [[ "$quick" != true ]]; then
        net_status
        echo
    fi

    # tmux sessions tree (only if running)
    if [[ "$status" == "RUNNING" ]] && [[ "$quick" != true ]]; then
        _render_sessions_tree
    fi
}

cmd_help() {
    cat <<'EOF'
vybn status — Show VM state and tmux sessions

Usage: vybn status [OPTIONS]

Options:
  --json      Output machine-readable JSON
  --quick     Skip network check and session query (faster)

Displays:
  - VM status, machine type, and external IP
  - Network connectivity info
  - Tree view of all tmux sessions with windows and paths

Examples:
  vybn status              # Full status
  vybn status --quick      # Just VM state, no SSH
  vybn status --json       # JSON output for scripting
EOF
}
