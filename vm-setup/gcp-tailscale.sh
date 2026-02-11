# VM setup variant: GCP + Tailscale
# Appended after base.sh at deploy time — no shebang needed.
# Installs Tailscale for mesh networking + vybn SSH key.

# GCP guest attributes implementation (overrides base.sh no-op)
_publish_guest_attr() {
    local key="$1" value="$2"
    curl -sf -X PUT --data "$value" \
        "http://metadata.google.internal/computeMetadata/v1/instance/guest-attributes/vybn/${key}" \
        -H "Metadata-Flavor: Google" 2>/dev/null || true
}

_publish_guest_attr setup-status running

log "=== vybn VM setup starting (tailscale) ==="

setup_system_packages
setup_user

# --- Tailscale installation (via apt repo — avoids piping curl to sh) ---
log "Installing Tailscale..."
if ! command -v tailscale &>/dev/null; then
    mkdir -p /usr/share/keyrings
    chmod 0755 /usr/share/keyrings
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
        -o /usr/share/keyrings/tailscale-archive-keyring.gpg

    # Verify GPG key fingerprint
    EXPECTED_TS_FP="2596A99EAAB33821893C0A79458CA832957F5868"
    ACTUAL_TS_FP="$(gpg --with-colons --import-options show-only --import \
        /usr/share/keyrings/tailscale-archive-keyring.gpg 2>/dev/null \
        | awk -F: '/^pub/{found=1} found && /^fpr/{print $10; exit}')"
    if [[ "$ACTUAL_TS_FP" != "$EXPECTED_TS_FP" ]]; then
        log "ERROR: Tailscale GPG key fingerprint mismatch (expected $EXPECTED_TS_FP, got $ACTUAL_TS_FP)"
        exit 1
    fi
    log "Tailscale GPG key verified: $EXPECTED_TS_FP"

    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list \
        -o /etc/apt/sources.list.d/tailscale.list
    apt-get update -qq
    apt-get install -y -qq tailscale
else
    log "Tailscale already installed."
fi

# Read config from injected variables (set by deploy.sh header)
TS_AUTHKEY="${VYBN_TAILSCALE_AUTHKEY:-}"
if [[ -z "$TS_AUTHKEY" ]]; then
    log "ERROR: No VYBN_TAILSCALE_AUTHKEY found in startup config."
    log "Set VYBN_TAILSCALE_AUTHKEY in ~/.vybnrc and redeploy."
    exit 1
else
    # Build tailscale up args
    TS_ARGS=(--authkey="$TS_AUTHKEY" --ssh=false)

    # Always set hostname (petname from deploy, or fallback to system hostname)
    TS_HOSTNAME="${VYBN_TAILSCALE_HOSTNAME:-$(hostname -s)}"
    TS_ARGS+=(--hostname="$TS_HOSTNAME")

    # Optional: ACL tags
    TS_TAGS="${VYBN_TAILSCALE_TAGS:-}"
    if [[ -n "$TS_TAGS" ]]; then
        TS_ARGS+=(--advertise-tags="$TS_TAGS")
    fi

    log "Connecting to Tailscale..."
    tailscale up "${TS_ARGS[@]}"

    # Verify Tailscale actually connected (authkey may be expired/invalid)
    if ! tailscale status &>/dev/null; then
        log "ERROR: Tailscale failed to connect. Auth key may be expired or invalid."
        log "Generate a new key: https://login.tailscale.com/admin/settings/keys"
        exit 1
    fi
    log "Tailscale connected: $(tailscale ip -4 2>/dev/null || echo 'unknown IP')"
fi

# --- Install vybn SSH public key ---
log "Installing vybn SSH key..."
VYBN_SSH_PUBKEY="${VYBN_SSH_PUBKEY:-}"
if [[ -n "$VYBN_SSH_PUBKEY" ]]; then
    # Validate SSH public key format before writing to authorized_keys.
    # Without this, a compromised value containing newlines could inject
    # additional authorized_keys entries with OpenSSH options (e.g., command="...")
    # to establish a persistent backdoor.
    PUBKEY_LINE_COUNT="$(echo "$VYBN_SSH_PUBKEY" | wc -l)"
    if [[ "$PUBKEY_LINE_COUNT" -ne 1 ]]; then
        log "ERROR: SSH public key contains multiple lines — rejecting (possible injection)"
    elif ! [[ "$VYBN_SSH_PUBKEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)\ [A-Za-z0-9+/=]+( .+)?$ ]]; then
        log "ERROR: SSH public key has invalid format — rejecting"
    else
        # Install for claude user only (root SSH access is unnecessary;
        # the claude user has sudo if elevated access is needed)
        CLAUDE_SSH_DIR="${CLAUDE_HOME}/.ssh"
        mkdir -p "$CLAUDE_SSH_DIR"
        chmod 700 "$CLAUDE_SSH_DIR"

        CLAUDE_AUTH_KEYS="${CLAUDE_SSH_DIR}/authorized_keys"
        if ! grep -qF "$VYBN_SSH_PUBKEY" "$CLAUDE_AUTH_KEYS" 2>/dev/null; then
            echo "$VYBN_SSH_PUBKEY" >> "$CLAUDE_AUTH_KEYS"
        fi
        chmod 600 "$CLAUDE_AUTH_KEYS"
        chown -R "${CLAUDE_USER}:${CLAUDE_USER}" "$CLAUDE_SSH_DIR"

        log "SSH key installed for ${CLAUDE_USER}."
    fi
else
    log "WARNING: No VYBN_SSH_PUBKEY found in startup config."
    log "SSH key-based auth will not work."
fi

# --- Fetch SSH.id public keys (if configured) ---
VYBN_SSHID_USER="${VYBN_SSHID:-}"
if [[ -n "$VYBN_SSHID_USER" ]]; then
    # Defense-in-depth: validate username format again on the VM
    if ! [[ "$VYBN_SSHID_USER" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log "ERROR: Invalid SSH.id username — skipping"
    else
        log "Fetching SSH keys from sshid.io/${VYBN_SSHID_USER}..."
        SSHID_KEYS="$(curl -sf --max-time 10 "https://sshid.io/${VYBN_SSHID_USER}" || true)"
        if [[ -z "$SSHID_KEYS" ]]; then
            log "WARNING: Could not fetch keys from sshid.io — service may be unreachable."
            log "SSH access via vybn-generated key still works. Use 'vybn add-key --sshid ${VYBN_SSHID_USER}' post-deploy."
        else
            # Ensure .ssh directory exists (may not if vybn-ssh-pubkey block was skipped)
            CLAUDE_SSH_DIR="${CLAUDE_SSH_DIR:-${CLAUDE_HOME}/.ssh}"
            CLAUDE_AUTH_KEYS="${CLAUDE_AUTH_KEYS:-${CLAUDE_SSH_DIR}/authorized_keys}"
            mkdir -p "$CLAUDE_SSH_DIR"
            chmod 700 "$CLAUDE_SSH_DIR"

            SSHID_COUNT=0
            while IFS= read -r line; do
                # Strip trailing \r from HTTP responses with \r\n line endings
                line="${line%$'\r'}"
                # Skip blank lines and comments
                [[ -z "$line" || "$line" == \#* ]] && continue
                # Validate key format (standard + FIDO2 sk-* key types)
                if ! [[ "$line" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)\ [A-Za-z0-9+/=]+( .+)?$ ]]; then
                    log "WARNING: Skipping invalid key line from sshid.io: ${line:0:40}..."
                    continue
                fi
                # Append if not already present
                if ! grep -qF "$line" "$CLAUDE_AUTH_KEYS" 2>/dev/null; then
                    echo "$line" >> "$CLAUDE_AUTH_KEYS"
                    SSHID_COUNT=$((SSHID_COUNT + 1))
                fi
            done <<< "$SSHID_KEYS"

            chmod 600 "$CLAUDE_AUTH_KEYS"
            chown -R "${CLAUDE_USER}:${CLAUDE_USER}" "$CLAUDE_SSH_DIR"
            log "Installed ${SSHID_COUNT} key(s) from sshid.io/${VYBN_SSHID_USER}."
        fi
    fi
fi

setup_toolchains
setup_claude_code
setup_extra_packages
setup_tmux
setup_ssh_hardening

# Publish SSH host key to guest attributes for client-side pinning
log "Publishing SSH host key to guest attributes..."
HOST_KEY_PUB="$(cat /etc/ssh/ssh_host_ed25519_key.pub)"
curl -sf -X PUT --data "$HOST_KEY_PUB" \
    "http://metadata.google.internal/computeMetadata/v1/instance/guest-attributes/vybn/ssh-host-key-ed25519" \
    -H "Metadata-Flavor: Google" \
    && log "Host key published." \
    || log "WARNING: Failed to publish host key to guest attributes."

setup_bashrc
setup_complete
