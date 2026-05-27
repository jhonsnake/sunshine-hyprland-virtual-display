# Sunshine + Hyprland — Remote Desktop with Virtual Display

Remote access setup for **Hyprland (Wayland)** using [Sunshine](https://github.com/LizardByte/Sunshine) as the server and [Moonlight](https://moonlight-stream.org/) / **Artemis** as the client.

Replicates **Apollo**-style virtual display behavior on Linux: a persistent headless monitor lives alongside your physical display and becomes the remote session when a client connects. Local workspaces are pinned to the physical monitor so they don't accidentally land on the invisible headless.

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
| Local windows never accidentally open on the invisible virtual display | ✅ (workspace pinning) |
| X11 / other compositors | ❌ (wlroots/Hyprland only) |

---

## How it works

**At session start:** `sunshine-start.sh` (Hyprland `exec-once`) creates a persistent headless monitor, pins workspaces 1-10 to your physical display, dedicates workspace 11 to the headless, writes the headless's name into `sunshine.conf`, and then exec's Sunshine. The monitor lives for the whole Hyprland session.

```
┌──────────────────────────────────────────────────────────┐
│  Hyprland                                                │
│                                                          │
│  DP-1 (physical monitor)        HEADLESS-N (virtual)     │
│  ┌──────────────────┐           ┌──────────────────┐     │
│  │  workspaces 1-10 │           │  workspace 11    │     │
│  │  your windows    │           │  (empty, ready)  │     │
│  └──────────────────┘           └──────────────────┘     │
│                                                          │
│  Sunshine: capturing HEADLESS-N (cached at startup)      │
└──────────────────────────────────────────────────────────┘
```

**Client connects:** `sunshine-connect.sh` migrates workspaces 1-10 from DP-1 onto HEADLESS-N, turns off the physical monitor, and pauses hypridle.

```
┌──────────────────────────────────────────────────────────┐
│  Hyprland                                                │
│                                                          │
│  DP-1 (off / DPMS)              HEADLESS-N (virtual)     │
│  ┌──────────────────┐           ┌──────────────────┐     │
│  │  blank           │           │  workspaces 1-10 │ ◄── Sunshine captures
│  │                  │           │  your windows    │     │
│  └──────────────────┘           └──────────────────┘     │
└──────────────────────────────────────────────────────────┘
          │
          ▼ stream (nvenc/vaapi)
   Moonlight / Artemis (Android, iOS, Windows, TV)
```

**Client disconnects:** `sunshine-disconnect.sh` migrates workspaces back to DP-1, turns it on, resumes hypridle. The headless monitor stays put — ready for the next connection without requiring Sunshine to re-read its config.

### Why persistent headless instead of on-demand

Sunshine's `wlr-capture` backend reads `output_name` once at process startup and **caches it for the process lifetime**. SIGHUP and the HTTP API do not refresh the cached value. So if the headless monitor is created on-demand by the connect hook, Sunshine still looks for the monitor name it loaded at startup (which no longer exists) and silently falls back to capturing the first available output — typically your physical display, producing a black/wrong frame on the remote client.

The persistent headless avoids that race entirely: the monitor exists and its name is in `sunshine.conf` *before* Sunshine starts, so Sunshine's cached value is always correct.

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

1. Log into Hyprland — the headless monitor is created and Sunshine starts automatically
2. Open **`https://localhost:47990`** in your browser and create a username + password
3. In **Moonlight** or **Artemis** add your local IP as a new host
4. On first connect a 4-digit PIN appears — enter it in the **Pin** tab of the web panel
5. Done — your workspaces move from DP-1 to the headless monitor and stream to the remote client

---

## File structure

```
sunshine-hyprland-virtual-display/
├── scripts/
│   ├── install.sh             # Automatic installer
│   ├── sunshine-start.sh      # Creates HEADLESS, pins workspaces, writes output_name, launches Sunshine
│   ├── sunshine-connect.sh    # On connect: migrates ws 1-10 -> HEADLESS, turns off DP-1, pauses hypridle
│   └── sunshine-disconnect.sh # On disconnect: restores ws, turns on DP-1, resumes hypridle
└── .config/
    └── sunshine/
        └── sunshine.conf      # Sunshine config (capture, encoder, global_prep_cmd, output_name placeholder)
```

---

## Virtual display resolution

Default is `1920x1080@60`. To change it, edit `sunshine-start.sh`:

```bash
hyprctl keyword monitor "$HEADLESS,1920x1080@60,9999x0,1"
#                                  ^^^^^^^^^^^^ change this
```

---

## Workspace layout

`sunshine-start.sh` pins:
- **Workspaces 1-10** → `DP-1` (your physical monitor)
- **Workspace 11** → `HEADLESS-N` (dedicated "remote" workspace, persistent)

If you use workspace numbers above 10 locally, edit the `for ws in 1 2 3 4 5 6 7 8 9 10;` loop in `sunshine-start.sh` to include them, and change `11` to your "remote" workspace number.

---

## Troubleshooting

**Client sees the physical monitor instead of the headless one (or a black frame)**
Sunshine cached the wrong `output_name`. This happens if Sunshine was already running when the headless was created. Fix: `pkill sunshine` then re-run `~/.local/bin/sunshine-start.sh &` (or log out and back in). Verify with: `grep output_name ~/.config/sunshine/sunshine.conf` matches the active HEADLESS in `hyprctl monitors`.

**Client sees an empty desktop (no windows)**
`sunshine-connect.sh` didn't migrate workspaces. Check `~/.local/share/sunshine-headless.log` for errors and confirm `global_prep_cmd` is set in `sunshine.conf`.

**Physical monitor stays off after disconnecting**
Run manually: `hyprctl dispatch dpms on DP-1`

**Cannot connect from the local network**
Check firewall with `sudo ufw status | grep -i sunshine`. If nothing shows, run step 4 of the manual setup.

**AMD/Intel: no image or encoder failure**
Change `encoder=nvenc` to `encoder=vaapi` in `~/.config/sunshine/sunshine.conf`.

**"Oopsie daisy, lockscreen app died" on the physical screen**
Something SIGKILL'd hyprlock while an `ext-session-lock` was active. To recover: switch to a TTY (`Ctrl+Alt+F3`), log in, and run:
```bash
hyprctl --instance 0 'keyword misc:allow_session_lock_restore 1'
killall -9 hyprlock
hyprctl --instance 0 'dispatch exec hyprlock'
```
To prevent it: never `pkill hyprlock` from a script; use `loginctl unlock-session` instead, and consider setting `misc { allow_session_lock_restore = true }` in your Hyprland config as a safety net.

**`hyprlock` or `hypridle` not installed**
Harmless — the `pkill` and `loginctl` calls are no-ops if those processes/sessions don't exist.
