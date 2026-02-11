#!/usr/bin/env bash
# Bash completion for vybn

_vybn_completions() {
    local cur prev commands tunnel_subcommands
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    commands="init deploy connect session sync-skills start stop destroy status ssh add-key tunnel check switch-network logs update version help"
    tunnel_subcommands="list kill"

    case "$prev" in
        tunnel)
            COMPREPLY=( $(compgen -W "$tunnel_subcommands" -- "$cur") )
            return
            ;;
        vybn)
            COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
            return
            ;;
    esac

    # Default: complete commands on first arg
    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
    fi
}

complete -F _vybn_completions vybn
