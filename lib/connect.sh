#!/usr/bin/env bash
# vybn connect — SSH + tmux attach

main() {
    require_provider
    require_vm_running

    local window="${1:-}"

    # Validate window name
    if [[ -n "$window" ]]; then
        if [[ "$window" =~ [$'\n\r\t'] ]] || [[ ${#window} -gt 200 ]]; then
            error "Invalid window name"
            exit 1
        fi
    fi

    # Escape single quotes for safe embedding in remote shell strings
    local safe_session="${VYBN_TMUX_SESSION//\'/\'\\\'\'}"

    if [[ -n "$window" ]]; then
        local safe_window="${window//\'/\'\\\'\'}"
        # Connect to (or create) a specific window
        info "Connecting to window '${window}'..."
        vybn_ssh_interactive \
            "export TERM='${VYBN_TERM}'; \
             tmux has-session -t '${safe_session}' 2>/dev/null || tmux new-session -d -s '${safe_session}'; \
             tmux select-window -t '${safe_session}:${safe_window}' 2>/dev/null || tmux new-window -t '${safe_session}' -n '${safe_window}'; \
             tmux attach -t '${safe_session}'"
    else
        # Attach to session (create if needed)
        info "Connecting to tmux session '${VYBN_TMUX_SESSION}'..."
        vybn_ssh_interactive \
            "export TERM='${VYBN_TERM}'; \
             tmux attach -t '${safe_session}' 2>/dev/null || tmux new-session -s '${safe_session}'"
    fi
}

cmd_help() {
    cat <<'EOF'
vybn connect — SSH + tmux attach

Usage: vybn connect [window]

  window    Optional tmux window name to select or create.

With no arguments, attaches to the default tmux session (creating it
if needed). With a window name, selects that window or creates a new one.

Examples:
  vybn connect              # Attach to default session
  vybn connect myproject    # Attach and select/create "myproject" window
EOF
}
