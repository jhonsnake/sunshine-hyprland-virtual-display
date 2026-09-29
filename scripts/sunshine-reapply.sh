#!/bin/bash
# Re-applies the virtual display setup after `hyprctl reload`.
#
# Everything the other scripts set at runtime (HEADLESS mode/position, workspace
# pins, input device pinning, DPMS wake options) is dropped on reload, which
# leaves HEADLESS glued next to the physical monitor — the mouse can wander onto
# the invisible screen. Hook this with a plain `exec =` (runs on every reload),
# NOT `exec-once`.

. "$HOME/.local/bin/sunshine-common.sh"

HEADLESS=$(headless_name)
[ -z "$HEADLESS" ] && exit 0

# shellcheck source=/dev/null
[ -f "$STATE_FILE" ] && . "$STATE_FILE"

workspace_rule "$REMOTE_WORKSPACE" "$HEADLESS" true false

if [ -e "$STREAMING_FLAG" ]; then
    set_monitor "$HEADLESS" "${CLIENT_MODE:-$HEADLESS_DEFAULT_MODE}" "$HEADLESS_POSITION" "${CLIENT_SCALE:-1}"
    pin_workspaces "$HEADLESS"
    bind_input_devices "$HEADLESS"
    set_option misc:mouse_move_enables_dpms false
    set_option misc:key_press_enables_dpms false
    log "reload: re-applied streaming setup on $HEADLESS (${CLIENT_MODE:-default mode})"
else
    pin_workspaces "$PHYSICAL_MONITOR" true
    idle_headless "$HEADLESS"
    log "reload: re-applied idle setup on $HEADLESS"
fi
