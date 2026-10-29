# Changelog

All notable changes to `workbench-gpg` are documented here.

## [Unreleased]

### Changed

- **Bug report template asks for OS family and environment separately.**
  The single "Platform" dropdown is replaced by an "Operating system"
  dropdown (Fedora/RHEL, Debian/Ubuntu, Arch, SUSE, other Linux, macOS),
  an optional distribution and version field, and an "Environment"
  dropdown (directly on the OS, container, or WSL2), so a report says
  which distro it ran on and whether that was WSL2 or a container.

## [0.5.1] - 2026-10-28

### Fixed

- **`GPG_TTY` is no longer exported as the literal `not a tty`.** When
  the loader sourced `gpg.sh` with stdin not attached to a terminal,
  `tty` printed `not a tty` to stdout, gpg passed that to pinentry as a
  device path, and imports and signing failed with `Operation
  cancelled`. `gpg.sh` and `gpg-agent-restart` now set `GPG_TTY` only
  when stdin is a terminal, and `gpg.sh` clears an inherited
  `not a tty`. Fixes #34.
- **The passphrase prompt gate points pinentry at the current terminal.**
  Before any operation that may prompt, `GPG_TTY` is refreshed and
  `gpg-connect-agent updatestartuptty` runs, so an agent started from an
  earlier terminal prompts on the right one.
- **`gpg-import`, `gpg-import-bitwarden` and `gpg-import-1password`
  explain a cancelled passphrase prompt.** On `Operation cancelled` they
  show the current `GPG_TTY` and the `updatestartuptty` command.
- **`gpg-import` returns non-zero when the import fails.** It used to
  print "Imported. Current secret keys:" and list keys regardless of
  gpg's exit status. It now reports `Import failed` and returns gpg's
  status, like the Bitwarden and 1Password variants.

## [0.5.0] - 2026-10-27

### Added

- **`gpg-resolve-signing-key <key-id>`**, a public, stable form of the
  signing-subkey resolution workbench-git uses for `git-add-project` /
  `git-update-project`. Prints the `[S]` subkey to use for a master key
  or fingerprint. README "For other modules" documents it.

### Fixed

- **Function listings say what each name needs.** `gpg-push-github` and
  `gpg-push-gitlab` now need gpg as well as `gh`/`glab`; the Bitwarden
  and 1Password functions name `python3` and `gpg` as well as `bw`/`op`
  and point at `wb tools install bw-cli`/`op-cli`; `gpg-agent-restart`
  and `gpg-agent-forget` need `gpgconf`. The `gpg-ls`/`gpg-ls-secret`
  aliases are hidden without gpg.
- **Keyserver names match case-insensitively in zsh.** `gpg-push-keyserver`
  and its alias lookup used bash's `shopt nocasematch`, which zsh doesn't
  have: in zsh, `OpenPGP` became `hkps://OpenPGP` with `shopt: command
  not found` errors, and the keys.openpgp.org verification note didn't
  show. Matching now lowercases the input instead.
- **`gpg-rotate-subkey` lists only subkeys.** The fingerprint list it
  shows before asking which subkey to retire included the master key's
  own fingerprint.
- **`gpg-push-gitlab` returns non-zero when `glab gpg-key add` fails.**
- **`gpg-export-bitwarden`/`gpg-export-1password` work without
  `hostname`.** The default qualifier falls back to `uname -n`.
- **`installed-pinentry` finds pinentry on macOS and when
  `~/.local/bin` isn't on `PATH`.** It also accepts `pinentry-mac` and
  the `~/.local/bin/pinentry` link `wb tools install pinentry` creates.

- **Vault exports no longer report success when an item wasn't stored.**
  `gpg-export-bitwarden` and `gpg-export-1password` ignored every upload
  result, so a failed `bw`/`op` call or a missing `python3` still printed
  "backup complete" and suggested `gpg-remove-master`. They now check
  each item (the Bitwarden JSON is built before it's piped to `bw`, and a
  new Bitwarden item is looked up again after it's created), print
  "backup INCOMPLETE … Do not remove the master key" and return non-zero
  when any item failed. The `gpg-remove-master` hint prints only after a
  complete backup. Re-running after fixing the problem updates existing
  items rather than duplicating them.
- **`get-gpg-functions` lists the module's functions in zsh.** The
  hand-written getter read `BASH_SOURCE` inside the function, which zsh
  doesn't set, so in zsh it printed only headers and `(none)`. It is
  removed; workbench-core now generates the getter from `workbench.yml`
  (its `docs/decisions-log.md` D89), in bash and zsh, including on hosts
  without gpg, where the old one was never defined. The section headers
  now read `GPG day-to-day and key-lifecycle helpers — functions` and
  `… — aliases`; `get-gpg-functions` no longer lists itself.

### Changed

- Requires workbench-core Core API 1.8 (`core_api: ">=1.8 <2.0"`).

## [0.4.3] - 2026-10-26

### Fixed

- **`gpg-create-key` can install pinentry when it's missing.** It called
  `install-pinentry` directly, but installer files are never loaded into
  your shell, so the offered install failed with `command not found`. It
  now runs `wb tools install pinentry`. Error messages and the README name
  `wb tools install <name>` instead of `install-*` functions you can't
  call directly. Required by workbench-core's module CI clean-shell check
  (its `docs/decisions-log.md` D94).

### Documentation

- Documented temp-file cleanup and Ctrl-C behaviour (README "Temp files
  and Ctrl-C" and a comment at `_gpg_tmp_guard`): the temp file is removed
  on EXIT/INT/TERM, but in an interactive shell the function keeps running
  after Ctrl-C.

## [0.4.2] - 2026-10-10

### Security

- **No predictable `/tmp` paths for key material.** `gpg-create-key`,
  `gpg-push-github` and `gpg-push-gitlab` now use a private `mktemp` file
  (mode 0600, created under umask 077) and remove it via an
  EXIT/INT/TERM trap, so parameter files and exported keys never linger
  after an interrupt. Any traps the calling shell already had are
  restored afterwards.
- **Revocation certificates are created 0600 from the start.**
  `gpg-revoke` and the export helpers' fallback certificate generation now
  run `gpg --gen-revoke` under `umask 077` rather than relying on a
  `chmod` after the write.

### Fixed

- Empty-array expansions (`vault_arg`, `uids`) now use the
  `${arr[@]+"${arr[@]}"}` idiom, so they no longer fail under `set -u` on
  bash < 4.4 (including macOS bash 3.2).

## [0.4.1] - 2026-10-10

### Security

- **Secret material no longer appears in process arguments (review M5).**
  `gpg-export-bitwarden` now pipes item JSON through `bw encode` into
  `bw create item` / `bw edit item` on stdin, and the passphrase reaches
  its JSON builder on stdin. `gpg-export-1password` builds items from
  `op item template get` and passes them with `--template <file>` instead
  of `notesPlain[text]=...` / `password=...` arguments.
- **Private temp location, no stale plaintext (review M6).** Transient
  key exports go to a 0700 directory under `$XDG_RUNTIME_DIR` (then
  `/dev/shm`, then `$TMPDIR`), leftovers older than 60 minutes from
  interrupted runs are swept, secret exports are created 0600 from the
  start, and `gpg-import-bitwarden` / `gpg-import-1password` pipe the key
  straight into `gpg --import` with no plaintext file.

## [0.4.0] - 2026-09-23

### Added

- **Manual `workflow_dispatch` release override.** `release.yml` now
  accepts a `bump_type` (patch/minor/major) input to force a release
  through `workbench-core`'s reusable `module-release.yml`, regardless of
  what Conventional Commits since the last tag would compute — a floor,
  never a downgrade of a higher severity already pending. Manual dispatch
  only runs from `main`. See `workbench-core`'s `docs/decisions-log.md` D67.

## [0.3.0] - 2026-09-21

### Added

- `gpg-push-keyserver` — publish a public signing key to a keyserver.
  Supports `openpgp` (keys.openpgp.org) and `ubuntu`
  (keyserver.ubuntu.com) as short aliases, a bare hostname (tried over
  `hkps://` first, falling back to `hkp://` only if that fails, with a
  warning at the point of fallback), or an explicit `hkps://`/`hkp://` URL
  with no fallback added. One parametrised function rather than a
  per-server duplicate of `gpg-push-github`/`gpg-push-gitlab`, since every
  keyserver speaks the same protocol (those two differ because `gh`/`glab`
  are genuinely different provider APIs). Prints a reminder when pushing
  to keys.openpgp.org that UIDs need email verification before becoming
  publicly searchable.

## [0.2.3] - 2026-09-16

### Changed

- Replaced this module's private `_gpg_functions_exclude_pattern`
  workaround (a hand-rolled exclude-pattern hack in `get-gpg-functions`)
  with `workbench-core`'s shared function-availability convention:
  `_<name>-available` predicates declared via `_wb_declare_availability`.
  `get-gpg-functions` now relies on `_get_functions_in`/`_get_aliases_in`
  to gate automatically, the same as every other module. Also closes a
  gap the old workaround didn't cover: every `gpg`-dependent function in
  `gpg-management.sh` (which has no load-time `gpg` guard of its own,
  unlike `gpg.sh`) is now correctly gated on `gpg` being installed, not
  just the Bitwarden/1Password/GitHub/GitLab-dependent ones.

## [0.2.2] - 2026-09-16

### Fixed

- `gpg-export-bitwarden`/`gpg-export-1password` checked the target key
  existed, and prompted interactively for one when none was given,
  before checking that `bw`/`op` was even installed — someone without
  the CLI would pick a key first and only then hit the missing-tool
  error. Preflight checks now run first, matching every other
  password-manager/forge function in this module (closes #13).
- `get-gpg-functions` listed `gpg-export-bitwarden`,
  `gpg-import-bitwarden`, `gpg-export-1password`,
  `gpg-import-1password`, `gpg-github-keys`, `gpg-push-github`,
  `gpg-gitlab-keys`, and `gpg-push-gitlab` even when their respective
  `bw`/`op`/`gh`/`glab` CLI wasn't installed. Each function still
  exits early with an install hint if run without its tool, but
  offering a command that can only ever fail was misleading, so the
  listing now hides them until the dependent CLI is present (closes
  #13).

## [0.2.1] - 2026-09-15

### Added

- **Agent-instruction files** (`AGENTS.md`, `CLAUDE.md`,
  `.github/copilot-instructions.md`,
  `.claude/skills/conventional-commits/SKILL.md`) — ports
  `workbench-core`'s D32 agent-instruction topology to this repo. See
  `workbench-core`'s `docs/decisions-log.md` D58.
- **Repo governance files** (`.github/PULL_REQUEST_TEMPLATE.md`,
  `.github/ISSUE_TEMPLATE/{bug_report,feature_request,config}.yml`,
  `.github/CODEOWNERS`, `CONTRIBUTING.md`, `SECURITY.md`) — ports
  `workbench-core`'s D31 governance-file topology to this repo,
  piloted on `workbench-git` first. See `workbench-core`'s
  `docs/decisions-log.md` D60.

### Fixed

- Suppressed a `gitleaks` false positive on `gpg-list-signing-keys`'s
  usage docblock: the entropy-based `generic-api-key` rule flagged the
  illustrative example key ID as a possible secret. Not a real
  credential — marked with an inline `gitleaks:allow`.

## [0.2.0] - 2026-09-09

- Added `installed-pinentry` — reports install status to `wb tools upgrade`/
  `list --status` (workbench-core §12 D43).

## [0.1.0] - 2026-09-09

### Added

- Initial decomposition from `workbench-precursor` (Wave C): day-to-day GPG
  functions (`gpg-list`/`gpg-show`/`gpg-verify`/`gpg-agent-*`/
  `gpg-card-status`/`gpg-github-keys`/`gpg-gitlab-keys`), key lifecycle
  management (`gpg-create-key`, UID/subkey/expiry management, export/
  import to Bitwarden and 1Password, rotation, revocation, `gpg-push-*`),
  signing-key resolution consumed by `workbench-git`
  (`_gpg_resolve_signing_key`), and `install-pinentry`.

### Changed

- `_array_get` is module-local here (`shell/gpg.sh`), not Core API — only
  this module needs zsh/bash array-index portability today. Promote to
  `workbench-core` if a second module needs it (same bar `_str_lower`
  cleared).
- The `git_default_signing_key`/`host_vars` global-signing-key wiring from
  `workbench-precursor`'s docs no longer applies — `workbench-core` has no
  host_vars concept, so setting a default signing key globally is now a
  one-time manual `git config --global` step, documented in the README.
