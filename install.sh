#!/usr/bin/env bash
# Install myskill into every coding assistant found under $HOME.
#
#   ./install.sh                 install into every assistant found
#   ./install.sh --dry-run       print what would happen, change nothing
#   ./install.sh --ide NAME      only claude, codex or opencode
#
# What goes where:
#   ~/.local/bin/myskill                 the CLI
#   ~/.local/share/myskill/requires.json what each skill needs to work here,
#                                        when the checkout has one
#   ~/.claude/skills/myskill/  ~/.codex/skills/myskill/
#   ~/.config/opencode/skills/myskill/   the skill (/myskill, $myskill)
#   ~/.config/opencode/commands/myskill.md
#                                        the /myskill command of Opencode
#   ~/.claude/settings.json, ~/.codex/hooks.json
#                                        SessionStart hook `myskill apply`,
#                                        wired by lib/wire.py
#
# Idempotent: a second run changes nothing. A file or skill folder it would
# replace with different content is backed up to ~/.local/state/myskill/backups/
# first — outside every directory an assistant reads, so a backup never loads
# as a second skill. A symlink in place of a file (the canon installed the CLI
# that way) is replaced by a copy. Nothing outside $HOME is written.
set -euo pipefail

# Not ${1/#$HOME/\~}: bash 3.2, the one macOS ships, keeps the backslash.
tilde() { case "$1" in "$HOME"*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/myskill"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/myskill"
DRY_RUN=0
ONLY_IDE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --ide)     ONLY_IDE="${2:?--ide needs claude, codex or opencode}"; shift ;;
        -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}" | sed -e 's/^# //' -e 's/^#$//'; exit 0 ;;
        *)         echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

say() { printf '%s\n' "$*"; }
bad() { printf '%s\n' "$*" >&2; }

command -v python3 >/dev/null 2>&1 || { bad "myskill needs python3 (3.8 or newer)"; exit 1; }
python3 -c 'import sys; sys.exit(sys.version_info < (3, 8))' || { bad "myskill needs python 3.8 or newer"; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"

keep_backup() { # keep_backup PATH — copy a file or folder to $STATE/backups
    mkdir -p "$STATE/backups" && chmod 700 "$STATE" "$STATE/backups"
    local tag
    tag="$(tilde "$1" | tr '/' '-' | sed -e 's/^~-//' -e 's/^-//' -e 's/^\.//' -e 's/-\./-/g')"
    cp -rp "$1" "$STATE/backups/$tag.bak.$STAMP"
}

# install_file SRC DST [MODE] — copy if missing or different; back up what it replaces.
install_file() {
    local src="$1" dst="$2" mode="${3:-644}"
    if [ -f "$dst" ] && [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then
        say "    = $(tilde "$dst")"; return
    fi
    if [ "$DRY_RUN" -eq 1 ]; then say "    would write $(tilde "$dst")"; return; fi
    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        if [ -f "$dst" ] && [ ! -L "$dst" ]; then keep_backup "$dst"; fi
        rm -f "$dst"
        say "    ~ $(tilde "$dst")"
    else
        say "    + $(tilde "$dst")"
    fi
    cp "$src" "$dst"
    chmod "$mode" "$dst"
}

# install_dir SRC DST — replace the folder when it differs; back up what it replaces.
install_dir() {
    local src="$1" dst="$2"
    if [ -d "$dst" ] && [ ! -L "$dst" ] && diff -r "$src" "$dst" >/dev/null 2>&1; then
        say "    = $(tilde "$dst")/"; return
    fi
    if [ "$DRY_RUN" -eq 1 ]; then say "    would write $(tilde "$dst")/"; return; fi
    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        if [ -d "$dst" ] && [ ! -L "$dst" ]; then keep_backup "$dst"; fi
        rm -rf -- "${dst:?}"
        say "    ~ $(tilde "$dst")/"
    else
        say "    + $(tilde "$dst")/"
    fi
    cp -r "$src" "$dst"
}

wire() { # wire IDE — exit code: 0 ok, 3 not set up, 1 failed
    local args=("$1" --bin "$BIN_DIR")
    [ "$DRY_RUN" -eq 1 ] && args+=(--dry-run)
    set +e
    PYTHONDONTWRITEBYTECODE=1 python3 "$SRC/lib/wire.py" "${args[@]}"
    local rc=$?
    set -e
    return $rc
}

detect_ides() {
    if [ -n "$ONLY_IDE" ]; then printf '%s\n' "$ONLY_IDE"; return; fi
    [ -d "$HOME/.claude" ]          && printf 'claude\n'
    [ -d "$HOME/.codex" ]           && printf 'codex\n'
    [ -d "$HOME/.config/opencode" ] && printf 'opencode\n'
    return 0
}

say "── command ──"
install_file "$SRC/bin/myskill" "$BIN_DIR/myskill" 755
# requires.json is yours and not in git; without it the installed copy, if any,
# is left as it is.
if [ -f "$SRC/requires.json" ]; then
    install_file "$SRC/requires.json" "$DATA_DIR/requires.json"
else
    say "    no requires.json — cp requires.example.json requires.json, list your skills, re-run"
fi
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) say "note: $BIN_DIR is not on PATH — the hooks use the full path, the skill does not" ;; esac

unwired=""
found=0
while IFS= read -r ide; do
    [ -n "$ide" ] || continue
    found=1
    say "── $ide ──"
    case "$ide" in
        claude)
            install_dir "$SRC/skills/myskill" "$HOME/.claude/skills/myskill" ;;
        codex)
            install_dir "$SRC/skills/myskill" "$HOME/.codex/skills/myskill" ;;
        opencode)
            install_dir "$SRC/skills/myskill" "$HOME/.config/opencode/skills/myskill"
            install_file "$SRC/commands/myskill.md" "$HOME/.config/opencode/commands/myskill.md" ;;
        *) bad "    unknown assistant: $ide"; exit 2 ;;
    esac
    [ "$ide" = opencode ] && continue   # no hook: its switch lives in opencode.json
    rc=0; wire "$ide" || rc=$?
    case "$rc" in
        0) ;;
        3) say "    (no configuration file yet — start $ide once, then re-run)" ;;
        *) bad "    $ide was NOT wired — see the message above"; unwired="$unwired $ide" ;;
    esac
done < <(detect_ides)

[ "$found" -eq 1 ] || { bad "No assistant found (~/.claude, ~/.codex, ~/.config/opencode). Use --ide to force one."; exit 1; }

say "── verify ──"
if [ "$DRY_RUN" -eq 1 ]; then say "  dry run — nothing was installed"; exit 0; fi
if "$BIN_DIR/myskill" --help | grep -q '^usage: myskill' && "$BIN_DIR/myskill" list >/dev/null; then
    say "  ok — $(tilde "$BIN_DIR/myskill") runs and lists the skills"
else
    bad "  FAIL — $(tilde "$BIN_DIR/myskill") did not run"; exit 1
fi
if [ -n "$unwired" ]; then bad "Not wired:$unwired"; exit 1; fi
say ""
say "Restart your assistant: skills and hooks are read at start-up."
say "Then: /myskill (Claude Code, Opencode), \$myskill (Codex), or \`myskill list\` in any shell."
