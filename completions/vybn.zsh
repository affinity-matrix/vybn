#compdef vybn
# Zsh completion for vybn

_vybn() {
    local -a commands
    commands=(
        'init:Interactive configuration wizard'
        'deploy:Create the VM'
        'connect:SSH + tmux attach'
        'session:Create a new Claude Code tmux window'
        'sync-skills:Copy Claude Code skills to the VM'
        'start:Start a stopped VM'
        'stop:Stop VM (preserves disk)'
        'destroy:Delete VM and network infrastructure'
        'status:Show VM state and tmux sessions'
        'ssh:Raw SSH to VM'
        'add-key:Add SSH public key(s) to the VM'
        'tunnel:Forward a TCP port'
        'check:Validate prerequisites before deploying'
        'switch-network:Switch network backend'
        'logs:View VM setup log'
        'update:Update Claude Code on the VM'
        'version:Show version'
        'help:Show help'
    )

    local -a tunnel_subcommands
    tunnel_subcommands=(
        'list:Show active tunnels'
        'kill:Stop a tunnel or all tunnels'
    )

    case "$words[2]" in
        tunnel)
            _describe -t subcommands 'tunnel subcommand' tunnel_subcommands
            ;;
        *)
            if (( CURRENT == 2 )); then
                _describe -t commands 'vybn command' commands
            fi
            ;;
    esac
}

_vybn "$@"
