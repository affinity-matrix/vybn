#compdef vybn
# Zsh completion for vybn

_vybn() {
    local -a commands
    commands=(
        'init:Interactive configuration wizard'
        'deploy:Create the VM'
        'connect:Attach to a per-project tmux session'
        'code:Open VS Code / Cursor on the VM'
        'sessions:List tmux sessions on the VM'
        'list:List tmux sessions (alias for sessions)'
        'push:Push files to VM'
        'pull:Pull files from VM'
        'sync-skills:Copy Claude Code skills to the VM'
        'start:Start a stopped VM'
        'stop:Stop VM (preserves disk)'
        'destroy:Delete VM and network infrastructure'
        'status:Show VM state and tmux sessions'
        'check:Validate prerequisites before deploying'
        'ssh:Raw SSH to VM'
        'add-key:Add SSH public key(s) to the VM'
        'keygen:Generate SSH key on VM'
        'tunnel:Forward a TCP port'
        'switch-network:Switch network backend'
        'logs:View VM logs'
        'update:Update Claude Code on the VM'
        'config:View and modify configuration'
        'ssh-config:Generate SSH config block'
        'ssh-fingerprint:Show VM SSH host key fingerprint'
        'redeploy:Destroy and recreate the VM'
        'resize:Change VM machine type'
        'snapshot:Create/manage disk snapshots'
        'self-update:Update vybn itself'
        'version:Show version'
        'help:Show help'
    )

    local -a tunnel_subcommands
    tunnel_subcommands=(
        'list:Show active tunnels'
        'kill:Stop a tunnel or all tunnels'
    )

    local -a config_subcommands
    config_subcommands=(
        'show:Show all active settings'
        'get:Get a single config value'
        'set:Set a config value'
        'edit:Open config in editor'
        'path:Print config file path'
    )

    local -a snapshot_subcommands
    snapshot_subcommands=(
        'create:Create a snapshot'
        'list:List snapshots'
        'delete:Delete a snapshot'
    )

    case "$words[2]" in
        tunnel)
            _describe -t subcommands 'tunnel subcommand' tunnel_subcommands
            ;;
        config)
            _describe -t subcommands 'config subcommand' config_subcommands
            ;;
        snapshot)
            _describe -t subcommands 'snapshot subcommand' snapshot_subcommands
            ;;
        deploy)
            _arguments \
                '-y[Skip confirmation]' \
                '--yes[Skip confirmation]' \
                '--connect[Connect after deploy]' \
                '--script-only[Output setup script]' \
                '--dry-run[Show what would be created]' \
                '--preemptible[Use preemptible/spot VM]' \
                '--spot[Use preemptible/spot VM]'
            ;;
        connect)
            _arguments \
                '--path[Session working directory]:path:_files -/' \
                {--reconnect,-r}'[Auto-reconnect on disconnect]'
            ;;
        status)
            _arguments \
                '--json[Output JSON]' \
                '--quick[Skip network and session query]'
            ;;
        *)
            if (( CURRENT == 2 )); then
                _describe -t commands 'vybn command' commands
            fi
            ;;
    esac
}

_vybn "$@"
