#!/usr/bin/env bash
# Checks that record.sh turns the config into the right wf-recorder command.
# Run it directly: ./test-record-args.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export HOME="$WORK"
mkdir -p "$HOME/.config/illogical-impulse" "$HOME/.local/state/quickshell" "$WORK/bin"
echo '{}' > "$HOME/.local/state/quickshell/states.json"

# Stubs: everything the script shells out to, plus a wf-recorder that only
# records the command line it was given.
for stub in notify-send slurp pkill pgrep; do
    printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/$stub"
done
printf '#!/usr/bin/env bash\necho "$@" > "$WF_LOG"\n' > "$WORK/bin/wf-recorder"
printf '#!/usr/bin/env bash\ncase "$1" in\n  get-default-sink) echo my_sink ;;\n  get-default-source) echo my_mic ;;\nesac\n' > "$WORK/bin/pactl"
printf '#!/usr/bin/env bash\necho '"'"'[{"name":"DP-1","focused":true}]'"'"'\n' > "$WORK/bin/hyprctl"
chmod +x "$WORK"/bin/*
export PATH="$WORK/bin:$PATH"
export WF_LOG="$WORK/cmd"

run() { # run <config json> <record.sh args...>
    echo "$1" > "$HOME/.config/illogical-impulse/config.json"
    shift
    : > "$WF_LOG"
    "$SCRIPT_DIR/record.sh" "$@" > /dev/null 2>&1
    cat "$WF_LOG"
}

expect() { # expect <needle> <haystack>
    [[ "$2" == *"$1"* ]] || { echo "FAIL: expected '$1' in: $2"; exit 1; }
}
reject() {
    [[ "$2" != *"$1"* ]] || { echo "FAIL: did not expect '$1' in: $2"; exit 1; }
}

# Defaults: no config at all, so wf-recorder's own defaults stand.
out=$(run '{}' --fullscreen)
expect "--pixel-format yuv420p" "$out"
expect "recording_" "$out"
reject "--audio" "$out"

# Every encoding knob makes it through.
full='{"screenRecord":{"savePath":"'"$WORK"'/vids","container":"mkv","codec":"libx265","device":"/dev/dri/renderD128","framerate":30,"pixelFormat":"yuv444p","quality":18,"audioCodec":"flac","extraArgs":"--no-damage"}}'
out=$(run "$full" --fullscreen --sound)
expect "-c libx265" "$out"
expect "-d /dev/dri/renderD128" "$out"
expect "-r 30" "$out"
expect "-p crf=18" "$out"
expect ".mkv" "$out"
expect "--no-damage" "$out"
expect "-C flac" "$out"
expect "--audio=my_sink.monitor" "$out"

# Hardware encoders take qp, not crf.
out=$(run '{"screenRecord":{"codec":"h264_vaapi","quality":26}}' --fullscreen)
expect "-p qp=26" "$out"
reject "crf" "$out"

# quality 0 leaves crf alone.
out=$(run '{"screenRecord":{"quality":0}}' --fullscreen)
reject "crf" "$out"

# audioMode overrides the --sound flag both ways.
out=$(run '{"screenRecord":{"audioMode":"off"}}' --fullscreen --sound)
reject "--audio" "$out"
out=$(run '{"screenRecord":{"audioMode":"always"}}' --fullscreen)
expect "--audio=my_sink.monitor" "$out"

# audioSource picks the device: mic sentinel, then a literal name.
out=$(run '{"screenRecord":{"audioMode":"always","audioSource":"@mic"}}' --fullscreen)
expect "--audio=my_mic" "$out"
out=$(run '{"screenRecord":{"audioMode":"always","audioSource":"some_dev.monitor"}}' --fullscreen)
expect "--audio=some_dev.monitor" "$out"

# A region is passed through as geometry.
out=$(run '{}' --region "10,20 300x400")
expect "--geometry 10,20 300x400" "$out"

echo "OK"
