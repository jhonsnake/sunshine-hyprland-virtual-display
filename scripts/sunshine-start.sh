#!/bin/bash
# Creates a persistent virtual HEADLESS display and launches Sunshine.
#
# Sunshine (wlr-capture backend) reads output_name once at process startup and
# caches it — SIGHUP and HTTP API reloads do not refresh the cached value.
# So the HEADLESS monitor must exist AND its name must be written to
# sunshine.conf BEFORE we exec sunshine. Once Sunshine is up the monitor
# stays alive for the lifetime of the session, and the connect/disconnect
# scripts only migrate workspaces in and out of it.
#
# To prevent the persistent HEADLESS from receiving local workspaces between
# remote sessions, this script also pins workspace 11 ("remote") to the
# HEADLESS monitor and sets workspaces 1-10 as defaults on DP-1.

LOG="$HOME/.local/share/sunshine-headless.log"
CONF="$HOME/.config/sunshine/sunshine.conf"

# --- Clean any HEADLESS leftovers from a previous Hyprland session ----------
while read -r name; do
    [ -n "$name" ] && hyprctl output remove "$name" >> "$LOG" 2>&1 && sleep 0.3
done < <(hyprctl monitors -j 2>/dev/null | python3 -c \
    "import sys,json; [print(m['name']) for m in json.load(sys.stdin) if 'HEADLESS' in m['name']]")

# --- Create the persistent HEADLESS monitor ---------------------------------
hyprctl output create headless >> "$LOG" 2>&1
sleep 0.8

HEADLESS=$(hyprctl monitors -j | python3 -c \
    "import sys,json; ms=[m['name'] for m in json.load(sys.stdin) if 'HEADLESS' in m['name']]; print(ms[0] if ms else '')")

if [ -z "$HEADLESS" ]; then
    echo "$(date -Iseconds) ERROR: failed to create headless monitor" >> "$LOG"
    exec sunshine
fi

echo "$(date -Iseconds) Headless created: $HEADLESS" >> "$LOG"

# 1920x1080@60, placed far off-screen so it can't be reached with the mouse.
hyprctl keyword monitor "$HEADLESS,1920x1080@60,9999x0,1" >> "$LOG" 2>&1
sleep 0.3

# --- Pin workspaces so local windows stay on DP-1 ---------------------------
# Workspaces 1-10 default to DP-1; workspace 11 lives on HEADLESS and serves
# as the "remote" workspace that connect.sh migrates into.
for ws in 1 2 3 4 5 6 7 8 9 10; do
    hyprctl keyword workspace "$ws, monitor:DP-1, default:true, persistent:false" >> "$LOG" 2>&1
done
hyprctl keyword workspace "11, monitor:$HEADLESS, default:true, persistent:true" >> "$LOG" 2>&1

# --- Write the headless name into sunshine.conf BEFORE launching sunshine ---
# Sunshine reads output_name once and caches it for the process lifetime.
sed -i "s/^output_name *=.*/output_name = $HEADLESS/" "$CONF"

exec sunshine
