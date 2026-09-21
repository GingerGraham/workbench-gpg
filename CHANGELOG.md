# Changelog

All notable changes to `workbench-gpg` are documented here.

## [Unreleased]

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
