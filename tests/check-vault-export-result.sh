#!/usr/bin/env bash
# tests/check-vault-export-result.sh — workbench-gpg
# Plain bash, numbered OK:/FAIL: checks, no framework. gpg-export-bitwarden
# and gpg-export-1password must report failure when an item wasn't stored,
# and suggest gpg-remove-master only when every item was. Runs both exports
# against stub gpg/bw/op/python3 commands on PATH; no network, no real
# keyring.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="${REPO_ROOT}/shell/gpg-management.sh"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

if ! command -v python3 &>/dev/null; then
    echo "SKIP: python3 not installed (the export functions build their JSON with it)"
    exit 0
fi

# shellcheck disable=SC2329  # stubs are called by the sourced file
_wb_declare_availability() { :; }
# shellcheck disable=SC2329
_wb_alias_availability() { :; }
# shellcheck disable=SC2329
log_info()  { echo "[INFO] $*"; }
# shellcheck disable=SC2329
log_warn()  { echo "[WARN] $*"; }
# shellcheck disable=SC2329
log_error() { echo "[ERROR] $*"; }
# The passphrase prompt answers with ${TEST_PASSPHRASE} (empty = skip).
# shellcheck disable=SC2329
_read_prompt_silent() { eval "$2=\"\${TEST_PASSPHRASE:-}\""; }
# shellcheck disable=SC2329
_read_prompt() { eval "$2=''"; }
# shellcheck disable=SC1090,SC1091
source "${SRC}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/bin" "${work}/nopy" "${work}/gnupg"
export GNUPGHOME="${work}/gnupg"
export STUB_LOG="${work}/argv.log"
export BW_STORE="${work}/bw-store"

# gpg: every export writes a fixed armoured block; --gen-revoke writes one
# to --output.
cat > "${work}/bin/gpg" <<'STUB'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) out="$2"; shift 2; continue ;;
        --list-keys) echo "uid:u::::::::Test User <test@example.com>:"; exit 0 ;;
        --list-secret-keys) exit 0 ;;
        --gen-revoke) printf -- '-----BEGIN PGP PUBLIC KEY BLOCK-----\nrev\n' > "${out}"; exit 0 ;;
        --export|--export-secret-keys|--export-secret-subkeys)
            printf -- '-----BEGIN PGP KEY BLOCK-----\nkey\n'; exit 0 ;;
    esac
    shift
done
STUB

# bw: encode is a pass-through; create stores the item JSON (one per line,
# with an id added) unless BW_FAIL_CREATE is set; list prints the stored items as an array.
cat > "${work}/bin/bw" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "bw $*" >> "${STUB_LOG}"
case "$1 ${2:-}" in
    "status ") echo '{"status":"unlocked"}' ;;
    "encode ") cat ;;
    "create item")
        [[ -n "${BW_FAIL_CREATE:-}" ]] && { cat >/dev/null; exit 1; }
        n="$(grep -c . "${BW_STORE}" 2>/dev/null)"
        { sed 's/^{/{"id":"stub-'"${n:-0}"'",/'; echo; } >> "${BW_STORE}" ;;
    "edit item") cat >/dev/null ;;
    "list items")
        printf '['
        [[ -f "${BW_STORE}" ]] && grep -v '^$' "${BW_STORE}" | paste -sd, -
        printf ']\n' ;;
esac
STUB

# op: template get serves minimal templates; item get reports no existing
# item; item create fails when OP_FAIL_CREATE is set.
cat > "${work}/bin/op" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "op $*" >> "${STUB_LOG}"
case "$1 ${2:-} ${3:-}" in
    "item template get")
        if [[ "$4" == "Login" ]]; then
            echo '{"title":"","category":"LOGIN","fields":[{"id":"username","value":""},{"id":"password","value":""}]}'
        else
            echo '{"title":"","category":"SECURE_NOTE","fields":[{"id":"notesPlain","value":""}]}'
        fi ;;
    "item get "*) exit 1 ;;
    "item create "*) [[ -n "${OP_FAIL_CREATE:-}" ]] && exit 1; exit 0 ;;
    "item edit "*) exit 0 ;;
    "whoami  ") exit 0 ;;
esac
exit 0
STUB

printf '#!/usr/bin/env bash\nexit 1\n' > "${work}/nopy/python3"
chmod +x "${work}/bin/gpg" "${work}/bin/bw" "${work}/bin/op" "${work}/nopy/python3"

export BW_SESSION="test-session"
export OP_SERVICE_ACCOUNT_TOKEN="test-token"
base_path="${work}/bin:${PATH}"
FP="0123456789ABCDEF0123456789ABCDEF01234567"
SECRET_PASS="correct-horse-battery"

# run_export <bitwarden|1password> <scenario: ok|vault-fails|no-python>
# Sets out/rc.
run_export() {
    local vault="$1" scenario="$2" path="${base_path}"
    rm -f "${BW_STORE}" "${STUB_LOG}"
    rm -rf "${GNUPGHOME}/revocations"
    unset BW_FAIL_CREATE OP_FAIL_CREATE
    case "${scenario}" in
        vault-fails) export BW_FAIL_CREATE=1 OP_FAIL_CREATE=1 ;;
        no-python)   path="${work}/nopy:${base_path}" ;;
    esac
    out="$(PATH="${path}" TEST_PASSPHRASE="${SECRET_PASS}" "gpg-export-${vault}" "${FP}" --name testhost 2>&1)"
    rc=$?
    unset BW_FAIL_CREATE OP_FAIL_CREATE
}

for vault in bitwarden 1password; do
    for scenario in vault-fails no-python; do
        run_export "${vault}" "${scenario}"
        if [[ ${rc} -ne 0 ]]; then
            ok "gpg-export-${vault} (${scenario}) returns non-zero"
        else
            fail "gpg-export-${vault} (${scenario}) returned 0"
        fi
        if [[ "${out}" == *INCOMPLETE* ]]; then
            ok "gpg-export-${vault} (${scenario}) reports the backup INCOMPLETE"
        else
            fail "gpg-export-${vault} (${scenario}) did not say INCOMPLETE"
        fi
        if [[ "${out}" != *"backup complete"* && "${out}" != *"gpg-remove-master ${FP}"* ]]; then
            ok "gpg-export-${vault} (${scenario}) neither claims completion nor suggests gpg-remove-master"
        else
            fail "gpg-export-${vault} (${scenario}) still claims completion or suggests gpg-remove-master"
        fi
    done

    run_export "${vault}" ok
    if [[ ${rc} -eq 0 ]]; then
        ok "gpg-export-${vault} (all stubs succeed) returns 0"
    else
        fail "gpg-export-${vault} (all stubs succeed) returned ${rc}: ${out}"
    fi
    if [[ "${out}" == *"backup complete for ${FP}"* && "${out}" == *"gpg-remove-master ${FP}"* ]]; then
        ok "gpg-export-${vault} (all stubs succeed) prints 'backup complete' and the gpg-remove-master hint"
    else
        fail "gpg-export-${vault} (all stubs succeed) output lacks 'backup complete' or the hint"
    fi
    if [[ "${out}" != *INCOMPLETE* ]]; then
        ok "gpg-export-${vault} (all stubs succeed) does not say INCOMPLETE"
    else
        fail "gpg-export-${vault} (all stubs succeed) said INCOMPLETE"
    fi
    if [[ -f "${STUB_LOG}" ]] && ! grep -qF "${SECRET_PASS}" "${STUB_LOG}"; then
        ok "gpg-export-${vault}: the passphrase never appeared in the vault CLI's argv"
    else
        fail "gpg-export-${vault}: passphrase found in argv (or no vault CLI call was logged)"
    fi
done

# The Bitwarden Login item was really stored with the passphrase (proves
# the passphrase path ran in the success case above, not just the notes).
run_export bitwarden ok
if [[ -f "${BW_STORE}" ]] && grep -qF "${SECRET_PASS}" "${BW_STORE}" \
        && grep -qF "GPG Key Passphrase" "${BW_STORE}"; then
    ok "Bitwarden success run stored the passphrase Login item"
else
    fail "Bitwarden success run did not store the passphrase Login item"
fi

if [[ "${FAILED}" -eq 0 ]]; then
    echo "All ${check_no} checks passed."
    exit 0
fi
echo "${FAILED} of ${check_no} checks FAILED."
exit 1
