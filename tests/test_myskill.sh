#!/usr/bin/env bash
# tests/test_myskill.sh — bin/myskill writes each IDE's own off-switch and
# takes it out again, leaving the rest of every config as it was.
#
#   bash tests/test_myskill.sh
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
ok () { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
no () { fail=$((fail + 1)); printf '  FAIL  %s — %s\n' "$1" "$2"; }

tmp="$(mktemp -d)" || exit 2
trap 'rm -r -- "${tmp:?}"' EXIT
# MYSKILL_NO_PROBE: never run the real `opencode debug skill` against this fake
# HOME — it is slow, and it rewrote the fixture's opencode.json.
export HOME="$tmp" CLAUDE_CONFIG_DIR="$tmp/.claude" CODEX_HOME="$tmp/.codex" XDG_CONFIG_HOME="$tmp/.config" MYSKILL_NO_PROBE=1 MYSKILL_CANON="$tmp/canon"
unset XDG_STATE_HOME MYSKILL_BACKUP_DIR OPENCODE_DISABLE_CLAUDE_CODE OPENCODE_DISABLE_CLAUDE_CODE_SKILLS
c="$tmp/.claude"; x="$tmp/.codex"; o="$tmp/.config/opencode"
mkdir -p "$c/skills/own" "$c/commands" "$c/plugins" "$x" "$o" "$c/skills-disabled/parked"
printf -- '---\nname: own\n---\n' > "$c/skills/own/SKILL.md"
mkdir -p "$tmp/cache/plug/1.0/skills/pskill"; printf -- '---\nname: pskill\n---\n' > "$tmp/cache/plug/1.0/skills/pskill/SKILL.md"
printf '{"version": 2, "plugins": {"plug@m": [{"installPath": "%s"}]}}\n' "$tmp/cache/plug/1.0" > "$c/plugins/installed_plugins.json"
printf '{\n  "model": "kept",\n  "enabledPlugins": {\n    "plug@m": true\n  }\n}\n' > "$c/settings.json"
printf 'model = "kept"\n\n[plugins."plug@m"]\nenabled = true\n\n[[skills.config]]\npath = "/x/SKILL.md"\nenabled = false\n' > "$x/config.toml"
mkdir -p "$x/plugins/cache/m/plug/1.0/skills/pskill" "$x/plugins/cache/m/plug/1.0/skills/codex-only"
printf -- '---\nname: pskill\n---\n' > "$x/plugins/cache/m/plug/1.0/skills/pskill/SKILL.md"
printf -- '---\nname: codex-only\n---\n' > "$x/plugins/cache/m/plug/1.0/skills/codex-only/SKILL.md"
# A plugin's command (<plugin>:<command>) and a skill its author made user-only
# (disable-model-invocation: true — "locked by author · user-only" in /skills).
mkdir -p "$tmp/cache/plug/1.0/commands" "$tmp/cache/plug/1.0/skills/useronly"
printf -- '---\ndescription: x\n---\n' > "$tmp/cache/plug/1.0/commands/pcmd.md"
printf -- '---\nname: useronly\ndisable-model-invocation: true\n---\n' > "$tmp/cache/plug/1.0/skills/useronly/SKILL.md"
# A bundled openai-curated plugin has no cache entry: read from the checkout.
printf '\n[plugins."cur@openai-curated"]\nenabled = true\n' >> "$x/config.toml"
mkdir -p "$x/.tmp/plugins/plugins/cur/skills/curated-skill"
printf -- '---\nname: curated-skill\n---\n' > "$x/.tmp/plugins/plugins/cur/skills/curated-skill/SKILL.md"
printf '{\n  "permission": {\n    "bash": {\n      "env": "deny"\n    }\n  }\n}\n' > "$o/opencode.json"
cp "$c/settings.json" "$tmp/s0"; cp "$x/config.toml" "$tmp/x0"; cp "$o/opencode.json" "$tmp/o0"
M="$SRC/bin/myskill"
J () { python3 -I -m json.tool "$1" > /dev/null 2>&1; }

"$M" off own pskill > "$tmp/out1"
case "$(tr -d ' \n' < "$c/settings.json")" in *'"skillOverrides":{"own":"off","plug:pskill":"off"}'*'"model":"kept"'*|*'"model":"kept"'*'"skillOverrides":{"own":"off","plug:pskill":"off"}'*)
    ok "Claude Code: own skill by name, plugin skill as <plugin>:<skill>, the rest kept" ;;
    *) no "Claude Code: own skill by name, plugin skill as <plugin>:<skill>, the rest kept" "$(cat "$c/settings.json")" ;; esac
# Codex names a plugin's skill <plugin>:<name> (codex debug prompt-input):
# an entry under the bare name left the plugin's skill visible.
if grep -q '^name = "own"$' "$x/config.toml" && grep -q '^name = "plug:pskill"$' "$x/config.toml" && grep -q '^model = "kept"$' "$x/config.toml"; then
    ok "Codex: a [[skills.config]] name entry per skill, a plugin's as <plugin>:<name>, the rest kept"
else no "Codex: a [[skills.config]] name entry per skill, a plugin's as <plugin>:<name>, the rest kept" "$(cat "$x/config.toml")"; fi
case "$(tr -d ' \n' < "$o/opencode.json")" in *'"bash":{"env":"deny"}'*'"skill":{"own":"deny","pskill":"deny"}'*)
    ok "Opencode: permission.skill deny, permission.bash kept" ;;
    *) no "Opencode: permission.skill deny, permission.bash kept" "$(cat "$o/opencode.json")" ;; esac
if J "$c/settings.json" && J "$o/opencode.json"; then ok "both JSON files still parse"; else no "both JSON files still parse" "broken"; fi

"$M" off own > "$tmp/out2"
if [ "$(grep -c 'no change' "$tmp/out2")" -eq 3 ]; then ok "a second off changes nothing"; else no "a second off changes nothing" "$(cat "$tmp/out2")"; fi

# row <name>: the row of one skill in the table, columns squeezed to one space.
row () { "$M" list --no-color | grep -E "^$1 " | tr -s ' '; }
# own: off in Claude Code, absent from Codex (an entry that waits is no cell),
# and in Opencode, which reads ~/.claude/skills too, hidden from the model by
# deny but callable from /skills — "manual".
if [ "$(row own)" = "own skill off · manual" ] && [ "$(row plug:pskill)" = "plug:pskill plug plugin off off ·" ] &&
   [ "$(row parked)" = "parked skill parked · ·" ]; then
    ok "list: one row per skill, a column per IDE, parked, manual and absent shown"
else no "list: one row per skill, a column per IDE, parked, manual and absent shown" "[$(row own)] [$(row plug:pskill)] [$(row parked)]"; fi
if [ "$(row plug:pcmd)" = "plug:pcmd plug plugin on · ·" ] && [ "$(row plug:useronly)" = "plug:useronly plug plugin manual · ·" ]; then
    ok "list: a plugin's command is a row; an author's user-only skill is manual"
else no "list: a plugin's command is a row; an author's user-only skill is manual" "[$(row plug:pcmd)] [$(row plug:useronly)]"; fi
if [ "$(row plug:codex-only)" = "plug:codex-only plug plugin · on ·" ]; then ok "list: a skill of an enabled Codex plugin is seen in Codex"
else no "list: a skill of an enabled Codex plugin is seen in Codex" "[$(row plug:codex-only)]"; fi
# Measured: a <plugin>@openai-curated enabled with no cache entry has none of
# its skills in the Codex prompt.
if [ -z "$(row curated-skill)" ]; then ok "list: an enabled Codex plugin with no cache entry is not loaded"
else no "list: an enabled Codex plugin with no cache entry is not loaded" "[$(row curated-skill)]"; fi
if [ -z "$(OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 "$M" list --no-color | grep -E '^own ' | grep manual)" ]; then
    ok "list: with OPENCODE_DISABLE_CLAUDE_CODE_SKILLS Opencode does not read ~/.claude/skills"
else no "list: with OPENCODE_DISABLE_CLAUDE_CODE_SKILLS Opencode does not read ~/.claude/skills" "still read"; fi
if [ "$("$M" list off --no-color | grep -cE '^(own|plug:pskill|parked) ')" = 3 ] && [ -z "$("$M" list on --no-color | grep -E '^own ')" ]; then
    ok "list off / list on filter the rows"
else no "list off / list on filter the rows" "wrong rows"; fi
# plug:useronly is manual and nowhere off: list manual has it, list off does not.
if "$M" list manual --no-color | grep -qE '^plug:useronly ' && ! "$M" list off --no-color | grep -qE '^plug:useronly '; then
    ok "list manual filters by state; list off keeps only what is off somewhere"
else no "list manual filters by state; list off keeps only what is off somewhere" "wrong rows"; fi
case "$("$M" list --color)" in *$'\033[31m'*) ok "list --color paints off red" ;; *) no "list --color paints off red" "no colour" ;; esac
case "$("$M" list)" in *$'\033['*) no "list is plain when not on a terminal" "escape codes" ;; *) ok "list is plain when not on a terminal" ;; esac

"$M" on own pskill > /dev/null
if cmp -s "$c/settings.json" "$tmp/s0"; then ok "on gives Claude Code's settings.json back as it was"
else no "on gives Claude Code's settings.json back as it was" "$(cat "$c/settings.json")"; fi
if cmp -s "$x/config.toml" "$tmp/x0"; then ok "on gives Codex's config.toml back as it was"
else no "on gives Codex's config.toml back as it was" "$(cat "$x/config.toml")"; fi
if cmp -s "$o/opencode.json" "$tmp/o0"; then ok "on gives opencode.json back as it was"
else no "on gives opencode.json back as it was" "$(cat "$o/opencode.json")"; fi

case "$("$M" on parked)" in *"is still parked"*) ok "on says a parked folder stays where it is" ;;
    *) no "on says a parked folder stays where it is" "no note" ;; esac
if "$M" off 'bad name' > /dev/null 2>&1; then no "a name with a space is refused" "accepted"; else ok "a name with a space is refused"; fi

# Claude Code ignores skillOverrides for a plugin's skill: its SKILL.md is
# renamed in the plugin's current install, and back on `on`.
ps="$tmp/cache/plug/1.0/skills/pskill"
"$M" off pskill > /dev/null
if [ ! -e "$ps/SKILL.md" ] && [ -e "$ps/SKILL.md.myskill-off" ]; then ok "off renames a plugin skill's SKILL.md"
else no "off renames a plugin skill's SKILL.md" "$(ls "$ps")"; fi
printf -- '---\nname: pskill\n---\n' > "$ps/SKILL.md"; rm "$ps/SKILL.md.myskill-off"    # a plugin update
out="$("$M" apply)"
if [ -z "$out" ] && [ ! -e "$ps/SKILL.md" ] && [ -e "$ps/SKILL.md.myskill-off" ]; then
    ok "apply hides it again after a plugin update, and prints nothing"
else no "apply hides it again after a plugin update, and prints nothing" "out [$out], $(ls "$ps")"; fi
printf -- '---\nname: pskill\n---\n' > "$ps/SKILL.md"; rm "$ps/SKILL.md.myskill-off"
case "$(row plug:pskill)" in "plug:pskill plug plugin on "*) ok "list shows what Claude Code really loads: a SKILL.md that came back is on" ;;
    *) no "list shows what Claude Code really loads: a SKILL.md that came back is on" "[$(row plug:pskill)]" ;; esac
"$M" on pskill > /dev/null
mv "$ps/SKILL.md" "$ps/SKILL.md.skills-tools-disabled"
"$M" on pskill > /dev/null
if [ -e "$ps/SKILL.md" ] && [ ! -e "$ps/SKILL.md.skills-tools-disabled" ]; then ok "on also brings back a SKILL.md skills-tools renamed"
else no "on also brings back a SKILL.md skills-tools renamed" "$(ls "$ps")"; fi

beside="$(find "$c" "$x" "$o" -name '*.bak.*' | wc -l)"
backed="$(find "$tmp/.local/state/myskill/backups" -name '*.bak.*' 2>/dev/null | wc -l)"
if [ "$beside" -eq 0 ] && [ "$backed" -ge 3 ]; then ok "backups go to ~/.local/state/myskill/backups, none beside the files"
else no "backups go to ~/.local/state/myskill/backups, none beside the files" "$beside beside, $backed backed up"; fi

# A machine without one of the IDEs: it is skipped, the other two are changed,
# and list says it is not installed. Each IDE in turn.
"$M" on own > /dev/null
for missing in claude codex opencode; do
    case "$missing" in
        claude)   env="CLAUDE_CONFIG_DIR=$tmp/none"; says="Claude Code: no settings.json — skipped"; head="Claude    not installed"
                  others=("$x/config.toml" "$o/opencode.json") ;;
        codex)    env="CODEX_HOME=$tmp/none";        says="Codex: no config.toml — skipped";        head="Codex     not installed"
                  others=("$c/settings.json" "$o/opencode.json") ;;
        opencode) env="XDG_CONFIG_HOME=$tmp/none";   says="Opencode: no opencode.json — skipped";   head="Opencode  not installed"
                  others=("$c/settings.json" "$x/config.toml") ;;
    esac
    out="$(env "$env" "$M" off own)"; rc=$?
    changed=0; for f in "${others[@]}"; do grep -q 'own' "$f" && changed=$((changed + 1)); done
    lst="$(env "$env" "$M" list --no-color)"
    if [ "$rc" -eq 0 ] && [[ "$out" == *"$says"* ]] && [ "$changed" -eq 2 ] && [[ "$lst" == *"$head"* ]]; then
        ok "no $missing: skipped, the other two changed, list says not installed"
    else no "no $missing: skipped, the other two changed, list says not installed" "rc $rc, changed $changed, [$out]"; fi
    env "$env" "$M" on own > /dev/null
done

# ── manual: hidden from the model, still callable ───────────────────────────
# Claude Code: skillOverrides user-invocable-only. Codex: agents/openai.yaml in
# the installed folder and in the canon, which sync.sh copies from. Opencode:
# deny. A plugin's skill has no such switch and gets off, said so.
mkdir -p "$x/skills/cskill" "$tmp/canon/skills/cskill"
printf -- '---\nname: cskill\n---\n' | tee "$x/skills/cskill/SKILL.md" > "$tmp/canon/skills/cskill/SKILL.md"
cp "$c/settings.json" "$tmp/s1"; cp "$x/config.toml" "$tmp/x1"; cp "$o/opencode.json" "$tmp/o1"
out="$("$M" manual own cskill pskill)"
case "$(tr -d ' \n' < "$c/settings.json")" in *'"own":"user-invocable-only"'*'"plug:pskill":"off"'*)
    ok "manual: Claude Code user-invocable-only, a plugin's skill off" ;;
    *) no "manual: Claude Code user-invocable-only, a plugin's skill off" "$(cat "$c/settings.json")" ;; esac
yaml="agents/openai.yaml"
if grep -q 'allow_implicit_invocation: false' "$x/skills/cskill/$yaml" && cmp -s "$x/skills/cskill/$yaml" "$tmp/canon/skills/cskill/$yaml" &&
   ! grep -q '^name = "cskill"$' "$x/config.toml" && grep -q '^name = "plug:pskill"$' "$x/config.toml"; then
    ok "manual: Codex agents/openai.yaml installed and in the canon, a plugin's skill off"
else no "manual: Codex agents/openai.yaml installed and in the canon, a plugin's skill off" "$(cat "$x/config.toml")"; fi
case "$out" in *"no manual in Claude Code"*"no manual in Codex"*"commit ~/canon/skills/cskill/$yaml"*) ok "manual says what got off instead, and what to commit" ;;
    *) no "manual says what got off instead, and what to commit" "$out" ;; esac
if [ "$(row own)" = "own skill manual · manual" ] && [ "$(row cskill)" = "cskill skill · manual ·" ]; then
    ok "list shows manual in every IDE"
else no "list shows manual in every IDE" "[$(row own)] [$(row cskill)]"; fi
"$M" manual nowhere-in-codex > /dev/null
if ! grep -q '"nowhere-in-codex"' "$x/config.toml"; then ok "manual writes nothing to Codex for a name Codex does not have"
else no "manual writes nothing to Codex for a name Codex does not have" "$(cat "$x/config.toml")"; fi
"$M" on own cskill pskill nowhere-in-codex > /dev/null
if cmp -s "$c/settings.json" "$tmp/s1" && cmp -s "$x/config.toml" "$tmp/x1" && cmp -s "$o/opencode.json" "$tmp/o1" &&
   [ ! -e "$x/skills/cskill/agents" ] && [ ! -e "$tmp/canon/skills/cskill/agents" ] && [ -e "$ps/SKILL.md" ]; then
    ok "on after manual gives every file back as it was"
else no "on after manual gives every file back as it was" "$(ls -R "$x/skills/cskill" "$tmp/canon/skills/cskill")"; fi
mkdir -p "$x/skills/cskill/agents"; printf 'interface:\n  display_name: C\n' > "$x/skills/cskill/$yaml"
out="$("$M" manual cskill)"
if [ "$(cat "$x/skills/cskill/$yaml")" = "$(printf 'interface:\n  display_name: C')" ] && [[ "$out" == *"has its own content — not touched"* ]]; then
    ok "manual never overwrites an openai.yaml it did not write"
else no "manual never overwrites an openai.yaml it did not write" "$out"; fi
"$M" on cskill > /dev/null; rm -r "$x/skills/cskill/agents" "$tmp/canon/skills/cskill/agents" 2>/dev/null

# A skill another repository installs has no canon copy: its Codex manual file
# lives in the installed folder only, and apply puts it back after a reinstall.
mkdir -p "$x/skills/bskill"; printf -- '---\nname: bskill\n---\n' > "$x/skills/bskill/SKILL.md"
"$M" manual bskill > /dev/null
rm -r "$x/skills/bskill/agents"                        # its installer copied the folder over
out="$("$M" apply)"
if [ -z "$out" ] && grep -q 'allow_implicit_invocation: false' "$x/skills/bskill/$yaml"; then
    ok "apply restores the Codex manual file of a skill with no canon copy, silently"
else no "apply restores the Codex manual file of a skill with no canon copy, silently" "out [$out]"; fi
"$M" on bskill > /dev/null
if [ ! -e "$x/skills/bskill/agents" ]; then ok "on removes it again"; else no "on removes it again" "still there"; fi

# A plugin's command is missed by skillOverrides too: its file is renamed.
pc="$tmp/cache/plug/1.0/commands/pcmd"
"$M" off plug:pcmd > /dev/null
if [ ! -e "$pc.md" ] && [ -e "$pc.md.myskill-off" ] && [ "$(row plug:pcmd)" = "plug:pcmd plug plugin off · ·" ]; then
    ok "off renames a plugin command's file, and list shows it off"
else no "off renames a plugin command's file, and list shows it off" "[$(row plug:pcmd)] $(ls "$(dirname "$pc")")"; fi
if ! grep -q '"pcmd"' "$o/opencode.json"; then ok "a plugin's skill Opencode does not load gets no deny under its bare name"
else no "a plugin's skill Opencode does not load gets no deny under its bare name" "$(cat "$o/opencode.json")"; fi
"$M" on plug:pcmd > /dev/null
if [ -e "$pc.md" ] && [ ! -e "$pc.md.myskill-off" ]; then ok "on brings a plugin command's file back"
else no "on brings a plugin command's file back" "$(ls "$(dirname "$pc")")"; fi

# ── what a skill needs to work here ─────────────────────────────────────────
printf '{"_comment":"x","own":{"env":["MYSKILL_T_SET","MYSKILL_T_UNSET"]},"cskill":{"bin":["no-such-binary-xyz"]},"bskill":{"note":"only Azure"},"pskill":{}}\n' > "$tmp/req.json"
mkdir -p "$c/skills/probed"; printf -- '---\nname: probed\n---\nUse $MYSKILL_T_NEW here.\n' > "$c/skills/probed/SKILL.md"
u="$(MYSKILL_REQUIRES="$tmp/req.json" MYSKILL_T_SET=1 "$M" unusable)"
if [[ "$u" == *"own"*"missing env MYSKILL_T_UNSET"* ]] && [[ "$u" != *"MYSKILL_T_SET "* ]] && [[ "$u" == *"cskill"*"missing bin no-such-binary-xyz"* ]] &&
   [[ "$u" == *"for you to judge:"*"bskill"*"only Azure"* ]] && [[ "$u" != *"pskill"* ]]; then
    ok "unusable lists what is missing, notes apart, nothing for an empty entry"
else no "unusable lists what is missing, notes apart, nothing for an empty entry" "$u"; fi
p="$(MYSKILL_REQUIRES="$tmp/req.json" "$M" probe)"
if [[ "$p" == *"probed"*"env? MYSKILL_T_NEW"* ]] && [[ "$p" != *"own "* ]]; then ok "probe suggests a skill not in the registry, skips one that is"
else no "probe suggests a skill not in the registry, skips one that is" "$p"; fi
a="$(MYSKILL_REQUIRES="$tmp/req.json" "$M" apply)"
if [ "$(printf '%s' "$a" | jq -r .systemMessage)" = "myskill: 1 skill(s) not checked for what they need here (probed) — run myskill probe" ]; then
    ok "apply tells the user, once per session start, of a skill nobody checked"
else no "apply tells the user, once per session start, of a skill nobody checked" "[$a]"; fi
rm -r "$c/skills/probed"
if [ -z "$(MYSKILL_REQUIRES="$tmp/req.json" "$M" apply)" ]; then ok "apply is silent when every skill is checked"
else no "apply is silent when every skill is checked" "printed"; fi

# ── what needs a skill ──────────────────────────────────────────────────────
mkdir -p "$c/rules"
printf 'Before any reply, invoke the `own` skill.\nThe ARN is arn:aws:pskill:eu-west-1:cluster.\n' > "$c/rules/needs.md"
cp "$c/settings.json" "$tmp/s2"
d="$("$M" deps own pskill)"
if [[ "$d" == *"own: needed by"*"rule"*"needs.md"*"invoke the \`own\` skill"* ]] && [[ "$d" == *"pskill: nothing needs it"* ]]; then
    ok "deps names the rule and its line; an ARN segment is no reference"
else no "deps names the rule and its line; an ARN segment is no reference" "$d"; fi
"$M" off own > "$tmp/out3" 2> "$tmp/err3"; rc=$?
if [ "$rc" -eq 1 ] && cmp -s "$c/settings.json" "$tmp/s2" && grep -q 'skipped: own' "$tmp/err3"; then
    ok "off skips a skill something needs, and changes nothing"
else no "off skips a skill something needs, and changes nothing" "rc $rc, $(cat "$tmp/err3")"; fi
"$M" manual own cskill > /dev/null 2>&1; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'allow_implicit_invocation' "$x/skills/cskill/$yaml" && ! grep -q '"own"' "$c/settings.json"; then
    ok "manual of two goes ahead with the free one, rc 1 for the skipped one"
else no "manual of two goes ahead with the free one, rc 1 for the skipped one" "rc $rc"; fi
"$M" off own --force > /dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -q '"own": "off"' "$c/settings.json"; then ok "--force overrides the check"
else no "--force overrides the check" "rc $rc"; fi
"$M" on own cskill > /dev/null; rm "$c/rules/needs.md"
# A command that is off itself needs nothing.
printf -- '---\ndescription: x\n---\nInvoke the `own` skill.\n' > "$c/commands/caller.md"
d1="$("$M" deps own)"; "$M" off caller > /dev/null 2>&1; d2="$("$M" deps own)"
if [[ "$d1" == *"caller.md"* ]] && [ "$d2" = "own: nothing needs it" ]; then ok "deps ignores a command that is off itself"
else no "deps ignores a command that is off itself" "[$d1] [$d2]"; fi
"$M" on caller > /dev/null; rm "$c/commands/caller.md"
# An Opencode command: the model never sees it, and Opencode has no switch.
mkdir -p "$o/commands"; printf -- '---\ndescription: x\n---\nx\n' > "$o/commands/occmd.md"
out="$("$M" off occmd)"
if ! grep -q '"occmd"' "$o/opencode.json" && [[ "$out" == *"occmd — an Opencode command"* ]] && [[ "$(row occmd)" == *" manual" ]]; then
    ok "off writes no deny for an Opencode command, says why; list shows it manual"
else no "off writes no deny for an Opencode command, says why; list shows it manual" "[$out] [$(row occmd)]"; fi
"$M" on occmd > /dev/null; rm "$o/commands/occmd.md"
case "$("$M" --help)" in *"examples:"*"myskill manual"*) ok "help has the examples" ;; *) no "help has the examples" "missing" ;; esac

# ── where an installed copy looks ───────────────────────────────────────────
# install.sh copies the CLI to ~/.local/bin and the registry to
# ~/.local/share/myskill; a copy has no checkout beside it to read from.
mkdir -p "$tmp/.local/bin" "$tmp/.local/share/myskill"; cp "$M" "$tmp/.local/bin/myskill"
I="$tmp/.local/bin/myskill"
u="$(env -u MYSKILL_REQUIRES "$I" unusable)"
if [[ "$u" == *"no requires.json at $tmp/.local/share/myskill/requires.json"* ]]; then ok "installed copy: names the registry path it looked for"
else no "installed copy: names the registry path it looked for" "$u"; fi
cp "$tmp/req.json" "$tmp/.local/share/myskill/requires.json"
u="$(env -u MYSKILL_REQUIRES "$I" unusable)"
if [[ "$u" == *"cskill"*"missing bin no-such-binary-xyz"* ]]; then ok "installed copy: reads the registry from ~/.local/share/myskill"
else no "installed copy: reads the registry from ~/.local/share/myskill" "$u"; fi
# The canon is ~/ai-config-source unless MYSKILL_CANON says otherwise — never
# the myskills checkout, whose skills/ holds only myskill.
mkdir -p "$x/skills/cskill" "$tmp/ai-config-source/skills/cskill"
printf -- '---\nname: cskill\n---\n' | tee "$x/skills/cskill/SKILL.md" > "$tmp/ai-config-source/skills/cskill/SKILL.md"
env -u MYSKILL_CANON "$M" manual cskill > /dev/null
if [ -e "$tmp/ai-config-source/skills/cskill/agents/openai.yaml" ] && [ ! -e "$SRC/skills/cskill" ]; then
    ok "manual: without MYSKILL_CANON the Codex file goes to ~/ai-config-source"
else no "manual: without MYSKILL_CANON the Codex file goes to ~/ai-config-source" "$(ls -R "$tmp/ai-config-source/skills/cskill")"; fi
env -u MYSKILL_CANON "$M" on cskill > /dev/null
rm -r "$tmp/ai-config-source"

# ── opencode.json is JSONC; settings.json may be a dotfiles symlink ──────────
h="$tmp/jc"; mkdir -p "$h/.claude/skills/own" "$h/.codex" "$h/.config/opencode" "$h/dot"
printf -- '---\nname: own\n---\n' > "$h/.claude/skills/own/SKILL.md"
: > "$h/.codex/config.toml"
in_h () { HOME="$h" CLAUDE_CONFIG_DIR="$h/.claude" CODEX_HOME="$h/.codex" XDG_CONFIG_HOME="$h/.config" "$M" "$@"; }
# What Opencode itself leaves behind: a URL with // in a string, a trailing comma.
printf '{\n  "$schema": "https://opencode.ai/config.json",\n  "keep": "a,}",\n}\n' > "$h/.config/opencode/opencode.json"
printf '{"model": "x"}\n' > "$h/dot/settings.json"; ln -s "$h/dot/settings.json" "$h/.claude/settings.json"
in_h off own > "$tmp/jc.out" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && J "$h/.config/opencode/opencode.json" &&
   grep -q '"own": "deny"' "$h/.config/opencode/opencode.json" && grep -q '"keep": "a,}"' "$h/.config/opencode/opencode.json" &&
   grep -q 'https://opencode.ai/config.json' "$h/.config/opencode/opencode.json"; then
    ok "Opencode: a trailing comma is read; strings with // and ,} survive the write"
else no "Opencode: a trailing comma is read; strings with // and ,} survive the write" "rc $rc: $(cat "$tmp/jc.out" "$h/.config/opencode/opencode.json")"; fi
if [ -L "$h/.claude/settings.json" ] && grep -q '"own": "off"' "$h/dot/settings.json"; then
    ok "Claude Code: a symlinked settings.json stays a link, the target gets the change"
else no "Claude Code: a symlinked settings.json stays a link, the target gets the change" "$(ls -l "$h/.claude/settings.json")"; fi
in_h on own > /dev/null 2>&1
printf '{\n  // mine\n  "permission": {"skill": {"own": "deny"}}\n}\n' > "$h/.config/opencode/opencode.json"
cp "$h/.config/opencode/opencode.json" "$tmp/jc0"
if in_h list --no-color > "$tmp/jc.out" 2>&1; then ok "list reads an opencode.json with a comment"
else no "list reads an opencode.json with a comment" "$(cat "$tmp/jc.out")"; fi
in_h on own > "$tmp/jc.out" 2>&1
if cmp -s "$h/.config/opencode/opencode.json" "$tmp/jc0" && grep -q 'has comments — not touched; remove from permission.skill: own' "$tmp/jc.out"; then
    ok "Opencode: a file with comments is not rewritten; the change to make is named"
else no "Opencode: a file with comments is not rewritten; the change to make is named" "$(cat "$tmp/jc.out")"; fi

echo
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
