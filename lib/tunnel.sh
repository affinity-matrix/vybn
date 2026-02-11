#!/usr/bin/env bash
# vybn tunnel — TCP tunnel management (open, list, kill)

VYBN_TUNNEL_DIR="$HOME/.vybn/tunnels"

_read_pidfile() {
    local file="$1"
    PID="" REMOTE_PORT="" LOCAL_PORT="" STARTED=""
    while IFS='=' read -r key value; do
        case "$key" in
            PID|REMOTE_PORT|LOCAL_PORT|STARTED)
                [[ "$value" =~ ^[0-9]+$ ]] && printf -v "$key" '%s' "$value" ;;
        esac
    done < "$file"
}

main() {
    require_provider

    local subcmd="${1:-}"

    case "$subcmd" in
        list)
            _tunnel_list
            ;;
        kill)
            shift
            _tunnel_kill "$@"
            ;;
        "")
            error "Missing required argument: remote port or subcommand"
            echo
            cmd_help
            exit 1
            ;;
        *)
            require_vm_running
            _tunnel_open "$@"
            ;;
    esac
}

_tunnel_open() {
    local foreground=false
    local args=()

    for arg in "$@"; do
        case "$arg" in
            -f|--foreground)
                foreground=true
                ;;
            *)
                args+=("$arg")
                ;;
        esac
    done

    local remote_port="${args[0]:-}"
    local local_port="${args[1]:-$remote_port}"

    if [[ -z "$remote_port" ]]; then
        error "Missing required argument: remote port"
        echo
        cmd_help
        exit 1
    fi

    if ! [[ "$remote_port" =~ ^[0-9]+$ ]] || (( remote_port < 1 || remote_port > 65535 )); then
        error "Invalid remote port: $remote_port"
        exit 1
    fi

    if ! [[ "$local_port" =~ ^[0-9]+$ ]] || (( local_port < 1 || local_port > 65535 )); then
        error "Invalid local port: $local_port"
        exit 1
    fi

    if [[ "$foreground" == true ]]; then
        info "Tunneling localhost:${local_port} -> ${VYBN_VM_NAME}:${remote_port}"
        info "Open http://localhost:${local_port} in your browser"
        info "Press Ctrl-C to stop"
        echo
        net_tunnel "$remote_port" "$local_port"
        return
    fi

    # Background mode (default)
    local pidfile="${VYBN_TUNNEL_DIR}/${local_port}.pid"

    # Check for existing tunnel on this local port
    if [[ -f "$pidfile" ]]; then
        _read_pidfile "$pidfile"
        if kill -0 "$PID" 2>/dev/null; then
            error "Tunnel already open on local port ${local_port} (PID ${PID})"
            exit 1
        fi
        # Stale PID file — clean up
        rm -f "$pidfile"
    fi

    mkdir -p "$VYBN_TUNNEL_DIR"

    net_tunnel "$remote_port" "$local_port" &>/dev/null &
    local pid=$!

    # Verify the tunnel process started and the local port is listening
    local wait_attempts=0
    local max_wait=20  # 20 * 0.5s = 10s
    while (( wait_attempts < max_wait )); do
        if ! kill -0 "$pid" 2>/dev/null; then
            error "Tunnel process exited immediately — check your network connection"
            exit 1
        fi
        if command -v lsof &>/dev/null; then
            lsof -iTCP:"${local_port}" -sTCP:LISTEN -P -n &>/dev/null && break
        elif command -v ss &>/dev/null; then
            ss -tlnp 2>/dev/null | grep -q ":${local_port} " && break
        else
            (echo >/dev/tcp/localhost/"${local_port}") 2>/dev/null && break
        fi
        wait_attempts=$((wait_attempts + 1))
        sleep 0.5
    done

    if (( wait_attempts >= max_wait )); then
        kill "$pid" 2>/dev/null || true
        error "Tunnel process started but port ${local_port} not listening after 10s"
        exit 1
    fi

    # Write PID file (sourceable format)
    cat > "$pidfile" <<EOF
PID=$pid
REMOTE_PORT=$remote_port
LOCAL_PORT=$local_port
STARTED=$(date +%s)
EOF

    success "Tunnel open: localhost:${local_port} -> ${VYBN_VM_NAME}:${remote_port} (PID ${pid})"
}

_tunnel_list() {
    local found=false

    if [[ ! -d "$VYBN_TUNNEL_DIR" ]] || ! compgen -G "${VYBN_TUNNEL_DIR}/*.pid" >/dev/null 2>&1; then
        info "No active tunnels"
        return
    fi

    printf "%-12s %-14s %-8s %s\n" "LOCAL PORT" "REMOTE PORT" "PID" "UPTIME"
    printf "%-12s %-14s %-8s %s\n" "----------" "-----------" "---" "------"

    for pidfile in "${VYBN_TUNNEL_DIR}"/*.pid; do
        [[ -f "$pidfile" ]] || continue

        local PID="" REMOTE_PORT="" LOCAL_PORT="" STARTED=""
        _read_pidfile "$pidfile"

        if ! kill -0 "$PID" 2>/dev/null; then
            rm -f "$pidfile"
            continue
        fi

        found=true
        local uptime="?"
        if [[ -n "$STARTED" ]]; then
            local elapsed=$(( $(date +%s) - STARTED ))
            uptime="$(format_duration "$elapsed")"
        fi

        printf "%-12s %-14s %-8s %s\n" "$LOCAL_PORT" "$REMOTE_PORT" "$PID" "$uptime"
    done

    if [[ "$found" == false ]]; then
        # All PID files were stale and removed
        info "No active tunnels"
    fi
}

_tunnel_kill() {
    local target="${1:-}"

    if [[ -z "$target" ]]; then
        error "Missing argument: local port or 'all'"
        echo
        echo "Usage: vybn tunnel kill <local-port>"
        echo "       vybn tunnel kill all"
        exit 1
    fi

    if [[ "$target" == "all" ]]; then
        if [[ ! -d "$VYBN_TUNNEL_DIR" ]] || ! compgen -G "${VYBN_TUNNEL_DIR}/*.pid" >/dev/null 2>&1; then
            info "No active tunnels"
            return
        fi

        local killed=0
        for pidfile in "${VYBN_TUNNEL_DIR}"/*.pid; do
            [[ -f "$pidfile" ]] || continue
            local PID="" LOCAL_PORT=""
            _read_pidfile "$pidfile"
            if kill "$PID" 2>/dev/null; then
                (( killed++ ))
                success "Killed tunnel on port ${LOCAL_PORT} (PID ${PID})"
            fi
            rm -f "$pidfile"
        done

        if (( killed == 0 )); then
            info "No active tunnels"
        fi
        return
    fi

    # Kill a specific tunnel by local port
    if ! [[ "$target" =~ ^[0-9]+$ ]]; then
        error "Invalid port: $target"
        exit 1
    fi

    local pidfile="${VYBN_TUNNEL_DIR}/${target}.pid"

    if [[ ! -f "$pidfile" ]]; then
        error "No tunnel found on local port ${target}"
        exit 1
    fi

    local PID=""
    _read_pidfile "$pidfile"

    if kill "$PID" 2>/dev/null; then
        success "Killed tunnel on port ${target} (PID ${PID})"
    else
        warn "Process ${PID} already exited"
    fi

    rm -f "$pidfile"
}

cmd_help() {
    cat <<'EOF'
vybn tunnel — Forward TCP ports from the VM to localhost

Usage:
  vybn tunnel <remote-port> [local-port]       Open tunnel (background, tracked)
  vybn tunnel <remote-port> [local-port] -f    Open tunnel (foreground, blocking)
  vybn tunnel list                              Show active tunnels
  vybn tunnel kill <local-port>                 Stop a specific tunnel
  vybn tunnel kill all                          Stop all tunnels

If local-port is omitted, it defaults to the same as remote-port.
Background tunnels are tracked in ~/.vybn/tunnels/ and can be listed or killed.
Use -f/--foreground for a blocking tunnel that stops on Ctrl-C.

Examples:
  vybn tunnel 8080              # background: localhost:8080 -> VM:8080
  vybn tunnel 3000 9000         # background: localhost:9000 -> VM:3000
  vybn tunnel 8080 -f           # foreground: blocks until Ctrl-C
  vybn tunnel list              # show all active tunnels
  vybn tunnel kill 8080         # stop tunnel on port 8080
  vybn tunnel kill all          # stop all tunnels
EOF
}
