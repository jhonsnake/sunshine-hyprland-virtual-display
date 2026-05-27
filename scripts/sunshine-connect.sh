#!/bin/bash
# Runs when a Moonlight/Artemis client connects (Sunshine global_prep_cmd "do").
#
# Responsibilities (in order):
#   1. Unlock any active hyprlock so the remote client doesn't land on a lock screen.
#   2. Pause hypridle (if present) so the session doesn't lock/dim/suspend
#      during remote use. Resumed in sunshine-disconnect.sh.
#   3. Create a fresh virtual HEADLESS monitor and update sunshine.conf's
#      output_name to its assigned name (e.g. HEADLESS-3). Sunshine (wlr
#      capture) re-reads output_name when starting the stream capture.
#   4. Migrate user workspaces from DP-1 onto the new HEADLESS monitor.
#   5. Turn off the physical monitor (DPMS off DP-1).
#
# The HEADLESS monitor is torn down in sunshine-disconnect.sh ("undo").

LOG="$HOME/.local/share/sunshine-headless.log"
CONF="$HOME/.config/sunshine/sunshine.conf"

# --- 1. unlock hyprlock if active (no-op if not installed/running) ----------
pkill -x hyprlock 2>/dev/null
loginctl unlock-session 2>/dev/null

# --- 2. pause hypridle so the session won't lock/dim during remote use ------
# SIGSTOP preserves the daemon's state; resumed in sunshine-disconnect.sh.
pkill -STOP -x hypridle 2>/dev/null

# --- 3. create HEADLESS monitor ---------------------------------------------
# Remove any HEADLESS residuals first (paranoia; should normally be clean).
while read -r name; do
    [ -n "$name" ] && hyprctl output remove "$name" >> "$LOG" 2>&1 && sleep 0.3
done < <(hyprctl monitors -j 2>/dev/null | python3 -c \
    "import sys,json; [print(m['name']) for m in json.load(sys.stdin) if 'HEADLESS' in m['name']]")

hyprctl output create headless >> "$LOG" 2>&1
sleep 0.8

HEADLESS=$(hyprctl monitors -j | python3 -c \
    "import sys,json; ms=[m['name'] for m in json.load(sys.stdin) if 'HEADLESS' in m['name']]; print(ms[0] if ms else '')")

if [ -z "$HEADLESS" ]; then
    echo "$(date -Iseconds) ERROR: failed to create headless monitor" >> "$LOG"
    exit 1
fi

echo "$(date -Iseconds) Headless created: $HEADLESS" >> "$LOG"

# 1920x1080@60, positioned far off-screen relative to your real monitors.
hyprctl keyword monitor "$HEADLESS,1920x1080@60,9999x0,1" >> "$LOG" 2>&1
sleep 0.3

# Update output_name in sunshine.conf with the real name assigned by Hyprland.
sed -i "s/^output_name *=.*/output_name = $HEADLESS/" "$CONF"

# Belt-and-suspenders: try to get Sunshine to re-read config. SIGHUP is a no-op
# on Sunshine versions that don't implement reload — the stream proceeds with
# whatever output_name was loaded at process start. If your stream lands on
# the wrong display, restart Sunshine after editing the conf instead.
pkill -HUP -x sunshine 2>/dev/null

# --- 4. migrate workspaces DP-1 -> HEADLESS ---------------------------------
WS_IDS=$(hyprctl workspaces -j | python3 -c \
    "import sys,json; [print(w['id']) for w in json.load(sys.stdin) if w['monitor']=='DP-1' and w['id']>0]")

for id in $WS_IDS; do
    hyprctl dispatch moveworkspacetomonitor "$id" "$HEADLESS"
done

hyprctl dispatch focusmonitor "$HEADLESS"

# --- 5. turn off the physical monitor ---------------------------------------
hyprctl dispatch dpms off DP-1
