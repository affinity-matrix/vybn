#!/usr/bin/env bash
# vybn logs — View VM setup log

main() {
    local lines=50
    local follow=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n)
                shift
                lines="${1:-}"
                if ! [[ "$lines" =~ ^[0-9]+$ ]] || (( lines < 1 )); then
                    error "Invalid line count: '${lines}'"
                    exit 1
                fi
                shift
                ;;
            -f|--follow)
                follow=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    require_provider
    require_vm_running

    if [[ "$follow" == true ]]; then
        vybn_ssh_interactive "tail -f /var/log/vybn-setup.log"
    else
        vybn_ssh "tail -n '${lines}' /var/log/vybn-setup.log"
    fi
}

cmd_help() {
    cat <<'EOF'
vybn logs — View VM setup log

Usage: vybn logs [OPTIONS]

Options:
  -n <lines>       Number of lines to show (default: 50)
  -f, --follow     Tail the log in real time (Ctrl-C to stop)

Shows the VM's setup log (/var/log/vybn-setup.log). Useful for
debugging deploy issues or checking what the startup script did.

Examples:
  vybn logs              # Last 50 lines
  vybn logs -n 100       # Last 100 lines
  vybn logs -f           # Follow in real time
EOF
}
