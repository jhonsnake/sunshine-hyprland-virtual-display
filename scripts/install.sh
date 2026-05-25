#!/bin/bash
# Instala y configura Sunshine + virtual display para Hyprland

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Verificar requisitos
command -v hyprctl &>/dev/null || error "Este script requiere Hyprland"
command -v python3 &>/dev/null || error "Requiere python3"

# Instalar sunshine-bin si no está
if ! command -v sunshine &>/dev/null; then
    info "Instalando sunshine-bin..."
    if command -v paru &>/dev/null; then
        paru -S --noconfirm sunshine-bin
    elif command -v yay &>/dev/null; then
        yay -S --noconfirm sunshine-bin
    else
        error "Necesitas paru o yay para instalar sunshine-bin desde AUR"
    fi
fi

# Copiar scripts
info "Instalando scripts..."
mkdir -p ~/.local/bin
cp scripts/sunshine-start.sh scripts/sunshine-connect.sh scripts/sunshine-disconnect.sh ~/.local/bin/
chmod +x ~/.local/bin/sunshine-start.sh \
         ~/.local/bin/sunshine-connect.sh \
         ~/.local/bin/sunshine-disconnect.sh

# Copiar config de Sunshine (sin sobreescribir si ya existe con cambios del usuario)
if [ ! -f ~/.config/sunshine/sunshine.conf ]; then
    info "Copiando sunshine.conf..."
    mkdir -p ~/.config/sunshine
    cp .config/sunshine/sunshine.conf ~/.config/sunshine/sunshine.conf
else
    warn "~/.config/sunshine/sunshine.conf ya existe — revísalo manualmente con el ejemplo en .config/sunshine/sunshine.conf"
fi

# Abrir puertos en UFW si está activo
if systemctl is-active --quiet ufw; then
    info "Abriendo puertos Sunshine en UFW..."
    pkexec sh -c '
        ufw allow 47984/tcp comment "Sunshine HTTPS"
        ufw allow 47989/tcp comment "Sunshine HTTP"
        ufw allow 47990/tcp comment "Sunshine Web UI"
        ufw allow 48010/tcp comment "Sunshine RTSP"
        ufw allow 47998/udp comment "Sunshine Video"
        ufw allow 47999/udp comment "Sunshine Control"
        ufw allow 48000/udp comment "Sunshine Audio"
        ufw allow 48002/udp comment "Sunshine Mic"
    '
fi

# Agregar exec-once a Hyprland si no está
HYPR_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/userprefs.conf"
HYPR_MAIN="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.conf"
TARGET_CONF=""

if [ -f "$HYPR_CONF" ]; then
    TARGET_CONF="$HYPR_CONF"
elif [ -f "$HYPR_MAIN" ]; then
    TARGET_CONF="$HYPR_MAIN"
fi

if [ -n "$TARGET_CONF" ]; then
    if ! grep -q "sunshine-start.sh" "$TARGET_CONF"; then
        info "Agregando autostart en $TARGET_CONF..."
        echo "" >> "$TARGET_CONF"
        echo "# Sunshine remote desktop" >> "$TARGET_CONF"
        echo "exec-once = ~/.local/bin/sunshine-start.sh" >> "$TARGET_CONF"
    else
        warn "sunshine-start.sh ya está en $TARGET_CONF"
    fi
else
    warn "No se encontró hyprland.conf — agrega manualmente:"
    warn "  exec-once = ~/.local/bin/sunshine-start.sh"
fi

echo ""
info "Instalación completa."
echo ""
echo "  Próximos pasos:"
echo "  1. Reinicia Hyprland (o loguéate de nuevo)"
echo "  2. Abre https://localhost:47990 y crea usuario + contraseña"
echo "  3. En Moonlight/Artemis agrega tu IP y empareja con el PIN"
