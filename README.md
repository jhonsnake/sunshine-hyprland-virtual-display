# Sunshine + Hyprland — Remote Desktop with Virtual Display

Remote access setup for **Hyprland (Wayland)** using [Sunshine](https://github.com/LizardByte/Sunshine) as the server and [Moonlight](https://moonlight-stream.org/) / **Artemis** as the client.

Replicates **Apollo**-style virtual display behavior on Linux: a headless virtual monitor becomes the remote session, completely separate from your physical display.

The virtual monitor is created **on-demand** when a client connects and **torn down on disconnect**, so it never sits around receiving local workspaces while no remote session is active.

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
| No phantom monitor stealing local workspaces between sessions | ✅ (on-demand mode) |
| X11 / other compositors | ❌ (wlroots/Hyprland only) |

---

## How it works

**Idle (no remote client):** only your physical monitor exists.

```
┌───────────────────────────────────────────────────────┐
│  Hyprland                                             │
│                                                       │
│  DP-1 (physical monitor)                              │
│  ┌──────────────────┐                                 │
│  │  your workspaces │                                 │
│  └──────────────────┘                                 │
│                                                       │
│  Sunshine: running, waiting for a client              │
└───────────────────────────────────────────────────────┘
```

**Connected:** Sunshine's `global_prep_cmd` fires `sunshine-connect.sh`, which creates the headless monitor, migrates your workspaces to it, and turns DP-1 off.

```
┌───────────────────────────────────────────────────────┐
│  Hyprland                                             │
│                                                       │
│  DP-1 (off / DPMS)         HEADLESS-N (virtual)       │
│  ┌──────────────────┐      ┌──────────────────┐       │
│  │  blank           │      │  your workspaces │ ◄──── Sunshine captures
│  └──────────────────┘      └──────────────────┘       │
└───────────────────────────────────────────────────────┘
          │
          ▼ stream (nvenc/vaapi)
   Moonlight / Artemis (Android, iOS, Windows, TV)
```

**Disconnected:** `sunshine-disconnect.sh` migrates workspaces back to DP-1, turns it back on, and removes the headless monitor.

---

## Requirements

- Hyprland (any recent version) — distro-agnostic
- `python3` (used to detect the dynamic headless monitor name)
- Sunshine package available for your distro
- NVIDIA, AMD, or Intel GPU with hardware encoding support
- *Optional:* `hyprlock` / `hypridle` — handled automatically if installed

> The `install.sh` script assumes an Arch-based distro (uses `paru` or `yay` to install `sunshine-bin` from AUR). On Debian/Ubuntu/Fedora, install Sunshine manually from [LizardByte's releases](https://github.com/LizardByte/Sunshine/releases) and follow the **Manual setup** section below.

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

1. Log into Hyprland — Sunshine starts automatically (no virtual display yet)
2. Open **`https://localhost:47990`** in your browser and create a username + password
3. In **Moonlight** or **Artemis** add your local IP as a new host
4. On first connect a 4-digit PIN appears — enter it in the **Pin** tab of the web panel
5. Done — the headless monitor materializes, your workspaces move to it, and the physical display turns off

---

## File structure

```
sunshine-hyprland-virtual-display/
├── scripts/
│   ├── install.sh             # Automatic installer
│   ├── sunshine-start.sh      # Hyprland exec-once: just launches Sunshine
│   ├── sunshine-connect.sh    # On client connect: creates HEADLESS, migrates workspaces, turns off DP-1
│   └── sunshine-disconnect.sh # On client disconnect: restores workspaces, turns on DP-1, removes HEADLESS
└── .config/
    └── sunshine/
        └── sunshine.conf      # Sunshine config (capture, encoder, global_prep_cmd)
```

---

## Virtual display resolution

Default is `1920x1080@60`. To change it, edit `sunshine-connect.sh`:

```bash
hyprctl keyword monitor "$HEADLESS,1920x1080@60,9999x0,1"
#                                  ^^^^^^^^^^^^ change this
```

---

## Persistent-headless mode (alternative)

If your Sunshine version does **not** re-read `output_name` between streams and the SIGHUP fallback in `sunshine-connect.sh` doesn't work for you, the stream will land on whatever monitor was named in `sunshine.conf` at Sunshine startup — typically DP-1 instead of the freshly-created HEADLESS-N.

In that case revert to the older "create at boot, keep forever" model:

1. In `sunshine-start.sh`, restore the headless-creation block from the [pre-on-demand version](https://github.com/jhonsnake/sunshine-hyprland-virtual-display/blob/c08a289/scripts/sunshine-start.sh).
2. Remove the create/remove blocks (sections 3 and 4) from `sunshine-connect.sh` / `sunshine-disconnect.sh`.
3. To prevent the persistent headless from receiving local workspaces, pin your normal workspaces to your physical monitor in Hyprland config:
   ```ini
   workspace = 1, monitor:DP-1, default:true
   workspace = 2, monitor:DP-1
   # ... up to your highest commonly-used workspace
   ```

---

## Troubleshooting

**Client sees an empty desktop (no windows)**
The connect script didn't run, or workspaces didn't migrate. Check `~/.local/share/sunshine-headless.log` for errors and confirm `global_prep_cmd` is set in `sunshine.conf`.

**Stream lands on the physical monitor instead of the virtual one**
Sunshine didn't re-read `output_name` after `sunshine-connect.sh` updated it. Try restarting Sunshine: `pkill sunshine` (the Hyprland `exec-once` will not relaunch it — start it manually with `~/.local/bin/sunshine-start.sh &` or log out and back in). If this happens consistently, switch to **persistent-headless mode** above.

**Physical monitor stays off after disconnecting**
Run manually: `hyprctl dispatch dpms on DP-1`

**Cannot connect from the local network**
Check firewall with `sudo ufw status | grep -i sunshine`. If nothing shows, run step 4 of the manual setup.

**AMD/Intel: no image or encoder failure**
Change `encoder=nvenc` to `encoder=vaapi` in `~/.config/sunshine/sunshine.conf`.

**`hyprlock` or `hypridle` not installed**
Harmless — the `pkill` calls in the connect/disconnect scripts are no-ops if those processes don't exist.
