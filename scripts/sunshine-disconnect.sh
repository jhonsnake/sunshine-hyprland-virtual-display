#!/bin/bash
# Runs when the Moonlight client disconnects (Sunshine global_prep_cmd "undo").
#
# Responsibilities (in order):
#   1. Resume hypridle (paused in sunshine-connect.sh).
#   2. Turn the physical monitor back on (DPMS on DP-1).
#   3. Migrate workspaces from HEADLESS back to DP-1.
#   4. Remove the HEADLESS monitor so it doesn't keep receiving workspaces
#      while no remote session is active.

LOG="$HOME/.local/share/sunshine-headless.log"

# --- 1. resume hypridle (no-op if not installed/running) --------------------
pkill -CONT -x hypridle 2>/dev/null

HEADLESS=$(hyprctl monitors -j | python3 -c \
    "import sys,json; ms=[m['name'] for m in json.load(sys.stdin) if 'HEADLESS' in m['name']]; print(ms[0] if ms else '')")

# --- 2. turn the physical monitor back on -----------------------------------
hyprctl dispatch dpms on DP-1

# --- 3. migrate workspaces HEADLESS -> DP-1 ---------------------------------
if [ -n "$HEADLESS" ]; then
    WS_IDS=$(hyprctl workspaces -j | python3 -c \
        "import sys,json; [print(w['id']) for w in json.load(sys.stdin) if w['monitor']=='$HEADLESS' and w['id']>0]")

    for id in $WS_IDS; do
        hyprctl dispatch moveworkspacetomonitor "$id" DP-1
    done
fi

hyprctl dispatch focusmonitor DP-1

# --- 4. remove the HEADLESS monitor -----------------------------------------
# Clears ALL HEADLESS-N entries in case one was left over.
while read -r name; do
    [ -n "$name" ] && hyprctl output remove "$name" >> "$LOG" 2>&1 && sleep 0.3
done < <(hyprctl monitors -j 2>/dev/null | python3 -c \
    "import sys,json; [print(m['name']) for m in json.load(sys.stdin) if 'HEADLESS' in m['name']]")

echo "$(date -Iseconds) Headless removed, remote session ended" >> "$LOG"
