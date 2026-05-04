# archnirinoc

A bootstrap script that sets up a complete [Niri](https://github.com/YaLTeR/niri) + [Noctalia](https://noctalia.dev/) desktop on a minimal Arch Linux installation, run from a TTY prompt.

## What it installs

| Category | Packages |
|---|---|
| AUR helper | paru |
| GPU drivers | NVIDIA (open-dkms), AMD, or Intel — detected automatically |
| Audio | PipeWire, WirePlumber, pavucontrol |
| Compositor | niri, xwayland-satellite |
| Shell | noctalia-shell (+ noctalia-qs) |
| Display manager | greetd + tuigreet |
| Terminal | kitty |
| File manager | nautilus + gvfs + gvfs-mtp |
| Notifications | mako |
| Wallpaper | swww |
| Screen lock | swaylock |
| Idle management | swayidle |
| Night light | wlsunset (optional) |
| Screenshots | grim + slurp |
| GTK theming | nwg-look, adwaita-icon-theme |
| Qt theming | qt5ct, qt6ct, kvantum |
| Power management | power-profiles-daemon |
| Flatpak | flatpak + Flathub remote |
| Fonts | Noto, JetBrains Mono Nerd, Font Awesome |
| Utilities | brightnessctl, wlr-randr, wl-clipboard, cliphist |
| Network | NetworkManager, network-manager-applet |
| Bluetooth | bluez, bluez-utils, blueman |

## Requirements

- A minimal Arch Linux installation (e.g. via `archinstall`)
- A regular user account with sudo privileges (wheel group)
- Internet connection
- NVIDIA: Turing architecture (RTX 2000 series) or newer for open kernel modules

## Usage

```bash
git clone https://github.com/lmaule/archnirinoc.git
cd archnirinoc
bash install.sh
```

The script asks a few questions upfront, then runs the rest of the install unattended.

## Interactive questions

| Question | Default | Notes |
|---|---|---|
| Mirror country code | skip | e.g. `GB`, `US`, `DE` — used by reflector to rank mirrors by speed |
| GPU driver | auto-detected | Choose NVIDIA / AMD / Intel or skip |
| Screen lock timeout | 5 min | Minutes of idle before swaylock activates |
| Display off timeout | 10 min | Minutes of idle before monitors power off |
| Night light latitude | skip | Leave blank to skip wlsunset entirely |
| Night light longitude | — | Only asked if latitude is provided |

## GPU drivers

The script detects your GPU vendor via `lspci` and pre-selects the matching option:

```
1) NVIDIA  open-dkms (Turing / RTX 2000+ required)
2) AMD     mesa + vulkan-radeon
3) Intel   mesa + vulkan-intel + intel-media-driver
4) Skip
```

NVIDIA additionally configures Early KMS in `mkinitcpio`, injects `nvidia-drm.modeset=1` into your bootloader (systemd-boot or GRUB), and writes a Wayland environment file.

## What gets configured

- **`/etc/pacman.conf`** — `Color` and `ParallelDownloads = 5` enabled
- **greetd** on VT1 with tuigreet, launching `niri-session` after login
- **`~/.config/niri/config.kdl`** — ready-to-use skeleton with keybinds, window rules, and all daemons wired up in `spawn-at-startup` (including swayidle with your chosen timeouts, cliphist, and optionally wlsunset)
- **`~/.config/environment.d/theming.conf`** — Qt Wayland backend, qt6ct platform theme, cursor size/theme
- **`~/.config/environment.d/nvidia-wayland.conf`** — NVIDIA-specific Wayland variables (NVIDIA only)

## Default keybinds

| Keys | Action |
|---|---|
| `Super + Return` | Open kitty terminal |
| `Super + D` | Toggle Noctalia launcher |
| `Super + E` | Open file manager (nautilus) |
| `Super + Shift + L` | Lock screen (swaylock) |
| `Super + Q` | Close window |
| `Super + H/L` | Focus column left/right |
| `Super + J/K` | Focus window up/down |
| `Super + Shift + H/L` | Move column left/right |
| `Super + 1–9` | Switch workspace |
| `Super + Shift + 1–9` | Move window to workspace |
| `Super + F` | Maximize column |
| `Super + Shift + F` | Fullscreen |
| `Super + R` | Cycle preset column widths |
| `Print` | Screenshot (region) |
| `Super + Shift + E` | Quit Niri |

## Post-install

1. Edit `~/.config/niri/config.kdl`:
   - Set your keyboard layout inside `xkb { layout "..." }`
   - Replace `eDP-1` with your display name — find it with `niri msg outputs`
2. Run `nwg-look` to configure the GTK theme, icons, and cursor
3. Run `qt6ct` → Style → **Kvantum**, then `kvantummanager` to pick a Qt theme
4. Configure Noctalia: [docs.noctalia.dev](https://docs.noctalia.dev/)
5. Reboot — greetd will handle login from here

## References

- [Niri wiki](https://github.com/YaLTeR/niri/wiki)
- [Noctalia documentation](https://docs.noctalia.dev/)
- [ArchWiki — Niri](https://wiki.archlinux.org/title/Niri)
- [ArchWiki — NVIDIA](https://wiki.archlinux.org/title/NVIDIA)
