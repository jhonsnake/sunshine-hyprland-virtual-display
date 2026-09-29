#!/bin/bash
# Runs when the Moonlight client disconnects (Sunshine global_prep_cmd "undo").
#
# Responsibilities (in order):
#   1. Resume hypridle (paused in sunshine-connect.sh).
#   2. Turn the physical monitor back on (DPMS on).
#   3. Migrate workspaces from HEADLESS back to the physical monitor.
#   4. Disable HEADLESS (or reset it to its default mode) until the next session.
#
# The HEADLESS monitor itself is NOT removed — it persists for the whole
# session so Sunshine's cached output_name stays valid for the next connect.

. "$HOME/.local/bin/sunshine-common.sh"

# --- 1. resume hypridle -----------------------------------------------------
pkill -CONT -x hypridle 2>/dev/null

HEADLESS=$(headless_name)

# --- 2. turn the physical monitor back on -----------------------------------
restore_dpms_wake
bind_input_devices ""
set_dpms on "$PHYSICAL_MONITOR"

# --- 3. re-pin workspaces 1-10 back to the physical monitor, then migrate ---
# Mirror of connect.sh: re-pin BEFORE moving so the workspaces stay put
# afterwards instead of being pulled back to HEADLESS by leftover rules.
pin_workspaces "$PHYSICAL_MONITOR"

if [ -n "$HEADLESS" ]; then
    move_workspaces "$HEADLESS" "$PHYSICAL_MONITOR"
    # --- 4. hide HEADLESS until the next session ------------------------------
    idle_headless "$HEADLESS"
fi

focus_monitor "$PHYSICAL_MONITOR"

rm -f "$STREAMING_FLAG"
log "Client disconnected, workspaces returned to $PHYSICAL_MONITOR"
