#!/usr/bin/env bash
# tests/check-secret-handling.sh — workbench-gpg
# Plain bash, numbered OK:/FAIL: checks, no framework. Guards the security
# review M5/M6 fixes: no secret material in argv, no plaintext in shared /tmp.
# Static greps plus cheap functional checks of the new helpers.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="${REPO_ROOT}/shell/gpg-management.sh"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

# shellcheck disable=SC2329  # stubs are called by the sourced file
_wb_declare_availability() { :; }
# shellcheck disable=SC2329
_wb_alias_availability() { :; }
# shellcheck disable=SC2329
log_info()  { :; }
# shellcheck disable=SC2329
log_warn()  { :; }
# shellcheck disable=SC2329
log_error() { :; }
# shellcheck disable=SC1090,SC1091
source "${SRC}"

# ── Static: forbidden patterns must be gone ─────────────────────────────────

if grep -nE 'bw (create|edit) item .*"\$\{encoded\}"' "${SRC}" >/dev/null; then
    fail "bw create/edit item still passes \${encoded} in argv"
else
    ok "no 'bw create|edit item \"\${encoded}\"' argv pattern remains"
fi

if grep -nE 'notesPlain\[text\]=\$\{' "${SRC}" >/dev/null; then
    fail "op still passes notesPlain[text]=\${...} in argv"
else
    ok "no 'notesPlain[text]=\${' argv pattern remains"
fi

if grep -nE 'password=\$\{password\}' "${SRC}" >/dev/null; then
    fail "op still passes password=\${password} in argv"
else
    ok "no 'password=\${password}' argv pattern remains"
fi

if grep -nE 'python3 - "\$\{item_name\}" "\$\{username\}" "\$\{password\}"' "${SRC}" >/dev/null; then
    fail "python3 still receives the passphrase as an argument"
else
    ok "passphrase is not passed to python3 as an argument"
fi

if grep -nE 'mktemp -d /tmp/gpg-(bw|op)-|/tmp/gpg-import-' "${SRC}" >/dev/null; then
    fail "predictable /tmp secret paths remain"
else
    ok "no 'mktemp -d /tmp/gpg-{bw,op}-' or '/tmp/gpg-import-' remains"
fi

# ── Functional: _gpg_bw_login_json reads the password from stdin ────────────

json="$(printf 'p@ss' | _gpg_bw_login_json "item name" "someuser")"
pw="$(printf '%s' "${json}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["login"]["password"], end="")')"
if [[ "${pw}" == "p@ss" ]]; then
    ok "_gpg_bw_login_json puts the stdin password in login.password"
else
    fail "_gpg_bw_login_json login.password was '${pw}', expected 'p@ss'"
fi

# ── Functional: _gpg_bw_note_json reads the body from a file ────────────────

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
printf -- '-----BEGIN PGP-----\nline\n' > "${work}/body.asc"
json="$(_gpg_bw_note_json "note" "${work}/body.asc")"
notes="$(printf '%s' "${json}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["notes"], end="")')"
if [[ "${notes}" == "$(cat "${work}/body.asc")" ]]; then
    ok "_gpg_bw_note_json reads the note body from the file"
else
    fail "_gpg_bw_note_json notes did not match the body file"
fi

# ── Functional: _gpg_op_fill_template with a stub op ────────────────────────

mkdir -p "${work}/bin"
cat > "${work}/bin/op" <<'STUB'
#!/usr/bin/env bash
if [[ "$1 $2 $3" == "item template get" ]]; then
    if [[ "$4" == "Login" ]]; then
        echo '{"title":"","category":"LOGIN","fields":[{"id":"username","value":""},{"id":"password","value":""}]}'
    else
        echo '{"title":"","category":"SECURE_NOTE","fields":[{"id":"notesPlain","value":""}]}'
    fi
fi
STUB
chmod +x "${work}/bin/op"
saved_path="${PATH}"
PATH="${work}/bin:${PATH}"

printf '%s\0%s' "user1" "s3cret" | _gpg_op_fill_template "Login" "${work}/login.json" "T" username password
got="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["title"], {f["id"]: f["value"] for f in d["fields"]}["username"], {f["id"]: f["value"] for f in d["fields"]}["password"])' "${work}/login.json")"
if [[ "${got}" == "T user1 s3cret" ]]; then
    ok "_gpg_op_fill_template fills Login title/username/password from stdin"
else
    fail "_gpg_op_fill_template Login output was '${got}'"
fi

printf 'multi\nline body' | _gpg_op_fill_template "Secure Note" "${work}/note.json" "N" notesPlain
got="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["fields"][0]["value"], end="")' "${work}/note.json")"
if [[ "${got}" == $'multi\nline body' ]]; then
    ok "_gpg_op_fill_template fills notesPlain from stdin"
else
    fail "_gpg_op_fill_template note output was '${got}'"
fi
PATH="${saved_path}"

# ── Functional: _gpg_secret_tmpdir returns a mode-700 directory ─────────────

_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

for base_case in "xdg" "fallback"; do
    if [[ "${base_case}" == "xdg" ]]; then
        mkdir -p "${work}/xdg"
        d="$(XDG_RUNTIME_DIR="${work}/xdg" _gpg_secret_tmpdir)"
    else
        mkdir -p "${work}/tmpbase"
        d="$(XDG_RUNTIME_DIR="" TMPDIR="${work}/tmpbase" _gpg_secret_tmpdir)"
    fi
    if [[ -d "${d}" && "$(_mode "${d}")" == "700" ]]; then
        ok "_gpg_secret_tmpdir (${base_case}) returned a 0700 directory"
    else
        fail "_gpg_secret_tmpdir (${base_case}) returned '${d}' mode '$(_mode "${d}" 2>/dev/null)'"
    fi
done

if [[ "${FAILED}" -eq 0 ]]; then
    echo "All ${check_no} checks passed."
    exit 0
fi
echo "${FAILED} of ${check_no} checks FAILED."
exit 1
