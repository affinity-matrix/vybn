#!/usr/bin/env bash
# vybn logs — View VM setup log

main() {
    local lines=50
    local follow=false
    local log_source="setup"

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
            --system)
                log_source="system"
                shift
                ;;
            --claude)
                log_source="claude"
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

    local log_file
    case "$log_source" in
        setup)  log_file="/var/log/vybn-setup.log" ;;
        system) log_file="/var/log/syslog" ;;
        claude) log_file="\$HOME/.claude/logs/claude.log" ;;
    esac

    if [[ "$follow" == true ]]; then
        vybn_ssh_interactive "tail -f ${log_file}"
    else
        vybn_ssh "tail -n '${lines}' ${log_file}"
    fi
}

cmd_help() {
    cat <<'EOF'
vybn logs — View VM logs

Usage: vybn logs [OPTIONS]

Options:
  -n <lines>       Number of lines to show (default: 50)
  -f, --follow     Tail the log in real time (Ctrl-C to stop)
  --system         Show system log (syslog) instead of setup log
  --claude         Show Claude Code log instead of setup log

By default, shows the VM's setup log (/var/log/vybn-setup.log).
Use --system or --claude to view other log sources.

Examples:
  vybn logs                # Last 50 lines of setup log
  vybn logs -n 100         # Last 100 lines
  vybn logs -f             # Follow setup log in real time
  vybn logs --system       # System log
  vybn logs --claude -f    # Follow Claude Code log
EOF
}
