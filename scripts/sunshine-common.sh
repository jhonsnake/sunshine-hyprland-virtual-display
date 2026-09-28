#!/bin/bash
# Shared settings and helpers for the sunshine-* scripts.
# Sourced, not executed. User overrides go in ~/.config/sunshine/virtual-display.conf

LOG="$HOME/.local/share/sunshine-headless.log"
CONF="$HOME/.config/sunshine/sunshine.conf"

# --- Defaults (override in virtual-display.conf) -----------------------------
PHYSICAL_MONITOR=""            # empty = first non-HEADLESS monitor
HEADLESS_DEFAULT_MODE="1920x1080@60"
HEADLESS_POSITION="9999x0"     # far away so the mouse can't wander onto it
HEADLESS_SCALE="auto"          # auto = 1.5 for >=2160p, 1.25 for >=1440p, else 1
MATCH_CLIENT_RESOLUTION=true   # resize HEADLESS to the client's width/height/fps on connect
REMOTE_WORKSPACE=11            # workspace that lives on HEADLESS between sessions
SUNSHINE_UNIT=""               # systemd --user unit to (re)start instead of exec'ing sunshine
STREAMING_FLAG="$HOME/.cache/sunshine-streaming"  # exists while a client is connected

USER_CONF="$HOME/.config/sunshine/virtual-display.conf"
# shellcheck source=/dev/null
[ -f "$USER_CONF" ] && . "$USER_CONF"

log() { echo "$(date -Iseconds) $*" >> "$LOG"; }

# Hyprland 0.55+ may run the Lua config provider instead of the classic keywords
HYPR_LUA=0
[ "$(hyprctl dispatch 'hl.dsp.no_op()' 2>/dev/null)" = "ok" ] && HYPR_LUA=1

monitor_names() { # all|headless|physical
    hyprctl monitors all -j 2>/dev/null | python3 -c "
import sys, json
kind = sys.argv[1]
for m in json.load(sys.stdin):
    h = 'HEADLESS' in m['name']
    if kind == 'all' or (kind == 'headless') == h:
        print(m['name'])" "$1"
}

headless_name() { monitor_names headless | head -1; }

[ -z "$PHYSICAL_MONITOR" ] && PHYSICAL_MONITOR=$(monitor_names physical | head -1)

set_monitor() { # name mode position scale
    if [ $HYPR_LUA = 1 ]; then
        hyprctl eval "hl.monitor({output=\"$1\", mode=\"$2\", position=\"$3\", scale=$4})" >> "$LOG" 2>&1
    else
        hyprctl keyword monitor "$1,$2,$3,$4" >> "$LOG" 2>&1
    fi
}

workspace_rule() { # workspace monitor default(true|false|"") persistent(true|false)
    if [ $HYPR_LUA = 1 ]; then
        local opts="persistent=$4"
        [ -n "$3" ] && opts="default=$3, $opts"
        hyprctl eval "hl.workspace_rule({workspace=\"$1\", monitor=\"$2\", $opts})" >> "$LOG" 2>&1
    else
        local opts="persistent:$4"
        [ -n "$3" ] && opts="default:$3, $opts"
        hyprctl keyword workspace "$1, monitor:$2, $opts" >> "$LOG" 2>&1
    fi
}

pin_workspaces() { # monitor [default]
    for ws in 1 2 3 4 5 6 7 8 9 10; do
        workspace_rule "$ws" "$1" "$2" false
    done
}

move_workspaces() { # from-monitor to-monitor
    local id
    for id in $(hyprctl workspaces -j | python3 -c "
import sys, json
for w in json.load(sys.stdin):
    if w['monitor'] == sys.argv[1] and 0 < w['id'] and w['id'] != int(sys.argv[2]):
        print(w['id'])" "$1" "$REMOTE_WORKSPACE"); do
        if [ $HYPR_LUA = 1 ]; then
            hyprctl dispatch "hl.dsp.workspace.move({ workspace=\"$id\", monitor=\"$2\" })" >/dev/null
        else
            hyprctl dispatch moveworkspacetomonitor "$id" "$2" >/dev/null
        fi
    done
}

set_dpms() { # on|off monitor
    if [ $HYPR_LUA = 1 ]; then
        hyprctl dispatch "hl.dsp.dpms({ action=\"$1\", monitor=\"$2\"})" >/dev/null
    else
        hyprctl dispatch dpms "$1" "$2" >/dev/null
    fi
}

focus_monitor() {
    if [ $HYPR_LUA = 1 ]; then
        hyprctl dispatch "hl.dsp.focus({ monitor=\"$1\"})" >/dev/null
    else
        hyprctl dispatch focusmonitor "$1" >/dev/null
    fi
}

scale_for_height() {
    if [ "$HEADLESS_SCALE" != "auto" ]; then
        echo "$HEADLESS_SCALE"
    elif [ "${1:-0}" -ge 2000 ]; then
        echo 1.5
    elif [ "${1:-0}" -ge 1400 ]; then
        echo 1.25
    else
        echo 1
    fi
}

# Creates HEADLESS at the default mode and binds the remote workspace to it.
create_headless() {
    hyprctl output create headless >> "$LOG" 2>&1
    sleep 0.8
    local name
    name=$(headless_name)
    [ -z "$name" ] && return 1
    set_monitor "$name" "$HEADLESS_DEFAULT_MODE" "$HEADLESS_POSITION" 1
    sleep 0.3
    workspace_rule "$REMOTE_WORKSPACE" "$name" true true
    sed -i "s/^output_name *=.*/output_name = $name/" "$CONF"
    grep -q '^output_name' "$CONF" || echo "output_name = $name" >> "$CONF"
    echo "$name"
}

# Starts (or restarts) Sunshine so it re-reads output_name.
# $1 = "exec" to replace the current process when no systemd unit is used.
launch_sunshine() {
    if [ -n "$SUNSHINE_UNIT" ]; then
        systemctl --user restart "$SUNSHINE_UNIT"
    elif [ "$1" = "exec" ]; then
        exec sunshine
    else
        setsid nohup bash -c 'sleep 0.5; pkill -x sunshine; sleep 1; exec sunshine' \
            >> "$LOG" 2>&1 < /dev/null &
    fi
}
