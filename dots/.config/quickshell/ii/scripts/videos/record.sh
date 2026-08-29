#!/usr/bin/env bash

# echo "SCRIPT STARTED $(date)" >> /tmp/region-record.log

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
JSON_PATH=".screenRecord.savePath"

STATE_FILE="$HOME/.local/state/quickshell/states.json"
STATE_JSON_PATH=".screenRecord.active"

CUSTOM_PATH=$(jq -r "$JSON_PATH" "$CONFIG_FILE" 2>/dev/null)

# One jq read for every encoding option; empty when unset so the wf-recorder
# defaults win.
cfg() {
    jq -r ".screenRecord.$1 // empty" "$CONFIG_FILE" 2>/dev/null
}
CONTAINER=$(cfg container); CONTAINER="${CONTAINER:-mp4}"
CODEC=$(cfg codec)
DEVICE=$(cfg device)
FRAMERATE=$(cfg framerate)
PIXEL_FORMAT=$(cfg pixelFormat); PIXEL_FORMAT="${PIXEL_FORMAT:-yuv420p}"
QUALITY=$(cfg quality)
AUDIO_MODE=$(cfg audioMode); AUDIO_MODE="${AUDIO_MODE:-flag}"
AUDIO_SOURCE=$(cfg audioSource)
AUDIO_CODEC=$(cfg audioCodec)
EXTRA_ARGS=$(cfg extraArgs)

RECORDING_DIR=""

TIMER_PID=""  
SECONDS_ELAPSED=-1

if [[ -n "$CUSTOM_PATH" ]]; then
    RECORDING_DIR="$CUSTOM_PATH"
else
    RECORDING_DIR="$HOME/Videos" # Use default path
fi

start_timer() {
    if [[ -n "$TIMER_PID" ]]; then
        kill "$TIMER_PID" 2>/dev/null
    fi

    ( 
        while true; do
            SECONDS_ELAPSED=$((SECONDS_ELAPSED + 1))
            jq ".screenRecord.seconds = $SECONDS_ELAPSED" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
            sleep 1
        done
    ) &
    TIMER_PID=$!
}
stop_timer() {
    if [[ -n "$TIMER_PID" ]]; then
        kill "$TIMER_PID" 2>/dev/null
        wait "$TIMER_PID" 2>/dev/null
        TIMER_PID=""
        jq ".screenRecord.seconds = 0" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE" # setting it to 0 after killing the timer
    fi
}


trap stop_timer EXIT


getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}

getaudiooutput() {
    case "$AUDIO_SOURCE" in
        "@mic")
            pactl get-default-source
            ;;
        "")
            # The default sink's own monitor, so we catch what is actually
            # playing rather than the first monitor pactl happens to list.
            local sink
            sink=$(pactl get-default-sink 2>/dev/null)
            if [[ -n "$sink" ]]; then
                echo "${sink}.monitor"
            else
                pactl list sources | grep 'Name' | grep 'monitor' | cut -d ' ' -f2 | head -n1
            fi
            ;;
        *)
            echo "$AUDIO_SOURCE"
            ;;
    esac
}
getactivemonitor() {
    hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name'
}

updatestate() {
    local state_value=$1
    jq "$STATE_JSON_PATH = $state_value | .screenRecord.paused = false" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    if [[ "$state_value" == "true" ]]; then
        start_timer
    else
        stop_timer
    fi
}


record() {
    local args=(--pixel-format "$PIXEL_FORMAT" -o "$(getactivemonitor)" -f "./recording_$(getdate).$CONTAINER")
    [[ -n "$CODEC" ]] && args+=(-c "$CODEC")
    [[ -n "$DEVICE" ]] && args+=(-d "$DEVICE")
    [[ -n "$FRAMERATE" ]] && args+=(-r "$FRAMERATE")
    if [[ -n "$QUALITY" && "$QUALITY" != "0" ]]; then
        # crf is a software-encoder option; the hardware ones take qp and would
        # otherwise just ignore the quality setting.
        case "$CODEC" in
            *_vaapi | *_nvenc | *_qsv | *_amf) args+=(-p "qp=$QUALITY") ;;
            *) args+=(-p "crf=$QUALITY") ;;
        esac
    fi
    if [[ $SOUND_FLAG -eq 1 ]]; then
        args+=(--audio="$(getaudiooutput)")
        [[ -n "$AUDIO_CODEC" ]] && args+=(-C "$AUDIO_CODEC")
    fi
    # shellcheck disable=SC2206 # word splitting is the point for a free-text field
    [[ -n "$EXTRA_ARGS" ]] && args+=($EXTRA_ARGS)
    wf-recorder "${args[@]}" "$@"
}

mkdir -p "$RECORDING_DIR"
cd "$RECORDING_DIR" || exit

# parse --region <value> without modifying $@ so other flags like --fullscreen still work
ARGS=("$@")
MANUAL_REGION=""
SOUND_FLAG=0
FULLSCREEN_FLAG=0
for ((i=0;i<${#ARGS[@]};i++)); do
    if [[ "${ARGS[i]}" == "--region" ]]; then
        if (( i+1 < ${#ARGS[@]} )); then
            MANUAL_REGION="${ARGS[i+1]}"
        else
            notify-send "Recording cancelled" "No region specified for --region" -a 'Recorder' & disown
            updatestate false
            exit 1
        fi
    elif [[ "${ARGS[i]}" == "--sound" ]]; then
        SOUND_FLAG=1
    elif [[ "${ARGS[i]}" == "--fullscreen" ]]; then
        FULLSCREEN_FLAG=1
    fi
done

case "$AUDIO_MODE" in
    off) SOUND_FLAG=0 ;;
    always) SOUND_FLAG=1 ;;
esac

if pgrep wf-recorder > /dev/null; then
    notify-send "Recording Stopped" "Stopped" -a 'Recorder' &
    updatestate false
    # SIGCONT after: a paused (SIGSTOPped) wf-recorder only handles the TERM once resumed
    { pkill wf-recorder; pkill -CONT wf-recorder; } &
else
    if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
        notify-send "Starting recording" 'recording_'"$(getdate)"'.'"$CONTAINER" -a 'Recorder' & disown
        updatestate true
        record
    else
        # If a manual region was provided via --region, use it; otherwise run slurp as before.
        if [[ -n "$MANUAL_REGION" ]]; then
            region="$MANUAL_REGION"
        else
            if ! region="$(slurp 2>&1)"; then
                notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
                updatestate false
                exit 1
            fi
        fi

        pos="${region%% *}"      # x,y
        size="${region##* }"     # WxH
        x="${pos%,*}"
        y="${pos#*,}"
        geometry="${x},${y} ${size}"

        notify-send "Starting recording" 'recording_'"$(getdate)"'.'"$CONTAINER" -a 'Recorder' & disown
        updatestate true
        record --geometry "$geometry"
    fi
fi

# echo "SCRIPT EXIT $(date)" >> /tmp/region-record.log