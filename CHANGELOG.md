# Changelog

## Unreleased

### Changed

- The README screenshots are smaller: 13 px text at 1.5× instead of 15 px at
  2×, about 660 px wide instead of 1020.
- The docs say first that `myskill` is a command for any terminal, with no
  assistant open; the skill is described as an optional way to run it.

## 0.1.2 — 2026-10-15

### Added

- The README shows `myskill list on` and `myskill list off`: `docs/list-on.png`
  and `docs/list-off.png`, rendered from `docs/*.d2`. The `.d2` files hold the
  real output of `myskill list` in a `HOME` with example skills.

## 0.1.1 — 2026-10-15

### Changed

- Comments in `bin/myskill` and `tests/test_myskill.sh` use example names
  instead of the skills of the machine they were measured on.
- `skills/myskill/agents/openai.yaml` is no longer shipped. It was the
  `manual` setting of one machine, and every install made `myskill` manual in
  Codex.

### Fixed

Found by an audit of the installer on 2026-10-15; A1–A8 are its item
numbers.

- A1: `install.sh` keeps the Codex manual file that `myskill manual myskill`
  wrote. Before, every reinstall replaced the folder and undid `on` or
  `manual`.
- A2: `release.sh check` compares installed skill folders as a whole. Before,
  it reported "everything agrees" when an installed file was missing or extra.
- A3: `lib/wire.py` writes a symlinked `settings.json` through the link.
  Before, it replaced the link with a plain file.
- A4: a hook is ours only when its program is `myskill`. Before, a hook that
  named `myskill` as an argument stopped the wiring, and `--remove` deleted it.
- A5: the final check of `install.sh` starts neither opencode nor codex. A
  failing `myskill list` is reported as what it said, not as "did not run".
- A6: the hook command quotes its path, so a `HOME` with a space works.
- A7: a `hooks` value of the wrong type gives a message, not a traceback.
- A8: `install.sh --ide` with an unknown name exits before writing anything.
- `lib/wire.py` and `install.sh` honour `MYSKILL_BACKUP_DIR`, as the README
  says.
- `myskill` reads `opencode.json` as JSONC, the format Opencode reads. Before,
  one comment or trailing comma stopped every command with "not valid JSON",
  and Opencode writes such a comma itself into a `{}` file. A file with
  comments is not rewritten: `off` and `on` print the entry to change by hand.
- `myskill` writes a symlinked `settings.json` or `opencode.json` through the
  link, as `lib/wire.py` does after A3.

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
