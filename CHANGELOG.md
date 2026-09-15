# Changelog

All notable changes to `workbench-gpg` are documented here.

## [Unreleased]

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
