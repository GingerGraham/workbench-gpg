#!/usr/bin/env bash
# tests/check-temp-files.sh — workbench-gpg
# Plain bash, numbered OK:/FAIL: checks, no framework. Guards: no predictable
# /tmp paths for secrets, EXIT/INT/TERM cleanup, revocation certs created
# 0600 from the start, and set -u-safe empty-array expansions (bash < 4.4).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="${REPO_ROOT}/shell/gpg-management.sh"
SRC2="${REPO_ROOT}/shell/gpg.sh"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

# shellcheck disable=SC2329  # stubs are called by the sourced file
_wb_declare_availability() { :; }
# shellcheck disable=SC2329
log_info()  { :; }
# shellcheck disable=SC2329
log_warn()  { :; }
# shellcheck disable=SC2329
log_error() { :; }
# shellcheck disable=SC1090,SC1091
source "${SRC}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

# ── Static ──────────────────────────────────────────────────────────────────

if grep -nE 'mktemp[[:space:]]+/tmp|"/tmp/' "${SRC}" | grep -v '^[0-9]*:[[:space:]]*#' >/dev/null; then
    fail "predictable /tmp path still used in gpg-management.sh"
else
    ok "no predictable /tmp temp paths in gpg-management.sh"
fi

if grep -nE '(rm -f|trap)' "${SRC}" | grep -E 'param_file|tmp_file' | grep -v _gpg_tmp_ >/dev/null; then
    fail "param_file/tmp_file cleaned up outside the _gpg_tmp_* helpers"
else
    ok "keygen/github/gitlab temp files go through the guard helpers"
fi

if grep -nE '^[[:space:]]*gpg --output "\$\{rev_file\}"' "${SRC}" >/dev/null; then
    fail "a --gen-revoke call runs without umask 077"
else
    ok "every --gen-revoke call runs under umask 077"
fi

bare="$(grep -nE '"\$\{(vault_arg|uids)\[@\]\}"' "${SRC}" "${SRC2}" | grep -v '+"' || true)"
if [[ -n "${bare}" ]]; then
    fail "bare empty-able array expansion (breaks set -u on bash < 4.4): ${bare}"
else
    ok "vault_arg/uids expansions use the \${arr[@]+...} idiom"
fi

# ── Functional ──────────────────────────────────────────────────────────────

f="$(TMPDIR="${work}" _gpg_tmp_new gpg-test)"
if [[ -f "${f}" && "$(_mode "${f}")" == "600" && "${f}" == "${work}"/gpg-test.* ]]; then
    ok "_gpg_tmp_new creates a unique 0600 file under \$TMPDIR"
else
    fail "_gpg_tmp_new returned '${f}' mode '$(_mode "${f}" 2>/dev/null)'"
fi
rm -f "${f}"

# Guard removes the file on EXIT and on TERM
for sig in EXIT TERM; do
    marker="${work}/guard-${sig}"
    : > "${marker}"
    if [[ "${sig}" == "EXIT" ]]; then
        ( _gpg_tmp_guard "${marker}"; exit 0 )
    else
        ( _gpg_tmp_guard "${marker}"; kill -TERM $BASHPID; sleep 1 ) 2>/dev/null
    fi
    if [[ ! -e "${marker}" ]]; then
        ok "guard removes the temp file on ${sig}"
    else
        fail "temp file survived ${sig}"
    fi
done

# Release removes the file and restores the caller's traps
marker="${work}/release"
: > "${marker}"
out="$(
    trap 'echo mine' EXIT
    _gpg_tmp_guard "${marker}"
    _gpg_tmp_release "${marker}"
    trap -p EXIT
)"
if [[ ! -e "${marker}" && "${out}" == *"echo mine"* ]]; then
    ok "_gpg_tmp_release removes the file and restores the caller's EXIT trap"
else
    fail "_gpg_tmp_release did not clean up/restore (out='${out}')"
fi

# gpg-revoke creates the certificate 0600 from the start
mkdir -p "${work}/bin" "${work}/gnupg"
cat > "${work}/bin/gpg" <<'STUB'
#!/usr/bin/env bash
# stub: record the creation mode of --output, no chmod afterwards
out=""
while [ $# -gt 0 ]; do
    if [ "$1" = "--output" ]; then out="$2"; shift; fi
    shift
done
if [ -n "${out}" ]; then
    echo "-----BEGIN PGP PUBLIC KEY BLOCK-----" > "${out}"
    (stat -c %a "${out}" 2>/dev/null || stat -f %Lp "${out}") > "${out}.mode"
fi
exit 0
STUB
chmod +x "${work}/bin/gpg"
saved_path="${PATH}"
# shellcheck disable=SC2329
_gpg_require_key() { return 0; }
PATH="${work}/bin:${PATH}"
( umask 022; GNUPGHOME="${work}/gnupg" gpg-revoke ABCDEF >/dev/null 2>&1 )
PATH="${saved_path}"
rf="${work}/gnupg/revocations/ABCDEF-revocation.asc"
if [[ -f "${rf}.mode" && "$(cat "${rf}.mode")" == "600" ]]; then
    ok "gpg-revoke: certificate is 0600 at creation (umask 022 caller)"
else
    fail "gpg-revoke: creation mode was '$(cat "${rf}.mode" 2>/dev/null)'"
fi

# Empty-array idiom works under set -u
if bash -c 'set -u; a=(); for x in ${a[@]+"${a[@]}"}; do :; done; echo ok' 2>/dev/null | grep -q ok; then
    ok "\${arr[@]+...} idiom is safe on an empty array under set -u"
else
    fail "empty-array idiom failed under set -u"
fi

if [[ "${FAILED}" -eq 0 ]]; then
    echo "All ${check_no} checks passed."
    exit 0
fi
echo "${FAILED} of ${check_no} checks FAILED."
exit 1
