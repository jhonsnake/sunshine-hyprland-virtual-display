#!/bin/bash
# Runs from hypridle's after_sleep_cmd. Recovers display state so a Moonlight
# client connecting right after S3 resume sees real frames, not a black screen.
#
# Symptoms this fixes:
#   - System idles -> systemctl suspend (500s listener)
#   - User connects from Moonlight; sunshine-connect.sh runs OK
#   - Remote screen stays solid black; Sunshine log shows it still "captures"
#     HEADLESS-N but Hyprland never repaints that output post-resume
#
# Root cause: after S3 the wlr virtual output exists in hyprctl but its
# scanout buffer is stale. Forcing dpms-on globally and bouncing focus to
# the headless monitor and back triggers Hyprland to push a fresh frame.

. "$HOME/.local/bin/sunshine-common.sh"

# Give Hyprland a beat to finish reattaching outputs after resume.
sleep 1

# 1. dpms on for everything (defensive — both physical and virtual).
hyprctl dispatch dpms on >> "$LOG" 2>&1

# 2. Locate the persistent HEADLESS monitor. If missing, nothing else to do
#    here: sunshine-connect.sh's self-heal path will recreate it on next
#    client connect.
HEADLESS=$(headless_name)

if [ -z "$HEADLESS" ]; then
    log "after_sleep: no HEADLESS present (connect.sh will recreate)"
    exit 0
fi

# 3. Repaint kick — bounce focus onto HEADLESS and back. Cheap and forces
#    Hyprland to commit a new frame to the headless scanout.
focus_monitor "$HEADLESS"
sleep 0.2
focus_monitor "$PHYSICAL_MONITOR"

log "after_sleep: dpms-on + repaint kick on $HEADLESS"
