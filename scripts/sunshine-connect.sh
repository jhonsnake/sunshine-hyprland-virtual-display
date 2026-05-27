#!/bin/bash
# Runs when a Moonlight/Artemis client connects (Sunshine global_prep_cmd "do").
#
# Responsibilities (in order):
#   1. Drop any active hyprlock via loginctl (NOT pkill — see history note).
#   2. Pause hypridle so the session won't lock/dim/suspend during remote use.
#   3. Migrate user workspaces from DP-1 onto the persistent HEADLESS monitor.
#   4. Turn off the physical monitor (DPMS off DP-1).
#
# The HEADLESS monitor itself is created at session start by sunshine-start.sh
# and lives for the whole session. Workspace 11 is pre-bound to HEADLESS by
# that script.

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

if [ -z "$HEADLESS" ]; then
    echo "$(date -Iseconds) WARNING: no HEADLESS monitor found on connect" >> "$LOG"
    exit 0
fi

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
