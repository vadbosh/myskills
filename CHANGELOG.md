# Changelog

## Unreleased

### Changed

- Comments in `bin/myskill` and `tests/test_myskill.sh` use example names
  instead of the skills of the machine they were measured on.

## 0.1.0 — 2026-10-14

First release as a repository of its own. Until now `myskill` lived in a
configuration repository together with other skills, and that repository's
sync script installed it.

### Added

- `install.sh`: copies the CLI to `~/.local/bin`, `requires.json` (when the
  checkout has one) to `~/.local/share/myskill/`, the skill into all three IDEs
  and the Opencode command, and wires the `SessionStart` hook through
  `lib/wire.py`. A symlink in place of the CLI is replaced by a copy; an
  existing hook entry is kept.
- `requires.example.json`: the template of the registry.
- `release.sh`: `check` and `tag`.
- `tests/test_install.sh`: the installer in a temporary `HOME`.

### Changed

- `requires.json` is yours and not in git. `myskill` reads it from
  `MYSKILL_REQUIRES`, else from the checkout it runs from, else from
  `~/.local/share/myskill/requires.json`.
- Config files are backed up to `~/.local/state/myskill/backups`, the same
  directory `install.sh` uses.
- The source of the installed skill folders, where a Codex `manual` file is
  also written, is `MYSKILL_CANON`, else `~/ai-config-source`. Before, it was
  the repository the CLI was symlinked from. Now that is this repository, and
  its `skills/` holds only `myskill`.
- The examples in `myskill --help` use example skill names.
