#!/bin/bash
# Mueve workspaces de DP-1 al display virtual al conectar

HEADLESS=$(hyprctl monitors -j | python3 -c \
    "import sys,json; ms=[m['name'] for m in json.load(sys.stdin) if 'HEADLESS' in m['name']]; print(ms[0] if ms else '')")

[ -z "$HEADLESS" ] && exit 1

WS_IDS=$(hyprctl workspaces -j | python3 -c \
    "import sys,json; [print(w['id']) for w in json.load(sys.stdin) if w['monitor']=='DP-1' and w['id']>0]")

for id in $WS_IDS; do
    hyprctl dispatch moveworkspacetomonitor "$id" "$HEADLESS"
done

hyprctl dispatch focusmonitor "$HEADLESS"
