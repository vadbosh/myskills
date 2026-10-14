#!/usr/bin/env bash
# tests/test_install.sh — install.sh into a throwaway HOME: every file in
# place, the hook wired once, a symlink replaced by a copy, a second run
# changing nothing.
#
#   bash tests/test_install.sh
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
ok () { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
no () { fail=$((fail + 1)); printf '  FAIL  %s — %s\n' "$1" "$2"; }

tmp="$(mktemp -d)" || exit 2
trap 'rm -r -- "${tmp:?}"' EXIT
# A copy of the checkout, so the requires.json it installs is a fixture and not
# whatever registry this checkout happens to hold (it is not in git).
SRC="$tmp/repo"; mkdir -p "$SRC"
cp -r "$REPO/bin" "$REPO/lib" "$REPO/skills" "$REPO/commands" "$REPO/install.sh" "$REPO/requires.example.json" "$SRC/"
cp "$REPO/requires.example.json" "$SRC/requires.json"
export HOME="$tmp" MYSKILL_NO_PROBE=1
unset XDG_DATA_HOME XDG_STATE_HOME XDG_CONFIG_HOME CLAUDE_CONFIG_DIR CODEX_HOME MYSKILL_CANON MYSKILL_REQUIRES
mkdir -p "$tmp/.claude" "$tmp/.codex" "$tmp/.config/opencode" "$tmp/.local/bin" "$tmp/old"
# As the canon left it: the CLI a symlink, the hook already wired by hand.
printf '#!/bin/sh\necho old\n' > "$tmp/old/myskill"; chmod 755 "$tmp/old/myskill"
ln -s "$tmp/old/myskill" "$tmp/.local/bin/myskill"
printf '{\n  "model": "kept",\n  "hooks": {"SessionStart": [{"matcher": "", "hooks": [{"type": "command", "command": "/elsewhere/myskill apply", "timeout": 5}]}]}\n}\n' > "$tmp/.claude/settings.json"
printf '{}\n' > "$tmp/.config/opencode/opencode.json"

out1="$(bash "$SRC/install.sh" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "install exits 0"; else no "install exits 0" "rc $rc: $out1"; fi

if [ -f "$tmp/.local/bin/myskill" ] && [ ! -L "$tmp/.local/bin/myskill" ] && cmp -s "$SRC/bin/myskill" "$tmp/.local/bin/myskill"; then
    ok "the CLI symlink is replaced by a copy"
else no "the CLI symlink is replaced by a copy" "$(ls -l "$tmp/.local/bin/myskill")"; fi
if cmp -s "$SRC/requires.json" "$tmp/.local/share/myskill/requires.json"; then ok "requires.json in ~/.local/share/myskill"
else no "requires.json in ~/.local/share/myskill" "missing"; fi

all=1
for d in "$tmp/.claude/skills/myskill" "$tmp/.codex/skills/myskill" "$tmp/.config/opencode/skills/myskill"; do
    diff -r "$SRC/skills/myskill" "$d" >/dev/null 2>&1 || all=0
done
if [ "$all" -eq 1 ]; then ok "the skill folder in all three IDEs"; else no "the skill folder in all three IDEs" "differs"; fi
if cmp -s "$SRC/commands/myskill.md" "$tmp/.config/opencode/commands/myskill.md" && [ ! -e "$tmp/.claude/commands/myskill.md" ]; then
    ok "the command in Opencode only"
else no "the command in Opencode only" "$(ls "$tmp/.claude/commands" "$tmp/.config/opencode/commands" 2>&1)"; fi

n="$(grep -c 'myskill apply' "$tmp/.claude/settings.json")"
if [ "$n" -eq 1 ] && grep -q '"model": "kept"' "$tmp/.claude/settings.json"; then ok "Claude Code: the hand-made hook kept, not doubled, the rest kept"
else no "Claude Code: the hand-made hook kept, not doubled, the rest kept" "$(cat "$tmp/.claude/settings.json")"; fi
if grep -q "\"$tmp/.local/bin/myskill apply\"" "$tmp/.codex/hooks.json" && grep -q '"SessionStart"' "$tmp/.codex/hooks.json"; then
    ok "Codex: hooks.json created with the SessionStart hook"
else no "Codex: hooks.json created with the SessionStart hook" "$(cat "$tmp/.codex/hooks.json" 2>&1)"; fi
if [ "$(cat "$tmp/.config/opencode/opencode.json")" = "{}" ]; then ok "Opencode: opencode.json untouched"
else no "Opencode: opencode.json untouched" "$(cat "$tmp/.config/opencode/opencode.json")"; fi

out2="$(bash "$SRC/install.sh" 2>&1)"
if ! printf '%s\n' "$out2" | grep -qE '^    [+~] |hook added'; then ok "a second run changes nothing"
else no "a second run changes nothing" "$out2"; fi

echo "local edit" >> "$tmp/.claude/skills/myskill/SKILL.md"
bash "$SRC/install.sh" --ide claude > /dev/null 2>&1
if cmp -s "$SRC/skills/myskill/SKILL.md" "$tmp/.claude/skills/myskill/SKILL.md" &&
   grep -rqs 'local edit' "$tmp/.local/state/myskill/backups/"; then
    ok "a local edit is backed up outside the skills directory, then replaced"
else no "a local edit is backed up outside the skills directory, then replaced" "$(ls -R "$tmp/.local/state/myskill" 2>&1)"; fi
if [ -z "$(find "$tmp/.claude/skills" -name '*.bak*')" ]; then ok "no backup inside a skills directory"
else no "no backup inside a skills directory" "$(find "$tmp/.claude/skills" -name '*.bak*')"; fi

PYTHONDONTWRITEBYTECODE=1 python3 "$SRC/lib/wire.py" claude --remove > /dev/null
if ! grep -q 'myskill apply' "$tmp/.claude/settings.json" && grep -q '"model": "kept"' "$tmp/.claude/settings.json"; then
    ok "wire.py --remove takes out only the hook"
else no "wire.py --remove takes out only the hook" "$(cat "$tmp/.claude/settings.json")"; fi

rm "$SRC/requires.json"
out="$(bash "$SRC/install.sh" --ide claude 2>&1)"
if [[ "$out" == *"no requires.json — cp requires.example.json"* ]] && [ -f "$tmp/.local/share/myskill/requires.json" ]; then
    ok "no requires.json in the checkout: says how to make one, keeps the installed copy"
else no "no requires.json in the checkout: says how to make one, keeps the installed copy" "$out"; fi

before="$(find "$tmp" -type f -not -path "$SRC/*" | sort | xargs cksum)"
bash "$SRC/install.sh" --dry-run > /dev/null 2>&1
if [ "$before" = "$(find "$tmp" -type f -not -path "$SRC/*" | sort | xargs cksum)" ]; then ok "--dry-run writes nothing"
else no "--dry-run writes nothing" "files changed"; fi

echo
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
