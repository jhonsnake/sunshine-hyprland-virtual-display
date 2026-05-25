#!/bin/bash
# Runs when the client disconnects
# Returns workspaces from the virtual headless display back to DP-1
# and turns the physical monitor back on

HEADLESS=$(hyprctl monitors -j | python3 -c \
    "import sys,json; ms=[m['name'] for m in json.load(sys.stdin) if 'HEADLESS' in m['name']]; print(ms[0] if ms else '')")

[ -z "$HEADLESS" ] && exit 1

# Turn physical monitor back on
hyprctl dispatch dpms on DP-1

WS_IDS=$(hyprctl workspaces -j | python3 -c \
    "import sys,json; [print(w['id']) for w in json.load(sys.stdin) if w['monitor']=='$HEADLESS' and w['id']>0]")

for id in $WS_IDS; do
    hyprctl dispatch moveworkspacetomonitor "$id" DP-1
done

hyprctl dispatch focusmonitor DP-1
