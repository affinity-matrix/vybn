#!/usr/bin/env bash
# vybn sync — Sync files between local machine and VM

_SYNC_DEFAULT_EXCLUDES=(
    .git
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

_parse_sync_args() {
    _SYNC_DRY_RUN=false
    _SYNC_DELETE=false
    _SYNC_VERBOSE=false
    _SYNC_EXCLUDES=()
    _SYNC_INCLUDES=()
    _SYNC_EXTRA_ARGS=()
    _SYNC_POSITIONAL=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                _SYNC_DRY_RUN=true
                shift
                ;;
            --delete)
                _SYNC_DELETE=true
                shift
                ;;
            -v|--verbose)
                _SYNC_VERBOSE=true
                shift
                ;;
            --exclude)
                if [[ -z "${2:-}" ]]; then
                    error "--exclude requires a pattern argument"
                    exit 1
                fi
                _SYNC_EXCLUDES+=("$2")
                shift 2
                ;;
            --include)
                if [[ -z "${2:-}" ]]; then
                    error "--include requires a pattern argument"
                    exit 1
                fi
                _SYNC_INCLUDES+=("$2")
                shift 2
                ;;
            --)
                shift
                _SYNC_EXTRA_ARGS+=("$@")
                break
                ;;
            -*)
                error "Unknown option: $1"
                error "Use -- to pass flags directly to rsync."
                exit 1
                ;;
            *)
                _SYNC_POSITIONAL+=("$1")
                shift
                ;;
        esac
    done
}

_build_rsync_args() {
    local rsh_cmd="$1"
    local rsync_args=()

    # Use -rlptD instead of -a to avoid owner/group errors as non-root
    rsync_args+=(-rlptD --human-readable --info=progress2)

    # Rsh command for SSH transport
    rsync_args+=(-e "$rsh_cmd")

    if [[ "$_SYNC_DRY_RUN" == true ]]; then
        rsync_args+=(--dry-run)
    fi

    if [[ "$_SYNC_DELETE" == true ]]; then
        rsync_args+=(--delete)
    fi

    if [[ "$_SYNC_VERBOSE" == true ]]; then
        rsync_args+=(--verbose)
    fi

    # Include patterns go before excludes (rsync processes rules in order)
    for pat in "${_SYNC_INCLUDES[@]}"; do
        rsync_args+=(--include "$pat")
    done

    # Default excludes
    for pat in "${_SYNC_DEFAULT_EXCLUDES[@]}"; do
        rsync_args+=(--exclude "$pat")
    done

    # User excludes
    for pat in "${_SYNC_EXCLUDES[@]}"; do
        rsync_args+=(--exclude "$pat")
    done

    # Extra args passed after --
    if [[ ${#_SYNC_EXTRA_ARGS[@]} -gt 0 ]]; then
        rsync_args+=("${_SYNC_EXTRA_ARGS[@]}")
    fi

    _RSYNC_ARGS=("${rsync_args[@]}")
}

_sync_up() {
    local local_path="${_SYNC_POSITIONAL[0]:-.}"
    local remote_path="${_SYNC_POSITIONAL[1]:-}"

    # Resolve local path to absolute
    local_path="$(cd "$local_path" 2>/dev/null && pwd)" || {
        error "Local path does not exist: ${_SYNC_POSITIONAL[0]:-.}"
        exit 1
    }

    # Default remote path: ~/basename of local dir
    # shellcheck disable=SC2088  # tilde is expanded by rsync on the remote side
    if [[ -z "$remote_path" ]]; then
        remote_path="~/${local_path##*/}"
    fi

    # Ensure local path ends with / for rsync directory sync
    [[ "$local_path" == */ ]] || local_path="${local_path}/"

    # Get rsh command and remote host from network backend
    local rsh_info
    rsh_info="$(net_rsync_rsh)"
    local rsh_cmd remote_host
    rsh_cmd="$(echo "$rsh_info" | head -1)"
    remote_host="$(echo "$rsh_info" | tail -1)"

    _build_rsync_args "$rsh_cmd"

    # Check rsync is available on the remote
    if ! vybn_ssh "command -v rsync" &>/dev/null; then
        error "rsync is not installed on the VM."
        error "Install it with: vybn ssh 'sudo apt-get install -y rsync'"
        exit 1
    fi

    info "Syncing: ${local_path} -> ${remote_host}:${remote_path}"
    if [[ "$_SYNC_DRY_RUN" == true ]]; then
        info "(dry run — no changes will be made)"
    fi

    rsync "${_RSYNC_ARGS[@]}" "$local_path" "${remote_host}:${remote_path}"

    if [[ "$_SYNC_DRY_RUN" != true ]]; then
        success "Sync complete."
    fi
}

_sync_down() {
    local remote_path="${_SYNC_POSITIONAL[0]:-}"
    local local_path="${_SYNC_POSITIONAL[1]:-.}"

    if [[ -z "$remote_path" ]]; then
        error "Remote path is required for 'sync down'."
        error "Usage: vybn sync down <remote-path> [local-path]"
        exit 1
    fi

    # Get rsh command and remote host from network backend
    local rsh_info
    rsh_info="$(net_rsync_rsh)"
    local rsh_cmd remote_host
    rsh_cmd="$(echo "$rsh_info" | head -1)"
    remote_host="$(echo "$rsh_info" | tail -1)"

    _build_rsync_args "$rsh_cmd"

    # Check rsync is available on the remote
    if ! vybn_ssh "command -v rsync" &>/dev/null; then
        error "rsync is not installed on the VM."
        error "Install it with: vybn ssh 'sudo apt-get install -y rsync'"
        exit 1
    fi

    # Ensure remote path ends with / for directory sync
    [[ "$remote_path" == */ ]] || remote_path="${remote_path}/"

    info "Syncing: ${remote_host}:${remote_path} -> ${local_path}"
    if [[ "$_SYNC_DRY_RUN" == true ]]; then
        info "(dry run — no changes will be made)"
    fi

    rsync "${_RSYNC_ARGS[@]}" "${remote_host}:${remote_path}" "$local_path"

    if [[ "$_SYNC_DRY_RUN" != true ]]; then
        success "Sync complete."
    fi
}

main() {
    local direction="${1:-}"
    shift || true

    case "$direction" in
        up|down)
            ;;
        "")
            error "Missing direction. Usage: vybn sync <up|down> [OPTIONS] [paths]"
            exit 1
            ;;
        *)
            error "Unknown direction: ${direction}. Use 'up' or 'down'."
            exit 1
            ;;
    esac

    _check_rsync
    _parse_sync_args "$@"

    require_provider
    require_vm_running

    case "$direction" in
        up)   _sync_up   ;;
        down) _sync_down ;;
    esac
}

cmd_help() {
    cat <<'EOF'
vybn sync — Sync files between local machine and VM

Usage:
  vybn sync up [OPTIONS] [local-path] [remote-path]    Push local -> VM
  vybn sync down [OPTIONS] [remote-path] [local-path]   Pull VM -> local

If local-path is omitted, uses the current directory.
If remote-path is omitted (for 'up'), uses ~/dirname on the VM.

Options:
  -n, --dry-run            Preview changes without syncing
  --delete                 Remove extraneous files on the receiver
  --exclude <pattern>      Additional exclude pattern (repeatable)
  --include <pattern>      Override an exclude (repeatable)
  -v, --verbose            Verbose rsync output
  --                       Pass remaining flags directly to rsync

Default excludes: .git, node_modules, __pycache__, .venv, dist, build,
  .next, .cache, *.pyc, .DS_Store, and other common build artifacts.

Examples:
  vybn sync up                          # Push cwd to ~/dirname on VM
  vybn sync up . ~/project              # Push cwd to ~/project on VM
  vybn sync up --dry-run                # Preview what would be synced
  vybn sync up --delete                 # Mirror local, removing extras
  vybn sync down ~/project .            # Pull project from VM to cwd
  vybn sync up -- --compress            # Pass --compress to rsync
EOF
}
