#!/usr/bin/env bash
# Shared configuration and helpers for vybn

set -euo pipefail

VYBN_VERSION="0.1.0"

# Defaults (overridable via env vars or ~/.vybnrc)
VYBN_VM_NAME="${VYBN_VM_NAME:-}"
VYBN_ZONE="${VYBN_ZONE:-us-west1-a}"
VYBN_MACHINE_TYPE="${VYBN_MACHINE_TYPE:-e2-standard-2}"
VYBN_DISK_SIZE="${VYBN_DISK_SIZE:-30}"
VYBN_USER="${VYBN_USER:-claude}"
VYBN_PROJECT="${VYBN_PROJECT:-}"
VYBN_TMUX_SESSION="${VYBN_TMUX_SESSION:-claude}"
VYBN_TERM="${VYBN_TERM:-xterm-256color}"
VYBN_SSHID="${VYBN_SSHID:-}"

# Output control
VYBN_QUIET="${VYBN_QUIET:-false}"
VYBN_VERBOSE="${VYBN_VERBOSE:-false}"

# Validate VYBN_MACHINE_TYPE (lowercase letters, digits, hyphens)
if ! [[ "$VYBN_MACHINE_TYPE" =~ ^[a-z][a-z0-9-]+$ ]]; then
    echo "[error] Invalid machine type: '${VYBN_MACHINE_TYPE}' (must be lowercase letters, digits, hyphens)" >&2
    exit 1
fi

# Validate VYBN_USER (standard Unix username)
if ! [[ "$VYBN_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || [[ ${#VYBN_USER} -gt 32 ]]; then
    echo "[error] Invalid user: '${VYBN_USER}' (must be a valid Unix username, max 32 chars)" >&2
    exit 1
fi

# Validate VYBN_TERM (safe terminal name — prevents injection via remote shell interpolation)
if ! [[ "$VYBN_TERM" =~ ^[a-zA-Z0-9._+-]+$ ]]; then
    echo "[error] Invalid TERM value: '${VYBN_TERM}' (only alphanumeric, dot, underscore, plus, hyphen)" >&2
    exit 1
fi

# Validate VYBN_SSHID (SSH.id username — used in URL, must be safe)
if [[ -n "$VYBN_SSHID" ]] && ! [[ "$VYBN_SSHID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "[error] Invalid VYBN_SSHID: '${VYBN_SSHID}' (must be alphanumeric, hyphens, underscores only)" >&2
    exit 1
fi

# Provider and network backends
VYBN_PROVIDER="${VYBN_PROVIDER:-gcp}"
VYBN_NETWORK="${VYBN_NETWORK:-tailscale}"

# Tailscale backend defaults
# Security: use ephemeral, single-use auth keys when possible to limit exposure
VYBN_TAILSCALE_AUTHKEY="${VYBN_TAILSCALE_AUTHKEY:-}"
VYBN_TAILSCALE_HOSTNAME="${VYBN_TAILSCALE_HOSTNAME:-}"
VYBN_TAILSCALE_TAGS="${VYBN_TAILSCALE_TAGS:-}"
VYBN_SSH_KEY_DIR="${VYBN_SSH_KEY_DIR:-$HOME/.vybn/ssh}"

# SSH provider defaults
VYBN_SSH_HOST="${VYBN_SSH_HOST:-}"
VYBN_SSH_USER="${VYBN_SSH_USER:-$(whoami)}"
VYBN_SSH_KEY="${VYBN_SSH_KEY:-}"
VYBN_SSH_PORT="${VYBN_SSH_PORT:-22}"

# VM defaults
VYBN_EXTERNAL_IP="${VYBN_EXTERNAL_IP:-false}"
VYBN_CLAUDE_CODE_VERSION="${VYBN_CLAUDE_CODE_VERSION:-2.1.38}"
VYBN_TOOLCHAINS="${VYBN_TOOLCHAINS:-node}"
VYBN_APT_PACKAGES="${VYBN_APT_PACKAGES:-}"
VYBN_NPM_PACKAGES="${VYBN_NPM_PACKAGES:-}"
VYBN_SETUP_SCRIPT="${VYBN_SETUP_SCRIPT:-}"

# Source user overrides (with ownership/permission checks)
if [[ -f "$HOME/.vybnrc" ]]; then
    # Verify the file is owned by the current user
    _vybn_file_owner=""
    if [[ "$(uname)" == "Darwin" ]]; then
        _vybn_file_owner="$(stat -f '%u' "$HOME/.vybnrc")" || { echo "[error] Cannot check ~/.vybnrc ownership" >&2; exit 1; }
    else
        _vybn_file_owner="$(stat -c '%u' "$HOME/.vybnrc")" || { echo "[error] Cannot check ~/.vybnrc ownership" >&2; exit 1; }
    fi
    if [[ "$_vybn_file_owner" != "$(id -u)" ]]; then
        echo "[error] ~/.vybnrc is not owned by you — refusing to source it" >&2
        exit 1
    fi
    # Verify the file is not world-writable
    if [[ "$(uname)" == "Darwin" ]]; then
        if stat -f '%Sp' "$HOME/.vybnrc" 2>/dev/null | grep -q '......w.'; then
            echo "[error] ~/.vybnrc is world-writable — refusing to source it (run: chmod o-w ~/.vybnrc)" >&2
            exit 1
        fi
    else
        if stat -c '%a' "$HOME/.vybnrc" 2>/dev/null | grep -q '[2367]$'; then
            echo "[error] ~/.vybnrc is world-writable — refusing to source it (run: chmod o-w ~/.vybnrc)" >&2
            exit 1
        fi
    fi
    source "$HOME/.vybnrc"
fi

# Validate VYBN_SSH_PORT
if [[ -n "$VYBN_SSH_PORT" ]] && ! [[ "$VYBN_SSH_PORT" =~ ^[0-9]+$ ]]; then
    echo "[error] Invalid VYBN_SSH_PORT: '${VYBN_SSH_PORT}'" >&2
    exit 1
fi

# Validate VYBN_TOOLCHAINS (comma-separated lowercase names)
if [[ -n "$VYBN_TOOLCHAINS" ]] && ! [[ "$VYBN_TOOLCHAINS" =~ ^[a-z][a-z0-9,]*$ ]]; then
    echo "[error] Invalid VYBN_TOOLCHAINS: '${VYBN_TOOLCHAINS}' (must be comma-separated lowercase names)" >&2
    exit 1
fi

# Validate VYBN_APT_PACKAGES (standard apt package name chars)
if [[ -n "$VYBN_APT_PACKAGES" ]] && ! [[ "$VYBN_APT_PACKAGES" =~ ^[a-zA-Z0-9_.+:\ -]+$ ]]; then
    echo "[error] Invalid VYBN_APT_PACKAGES: '${VYBN_APT_PACKAGES}' (only letters, digits, dots, underscores, plus, colons, hyphens, spaces)" >&2
    exit 1
fi

# Validate VYBN_NPM_PACKAGES (allows scoped packages like @types/node)
if [[ -n "$VYBN_NPM_PACKAGES" ]] && ! [[ "$VYBN_NPM_PACKAGES" =~ ^[a-zA-Z0-9_./@:\ -]+$ ]]; then
    echo "[error] Invalid VYBN_NPM_PACKAGES: '${VYBN_NPM_PACKAGES}' (only letters, digits, dots, underscores, slashes, at-signs, colons, hyphens, spaces)" >&2
    exit 1
fi

# Validate VYBN_SETUP_SCRIPT (must be a readable file if set)
if [[ -n "$VYBN_SETUP_SCRIPT" ]] && [[ ! -r "$VYBN_SETUP_SCRIPT" ]]; then
    echo "[error] VYBN_SETUP_SCRIPT '${VYBN_SETUP_SCRIPT}' is not a readable file" >&2
    exit 1
fi

# --- Output helpers ---

_color() { printf "\033[%sm" "$1"; }
_reset() { printf "\033[0m"; }

format_duration() {
    local secs=$1
    if (( secs < 60 )); then
        printf "%ds" "$secs"
    elif (( secs < 3600 )); then
        printf "%dm %ds" "$(( secs / 60 ))" "$(( secs % 60 ))"
    else
        printf "%dh %dm" "$(( secs / 3600 ))" "$(( (secs % 3600) / 60 ))"
    fi
}

info()    { [[ "$VYBN_QUIET" == "true" ]] && return 0; echo "$(_color 34)[info]$(_reset) $*"; }
warn()    { echo "$(_color 33)[warn]$(_reset) $*" >&2; }
error()   { echo "$(_color 31)[error]$(_reset) $*" >&2; }
success() { [[ "$VYBN_QUIET" == "true" ]] && return 0; echo "$(_color 32)[ok]$(_reset) $*"; }

# --- Petname generator (unique Tailscale hostnames) ---

_VYBN_ADJECTIVES=(
    bright cosmic daring gentle golden
    happy jolly keen lively mellow
    noble plucky quiet radiant serene
    swift tender upbeat vivid warm
)

_VYBN_ANIMALS=(
    badger bunny chinchilla dolphin falcon
    gecko heron iguana jackdaw koala
    lemur mantis newt otter panda
    quail robin starling toucan wombat
)

generate_petname() {
    local adj="${_VYBN_ADJECTIVES[$((RANDOM % ${#_VYBN_ADJECTIVES[@]}))]}"
    local noun="${_VYBN_ANIMALS[$((RANDOM % ${#_VYBN_ANIMALS[@]}))]}"
    echo "${adj}-${noun}"
}

# --- VM name resolution ---

_VYBN_NAME_AUTO=false
VYBN_VM_NAME_FILE="$HOME/.vybn/vm-name"

_resolve_vm_name() {
    # Already set (user config or prior call) — nothing to do
    if [[ -n "$VYBN_VM_NAME" ]]; then
        return
    fi

    # Read from persisted state file
    if [[ -f "$VYBN_VM_NAME_FILE" ]]; then
        VYBN_VM_NAME="$(cat "$VYBN_VM_NAME_FILE")"
        return
    fi

    # Auto-generate a petname
    VYBN_VM_NAME="$(generate_petname)"
    _VYBN_NAME_AUTO=true
}

_persist_vm_name() {
    mkdir -p "$(dirname "$VYBN_VM_NAME_FILE")"
    echo "$VYBN_VM_NAME" > "$VYBN_VM_NAME_FILE"
}

# --- Composable cleanup (LIFO) ---

_VYBN_CLEANUP_FUNCS=()

_vybn_add_cleanup() {
    _VYBN_CLEANUP_FUNCS+=("$1")
}

_vybn_run_cleanup() {
    local i
    for (( i=${#_VYBN_CLEANUP_FUNCS[@]}-1; i>=0; i-- )); do
        eval "${_VYBN_CLEANUP_FUNCS[$i]}" 2>/dev/null || true
    done
}

trap '_vybn_run_cleanup' EXIT

# --- Retry with exponential backoff ---

_retry() {
    local max=3 delay=2 attempt=1
    while (( attempt <= max )); do
        "$@" && return 0
        local rc=$?
        (( attempt == max )) && return $rc
        warn "Command failed (attempt ${attempt}/${max}). Retrying in ${delay}s..."
        sleep "$delay"
        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done
}

# --- Concurrency lock ---

_vybn_lock() {
    local lockdir="$HOME/.vybn"
    mkdir -p "$lockdir"
    local lockfile="${lockdir}/${VYBN_VM_NAME}.lock"

    if [[ "$(uname)" == "Linux" ]] && command -v flock &>/dev/null; then
        # Linux: use flock
        exec 9>"$lockfile"
        if ! flock -n 9; then
            error "Another vybn process is operating on '${VYBN_VM_NAME}'. Waiting..."
            flock 9
        fi
        _vybn_add_cleanup "rm -f '${lockfile}'"
    else
        # macOS / fallback: mkdir-based lock with PID staleness check
        local attempts=0
        while ! mkdir "${lockfile}.d" 2>/dev/null; do
            local lock_pid=""
            if [[ -f "${lockfile}.d/pid" ]]; then
                lock_pid="$(cat "${lockfile}.d/pid" 2>/dev/null || true)"
            fi
            # Check if the lock holder is still alive
            if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                rm -rf "${lockfile}.d"
                continue
            fi
            if (( attempts == 0 )); then
                error "Another vybn process is operating on '${VYBN_VM_NAME}'. Waiting..."
            fi
            attempts=$((attempts + 1))
            sleep 1
            if (( attempts > 300 )); then
                error "Lock timeout after 300s"
                exit 1
            fi
        done
        echo $$ > "${lockfile}.d/pid"
        _vybn_add_cleanup "rm -rf '${lockfile}.d'"
    fi
}

# --- Load provider and network backends ---

# Validate backend names to prevent path traversal (must be lowercase alpha only)
if ! [[ "$VYBN_PROVIDER" =~ ^[a-z]+$ ]]; then
    error "Invalid provider name: '${VYBN_PROVIDER}' (must be lowercase letters only)"
    exit 1
fi
if ! [[ "$VYBN_NETWORK" =~ ^[a-z]+$ ]]; then
    error "Invalid network name: '${VYBN_NETWORK}' (must be lowercase letters only)"
    exit 1
fi

if [[ ! -f "${VYBN_DIR}/providers/${VYBN_PROVIDER}.sh" ]]; then
    error "Unknown provider: '${VYBN_PROVIDER}'"
    exit 1
fi
if [[ ! -f "${VYBN_DIR}/networks/${VYBN_NETWORK}.sh" ]]; then
    error "Unknown network: '${VYBN_NETWORK}'"
    exit 1
fi

source "${VYBN_DIR}/providers/${VYBN_PROVIDER}.sh"
source "${VYBN_DIR}/networks/${VYBN_NETWORK}.sh"

# --- Lazy validation (deferred until cloud commands need it) ---

_ensure_project() {
    if [[ -z "$VYBN_PROJECT" ]]; then
        VYBN_PROJECT="$(provider_detect_project)"
    fi
    if [[ -z "$VYBN_PROJECT" ]]; then
        error "No GCP project set. Run: gcloud config set project <PROJECT_ID>"
        error "Or set VYBN_PROJECT in ~/.vybnrc"
        exit 1
    fi
}

_validate_gcp_params() {
    # Reject empty VM name (must be resolved before reaching here)
    if [[ -z "$VYBN_VM_NAME" ]]; then
        error "VM name is empty. Set VYBN_VM_NAME in ~/.vybnrc or let it auto-generate."
        exit 1
    fi

    # Validate VM name (GCP naming: lowercase, digits, hyphens, 1-63 chars)
    if ! [[ "$VYBN_VM_NAME" =~ ^[a-z][a-z0-9-]{0,61}[a-z0-9]$ ]] && \
       ! [[ "$VYBN_VM_NAME" =~ ^[a-z]$ ]]; then
        error "Invalid VM name: '${VYBN_VM_NAME}'"
        error "Must be 1-63 characters: lowercase letters, digits, hyphens. Must start with a letter."
        exit 1
    fi

    # Validate zone format
    if ! [[ "$VYBN_ZONE" =~ ^[a-z]+-[a-z]+[0-9]+-[a-z]$ ]]; then
        error "Invalid zone: '${VYBN_ZONE}' (expected format like: us-west1-a)"
        exit 1
    fi

    # Validate disk size range (10-65536 GB, GCP limits)
    if ! [[ "$VYBN_DISK_SIZE" =~ ^[0-9]+$ ]] || (( VYBN_DISK_SIZE < 10 || VYBN_DISK_SIZE > 65536 )); then
        error "Invalid disk size: '${VYBN_DISK_SIZE}' (must be 10-65536 GB)"
        exit 1
    fi
}

# --- Provider-agnostic validation helpers ---

require_provider() {
    _resolve_vm_name
    if [[ "$VYBN_PROVIDER" == "gcp" ]]; then
        _ensure_project
        _validate_gcp_params
    fi
    provider_require_cli
}

require_vm_exists() {
    if ! provider_vm_exists; then
        error "VM '$VYBN_VM_NAME' not found in zone '$VYBN_ZONE'."
        error "Run 'vybn deploy' first."
        exit 1
    fi
}

require_vm_running() {
    require_vm_exists
    local status
    status="$(provider_vm_status)"
    if [[ "$status" != "RUNNING" ]]; then
        case "$status" in
            TERMINATED|STOPPED)
                error "VM '$VYBN_VM_NAME' is stopped. Start it with: vybn start"
                ;;
            STAGING|PROVISIONING|SUSPENDING|STOPPING)
                error "VM '$VYBN_VM_NAME' is ${status,,}. Wait a moment and try again."
                ;;
            SUSPENDED)
                error "VM '$VYBN_VM_NAME' is suspended. Resume it with: vybn start"
                ;;
            *)
                error "VM '$VYBN_VM_NAME' is ${status}. Check: vybn status"
                ;;
        esac
        exit 1
    fi
}
