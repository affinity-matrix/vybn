# Toolchain module: Docker CE (official apt repo)
# shellcheck disable=SC2154

setup_toolchain_docker() {
    if ! command -v docker &>/dev/null; then
        log "Installing Docker CE..."

        # Add Docker's official GPG key
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        # Add the repository
        # shellcheck disable=SC1091
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
            https://download.docker.com/linux/ubuntu \
            $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
            > /etc/apt/sources.list.d/docker.list

        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        # Add claude user to docker group
        usermod -aG docker "$CLAUDE_USER"
    else
        log "Docker already installed."
    fi
}
