#!/usr/bin/env bash
# vybn init — Interactive configuration wizard

# --- Internal helpers ---

_init_cancelled=false

_init_cleanup() {
    if [[ "$_init_cancelled" == true ]]; then
        echo
        warn "Cancelled. No changes written."
    fi
}

# _prompt <var_name> <prompt_text> <default> [regex] [error_msg]
# Reads a value from the user with a default, validates against optional regex.
_prompt() {
    local var_name="$1" prompt_text="$2" default="$3"
    local regex="${4:-}" error_msg="${5:-Invalid input.}"
    local value

    while true; do
        if [[ -n "$default" ]]; then
            read -rp "${prompt_text} [${default}]: " value
        else
            read -rp "${prompt_text}: " value
        fi
        value="${value:-$default}"

        # Empty check (if no default and no regex, allow empty)
        if [[ -z "$value" ]] && [[ -z "$default" ]] && [[ -z "$regex" ]]; then
            break
        fi

        # If regex is set, validate
        if [[ -n "$regex" ]]; then
            if [[ "$value" =~ $regex ]]; then
                break
            else
                warn "$error_msg"
                continue
            fi
        else
            break
        fi
    done

    printf -v "$var_name" '%s' "$value"
}

# _prompt_required <var_name> <prompt_text> [regex] [error_msg]
# Like _prompt but requires non-empty input (no default).
_prompt_required() {
    local var_name="$1" prompt_text="$2"
    local regex="${3:-}" error_msg="${4:-Invalid input.}"
    local value

    while true; do
        read -rp "${prompt_text}: " value

        if [[ -z "$value" ]]; then
            warn "This field is required."
            continue
        fi

        if [[ -n "$regex" ]] && ! [[ "$value" =~ $regex ]]; then
            warn "$error_msg"
            continue
        fi

        break
    done

    printf -v "$var_name" '%s' "$value"
}

# _prompt_choice <var_name> <default_idx> <options_array_name>
# Displays a numbered menu and reads a choice.
_prompt_choice() {
    local var_name="$1" default_idx="$2" options_name="$3"
    local -n options_ref="$options_name"
    local choice

    while true; do
        read -rp "Choice [${default_idx}]: " choice
        choice="${choice:-$default_idx}"

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options_ref[@]} )); then
            printf -v "$var_name" '%s' "$choice"
            return
        fi

        warn "Please enter a number between 1 and ${#options_ref[@]}."
    done
}

# _mask_key <key> — show first 10 and last 4 chars, mask the middle
_mask_key() {
    local key="$1"
    local len=${#key}
    if (( len <= 14 )); then
        echo "$key"
    else
        echo "${key:0:10}...${key:$((len-4)):4}"
    fi
}

# _machine_type_cost <type> — return monthly VM cost estimate
_machine_type_cost() {
    case "$1" in
        e2-micro)           echo 6 ;;
        e2-small)           echo 12 ;;
        e2-medium)          echo 25 ;;
        e2-standard-2)      echo 49 ;;
        e2-standard-4)      echo 97 ;;
        e2-standard-8)      echo 194 ;;
        e2-standard-16)     echo 388 ;;
        e2-highmem-2)       echo 66 ;;
        e2-highmem-4)       echo 131 ;;
        e2-highmem-8)       echo 262 ;;
        e2-highmem-16)      echo 524 ;;
        e2-highcpu-2)       echo 36 ;;
        e2-highcpu-4)       echo 73 ;;
        e2-highcpu-8)       echo 146 ;;
        e2-highcpu-16)      echo 292 ;;
        n2-standard-2)      echo 57 ;;
        n2-standard-4)      echo 113 ;;
        n2-standard-8)      echo 226 ;;
        *)                  echo "" ;;
    esac
}

# _available_toolchains — list names of available toolchain modules
_available_toolchains() {
    local tc_dir="${VYBN_DIR}/vm-setup/toolchains"
    local names=()
    if [[ -d "$tc_dir" ]]; then
        for f in "${tc_dir}"/*.sh; do
            [[ -f "$f" ]] && names+=("$(basename "$f" .sh)")
        done
    fi
    echo "${names[*]}"
}

main() {
    local force=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force) force=true; shift ;;
            *) error "Unknown option: $1"; exit 1 ;;
        esac
    done

    # Terminal guard
    if ! [[ -t 0 ]]; then
        error "vybn init requires an interactive terminal."
        error "Set environment variables and create ~/.vybnrc manually instead."
        exit 1
    fi

    # Ctrl-C safety
    _init_cancelled=true
    trap '_init_cleanup' INT TERM

    local rcfile="$HOME/.vybnrc"

    # --- Existing config handling ---
    if [[ -f "$rcfile" ]]; then
        if [[ "$force" == true ]]; then
            local backup
            backup="${rcfile}.bak.$(date +%s)"
            cp "$rcfile" "$backup"
            info "Backed up existing config to ${backup}"
        else
            echo "An existing ~/.vybnrc was found."
            echo
            echo "  1) Back up and overwrite"
            echo "  2) Overwrite without backup"
            echo "  3) Cancel"
            echo
            local overwrite_choice
            while true; do
                read -rp "Choice [1]: " overwrite_choice
                overwrite_choice="${overwrite_choice:-1}"
                case "$overwrite_choice" in
                    1)
                        local backup
                        backup="${rcfile}.bak.$(date +%s)"
                        cp "$rcfile" "$backup"
                        info "Backed up existing config to ${backup}"
                        break
                        ;;
                    2)
                        break
                        ;;
                    3)
                        info "Cancelled."
                        _init_cancelled=false
                        return
                        ;;
                    *)
                        warn "Please enter 1, 2, or 3."
                        ;;
                esac
            done
        fi
    fi

    # Collect all values into local variables. Nothing is written until final confirmation.
    local cfg_provider cfg_network cfg_project cfg_zone cfg_vm_name cfg_machine_type cfg_disk_size
    local cfg_ts_authkey cfg_ts_hostname cfg_ts_tags
    local cfg_ssh_host cfg_ssh_user cfg_ssh_key cfg_ssh_port
    local cfg_toolchains cfg_apt_packages cfg_npm_packages cfg_setup_script

    # --- Section 1: Provider ---
    echo
    echo "=== Provider ==="
    echo "  1) gcp   — Create and manage a GCP VM"
    echo "  2) ssh   — Use an existing server (bring your own VM)"
    echo

    local provider_default=1
    if [[ "${VYBN_PROVIDER}" == "ssh" ]]; then
        provider_default=2
    fi

    local provider_choice
    while true; do
        read -rp "Choice [${provider_default}]: " provider_choice
        provider_choice="${provider_choice:-$provider_default}"
        case "$provider_choice" in
            1) cfg_provider="gcp"; break ;;
            2) cfg_provider="ssh"; break ;;
            *) warn "Please enter 1 or 2." ;;
        esac
    done

    # --- Section 2: Network Backend ---
    echo
    echo "=== Network Backend ==="
    if [[ "$cfg_provider" == "ssh" ]]; then
        info "SSH provider currently supports Tailscale only."
        cfg_network="tailscale"
    else
        _prompt cfg_network "Network backend (tailscale, iap)" "${VYBN_NETWORK}" \
            "^(tailscale|iap)$" "Must be 'tailscale' or 'iap'."
    fi

    # --- Provider-specific settings ---
    cfg_ssh_host=""
    cfg_ssh_user=""
    cfg_ssh_key=""
    cfg_ssh_port=""
    cfg_project=""
    cfg_zone=""
    cfg_vm_name=""
    cfg_machine_type=""
    cfg_disk_size=""

    if [[ "$cfg_provider" == "ssh" ]]; then
        # --- SSH Provider Settings ---
        echo
        echo "=== SSH Server ==="

        _prompt_required cfg_ssh_host "Server hostname or IP" \
            '^[a-zA-Z0-9._:-]+$' "Must be a valid hostname or IP address."

        local ssh_user_default="${VYBN_SSH_USER:-$(whoami)}"
        _prompt cfg_ssh_user "SSH user" "$ssh_user_default" \
            '^[a-zA-Z0-9._-]+$' "Must be a valid username."

        local ssh_key_default="${VYBN_SSH_KEY:-}"
        _prompt cfg_ssh_key "SSH private key path (blank for SSH agent)" "$ssh_key_default"
        if [[ -n "$cfg_ssh_key" ]]; then
            while [[ -n "$cfg_ssh_key" ]] && [[ ! -r "$cfg_ssh_key" ]]; do
                warn "File not found or not readable: '${cfg_ssh_key}'"
                _prompt cfg_ssh_key "SSH private key path (blank for SSH agent)" ""
            done
        fi

        local ssh_port_default="${VYBN_SSH_PORT:-22}"
        _prompt cfg_ssh_port "SSH port" "$ssh_port_default" \
            '^[0-9]+$' "Must be a number."

        # VM name for Tailscale hostname
        echo
        echo "=== VM Identity ==="
        local vm_name_default="${VYBN_VM_NAME}"
        _prompt cfg_vm_name "VM name (leave blank to auto-generate)" "$vm_name_default"

        # Use reasonable defaults for GCP-only fields (not shown to user)
        cfg_machine_type="${VYBN_MACHINE_TYPE}"
        cfg_disk_size="${VYBN_DISK_SIZE}"
    else
        # --- GCP Settings ---
        echo
        echo "=== GCP Settings ==="

        # Auto-detect project
        local detected_project="${VYBN_PROJECT}"
        if [[ -z "$detected_project" ]] && command -v gcloud &>/dev/null; then
            detected_project="$(gcloud config get-value project 2>/dev/null)" || detected_project=""
        fi
        _prompt cfg_project "GCP project" "$detected_project" \
            "^[a-z][a-z0-9:._-]+$" "Invalid project ID."

        if [[ -z "$cfg_project" ]]; then
            error "GCP project is required."
            _init_cancelled=false
            exit 1
        fi

        _prompt cfg_zone "GCP zone" "${VYBN_ZONE}" \
            '^[a-z]+-[a-z]+[0-9]+-[a-z]$' "Invalid zone format (expected like: us-west1-a)."

        # --- VM Configuration ---
        echo
        echo "=== VM Configuration ==="

        # VM name (optional — leave blank for auto-generate)
        local vm_name_default="${VYBN_VM_NAME}"
        _prompt cfg_vm_name "VM name (leave blank to auto-generate)" "$vm_name_default"

        # Validate VM name if provided
        if [[ -n "$cfg_vm_name" ]]; then
            while ! [[ "$cfg_vm_name" =~ ^[a-z][a-z0-9-]{0,61}[a-z0-9]$ ]] && \
                  ! [[ "$cfg_vm_name" =~ ^[a-z]$ ]]; do
                warn "Invalid VM name. Must be 1-63 chars: lowercase letters, digits, hyphens. Must start with a letter."
                _prompt cfg_vm_name "VM name (leave blank to auto-generate)" ""
                [[ -z "$cfg_vm_name" ]] && break
            done
        fi

        # Machine type menu
        local -a machine_types=(
            "e2-micro"
            "e2-small"
            "e2-medium"
            "e2-standard-2"
            "e2-standard-4"
            "e2-standard-8"
            "e2-highmem-2"
            "e2-highmem-4"
        )
        local -a machine_labels=(
            "e2-micro       2 shared vCPU,  1 GB   ~\$6/mo"
            "e2-small       2 shared vCPU,  2 GB   ~\$12/mo"
            "e2-medium      2 shared vCPU,  4 GB   ~\$25/mo"
            "e2-standard-2  2 vCPU,  8 GB          ~\$49/mo"
            "e2-standard-4  4 vCPU, 16 GB          ~\$97/mo"
            "e2-standard-8  8 vCPU, 32 GB          ~\$194/mo"
            "e2-highmem-2   2 vCPU, 16 GB          ~\$66/mo"
            "e2-highmem-4   4 vCPU, 32 GB          ~\$131/mo"
        )

        # Determine default selection based on current VYBN_MACHINE_TYPE
        local default_machine_idx=4
        local i
        for i in "${!machine_types[@]}"; do
            if [[ "${machine_types[$i]}" == "$VYBN_MACHINE_TYPE" ]]; then
                default_machine_idx=$((i + 1))
                break
            fi
        done

        echo
        echo "Select a machine type:"
        for i in "${!machine_labels[@]}"; do
            local marker=""
            if (( i + 1 == default_machine_idx )); then
                marker=" <- default"
            fi
            printf "  %d) %s%s\n" "$((i + 1))" "${machine_labels[$i]}" "$marker"
        done
        echo "  9) Other (enter a machine type name)"

        local machine_choice
        while true; do
            read -rp "Choice [${default_machine_idx}]: " machine_choice
            machine_choice="${machine_choice:-$default_machine_idx}"

            if [[ "$machine_choice" =~ ^[1-8]$ ]]; then
                cfg_machine_type="${machine_types[$((machine_choice - 1))]}"
                break
            elif [[ "$machine_choice" == "9" ]]; then
                _prompt cfg_machine_type "Machine type" "" \
                    '^[a-z][a-z0-9-]+$' "Must be lowercase letters, digits, hyphens."
                if [[ -z "$cfg_machine_type" ]]; then
                    warn "Machine type cannot be empty."
                    continue
                fi
                break
            else
                warn "Please enter a number between 1 and 9."
            fi
        done

        _prompt cfg_disk_size "Boot disk size in GB" "${VYBN_DISK_SIZE}"

        # Validate disk size
        while ! [[ "$cfg_disk_size" =~ ^[0-9]+$ ]] || \
              (( cfg_disk_size < 10 || cfg_disk_size > 65536 )); do
            warn "Disk size must be an integer between 10 and 65536."
            _prompt cfg_disk_size "Boot disk size in GB" "${VYBN_DISK_SIZE}"
        done
    fi

    # --- Network-Specific Settings ---
    cfg_ts_authkey=""
    cfg_ts_hostname=""
    cfg_ts_tags=""

    if [[ "$cfg_network" == "tailscale" ]]; then
        echo
        echo "=== Tailscale ==="

        # Auth key — required, loop until valid
        local ts_default="${VYBN_TAILSCALE_AUTHKEY}"
        while true; do
            if [[ -n "$ts_default" ]]; then
                local masked
                masked="$(_mask_key "$ts_default")"
                echo "Current auth key: ${masked}"
                read -rp "Auth key (Enter to keep current, or paste new): " cfg_ts_authkey
                cfg_ts_authkey="${cfg_ts_authkey:-$ts_default}"
            else
                echo "Generate at: https://login.tailscale.com/admin/settings/keys"
                read -rp "Auth key: " cfg_ts_authkey
            fi

            if [[ "$cfg_ts_authkey" == tskey-auth-* ]]; then
                break
            fi
            warn "Auth key must start with 'tskey-auth-'."
            ts_default=""
        done

        local ts_hostname_default="${VYBN_TAILSCALE_HOSTNAME}"
        _prompt cfg_ts_hostname "Tailscale hostname (leave blank for VM name)" "$ts_hostname_default"

        local ts_tags_default="${VYBN_TAILSCALE_TAGS}"
        _prompt cfg_ts_tags "Tailscale ACL tags (e.g. tag:vybn, leave blank for none)" "$ts_tags_default"
    else
        echo
        echo "=== IAP ==="
        echo "No additional configuration needed for IAP."
    fi

    # --- Section 5: Toolchains and Extras ---
    echo
    echo "=== Toolchains ==="

    local available_tc
    available_tc="$(_available_toolchains)"
    echo "Available: ${available_tc}"

    # Convert current comma-separated toolchains to space-separated for display
    local tc_default="${VYBN_TOOLCHAINS//,/ }"
    local tc_input
    _prompt tc_input "Toolchains to install (space-separated)" "$tc_default"

    # Validate each toolchain
    local tc_dir="${VYBN_DIR}/vm-setup/toolchains"
    if [[ -n "$tc_input" ]]; then
        local valid_tc=true
        local tc_word
        for tc_word in $tc_input; do
            if [[ ! -f "${tc_dir}/${tc_word}.sh" ]]; then
                warn "Unknown toolchain: '${tc_word}'. Available: ${available_tc}"
                valid_tc=false
            fi
        done
        while [[ "$valid_tc" == false ]]; do
            _prompt tc_input "Toolchains to install (space-separated)" "$tc_default"
            valid_tc=true
            for tc_word in $tc_input; do
                if [[ -n "$tc_word" ]] && [[ ! -f "${tc_dir}/${tc_word}.sh" ]]; then
                    warn "Unknown toolchain: '${tc_word}'. Available: ${available_tc}"
                    valid_tc=false
                fi
            done
        done
    fi

    # Convert space-separated to comma-separated for storage
    cfg_toolchains="${tc_input// /,}"

    # Validate the comma-separated format
    if [[ -n "$cfg_toolchains" ]] && ! [[ "$cfg_toolchains" =~ ^[a-z][a-z0-9,]*$ ]]; then
        warn "Toolchain names must be lowercase letters and digits."
        cfg_toolchains="${VYBN_TOOLCHAINS}"
    fi

    local apt_default="${VYBN_APT_PACKAGES}"
    _prompt cfg_apt_packages "Extra apt packages (space-separated, blank for none)" "$apt_default"

    # Validate apt packages
    if [[ -n "$cfg_apt_packages" ]] && ! [[ "$cfg_apt_packages" =~ ^[a-zA-Z0-9_.+:\ -]+$ ]]; then
        while ! [[ "$cfg_apt_packages" =~ ^[a-zA-Z0-9_.+:\ -]+$ ]] && [[ -n "$cfg_apt_packages" ]]; do
            warn "Invalid package names (only letters, digits, dots, underscores, plus, colons, hyphens, spaces)."
            _prompt cfg_apt_packages "Extra apt packages (space-separated, blank for none)" "$apt_default"
        done
    fi

    local npm_default="${VYBN_NPM_PACKAGES}"
    _prompt cfg_npm_packages "Extra npm packages (space-separated, blank for none)" "$npm_default"

    # Validate npm packages
    if [[ -n "$cfg_npm_packages" ]] && ! [[ "$cfg_npm_packages" =~ ^[a-zA-Z0-9_./@:\ -]+$ ]]; then
        while ! [[ "$cfg_npm_packages" =~ ^[a-zA-Z0-9_./@:\ -]+$ ]] && [[ -n "$cfg_npm_packages" ]]; do
            warn "Invalid package names (only letters, digits, dots, underscores, slashes, at-signs, colons, hyphens, spaces)."
            _prompt cfg_npm_packages "Extra npm packages (space-separated, blank for none)" "$npm_default"
        done
    fi

    local setup_default="${VYBN_SETUP_SCRIPT}"
    _prompt cfg_setup_script "Custom setup script path (blank for none)" "$setup_default"

    # Validate setup script if provided
    if [[ -n "$cfg_setup_script" ]]; then
        while [[ -n "$cfg_setup_script" ]] && [[ ! -r "$cfg_setup_script" ]]; do
            warn "File not found or not readable: '${cfg_setup_script}'"
            _prompt cfg_setup_script "Custom setup script path (blank for none)" ""
        done
    fi

    # --- Summary ---
    echo
    echo "=== Summary ==="

    echo "  Provider:     ${cfg_provider}"
    echo "  Network:      ${cfg_network}"

    if [[ "$cfg_provider" == "ssh" ]]; then
        echo "  Host:         ${cfg_ssh_host}"
        echo "  SSH user:     ${cfg_ssh_user}"
        if [[ -n "$cfg_ssh_key" ]]; then
            echo "  SSH key:      ${cfg_ssh_key}"
        fi
        if [[ "${cfg_ssh_port}" != "22" ]]; then
            echo "  SSH port:     ${cfg_ssh_port}"
        fi
    else
        echo "  GCP project:  ${cfg_project}"
        echo "  Zone:         ${cfg_zone}"
        echo "  Machine type: ${cfg_machine_type}"
        echo "  Disk:         ${cfg_disk_size} GB SSD"

        # Calculate cost estimate
        local vm_cost disk_cost total_cost cost_display
        vm_cost="$(_machine_type_cost "$cfg_machine_type")"
        disk_cost=$(awk -v size="$cfg_disk_size" 'BEGIN {printf "%.0f", size * 0.17}')

        if [[ -n "$vm_cost" ]]; then
            total_cost=$((vm_cost + disk_cost))
            cost_display="~\$${total_cost}/mo"
        else
            cost_display="~\$${disk_cost}/mo disk + unknown VM cost"
        fi
        echo "  Est. cost:    ${cost_display}"
    fi

    if [[ -n "$cfg_vm_name" ]]; then
        echo "  VM name:      ${cfg_vm_name}"
    else
        echo "  VM name:      (auto-generated)"
    fi
    if [[ "$cfg_network" == "tailscale" ]]; then
        local masked_key
        masked_key="$(_mask_key "$cfg_ts_authkey")"
        echo "  Tailscale:    ${masked_key}"
    fi
    if [[ -n "$cfg_toolchains" ]]; then
        echo "  Toolchains:   ${cfg_toolchains}"
    fi
    if [[ -n "$cfg_apt_packages" ]]; then
        echo "  Apt packages: ${cfg_apt_packages}"
    fi
    if [[ -n "$cfg_npm_packages" ]]; then
        echo "  Npm packages: ${cfg_npm_packages}"
    fi
    if [[ -n "$cfg_setup_script" ]]; then
        echo "  Setup script: ${cfg_setup_script}"
    fi
    echo

    local confirm
    read -rp "Write configuration to ~/.vybnrc? [Y/n]: " confirm
    if [[ "$confirm" == [nN] ]]; then
        info "Cancelled. No changes written."
        _init_cancelled=false
        return
    fi

    # --- Write config ---
    local tmpfile="${rcfile}.tmp.$$"

    cat > "$tmpfile" <<RCEOF
# vybn configuration — generated by 'vybn init'
# Edit directly or re-run 'vybn init' to update.

# --- Provider and network ---

VYBN_PROVIDER="${cfg_provider}"
VYBN_NETWORK="${cfg_network}"

RCEOF

    if [[ "$cfg_provider" == "ssh" ]]; then
        cat >> "$tmpfile" <<RCEOF
# --- SSH server ---

VYBN_SSH_HOST="${cfg_ssh_host}"
VYBN_SSH_USER="${cfg_ssh_user}"
RCEOF
        if [[ -n "$cfg_ssh_key" ]]; then
            echo "VYBN_SSH_KEY=\"${cfg_ssh_key}\"" >> "$tmpfile"
        else
            echo "# VYBN_SSH_KEY=\"\"" >> "$tmpfile"
        fi
        if [[ "${cfg_ssh_port}" != "22" ]]; then
            echo "VYBN_SSH_PORT=\"${cfg_ssh_port}\"" >> "$tmpfile"
        else
            echo "# VYBN_SSH_PORT=\"22\"" >> "$tmpfile"
        fi
    else
        cat >> "$tmpfile" <<RCEOF
# --- GCP settings ---

VYBN_PROJECT="${cfg_project}"
VYBN_ZONE="${cfg_zone}"
RCEOF
    fi

    cat >> "$tmpfile" <<RCEOF

# --- VM configuration ---

RCEOF

    if [[ -n "$cfg_vm_name" ]]; then
        echo "VYBN_VM_NAME=\"${cfg_vm_name}\"" >> "$tmpfile"
    else
        echo "# VYBN_VM_NAME=\"\"  # Leave unset for auto-generated name" >> "$tmpfile"
    fi

    if [[ "$cfg_provider" != "ssh" ]]; then
        cat >> "$tmpfile" <<RCEOF
VYBN_MACHINE_TYPE="${cfg_machine_type}"
VYBN_DISK_SIZE="${cfg_disk_size}"
RCEOF
    fi

    cat >> "$tmpfile" <<RCEOF

# --- Tailscale ---

RCEOF

    if [[ "$cfg_network" == "tailscale" ]]; then
        echo "VYBN_TAILSCALE_AUTHKEY=\"${cfg_ts_authkey}\"" >> "$tmpfile"
        if [[ -n "$cfg_ts_hostname" ]]; then
            echo "VYBN_TAILSCALE_HOSTNAME=\"${cfg_ts_hostname}\"" >> "$tmpfile"
        else
            echo "# VYBN_TAILSCALE_HOSTNAME=\"\"" >> "$tmpfile"
        fi
        if [[ -n "$cfg_ts_tags" ]]; then
            echo "VYBN_TAILSCALE_TAGS=\"${cfg_ts_tags}\"" >> "$tmpfile"
        else
            echo "# VYBN_TAILSCALE_TAGS=\"\"" >> "$tmpfile"
        fi
    else
        {
            echo "# VYBN_TAILSCALE_AUTHKEY=\"\""
            echo "# VYBN_TAILSCALE_HOSTNAME=\"\""
            echo "# VYBN_TAILSCALE_TAGS=\"\""
        } >> "$tmpfile"
    fi

    cat >> "$tmpfile" <<RCEOF

# --- Toolchains ---

RCEOF

    if [[ -n "$cfg_toolchains" ]]; then
        echo "VYBN_TOOLCHAINS=\"${cfg_toolchains}\"" >> "$tmpfile"
    else
        echo "# VYBN_TOOLCHAINS=\"node\"" >> "$tmpfile"
    fi

    if [[ -n "$cfg_apt_packages" ]]; then
        echo "VYBN_APT_PACKAGES=\"${cfg_apt_packages}\"" >> "$tmpfile"
    else
        echo "# VYBN_APT_PACKAGES=\"\"" >> "$tmpfile"
    fi

    if [[ -n "$cfg_npm_packages" ]]; then
        echo "VYBN_NPM_PACKAGES=\"${cfg_npm_packages}\"" >> "$tmpfile"
    else
        echo "# VYBN_NPM_PACKAGES=\"\"" >> "$tmpfile"
    fi

    if [[ -n "$cfg_setup_script" ]]; then
        echo "VYBN_SETUP_SCRIPT=\"${cfg_setup_script}\"" >> "$tmpfile"
    else
        echo "# VYBN_SETUP_SCRIPT=\"\"" >> "$tmpfile"
    fi

    mv "$tmpfile" "$rcfile"
    chmod 600 "$rcfile"

    _init_cancelled=false

    echo
    success "Configuration saved to ~/.vybnrc"
    echo
    info "Next steps:"
    info "  vybn check              Verify prerequisites"
    info "  vybn deploy             Create your VM"
    info "  vybn deploy --connect   Deploy and connect in one step"
}

cmd_help() {
    cat <<'EOF'
vybn init — Interactive configuration wizard

Usage: vybn init [OPTIONS]

Walks through every configuration option and writes a validated ~/.vybnrc.
Re-run to update — existing values are pre-filled as defaults.

Options:
  -f, --force   Back up and overwrite existing ~/.vybnrc without prompting

Sections:
  1. Provider (gcp or ssh)
  2. Network backend (tailscale or iap)
  3. Provider-specific settings (GCP project/zone or SSH host)
  4. VM configuration (name, machine type, disk size)
  5. Network-specific settings (Tailscale auth key, etc.)
  6. Toolchains and extra packages
EOF
}
