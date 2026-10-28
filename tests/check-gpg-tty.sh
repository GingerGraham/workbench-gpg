#!/usr/bin/env bash
# tests/check-gpg-tty.sh — workbench-gpg
# Plain bash, numbered OK:/FAIL: checks, no framework. Guards GPG_TTY handling:
# `tty` prints "not a tty" to stdout when stdin isn't a terminal, and that
# string must never be exported for gpg/pinentry to use as a device path.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GPG_SH="${REPO_ROOT}/shell/gpg.sh"
MGMT_SH="${REPO_ROOT}/shell/gpg-management.sh"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# Stubs for the Core API that the module files expect, plus a fake gpg so
# gpg.sh gets past its `command -v gpg` guard on any host.
printf '#!/bin/sh\nexit 0\n' > "${work}/gpg"
chmod +x "${work}/gpg"
cat > "${work}/stubs.sh" <<'STUBS'
_wb_declare_availability() { :; }
_wb_alias_availability() { :; }
log_info()  { :; }
log_warn()  { echo "WARN: $*"; }
log_error() { :; }
STUBS

# Source gpg.sh in a fresh bash with stdin from /dev/null (not a terminal,
# the way the workbench-core loader sources it), starting from the given
# GPG_TTY. Prints "GPG_TTY=<value>|exported=<yes/no>".
source_gpg_sh() {
    local start_tty="$1"
    PATH="${work}:${PATH}" START_TTY="${start_tty}" STUBS="${work}/stubs.sh" GPG_SH="${GPG_SH}" \
        bash -c '
            if [[ -n "${START_TTY}" ]]; then export GPG_TTY="${START_TTY}"; fi
            # shellcheck disable=SC1090
            source "${STUBS}"
            # shellcheck disable=SC1090
            source "${GPG_SH}"
            exported=no
            if [[ -n "$(env | grep "^GPG_TTY=")" ]]; then exported=yes; fi
            echo "GPG_TTY=${GPG_TTY:-<unset>}|exported=${exported}"
        ' < /dev/null
}

# ── Source-time block, stdin not a terminal ─────────────────────────────────

out="$(source_gpg_sh "")"
if [[ "${out}" == "GPG_TTY=<unset>|exported=no" ]]; then
    ok "non-terminal stdin, no prior value: GPG_TTY stays unset and unexported"
else
    fail "non-terminal stdin, no prior value: got '${out}'"
fi

out="$(source_gpg_sh "not a tty")"
if [[ "${out}" == "GPG_TTY=<unset>|exported=no" ]]; then
    ok "inherited 'not a tty' is cleared"
else
    fail "inherited 'not a tty' not cleared: got '${out}'"
fi

out="$(source_gpg_sh "/dev/pts/7")"
if [[ "${out}" == "GPG_TTY=/dev/pts/7|exported=yes" ]]; then
    ok "inherited valid GPG_TTY is left alone"
else
    fail "inherited valid GPG_TTY changed: got '${out}'"
fi

# ── Static: no unguarded tty calls left ─────────────────────────────────────

if grep -nE '\$\(tty( 2>/dev/null)?( \|\| [^)]*)?\)' "${GPG_SH}" "${MGMT_SH}" \
        | grep -v '^[0-9]*:[[:space:]]*#' | grep -vE 'GPG_TTY=|export GPG_TTY=' >/dev/null; then
    fail "a tty call exists outside a GPG_TTY assignment"
else
    ok "every tty call is a GPG_TTY assignment"
fi

# Each assignment of GPG_TTY="$(tty...)" must sit inside an `if [[ -t 0 ]]`
# block, i.e. the nearest preceding non-comment line opens that test.
unguarded=0
for f in "${GPG_SH}" "${MGMT_SH}"; do
    while IFS=: read -r lineno _; do
        prev="$(sed -n "1,$((lineno - 1))p" "${f}" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | tail -1)"
        case "${prev}" in
            *"[[ -t 0 ]]"*) ;;
            *) unguarded=$((unguarded + 1)); echo "      unguarded: ${f##*/}:${lineno}" ;;
        esac
    done < <(grep -nE '^[[:space:]]*GPG_TTY="\$\(tty' "${f}")
done
if [[ ${unguarded} -eq 0 ]]; then
    ok "every GPG_TTY=\$(tty) assignment is guarded by [[ -t 0 ]]"
else
    fail "${unguarded} GPG_TTY=\$(tty) assignment(s) lack a [[ -t 0 ]] guard"
fi

# ── Passphrase gate: not-a-terminal stdin leaves GPG_TTY alone ──────────────

# shellcheck disable=SC1090
source "${work}/stubs.sh"
# shellcheck disable=SC1090
source "${MGMT_SH}"
_read_prompt() { printf -v "$2" '%s' "y"; }
_str_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

unset GPG_TTY
_gpg_passphrase_ready_check enter < /dev/null >/dev/null
if [[ -z "${GPG_TTY:-}" ]]; then
    ok "passphrase gate leaves GPG_TTY unset when stdin is not a terminal"
else
    fail "passphrase gate set GPG_TTY to '${GPG_TTY}' with non-terminal stdin"
fi

# ── Cancel hint ─────────────────────────────────────────────────────────────

GPG_TTY="/dev/pts/9"
hint="$(_gpg_pinentry_cancel_hint "gpg: import from '[stdin]' failed: Operation cancelled")"
if [[ "${hint}" == *"/dev/pts/9"* && "${hint}" == *"updatestartuptty"* ]]; then
    ok "cancel hint shows the current GPG_TTY and the updatestartuptty command"
else
    fail "cancel hint missing GPG_TTY or updatestartuptty: '${hint}'"
fi

unset GPG_TTY
hint="$(_gpg_pinentry_cancel_hint "gpg: import from '[stdin]' failed: Operation cancelled")"
if [[ "${hint}" == *"<unset>"* ]]; then
    ok "cancel hint reports an unset GPG_TTY"
else
    fail "cancel hint doesn't report an unset GPG_TTY: '${hint}'"
fi

hint="$(_gpg_pinentry_cancel_hint "gpg: Total number processed: 1")"
if [[ -z "${hint}" ]]; then
    ok "no hint for output without 'Operation cancelled'"
else
    fail "hint printed for unrelated output: '${hint}'"
fi

# ── Terminal path (needs a pty; skipped where `script` is unavailable) ──────

if command -v script >/dev/null 2>&1; then
    pty_out="${work}/pty.out"
    cat > "${work}/pty.sh" <<PTY
PATH='${work}':\$PATH
source '${work}/stubs.sh'
source '${GPG_SH}'
echo "RESULT=[\${GPG_TTY:-}]"
PTY
    script -qec "bash '${work}/pty.sh'" /dev/null > "${pty_out}" 2>&1 < /dev/null || true
    if grep -qE 'RESULT=\[/dev/(pts/[0-9]+|tty[A-Za-z0-9]*)\]' "${pty_out}"; then
        ok "terminal stdin: GPG_TTY is set to the real device path"
    else
        fail "terminal stdin: GPG_TTY not set to a device path ($(tr -d '\r' < "${pty_out}" | tail -1))"
    fi
else
    echo "SKIP: no 'script' available; terminal-path check not run"
fi

echo "==============================="
if [[ ${FAILED} -eq 0 ]]; then
    echo "All ${check_no} checks passed."
else
    echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
    exit 1
fi
