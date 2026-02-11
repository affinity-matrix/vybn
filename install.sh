#!/usr/bin/env bash
# Install (or uninstall) vybn CLI by symlinking to /usr/local/bin
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Uninstall mode ---
if [[ "${1:-}" == "--uninstall" ]]; then
    echo "Uninstalling vybn..."

    # Remove symlink
    if [[ -L /usr/local/bin/vybn ]]; then
        if [[ -w /usr/local/bin ]]; then
            rm /usr/local/bin/vybn
        else
            echo "Requires sudo to remove symlink from /usr/local/bin..."
            sudo rm /usr/local/bin/vybn
        fi
        echo "[ok] Removed /usr/local/bin/vybn symlink."
    else
        echo "[info] /usr/local/bin/vybn symlink not found (already removed?)."
    fi

    # Prompt to remove ~/.vybn/ (SSH keys, tunnel state)
    if [[ -d "$HOME/.vybn" ]]; then
        read -rp "Remove ~/.vybn/ (SSH keys, tunnel state)? [y/N] " confirm
        if [[ "$confirm" == [yY] ]]; then
            rm -rf "$HOME/.vybn"
            echo "[ok] Removed ~/.vybn/"
        else
            echo "[info] Kept ~/.vybn/"
        fi
    fi

    # Remove completion source lines from shell rc files
    for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ -f "$rcfile" ]] && grep -qF "vybn.bash" "$rcfile" 2>/dev/null; then
            grep -vF "vybn.bash" "$rcfile" > "${rcfile}.tmp.$$"
            mv "${rcfile}.tmp.$$" "$rcfile"
            echo "[ok] Removed vybn completion from $(basename "$rcfile")"
        fi
        if [[ -f "$rcfile" ]] && grep -qF "vybn.zsh" "$rcfile" 2>/dev/null; then
            grep -vF "vybn.zsh" "$rcfile" > "${rcfile}.tmp.$$"
            mv "${rcfile}.tmp.$$" "$rcfile"
            echo "[ok] Removed vybn completion from $(basename "$rcfile")"
        fi
    done

    # Remind about ~/.vybnrc
    if [[ -f "$HOME/.vybnrc" ]]; then
        echo "[info] ~/.vybnrc still exists. Remove it manually if no longer needed."
    fi

    echo "[ok] vybn uninstalled."
    exit 0
fi

# --- Install mode ---

# Make all scripts executable
chmod +x "${SCRIPT_DIR}/vybn"
chmod +x "${SCRIPT_DIR}/vm-setup/base.sh"
chmod +x "${SCRIPT_DIR}/vm-setup/"*.sh
chmod +x "${SCRIPT_DIR}/providers/"*.sh
chmod +x "${SCRIPT_DIR}/networks/"*.sh
chmod +x "${SCRIPT_DIR}/lib/"*.sh

# Verify gcloud is installed
if ! command -v gcloud &>/dev/null; then
    echo "[warn] gcloud CLI not found. Install it before using vybn:"
    echo "       https://cloud.google.com/sdk/docs/install"
fi

# Create symlink (may need sudo for /usr/local/bin)
if [[ -w /usr/local/bin ]]; then
    ln -sf "${SCRIPT_DIR}/vybn" /usr/local/bin/vybn
else
    echo "Requires sudo to symlink into /usr/local/bin..."
    sudo ln -sf "${SCRIPT_DIR}/vybn" /usr/local/bin/vybn
fi

echo "[ok] vybn installed. Run 'vybn help' to get started."

# Auto-install shell completions
_shell_name="$(basename "${SHELL:-/bin/bash}")"
case "$_shell_name" in
    bash)
        _comp_file="${SCRIPT_DIR}/completions/vybn.bash"
        _rc_file="$HOME/.bashrc"
        _source_line="source \"${_comp_file}\""
        ;;
    zsh)
        _comp_file="${SCRIPT_DIR}/completions/vybn.zsh"
        _rc_file="$HOME/.zshrc"
        _source_line="source \"${_comp_file}\""
        ;;
    *)
        _comp_file=""
        _rc_file=""
        _source_line=""
        ;;
esac

if [[ -n "$_comp_file" && -f "$_comp_file" && -n "$_rc_file" ]]; then
    if [[ -f "$_rc_file" ]] && grep -qF "vybn.${_shell_name}" "$_rc_file" 2>/dev/null; then
        echo "[info] Completions already configured in ${_rc_file}."
    else
        echo
        read -rp "Add tab completion to ${_rc_file}? [Y/n] " _confirm
        if [[ "${_confirm:-y}" == [yY] || -z "$_confirm" ]]; then
            echo "" >> "$_rc_file"
            echo "# vybn tab completion" >> "$_rc_file"
            echo "${_source_line}" >> "$_rc_file"
            echo "[ok] Completions added to ${_rc_file}. Restart your shell or: source ${_rc_file}"
        else
            echo "[info] Skipped. To add manually:"
            echo "  echo '${_source_line}' >> ${_rc_file}"
        fi
    fi
else
    echo
    echo "To enable tab completion:"
    echo "  Bash: source ${SCRIPT_DIR}/completions/vybn.bash"
    echo "        (add to ~/.bashrc to persist)"
    echo "  Zsh:  source ${SCRIPT_DIR}/completions/vybn.zsh"
    echo "        (add to ~/.zshrc to persist)"
fi
