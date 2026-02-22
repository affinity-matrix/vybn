#!/usr/bin/env bash
# sessions_conf.sh — Remote session registry helpers (not a command module)
# Manages ~/.vybn/sessions.conf on the VM (name=path mappings).

# Read all name=path entries from VM's sessions.conf.
# Output: lines of "name=path" (empty if file missing).
_remote_sessions_conf_read() {
    vybn_ssh "cat /home/${VYBN_USER}/.vybn/sessions.conf 2>/dev/null || true"
}

# Upsert a name=path mapping in VM's sessions.conf.
_remote_sessions_conf_write() {
    local name="$1"
    local path="$2"
    local safe_name="${name//\'/\'\\\'\'}"
    local safe_path="${path//\'/\'\\\'\'}"
    vybn_ssh "\
        mkdir -p /home/${VYBN_USER}/.vybn && \
        conf=/home/${VYBN_USER}/.vybn/sessions.conf && \
        touch \"\$conf\" && \
        if grep -q '^${safe_name}=' \"\$conf\" 2>/dev/null; then \
            sed -i 's|^${safe_name}=.*|${safe_name}=${safe_path}|' \"\$conf\"; \
        else \
            echo '${safe_name}=${safe_path}' >> \"\$conf\"; \
        fi"
}

# Lookup path by session name. Returns path or empty string.
_remote_session_path() {
    local name="$1"
    local conf
    conf="$(_remote_sessions_conf_read)"
    if [[ -n "$conf" ]]; then
        echo "$conf" | grep "^${name}=" | head -1 | cut -d= -f2-
    fi
}

# List tmux sessions with format: name|windows|attached/detached
_remote_tmux_list_sessions() {
    vybn_ssh "tmux list-sessions -F '#{session_name}|#{session_windows}|#{?session_attached,attached,detached}' 2>/dev/null || true"
}

# List tmux windows for a session with format: index|name|active_flag
_remote_tmux_list_windows() {
    local session="$1"
    local safe_session="${session//\'/\'\\\'\'}"
    vybn_ssh "tmux list-windows -t '${safe_session}' -F '#{window_index}|#{window_name}|#{window_active}' 2>/dev/null || true"
}
