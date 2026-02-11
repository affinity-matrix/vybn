# Toolchain module: Rust (rustup + stable toolchain)
# shellcheck disable=SC2154

setup_toolchain_rust() {
    if [[ ! -d "${CLAUDE_HOME}/.rustup" ]]; then
        log "Installing Rust stable toolchain..."
        sudo -u "$CLAUDE_USER" bash -c '
            curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
        '
    else
        log "Rust already installed."
    fi
}
