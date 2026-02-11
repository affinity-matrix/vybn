# Toolchain module: Python (pyenv + latest Python 3)
# shellcheck disable=SC2154

setup_toolchain_python() {
    if [[ ! -d "${CLAUDE_HOME}/.pyenv" ]]; then
        log "Installing pyenv and Python 3..."

        # pyenv build dependencies
        apt-get install -y -qq \
            libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
            libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
            libffi-dev liblzma-dev

        sudo -u "$CLAUDE_USER" bash -c '
            curl -fsSL https://pyenv.run | bash
            export PYENV_ROOT="$HOME/.pyenv"
            export PATH="$PYENV_ROOT/bin:$PATH"
            eval "$(pyenv init -)"

            # Install latest stable Python 3
            LATEST_PY="$(pyenv install --list | grep -E "^\s+3\.[0-9]+\.[0-9]+$" | tail -1 | tr -d " ")"
            pyenv install "$LATEST_PY"
            pyenv global "$LATEST_PY"
        '
    else
        log "pyenv already installed."
    fi
}
