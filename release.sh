#!/usr/bin/env bash
# release.sh — keep the changelog, the tag and the installed copies in agreement.
#
#   ./release.sh check     say whether they agree; exit 3 if they do not
#   ./release.sh tag       create the missing annotated tag for the current version
#
# The newest numbered heading in CHANGELOG.md (`## 0.1.0 — 2026-10-14`) is the
# version; there is no version string anywhere else. A release is: rename
# `## Unreleased` to the number and date, commit, `./release.sh tag`, push with
# --follow-tags when there is a remote, ./install.sh. `check` says which of
# those steps is missing, including the last one: an installed copy that is
# behind is the copy that runs.
set -uo pipefail

tilde() { case "$1" in "$HOME"*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SRC" || exit 2
# shellcheck source=lib/skillfiles.sh
. "$SRC/lib/skillfiles.sh"

version() {
    sed -n 's/^## \([0-9][0-9.]*\) — .*/\1/p' CHANGELOG.md | head -1
}

# Installed path for each shipped file, as install.sh writes it.
installed() {
    local data="${XDG_DATA_HOME:-$HOME/.local/share}/myskill"
    cat <<EOF
bin/myskill $HOME/.local/bin/myskill
commands/myskill.md $HOME/.config/opencode/commands/myskill.md
EOF
    # Not in git, so not part of a release; compared only when there is one.
    [ -f requires.json ] && printf 'requires.json %s\n' "$data/requires.json"
    return 0
}

# Installed skill folders, compared as a whole: a file missing from one, or
# left over in one, makes it stale as surely as a changed file does.
installed_dirs() {
    printf '%s\n' "$HOME/.claude/skills/myskill" "$HOME/.codex/skills/myskill" \
        "$HOME/.config/opencode/skills/myskill"
}

check() {
    local v bad=0 n=0 stale=0
    v="$(version)"
    if [ -z "$v" ]; then echo "  version:      none — no '## X.Y.Z — date' heading in CHANGELOG.md"; return 3; fi
    echo "  version:      $v (CHANGELOG.md)"
    if git rev-parse -q --verify "refs/tags/v$v" >/dev/null; then
        echo "  git tag:      v$v exists"
        local since
        since="$(git rev-list --count "v$v..HEAD")"
        if [ "$since" -eq 0 ]; then
            echo "  unreleased:   nothing since v$v"
        else
            echo "  unreleased:   $since commit(s) since v$v"
            grep -q '^## Unreleased' CHANGELOG.md || { echo "                and no '## Unreleased' section describes them"; bad=1; }
        fi
    else
        echo "  git tag:      v$v MISSING — ./release.sh tag"; bad=1
    fi
    [ -z "$(git status --porcelain)" ] || { echo "  working tree: uncommitted changes"; bad=1; }
    while read -r src dst; do
        [ -e "$dst" ] || continue
        n=$((n + 1))
        if ! cmp -s "$src" "$dst"; then echo "  installed:    $(tilde "$dst") differs from $src — ./install.sh"; stale=1; fi
    done < <(installed)
    while IFS= read -r dst; do
        [ -d "$dst" ] || continue       # that assistant is not set up
        n=$((n + 1))
        if ! same_tree skills/myskill "$dst"; then
            echo "  installed:    $(tilde "$dst")/ differs from skills/myskill (a file changed, missing or extra) — ./install.sh"
            stale=1
        fi
    done < <(installed_dirs)
    [ "$stale" -eq 0 ] && echo "  installed:    $n cop(ies), all identical to this checkout"
    [ "$stale" -eq 0 ] || bad=1
    if [ "$bad" -eq 0 ]; then echo "  everything agrees on $v"; return 0; fi
    return 3
}

make_tag() {
    local v
    v="$(version)"
    [ -n "$v" ] || { echo "no version in CHANGELOG.md" >&2; return 2; }
    if git rev-parse -q --verify "refs/tags/v$v" >/dev/null; then echo "v$v already exists"; return 0; fi
    [ -z "$(git status --porcelain)" ] || { echo "commit first: the tag must point at what CHANGELOG.md describes" >&2; return 2; }
    git tag -a "v$v" -m "myskill $v"
    echo "created v$v at $(git rev-parse --short HEAD)"
    if git remote | grep -q .; then echo "push it with:  git push --follow-tags"; fi
}

case "${1:-check}" in
    check) check ;;
    tag)   make_tag ;;
    *)     sed -n '2,12p' "$0" | sed -e 's/^# //' -e 's/^#$//'; exit 2 ;;
esac
