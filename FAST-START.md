# Fast start

One screen. Full guide: [README.md](README.md) · [по-русски](FAST-START.RU.md)

## Once

```bash
./install.sh --dry-run   # what would change
./install.sh             # CLI, skill and hook into every IDE found
myskill list             # a row per skill = it works
```

Restart the IDE: skills and hooks are read at start-up.

## Then talk to the assistant

| You say | What happens |
|---|---|
| `/myskill` | the table: every skill, its state in each IDE |
| `what is off` | `myskill list off` |
| `hide diagram from the model` | `manual`: the model does not see it, `/diagram` still works |
| `turn off deploy` | `off` in all three IDEs |
| `turn on diagram` | back to the default |
| `what needs notes` | the hooks, rules and skills that name it |

In Codex the skill is `$myskill`. In any shell the CLI is `myskill`.

## States

| State | Model uses it by itself | You call it | Claude Code | Codex | Opencode |
|---|:---:|:---:|---|---|---|
| `on` | ✅ | ✅ | `/name` | `$name` | `/name` |
| `manual` | ❌ | ✅ | `/name` | `$name` | `/name` or `/skills` |
| `off` | ❌ | ❌ | — | — | not possible: becomes `manual` |
| `·` | | | the skill is not installed in that IDE | | |

A plugin's skill has no `manual` in Claude Code and Codex: it gets `off`.

## When something does not work

```bash
myskill deps <name>     # off or manual refused: these lines need the skill
myskill unusable        # skills that cannot work here: a variable or a program is missing
./release.sh check      # the installed copy differs from this checkout
```

A change does not show in the current session. Start a new one.
