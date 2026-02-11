#!/usr/bin/env bash
# vybn sync-skills — Copy Claude Code skills to VM

main() {
    require_provider
    require_vm_running

    local skills_dir="$HOME/.claude/skills"

    if [[ ! -d "$skills_dir" ]]; then
        error "No ~/.claude/skills/ directory found."
        exit 1
    fi

    local tar_flags=(-cf - --exclude .git)
    [[ "$(uname)" == "Darwin" ]] && tar_flags=(--no-mac-metadata "${tar_flags[@]}")

    vybn_ssh "mkdir -p ~/.claude/skills"

    local count=0
    for skill in "$skills_dir"/*/; do
        [[ -d "$skill" ]] || continue
        local name
        name="$(basename "$skill")"

        # Escape single quotes for safe embedding in remote shell string
        local safe_name="${name//\'/\'\\\'\'}"

        info "Syncing skill: ${name}"
        tar "${tar_flags[@]}" -C "$skill" . | \
            vybn_ssh "rm -rf ~/.claude/skills/'${safe_name}' && mkdir -p ~/.claude/skills/'${safe_name}' && tar -xf - -C ~/.claude/skills/'${safe_name}'"
        ((count++))
    done

    if [[ "$count" -eq 0 ]]; then
        warn "No skills found in ${skills_dir}."
    else
        success "Synced ${count} skill(s) to VM."
    fi
}

cmd_help() {
    cat <<'EOF'
vybn sync-skills — Copy Claude Code skills to VM

Usage: vybn sync-skills

Copies all installed skills from ~/.claude/skills/ to the VM.
Resolves symlinks and excludes .git directories to keep transfers lean.

Run this after installing or updating skills locally.
EOF
}
