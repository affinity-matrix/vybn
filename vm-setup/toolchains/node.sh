# Toolchain module: Node.js (nvm + LTS)
# shellcheck disable=SC2154

setup_toolchain_node() {
    if [[ ! -d "${CLAUDE_HOME}/.nvm" ]]; then
        log "Installing nvm and Node.js LTS..."
        curl -fsSL -o /tmp/nvm-install.sh "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh"
        echo "${NVM_SHA256}  /tmp/nvm-install.sh" | sha256sum -c - || { log "ERROR: nvm installer checksum mismatch"; exit 1; }
        sudo -u "$CLAUDE_USER" bash /tmp/nvm-install.sh
        rm -f /tmp/nvm-install.sh
        sudo -u "$CLAUDE_USER" bash -c '
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
            nvm install --lts
            nvm alias default lts/*
        '
    else
        log "nvm already installed."
    fi
}
