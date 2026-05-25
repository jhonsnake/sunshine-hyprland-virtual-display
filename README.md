# Sunshine + Hyprland — Remote Desktop with Virtual Display

Remote access setup for **Hyprland (Wayland)** using [Sunshine](https://github.com/LizardByte/Sunshine) as the server and [Moonlight](https://moonlight-stream.org/) / **Artemis** as the client.

Replicates **Apollo**-style virtual display behavior on Linux: creates a headless virtual monitor that becomes the remote session, completely separate from your physical display.

---

## When to use this

| Scenario | Works? |
|---|---|
| Hyprland compositor (Wayland) | ✅ |
| NVIDIA GPU with proprietary driver | ✅ (nvenc — H.264/HEVC/AV1) |
| AMD/Intel GPU | ✅ (change `encoder=nvenc` to `encoder=vaapi`) |
| Windows open on the remote client, not the physical monitor | ✅ |
| Physical monitor turns off during remote session | ✅ |
| Simultaneous remote access without disturbing your physical session | ✅ |
| X11 / other compositors | ❌ (wlroots/Hyprland only) |

---

## How it works

```
┌───────────────────────────────────────────────────────┐
│  Hyprland                                             │
│                                                       │
│  DP-1 (physical monitor)    HEADLESS-N (virtual)      │
│  ┌──────────────────┐       ┌──────────────────┐      │
│  │  off / idle      │       │  your workspaces │ ◄─── Sunshine captures this
│  └──────────────────┘       └──────────────────┘      │
└───────────────────────────────────────────────────────┘
          │
          ▼ stream (nvenc/vaapi)
   Moonlight / Artemis (Android, iOS, Windows, TV)
```

- On **connect**: workspaces migrate DP-1 → HEADLESS, physical monitor turns off
- On **disconnect**: workspaces return to DP-1, physical monitor turns back on

---

## Requirements

- Hyprland (any recent version)
- `python3` (used to detect the dynamic headless monitor name)
- `paru` or `yay` (to install from AUR)
- NVIDIA, AMD, or Intel GPU with hardware encoding support

---

## Installation

```bash
git clone https://github.com/jhonsnake/sunshine-hyprland-virtual-display
cd sunshine-hyprland-virtual-display
bash scripts/install.sh
```

The script will:
1. Install `sunshine-bin` from AUR
2. Copy scripts to `~/.local/bin/`
3. Copy `sunshine.conf` to `~/.config/sunshine/`
4. Open required ports in UFW (if active)
5. Add `exec-once` to your Hyprland config

---

## Manual setup (without install.sh)

### 1. Copy scripts

```bash
cp scripts/sunshine-start.sh ~/.local/bin/
cp scripts/sunshine-connect.sh ~/.local/bin/
cp scripts/sunshine-disconnect.sh ~/.local/bin/
chmod +x ~/.local/bin/sunshine-*.sh
```

### 2. Copy Sunshine config

```bash
mkdir -p ~/.config/sunshine
cp .config/sunshine/sunshine.conf ~/.config/sunshine/
```

> For AMD/Intel change `encoder=nvenc` to `encoder=vaapi`

### 3. Autostart in Hyprland

Add to `~/.config/hypr/hyprland.conf` or `userprefs.conf`:

```ini
exec-once = ~/.local/bin/sunshine-start.sh
```

### 4. Open firewall ports (if using UFW)

```bash
sudo ufw allow 47984/tcp comment "Sunshine HTTPS"
sudo ufw allow 47989/tcp comment "Sunshine HTTP"
sudo ufw allow 47990/tcp comment "Sunshine Web UI"
sudo ufw allow 48010/tcp comment "Sunshine RTSP"
sudo ufw allow 47998/udp comment "Sunshine Video"
sudo ufw allow 47999/udp comment "Sunshine Control"
sudo ufw allow 48000/udp comment "Sunshine Audio"
sudo ufw allow 48002/udp comment "Sunshine Mic"
```

---

## First use

1. Log into Hyprland — Sunshine starts automatically with the virtual display
2. Open **`https://localhost:47990`** in your browser and create a username + password
3. In **Moonlight** or **Artemis** add your local IP as a new host
4. On first connect a 4-digit PIN appears — enter it in the **Pin** tab of the web panel
5. Done — your workspaces appear on the remote client

---

## File structure

```
sunshine-hyprland-virtual-display/
├── scripts/
│   ├── install.sh             # Automatic installer
│   ├── sunshine-start.sh      # Creates virtual display and launches Sunshine
│   ├── sunshine-connect.sh    # Runs on client connect (moves workspaces, turns off monitor)
│   └── sunshine-disconnect.sh # Runs on client disconnect (restores workspaces, turns on monitor)
└── .config/
    └── sunshine/
        └── sunshine.conf      # Sunshine config (capture, encoder, prep_cmd)
```

---

## Virtual display resolution

Default is `1920x1080@60`. To change it, edit `sunshine-start.sh`:

```bash
hyprctl keyword monitor "$HEADLESS_NAME,1920x1080@60,9999x0,1"
#                                       ^^^^^^^^^^^^ change this
```

---

## Troubleshooting

**Client sees an empty desktop (no windows)**
The connect script did not run. Check that `global_prep_cmd` is set in `sunshine.conf` and that the scripts have execute permission.

**Sunshine captures DP-1 instead of the headless display**
The headless monitor name changed. Restart Sunshine: `pkill sunshine && ~/.local/bin/sunshine-start.sh`.

**Cannot connect from the local network**
Check firewall with `sudo ufw status | grep -i sunshine`. If nothing shows, run step 4 of the manual setup.

**AMD/Intel: no image or encoder failure**
Change `encoder=nvenc` to `encoder=vaapi` in `~/.config/sunshine/sunshine.conf`.

**Physical monitor stays off after disconnecting**
Run manually: `hyprctl dispatch dpms on DP-1`
