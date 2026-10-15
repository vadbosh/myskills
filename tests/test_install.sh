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

# ── review-2026-10-15-installer.md: one group per item ──────────────────────
fresh() { # fresh NAME — a HOME with all three assistants set up, printed
    local h="$tmp/$1"
    mkdir -p "$h/.claude" "$h/.codex" "$h/.config/opencode" "$h/.local/bin"
    printf '{}\n' > "$h/.claude/settings.json"
    printf '{}\n' > "$h/.config/opencode/opencode.json"
    : > "$h/.codex/config.toml"
    printf '%s' "$h"
}
wire() { HOME="$1" PYTHONDONTWRITEBYTECODE=1 python3 "$SRC/lib/wire.py" "${@:2}"; }

# A1: no manual file shipped; the user's own survives a reinstall, both ways.
h="$(fresh a1)"
HOME="$h" bash "$SRC/install.sh" > /dev/null 2>&1
y="$h/.codex/skills/myskill/agents/openai.yaml"
if [ ! -e "$y" ]; then ok "A1: a fresh install leaves myskill implicit in Codex"
else no "A1: a fresh install leaves myskill implicit in Codex" "$y exists"; fi
HOME="$h" "$h/.local/bin/myskill" manual myskill > /dev/null 2>&1
HOME="$h" bash "$SRC/install.sh" > /dev/null 2>&1
out="$(HOME="$h" bash "$SRC/install.sh" 2>&1)"
if [ -e "$y" ] && ! printf '%s\n' "$out" | grep -qE '^    [+~] '; then
    ok "A1: manual, then install twice — the file stays, the second run changes nothing"
else no "A1: manual, then install twice — the file stays, the second run changes nothing" "$(ls "$y" 2>&1); $out"; fi
HOME="$h" "$h/.local/bin/myskill" on myskill > /dev/null 2>&1
HOME="$h" bash "$SRC/install.sh" > /dev/null 2>&1
if [ ! -e "$y" ]; then ok "A1: on, then install — the file does not come back"
else no "A1: on, then install — the file does not come back" "$y exists"; fi

# A2: release.sh check sees a missing and an extra file in an installed folder.
rel="$tmp/rel"; mkdir -p "$rel"
cp -r "$SRC/." "$rel/"; cp "$REPO/release.sh" "$REPO/CHANGELOG.md" "$REPO/.gitignore" "$rel/"
git -C "$rel" init -q && git -C "$rel" add -A &&
    git -C "$rel" -c user.name=t -c user.email=t@t commit -qm t &&
    git -C "$rel" -c user.name=t -c user.email=t@t tag -a "v$(sed -n 's/^## \([0-9][0-9.]*\) — .*/\1/p' "$rel/CHANGELOG.md" | head -1)" -m t
h="$(fresh a2)"
HOME="$h" bash "$rel/install.sh" > /dev/null 2>&1
chk() { HOME="$h" bash "$rel/release.sh" check > "$tmp/chk.out" 2>&1; echo $?; }
rc="$(chk)"; if [ "$rc" -eq 0 ]; then ok "A2: check agrees right after install"
else no "A2: check agrees right after install" "rc $rc: $(cat "$tmp/chk.out")"; fi
mkdir -p "$rel/skills/myskill/references"; echo x > "$rel/skills/myskill/references/new.md"
git -C "$rel" add -A && git -C "$rel" -c user.name=t -c user.email=t@t commit -qm new
rc="$(chk)"; if [ "$rc" -eq 3 ] && grep -q './install.sh' "$tmp/chk.out"; then ok "A2: a new file not installed yet — exit 3"
else no "A2: a new file not installed yet — exit 3" "rc $rc: $(cat "$tmp/chk.out")"; fi
HOME="$h" bash "$rel/install.sh" > /dev/null 2>&1
rm "$h/.codex/skills/myskill/SKILL.md"
rc="$(chk)"; if [ "$rc" -eq 3 ]; then ok "A2: an installed file deleted — exit 3"
else no "A2: an installed file deleted — exit 3" "rc $rc: $(cat "$tmp/chk.out")"; fi
HOME="$h" bash "$rel/install.sh" > /dev/null 2>&1
echo stale > "$h/.claude/skills/myskill/OLD.md"
rc="$(chk)"; if [ "$rc" -eq 3 ]; then ok "A2: a stray file in an installed folder — exit 3"
else no "A2: a stray file in an installed folder — exit 3" "rc $rc: $(cat "$tmp/chk.out")"; fi
HOME="$h" bash "$rel/install.sh" > /dev/null 2>&1
HOME="$h" "$h/.local/bin/myskill" manual myskill > /dev/null 2>&1
rc="$(chk)"; if [ "$rc" -eq 0 ]; then ok "A2: the user's manual file is not a difference"
else no "A2: the user's manual file is not a difference" "rc $rc: $(cat "$tmp/chk.out")"; fi

# A3: a symlinked settings.json is written through the link.
h="$(fresh a3)"; mkdir -p "$h/dotfiles"; printf '{"model": "x"}\n' > "$h/dotfiles/settings.json"
rm "$h/.claude/settings.json"; ln -s "$h/dotfiles/settings.json" "$h/.claude/settings.json"
wire "$h" claude --bin "$h/.local/bin" > /dev/null
if [ -L "$h/.claude/settings.json" ] && grep -q 'myskill apply' "$h/dotfiles/settings.json"; then
    ok "A3: a symlinked settings.json stays a link, the target gets the hook"
else no "A3: a symlinked settings.json stays a link, the target gets the hook" "$(ls -l "$h/.claude/settings.json")"; fi

# A4: a hook that names myskill only as an argument is not ours.
h="$(fresh a4)"
printf '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "other-tool sync myskill"}]}]}}\n' > "$h/.claude/settings.json"
wire "$h" claude --bin "$h/.local/bin" > /dev/null
if grep -q 'myskill apply' "$h/.claude/settings.json"; then ok "A4: a foreign hook mentioning myskill does not stop the wiring"
else no "A4: a foreign hook mentioning myskill does not stop the wiring" "$(cat "$h/.claude/settings.json")"; fi
wire "$h" claude --remove > /dev/null
if grep -q 'other-tool sync myskill' "$h/.claude/settings.json" && ! grep -q 'myskill apply' "$h/.claude/settings.json"; then
    ok "A4: --remove keeps the foreign hook"
else no "A4: --remove keeps the foreign hook" "$(cat "$h/.claude/settings.json")"; fi

# A6: a HOME with a space gives a hook the shell can run, wired once.
h="$(fresh 'a6 x')"; cp "$SRC/bin/myskill" "$h/.local/bin/"
wire "$h" claude --bin "$h/.local/bin" > /dev/null
cmd="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"]["SessionStart"][0]["hooks"][0]["command"])' "$h/.claude/settings.json")"
if HOME="$h" sh -c "$cmd" > /dev/null 2>&1 && wire "$h" claude --bin "$h/.local/bin" | grep -q 'already current'; then
    ok "A6: a path with a space is quoted and recognised as ours"
else no "A6: a path with a space is quoted and recognised as ours" "$cmd"; fi

# A7: a malformed hooks value is a message, not a traceback.
h="$(fresh a7)"; printf '{"hooks": []}\n' > "$h/.claude/settings.json"
out="$(wire "$h" claude --bin "$h/.local/bin" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && [[ "$out" != *Traceback* ]] && [ "$(cat "$h/.claude/settings.json")" = '{"hooks": []}' ]; then
    ok "A7: hooks not an object — exit 1, a message, the file untouched"
else no "A7: hooks not an object — exit 1, a message, the file untouched" "rc $rc: $out"; fi

# A8: a mistyped --ide writes nothing.
h="$(fresh a8)"
HOME="$h" bash "$SRC/install.sh" --ide claud > /dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ] && [ ! -e "$h/.local/bin/myskill" ]; then ok "A8: --ide claud exits 2 before writing"
else no "A8: --ide claud exits 2 before writing" "rc $rc"; fi

# A5: verify starts no IDE, and a config the CLI cannot read is not "did not run".
h="$(fresh a5)"; mkdir -p "$tmp/fakebin"
printf '#!/bin/sh\ntouch "%s/started"\n' "$tmp" > "$tmp/fakebin/opencode"; cp "$tmp/fakebin/opencode" "$tmp/fakebin/codex"
chmod 755 "$tmp/fakebin/opencode" "$tmp/fakebin/codex"
printf '{ "broken"\n' > "$h/.config/opencode/opencode.json"   # not even JSONC
out="$(env -u MYSKILL_NO_PROBE HOME="$h" PATH="$tmp/fakebin:$PATH" bash "$SRC/install.sh" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [[ "$out" == *"installed; \`myskill list\` says"* ]] && [[ "$out" != *"did not run"* ]]; then
    ok "A5: an unreadable opencode.json — exit 0, says what list said"
else no "A5: an unreadable opencode.json — exit 0, says what list said" "rc $rc: $out"; fi
if [ ! -e "$tmp/started" ]; then ok "A5: the installer starts neither opencode nor codex"
else no "A5: the installer starts neither opencode nor codex" "a fake IDE binary ran"; fi

# B1: MYSKILL_BACKUP_DIR moves the backups of wire.py and install.sh too.
h="$(fresh b1)"
MYSKILL_BACKUP_DIR="$h/bak" wire "$h" claude --bin "$h/.local/bin" > /dev/null
HOME="$h" bash "$SRC/install.sh" --ide claude > /dev/null 2>&1
echo "local edit" >> "$h/.claude/skills/myskill/SKILL.md"
MYSKILL_BACKUP_DIR="$h/bak" HOME="$h" bash "$SRC/install.sh" --ide claude > /dev/null 2>&1
if ls "$h/bak" | grep -q '^claude-settings.json.bak' && ls "$h/bak" | grep -q '^claude-skills-myskill.bak'; then
    ok "B1: MYSKILL_BACKUP_DIR is honoured by wire.py and install.sh"
else no "B1: MYSKILL_BACKUP_DIR is honoured by wire.py and install.sh" "$(ls "$h/bak" 2>&1)"; fi

echo
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
