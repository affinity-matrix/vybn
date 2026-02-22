#!/usr/bin/env bash
# vybn pull — Pull files from VM

_PULL_DEFAULT_EXCLUDES=(
    .git
    .vybn
    node_modules
    __pycache__
    .venv
    venv
    dist
    build
    .next
    .cache
    .tox
    .mypy_cache
    .pytest_cache
    .ruff_cache
    "*.pyc"
    .DS_Store
    .env.local
    .turbo
    coverage
)

_check_rsync() {
    if ! command -v rsync &>/dev/null; then
        error "rsync is not installed locally."
        error "Install it with your package manager (e.g., apt install rsync, brew install rsync)."
        exit 1
    fi
}

_parse_pull_args() {
    _PULL_DRY_RUN=false
    _PULL_YES=false
    _PULL_DELETE=false
    _PULL_VERBOSE=false
    _PULL_EXCLUDES=()
    _PULL_INCLUDES=()
    _PULL_EXTRA_ARGS=()
    _PULL_POSITIONAL=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                _PULL_DRY_RUN=true
                shift
                ;;
            -y|--yes)
                _PULL_YES=true
                shift
                ;;
            --delete)
                _PULL_DELETE=true
                shift
                ;;
            -v|--verbose)
                _PULL_VERBOSE=true
                shift
                ;;
            --exclude)
                if [[ -z "${2:-}" ]]; then
                    error "--exclude requires a pattern argument"
                    exit 1
                fi
                _PULL_EXCLUDES+=("$2")
                shift 2
                ;;
            --include)
                if [[ -z "${2:-}" ]]; then
                    error "--include requires a pattern argument"
                    exit 1
                fi
                _PULL_INCLUDES+=("$2")
                shift 2
                ;;
            --)
                shift
                _PULL_EXTRA_ARGS+=("$@")
                break
                ;;
            -*)
                error "Unknown option: $1"
                error "Use -- to pass flags directly to rsync."
                exit 1
                ;;
            *)
                _PULL_POSITIONAL+=("$1")
                shift
                ;;
        esac
    done
}

_build_pull_rsync_args() {
    local rsh_cmd="$1"
    local dry_run_override="${2:-false}"
    local rsync_args=()

    rsync_args+=(-rlptD --human-readable --info=progress2)
    rsync_args+=(-e "$rsh_cmd")

    if [[ "$_PULL_DRY_RUN" == true ]] || [[ "$dry_run_override" == true ]]; then
        rsync_args+=(--dry-run)
    fi

    if [[ "$_PULL_DELETE" == true ]]; then
        rsync_args+=(--delete)
    fi

    if [[ "$_PULL_VERBOSE" == true ]] || [[ "$dry_run_override" == true ]]; then
        rsync_args+=(--verbose)
    fi

    for pat in "${_PULL_INCLUDES[@]}"; do
        rsync_args+=(--include "$pat")
    done

    for pat in "${_PULL_DEFAULT_EXCLUDES[@]}"; do
        rsync_args+=(--exclude "$pat")
    done

    for pat in "${_PULL_EXCLUDES[@]}"; do
        rsync_args+=(--exclude "$pat")
    done

    if [[ ${#_PULL_EXTRA_ARGS[@]} -gt 0 ]]; then
        rsync_args+=("${_PULL_EXTRA_ARGS[@]}")
    fi

    _RSYNC_ARGS=("${rsync_args[@]}")
}

_read_vybn_tracking() {
    local tracking_file="${1:-.}/.vybn"
    if [[ -f "$tracking_file" ]]; then
        grep '^remote_path=' "$tracking_file" | head -1 | cut -d= -f2-
    fi
}

main() {
    _parse_pull_args "$@"
    _check_rsync

    require_provider
    require_vm_running

    local remote_path="${_PULL_POSITIONAL[0]:-}"
    local local_path="${_PULL_POSITIONAL[1]:-.}"

    # If no remote path specified, try .vybn tracking file
    if [[ -z "$remote_path" ]]; then
        remote_path="$(_read_vybn_tracking "$local_path")"
        if [[ -z "$remote_path" ]]; then
            error "No remote path specified and no .vybn tracking file found."
            error "Usage: vybn pull <remote-path> [local-path]"
            error "Or push first with 'vybn push' to create a .vybn tracking file."
            exit 1
        fi
        info "Using remote path from .vybn: ${remote_path}"
    fi

    # Ensure remote path ends with / for directory sync
    [[ "$remote_path" == */ ]] || remote_path="${remote_path}/"

    # Get rsh command and remote host from network backend
    local rsh_info
    rsh_info="$(net_rsync_rsh)"
    local rsh_cmd remote_host
    rsh_cmd="$(echo "$rsh_info" | head -1)"
    remote_host="$(echo "$rsh_info" | tail -1)"

    # Check rsync on remote
    if ! vybn_ssh "command -v rsync" &>/dev/null; then
        error "rsync is not installed on the VM."
        error "Install it with: vybn ssh 'sudo apt-get install -y rsync'"
        exit 1
    fi

    # Dry-run only mode
    if [[ "$_PULL_DRY_RUN" == true ]]; then
        _build_pull_rsync_args "$rsh_cmd" false
        info "Pulling (dry run): ${remote_host}:${remote_path} -> ${local_path}"
        info "(dry run — no changes will be made)"
        rsync "${_RSYNC_ARGS[@]}" "${remote_host}:${remote_path}" "$local_path"
        return
    fi

    # Safety: dry-run preview first unless --yes
    if [[ "$_PULL_YES" != true ]]; then
        info "Previewing pull: ${remote_host}:${remote_path} -> ${local_path}"
        _build_pull_rsync_args "$rsh_cmd" true
        rsync "${_RSYNC_ARGS[@]}" "${remote_host}:${remote_path}" "$local_path"
        echo
        read -rp "Proceed? [y/N] " confirm
        if [[ "$confirm" != [yY] ]]; then
            info "Cancelled."
            return
        fi
    fi

    # Actual pull
    _build_pull_rsync_args "$rsh_cmd" false
    info "Pulling: ${remote_host}:${remote_path} -> ${local_path}"
    rsync "${_RSYNC_ARGS[@]}" "${remote_host}:${remote_path}" "$local_path"

    success "Pull complete."
}

cmd_help() {
    cat <<'EOF'
vybn pull — Pull files from VM

Usage: vybn pull [OPTIONS] [remote-path] [local-path]

Pulls files from the VM to your local machine using rsync.

If remote-path is omitted, reads the .vybn tracking file in local-path
(created by `vybn push`) to determine the remote path.

Safety: By default, shows a dry-run preview and prompts before pulling.
Use -y/--yes to skip the confirmation.

Options:
  -y, --yes                Skip dry-run confirmation
  -n, --dry-run            Only show what would change (no prompt, no action)
  --delete                 Remove local files not present on VM
  --exclude <pattern>      Additional exclude pattern (repeatable)
  --include <pattern>      Override an exclude (repeatable)
  -v, --verbose            Verbose rsync output
  --                       Pass remaining flags directly to rsync

Examples:
  vybn pull                             # Pull using .vybn tracking file
  vybn pull -y                          # Pull without confirmation
  vybn pull /home/claude/myproject .    # Explicit remote and local paths
  vybn pull --dry-run                   # Preview only
EOF
}
