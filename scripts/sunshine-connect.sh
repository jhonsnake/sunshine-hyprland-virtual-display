#!/bin/bash
# Runs when a Moonlight/Artemis client connects (Sunshine global_prep_cmd "do").
#
# Responsibilities (in order):
#   1. Drop any active hyprlock via loginctl (NOT pkill — see history note).
#   2. Pause hypridle so the session won't lock/dim/suspend during remote use.
#   3. Resize HEADLESS to the client's resolution and refresh rate (Apollo-style).
#   4. Migrate user workspaces from the physical monitor onto HEADLESS.
#   5. Turn off the physical monitor (DPMS off).
#
# The HEADLESS monitor is normally created once per session by
# sunshine-start.sh, but if it's gone at connect time (post-S3 resume edge
# case) this script self-heals: recreates HEADLESS, rewrites sunshine.conf
# output_name, and restarts sunshine.

. "$HOME/.local/bin/sunshine-common.sh"

# --- 1. unlock --------------------------------------------------------------
# Use the session-lock protocol path. SIGKILLing hyprlock would orphan
# Hyprland's ext-session-lock and strand the session on the recovery screen.
loginctl unlock-session 2>/dev/null

# --- 2. pause hypridle (SIGSTOP preserves state for SIGCONT in disconnect) --
pkill -STOP -x hypridle 2>/dev/null

# --- 3. find the persistent HEADLESS ----------------------------------------
HEADLESS=$(headless_name)

# Self-heal: if HEADLESS is missing (e.g. Hyprland tore it down across S3
# resume), recreate it AND restart sunshine so it re-reads output_name.
# The current sunshine process spawned us, so the restart runs detached.
# The client briefly sees a disconnect, then can reconnect cleanly.
if [ -z "$HEADLESS" ]; then
    log "WARNING: no HEADLESS on connect, self-healing"
    HEADLESS=$(create_headless)
    if [ -z "$HEADLESS" ]; then
        log "ERROR: self-heal failed, could not create HEADLESS"
        exit 0
    fi
    log "self-heal: recreated $HEADLESS, scheduling sunshine restart"
    launch_sunshine
    exit 0
fi

# Defensive dpms-on for HEADLESS — covers post-S3 resume where the virtual
# output came back in dpms-off state.
set_dpms on "$HEADLESS"

# --- 4. match the client's resolution ----------------------------------------
# Sunshine exports the client's requested mode to prep commands. Resizing the
# existing HEADLESS keeps its name, so Sunshine's cached output_name stays valid.
if [ "$MATCH_CLIENT_RESOLUTION" = true ] && [ -n "$SUNSHINE_CLIENT_WIDTH" ] && [ -n "$SUNSHINE_CLIENT_HEIGHT" ]; then
    MODE="${SUNSHINE_CLIENT_WIDTH}x${SUNSHINE_CLIENT_HEIGHT}@${SUNSHINE_CLIENT_FPS:-60}"
    SCALE=$(scale_for_height "$SUNSHINE_CLIENT_HEIGHT")
    set_monitor "$HEADLESS" "$MODE" "$HEADLESS_POSITION" "$SCALE"
    printf 'CLIENT_MODE=%s\nCLIENT_SCALE=%s\n' "$MODE" "$SCALE" >> "$STATE_FILE"
    log "HEADLESS set to $MODE scale $SCALE for client '${SUNSHINE_CLIENT_NAME:-unknown}'"
    sleep 0.3
fi

# --- 5. migrate workspaces ---------------------------------------------------
# Re-pin workspaces 1-10 to HEADLESS BEFORE moving them. Without this re-pin,
# the static rule from sunshine-start.sh yanks each workspace back to the
# physical monitor the instant the remote user dispatches `workspace N`,
# leaving the cursor on the (DPMS-off) physical monitor while Sunshine still
# captures HEADLESS — symptom: windows visible, mouse stuck.
pin_workspaces "$HEADLESS"
move_workspaces "$PHYSICAL_MONITOR" "$HEADLESS"
focus_monitor "$HEADLESS"

# Absolute input (Moonlight on macOS/iPad, touch on phones) is mapped over the whole
# layout unless pinned — the cursor would land on the physical monitor.
bind_input_devices "$HEADLESS"

# --- 6. turn off the physical monitor ---------------------------------------
# ...and keep remote mouse/keyboard input from waking it up again.
suspend_dpms_wake
set_dpms off "$PHYSICAL_MONITOR"

touch "$STREAMING_FLAG"
log "Client connected, workspaces migrated to $HEADLESS"
