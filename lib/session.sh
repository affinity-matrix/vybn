#!/usr/bin/env bash
# vybn session — Create a new Claude Code tmux window

main() {
    local name="${1:-}"
    local path="${2:-}"

    # Validate session/window name
    if [[ -n "$name" ]]; then
        if [[ "$name" =~ [$'\n\r\t'] ]] || [[ ${#name} -gt 200 ]]; then
            error "Invalid session name"
            exit 1
        fi
    fi

    if [[ -z "$name" ]]; then
        error "Usage: vybn session <name> [path]"
        error "  name — window name (e.g., myapp)"
        error "  path — directory to cd into (e.g., ~/projects/myapp)"
        exit 1
    fi

    require_provider
    require_vm_running

    info "Creating tmux window '${name}'..."

    # Escape single quotes for safe embedding in shell strings
    local safe_name="${name//\'/\'\\\'\'}"
    local safe_session="${VYBN_TMUX_SESSION//\'/\'\\\'\'}"

    # Build the window script and base64-encode it to avoid nested quoting issues
    # (local bash -> SSH -> remote bash -> tmux -> sh = 4 quoting layers)
    local window_script='#!/bin/bash
source "$HOME/.nvm/nvm.sh"
'
    if [[ -n "$path" ]]; then
        window_script+="cd $(printf '%q' "$path")"$'\n'
    fi
    window_script+='exec claude'

    local encoded
    encoded="$(printf '%s' "$window_script" | base64 | tr -d '\n')"

    # Ensure tmux session exists, then create a new window
    vybn_ssh "\
        tmux has-session -t '${safe_session}' 2>/dev/null || tmux new-session -d -s '${safe_session}'; \
        tmux new-window -t '${safe_session}' -n '${safe_name}' 'echo ${encoded} | base64 -d | bash'"

    success "Window '${name}' created with Claude Code."
    info "Connect with: vybn connect ${name}"
}

cmd_help() {
    cat <<'EOF'
vybn session — Create a new Claude Code tmux window

Usage: vybn session <name> [path]

  name    Window name (e.g., myapp)
  path    Directory to cd into before launching Claude Code

Creates a new tmux window in the default session, launches Claude Code
in it, and optionally changes to the specified directory first.

Examples:
  vybn session myapp                    # New window named "myapp"
  vybn session myapp ~/projects/myapp   # cd first, then launch claude
EOF
}
