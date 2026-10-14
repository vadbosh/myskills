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
out only ours. Every other key and entry is left as it was. A configuration
file is backed up before it is written, outside every directory an assistant
reads (~/.local/state/myskill/backups/).

Exit codes: 0 done or already current, 3 no configuration file (the assistant
is not set up — not an error), 1 the file could not be read or written.
"""
import argparse
import json
import os
import shutil
import sys
import time

HOME = os.path.expanduser("~")
STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "myskill")
BACKUPS = os.path.join(STATE, "backups")

CONFIG = {
    "claude": os.path.join(HOME, ".claude", "settings.json"),
    "codex": os.path.join(HOME, ".codex", "hooks.json"),
}
EVENT = "SessionStart"
PROGRAM = "myskill"
ARGS = "apply"
TIMEOUT = 5


def is_ours(hook):
    """`/path/myskill apply`, or `python /path/myskill apply`. Backslashes
    count as separators."""
    words = (hook.get("command") or "").split() + list(hook.get("args") or [])
    return any(os.path.basename(w.strip('"\'').replace("\\", "/")) == PROGRAM for w in words)


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
        hook = {"type": "command", "command": f"{os.path.join(bindir, PROGRAM)} {ARGS}", "timeout": TIMEOUT}
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
