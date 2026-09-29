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
REMOTE_WORKSPACE=11            # workspace HEADLESS shows when a session starts
DISABLE_WHEN_IDLE=true         # disable HEADLESS between sessions so apps never see (or land on) it
SUNSHINE_UNIT=""               # systemd --user unit to (re)start instead of exec'ing sunshine
STREAMING_FLAG="$HOME/.cache/sunshine-streaming"  # exists while a client is connected
# Sunshine's virtual absolute-input devices (see `hyprctl devices`). Hyprland maps absolute
# input over the whole layout, so a Mac/iPad/phone client would click on the physical monitor.
SUNSHINE_INPUT_DEVICES=("libvirtualhid-mouse-(absolute)" "libvirtualhid-touchscreen" "libvirtualhid-pen-tablet")
STATE_FILE="$HOME/.cache/sunshine-headless.state"
# Experimental HDR: when the client asks for HDR, HEADLESS is switched to 10-bit BT.2020/PQ.
# Needs a Sunshine that reads the output's colour (LizardByte/Sunshine PR #5615) and
# `source = <HDR_CONF>` in your Hyprland config: Hyprland only applies HDR to an output
# from a monitorv2 block at config (re)load, not through hyprctl keyword.
ENABLE_HDR=false
HDR_CONF="$HOME/.cache/sunshine-headless-hdr.conf"
# A virtual output has no EDID, so its HDR luminances (sent to the client as HDR
# metadata) must be set explicitly, or the client tone-maps against garbage and
# SDR content shifts colour. SDR white follows ITU-R BT.2408 (203 nits).
HDR_SDR_WHITE=203
HDR_MAX_NITS=1000
HDR_MAX_AVG_NITS=400
HDR_MIN_NITS=0.005

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

workspaces_on() { # monitor -> ids of user workspaces with windows on it (excluding the remote one)
    # Empty ones are skipped: Hyprland auto-creates an empty placeholder as the active
    # workspace of a monitor whose workspaces were all moved away, and recreates it if moved.
    hyprctl workspaces -j | python3 -c "
import sys, json
for w in json.load(sys.stdin):
    if w['monitor'] == sys.argv[1] and 0 < w['id'] and w['id'] != int(sys.argv[2]) and w['windows'] > 0:
        print(w['id'])" "$1" "$REMOTE_WORKSPACE"
}

# Moves are acknowledged with "ok" but silently dropped while the target monitor is
# still waking up from DPMS, so verify and retry a few times.
move_workspaces() { # from-monitor to-monitor
    local id try left
    for try in 1 2 3 4 5; do
        left=$(workspaces_on "$1")
        [ -z "$left" ] && return 0
        for id in $left; do
            if [ $HYPR_LUA = 1 ]; then
                hyprctl dispatch "hl.dsp.workspace.move({ workspace=\"$id\", monitor=\"$2\" })" >/dev/null
            else
                hyprctl dispatch moveworkspacetomonitor "$id" "$2" >/dev/null
            fi
        done
        sleep 0.4
    done
    left=$(workspaces_on "$1")
    [ -n "$left" ] && log "WARNING: workspaces still on $1 after retries: $(echo $left)"
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

# Pins (or unpins, with "") Sunshine's absolute input devices to a monitor.
bind_input_devices() {
    local d
    for d in "${SUNSHINE_INPUT_DEVICES[@]}"; do
        # TODO: Lua config provider equivalent (not verified yet)
        [ $HYPR_LUA = 1 ] && { log "WARNING: input device pinning not implemented for the Lua config provider"; return; }
        hyprctl keyword "device[$d]:output" "$1" >> "$LOG" 2>&1
    done
}

get_option() { hyprctl getoption "$1" -j | python3 -c "import sys,json; print(json.load(sys.stdin).get('int', 1))"; }

set_option() {
    # TODO: Lua config provider equivalent (not verified yet)
    [ $HYPR_LUA = 1 ] && { log "WARNING: cannot set $1 with the Lua config provider"; return; }
    hyprctl keyword "$1" "$2" >> "$LOG" 2>&1
}

# Remote mouse/keyboard input must not wake the (DPMS-off) physical monitor.
suspend_dpms_wake() {
    grep -q '^MOUSE_WAKE=' "$STATE_FILE" 2>/dev/null || {
        echo "MOUSE_WAKE=$(get_option misc:mouse_move_enables_dpms)"
        echo "KEY_WAKE=$(get_option misc:key_press_enables_dpms)"
    } >> "$STATE_FILE"
    set_option misc:mouse_move_enables_dpms false
    set_option misc:key_press_enables_dpms false
}

restore_dpms_wake() {
    local MOUSE_WAKE=1 KEY_WAKE=1
    # shellcheck source=/dev/null
    [ -f "$STATE_FILE" ] && . "$STATE_FILE"
    set_option misc:mouse_move_enables_dpms "$([ "$MOUSE_WAKE" = 1 ] && echo true || echo false)"
    set_option misc:key_press_enables_dpms "$([ "$KEY_WAKE" = 1 ] && echo true || echo false)"
    rm -f "$STATE_FILE"
}

# Disables HEADLESS between sessions. It keeps its name, and Sunshine re-lists the
# outputs on every session start, so connect.sh just re-enables it in time.
idle_headless() { # name
    if [ "$DISABLE_WHEN_IDLE" != true ]; then
        set_monitor "$1" "$HEADLESS_DEFAULT_MODE" "$HEADLESS_POSITION" 1
    elif [ $HYPR_LUA = 1 ]; then
        log "WARNING: disabling HEADLESS not implemented for the Lua config provider"
        set_monitor "$1" "$HEADLESS_DEFAULT_MODE" "$HEADLESS_POSITION" 1
    else
        hyprctl keyword monitor "$1,disable" >> "$LOG" 2>&1
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

# --- Experimental HDR ----------------------------------------------------------
client_wants_hdr() {
    [ "$ENABLE_HDR" = true ] && [[ "${SUNSHINE_CLIENT_HDR:-}" =~ ^(1|[Tt]rue|TRUE)$ ]]
}

hdr_active() { grep -q '^monitorv2' "$HDR_CONF" 2>/dev/null; }

# Writes (or clears, with no arguments) the monitorv2 block Hyprland sources for HEADLESS.
write_hdr_conf() { # [name mode scale]
    mkdir -p "$(dirname "$HDR_CONF")"
    if [ -z "${1:-}" ]; then
        echo "# Managed by sunshine-hyprland-virtual-display: no HDR session active." > "$HDR_CONF"
        return
    fi
    cat > "$HDR_CONF" <<EOF
# Managed by sunshine-hyprland-virtual-display: HDR session active.
monitorv2 {
    output = $1
    mode = $2
    position = $HEADLESS_POSITION
    scale = $3
    bitdepth = 10
    supports_wide_color = 1
    supports_hdr = 1
    cm = hdr
    sdr_min_luminance = $HDR_MIN_NITS
    sdr_max_luminance = $HDR_SDR_WHITE
    min_luminance = $HDR_MIN_NITS
    max_luminance = $HDR_MAX_NITS
    max_avg_luminance = $HDR_MAX_AVG_NITS
}
EOF
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
    workspace_rule "$REMOTE_WORKSPACE" "$name" true false
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
