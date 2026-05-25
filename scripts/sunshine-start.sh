#!/bin/bash
# Crea display virtual headless y lanza Sunshine

LOG="$HOME/.local/share/sunshine-headless.log"
CONF="$HOME/.config/sunshine/sunshine.conf"

# Remover cualquier headless previo
while read -r name; do
    hyprctl output remove "$name" >> "$LOG" 2>&1 && sleep 0.3
done < <(hyprctl monitors -j 2>/dev/null | python3 -c \
    "import sys,json; [print(m['name']) for m in json.load(sys.stdin) if 'HEADLESS' in m['name']]")

# Crear headless fresco
hyprctl output create headless >> "$LOG" 2>&1
sleep 0.8

# Detectar nombre real asignado por Hyprland
HEADLESS_NAME=$(hyprctl monitors -j 2>/dev/null | python3 -c \
    "import sys,json; ms=[m['name'] for m in json.load(sys.stdin) if 'HEADLESS' in m['name']]; print(ms[0] if ms else '')")

if [ -z "$HEADLESS_NAME" ]; then
    echo "ERROR: no se pudo crear monitor headless" >> "$LOG"
    exec sunshine
fi

echo "Headless creado: $HEADLESS_NAME" >> "$LOG"

# Aplicar resolución 1920x1080@60, sin scale extra, fuera de pantalla
hyprctl keyword monitor "$HEADLESS_NAME,1920x1080@60,9999x0,1" >> "$LOG" 2>&1
sleep 0.3

# Actualizar output_name en sunshine.conf con el nombre real
sed -i "s/^output_name *=.*/output_name = $HEADLESS_NAME/" "$CONF"

exec sunshine
