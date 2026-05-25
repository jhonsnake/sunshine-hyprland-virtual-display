#!/bin/bash
# Runs when a Moonlight/Artemis client connects
# Migrates workspaces from DP-1 to the virtual headless display
# and turns off the physical monitor

HEADLESS=$(hyprctl monitors -j | python3 -c \
    "import sys,json; ms=[m['name'] for m in json.load(sys.stdin) if 'HEADLESS' in m['name']]; print(ms[0] if ms else '')")

[ -z "$HEADLESS" ] && exit 1

WS_IDS=$(hyprctl workspaces -j | python3 -c \
    "import sys,json; [print(w['id']) for w in json.load(sys.stdin) if w['monitor']=='DP-1' and w['id']>0]")

for id in $WS_IDS; do
    hyprctl dispatch moveworkspacetomonitor "$id" "$HEADLESS"
done

hyprctl dispatch focusmonitor "$HEADLESS"

# Turn off physical monitor while remote session is active
hyprctl dispatch dpms off DP-1
