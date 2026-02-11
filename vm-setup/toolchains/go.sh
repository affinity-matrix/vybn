# Toolchain module: Go (official binary)
# shellcheck disable=SC2154

setup_toolchain_go() {
    if [[ ! -d /usr/local/go ]]; then
        log "Installing Go..."

        local arch
        case "$(uname -m)" in
            x86_64)  arch="amd64" ;;
            aarch64) arch="arm64" ;;
            *)       log "ERROR: Unsupported architecture for Go: $(uname -m)"; exit 1 ;;
        esac

        # Fetch the latest stable version
        local go_version
        go_version="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1)"

        curl -fsSL "https://go.dev/dl/${go_version}.linux-${arch}.tar.gz" -o /tmp/go.tar.gz
        tar -C /usr/local -xzf /tmp/go.tar.gz
        rm -f /tmp/go.tar.gz

        # Create GOPATH for claude user
        sudo -u "$CLAUDE_USER" mkdir -p "${CLAUDE_HOME}/go"
    else
        log "Go already installed."
    fi
}
