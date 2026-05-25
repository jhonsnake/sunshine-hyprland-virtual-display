# Sunshine + Hyprland — Remote Desktop con Display Virtual

Configuración para acceso remoto en **Hyprland (Wayland)** usando [Sunshine](https://github.com/LizardByte/Sunshine) como servidor y [Moonlight](https://moonlight-stream.org/) / **Artemis** como cliente.

Replica el comportamiento de **Apollo** en Linux: crea un display virtual headless que se convierte en la sesión remota, separado de tu monitor físico.

---

## Cuándo usar esto

| Situación | ¿Funciona? |
|---|---|
| Hyprland como compositor (Wayland) | ✅ |
| GPU NVIDIA con driver propietario | ✅ (encoding nvenc — H.264/HEVC/AV1) |
| GPU AMD/Intel | ✅ (cambia `encoder=nvenc` por `encoder=vaapi`) |
| Quieres que las ventanas aparezcan en el cliente, no en el monitor físico | ✅ |
| Quieres acceso remoto simultáneo sin afectar tu sesión física | ✅ |
| X11 / otros compositors | ❌ (solo wlroots/Hyprland) |

---

## Cómo funciona

```
┌─────────────────────────────────────────────────────┐
│  Hyprland                                           │
│                                                     │
│  DP-1 (monitor físico)    HEADLESS-N (virtual)      │
│  ┌─────────────────┐      ┌─────────────────┐       │
│  │  idle / vacío   │      │  tus workspaces │ ◄─── Sunshine captura esto
│  └─────────────────┘      └─────────────────┘       │
└─────────────────────────────────────────────────────┘
         │
         ▼ stream (nvenc/vaapi)
  Moonlight / Artemis (Android, iOS, Windows, TV)
```

- Al **conectar**: los workspaces migran de DP-1 → HEADLESS automáticamente
- Al **desconectar**: regresan a DP-1

---

## Requisitos

- Hyprland (cualquier versión reciente)
- `python3` (para detectar el nombre dinámico del headless)
- `paru` o `yay` (para instalar desde AUR)
- GPU NVIDIA o AMD/Intel con soporte de encoding por hardware

---

## Instalación

```bash
git clone https://github.com/jhonsnake/sunshine-hyprland
cd sunshine-hyprland
bash scripts/install.sh
```

El script:
1. Instala `sunshine-bin` desde AUR
2. Copia los scripts a `~/.local/bin/`
3. Copia `sunshine.conf` a `~/.config/sunshine/`
4. Abre los puertos necesarios en UFW (si está activo)
5. Agrega `exec-once` al config de Hyprland

---

## Configuración manual (sin install.sh)

### 1. Copiar scripts

```bash
cp scripts/sunshine-start.sh ~/.local/bin/
cp scripts/sunshine-connect.sh ~/.local/bin/
cp scripts/sunshine-disconnect.sh ~/.local/bin/
chmod +x ~/.local/bin/sunshine-*.sh
```

### 2. Copiar config de Sunshine

```bash
mkdir -p ~/.config/sunshine
cp .config/sunshine/sunshine.conf ~/.config/sunshine/
```

> Si usas AMD/Intel cambia `encoder=nvenc` por `encoder=vaapi`

### 3. Autostart en Hyprland

Agrega a `~/.config/hypr/hyprland.conf` o `userprefs.conf`:

```ini
exec-once = ~/.local/bin/sunshine-start.sh
```

### 4. Abrir puertos (si usas UFW)

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

## Primer uso

1. Inicia sesión en Hyprland — Sunshine arranca automáticamente con el display virtual
2. Abre **`https://localhost:47990`** en tu navegador y crea usuario + contraseña
3. En **Moonlight** o **Artemis** agrega tu IP local como host nuevo
4. Al conectar por primera vez aparece un PIN de 4 dígitos — ingrésalo en la pestaña **Pin** del panel web
5. Listo — tus workspaces aparecen en el cliente remoto

---

## Estructura de archivos

```
sunshine-hyprland/
├── scripts/
│   ├── install.sh            # Instalador automático
│   ├── sunshine-start.sh     # Crea el display virtual y lanza Sunshine
│   ├── sunshine-connect.sh   # Se ejecuta al conectar un cliente (mueve workspaces)
│   └── sunshine-disconnect.sh # Se ejecuta al desconectar (regresa workspaces)
└── .config/
    └── sunshine/
        └── sunshine.conf     # Config de Sunshine (capture, encoder, prep_cmd)
```

---

## Resolución del display virtual

Por defecto `1920x1080@60`. Para cambiarla edita en `sunshine-start.sh`:

```bash
hyprctl keyword monitor "$HEADLESS_NAME,1920x1080@60,9999x0,1"
#                                       ^^^^^^^^^^^^ cambia esto
```

---

## Troubleshooting

**El cliente ve el escritorio vacío (sin ventanas)**
El script de connect no corrió. Verifica que `global_prep_cmd` está en `sunshine.conf` y que los scripts tienen permiso de ejecución.

**Sunshine captura DP-1 en lugar del headless**
El nombre del headless cambió. Reinicia Sunshine con `pkill sunshine && ~/.local/bin/sunshine-start.sh`.

**No conecta desde la red local**
Verifica firewall con `sudo ufw status | grep -i sunshine`. Si no aparece nada ejecuta el paso 4 de configuración manual.

**AMD/Intel: no hay imagen o falla el encoder**
Cambia `encoder=nvenc` por `encoder=vaapi` en `~/.config/sunshine/sunshine.conf`.
