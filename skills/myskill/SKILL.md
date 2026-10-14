---
name: myskill
description: Turn a skill on, manual or off in Claude Code, Codex and Opencode at once, show what needs a skill, and list states, by running the `myskill` CLI. Handles "/myskill", "myskill off|manual|on|deps <name>", "myskill list", "отключи скилл <name>", "скрой от модели <name>", "включи скилл <name>", "что зависит от <name>", "disable skill <name>", "enable skill <name>", "какие скилы выключены". Only runs the CLI; no overview of the skill system.
version: "1.1.0"
---

# myskill

Runs `~/.local/bin/myskill`. It writes each IDE's own off-switch and moves
no skill folder:

| IDE | setting |
|---|---|
| Claude Code | `skillOverrides` in `~/.claude/settings.json` (`off`, or `user-invocable-only` for manual); a plugin's skill or command also gets its file renamed, because `skillOverrides` does not reach plugins — so a plugin's has no manual, only off |
| Codex | off: `[[skills.config]] name = …, enabled = false` in `~/.codex/config.toml`; manual: `<skill>/agents/openai.yaml`, written to the source repository too when the folder is a copy |
| Opencode | `permission.skill` `deny` in `opencode.json` — hides it from the model; `/skills` still runs it (`manual` in the list) |

`list` columns: `on` the model is shown it · `manual` it is not, the user can
call it · `off` neither · `·` not in that IDE.

## Commands

| User intent | Run |
|---|---|
| no arguments, "list", "what is on and off" | `myskill list` — a row per skill, a column per IDE |
| "what is off" | `myskill list off` |
| "what is on" | `myskill list on` |
| "what is manual", "что скрыто от модели" | `myskill list manual` |
| "is X off", a part of a name | `myskill list X` |
| "off X", "отключи X", "disable X" | `myskill off X [Y…]` |
| "hide X from the model", "скрой от модели X", "только вручную X" | `myskill manual X [Y…]` |
| "on X", "включи X", "enable X" | `myskill on X [Y…]` |
| "what needs X", "что зависит от X", "можно ли отключить X" | `myskill deps X [Y…]` |

`off` and `manual` skip a skill that a hook, rule or other skill names, print
those lines, and exit 1. Add `--force` only when the user says so after seeing
them.

A plugin's skill can be given as `<plugin>:<skill>` (`acme:lint`) or by
its bare name. Pass the names exactly as the user wrote them.

## Rules

1. Run the CLI with Bash; never edit `settings.json`, `config.toml` or
   `opencode.json` by hand for this.
2. `off`, `manual` and `on` change three config files. Run them when the user named the
   skill; ask first only when the name is unclear.
3. Do not repeat the CLI output in the reply — it is on screen. Add at most one
   sentence, and say that the change loads in a new session or after a restart
   of the IDE.
4. `myskill apply` belongs to the SessionStart hook; do not run it in chat.
5. CLI missing → say so and point to `./install.sh` of the myskills
   repository; do not imitate it by hand.
