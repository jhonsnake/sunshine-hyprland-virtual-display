#!/bin/bash
# Launches Sunshine when the Hyprland session starts.
#
# The virtual HEADLESS monitor is created on-demand from sunshine-connect.sh
# (Sunshine global_prep_cmd "do") when a Moonlight client connects, and
# removed from sunshine-disconnect.sh ("undo") when the client disconnects.
# This avoids HEADLESS-N existing persistently and being assigned local
# workspaces while no remote session is active.

exec sunshine
