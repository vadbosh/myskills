# shellcheck shell=bash
# lib/skillfiles.sh — sourced by install.sh and release.sh, so the two agree on
# when an installed skill folder matches the release.
#
# One file in an installed folder is the user's state, not the release: the
# Codex manual file `myskill manual myskill` writes. It must equal MANUAL_YAML
# in bin/myskill; tests/test_install.sh runs `myskill manual` and then
# install.sh, which fails if the two drift apart.

MYSKILL_MANUAL_YAML='# myskill manual: hidden from the model, callable as $name
policy:
  allow_implicit_invocation: false'

# own_state FILE — FILE is the manual file myskill wrote.
own_state() {
    [ -f "$1" ] && [ ! -L "$1" ] && [ "$(cat "$1"; printf x)" = "$MYSKILL_MANUAL_YAML"$'\n'x ]
}

# carries_state SRC DST — DST holds a manual file and the release has none.
carries_state() {
    [ ! -e "$1/agents/openai.yaml" ] && own_state "$2/agents/openai.yaml"
}

# same_tree SRC DST — DST is a folder with exactly the files of SRC, a manual
# file aside. A missing file and an extra file both count as a difference.
same_tree() {
    local src="$1" dst="$2" view rc
    { [ -d "$dst" ] && [ ! -L "$dst" ]; } || return 1
    if ! carries_state "$src" "$dst"; then
        diff -r "$src" "$dst" >/dev/null 2>&1
        return
    fi
    view="$(mktemp -d)" || return 2
    cp -r "$dst/." "$view/"
    rm -f "$view/agents/openai.yaml"
    rmdir "$view/agents" 2>/dev/null
    diff -r "$src" "$view" >/dev/null 2>&1
    rc=$?
    rm -r -- "${view:?}"
    return $rc
}
