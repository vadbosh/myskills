# How each IDE stores the state

[Русская версия](how-it-works.ru.md) · [README](../README.md)

`myskill` writes the setting each IDE already reads. This page lists those
settings, the name each IDE expects in them, and the cases where the setting
alone is not enough.

## Claude Code

| State | What `myskill` writes |
|---|---|
| `off` | `"skillOverrides": {"<name>": "off"}` in `~/.claude/settings.json` |
| `manual` | `"skillOverrides": {"<name>": "user-invocable-only"}` |
| `on` | removes the entry |

The name is the skill's directory. A plugin's skill is `<plugin>:<directory>`.

**A plugin's skill.** Claude Code ignores `skillOverrides` for a plugin's
skill. The documentation says so, and in a test an `"off"` entry for a
plugin's skill left it loadable in a new session. So `off` also renames `SKILL.md` in the plugin's
current install to `SKILL.md.myskill-off`, and a plugin's command file to
`<name>.md.myskill-off`. The entry in `skillOverrides` stays: it is the list
that `apply` reads. A plugin's skill has no `manual`: `manual` turns it off.

**After a plugin update** the new install has a fresh `SKILL.md`. The
`SessionStart` hook `myskill apply` renames it again.

## Codex

| State | What `myskill` writes |
|---|---|
| `off` | `[[skills.config]]` with `name = "<name>"` and `enabled = false` in `~/.codex/config.toml` |
| `manual` | `<skill>/agents/openai.yaml` with `allow_implicit_invocation: false` |
| `on` | removes both |

The name is the `name:` field of the skill's frontmatter. A plugin's skill is
`<plugin>:<name>`. In a test, an entry under the bare name left the plugin's
skill visible.

**The manual file lives in the skill folder.** An installer may copy that
folder from a source repository. The next copy then drops any file the source
does not have. So `manual` writes the file into the source too:
`$MYSKILL_CANON/skills/<skill>/`, by default `~/ai-config-source/skills/<skill>/`.
Commit it there. A skill whose source is another repository gets the file in
the installed folder only. After its installer runs again, `myskill apply`
writes the file back.

A plugin's skill has no `manual` in Codex either: `manual` turns it off.

**Plugins of a remote marketplace** are enabled on the account, not in
`config.toml`. `myskill` asks `codex plugin list` and keeps the answer in
`~/.cache/myskill/` until `config.toml` or the plugin cache changes.

## Opencode

| State | What `myskill` writes |
|---|---|
| `manual` and `off` | `"permission": {"skill": {"<name>": "deny"}}` in `~/.config/opencode/opencode.json` |
| `on` | removes the entry |

The name is the `name:` field of the frontmatter. A denied skill is hidden from
the model, and `/skills` still runs it. So Opencode has no `off`:
`myskill list` shows a denied skill as `manual`.

Opencode also reads `~/.claude/skills` and `~/.agents/skills`, unless
`OPENCODE_DISABLE_CLAUDE_CODE_SKILLS` is set. `myskill` counts those skills
too.

Which skills of an npm or git plugin Opencode loads is known only to Opencode.
`myskill` asks `opencode debug skill`, which takes about 8 seconds, and keeps
the answer in `~/.cache/myskill/` until `opencode.json` changes.

A command of Opencode is never shown to the model. `myskill off` writes no
entry for it and says why.

## What `apply` does

`myskill apply` runs from the `SessionStart` hook of Claude Code and Codex. It
prints nothing when nothing needs doing.

1. Renames again the `SKILL.md` of a plugin's skill that is `off` in
   `skillOverrides`, after a plugin update brought it back.
2. Writes back a Codex `agents/openai.yaml` that an installer dropped.
3. Names, once per session start, the skills that `requires.json` does not
   list yet.

## What `deps` finds

`myskill deps <name>` searches hooks, rules and other skills for the name, and
prints each line it found. It finds the name, not the intent: a rule that only
offers `/review` counts as needing `review`. Read the lines before you use `--force`.

## How `list` was checked

On 2026-10-08 the output of `myskill list` was compared with each IDE's own
report: `codex debug prompt-input`, `opencode debug skill`, and the skill
listing of Claude Code. They were equal, except for the 12 built-in skills of
Claude Code, which no file names.
