#!/usr/bin/env bash
# Install Niri + Noctalia on a minimal Arch Linux installation.
# Run as a regular user with sudo privileges from a TTY prompt.

set -euo pipefail

# ── Colors & logging ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { printf "${CYAN}==> ${NC}%s\n" "$*"; }
ok()    { printf "${GREEN}  ✓ ${NC}%s\n" "$*"; }
warn()  { printf "${YELLOW}  ! ${NC}%s\n" "$*"; }
die()   { printf "${RED}  ✗ ${NC}%s\n" "$*" >&2; exit 1; }
header(){ printf "\n${BOLD}━━━ %s ${NC}\n" "$*"; }

# ── Pre-flight checks ─────────────────────────────────────────────────────────
header "Pre-flight checks"

[[ $EUID -eq 0 ]] && die "Do not run this script as root. Run as a regular user with sudo privileges."

if ! sudo -v 2>/dev/null; then
    die "This script requires sudo. Make sure your user is in the wheel group and /etc/sudoers is configured."
fi

if ! ping -c1 -W5 archlinux.org &>/dev/null; then
    die "No internet connection detected. Check your network and try again."
fi

ok "Running as ${USER}, sudo available, internet reachable"

# Re-validate sudo every 60 s so it never times out during long AUR builds
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
_keepalive_pid=$!
trap "kill $_keepalive_pid 2>/dev/null" EXIT

# ── Configuration — all interactive prompts collected upfront ─────────────────
header "Configuration"
printf "  Answer a few questions — the rest of the install runs unattended.\n\n"

# Mirror country
printf "  ${BOLD}Mirror optimisation${NC}\n"
printf "  Enter your ISO country code to rank pacman mirrors by speed.\n"
printf "  Leave blank to skip (existing mirrorlist will be used).\n"
read -rp "  Country code (e.g. GB, US, DE) [skip]: " CFG_MIRROR_COUNTRY
printf "\n"

# GPU selection
printf "  ${BOLD}GPU drivers${NC}\n"
_detected_gpu="none"
if lspci 2>/dev/null | grep -Eiq "VGA|3D|Display"; then
    if lspci 2>/dev/null | grep -Eiq "NVIDIA"; then
        _detected_gpu="nvidia"
    elif lspci 2>/dev/null | grep -Eiq "AMD|ATI|Radeon"; then
        _detected_gpu="amd"
    elif lspci 2>/dev/null | grep -Eiq "Intel.*Graphics|Intel.*VGA"; then
        _detected_gpu="intel"
    fi
fi

case "$_detected_gpu" in
    nvidia) _gpu_default=1 ;;
    amd)    _gpu_default=2 ;;
    intel)  _gpu_default=3 ;;
    *)      _gpu_default=4 ;;
esac

[[ "$_detected_gpu" != "none" ]] \
    && printf "  Detected: ${CYAN}${_detected_gpu}${NC}\n" \
    || printf "  ${YELLOW}GPU vendor not auto-detected${NC}\n"

printf "  1) NVIDIA  open-dkms  (Turing / RTX 2000+ required)\n"
printf "  2) AMD     mesa + vulkan-radeon\n"
printf "  3) Intel   mesa + vulkan-intel + intel-media-driver\n"
printf "  4) Skip    (already installed or VM)\n"
read -rp "  Choice [${_gpu_default}]: " CFG_GPU_CHOICE
CFG_GPU_CHOICE="${CFG_GPU_CHOICE:-$_gpu_default}"
printf "\n"

# Screen lock / idle timeouts
printf "  ${BOLD}Screen lock & idle${NC}\n"
read -rp "  Minutes of idle before locking the screen [5]: " _lock_mins
read -rp "  Minutes of idle before turning off displays [10]: " _off_mins
CFG_LOCK_SECS=$(( ${_lock_mins:-5} * 60 ))
CFG_OFF_SECS=$(( ${_off_mins:-10} * 60 ))
printf "\n"

# Night light
printf "  ${BOLD}Night light (wlsunset)${NC}\n"
printf "  Reduces blue light after sunset. Enter your coordinates,\n"
printf "  or leave latitude blank to skip.\n"
read -rp "  Latitude  (e.g. 51.5 for London, 40.7 for New York) [skip]: " CFG_LAT
if [[ -n "$CFG_LAT" ]]; then
    read -rp "  Longitude (e.g. -0.1 for London, -74.0 for New York): " CFG_LON
else
    CFG_LON=""
fi
printf "\n"

ok "Configuration collected — starting unattended install"

# ── Pacman tweaks ─────────────────────────────────────────────────────────────
header "Pacman configuration"
sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
sudo sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
ok "Color and ParallelDownloads = 5 enabled"

# ── Mirror optimisation ───────────────────────────────────────────────────────
if [[ -n "$CFG_MIRROR_COUNTRY" ]]; then
    header "Mirror optimisation (reflector)"
    sudo pacman -S --noconfirm --needed reflector
    info "Ranking mirrors for: ${CFG_MIRROR_COUNTRY}..."
    sudo reflector --country "$CFG_MIRROR_COUNTRY" --latest 10 --protocol https --sort rate \
        --save /etc/pacman.d/mirrorlist
    ok "Mirrorlist updated"
fi

# ── System update ─────────────────────────────────────────────────────────────
header "System update"
info "Syncing package databases and upgrading system..."
sudo pacman -Syu --noconfirm
ok "System is up to date"

# ── Base build tools ──────────────────────────────────────────────────────────
header "Base build tools"
sudo pacman -S --noconfirm --needed base-devel git curl
ok "Build tools installed"

# ── AUR helper: paru ──────────────────────────────────────────────────────────
header "AUR helper (paru)"
if command -v paru &>/dev/null; then
    ok "paru already installed"
else
    info "Cloning and building paru..."
    _tmpdir=$(mktemp -d)
    git clone https://aur.archlinux.org/paru.git "$_tmpdir/paru"
    (cd "$_tmpdir/paru" && makepkg -si --noconfirm)
    rm -rf "$_tmpdir"
    ok "paru installed"
fi

# ── GPU drivers ───────────────────────────────────────────────────────────────
header "GPU drivers"

_install_nvidia() {
    info "Installing NVIDIA open kernel module drivers (requires Turing / RTX 2000+ or newer)..."

    info "Installing kernel headers for DKMS..."
    while IFS= read -r _kpkg; do
        sudo pacman -S --noconfirm --needed "${_kpkg}-headers" \
            && ok "Installed ${_kpkg}-headers" \
            || warn "Could not install ${_kpkg}-headers — skipping"
    done < <(pacman -Qq | grep -E "^linux(-lts|-zen|-hardened)?$")

    sudo pacman -S --noconfirm --needed \
        nvidia-open-dkms \
        nvidia-utils \
        lib32-nvidia-utils \
        nvidia-settings \
        egl-wayland

    # Early KMS: prevents a race condition between the DM and the driver
    local _conf=/etc/mkinitcpio.conf
    local _mods="nvidia nvidia_modeset nvidia_uvm nvidia_drm"
    if ! grep -q "nvidia" "$_conf"; then
        local _cur
        _cur=$(grep "^MODULES=" "$_conf" | sed 's/MODULES=(\(.*\))/\1/' | xargs)
        if [[ -z "$_cur" ]]; then
            sudo sed -i "s|^MODULES=(.*|MODULES=($_mods)|" "$_conf"
        else
            sudo sed -i "s|^MODULES=(.*|MODULES=($_cur $_mods)|" "$_conf"
        fi
        info "Rebuilding initramfs with nvidia modules..."
        sudo mkinitcpio -P
    else
        ok "nvidia already present in mkinitcpio MODULES — skipping"
    fi

    local _param="nvidia-drm.modeset=1"
    if [[ -d /boot/loader/entries ]]; then
        local _updated=0
        for _entry in /boot/loader/entries/*.conf; do
            if grep -q "^options" "$_entry" && ! grep -q "$_param" "$_entry"; then
                sudo sed -i "s|^options .*|& $_param|" "$_entry"
                ok "Added $_param → $(basename "$_entry")"
                _updated=1
            fi
        done
        [[ $_updated -eq 0 ]] && warn "systemd-boot entry already has $_param or none found"
    elif [[ -f /etc/default/grub ]]; then
        if ! grep -q "$_param" /etc/default/grub; then
            sudo sed -i \
                "s|GRUB_CMDLINE_LINUX_DEFAULT=\"\([^\"]*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $_param\"|" \
                /etc/default/grub
            sudo grub-mkconfig -o /boot/grub/grub.cfg
            ok "Added $_param to GRUB and regenerated grub.cfg"
        else
            ok "GRUB already has $_param — skipping"
        fi
    else
        warn "Bootloader not detected — add '$_param' to your kernel parameters manually."
    fi

    mkdir -p "$HOME/.config/environment.d"
    cat > "$HOME/.config/environment.d/nvidia-wayland.conf" <<'EOF'
LIBVA_DRIVER_NAME=nvidia
__GLX_VENDOR_LIBRARY_NAME=nvidia
EOF
    ok "Wayland environment written to ~/.config/environment.d/nvidia-wayland.conf"
    ok "NVIDIA drivers installed — a full reboot is required before starting Niri."
}

_install_amd() {
    info "Installing AMD drivers (mesa + vulkan-radeon)..."
    sudo pacman -S --noconfirm --needed \
        mesa \
        lib32-mesa \
        vulkan-radeon \
        lib32-vulkan-radeon \
        libva-mesa-driver \
        mesa-vdpau
    ok "AMD drivers installed"
}

_install_intel() {
    info "Installing Intel drivers (mesa + vulkan-intel + intel-media-driver)..."
    sudo pacman -S --noconfirm --needed \
        mesa \
        lib32-mesa \
        vulkan-intel \
        lib32-vulkan-intel \
        intel-media-driver
    ok "Intel drivers installed"
}

case "$CFG_GPU_CHOICE" in
    1) _install_nvidia ;;
    2) _install_amd    ;;
    3) _install_intel  ;;
    4) warn "Skipping GPU driver installation" ;;
    *) warn "Invalid choice — skipping GPU driver installation" ;;
esac

# ── Audio: PipeWire stack ─────────────────────────────────────────────────────
header "Audio stack (PipeWire)"
sudo pacman -S --noconfirm --needed \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    pipewire-jack \
    wireplumber \
    pavucontrol
ok "PipeWire stack installed"

# ── Power management ──────────────────────────────────────────────────────────
header "Power management"
sudo pacman -S --noconfirm --needed power-profiles-daemon
sudo systemctl enable --now power-profiles-daemon
ok "power-profiles-daemon installed and enabled"

# ── Niri and Wayland core ─────────────────────────────────────────────────────
header "Niri and Wayland core"
sudo pacman -S --noconfirm --needed \
    niri \
    xdg-desktop-portal-gnome \
    xdg-user-dirs \
    polkit-gnome \
    dbus \
    wl-clipboard \
    grim \
    slurp

info "Installing xwayland-satellite from AUR..."
paru -S --noconfirm --needed xwayland-satellite

ok "Niri and Wayland core installed"

# ── Terminal emulator ─────────────────────────────────────────────────────────
header "Terminal (kitty)"
sudo pacman -S --noconfirm --needed kitty
ok "kitty installed"

# ── File manager ──────────────────────────────────────────────────────────────
header "File manager (nautilus)"
sudo pacman -S --noconfirm --needed \
    nautilus \
    gvfs \
    gvfs-mtp
ok "nautilus + gvfs installed"

# ── Notification daemon ───────────────────────────────────────────────────────
header "Notifications (mako)"
sudo pacman -S --noconfirm --needed mako
ok "mako installed"

# ── Wallpaper daemon ──────────────────────────────────────────────────────────
header "Wallpaper daemon (swww)"
paru -S --noconfirm --needed swww
ok "swww installed"

# ── Screen lock ───────────────────────────────────────────────────────────────
header "Screen lock (swaylock)"
sudo pacman -S --noconfirm --needed swaylock
ok "swaylock installed"

# ── Idle management ───────────────────────────────────────────────────────────
header "Idle management (swayidle)"
sudo pacman -S --noconfirm --needed swayidle
ok "swayidle installed (lock at ${CFG_LOCK_SECS}s, displays off at ${CFG_OFF_SECS}s)"

# ── Night light ───────────────────────────────────────────────────────────────
if [[ -n "$CFG_LAT" ]]; then
    header "Night light (wlsunset)"
    sudo pacman -S --noconfirm --needed wlsunset
    ok "wlsunset installed (lat: ${CFG_LAT}, lon: ${CFG_LON})"
fi

# ── Brightness & display utilities ────────────────────────────────────────────
header "Brightness & display"
sudo pacman -S --noconfirm --needed \
    brightnessctl \
    wlr-randr
ok "brightnessctl and wlr-randr installed"

# ── Fonts ─────────────────────────────────────────────────────────────────────
header "Fonts"
sudo pacman -S --noconfirm --needed \
    noto-fonts \
    noto-fonts-emoji \
    ttf-jetbrains-mono-nerd \
    ttf-font-awesome
ok "Fonts installed"

# ── GTK & Qt theming ──────────────────────────────────────────────────────────
header "GTK & Qt theming"
sudo pacman -S --noconfirm --needed \
    gtk3 \
    gtk4 \
    adwaita-icon-theme \
    gsettings-desktop-schemas \
    nwg-look \
    qt5ct \
    qt6ct \
    kvantum

mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/theming.conf" <<'EOF'
QT_QPA_PLATFORM=wayland
QT_QPA_PLATFORMTHEME=qt6ct
XCURSOR_THEME=Adwaita
XCURSOR_SIZE=24
EOF

ok "GTK & Qt theming installed"
ok "Theming environment written to ~/.config/environment.d/theming.conf"

# ── Network & Bluetooth ───────────────────────────────────────────────────────
header "Network & Bluetooth"
sudo pacman -S --noconfirm --needed networkmanager network-manager-applet
sudo systemctl enable --now NetworkManager
paru -S --noconfirm --needed blueman
sudo pacman -S --noconfirm --needed bluez bluez-utils
sudo systemctl enable --now bluetooth
ok "Network and Bluetooth services enabled"

# ── Display manager: greetd + tuigreet ────────────────────────────────────────
header "Display manager (greetd + tuigreet)"
sudo pacman -S --noconfirm --needed greetd greetd-tuigreet

sudo mkdir -p /etc/greetd
sudo tee /etc/greetd/config.toml > /dev/null <<EOF
[terminal]
vt = 1

[default_session]
# tuigreet remembers the last user and launches niri-session
command = "tuigreet --time --remember --cmd niri-session"
user = "greeter"
EOF

sudo systemctl enable greetd
ok "greetd configured and enabled"

# ── Flatpak ───────────────────────────────────────────────────────────────────
header "Flatpak"
sudo pacman -S --noconfirm --needed flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
ok "Flatpak installed with Flathub remote"

# ── Noctalia shell ────────────────────────────────────────────────────────────
header "Noctalia shell"

for _pkg in quickshell quickshell-git; do
    if paru -Q "$_pkg" &>/dev/null; then
        warn "$_pkg conflicts with noctalia-qs — removing it..."
        sudo pacman -Rns --noconfirm "$_pkg"
    fi
done

info "Installing noctalia-shell from AUR (builds noctalia-qs + Qt deps — may take a while)..."
paru -S --noconfirm --needed noctalia-shell

info "Installing optional Noctalia dependencies..."
paru -S --noconfirm --needed cliphist
sudo pacman -S --noconfirm --needed imagemagick ffmpeg python qt6-multimedia

ok "Noctalia shell installed"

# ── Niri config skeleton ──────────────────────────────────────────────────────
header "Niri configuration"
mkdir -p "$HOME/.config/niri"

# Build the wlsunset line before the heredoc so the variable expands correctly.
# The heredoc uses an unquoted delimiter so CFG_* variables are interpolated.
if [[ -n "$CFG_LAT" ]]; then
    _wlsunset_line="spawn-at-startup \"wlsunset\" \"-l\" \"${CFG_LAT}\" \"-L\" \"${CFG_LON}\""
else
    _wlsunset_line="// night light not configured — to enable: spawn-at-startup \"wlsunset\" \"-l\" \"LAT\" \"-L\" \"LON\""
fi

if [[ -f "$HOME/.config/niri/config.kdl" ]]; then
    warn "~/.config/niri/config.kdl already exists — backing up to config.kdl.bak and skipping"
    cp "$HOME/.config/niri/config.kdl" "$HOME/.config/niri/config.kdl.bak"
else
    info "Writing ~/.config/niri/config.kdl..."
    cat > "$HOME/.config/niri/config.kdl" <<KDLEOF
// Niri configuration — https://github.com/YaLTeR/niri/wiki/Configuration
// Super key = Mod

input {
    keyboard {
        xkb {
            layout "gb"
            // options "caps:escape"
        }
        repeat-delay 600
        repeat-rate 25
    }
    touchpad {
        tap
        natural-scroll
        scroll-factor 0.3
    }
    mouse {
        natural-scroll false
    }
}

cursor {
    xcursor-theme "Adwaita"
    xcursor-size 24
}

output "eDP-1" {
    scale 1.0
}

layout {
    gaps 12
    center-focused-column "never"
    preset-column-widths {
        proportion 0.333333
        proportion 0.5
        proportion 0.666667
    }
    default-column-width { proportion 0.5 }
    focus-ring {
        width 2
        active-color "#7fc8ff"
        inactive-color "#404040"
    }
    border {
        off
    }
    shadow {
        on
    }
}

// Daemon autostart
spawn-at-startup "xwayland-satellite"
spawn-at-startup "mako"
spawn-at-startup "swww-daemon"
spawn-at-startup "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
spawn-at-startup "noctalia"
spawn-at-startup "wl-paste" "--type" "text" "--watch" "cliphist store"
spawn-at-startup "wl-paste" "--type" "image" "--watch" "cliphist store"
spawn-at-startup "swayidle" "-w" "timeout" "${CFG_LOCK_SECS}" "swaylock -f -c 000000" "timeout" "${CFG_OFF_SECS}" "niri msg action power-off-monitors" "resume" "niri msg action power-on-monitors" "before-sleep" "swaylock -f -c 000000"
${_wlsunset_line}

prefer-no-csd

screenshot-path "~/Pictures/Screenshots/Screenshot_%Y-%m-%d_%H-%M-%S.png"

hotkey-overlay {
    skip-at-startup
}

animations {
    slowdown 1.0
}

window-rule {
    geometry-corner-radius 8
    clip-to-geometry true
}

binds {
    // ── Applications ──────────────────────────────────────────────────
    Mod+Return  { spawn "kitty"; }
    Mod+D       { spawn-sh "noctalia-shell ipc call launcher toggle"; }
    Mod+E       { spawn "nautilus"; }

    // ── Screen lock ───────────────────────────────────────────────────
    Mod+Shift+L { spawn "swaylock" "-f" "-c" "000000"; }

    // ── Window management ─────────────────────────────────────────────
    Mod+Q           { close-window; }
    Mod+F           { maximize-column; }
    Mod+Shift+F     { fullscreen-window; }
    Mod+C           { center-column; }

    // ── Focus movement ────────────────────────────────────────────────
    Mod+H           { focus-column-left; }
    Mod+L           { focus-column-right; }
    Mod+J           { focus-window-down; }
    Mod+K           { focus-window-up; }
    Mod+Left        { focus-column-left; }
    Mod+Right       { focus-column-right; }
    Mod+Down        { focus-window-down; }
    Mod+Up          { focus-window-up; }

    // ── Window movement ───────────────────────────────────────────────
    Mod+Shift+H     { move-column-left; }
    Mod+Shift+L     { move-column-right; }
    Mod+Shift+J     { move-window-down; }
    Mod+Shift+K     { move-window-up; }
    Mod+Shift+Left  { move-column-left; }
    Mod+Shift+Right { move-column-right; }

    // ── Column sizing ─────────────────────────────────────────────────
    Mod+R           { switch-preset-column-width; }
    Mod+Minus       { set-column-width "-10%"; }
    Mod+Equal       { set-column-width "+10%"; }
    Mod+Shift+Minus { set-window-height "-10%"; }
    Mod+Shift+Equal { set-window-height "+10%"; }

    // ── Workspaces ────────────────────────────────────────────────────
    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }
    Mod+5 { focus-workspace 5; }
    Mod+6 { focus-workspace 6; }
    Mod+7 { focus-workspace 7; }
    Mod+8 { focus-workspace 8; }
    Mod+9 { focus-workspace 9; }
    Mod+Shift+1 { move-column-to-workspace 1; }
    Mod+Shift+2 { move-column-to-workspace 2; }
    Mod+Shift+3 { move-column-to-workspace 3; }
    Mod+Shift+4 { move-column-to-workspace 4; }
    Mod+Shift+5 { move-column-to-workspace 5; }
    Mod+Shift+6 { move-column-to-workspace 6; }
    Mod+Shift+7 { move-column-to-workspace 7; }
    Mod+Shift+8 { move-column-to-workspace 8; }
    Mod+Shift+9 { move-column-to-workspace 9; }
    Mod+Tab            { focus-workspace-down; }
    Mod+Shift+Tab      { focus-workspace-up; }
    Mod+BracketRight   { focus-workspace-down; }
    Mod+BracketLeft    { focus-workspace-up; }

    // ── Scrolling ─────────────────────────────────────────────────────
    Mod+WheelScrollRight       { focus-column-right; }
    Mod+WheelScrollLeft        { focus-column-left; }
    Mod+Shift+WheelScrollRight { move-column-right; }
    Mod+Shift+WheelScrollLeft  { move-column-left; }

    // ── Screenshots ───────────────────────────────────────────────────
    Print       { screenshot; }
    Ctrl+Print  { screenshot-screen; }
    Alt+Print   { screenshot-window; }

    // ── Session ───────────────────────────────────────────────────────
    Mod+Shift+E     { quit; }
    Mod+Shift+Slash { show-hotkey-overlay; }

    // ── Media & brightness keys ───────────────────────────────────────
    XF86AudioRaiseVolume  allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"; }
    XF86AudioLowerVolume  allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
    XF86AudioMute         allow-when-locked=true { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
    XF86AudioMicMute      allow-when-locked=true { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle"; }
    XF86MonBrightnessUp   { spawn "brightnessctl" "set" "5%+"; }
    XF86MonBrightnessDown { spawn "brightnessctl" "set" "5%-"; }
}
KDLEOF
    ok "~/.config/niri/config.kdl written"
fi

# ── Screenshots directory ─────────────────────────────────────────────────────
mkdir -p "$HOME/Pictures/Screenshots"

# ── XDG user dirs ─────────────────────────────────────────────────────────────
xdg-user-dirs-update

# ── Enable user systemd services ──────────────────────────────────────────────
header "User systemd services"
systemctl --user enable --now wireplumber.service 2>/dev/null || true
systemctl --user enable --now pipewire-pulse.service 2>/dev/null || true
ok "wireplumber and pipewire-pulse user services enabled"

# ── Done ──────────────────────────────────────────────────────────────────────
header "Install complete"
printf "\n${GREEN}${BOLD}Everything is installed!${NC}\n\n"
printf "  ${BOLD}Next steps:${NC}\n"
printf "  1. Edit ${CYAN}~/.config/niri/config.kdl${NC} — set your keyboard layout\n"
printf "     and replace eDP-1 with your display name (find it with: niri msg outputs).\n"
printf "  2. Run ${CYAN}niri validate-config${NC} to check for syntax errors.\n"
printf "  3. Configure Noctalia: ${CYAN}https://docs.noctalia.dev/${NC}\n"
printf "  4. Reboot — greetd will handle login from here on.\n"
printf "     ${BOLD}sudo reboot${NC}\n\n"
