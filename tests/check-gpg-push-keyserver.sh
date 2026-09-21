#!/usr/bin/env bash
# tests/check-gpg-push-keyserver.sh — workbench-gpg
# Plain bash, numbered OK:/FAIL: checks, matching this repo's existing
# tests/check-*.sh convention (no framework). Unit-tests
# _gpg_resolve_keyserver_candidates in isolation.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

# gpg-management.sh calls workbench-core's _wb_declare_availability at
# source time. Stub it so this file sources standalone, the same
# isolation approach check-manifest-structure.sh uses for manifest
# discovery (no workbench-core checkout required to run this test).
_wb_declare_availability() { :; }
# shellcheck disable=SC1091
source "${REPO_ROOT}/shell/gpg-management.sh"

# ── Known aliases → a single hkps:// candidate, case-insensitively ──────────

for input in openpgp OpenPGP OPENPGP; do
    out="$(_gpg_resolve_keyserver_candidates "${input}")"
    rc=$?
    lines="$(printf '%s\n' "${out}" | wc -l)"
    if [[ ${rc} -eq 0 && "${lines}" -eq 1 && "${out}" == "hkps://keys.openpgp.org" ]]; then
        ok "'${input}' resolves to a single candidate: hkps://keys.openpgp.org"
    else
        fail "'${input}' did not resolve to a single hkps://keys.openpgp.org candidate (got '${out}')"
    fi
done

for input in ubuntu Ubuntu UBUNTU; do
    out="$(_gpg_resolve_keyserver_candidates "${input}")"
    rc=$?
    lines="$(printf '%s\n' "${out}" | wc -l)"
    if [[ ${rc} -eq 0 && "${lines}" -eq 1 && "${out}" == "hkps://keyserver.ubuntu.com" ]]; then
        ok "'${input}' resolves to a single candidate: hkps://keyserver.ubuntu.com"
    else
        fail "'${input}' did not resolve to a single hkps://keyserver.ubuntu.com candidate (got '${out}')"
    fi
done

# ── Explicit hkps:// / hkp:// URLs pass through as their own single ─────────
#    candidate — the caller's protocol choice is honoured, no fallback added

for url in "hkps://my.keyserver.example" "hkp://old-style.example:11371" "hkps://keys.openpgp.org"; do
    out="$(_gpg_resolve_keyserver_candidates "${url}")"
    rc=$?
    lines="$(printf '%s\n' "${out}" | wc -l)"
    if [[ ${rc} -eq 0 && "${lines}" -eq 1 && "${out}" == "${url}" ]]; then
        ok "explicit URL '${url}' passes through as its own single candidate"
    else
        fail "explicit URL '${url}' did not pass through unchanged (got '${out}')"
    fi
done

# ── A bare hostname yields two candidates, hkps first then hkp fallback ─────

for host in "my.keyserver.example" "sks-keyservers.net" "localhost"; do
    out="$(_gpg_resolve_keyserver_candidates "${host}")"
    rc=$?
    first="$(printf '%s\n' "${out}" | sed -n '1p')"
    second="$(printf '%s\n' "${out}" | sed -n '2p')"
    if [[ ${rc} -eq 0 && "${first}" == "hkps://${host}" && "${second}" == "hkp://${host}" ]]; then
        ok "bare host '${host}' yields [hkps://${host}, hkp://${host}] in that order"
    else
        fail "bare host '${host}' did not yield the expected hkps-then-hkp pair (got '${out}')"
    fi
done

# ── Invalid input is still rejected outright — empty, whitespace, or an ─────
#    explicit non-keyserver scheme are never reinterpreted as a bare host

for input in "" "ftp://keys.openpgp.org" "https://keys.openpgp.org" "not a host at all"; do
    if out="$(_gpg_resolve_keyserver_candidates "${input}" 2>/dev/null)"; then
        fail "'${input}' was accepted but should have been rejected (got '${out}')"
    else
        ok "'${input}' is correctly rejected"
    fi
done

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
[[ "${FAILED}" -eq 0 ]]
