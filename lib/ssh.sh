#!/usr/bin/env bash
# vybn ssh — Raw SSH passthrough

main() {
    require_provider
    require_vm_running

    local batch=false
    local args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b|--batch) batch=true; shift ;;
            *)          args+=("$1"); shift ;;
        esac
    done

    if [[ ${#args[@]} -eq 0 ]]; then
        # Interactive shell
        vybn_ssh_interactive
    elif [[ "$batch" == true ]]; then
        # Batch mode: no PTY, no interactive prompts
        vybn_ssh -T -o BatchMode=yes "${args[@]}"
    else
        # Run a command
        vybn_ssh "${args[@]}"
    fi
}

cmd_help() {
    cat <<'EOF'
vybn ssh — Raw SSH to the VM

Usage: vybn ssh [OPTIONS] [command]

With no arguments, opens an interactive shell on the VM.
With a command, runs it remotely and returns the output.

Options:
  -b, --batch       Batch mode (no PTY, no interactive prompts)

Examples:
  vybn ssh                        # Interactive shell
  vybn ssh 'claude --version'     # Run a remote command
  vybn ssh 'tmux list-sessions'   # Check tmux sessions
  vybn ssh --batch 'cat /etc/os-release'  # Batch mode
EOF
}
