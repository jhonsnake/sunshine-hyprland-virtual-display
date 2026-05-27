#!/bin/bash
# Installs and configures Sunshine + virtual display for Hyprland

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Check requirements
command -v hyprctl &>/dev/null || error "This script requires Hyprland"
command -v python3 &>/dev/null || error "python3 is required"

# Install sunshine-bin if missing
if ! command -v sunshine &>/dev/null; then
    info "Installing sunshine-bin..."
    if command -v paru &>/dev/null; then
        paru -S --noconfirm sunshine-bin
    elif command -v yay &>/dev/null; then
        yay -S --noconfirm sunshine-bin
    else
        error "paru or yay is required to install sunshine-bin from AUR"
    fi
fi

# Copy scripts
info "Installing scripts..."
mkdir -p ~/.local/bin
cp scripts/sunshine-start.sh \
   scripts/sunshine-connect.sh \
   scripts/sunshine-disconnect.sh \
   scripts/sunshine-after-sleep.sh \
   ~/.local/bin/
chmod +x ~/.local/bin/sunshine-start.sh \
         ~/.local/bin/sunshine-connect.sh \
         ~/.local/bin/sunshine-disconnect.sh \
         ~/.local/bin/sunshine-after-sleep.sh

# Copy Sunshine config (do not overwrite if the user already customized it)
if [ ! -f ~/.config/sunshine/sunshine.conf ]; then
    info "Copying sunshine.conf..."
    mkdir -p ~/.config/sunshine
    cp .config/sunshine/sunshine.conf ~/.config/sunshine/sunshine.conf
else
    warn "~/.config/sunshine/sunshine.conf already exists — review it manually against the example in .config/sunshine/sunshine.conf"
fi

# Open ports in UFW if active
if systemctl is-active --quiet ufw; then
    info "Opening Sunshine ports in UFW..."
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

# Add exec-once to Hyprland config if not present
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
        info "Adding autostart entry to $TARGET_CONF..."
        echo "" >> "$TARGET_CONF"
        echo "# Sunshine remote desktop" >> "$TARGET_CONF"
        echo "exec-once = ~/.local/bin/sunshine-start.sh" >> "$TARGET_CONF"
    else
        warn "sunshine-start.sh is already in $TARGET_CONF"
    fi
else
    warn "hyprland.conf not found — add this line manually:"
    warn "  exec-once = ~/.local/bin/sunshine-start.sh"
fi

# Wire after_sleep_cmd into hypridle if it's installed — fixes the
# black-screen-after-S3-resume case where the wlr virtual output comes back
# with a stale scanout buffer. Idempotent: skips if the line already exists.
HYPRIDLE_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hypridle.conf"
if command -v hypridle &>/dev/null && [ -f "$HYPRIDLE_CONF" ]; then
    if grep -qE '^\s*after_sleep_cmd\s*=' "$HYPRIDLE_CONF"; then
        warn "hypridle already has after_sleep_cmd — leaving alone (verify it points to sunshine-after-sleep.sh)"
    elif grep -qE '^\s*general\s*\{' "$HYPRIDLE_CONF"; then
        info "Adding after_sleep_cmd to $HYPRIDLE_CONF..."
        # Insert one line after the general { opening brace.
        sed -i '/^\s*general\s*{/a\    after_sleep_cmd = '"$HOME"'/.local/bin/sunshine-after-sleep.sh  # repaint HEADLESS after S3 resume' "$HYPRIDLE_CONF"
        # Reload hypridle if it's running so the change takes effect.
        if pgrep -x hypridle >/dev/null; then
            info "Restarting hypridle to apply config..."
            pkill -x hypridle
            sleep 0.3
            setsid nohup hypridle >/dev/null 2>&1 < /dev/null &
        fi
    else
        warn "$HYPRIDLE_CONF has no 'general {' block — add this manually inside one:"
        warn "  after_sleep_cmd = ~/.local/bin/sunshine-after-sleep.sh"
    fi
fi

echo ""
info "Installation complete."
echo ""
echo "  Next steps:"
echo "  1. Restart Hyprland (or log in again)"
echo "  2. Open https://localhost:47990 and create a username + password"
echo "  3. In Moonlight/Artemis add your IP and pair using the PIN"
