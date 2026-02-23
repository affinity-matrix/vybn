#!/usr/bin/env bash
# Bash completion for vybn

_vybn_completions() {
    local cur prev commands
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    commands="init deploy connect code sessions push pull sync-skills start stop destroy status check ssh add-key keygen tunnel switch-network logs update config ssh-config ssh-fingerprint redeploy resize snapshot self-update version help"

    case "$prev" in
        tunnel)
            COMPREPLY=( $(compgen -W "list kill" -- "$cur") )
            return
            ;;
        config)
            COMPREPLY=( $(compgen -W "show get set edit path" -- "$cur") )
            return
            ;;
        snapshot)
            COMPREPLY=( $(compgen -W "create list delete" -- "$cur") )
            return
            ;;
        deploy)
            COMPREPLY=( $(compgen -W "-y --yes --connect --script-only --dry-run --preemptible --spot" -- "$cur") )
            return
            ;;
        connect)
            COMPREPLY=( $(compgen -W "--path --reconnect -r" -- "$cur") )
            return
            ;;
        status)
            COMPREPLY=( $(compgen -W "--json --quick" -- "$cur") )
            return
            ;;
        init)
            COMPREPLY=( $(compgen -W "-f --force --non-interactive" -- "$cur") )
            return
            ;;
        logs)
            COMPREPLY=( $(compgen -W "-n -f --follow --system --claude" -- "$cur") )
            return
            ;;
        update)
            COMPREPLY=( $(compgen -W "--check" -- "$cur") )
            return
            ;;
        keygen)
            COMPREPLY=( $(compgen -W "--force -f --type -t --comment -C" -- "$cur") )
            return
            ;;
        add-key)
            COMPREPLY=( $(compgen -W "--sshid --github --file" -- "$cur") )
            return
            ;;
        ssh-config)
            COMPREPLY=( $(compgen -W "--append" -- "$cur") )
            return
            ;;
        ssh-fingerprint)
            COMPREPLY=( $(compgen -W "--type -t" -- "$cur") )
            return
            ;;
        ssh)
            COMPREPLY=( $(compgen -W "-b --batch --" -- "$cur") )
            return
            ;;
        redeploy)
            COMPREPLY=( $(compgen -W "-y --yes --connect" -- "$cur") )
            return
            ;;
        self-update)
            COMPREPLY=( $(compgen -W "--check" -- "$cur") )
            return
            ;;
        destroy)
            COMPREPLY=( $(compgen -W "-y --yes" -- "$cur") )
            return
            ;;
        help)
            COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
            return
            ;;
        vybn)
            COMPREPLY=( $(compgen -W "$commands --quiet -q --verbose --no-color" -- "$cur") )
            return
            ;;
    esac

    # Default: complete commands on first arg
    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$commands --quiet -q --verbose --no-color" -- "$cur") )
    fi
}

complete -F _vybn_completions vybn
