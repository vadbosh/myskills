#!/usr/bin/env python3
"""Wire the myskill SessionStart hook into one assistant, or unwire it.

  wire.py <claude|codex> --bin DIR [--remove] [--dry-run]

What each assistant gets — files are copied by install.sh, this writes only
the configuration that makes the hook run:

  claude    ~/.claude/settings.json   hooks.SessionStart   myskill apply
  codex     ~/.codex/hooks.json       hooks.SessionStart   myskill apply

`myskill apply` renames again the SKILL.md of a plugin's skill that a plugin
update brought back, and restores a Codex manual file an install dropped.
Opencode needs no hook: its switch lives in opencode.json, which no update
rewrites.

An entry counts as ours when its command's program is `myskill`, whatever
directory it is in: an entry made by hand, or by the ai-config-source canon
before myskill moved out of it, is kept and never doubled, and --remove takes
out only ours. A hook that only mentions myskill as an argument is not ours.
Every other key and entry is left as it was. A configuration file is backed up
before it is written, outside every directory an assistant reads
(MYSKILL_BACKUP_DIR, else ~/.local/state/myskill/backups/); a symlinked one is
written through the link, so a dotfiles checkout keeps the change.

Exit codes: 0 done or already current, 3 no configuration file (the assistant
is not set up — not an error), 1 the file could not be read or written.
"""
import argparse
import json
import os
import re
import shlex
import shutil
import sys
import time

HOME = os.path.expanduser("~")
BACKUPS = os.environ.get("MYSKILL_BACKUP_DIR") or os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "myskill", "backups")

CONFIG = {
    "claude": os.path.join(HOME, ".claude", "settings.json"),
    "codex": os.path.join(HOME, ".codex", "hooks.json"),
}
EVENT = "SessionStart"
PROGRAM = "myskill"
ARGS = "apply"
TIMEOUT = 5
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
INTERPRETERS = re.compile(r"^(env|sh|bash|zsh|python[0-9.]*)$")


def program(hook):
    """The program a hook runs: the first word that is not `VAR=value`, an
    interpreter or an interpreter's option. Backslashes count as separators."""
    command = (hook.get("command") or "").replace("\\", "/")
    try:
        words = shlex.split(command)
    except ValueError:
        words = command.split()
    after_interpreter = False
    for w in words + list(hook.get("args") or []):
        name = os.path.basename(w)
        if ASSIGNMENT.match(w) or (after_interpreter and w.startswith("-")):
            continue
        if INTERPRETERS.match(name):
            after_interpreter = True
            continue
        return name
    return ""


def is_ours(hook):
    """`/path/myskill apply`, `"/a b/myskill" apply`, `python /path/myskill apply`;
    not `other-tool myskill`."""
    return program(hook) == PROGRAM


def shape_error(data):
    """Why the hooks of this file cannot be edited safely, or None."""
    hooks = data.get("hooks")
    if hooks is None:
        return None
    if not isinstance(hooks, dict):
        return "hooks is not an object"
    entries = hooks.get(EVENT)
    if entries is None:
        return None
    if not isinstance(entries, list):
        return f"hooks.{EVENT} is not a list"
    for e in entries:
        if not isinstance(e, dict) or not isinstance(e.get("hooks", []), list) \
                or not all(isinstance(h, dict) for h in e.get("hooks", [])):
            return f"hooks.{EVENT} holds an entry that is not an object with a hooks list"
    return None


def wire_hooks(data, bindir, remove):
    hooks = data.setdefault("hooks", {})
    entries = hooks.get(EVENT, [])
    ours = [e for e in entries if any(is_ours(h) for h in e.get("hooks", []))]
    changed = []
    if remove:
        if ours:
            kept = []
            for e in entries:
                rest = [h for h in e.get("hooks", []) if not is_ours(h)]
                if rest:
                    kept.append(dict(e, hooks=rest))
                elif e not in ours:
                    kept.append(e)
            if kept:
                hooks[EVENT] = kept
            else:
                hooks.pop(EVENT, None)
            changed.append(f"{EVENT} hook removed ({PROGRAM} {ARGS})")
    elif not ours:
        # Quoted: hook commands go through a shell, and a HOME may hold a space.
        hook = {"type": "command", "command": f"{shlex.quote(os.path.join(bindir, PROGRAM))} {ARGS}",
                "timeout": TIMEOUT}
        hooks.setdefault(EVENT, []).append({"matcher": "", "hooks": [hook]})
        changed.append(f"{EVENT} hook added ({PROGRAM} {ARGS})")
    if not hooks:
        data.pop("hooks", None)
    return changed


def backup(path):
    if not os.path.isfile(path):
        return
    os.makedirs(BACKUPS, mode=0o700, exist_ok=True)
    rel = path.replace(HOME, "").replace("\\", "/")
    tag = rel.strip("/").replace("/.", "/").lstrip(".").replace("/", "-")
    shutil.copy2(path, os.path.join(BACKUPS, f"{tag}.bak.{int(time.time())}"))


def atomic_write(path, text):
    # Through a symlink, not over it: os.replace on the link itself would turn
    # a dotfiles-managed file into a plain copy that the dotfiles never see.
    path = os.path.realpath(path)
    tmp = f"{path}.myskill-tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    if os.path.exists(path):
        shutil.copymode(path, tmp)
    os.replace(tmp, path)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("ide", choices=sorted(CONFIG))
    ap.add_argument("--bin", default=os.path.join(HOME, ".local", "bin"))
    ap.add_argument("--remove", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)

    path = CONFIG[a.ide]
    if not os.path.exists(path):
        if a.ide == "codex" and os.path.isdir(os.path.dirname(path)) and not a.remove:
            data = {}           # Codex is set up, it only has no hooks yet
        else:
            print(f"    config not found: {path}", file=sys.stderr)
            return 3
    else:
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
        except ValueError as exc:
            print(f"    {path} is not plain JSON ({exc}) — left untouched; "
                  f"run `{sys.argv[0]} {a.ide} --dry-run` to see what to add by hand", file=sys.stderr)
            return 1
        if not isinstance(data, dict):
            print(f"    {path} is not a JSON object — left untouched", file=sys.stderr)
            return 1
        why = shape_error(data)
        if why:
            print(f"    {path}: {why} — left untouched", file=sys.stderr)
            return 1

    changed = wire_hooks(data, a.bin, a.remove)
    if changed and not a.dry_run:
        backup(path)
        atomic_write(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    prefix = "    would " if a.dry_run else "    "
    for line in changed:
        print(prefix + line)
    if not changed:
        print("    = already current")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
