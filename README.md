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
| Notifications | mako |
| Wallpaper | swww |
| Screenshots | grim + slurp |
| GTK theming | nwg-look, adwaita-icon-theme |
| Qt theming | qt5ct, qt6ct, kvantum |
| Fonts | Noto, JetBrains Mono Nerd, Font Awesome |
| Utilities | brightnessctl, wlr-randr, wl-clipboard, cliphist |
| Network | NetworkManager, nm-applet |
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

The script is interactive only for GPU driver selection — everything else runs unattended.

## GPU drivers

The script detects your GPU vendor via `lspci` and pre-selects the matching option:

```
1) NVIDIA  open-dkms  (Turing / RTX 2000+ required)
2) AMD     mesa + vulkan-radeon
3) Intel   mesa + vulkan-intel + intel-media-driver
4) Skip
```

NVIDIA additionally configures Early KMS in `mkinitcpio`, injects `nvidia-drm.modeset=1` into your bootloader (systemd-boot or GRUB), and writes a Wayland environment file.

## What gets configured

- **greetd** on VT1 with tuigreet, launching `niri-session` after login
- **`~/.config/niri/config.kdl`** — a ready-to-use skeleton with keybinds, window rules, daemon autostart, and cursor settings
- **`~/.config/environment.d/theming.conf`** — Qt Wayland backend, qt6ct platform theme, and cursor size/theme
- **`~/.config/environment.d/nvidia-wayland.conf`** — NVIDIA-specific Wayland variables (NVIDIA only)

## Default keybinds

| Keys | Action |
|---|---|
| `Super + Return` | Open kitty terminal |
| `Super + D` | Toggle Noctalia launcher |
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
   - Replace `eDP-1` with your display name (find it with `niri msg outputs`)
2. Run `nwg-look` to configure the GTK theme, icons, and cursor
3. Run `qt6ct` → Style → **Kvantum**, then `kvantummanager` to pick a Qt theme
4. Configure Noctalia: [docs.noctalia.dev](https://docs.noctalia.dev/)
5. Reboot — greetd will handle login from here

## References

- [Niri wiki](https://github.com/YaLTeR/niri/wiki)
- [Noctalia documentation](https://docs.noctalia.dev/)
- [ArchWiki — Niri](https://wiki.archlinux.org/title/Niri)
- [ArchWiki — NVIDIA](https://wiki.archlinux.org/title/NVIDIA)
