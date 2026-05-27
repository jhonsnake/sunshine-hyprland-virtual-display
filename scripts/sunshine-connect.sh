#!/bin/bash
# Runs when a Moonlight/Artemis client connects (Sunshine global_prep_cmd "do").
#
# Responsibilities (in order):
#   1. Drop any active hyprlock via loginctl (NOT pkill — see history note).
#   2. Pause hypridle so the session won't lock/dim/suspend during remote use.
#   3. Migrate user workspaces from DP-1 onto the persistent HEADLESS monitor.
#   4. Turn off the physical monitor (DPMS off DP-1).
#
# The HEADLESS monitor is normally created once per session by
# sunshine-start.sh, but if it's gone at connect time (post-S3 resume edge
# case) this script self-heals: recreates HEADLESS, rewrites sunshine.conf
# output_name, and detach-restarts sunshine. Workspace 11 is pre-bound to
# HEADLESS by sunshine-start.sh (and re-bound here on self-heal).

LOG="$HOME/.local/share/sunshine-headless.log"

# --- 1. unlock --------------------------------------------------------------
# Use the session-lock protocol path. SIGKILLing hyprlock would orphan
# Hyprland's ext-session-lock and strand the session on the recovery screen.
loginctl unlock-session 2>/dev/null

# --- 2. pause hypridle (SIGSTOP preserves state for SIGCONT in disconnect) --
pkill -STOP -x hypridle 2>/dev/null

# --- 3. find the persistent HEADLESS, re-pin workspaces, migrate ------------
HEADLESS=$(hyprctl monitors -j | python3 -c \
    "import sys,json; ms=[m['name'] for m in json.load(sys.stdin) if 'HEADLESS' in m['name']]; print(ms[0] if ms else '')")

# Self-heal: if HEADLESS is missing (e.g. Hyprland tore it down across S3
# resume), recreate it AND restart sunshine so it re-reads output_name.
# The current sunshine process spawned us, so the restart runs detached via
# setsid+nohup. Client briefly sees disconnect, then can reconnect cleanly.
if [ -z "$HEADLESS" ]; then
    echo "$(date -Iseconds) WARNING: no HEADLESS on connect, self-healing" >> "$LOG"
    hyprctl output create headless >> "$LOG" 2>&1
    sleep 0.8
    HEADLESS=$(hyprctl monitors -j | python3 -c \
        "import sys,json; ms=[m['name'] for m in json.load(sys.stdin) if 'HEADLESS' in m['name']]; print(ms[0] if ms else '')")
    if [ -z "$HEADLESS" ]; then
        echo "$(date -Iseconds) ERROR: self-heal failed, could not create HEADLESS" >> "$LOG"
        exit 0
    fi
    hyprctl keyword monitor "$HEADLESS,1920x1080@60,9999x0,1" >> "$LOG" 2>&1
    hyprctl keyword workspace "11, monitor:$HEADLESS, default:true, persistent:true" >> "$LOG" 2>&1
    sed -i "s/^output_name *=.*/output_name = $HEADLESS/" "$HOME/.config/sunshine/sunshine.conf"
    echo "$(date -Iseconds) self-heal: recreated $HEADLESS, scheduling sunshine restart" >> "$LOG"
    setsid nohup bash -c 'sleep 0.5; pkill -x sunshine; sleep 1; exec sunshine' \
        >> "$LOG" 2>&1 < /dev/null &
    exit 0
fi

# Defensive dpms-on for HEADLESS — covers post-S3 resume where the virtual
# output came back in dpms-off state and hypridle's after_sleep_cmd didn't
# fire (e.g. client reconnected before that script's sleep elapsed).
hyprctl dispatch dpms on "$HEADLESS" >> "$LOG" 2>&1

# Re-pin workspaces 1-10 to HEADLESS via hyprctl keyword BEFORE moving them.
# Without this re-pin, the static "monitor:DP-1" rule from sunshine-start.sh
# yanks each workspace back to DP-1 the instant the remote user dispatches
# `workspace N`, leaving the cursor on the (DPMS-off) physical monitor while
# Sunshine still captures HEADLESS — symptom: windows visible, mouse stuck.
for ws in 1 2 3 4 5 6 7 8 9 10; do
    hyprctl keyword workspace "$ws, monitor:$HEADLESS, persistent:false" >/dev/null 2>&1
done

WS_IDS=$(hyprctl workspaces -j | python3 -c \
    "import sys,json; [print(w['id']) for w in json.load(sys.stdin) if w['monitor']=='DP-1' and w['id']>0]")

for id in $WS_IDS; do
    hyprctl dispatch moveworkspacetomonitor "$id" "$HEADLESS"
done

hyprctl dispatch focusmonitor "$HEADLESS"

# --- 4. turn off the physical monitor ---------------------------------------
hyprctl dispatch dpms off DP-1

echo "$(date -Iseconds) Client connected, workspaces migrated to $HEADLESS" >> "$LOG"
