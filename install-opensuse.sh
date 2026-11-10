#!/bin/bash

# mango_opensuse installer — openSUSE Tumbleweed port of install.sh.
#
# Differences from upstream's install.sh (Drew's original, for Debian):
#   * packages come from the official Tumbleweed repos (zypper), no butterrepo
#   * mangowc 0.14.4 (with butterrepo's two patches), scenefx 0.4.1, quickshell,
#     butterpal and butterview are built from source into /usr/local
#   * Orchis-Nord-Template and the Colloid Dark icon schemes are built from
#     vinceliuice's upstream tags into /usr/share/{themes,icons}
#   * the login entry goes to /usr/share/wayland-sessions (SDDM is kept)
#   * the bar's apt commands are rewritten to zypper in the installed copy
#   * no LightDM, no optional-tools prompt, no Debian network fixup
#
# --only-config: the setup's files, plus any packages added to the list since
# (never removing any). --rebuild: rebuild the source-built pieces even when
# they are up to date (do this after Tumbleweed moves Qt or wlroots, if the
# installer didn't already notice).

set -e

ONLY_CONFIG=false
REBUILD=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --only-config) ONLY_CONFIG=true; shift ;;
        --rebuild)     REBUILD=true; shift ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "  --only-config   Config files, plus packages added to the list since (never removes any)"
            echo "  --rebuild       Rebuild mangowc, scenefx, quickshell, butterpal, butterview and themes"
            echo "  --help          Show this help message"
            exit 0
            ;;
        *) echo "Unknown option: $1"; echo "Use --help for usage information"; exit 1 ;;
    esac
done

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mango"
KEPT_NEW=()
TEMP_DIR="/tmp/mango_$$"
LOG_FILE="$HOME/mango-install.log"
PREFIX=/usr/local
BUILD_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/mangobutter-build"
STAMP_DIR="$PREFIX/share/mangobutter/built"

# Pinned upstream versions (the same ones butterrepo ships, except quickshell:
# 0.3.2 is the first release that builds against Tumbleweed's Qt 6.12)
MANGO_REF=0.14.4
SCENEFX_REF=0.4.1
QUICKSHELL_REF=v0.3.2
BUTTERPAL_REF=v0.3.2
BUTTERVIEW_REF=v0.4.5
ZIG_VERSION=0.16.0
ORCHIS_TAG=2026-07-07
COLLOID_TAG=2026-08-10
DEB_BUILDERS_COMMIT=5cd20720d0c8945286e23bf533dd43c216dd9b43   # mangowc patches + mango-session

# Logging and cleanup
exec > >(tee -a "$LOG_FILE") 2>&1
SUDO_KEEPALIVE=""
trap 'rm -rf "$TEMP_DIR"; [ -n "$SUDO_KEEPALIVE" ] && kill "$SUDO_KEEPALIVE" 2>/dev/null' EXIT

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

die() { echo -e "${RED}ERROR: $*${NC}" >&2; exit 1; }
warn() { echo -e "${YELLOW}WARNING: $*${NC}" >&2; }
msg() { echo -e "${CYAN}$*${NC}"; }

[ "$EUID" -eq 0 ] && die "Run this as your normal user, not root (it uses sudo where needed)"

if [ "$ONLY_CONFIG" = false ]; then
    # shellcheck source=/dev/null
    . /etc/os-release 2>/dev/null || die "Cannot read /etc/os-release to verify OS"
    case "$ID" in
        opensuse-tumbleweed) ;;
        opensuse-slowroll) warn "Slowroll: untested, but should behave like Tumbleweed" ;;
        *) die "Unsupported OS: ${PRETTY_NAME:-unknown}. This installer targets openSUSE Tumbleweed (Leap's wlroots/Qt are too old)." ;;
    esac
fi

# an update keeps what setup-update printed above it
[ "$ONLY_CONFIG" = true ] || clear 2>/dev/null || true
printf '\033[1mmango_opensuse\033[0m\n\033[2mmango for openSUSE Tumbleweed · port of justaguy.dev/butter/mango\033[0m\n\n'

DM_AT_START=$(systemctl is-active display-manager 2>/dev/null || true)

# One sudo prompt up front, kept alive through the long builds
sudo -v || die "sudo is required"
( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 $$ 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE=$!

# ---------------------------------------------------------------------------
# Packages
# ---------------------------------------------------------------------------

# Runtime packages (upstream's list, by Tumbleweed name)
PACKAGES=(
    # compositor runtime (mangowc itself is built below)
    xwayland awww libwlroots-0_19
    gcc make
    # the bar and what backs its features
    rofi dunst libnotify-tools btop
    pamixer playerctl brightnessctl wlsunset power-profiles-daemon
    NetworkManager-applet qrencode
    bluez pulseaudio-utils xdg-utils pkexec python3
    # Wayland tools
    grim slurp swappy wl-clipboard cliphist
    wlr-randr swayidle wlopm qt6-declarative-imports libQt6Svg6 qt6-wayland
    xdg-desktop-portal-wlr xdg-desktop-portal-gtk
    xrdb xset
    # gtk tooling; polkit-gnome stands in for lxpolkit (see the shim below)
    nwg-look xsettingsd polkit-gnome glib2-tools
    # file manager
    thunar thunar-archive-plugin thunar-volman file-roller
    gvfs gvfs-backends gvfs-fuse dialog mtools samba-client cifs-utils unzip
    # audio
    pavucontrol python313-pulsemixer pipewire-pulseaudio wireplumber
    # utilities
    avahi acpi acpid upower
    fd xdg-user-dirs-gtk fastfetch
    gawk curl wget git xz fontconfig
    # apps upstream gets from butterscripts
    kitty geany MozillaFirefox
    # fonts (RobotoMono / SauceCodePro Nerd Fonts come from butterscripts below)
    google-noto-sans-fonts fontawesome-fonts google-noto-coloremoji-fonts nerdfonts-symbolsonly-fonts
)

# Yours, on top of the setup (gathered from ~/.bash_history). Part of
# PACKAGES so --only-config picks up anything added here later too.
PACKAGES+=(
    # editors and dotfiles
    git stow vim emacs
    # apps
    alacritty blueman flatpak
    # mise (from the mise repo, added below) — manages claude
    mise
    # OCR a screen region (~/.local/bin/ocr-region) and dictation typing
    tesseract-ocr tesseract-ocr-traineddata-eng wtype
    # scripts: CJK, Thai, Arabic, Khmer
    google-noto-sans-cjk-fonts
    google-noto-sans-thai-fonts google-noto-serif-thai-fonts
    google-noto-sans-arabic-fonts google-noto-naskharabic-fonts
    google-noto-sans-khmer-fonts google-noto-serif-khmer-fonts
)

# Flathub apps (system-wide, like the originals)
FLATPAKS=(
    io.github.focustimerhq.FocusTimer   # the bar's FocusPill talks to it over D-Bus
    org.telegram.desktop
)

# Build-only packages for the source-built pieces
BUILD_DEPS=(
    meson ninja cmake gcc-c++ pkgconf patch sassc
    # scenefx + mangowc
    wlroots-0_19-devel wayland-devel wayland-protocols-devel libinput-devel
    libxkbcommon-devel pcre2-devel cJSON-devel libpixman-1-0-devel libdrm-devel
    libgbm-devel Mesa-libEGL-devel Mesa-libGLESv2-devel libdisplay-info-devel
    libliftoff-devel seatd-devel systemd-devel libxcb-devel xcb-util-wm-devel
    xcb-util-renderutil-devel xwayland-devel
    # quickshell
    qt6-base-devel qt6-base-private-devel qt6-declarative-devel qt6-declarative-private-devel
    qt6-shadertools-devel qt6-svg-devel qt6-wayland-devel qt6-wayland-private-devel
    spirv-tools cli11-devel jemalloc-devel pipewire-devel pam-devel polkit-devel
    glib2-devel vulkan-devel libglvnd-devel
    # butterview
    SDL3-devel SDL3_image-devel SDL3_ttf-devel libjpeg8-devel dbus-1-devel python313-CairoSVG
)

ZYPPER=(sudo zypper --non-interactive install --auto-agree-with-licenses)

# Third-party repo for mise (both modes, so --only-config can install it)
if ! zypper lr -u 2>/dev/null | grep -q 'mise.jdx.dev'; then
    msg "Adding the mise repository..."
    sudo zypper addrepo -f https://mise.jdx.dev/rpm/mise.repo
    sudo zypper --gpg-auto-import-keys refresh mise-repo
fi

if [ "$ONLY_CONFIG" = false ]; then
    # IceWM: removed and locked so it never comes back with a pattern
    if rpm -q icewm >/dev/null 2>&1; then
        msg "Removing IceWM..."
        sudo zypper --non-interactive remove --clean-deps 'icewm*' || warn "IceWM not removed - sudo zypper rm --clean-deps 'icewm*'"
    fi
    zypper locks 2>/dev/null | grep -q 'icewm\*' || sudo zypper addlock 'icewm*'

    msg "Updating system (zypper dup — answer its prompts if it asks about conflicts)..."
    sudo zypper refresh
    sudo zypper dup || die "zypper dup failed - fix it (the messages above say why) and run the installer again"

    msg "Installing packages..."
    "${ZYPPER[@]}" "${PACKAGES[@]}" || die "Failed to install packages - zypper names the one it could not install above"
    msg "Installing build dependencies..."
    "${ZYPPER[@]}" "${BUILD_DEPS[@]}" || die "Failed to install build dependencies - zypper names the one it could not install above"

    sudo systemctl enable avahi-daemon acpid

    # GPU access: scenefx opens the render node directly at startup
    if ! id -nG "$USER" | grep -qw render; then
        msg "Adding $USER to the render group (GPU render node access)..."
        sudo usermod -aG render "$USER"
    fi

    # Seat management: with a display manager the seat belongs to logind
    if systemctl is-active --quiet seatd 2>/dev/null; then
        warn "seatd is running alongside logind — disabling it (mango uses logind for the seat)"
        sudo systemctl disable --now seatd
    fi
else
    # --only-config: packages added to the list since, one at a time
    missing=()
    for p in "${PACKAGES[@]}"; do
        rpm -q --whatprovides "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        msg "Installing packages added since your install: ${missing[*]}"
        for p in "${missing[@]}"; do
            "${ZYPPER[@]}" "$p" || warn "$p not installed - sudo zypper install $p"
        done
    fi
fi

# ---------------------------------------------------------------------------
# Flatpak: Flathub + your apps (both modes; already-installed apps are skipped)
# ---------------------------------------------------------------------------

if command -v flatpak >/dev/null; then
    msg "Setting up Flathub..."
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    missing=()
    for app in "${FLATPAKS[@]}"; do
        flatpak info --system "$app" >/dev/null 2>&1 || missing+=("$app")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        msg "Installing Flatpak apps: ${missing[*]}"
        sudo flatpak install --system --noninteractive -y flathub "${missing[@]}" \
            || warn "Some Flatpak apps not installed - sudo flatpak install flathub ${missing[*]}"
    fi
else
    warn "flatpak not installed - skipping Flathub apps"
fi

# mise: activate in bash and install claude (as you, not root)
if command -v mise >/dev/null; then
    grep -q 'mise activate bash' "$HOME/.bashrc" 2>/dev/null \
        || echo 'eval "$(mise activate bash)"' >> "$HOME/.bashrc"
    mise use -g claude@latest || warn "claude not installed via mise - mise use -g claude@latest"
fi

# ---------------------------------------------------------------------------
# Source builds (into /usr/local; stamped so a rerun skips what's current)
# ---------------------------------------------------------------------------

# Parallel jobs: one per ~1.5 GB of available RAM (quickshell's C++ is heavy;
# one job per core gets cc1plus OOM-killed on a 16-core / 8 GB machine)
JOBS=$(awk '/MemAvailable/ {j=int($2/1500000); print (j<1?1:j)}' /proc/meminfo)
[ "$JOBS" -gt "$(nproc)" ] && JOBS=$(nproc)
[ -n "${MANGO_JOBS:-}" ] && JOBS=$MANGO_JOBS

export PKG_CONFIG_PATH="$PREFIX/lib64/pkgconfig:$PREFIX/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

up_to_date() { [ "$REBUILD" = false ] && [ "$(cat "$STAMP_DIR/$1" 2>/dev/null)" = "$2" ]; }
stamp() { sudo mkdir -p "$STAMP_DIR" && echo "$2" | sudo tee "$STAMP_DIR/$1" >/dev/null; }
# fetch_src <dir> <url> <tag>
fetch_src() {
    rm -rf "${BUILD_ROOT:?}/$1"
    git -c advice.detachedHead=false clone -q --depth 1 --branch "$3" "$2" "$BUILD_ROOT/$1"
}

build_scenefx() {
    local id="$SCENEFX_REF wlroots-$WLR_VER"
    if up_to_date scenefx "$id" && [ -f "$PREFIX/lib64/pkgconfig/scenefx-0.4.pc" ]; then
        msg "scenefx $SCENEFX_REF is current"; return 0
    fi
    msg "Building scenefx $SCENEFX_REF..."
    fetch_src scenefx https://github.com/wlrfx/scenefx.git "$SCENEFX_REF"
    ( cd "$BUILD_ROOT/scenefx" \
      && meson setup build --buildtype=release --prefix="$PREFIX" --libdir=lib64 -Dexamples=false \
      && ninja -C build -j "$JOBS" && sudo ninja -C build install ) || return 1
    sudo ldconfig
    stamp scenefx "$id"
    FORCE_MANGO=true
}

build_mango() {
    local id="$MANGO_REF wlroots-$WLR_VER scenefx-$SCENEFX_REF patches-${DEB_BUILDERS_COMMIT:0:8}"
    if [ "${FORCE_MANGO:-false}" = false ] && up_to_date mangowc "$id" && [ -x "$PREFIX/bin/mango" ]; then
        msg "mangowc $MANGO_REF is current"; return 0
    fi
    msg "Building mangowc $MANGO_REF (with butterrepo's 12-tags and live-opacity patches)..."
    rm -rf "$BUILD_ROOT/deb-builders"
    git clone -q https://justaguy.dev/drew/deb-builders.git "$BUILD_ROOT/deb-builders" || return 1
    git -C "$BUILD_ROOT/deb-builders" -c advice.detachedHead=false checkout -q "$DEB_BUILDERS_COMMIT" \
        || warn "deb-builders commit $DEB_BUILDERS_COMMIT not found - using its main branch"
    fetch_src mango https://github.com/mangowm/mango.git "$MANGO_REF" || return 1
    ( cd "$BUILD_ROOT/mango" \
      && for p in "$BUILD_ROOT"/deb-builders/mangowc/patches/*.patch; do patch -p1 < "$p" || exit 1; done \
      && meson setup build --buildtype=release --prefix="$PREFIX" --libdir=lib64 -Dxwayland=enabled \
      && ninja -C build -j "$JOBS" && sudo ninja -C build install ) || return 1

    # Login wrapper (sources ~/.config/mango/env, then execs mango)
    sudo install -Dm755 "$BUILD_ROOT/deb-builders/mangowc/files/mango-session" "$PREFIX/bin/mango-session"
    sudo sed -i "s|^exec /usr/bin/mango |exec $PREFIX/bin/mango |" "$PREFIX/bin/mango-session"
    grep -q "^exec $PREFIX/bin/mango " "$PREFIX/bin/mango-session" || return 1
    # qs, butterpal etc. live in /usr/local/bin: make sure the session can find them
    # shellcheck disable=SC2016
    sudo sed -i '/^ENV_FILE=/i export PATH="/usr/local/bin:$PATH"' "$PREFIX/bin/mango-session"

    # Session entry where SDDM looks; drop the /usr/local copy so it isn't listed twice
    sudo install -d /usr/share/wayland-sessions
    sed "s|^Exec=.*|Exec=$PREFIX/bin/mango-session|" "$BUILD_ROOT/mango/assets/mango.desktop" \
        | sudo tee /usr/share/wayland-sessions/mango.desktop >/dev/null
    sudo rm -f "$PREFIX/share/wayland-sessions/mango.desktop"

    # Headless smoke test, as butterrepo's builder does (exit 124 = still running at timeout)
    if [ -d /dev/dri ]; then
        local rc=0
        ( cd /tmp && WLR_BACKENDS=headless WAYLAND_DISPLAY="wayland-smoke-$$" \
            timeout 4 "$PREFIX/bin/mango" -c "$BUILD_ROOT/mango/assets/config.conf" >"$BUILD_ROOT/mango-smoke.log" 2>&1 ) || rc=$?
        [ "$rc" -eq 124 ] && msg "mango smoke test OK" \
            || warn "mango smoke test exited $rc - see $BUILD_ROOT/mango-smoke.log"
    fi
    stamp mangowc "$id"
}

build_quickshell() {
    local qt id
    qt=$(rpm -q --qf '%{VERSION}' libQt6Core6 2>/dev/null)
    id="$QUICKSHELL_REF qt-$qt"
    if up_to_date quickshell "$id" && [ -x "$PREFIX/bin/qs" ]; then
        msg "quickshell $QUICKSHELL_REF is current (Qt $qt)"; return 0
    fi
    msg "Building quickshell $QUICKSHELL_REF against Qt $qt with $JOBS jobs (the longest step)..."
    fetch_src quickshell https://git.outfoxxed.me/quickshell/quickshell.git "$QUICKSHELL_REF" \
        || fetch_src quickshell https://github.com/quickshell-mirror/quickshell.git "$QUICKSHELL_REF" || return 1
    ( cd "$BUILD_ROOT/quickshell" \
      && cmake -GNinja -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
            -DCRASH_HANDLER=OFF -DDISTRIBUTOR="mango_opensuse (source build)" \
      && cmake --build build -j "$JOBS" && sudo cmake --install build ) || return 1
    stamp quickshell "$id"
}

build_butterpal() {
    if up_to_date butterpal "$BUTTERPAL_REF" && [ -x "$PREFIX/bin/butterpal" ]; then
        msg "butterpal $BUTTERPAL_REF is current"; return 0
    fi
    msg "Building butterpal $BUTTERPAL_REF..."
    fetch_src butterpal https://justaguy.dev/drew/butterpal.git "$BUTTERPAL_REF" || return 1
    ( cd "$BUILD_ROOT/butterpal" && make VERSION="${BUTTERPAL_REF#v}" \
      && sudo make install PREFIX="$PREFIX" ) || return 1
    stamp butterpal "$BUTTERPAL_REF"
}

build_butterview() {
    if up_to_date butterview "$BUTTERVIEW_REF" && [ -x "$PREFIX/bin/butterview" ]; then
        msg "butterview $BUTTERVIEW_REF is current"; return 0
    fi
    msg "Building butterview $BUTTERVIEW_REF (Zig $ZIG_VERSION, downloaded into the build folder)..."
    local zig="$BUILD_ROOT/zig-x86_64-linux-$ZIG_VERSION"
    if [ ! -x "$zig/zig" ]; then
        wget -qO "$BUILD_ROOT/zig.tar.xz" "https://ziglang.org/download/$ZIG_VERSION/zig-x86_64-linux-$ZIG_VERSION.tar.xz" \
            && tar -xf "$BUILD_ROOT/zig.tar.xz" -C "$BUILD_ROOT" && rm -f "$BUILD_ROOT/zig.tar.xz" || return 1
    fi
    fetch_src butterview https://justaguy.dev/drew/butterview.git "$BUTTERVIEW_REF" || return 1
    ( cd "$BUILD_ROOT/butterview" \
      && "$zig/zig" build -Doptimize=ReleaseSafe -Dversion="${BUTTERVIEW_REF#v}" \
      && sudo install -Dm755 zig-out/bin/butterview "$PREFIX/bin/butterview" \
      && sudo install -Dm644 data/butterview.1 "$PREFIX/share/man/man1/butterview.1" \
      && sudo install -Dm644 data/butterview.desktop "$PREFIX/share/applications/butterview.desktop" \
      && sudo install -Dm644 data/butterview.svg "$PREFIX/share/icons/hicolor/scalable/apps/butterview.svg" \
      && for s in 48 128 256; do
             python3 -m cairosvg -W $s -H $s -o "butterview-$s.png" data/butterview.svg \
               && sudo install -Dm644 "butterview-$s.png" "$PREFIX/share/icons/hicolor/${s}x${s}/apps/butterview.png"
         done ) || return 1
    stamp butterview "$BUTTERVIEW_REF"
}

# Orchis-Nord-Template: upstream's plain-Nord build under its own name, the
# source scripts/wallpaper-theme recolors (same recipe as butterrepo's package)
build_orchis() {
    if up_to_date orchis "$ORCHIS_TAG" && [ -d /usr/share/themes/Orchis-Nord-Template ]; then
        msg "Orchis-Nord-Template ($ORCHIS_TAG) is current"; return 0
    fi
    msg "Building Orchis-Nord-Template from Orchis $ORCHIS_TAG..."
    fetch_src orchis https://github.com/vinceliuice/Orchis-theme.git "$ORCHIS_TAG" || return 1
    local out="$BUILD_ROOT/orchis-out"
    rm -rf "$out"; mkdir -p "$out"
    ( cd "$BUILD_ROOT/orchis" && ./install.sh -d "$out" -c dark -s standard -t default --tweaks nord < <(yes) >/dev/null 2>&1 ) || return 1
    [ -d "$out/Orchis-Dark-Nord" ] || return 1
    sed -i 's/Orchis-Dark-Nord/Orchis-Nord-Template/g' "$out/Orchis-Dark-Nord/index.theme"
    grep -qi '#242932' "$out/Orchis-Dark-Nord/gtk-3.0/gtk.css" \
        || { warn "Orchis $ORCHIS_TAG lacks Nord's #242932 - wallpaper-theme won't recolor it"; return 1; }
    sudo rm -rf /usr/share/themes/Orchis-Nord-Template
    sudo cp -a "$out/Orchis-Dark-Nord" /usr/share/themes/Orchis-Nord-Template
    stamp orchis "$ORCHIS_TAG"
}

# The Colloid Dark schemes wallpaper-theme's hue matcher picks from (same list
# as butterrepo's colloid-icon-theme-butter; only the -Dark trees are kept)
build_colloid() {
    if up_to_date colloid "$COLLOID_TAG" && [ -d /usr/share/icons/Colloid-Nord-Dark ]; then
        msg "Colloid icons ($COLLOID_TAG) are current"; return 0
    fi
    msg "Building Colloid icon schemes from $COLLOID_TAG..."
    fetch_src colloid https://github.com/vinceliuice/Colloid-icon-theme.git "$COLLOID_TAG" || return 1
    local stage="$BUILD_ROOT/colloid-out" v dark base link target real
    rm -rf "$stage"; mkdir -p "$stage"
    for v in "-s default" "-t orange" "-t purple" "-t pink" "-s gruvbox" "-s everforest" \
             "-s nord" "-s dracula" "-s catppuccin" "-t grey -s dracula"; do
        # shellcheck disable=SC2086
        ( cd "$BUILD_ROOT/colloid" && ./install.sh -d "$stage" $v >/dev/null 2>&1 ) || { warn "Colloid install.sh failed for $v"; return 1; }
    done
    # Dark trees link some folders into their Light sibling: make those real copies
    for dark in "$stage"/*-Dark; do
        base=$(basename "${dark%-Dark}")
        while IFS= read -r link; do
            target=$(readlink "$link")
            case $target in
                */"$base-Light"/*)
                    real=$(cd "$(dirname "$link")/$(dirname "$target")" && pwd)/$(basename "$target")
                    rm "$link"; cp -a "$real" "$link" ;;
            esac
        done < <(find "$dark" -type l)
    done
    for dark in "$stage"/*-Dark; do
        sudo rm -rf "/usr/share/icons/$(basename "$dark")"
        sudo cp -a "$dark" /usr/share/icons/
        sudo gtk-update-icon-cache -qf "/usr/share/icons/$(basename "$dark")" 2>/dev/null || true
    done
    stamp colloid "$COLLOID_TAG"
}

if [ "$ONLY_CONFIG" = false ]; then
    mkdir -p "$BUILD_ROOT"
    WLR_VER=$(rpm -q --qf '%{VERSION}' libwlroots-0_19 2>/dev/null) || die "libwlroots-0_19 is not installed"
    FORCE_MANGO=false
    build_scenefx    || die "scenefx build failed - see the messages above"
    build_mango      || die "mangowc build failed - see the messages above"
    build_quickshell || die "quickshell build failed - see the messages above"
    build_butterpal  || die "butterpal build failed - see the messages above"
    build_butterview || warn "butterview build failed - images will open in another viewer"
    build_orchis     || warn "Orchis-Nord-Template build failed - wallpaper picks won't re-theme GTK"
    build_colloid    || warn "Colloid icon build failed - wallpaper picks won't switch icon colors"

    # Debian names the configs call, mapped to their Tumbleweed equivalents.
    # Shims, not edits: keybinds.conf/autostart.conf are yours and stay as shipped.
    POLKIT_AGENT=$(rpm -ql polkit-gnome 2>/dev/null | grep 'polkit-gnome-authentication-agent-1$' | head -1)
    [ -n "$POLKIT_AGENT" ] && printf '#!/bin/sh\nexec %s "$@"\n' "$POLKIT_AGENT" \
        | sudo tee "$PREFIX/bin/lxpolkit" >/dev/null && sudo chmod 755 "$PREFIX/bin/lxpolkit"
    printf '#!/bin/sh\nexec firefox "$@"\n' | sudo tee "$PREFIX/bin/firefox-esr" >/dev/null
    sudo chmod 755 "$PREFIX/bin/firefox-esr"
    sudo ldconfig
fi

# ---------------------------------------------------------------------------
# Configuration (unchanged from install.sh apart from the openSUSE patch step)
# ---------------------------------------------------------------------------

SHARE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mango"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mango"
mkdir -p "$SHARE_DIR" "$CONFIG_DIR" "$STATE_DIR/shipped"

# An install with the old one-folder layout keeps everything in $CONFIG_DIR
BACKUP_DIR=""
if [ -d "$CONFIG_DIR/quickshell" ]; then
    BACKUP_DIR="$CONFIG_DIR.bak.$(date +%Y%m%d-%H%M%S)"
    while [ -e "$BACKUP_DIR" ]; do BACKUP_DIR="$BACKUP_DIR-1"; done
    msg "Config with the old one-folder layout found - moving it to $BACKUP_DIR and carrying yours over"
    mv "$CONFIG_DIR" "$BACKUP_DIR"
    mkdir -p "$CONFIG_DIR"
    for f in keybinds.conf local.conf env; do
        [ -f "$BACKUP_DIR/$f" ] && cp "$BACKUP_DIR/$f" "$CONFIG_DIR/$f"
    done
    [ -d "$BACKUP_DIR/wallpaper" ] && mv "$BACKUP_DIR/wallpaper" "$CONFIG_DIR/wallpaper"
    for f in theme.conf polybar/colors.ini rofi/colors.rasi dunst/dunstrc \
             bar-height bar-scale popup-scale tag-icons mango-gaps mango-effects \
             lock-idle lock-style pomodoro weather-location weather-units \
             launcher-history displays.conf; do
        [ -f "$BACKUP_DIR/$f" ] && [ ! -e "$STATE_DIR/$(basename "$f")" ] && cp "$BACKUP_DIR/$f" "$STATE_DIR/$(basename "$f")"
    done
    [ -f "$BACKUP_DIR/kitty/current-theme.conf" ] && [ ! -e "$STATE_DIR/kitty-theme.conf" ] && cp "$BACKUP_DIR/kitty/current-theme.conf" "$STATE_DIR/kitty-theme.conf"
    if [ -f "$STATE_DIR/theme.conf" ] && ! grep -q '^exec-once=awww img' "$STATE_DIR/theme.conf"; then
        grep '^exec-once=awww img' "$BACKUP_DIR/config.conf" >> "$STATE_DIR/theme.conf" 2>/dev/null || true
    fi
    for f in keybinds.conf env; do
        # shellcheck disable=SC2016
        [ -f "$CONFIG_DIR/$f" ] && sed -i 's|\.config/mango/scripts/|.local/share/mango/scripts/|g; s|\.config/mango/quickshell|.local/share/mango/quickshell|g; s|^KITTY_CONFIG_DIRECTORY=.*|KITTY_CONFIG_DIRECTORY=${XDG_DATA_HOME:-$HOME/.local/share}/mango/kitty|' "$CONFIG_DIR/$f"
    done
fi

# The setup's own files: replaced wholesale
msg "Setting up configuration..."
rm -rf "$SHARE_DIR"
mkdir -p "$SHARE_DIR"
cp -r "$SCRIPT_DIR"/share/* "$SHARE_DIR"/ || die "Failed to copy the setup's files"
chmod +x "$SHARE_DIR"/scripts/*

# openSUSE: the bar's package commands, in the installed copy only (the repo
# stays as upstream ships it, so 'Update setup' can still git pull)
msg "Adapting the bar's apt commands to zypper..."
mapfile -t APT_FILES < <(grep -rlE 'apt(-get)? |apt list|install\.sh --only-config' "$SHARE_DIR" 2>/dev/null || true)
for f in "${APT_FILES[@]}"; do
    sed -i \
        -e "s#apt-get -s -o Debug::NoLocking=1 dist-upgrade 2>/dev/null | grep -c '^Inst'#zypper -q --no-refresh list-updates 2>/dev/null | grep -c '^v '#" \
        -e 's#sudo apt update && sudo apt full-upgrade#sudo zypper refresh \&\& sudo zypper dup#g' \
        -e 's#sudo apt update && apt list --upgradable#sudo zypper refresh \&\& zypper list-updates#g' \
        -e 's#sudo apt install #sudo zypper install #g' \
        -e 's#\./install\.sh --only-config#./install-opensuse.sh --only-config#g' \
        "$f"
done
grep -rq "apt-get -s" "$SHARE_DIR" && warn "the bar's update counter still calls apt-get - upstream changed it; it will show 0"

# The user's files, dpkg's way. "Never edited" is known from the copy of
# what was shipped last time, kept in the state folder.
for f in config.conf autostart.conf keybinds.conf rules.conf local.conf env; do
    ours="$SCRIPT_DIR/config/$f"; theirs="$CONFIG_DIR/$f"; prev="$STATE_DIR/shipped/$f"
    if [ ! -f "$theirs" ]; then
        cp "$ours" "$theirs"
    elif cmp -s "$theirs" "$ours"; then
        :
    elif [ -f "$prev" ] && cmp -s "$theirs" "$prev"; then
        cp "$ours" "$theirs"
    elif [ -f "$prev" ] && cmp -s "$ours" "$prev"; then
        :
    elif [ -f "$theirs.new" ] && cmp -s "$theirs.new" "$ours"; then
        :
    else
        cp "$ours" "$theirs.new"
        KEPT_NEW+=("$f")
    fi
done
if [ ${#KEPT_NEW[@]} -gt 0 ]; then
    msg "Kept your ${KEPT_NEW[*]}; the new defaults are beside as .new"
fi
PREV_COMMIT=$(cat "$STATE_DIR/shipped/commit" 2>/dev/null || true)
cp "$SCRIPT_DIR"/config/{config.conf,autostart.conf,keybinds.conf,rules.conf,local.conf,env} "$STATE_DIR/shipped/"
if git -C "$SCRIPT_DIR" rev-parse HEAD >/dev/null 2>&1; then
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
grep -q 'autostart\.conf' "$CONFIG_DIR/config.conf" || sed -i '/^source=.*defaults\.conf/a source=~/.config/mango/autostart.conf' "$CONFIG_DIR/config.conf"
grep -q 'rules\.conf' "$CONFIG_DIR/config.conf" || sed -i '/^source=.*keybinds\.conf/a source=~/.config/mango/rules.conf' "$CONFIG_DIR/config.conf"
for f in autostart.conf rules.conf; do
    grep -qF "$f" "$CONFIG_DIR/config.conf" || warn "$CONFIG_DIR/config.conf does not read $f - add source=~/.config/mango/$f (see $SCRIPT_DIR/config/config.conf)"
done
# shellcheck disable=SC2016
grep -q '^MANGO_STATE_DIR=' "$CONFIG_DIR/env" || printf '\nMANGO_STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/mango\n' >> "$CONFIG_DIR/env"

# Generated files: replaced while they still equal what was shipped last time
mkdir -p "$STATE_DIR/shipped/state"
generated() {        # <ours> <name> <path in the repo at the old commit>
    local ours="$1" theirs="$STATE_DIR/$2" prev="$STATE_DIR/shipped/state/$2"
    if [ ! -e "$theirs" ]; then
        cp "$ours" "$theirs"
    elif [ -f "$prev" ]; then
        cmp -s "$theirs" "$prev" && cp "$ours" "$theirs"
    elif [ -n "$PREV_COMMIT" ] && git -C "$SCRIPT_DIR" show "$PREV_COMMIT:$3" 2>/dev/null | cmp -s - "$theirs"; then
        cp "$ours" "$theirs"
    fi
    cp "$ours" "$prev"
}
for f in "$SCRIPT_DIR"/state/*; do
    generated "$f" "$(basename "$f")" "state/$(basename "$f")"
done
generated "$SHARE_DIR/dunst/dunstrc" dunstrc share/dunst/dunstrc

[ -x "$PREFIX/bin/mango-session" ] || warn "mango-session is missing - $CONFIG_DIR/env won't be sourced at login (run without --only-config)"

# VM: software cursor
if systemd-detect-virt -q 2>/dev/null; then
    msg "Virtual machine detected ($(systemd-detect-virt)) - enabling software cursor"
    sed -i 's|^#WLR_NO_HARDWARE_CURSORS=1$|WLR_NO_HARDWARE_CURSORS=1|' "$CONFIG_DIR/env"
fi

if [ ! -e ~/.config/dunst/dunstrc ] || [ -L ~/.config/dunst/dunstrc ]; then
    mkdir -p ~/.config/dunst
    ln -sfn "$STATE_DIR/dunstrc" ~/.config/dunst/dunstrc
fi
if [ ! -e ~/.config/swappy/config ] || [ -L ~/.config/swappy/config ]; then
    mkdir -p ~/.config/swappy
    ln -sfn "$SHARE_DIR/swappy/config" ~/.config/swappy/config
fi

command -v xdg-user-dirs-update >/dev/null && xdg-user-dirs-update
if [ "$ONLY_CONFIG" = false ] && command -v xdg-mime >/dev/null; then
    xdg-mime default thunar.desktop inode/directory
    xdg-mime default butterview.desktop \
        image/jpeg image/png image/gif image/webp image/avif image/jxl image/tiff image/bmp image/svg+xml
fi
if [ "$(readlink ~/.config/butterview/wallpaper)" = "$SHARE_DIR/butterview/wallpaper" ]; then
    rm -f ~/.config/butterview/wallpaper
fi
mkdir -p ~/Screenshots

if [ "$ONLY_CONFIG" = false ] && [ -f "$SCRIPT_DIR/QUICKSTART.md" ]; then
    cp "$SCRIPT_DIR/QUICKSTART.md" "$HOME/QUICKSTART-mango.md"
fi
if [ "$ONLY_CONFIG" = false ] && [ -f "$SCRIPT_DIR/nvidia-setup.sh" ]; then
    cp "$SCRIPT_DIR/nvidia-setup.sh" "$HOME/nvidia-setup.sh"
    chmod +x "$HOME/nvidia-setup.sh"
fi

# butterscripts that are distro-neutral once their prerequisites are present
# (they only call apt when something is missing, and everything is installed above)
BUTTERSCRIPTS=https://justaguy.dev/drew/butterscripts/raw/branch/main
get_script() {
    local script
    script=$(wget -qO- "$BUTTERSCRIPTS/$1") || return
    bash -s -- "${@:2}" <<< "$script"
}

if [ "$ONLY_CONFIG" = false ]; then
    mkdir -p "$TEMP_DIR" && cd "$TEMP_DIR"

    msg "Installing Nerd Fonts (RobotoMono, SauceCodePro, Symbols)..."
    get_script "theming/install_nerdfonts.sh" || warn "Font installation failed - you can install fonts manually later"

    msg "Applying the GTK and icon themes..."
    get_script "theming/install_wallpaper_theme.sh" || warn "Theme setup failed - pick a wallpaper later to theme GTK"

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

    if [ ! -f /run/host/container-manager ] && [ -d /sys/class/drm ]; then
        msg "Checking for NVIDIA GPU configuration..."
        bash "$SCRIPT_DIR/nvidia-setup.sh" || warn "NVIDIA setup skipped"
    fi
else
    msg "Skipping builds and external tools (--only-config mode)"
fi

DEFAULT_WALLPAPER=mangobutter-journey.png
if [ ! -f "$CONFIG_DIR/wallpaper/$DEFAULT_WALLPAPER" ]; then
    mkdir -p "$CONFIG_DIR/wallpaper"
    wget -qO "$CONFIG_DIR/wallpaper/$DEFAULT_WALLPAPER" "https://raw.githubusercontent.com/drewgrif/wallpapers/main/$DEFAULT_WALLPAPER" \
        || { rm -f "$CONFIG_DIR/wallpaper/$DEFAULT_WALLPAPER"; warn "could not fetch the default wallpaper ($DEFAULT_WALLPAPER); pick one from the bar"; }
fi

# Run from inside the session (Update setup): make the new files live now
LIVE=false
if [ "$ONLY_CONFIG" = true ] && [ -n "${WAYLAND_DISPLAY:-}" ] && pgrep -x -u "$USER" mango >/dev/null 2>&1; then
    LIVE=true
    if [ -n "$BACKUP_DIR" ]; then
        pkill -u "$USER" -f "^qs -p $CONFIG_DIR/quickshell( |\$)" || true
    fi
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

# Session target + portal choice. Tumbleweed's xdg-desktop-portal.service is
# Requisite=graphical-session.target, which only a session manager starts;
# mango-session.target binds it (autostart.conf starts it before restarting
# the portals). mango-portals.conf routes file dialogs to the gtk portal
# (it declares UseIn=gnome only) and screen sharing to wlr. Without both,
# flatpak apps like Telegram get a file picker that only sees their sandbox.
install -Dm644 "$SCRIPT_DIR/session/mango-session.target" "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/mango-session.target"
install -Dm644 "$SCRIPT_DIR/session/mango-portals.conf" "${XDG_CONFIG_HOME:-$HOME/.config}/xdg-desktop-portal/mango-portals.conf"
systemctl --user daemon-reload 2>/dev/null || true
# An autostart.conf kept from before this fix: add the target to its portal line
if [ -f "$CONFIG_DIR/autostart.conf" ] && ! grep -q 'mango-session\.target' "$CONFIG_DIR/autostart.conf"; then
    if grep -q '^exec-once=dbus-update-activation-environment .*systemctl --user restart xdg-desktop-portal' "$CONFIG_DIR/autostart.conf"; then
        sed -i '/^exec-once=dbus-update-activation-environment /s#&& systemctl --user restart xdg-desktop-portal#\&\& systemctl --user start mango-session.target \&\& systemctl --user restart xdg-desktop-portal#' "$CONFIG_DIR/autostart.conf"
        msg "Added mango-session.target to your autostart.conf (portals need it)"
    else
        warn "autostart.conf: start mango-session.target before the portals (see the shipped autostart.conf), or flatpak file dialogs stay sandboxed"
    fi
fi

# First-run setup: hostname, git identity, ssh-agent, SSH key for Codeberg/
# GitHub/GitLab, zypper dup. Files are refreshed on every run; it is armed
# (runs in a terminal at next login) only until it has once completed.
FR_SRC="$SCRIPT_DIR/first-run"
FR_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/mango"
if [ -d "$FR_SRC" ]; then
    install -Dm755 "$FR_SRC/mango-first-run" "$HOME/.local/bin/mango-first-run"
    mkdir -p "$CONFIG_DIR/first-run.d"
    install -m644 "$FR_SRC"/first-run.d/*.sh "$CONFIG_DIR/first-run.d/"
    install -Dm644 "$FR_SRC/ssh-agent.service" "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/ssh-agent.service"
    if [ ! -f "$FR_STATE/first-run.done" ]; then
        "$HOME/.local/bin/mango-first-run" --install >/dev/null
        FIRST_RUN_ARMED=true
    fi
fi

# Done
echo -e "\n${GREEN}Installation complete!${NC}"
[ "${FIRST_RUN_ARMED:-}" = true ] && echo "0. At your next login a terminal opens for one-time setup: hostname, git, SSH key, GitHub/GitLab/Codeberg, system update"
if [ "$LIVE" = true ] && [ -n "$BACKUP_DIR" ]; then
    echo "1. mango reloaded and the bar restarted; log out and back in once so terminals find their new colors"
elif [ "$LIVE" = true ]; then
    echo "1. mango reloaded and the bar restarted: the update is live"
elif [ "$DM_AT_START" = active ] || [ "$ONLY_CONFIG" = true ]; then
    echo "1. Log out (fully — the render group applies at next login) and pick 'Mango' in SDDM's session menu"
    echo "   (SDDM autologin goes straight to Plasma: log out from it to reach the session menu)"
else
    echo "1. Reboot, then select 'Mango' at the login screen"
fi
echo "2. Press Super + / for keybindings"
echo "3. Super + Space for application launcher"
echo "4. Super + Shift + p for the wallpaper picker (re-themes the desktop from the image)"
echo "5. Super + Shift + m for the command menu"
[ -f "$HOME/QUICKSTART-mango.md" ] && echo "6. See ~/QUICKSTART-mango.md for a quick reference"
echo "To update later: 'Update setup' in the command menu (or cd $SCRIPT_DIR && git pull && ./install-opensuse.sh)"
echo "After a big Tumbleweed snapshot (new Qt or wlroots), if the bar or mango won't start: ./install-opensuse.sh --rebuild"
echo "Source builds live in $BUILD_ROOT; installation log: $LOG_FILE"
