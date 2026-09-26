#!/usr/bin/env bash
# Saves the image on the clipboard for the Hermes composer to attach.
#
# usage: clipboard-image.sh <dir> [cliphist-binary]
# Prints the saved file's path, the file:// URIs of copied files one per line (a
# file manager's copy), `text` when the clipboard holds something else (the
# composer then pastes it as text), or nothing when there is no image.
#
# The live selection comes first, since it is what was copied last. cliphist is
# the fallback only when the selection is *empty*: a Wayland selection dies with
# the app that offered it, so an image copied from a window that has since closed
# is gone from wl-paste while cliphist still holds it. That is the case that made
# the gateway's clipboard.paste answer "No image found in clipboard". A selection
# that holds text never falls back, or a copy cliphist skipped (a password
# manager's) would attach whatever image it stored before.

set -uo pipefail

dir=${1:?usage: clipboard-image.sh <dir> [cliphist-binary]}
cliphist=${2:-cliphist}
mkdir -p "$dir"
out="$dir/hermes-clip-$(date +%s%N)"

types=$(wl-paste --list-types 2>/dev/null)
# Copied files come first: they are the files themselves, name and all, where an
# image type offered beside them is a preview. cliphist's list line cuts a long
# selection short, so the live one is read whole.
if grep -qx 'text/uri-list' <<<"$types"; then
    uris=$(wl-paste --no-newline --type text/uri-list 2>/dev/null | tr -d '\r' | grep '^file://')
    [[ -n $uris ]] && { echo "$uris"; exit 0; }
fi
mime=$(grep -m1 -xE 'image/(png|jpeg|webp|gif|bmp)' <<<"$types")
if [[ -n $mime ]]; then
    ext=${mime#image/}
    [[ $ext == jpeg ]] && ext=jpg
    wl-paste --no-newline --type "$mime" >"$out.$ext" 2>/dev/null && [[ -s $out.$ext ]] && echo "$out.$ext"
    exit 0
fi
if [[ -n $types ]]; then
    echo text
    exit 0
fi

line=$("$cliphist" list 2>/dev/null | head -n1)
[[ $line =~ binary\ data.*\ (png|jpe?g|webp|gif|bmp)\ [0-9]+x[0-9]+ ]] || exit 0
ext=${BASH_REMATCH[1]/jpeg/jpg}
# Classic cliphist decodes the listed line from stdin; stash takes the id.
if [[ $cliphist == *cliphist* ]]; then  # the test Cliphist.decodeCommand uses
    printf '%s' "$line" | "$cliphist" decode >"$out.$ext" 2>/dev/null
else
    "$cliphist" decode "${line%%$'\t'*}" >"$out.$ext" 2>/dev/null
fi
[[ -s $out.$ext ]] && echo "$out.$ext"
exit 0
