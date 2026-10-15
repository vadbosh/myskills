# myskills

**One command turns a skill on, hides it from the model, or turns it off. It
does this in Claude Code, Codex and Opencode at once, through each IDE's own
setting.**

`myskill` is a CLI and a skill that calls it. It moves no skill folder and
keeps no state of its own: the state lives in `settings.json`, `config.toml`
and `opencode.json`, where each IDE reads it.

**No time to read?** → [Fast start](FAST-START.md) · [Быстрый старт](FAST-START.RU.md)

[Русская версия](README.RU.md) · How each IDE stores the state:
[English](docs/how-it-works.en.md) · [по-русски](docs/how-it-works.ru.md)

---

## Why myskills exists

Every skill the model is shown puts its name and description into the
context of every session. Some skills are needed once a month. Some cannot
work on this machine at all, because a variable or a program they need is
missing.

Each IDE can switch a skill off, and each does it differently:

| IDE | Off | Hidden from the model, still callable |
|---|---|---|
| Claude Code | `skillOverrides` in `settings.json` | `"user-invocable-only"` |
| Codex | `[[skills.config]]` in `config.toml` | `agents/openai.yaml` in the skill folder |
| Opencode | none | `permission.skill` `deny` in `opencode.json` |

Each IDE also names a skill its own way, and an entry under another name does
nothing. A plugin's skill is the hardest case: Claude Code ignores
`skillOverrides` for it. `myskill` knows these differences, so one command
gives the same result in all three IDEs.

## What is in it

| File | What it does |
|---|---|
| `bin/myskill` | the CLI: `list`, `on`, `manual`, `off`, `deps`, `unusable`, `probe`, `apply` |
| `skills/myskill/SKILL.md` | the skill: `/myskill` in Claude Code and Opencode, `$myskill` in Codex |
| `commands/myskill.md` | the `/myskill` command of Opencode |
| `requires.example.json` | the template of `requires.json`: what each skill needs to work — variables, programs, MCP servers |
| `lib/wire.py` | wires the `SessionStart` hook `myskill apply` into Claude Code and Codex |
| `install.sh` | copies all of the above and wires the hook |
| `lib/skillfiles.sh` | decides when an installed skill folder matches this checkout; `install.sh` and `release.sh` both read it |
| `release.sh` | checks that the changelog, the tag and the installed copies agree |
| `tests/` | `test_myskill.sh` for the CLI, `test_install.sh` for the installer; both run in a temporary `HOME` |

## Install

Linux or macOS, `python3` 3.8 or newer.

```bash
git clone <this-repository> myskills
cd myskills
./install.sh --dry-run    # what would change
./install.sh              # every IDE found under $HOME
```

What goes where:

| Path | What |
|---|---|
| `~/.local/bin/myskill` | the CLI |
| `~/.local/share/myskill/requires.json` | the registry of what skills need, when the checkout has one |
| `~/.claude/skills/myskill/`, `~/.codex/skills/myskill/`, `~/.config/opencode/skills/myskill/` | the skill |
| `~/.config/opencode/commands/myskill.md` | the Opencode command |
| `~/.claude/settings.json`, `~/.codex/hooks.json` | the `SessionStart` hook `myskill apply` |

`install.sh` changes nothing on a second run. It backs up a file or a skill
folder it replaces to `~/.local/state/myskill/backups/`, outside every
directory an IDE reads; `MYSKILL_BACKUP_DIR` moves them. An existing hook
entry whose program is `myskill` is kept and never doubled. If you ran
`myskill manual myskill`, the Codex file it wrote stays after a reinstall. `--ide claude|codex|opencode` limits the run to one IDE.

Restart the IDE after the install: skills and hooks are read at start-up.

## Usage

Ask the assistant: "turn off deploy", "hide diagram from the model", "what
needs notes". Or run the CLI in any shell. The skill names below are examples;
use the names from `myskill list`.

```bash
myskill list                    # a row per skill, a column per IDE
myskill list off                # off in at least one IDE
myskill list deploy             # rows whose name contains "deploy"
myskill manual diagram review   # hidden from the model, /diagram still works
myskill off acme:lint           # a plugin's skill, as <plugin>:<skill>
myskill on diagram              # back to the default
myskill deps notes              # what needs it: hooks, rules, other skills
myskill unusable                # skills that cannot work on this machine
```

`myskill list on` and `myskill list off` show the rows that have that state
in at least one IDE. The counters at the top always cover every skill:

[![myskill list on](docs/list-on.png)](docs/list-on.png)

[![myskill list off](docs/list-off.png)](docs/list-off.png)

### The states

| State | Model uses it by itself | You call it | Claude Code | Codex | Opencode |
|---|:---:|:---:|---|---|---|
| `on` | ✅ | ✅ | `/name` | `$name` | `/name` |
| `manual` | ❌ | ✅ | `/name` | `$name` | `/name` or `/skills` |
| `off` | ❌ | ❌ | — | — | not possible: becomes `manual` |
| `·` | | | the skill is not installed in that IDE | | |

The IDE columns show how you start the skill by hand.

Special cases:

| What | Claude Code | Codex | Opencode |
|---|---|---|---|
| a plugin's skill | `manual` gives `off` | `manual` gives `off` | as in the table |
| a command | as in the table | no commands: `·` | always `manual`: the model never sees a command |

Every change loads in a new session, not in the current one.

## Safety

- **`off` and `manual` refuse a skill that something needs.** `myskill` looks
  for the name in hooks, rules and other skills, prints each line it found, and
  exits 1. Add `--force` only after you read those lines.
- **A file is backed up before it changes.** `settings.json`, `config.toml` and
  `opencode.json` are copied to `~/.local/state/myskill/backups/` first;
  three copies of each are kept.
- **A file of another author is not touched.** An `agents/openai.yaml` that
  `myskill` did not write stays as it is, and `manual` says so.
- **A broken JSON file is not touched.** `myskill` stops and names the file.
- **An `opencode.json` with comments is read but not rewritten.** Opencode
  reads the file as JSONC. Writing it back as JSON would drop the comments, so
  `off` and `on` print the entry to add or remove by hand.
- **A symlinked config file stays a symlink.** The change goes into the file
  it points to, so a dotfiles checkout keeps it.

## What a skill needs

`requires.json` lists what each skill needs to work. `myskill unusable` reads
it and prints the skills that cannot work on this machine. The file is yours
and is not in git: start from `requires.example.json`, then list your own
skills.

```bash
cp requires.example.json requires.json
```

```json
"metrics-query": { "env": ["METRICS_URL"] }
```

| Key | Meaning |
|---|---|
| `env` | every variable must be set |
| `env_any` | at least one variable must be set |
| `bin` | every program must be on `PATH` |
| `mcp` | every MCP server must be in `~/.claude/mcp.json` or `~/.claude.json` |
| `note` | a condition no program can check; printed for you to judge |
| `{}` | checked: the skill needs nothing here |

`myskill probe` reads each Claude Code skill and suggests entries for the skills
that `requires.json` does not list yet. It writes nothing. When a new session
starts, `myskill apply` names those skills once.

`myskill` reads the registry from `MYSKILL_REQUIRES`, else from the checkout it
runs from, else from `~/.local/share/myskill/requires.json`. Edit the file in
the checkout, then run `./install.sh`.

## What myskills does not do

- It does not delete or move a skill folder. To delete a skill, remove it
  with the tool that installed it.
- It does not switch an MCP server, a plugin or a hook on or off.
- It does not change the current session. The IDE reads the new state when the
  next session starts.
- It does not count tokens. `myskill list` prints counts of skills per state,
  not their cost.

## Environment

| Variable | Default | What it sets |
|---|---|---|
| `MYSKILL_CANON` | `~/ai-config-source`, when it has `skills/`; otherwise none | the repository your installed skill folders are copied from, if there is one; a Codex `manual` file is written there too. Set it when your skills come from another directory |
| `MYSKILL_REQUIRES` | see [What a skill needs](#what-a-skill-needs) | the registry file |
| `MYSKILL_BACKUP_DIR` | `~/.local/state/myskill/backups` | where config files are backed up |
| `MYSKILL_NO_PROBE` | unset | when set, `myskill` does not run `codex plugin list` and `opencode debug skill`; tests set it |
| `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `XDG_CONFIG_HOME` | `~/.claude`, `~/.codex`, `~/.config` | where each IDE keeps its configuration |

## Sending a change

Run both test suites before a commit:

```bash
bash tests/test_myskill.sh
bash tests/test_install.sh
```

Every documentation change goes to both languages: `README.md` and
`README.RU.md`, `FAST-START.md` and `FAST-START.RU.md`, and the two files in
`docs/`. Write commit messages in English, with a body that says why.

A release: rename `## Unreleased` in `CHANGELOG.md` to the version and the
date, commit, run `./release.sh tag`, then `./install.sh`. `./release.sh check`
names the step that is missing.

## Licence

MIT, see [LICENSE](LICENSE).
