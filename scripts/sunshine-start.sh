#!/bin/bash
# Creates a headless virtual display and launches Sunshine

LOG="$HOME/.local/share/sunshine-headless.log"
CONF="$HOME/.config/sunshine/sunshine.conf"

# Remove any previous headless monitor
while read -r name; do
    hyprctl output remove "$name" >> "$LOG" 2>&1 && sleep 0.3
done < <(hyprctl monitors -j 2>/dev/null | python3 -c \
    "import sys,json; [print(m['name']) for m in json.load(sys.stdin) if 'HEADLESS' in m['name']]")

# Create a fresh headless monitor
hyprctl output create headless >> "$LOG" 2>&1
sleep 0.8

# Detect the real name assigned by Hyprland
HEADLESS_NAME=$(hyprctl monitors -j 2>/dev/null | python3 -c \
    "import sys,json; ms=[m['name'] for m in json.load(sys.stdin) if 'HEADLESS' in m['name']]; print(ms[0] if ms else '')")

if [ -z "$HEADLESS_NAME" ]; then
    echo "ERROR: could not create headless monitor" >> "$LOG"
    exec sunshine
fi

echo "Headless created: $HEADLESS_NAME" >> "$LOG"

# Apply 1920x1080@60 resolution, no extra scale, off-screen position
hyprctl keyword monitor "$HEADLESS_NAME,1920x1080@60,9999x0,1" >> "$LOG" 2>&1
sleep 0.3

# Update output_name in sunshine.conf with the real name
sed -i "s/^output_name *=.*/output_name = $HEADLESS_NAME/" "$CONF"

exec sunshine
