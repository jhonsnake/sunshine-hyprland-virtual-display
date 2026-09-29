#!/bin/bash
# Creates a persistent virtual HEADLESS display and launches Sunshine.
#
# Sunshine (wlr-capture backend) reads output_name once at process startup and
# caches it — SIGHUP and HTTP API reloads do not refresh the cached value.
# So the HEADLESS monitor must exist AND its name must be written to
# sunshine.conf BEFORE Sunshine starts. Once Sunshine is up the monitor
# stays alive for the lifetime of the session; the connect/disconnect scripts
# only resize it and migrate workspaces in and out of it.
#
# To prevent the persistent HEADLESS from receiving local workspaces between
# remote sessions, this script pins workspaces 1-10 to the physical monitor and
# the remote workspace (11 by default) to HEADLESS.

. "$HOME/.local/bin/sunshine-common.sh"

# --- Clean any HEADLESS leftovers from a previous Hyprland session ----------
for name in $(monitor_names headless); do
    hyprctl output remove "$name" >> "$LOG" 2>&1 && sleep 0.3
done
rm -f "$STREAMING_FLAG" "$STATE_FILE"
# No session yet: make sure the sourced HDR block exists and is empty (also clears a
# block left behind if Hyprland or Sunshine died during an HDR session).
write_hdr_conf

# --- Create the persistent HEADLESS monitor ---------------------------------
HEADLESS=$(create_headless)
if [ -z "$HEADLESS" ]; then
    log "ERROR: failed to create headless monitor"
    launch_sunshine exec
    exit 0
fi
log "Headless created: $HEADLESS (physical: $PHYSICAL_MONITOR)"

# --- Pin workspaces so local windows stay on the physical monitor -----------
pin_workspaces "$PHYSICAL_MONITOR" true

# --- Nobody is connected yet: hide HEADLESS until a client shows up ---------
idle_headless "$HEADLESS"

launch_sunshine exec
