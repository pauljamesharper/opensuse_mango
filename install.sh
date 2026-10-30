#!/bin/bash

# mangobutter installer (--only-config: the setup's files, and on Debian the
# packages added to the list since, never removing any)

set -e

ONLY_CONFIG=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --only-config)
            ONLY_CONFIG=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "  --only-config      Config files; on Debian also packages added since (never removes any)"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mango"
KEPT_NEW=()
TEMP_DIR="/tmp/mango_$$"
LOG_FILE="$HOME/mango-install.log"

# Logging and cleanup
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'rm -rf "$TEMP_DIR"' EXIT

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

die() { echo -e "${RED}ERROR: $*${NC}" >&2; exit 1; }
warn() { echo -e "${YELLOW}WARNING: $*${NC}" >&2; }
msg() { echo -e "${CYAN}$*${NC}"; }


# Package names target Debian 13 (trixie); newer releases (forky/sid) and Ubuntu differ.
# mangowc itself comes from butterrepo: it needs wlroots 0.19 + scenefx 0.4, which
# trixie does not ship, and butterrepo carries all three as .debs.
if [ "$ONLY_CONFIG" = false ]; then
    # shellcheck source=/dev/null
    . /etc/os-release 2>/dev/null || die "Cannot read /etc/os-release to verify OS"
    case " $ID ${ID_LIKE:-} " in
        *" ubuntu "*) die "Unsupported OS: ${PRETTY_NAME:-unknown}. Ubuntu-based systems are not supported." ;;
    esac
    DEBIAN_BASE=$(cat /etc/debian_version 2>/dev/null || true)
    case "$DEBIAN_BASE" in
        13|13.*) ;;
        *) die "Unsupported OS: ${PRETTY_NAME:-unknown}. This installer requires a Debian 13 (trixie) base (found: ${DEBIAN_BASE:-no /etc/debian_version})." ;;
    esac
fi

# an update keeps what setup-update printed above it
[ "$ONLY_CONFIG" = true ] || clear 2>/dev/null || true
printf '\033[1mmangobutter\033[0m\n\033[2mmango for Debian · justaguy.dev/butter/mango\033[0m\n\n'

# A machine with no login screen yet (a minimal Debian) needs a reboot at
# the end, not a logout: remembered now, before one gets installed
DM_AT_START=$(systemctl is-active display-manager 2>/dev/null || true)

if [ "$ONLY_CONFIG" = false ]; then
    msg "Updating system..."
    sudo apt-get update && sudo apt-get upgrade -y

    # Add butterrepo for mangowc (+ wlroots 0.19 / scenefx 0.4), quickshell and rofi
    msg "Checking butterrepo..."
    wget -qO- "https://justaguy.dev/drew/butterscripts/raw/branch/main/setup/add_butterrepo.sh" | bash \
        || die "butterrepo could not be set up - see the messages above"

    # Fail here, with the reason, rather than at the first apt install with
    # "Unable to locate package mangowc".
    if ! apt-cache policy mangowc 2>/dev/null | grep -q 'apt.justaguy.dev'; then
        die "apt can't see mangowc in butterrepo. Check /etc/apt/sources.list.d/butterrepo.list, then run 'sudo apt-get update' and look for errors mentioning justaguy.dev"
    fi
else
    msg "Skipping system update (--only-config mode)"
fi

# One apt run: a package it can't install is named in its error
PACKAGES=(
    # mango and the wallpaper daemon (butterrepo)
    mangowc xwayland awww
    build-essential
    # the bar; quickshell pulls its qml6 modules in through Recommends.
    # bluez, pulseaudio-utils, xdg-utils, pkexec and python3 back features
    # of the bar (Bluetooth rows, the timer chime, opening links, the
    # Tailscale grant, restoring a kept display layout); a full Debian
    # usually has them, a minimal one doesn't
    quickshell rofi dunst libnotify-bin btop
    pamixer playerctl brightnessctl wlsunset power-profiles-daemon
    network-manager-gnome network-manager-config-connectivity-debian qrencode
    bluez pulseaudio-utils xdg-utils pkexec python3
    # Wayland tools
    grim slurp swappy wl-clipboard cliphist
    wlr-randr swayidle wlopm qml6-module-qtquick-effects
    xdg-desktop-portal-wlr xdg-desktop-portal-gtk
    x11-xserver-utils
    # gtk + icon themes (butterrepo: prebuilt vinceliuice selections, see deb-builders)
    orchis-gtk-theme-butter colloid-icon-theme-butter
    # the wallpaper picker's palette (butterrepo: a small C program the setups share)
    butterpal
    nwg-look xsettingsd lxpolkit
    # file manager
    thunar thunar-archive-plugin thunar-volman
    gvfs-backends gvfs-fuse dialog mtools smbclient cifs-utils unzip
    # audio
    pavucontrol pulsemixer pipewire-audio
    # utilities
    avahi-daemon acpi acpid upower
    fd-find xdg-user-dirs-gtk
    butterview fastfetch
    gawk curl wget
    # fonts
    fonts-recommended fonts-font-awesome fonts-noto-color-emoji
)

if [ "$ONLY_CONFIG" = false ]; then
    msg "Installing packages..."
    sudo apt-get install -y "${PACKAGES[@]}" || die "Failed to install packages - apt names the one it could not install above"

    # on its own, allowed to fail: nothing else needs it
    sudo apt-get install -y firefox-esr 2>/dev/null || msg "Note: firefox-esr not available, skipping..."

    # Enable services
    sudo systemctl enable avahi-daemon acpid

    # GPU access. scenefx (mango's renderer) opens the render node directly at
    # startup and has no fallback if that fails. logind normally grants the
    # active session an ACL on it, but that can land a moment after the
    # session starts; the render group makes access unconditional.
    if ! id -nG "$USER" | grep -qw render; then
        msg "Adding $USER to the render group (GPU render node access)..."
        sudo usermod -aG render "$USER"
    fi

    # Seat management. mango's libseat prefers a running seatd over logind,
    # but with a display manager the seat belongs to logind, and with two
    # seat managers mango can't become DRM master (a blank session). Nothing
    # here needs seatd; make sure it isn't running.
    if systemctl is-active --quiet seatd 2>/dev/null; then
        warn "seatd is running alongside logind — disabling it (mango uses logind for the seat)"
        sudo systemctl disable --now seatd
    fi
else
    # --only-config: the setup's files, and on Debian the packages added to
    # the list since (the Update button runs this): one at a time and never
    # removing anything, so a system set up its own way (XLibre in place of
    # xorg, say) keeps what it has. Lists too old to know a new package are
    # refreshed once.
    if command -v apt-get >/dev/null 2>&1 && command -v dpkg-query >/dev/null 2>&1; then
        missing=()
        for p in "${PACKAGES[@]}"; do
            [ "$p" = quickshell ] && command -v qs >/dev/null 2>&1 && continue
            [ "$(dpkg-query -W -f='${db:Status-Status}' "$p" 2>/dev/null)" = installed ] || missing+=("$p")
        done
        if [ ${#missing[@]} -gt 0 ]; then
            msg "Installing packages added since your install: ${missing[*]}"
            refreshed=false
            for p in "${missing[@]}"; do
                sudo apt-get install -y --no-remove "$p" && continue
                if [ "$refreshed" = false ]; then
                    refreshed=true
                    sudo apt-get update && sudo apt-get install -y --no-remove "$p" && continue
                fi
                warn "$p not installed (apt can't find it, or it would remove a package) - sudo apt install $p"
            done
        fi
    fi
fi

# Three folders, by owner (see README, "Making it yours"):
#   $SHARE_DIR   the setup's files: bar, scripts, defaults, templates —
#                replaced wholesale on every update, nothing of yours lives here
#   $CONFIG_DIR  the user's: config.conf, autostart.conf, keybinds.conf,
#                local.conf, env, wallpaper/ — never replaced; the files follow dpkg's
#                conffile rule (updated silently if never edited, otherwise
#                kept with ours beside as FILE.new, said once)
#   $STATE_DIR   generated files (palette, theme.conf, themed dunst, kitty
#                colors) and the settings the bar keeps — survive untouched
SHARE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mango"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mango"
mkdir -p "$SHARE_DIR" "$CONFIG_DIR" "$STATE_DIR/shipped"

# An install with the old one-folder layout keeps everything in
# $CONFIG_DIR. Move it aside whole and carry over what is the user's; the
# share folder takes over the rest.
BACKUP_DIR=""
if [ -d "$CONFIG_DIR/quickshell" ]; then
    BACKUP_DIR="$CONFIG_DIR.bak.$(date +%Y%m%d-%H%M%S)"
    while [ -e "$BACKUP_DIR" ]; do BACKUP_DIR="$BACKUP_DIR-1"; done
    msg "Config with the old one-folder layout found - moving it to $BACKUP_DIR and carrying yours over"
    mv "$CONFIG_DIR" "$BACKUP_DIR"
    mkdir -p "$CONFIG_DIR"
    # the user's files, as they were
    for f in keybinds.conf local.conf env; do
        [ -f "$BACKUP_DIR/$f" ] && cp "$BACKUP_DIR/$f" "$CONFIG_DIR/$f"
    done
    [ -d "$BACKUP_DIR/wallpaper" ] && mv "$BACKUP_DIR/wallpaper" "$CONFIG_DIR/wallpaper"
    # generated files and settings go to the state folder
    for f in theme.conf polybar/colors.ini rofi/colors.rasi dunst/dunstrc \
             bar-height bar-scale popup-scale tag-icons mango-gaps mango-effects \
             lock-idle lock-style pomodoro weather-location weather-units \
             launcher-history displays.conf; do
        [ -f "$BACKUP_DIR/$f" ] && [ ! -e "$STATE_DIR/$(basename "$f")" ] && cp "$BACKUP_DIR/$f" "$STATE_DIR/$(basename "$f")"
    done
    [ -f "$BACKUP_DIR/kitty/current-theme.conf" ] && [ ! -e "$STATE_DIR/kitty-theme.conf" ] && cp "$BACKUP_DIR/kitty/current-theme.conf" "$STATE_DIR/kitty-theme.conf"
    # that layout keeps the wallpaper line in config.conf; theme.conf carries it
    if [ -f "$STATE_DIR/theme.conf" ] && ! grep -q '^exec-once=awww img' "$STATE_DIR/theme.conf"; then
        grep '^exec-once=awww img' "$BACKUP_DIR/config.conf" >> "$STATE_DIR/theme.conf" 2>/dev/null || true
    fi
    # keybinds and env from that layout name the old script paths
    for f in keybinds.conf env; do
        # shellcheck disable=SC2016  # written literally, expanded at login
        [ -f "$CONFIG_DIR/$f" ] && sed -i 's|\.config/mango/scripts/|.local/share/mango/scripts/|g; s|\.config/mango/quickshell|.local/share/mango/quickshell|g; s|^KITTY_CONFIG_DIRECTORY=.*|KITTY_CONFIG_DIRECTORY=${XDG_DATA_HOME:-$HOME/.local/share}/mango/kitty|' "$CONFIG_DIR/$f"
    done
fi

# The setup's own files: replaced wholesale
msg "Setting up configuration..."
rm -rf "$SHARE_DIR"
mkdir -p "$SHARE_DIR"
cp -r "$SCRIPT_DIR"/share/* "$SHARE_DIR"/ || die "Failed to copy the setup's files"
chmod +x "$SHARE_DIR"/scripts/*

# The user's files, dpkg's way. "Never edited" is known from the copy of
# what was shipped last time, kept in the state folder.
for f in config.conf autostart.conf keybinds.conf rules.conf local.conf env; do
    ours="$SCRIPT_DIR/config/$f"; theirs="$CONFIG_DIR/$f"; prev="$STATE_DIR/shipped/$f"
    if [ ! -f "$theirs" ]; then
        cp "$ours" "$theirs"                              # first time: ours
    elif cmp -s "$theirs" "$ours"; then
        :                                                 # identical already
    elif [ -f "$prev" ] && cmp -s "$theirs" "$prev"; then
        cp "$ours" "$theirs"                              # never edited: ours, silently
    elif [ -f "$prev" ] && cmp -s "$ours" "$prev"; then
        :                                                 # edited, ours unchanged: theirs
    elif [ -f "$theirs.new" ] && cmp -s "$theirs.new" "$ours"; then
        :                                                 # same .new as last time, said already
    else
        cp "$ours" "$theirs.new"                          # edited and ours changed: theirs stays
        KEPT_NEW+=("$f")
    fi
done
if [ ${#KEPT_NEW[@]} -gt 0 ]; then
    msg "Kept your ${KEPT_NEW[*]}; the new defaults are beside as .new"
fi
# the commit installed from last time, for generated() below
PREV_COMMIT=$(cat "$STATE_DIR/shipped/commit" 2>/dev/null || true)
# remember what was shipped this time (see above)
cp "$SCRIPT_DIR"/config/{config.conf,autostart.conf,keybinds.conf,rules.conf,local.conf,env} "$STATE_DIR/shipped/"
# and where it came from, for scripts/setup-update (the command menu's
# "Update setup"); a zip download has no record and the entry says so
if git -C "$SCRIPT_DIR" rev-parse HEAD >/dev/null 2>&1; then
    # a clone made under the old name moves to the new one
    remote=$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || true)
    case "$remote" in
        *justaguy.dev*/mangowc-setup|*justaguy.dev*/mangowc-setup.git|*justaguy.dev*/mangowc-setup/)
            remote="${remote%mangowc-setup*}mangobutter${remote##*mangowc-setup}"
            git -C "$SCRIPT_DIR" remote set-url origin "$remote" ;;
    esac
    git -C "$SCRIPT_DIR" rev-parse HEAD > "$STATE_DIR/shipped/commit"
    git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD > "$STATE_DIR/shipped/branch"
    echo "$remote" > "$STATE_DIR/shipped/remote"
    echo "$SCRIPT_DIR" > "$STATE_DIR/shipped/source"
else
    rm -f "$STATE_DIR/shipped/commit" "$STATE_DIR/shipped/branch" "$STATE_DIR/shipped/remote" "$STATE_DIR/shipped/source"
fi
# a kept config.conf may lack the source lines for autostart.conf (the bar,
# dunst, idle) and rules.conf; they go in where the shipped one has them
grep -q 'autostart\.conf' "$CONFIG_DIR/config.conf" || sed -i '/^source=.*defaults\.conf/a source=~/.config/mango/autostart.conf' "$CONFIG_DIR/config.conf"
grep -q 'rules\.conf' "$CONFIG_DIR/config.conf" || sed -i '/^source=.*keybinds\.conf/a source=~/.config/mango/rules.conf' "$CONFIG_DIR/config.conf"
for f in autostart.conf rules.conf; do
    grep -qF "$f" "$CONFIG_DIR/config.conf" || warn "$CONFIG_DIR/config.conf does not read $f - add source=~/.config/mango/$f (see $SCRIPT_DIR/config/config.conf)"
done
# a kept env may lack MANGO_STATE_DIR
# shellcheck disable=SC2016  # written literally, expanded at login
grep -q '^MANGO_STATE_DIR=' "$CONFIG_DIR/env" || printf '\nMANGO_STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/mango\n' >> "$CONFIG_DIR/env"

# Generated files: the default look, written from the default wallpaper.
# A pick rewrites them all, so they follow the conffile rule without the
# .new: replaced while they still equal what was shipped last time, left
# alone after a pick. An install with no shipped copies yet is judged
# against the commit it was installed from.
mkdir -p "$STATE_DIR/shipped/state"
generated() {        # <ours> <name> <path in the repo at the old commit>
    local ours="$1" theirs="$STATE_DIR/$2" prev="$STATE_DIR/shipped/state/$2"
    if [ ! -e "$theirs" ]; then
        cp "$ours" "$theirs"                              # first time: ours
    elif [ -f "$prev" ]; then
        cmp -s "$theirs" "$prev" && cp "$ours" "$theirs"  # no pick since: ours
    elif [ -n "$PREV_COMMIT" ] && git -C "$SCRIPT_DIR" show "$PREV_COMMIT:$3" 2>/dev/null | cmp -s - "$theirs"; then
        cp "$ours" "$theirs"                              # same, judged by the old commit
    fi
    cp "$ours" "$prev"
}
for f in "$SCRIPT_DIR"/state/*; do
    generated "$f" "$(basename "$f")" "state/$(basename "$f")"
done
generated "$SHARE_DIR/dunst/dunstrc" dunstrc share/dunst/dunstrc

# $CONFIG_DIR/env is sourced at login by mango-session, the wrapper the
# mangowc package's session entry runs from 0.14.4-4 on: that's how
# KITTY_CONFIG_DIRECTORY (the session's kitty config in $SHARE_DIR/kitty)
# reaches the terminals mango spawns. Older packages ignore the file.
MANGO_VER=$(dpkg-query -W -f='${Version}' mangowc 2>/dev/null || true)
if [ -z "$MANGO_VER" ]; then
    [ "$ONLY_CONFIG" = true ] && warn "mangowc is not installed - $CONFIG_DIR/env needs mangowc 0.14.4-4 or newer (butterrepo)"
elif ! dpkg --compare-versions "$MANGO_VER" ge 0.14.4-4; then
    warn "mangowc $MANGO_VER is older than 0.14.4-4: $CONFIG_DIR/env won't be sourced at login (kitty theming stays global) - update mangowc from butterrepo"
fi

# Inside a VM, virtio-gpu renders the hardware cursor upside down or not at
# all. Switch mango to a software cursor via the session env file (the line
# is shipped commented out). Not a supported target, just not broken.
if systemd-detect-virt -q 2>/dev/null; then
    msg "Virtual machine detected ($(systemd-detect-virt)) - enabling software cursor"
    sed -i 's|^#WLR_NO_HARDWARE_CURSORS=1$|WLR_NO_HARDWARE_CURSORS=1|' "$CONFIG_DIR/env"
fi

# dunst is started with -config from autostart.conf; the symlink covers the
# D-Bus-activated case (a notification arriving before autostart ran). A
# dunstrc of the user's own is left alone
if [ ! -e ~/.config/dunst/dunstrc ] || [ -L ~/.config/dunst/dunstrc ]; then
    mkdir -p ~/.config/dunst
    ln -sfn "$STATE_DIR/dunstrc" ~/.config/dunst/dunstrc
fi
# swappy (screenshot annotate) saves where the other screenshots go; a
# swappy config of the user's own is left alone
if [ ! -e ~/.config/swappy/config ] || [ -L ~/.config/swappy/config ]; then
    mkdir -p ~/.config/swappy
    ln -sfn "$SHARE_DIR/swappy/config" ~/.config/swappy/config
fi

# Setup directories
command -v xdg-user-dirs-update >/dev/null && xdg-user-dirs-update
# Default apps, set on a full install only: an update leaves the user's
# choices alone. thunar handles folders: the bar's wallpaper picker opens
# one via xdg-open, and with no default set it falls to whichever .desktop
# sorts first. butterview opens images (double-click in thunar, xdg-open
# from the scripts).
if [ "$ONLY_CONFIG" = false ] && command -v xdg-mime >/dev/null; then
    xdg-mime default thunar.desktop inode/directory
    xdg-mime default butterview.desktop \
        image/jpeg image/png image/gif image/webp image/avif image/jxl image/tiff image/bmp image/svg+xml
fi
# butterview no longer sets wallpapers: drop the hook earlier installs linked
if [ "$(readlink ~/.config/butterview/wallpaper)" = "$SHARE_DIR/butterview/wallpaper" ]; then
    rm -f ~/.config/butterview/wallpaper
fi
mkdir -p ~/Screenshots

# Drop quickstart cheatsheet in $HOME (user can delete once read); a full
# install only, so a deleted one stays deleted
if [ "$ONLY_CONFIG" = false ] && [ -f "$SCRIPT_DIR/QUICKSTART.md" ]; then
    cp "$SCRIPT_DIR/QUICKSTART.md" "$HOME/QUICKSTART-mango.md"
fi

# Copy nvidia-setup.sh to $HOME so NVIDIA users can re-run it after install
if [ "$ONLY_CONFIG" = false ] && [ -f "$SCRIPT_DIR/nvidia-setup.sh" ]; then
    cp "$SCRIPT_DIR/nvidia-setup.sh" "$HOME/nvidia-setup.sh"
    chmod +x "$HOME/nvidia-setup.sh"
fi

BUTTERSCRIPTS=https://justaguy.dev/drew/butterscripts/raw/branch/main
# get_script <path> [args]: run a butterscript from memory; fails when the
# download does, rather than running nothing
get_script() {
    local script
    script=$(wget -qO- "$BUTTERSCRIPTS/$1") || return
    bash -s -- "${@:2}" <<< "$script"
}
# fetch_script <path> <name> <hint>: save a butterscript to $TEMP_DIR, for
# one that asks questions (run from a file it can read the terminal); a
# failed download warns with the hint and returns 1
fetch_script() {
    msg "Downloading $2 installer..."
    if wget -O "$TEMP_DIR/${1##*/}" "$BUTTERSCRIPTS/$1"; then
        msg "Running $2 installer..."
    else
        warn "Could not download the $2 installer - $3"
        return 1
    fi
}

# Install essential components
if [ "$ONLY_CONFIG" = false ]; then
    mkdir -p "$TEMP_DIR" && cd "$TEMP_DIR"

    # --no-config: the session's kitty config is $SHARE_DIR/kitty;
    # ~/.config/kitty is left alone
    msg "Installing kitty..."
    get_script "kitty/install_kitty.sh" --no-config \
        || warn "Kitty installation failed - you can install it manually later"

    # fonts before geany: its installer skips its own font step when
    # SauceCodePro is already there
    msg "Installing fonts..."
    get_script "theming/install_nerdfonts.sh" || warn "Font installation failed - you can install fonts manually later"

    # the editor Super+E and the keybinds viewer open (keybinds.conf, scripts/keybinds)
    msg "Installing geany..."
    get_script "geany/install_geany.sh" \
        || warn "Geany installation failed - Super+E and editing from the keybinds viewer need an editor called geany"

    msg "Installing themes..."
    get_script "theming/install_wallpaper_theme.sh" || warn "Theme installation failed - you can install themes manually later"

    msg "Downloading wallpaper directory..."
    if [ ! -d "$CONFIG_DIR/wallpaper" ]; then
        if git clone --depth 1 --progress https://github.com/drewgrif/wallpapers.git "$CONFIG_DIR/wallpaper"; then
            rm -rf "$CONFIG_DIR/wallpaper/.git"
        else
            warn "Failed to clone wallpapers - the default one is fetched on its own below"
        fi
    else
        msg "Wallpaper directory already exists, skipping..."
    fi

    if fetch_script system/install_lightdm.sh "display manager" "you can install a login screen later"; then
        bash "$TEMP_DIR/install_lightdm.sh" || warn "Display manager installer failed - you can run it again later"
    fi

    # NVIDIA setup (auto-detects GPU and drivers)
    # Skip in chroot (no GPU access) or if running as root (e.g., during butterknife install)
    if [ "$EUID" -ne 0 ] && [ ! -f /run/host/container-manager ] && [ -d /sys/class/drm ]; then
        msg "Checking for NVIDIA GPU configuration..."
        bash "$SCRIPT_DIR/nvidia-setup.sh" || warn "NVIDIA setup skipped"
    else
        msg "Skipping NVIDIA setup (chroot or root environment)"
    fi

    # Optional tools
    # a whole line read, so the Enter after y doesn't land in the next menu;
    # no answer (no terminal) is a no
    read -r -p "Install optional tools (browsers, editors, etc)? (y/n) " REPLY || REPLY=n
    if [[ $REPLY =~ ^[Yy] ]] && fetch_script setup/optional_tools.sh "optional tools" "you can run it later"; then
        if bash "$TEMP_DIR/optional_tools.sh"; then
            msg "Optional tools completed successfully"
        else
            msg "Optional tools exited (this is normal if canceled by user)"
        fi
    fi
else
    msg "Skipping external tool installation (--only-config mode)"
fi

# The default wallpaper has to exist for theme.conf's awww line: the
# wallpaper folder is cloned once, on the first install, so a default that
# changed since (or a config-only run on a bare machine) fetches that one file
DEFAULT_WALLPAPER=mangobutter-journey.png
if [ ! -f "$CONFIG_DIR/wallpaper/$DEFAULT_WALLPAPER" ]; then
    mkdir -p "$CONFIG_DIR/wallpaper"
    wget -qO "$CONFIG_DIR/wallpaper/$DEFAULT_WALLPAPER" "https://raw.githubusercontent.com/drewgrif/wallpapers/main/$DEFAULT_WALLPAPER" \
        || { rm -f "$CONFIG_DIR/wallpaper/$DEFAULT_WALLPAPER"; warn "could not fetch the default wallpaper ($DEFAULT_WALLPAPER); pick one from the bar"; }
fi

# Run from inside the session (Update setup): finish the job here, so the
# new files are live without a logout. The terminal this runs in was
# started detached from the bar, so it outlives the restart.
LIVE=false
if [ "$ONLY_CONFIG" = true ] && [ -n "${WAYLAND_DISPLAY:-}" ] && pgrep -x -u "$USER" mango >/dev/null 2>&1; then
    LIVE=true
    # a bar from the old one-folder layout still runs out of the moved
    # folder: stop it, or both bars stay up
    if [ -n "$BACKUP_DIR" ]; then
        pkill -u "$USER" -f "^qs -p $CONFIG_DIR/quickshell( |\$)" || true
    fi
    # The bar first, on the new files, and wait until it answers: mango's
    # reload below runs the exec-once lines again (0.14), whose `bar start`
    # is a no-op only once this bar is registered; started side by side,
    # both would start a bar. mango starts it, so it lands in the login
    # session (the network and power actions need that; this terminal runs
    # in a scope of its own).
    oldbar=" $(pgrep -x -u "$USER" qs | tr '\n' ' ')"
    "$SHARE_DIR/scripts/mango-ipc" dispatch "spawn,$SHARE_DIR/scripts/bar restart" >/dev/null 2>&1 \
        || ("$SHARE_DIR/scripts/bar" restart >/dev/null 2>&1 &)
    for _ in $(seq 1 50); do
        newbar=""
        for p in $(pgrep -x -u "$USER" qs); do
            case "$oldbar" in *" $p "*) ;; *) newbar=$p ;; esac
        done
        [ -n "$newbar" ] && qs -p "$SHARE_DIR/quickshell" ipc show >/dev/null 2>&1 && break
        sleep 0.2
    done
    sleep 1
    "$SHARE_DIR/scripts/mango-ipc" dispatch reload_config >/dev/null 2>&1 || warn "mango did not reload config.conf; Super + Shift + r"
fi

# Done
echo -e "\n${GREEN}Installation complete!${NC}"
if [ "$LIVE" = true ] && [ -n "$BACKUP_DIR" ]; then
    # the session's environment (env) is read at login: kitty's config and
    # colors moved with the layout
    echo "1. mango reloaded and the bar restarted; log out and back in once so terminals find their new colors"
elif [ "$LIVE" = true ]; then
    echo "1. mango reloaded and the bar restarted: the update is live"
elif [ "$DM_AT_START" = active ] || [ "$ONLY_CONFIG" = true ]; then
    echo "1. Log out (fully — the render group applies at next login) and select 'Mango' from your display manager"
    echo "   (no sound or screen sharing afterwards? reboot once: services installed just now start with a fresh login)"
else
    echo "1. Reboot, then select 'Mango' at the login screen"
    echo "   (a reboot, not a logout: the login screen, sound and screen sharing all start with it)"
fi
echo "2. Press Super + / for keybindings"
echo "3. Super + Space for application launcher"
echo "4. Super + Shift + p for the wallpaper picker (re-themes the desktop from the image)"
echo "5. Super + Shift + m for the command menu"
[ -f "$HOME/QUICKSTART-mango.md" ] && echo "6. See ~/QUICKSTART-mango.md for a quick reference"
echo "To update later: 'Update setup' in the command menu (or cd $SCRIPT_DIR && git pull && ./install.sh)"
echo "Installation log: $LOG_FILE"

# NetworkManager leaves alone any interface Debian's installer wrote into
# /etc/network/interfaces, which a netinst without a desktop does for the
# wired one. The connection works but the bar can't see it. Say so, with
# the fix: changing a machine's network setup is its owner's call.
# The test is narrow on purpose: the interface carrying the default route
# is the one NetworkManager calls unmanaged. A second, unused port listed
# in that file is nobody's problem.
dev=$(ip route show default 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
if [ -n "$dev" ] \
   && nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep -qx "$dev:unmanaged" \
   && grep -qsE "^[[:space:]]*iface[[:space:]]+${dev}[[:space:]]" /etc/network/interfaces /etc/network/interfaces.d/*; then
    echo
    warn "Network: $dev is set up in /etc/network/interfaces, so NetworkManager leaves it alone."
    echo "  Your connection works, but the bar's network icon will show offline and the"
    echo "  network app will be empty. To hand a DHCP interface over to NetworkManager:"
    echo "    sudo sed -i -E '/^(auto|allow-hotplug|iface) +$dev( |\$)/ s/^/#/' /etc/network/interfaces"
    echo "    sudo reboot"
    echo "  (a static address you set by hand belongs in NetworkManager first: nmtui)"
fi
