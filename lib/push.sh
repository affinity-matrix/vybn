#!/usr/bin/env bash
# vybn push — Push files to VM

_PUSH_DEFAULT_EXCLUDES=(
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

_parse_push_args() {
    _PUSH_DRY_RUN=false
    _PUSH_DELETE=false
    _PUSH_VERBOSE=false
    _PUSH_NO_REGISTER=false
    _PUSH_EXCLUDES=()
    _PUSH_INCLUDES=()
    _PUSH_EXTRA_ARGS=()
    _PUSH_POSITIONAL=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                _PUSH_DRY_RUN=true
                shift
                ;;
            --delete)
                _PUSH_DELETE=true
                shift
                ;;
            -v|--verbose)
                _PUSH_VERBOSE=true
                shift
                ;;
            --no-register)
                _PUSH_NO_REGISTER=true
                shift
                ;;
            --exclude)
                if [[ -z "${2:-}" ]]; then
                    error "--exclude requires a pattern argument"
                    exit 1
                fi
                _PUSH_EXCLUDES+=("$2")
                shift 2
                ;;
            --include)
                if [[ -z "${2:-}" ]]; then
                    error "--include requires a pattern argument"
                    exit 1
                fi
                _PUSH_INCLUDES+=("$2")
                shift 2
                ;;
            --)
                shift
                _PUSH_EXTRA_ARGS+=("$@")
                break
                ;;
            -*)
                error "Unknown option: $1"
                error "Use -- to pass flags directly to rsync."
                exit 1
                ;;
            *)
                _PUSH_POSITIONAL+=("$1")
                shift
                ;;
        esac
    done
}

_build_push_rsync_args() {
    local rsh_cmd="$1"
    local rsync_args=()

    rsync_args+=(-rlptD --human-readable --info=progress2)
    rsync_args+=(-e "$rsh_cmd")

    if [[ "$_PUSH_DRY_RUN" == true ]]; then
        rsync_args+=(--dry-run)
    fi

    if [[ "$_PUSH_DELETE" == true ]]; then
        rsync_args+=(--delete)
    fi

    if [[ "$_PUSH_VERBOSE" == true ]]; then
        rsync_args+=(--verbose)
    fi

    for pat in "${_PUSH_INCLUDES[@]}"; do
        rsync_args+=(--include "$pat")
    done

    for pat in "${_PUSH_DEFAULT_EXCLUDES[@]}"; do
        rsync_args+=(--exclude "$pat")
    done

    for pat in "${_PUSH_EXCLUDES[@]}"; do
        rsync_args+=(--exclude "$pat")
    done

    if [[ ${#_PUSH_EXTRA_ARGS[@]} -gt 0 ]]; then
        rsync_args+=("${_PUSH_EXTRA_ARGS[@]}")
    fi

    _RSYNC_ARGS=("${rsync_args[@]}")
}

_write_vybn_tracking() {
    local local_dir="$1"
    local remote_path="$2"
    local tracking_file="${local_dir}/.vybn"
    local vm_name="${VYBN_VM_NAME:-unknown}"
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    cat > "$tracking_file" << EOF
remote_path=${remote_path}
vm=${vm_name}
last_push=${timestamp}
EOF

    # Suggest adding .vybn to .gitignore
    local gitignore="${local_dir}/.gitignore"
    if [[ -f "$gitignore" ]] && ! grep -q '\.vybn' "$gitignore" 2>/dev/null; then
        info "Tip: add '.vybn' to your .gitignore"
    fi
}

_read_vybn_tracking() {
    local tracking_file="${1:-.}/.vybn"
    if [[ -f "$tracking_file" ]]; then
        grep '^remote_path=' "$tracking_file" | head -1 | cut -d= -f2-
    fi
}

main() {
    _parse_push_args "$@"
    _check_rsync

    require_provider
    require_vm_running

    local local_path="${_PUSH_POSITIONAL[0]:-.}"
    local remote_path="${_PUSH_POSITIONAL[1]:-}"
    local is_file=false

    # Detect single file vs directory
    if [[ -f "$local_path" ]]; then
        is_file=true
    elif [[ -d "$local_path" ]]; then
        is_file=false
    else
        error "Local path does not exist: ${local_path}"
        exit 1
    fi

    if [[ "$is_file" == true ]]; then
        # Single file push
        local filename
        filename="$(basename "$local_path")"
        if [[ -z "$remote_path" ]]; then
            remote_path="${VYBN_PROJECTS_DIR}/${filename}"
        fi
    else
        # Directory push — resolve to absolute
        local_path="$(cd "$local_path" 2>/dev/null && pwd)" || {
            error "Cannot access local path: ${_PUSH_POSITIONAL[0]:-.}"
            exit 1
        }

        local dirname
        dirname="$(basename "$local_path")"

        # Check .vybn tracking file for saved remote path
        if [[ -z "$remote_path" ]]; then
            remote_path="$(_read_vybn_tracking "$local_path")"
        fi

        # Default remote path
        if [[ -z "$remote_path" ]]; then
            remote_path="${VYBN_PROJECTS_DIR}/${dirname}"
        fi

        # Ensure trailing slash for directory sync
        [[ "$local_path" == */ ]] || local_path="${local_path}/"
    fi

    # Get rsh command and remote host from network backend
    local rsh_info
    rsh_info="$(net_rsync_rsh)"
    local rsh_cmd remote_host
    rsh_cmd="$(echo "$rsh_info" | head -1)"
    remote_host="$(echo "$rsh_info" | tail -1)"

    _build_push_rsync_args "$rsh_cmd"

    # Check rsync on remote
    if ! vybn_ssh "command -v rsync" &>/dev/null; then
        error "rsync is not installed on the VM."
        error "Install it with: vybn ssh 'sudo apt-get install -y rsync'"
        exit 1
    fi

    info "Pushing: ${local_path} -> ${remote_host}:${remote_path}"
    if [[ "$_PUSH_DRY_RUN" == true ]]; then
        info "(dry run — no changes will be made)"
    fi

    if [[ "$is_file" == true ]]; then
        # Ensure remote directory exists for single file
        local remote_dir
        remote_dir="$(dirname "$remote_path")"
        local safe_dir="${remote_dir//\'/\'\\\'\'}"
        vybn_ssh "mkdir -p '${safe_dir}'"
    fi

    rsync "${_RSYNC_ARGS[@]}" "$local_path" "${remote_host}:${remote_path}"

    if [[ "$_PUSH_DRY_RUN" != true ]]; then
        success "Push complete."

        # Directory-only post-push actions
        if [[ "$is_file" != true ]]; then
            # Write .vybn tracking file
            local source_dir="${local_path%/}"
            _write_vybn_tracking "$source_dir" "$remote_path"

            # Auto-register session in sessions.conf
            if [[ "$_PUSH_NO_REGISTER" != true ]]; then
                source "${VYBN_DIR}/lib/sessions_conf.sh"
                local session_name
                session_name="$(basename "$remote_path")"
                _remote_sessions_conf_write "$session_name" "$remote_path"
                info "Registered session '${session_name}' -> ${remote_path}"
            fi
        fi
    fi
}

cmd_help() {
    cat <<'EOF'
vybn push — Push files to VM

Usage: vybn push [OPTIONS] [local-path] [remote-path]

Pushes files from your local machine to the VM using rsync.

If local-path is omitted, pushes the current directory.
If remote-path is omitted, pushes to $VYBN_PROJECTS_DIR/<basename>.

For directories, creates a .vybn tracking file so subsequent pushes
from the same directory automatically target the same remote path.
Also auto-registers the directory as a session in the VM's registry,
so `vybn connect <name>` works immediately after pushing.

Options:
  -n, --dry-run            Preview changes without pushing
  --delete                 Remove extraneous files on the VM
  --exclude <pattern>      Additional exclude pattern (repeatable)
  --include <pattern>      Override an exclude (repeatable)
  -v, --verbose            Verbose rsync output
  --no-register            Skip auto-registration of session mapping
  --                       Pass remaining flags directly to rsync

Default excludes: .git, .vybn, node_modules, __pycache__, .venv, dist,
  build, .next, .cache, *.pyc, .DS_Store, and other common artifacts.

Examples:
  vybn push                             # Push cwd to VM
  vybn push ./myproject                 # Push directory to VM
  vybn push ./myfile.txt                # Push single file
  vybn push ./myproject /home/claude/custom  # Explicit remote path
  vybn push --dry-run                   # Preview what would be pushed
  vybn push --delete                    # Mirror local, removing extras
  vybn push -- --compress               # Pass --compress to rsync
EOF
}
