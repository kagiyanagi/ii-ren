#!/usr/bin/env sh
# Config profiles: whole copies of the shell's config.json, kept as <name>.json
# in DIR. The live config always belongs to the active profile, so switching
# saves it into that profile first and nothing changed since the last switch
# is lost.
#
#   profiles.sh DIR CONFIG OP [NAME [NEWNAME]]   OP: list|switch|new|rename|delete
#
# Prints the active name, then a wallpaper the caller should apply (or an empty
# line), then one profile name per line. Exits non-zero if OP failed; the
# listing is printed either way, so the page shows the real state.
D=$1 C=$2 op=$3 a=$4 b=$5
cur=$(cat "$D/.active" 2>/dev/null) || cur=Default
wall=

run() {
    [ "$op" = list ] && return
    mkdir -p "$D" || return
    case $op in
    switch)
        # Checked first: `cat missing > config` would truncate the live config.
        [ -s "$D/$a.json" ] && [ "$a" != "$cur" ] || return
        cat "$C" > "$D/$cur.json" || return
        old=$(jq -r '.background.wallpaperPath // ""' "$C")
        cat "$D/$a.json" > "$C" || return
        printf %s "$a" > "$D/.active"
        new=$(jq -r '.background.wallpaperPath // ""' "$C")
        [ "$new" = "$old" ] || wall=$new
        ;;
    new) [ ! -e "$D/$a.json" ] && cat "$C" > "$D/$cur.json" && cat "$C" > "$D/$a.json" && printf %s "$a" > "$D/.active" ;;
    rename)
        [ ! -e "$D/$b.json" ] || return
        { [ ! -f "$D/$a.json" ] || mv "$D/$a.json" "$D/$b.json"; } &&
        { [ "$a" != "$cur" ] || printf %s "$b" > "$D/.active"; }
        ;;
    delete) [ "$a" != "$cur" ] && rm -f "$D/$a.json" ;;
    *) return 1 ;;
    esac
}

run
status=$?
cat "$D/.active" 2>/dev/null || printf Default
printf '\n%s\n' "$wall"
for f in "$D"/*.json; do [ -e "$f" ] && basename "$f" .json; done
exit $status
