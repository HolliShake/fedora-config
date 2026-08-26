#!/usr/bin/env bash
# =============================================================================
#  CachyOSXDev — penguins-eggs installer generator for a running CachyOS
#
#  Rebrands the official CachyOS Calamares branding to "CachyOSXDev" and wires
#  it into penguins-eggs so you can remaster your running system into your own
#  bootable, installable ISO.
#
#  Usage (as root):
#    sudo ./cachyos-eggs.sh             # install tools + branding (no ISO yet)
#    sudo ./cachyos-eggs.sh --remaster  # ... then produce the ISO with eggs
#    sudo ./cachyos-eggs.sh --clean     # tear down the eggs remaster workspace
#    sudo ./cachyos-eggs.sh --help
#
#  References:
#    - CachyOS official branding: CachyOS/cachyos-calamares
#      (src/branding/cachyos/branding.desc)
#    - penguins-eggs: pieroproietti/penguins-eggs
# =============================================================================
set -euo pipefail

# --- Color output ------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Log helpers write to stderr so they never pollute command substitution.
log()  { echo -e "${BLUE}[*]${NC} $*" >&2; }
ok()   { echo -e "${GREEN}[+]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[!]${NC} $*" >&2; }
err()  { echo -e "${RED}[x]${NC} $*" >&2; }

# --- Configuration -----------------------------------------------------------
BRANDING_NAME="CachyOSXDev"      # the rebranded product name
BRANDING_VERSION="2026.08"       # version string shown by the installer

CALAMARES_BRANDING_ROOT="/etc/calamares/branding"
CALAMARES_SETTINGS="/etc/calamares/settings.conf"
CALAMARES_SETTINGS_BACKUP="${CALAMARES_SETTINGS}.backup"

# penguins-eggs "vendor branding overlay". eggs copies this directory over its
# generated Calamares branding at install time, so it must keep
# "componentName: eggs" (that is the target directory name it lands in).
EGGS_OVERLAY_DIR="/etc/penguins-eggs.d/brain.d/assets/calamares"

# Where the official CachyOS branding normally lives after installing
# cachyos-calamares. We copy ALL of it (logo, icon, QML sidebar, slideshow,
# slides, translations) so the result is visually identical to CachyOS.
OFFICIAL_BRANDING_PATHS=(
    "/usr/share/calamares/branding/cachyos"
    "/usr/lib/calamares/branding/cachyos"
    "/usr/local/share/calamares/branding/cachyos"
)

# Upstream fallback (only used if the local branding directory is missing).
CACHYOS_REPO="https://github.com/CachyOS/cachyos-calamares.git"
CACHYOS_REPO_BRANCH="cachyos"
CACHYOS_REPO_BRANDING="src/branding/cachyos"

# --- CLI flags ---------------------------------------------------------------
DO_REMASTER=false
DO_CLEAN=false

usage() {
    cat <<EOF
Usage: $0 [options]

  (none)         Install eggs + Calamares and set up CachyOSXDev branding
  --remaster     Also produce the installable ISO via 'eggs remaster'
  --clean        Tear down the eggs remaster workspace ('eggs destroy')
  --help         Show this help

This script must be run as root (sudo).
EOF
}

# --- Basic guards ------------------------------------------------------------
require_root() {
    if [ "$EUID" -ne 0 ]; then
        err "This script must be run as root. Please use: sudo $0"
        exit 1
    fi
}

require_cachyos() {
    if grep -qi 'cachyos' /etc/os-release 2>/dev/null; then
        local pretty
        pretty="$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')"
        ok "Detected CachyOS: ${pretty:-unknown}"
    else
        warn "This does not look like CachyOS (/etc/os-release). Continuing anyway."
    fi
}

# --- Tooling -----------------------------------------------------------------
install_calamares() {
    if command -v calamares >/dev/null 2>&1; then
        ok "Calamares found: $(command -v calamares)"
        return 0
    fi
    log "Installing Calamares..."
    pacman -S --needed --noconfirm calamares
    # The CachyOS branding package is what provides the assets we copy below.
    pacman -S --needed --noconfirm cachyos-calamares || \
        warn "Package 'cachyos-calamares' not available; upstream clone will be used if needed."
    ok "Calamares installed."
}

install_eggs() {
    if command -v eggs >/dev/null 2>&1; then
        ok "penguins-eggs already installed: $(command -v eggs)"
        return 0
    fi

    log "penguins-eggs not found — installing..."

    # 1) Try AUR helper as original user (makepkg fails if executed as root)
    local real_user="${SUDO_USER:-}"
    if [ -n "$real_user" ] && [ "$real_user" != "root" ]; then
        if command -v paru >/dev/null 2>&1; then
            sudo -u "$real_user" paru -S --noconfirm penguins-eggs || true
        elif command -v yay >/dev/null 2>&1; then
            sudo -u "$real_user" yay -S --noconfirm penguins-eggs || true
        fi
    fi

    if command -v eggs >/dev/null 2>&1; then
        ok "penguins-eggs installed."
        return 0
    fi

    # 2) Fallback: Install via npm (penguins-eggs is an npm package)
    warn "AUR install unavailable; installing penguins-eggs via npm..."
    pacman -S --needed --noconfirm nodejs npm
    npm install -g penguins-eggs

    if command -v eggs >/dev/null 2>&1; then
        ok "penguins-eggs built and installed."
    else
        err "Could not install penguins-eggs automatically."
        err "See https://github.com/pieroproietti/penguins-eggs for manual install."
        exit 1
    fi
}

# --- Branding ----------------------------------------------------------------
fetch_official_branding() {
    local src=""
    for p in "${OFFICIAL_BRANDING_PATHS[@]}"; do
        if [ -f "$p/branding.desc" ]; then
            src="$p"
            break
        fi
    done

    if [ -n "$src" ]; then
        ok "Using locally installed CachyOS branding: $src"
        echo "$src"
        return 0
    fi

    warn "Local CachyOS branding not found. Sparse-cloning from upstream..."
    if ! command -v git >/dev/null 2>&1; then
        err "git is required for the upstream fallback. Install it: sudo pacman -S git"
        exit 1
    fi

    local tmp
    tmp="$(mktemp -d)"
    git clone --depth 1 --filter=blob:none --sparse \
        --branch "$CACHYOS_REPO_BRANCH" "$CACHYOS_REPO" "$tmp" >/dev/null 2>&1
    git -C "$tmp" sparse-checkout set "$CACHYOS_REPO_BRANDING" >/dev/null 2>&1
    src="$tmp/$CACHYOS_REPO_BRANDING"

    if [ ! -f "$src/branding.desc" ]; then
        err "Failed to obtain the CachyOS branding from the upstream repo."
        exit 1
    fi
    ok "Cloned CachyOS branding from upstream."
    echo "$src"
}

write_branding_desc() {
    local component_name="$1"
    local dest_dir="$2"
    local desc_file="$dest_dir/branding.desc"

    log "Writing branding.desc (componentName: $component_name)"

    cat > "$desc_file" <<EOF
---
componentName:   $component_name

welcomeStyleCalamares:   false
welcomeExpandingLogo:    true

windowExpanding:    normal
windowSize: 1100px,520px
windowPlacement: center

sidebar: qml,bottom
navigation: widget

strings:
    productName:         $BRANDING_NAME
    shortProductName:    $BRANDING_NAME
    version:             $BRANDING_VERSION
    shortVersion:        $BRANDING_VERSION
    versionedName:       $BRANDING_NAME
    shortVersionedName:  $BRANDING_NAME
    bootloaderEntryName: $BRANDING_NAME

images:
    productLogo:         "logo.png"
    productIcon:         "icon.png"
    productWelcome:      "welcome.png"

style:
    SidebarBackground:        "#292F34"
    SidebarText:              "#FFFFFF"
    SidebarTextCurrent:       "#292F34"
    SidebarBackgroundCurrent: "#00CED1"

slideshow:              "show.qml"
slideshowAPI: 2

uploadServer :
    type :    "http"
    url :     "https://paste.cachyos.org"
    sizeLimit : -1
EOF
    ok "branding.desc written."
}

install_branding() {
    local src
    src="$(fetch_official_branding)"
    local standalone_dir="$CALAMARES_BRANDING_ROOT/$BRANDING_NAME"

    log "Installing standalone branding -> $standalone_dir"
    mkdir -p "$standalone_dir"
    cp -a "$src"/. "$standalone_dir"/
    write_branding_desc "$BRANDING_NAME" "$standalone_dir"

    log "Installing eggs branding overlay -> $EGGS_OVERLAY_DIR"
    mkdir -p "$EGGS_OVERLAY_DIR"
    cp -a "$src"/. "$EGGS_OVERLAY_DIR"/
    write_branding_desc "eggs" "$EGGS_OVERLAY_DIR"

    find "$standalone_dir" -type d -exec chmod 755 {} +
    find "$standalone_dir" -type f -exec chmod 644 {} +
    chown -R root:root "$standalone_dir"
    find "$EGGS_OVERLAY_DIR" -type d -exec chmod 755 {} +
    find "$EGGS_OVERLAY_DIR" -type f -exec chmod 644 {} +
    chown -R root:root "$EGGS_OVERLAY_DIR"
    ok "Permissions set (755/644 root:root)."
}

configure_calamares_settings() {
    [ -f "$CALAMARES_SETTINGS" ] || {
        warn "No settings file at $CALAMARES_SETTINGS — skipping."
        return 0
    }

    if [ ! -f "$CALAMARES_SETTINGS_BACKUP" ]; then
        cp "$CALAMARES_SETTINGS" "$CALAMARES_SETTINGS_BACKUP"
        ok "Backed up settings -> $CALAMARES_SETTINGS_BACKUP"
    fi

    if grep -q '^[[:space:]]*branding:' "$CALAMARES_SETTINGS"; then
        sed -i "s|^\([[:space:]]*branding:\).*|\1 $BRANDING_NAME|" "$CALAMARES_SETTINGS"
        ok "settings.conf branding -> $BRANDING_NAME"
    else
        warn "No 'branding:' key found in settings.conf. Add it manually:"
        echo "    echo 'branding: $BRANDING_NAME' >> $CALAMARES_SETTINGS" >&2
    fi
}

# --- eggs actions ------------------------------------------------------------
produce_iso() {
    log "Producing the CachyOSXDev ISO with penguins-eggs..."
    log "This remasters your running system and can take a while."
    eggs remaster
    ok "Remaster complete. Check your eggs workdir (default /home/eggs) for the ISO."
}

clean_workspace() {
    command -v eggs >/dev/null 2>&1 || {
        warn "eggs not installed; nothing to clean."
        return 0
    }
    log "Tearing down the eggs workspace..."
    eggs destroy
    ok "Workspace cleaned."
}

summary() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN} CachyOSXDev installer ready${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "  Standalone branding : $CALAMARES_BRANDING_ROOT/$BRANDING_NAME"
    echo -e "  eggs overlay        : $EGGS_OVERLAY_DIR"
    echo -e "  Settings backup     : $CALAMARES_SETTINGS_BACKUP"
    echo -e ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo -e "  1. Produce the ISO : sudo $0 --remaster    (or: sudo eggs remaster)"
    echo -e "  2. Tune compression: sudo eggs config"
    echo -e "  3. Test the ISO    : boot it, then 'sudo eggs sysinstall calamares'"
    echo -e "  4. Clean workspace : sudo $0 --clean"
    echo -e "${BLUE}========================================${NC}"
}

# --- Entrypoint --------------------------------------------------------------
main() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --remaster|--produce) DO_REMASTER=true ;;
            --clean)              DO_CLEAN=true ;;
            --help|-h)            usage; exit 0 ;;
            *) err "Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done

    require_root
    require_cachyos

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  CachyOSXDev eggs installer generator  ${NC}"
    echo -e "${BLUE}========================================${NC}"

    install_calamares
    install_eggs
    install_branding
    configure_calamares_settings

    if [ "$DO_CLEAN" = true ]; then
        clean_workspace
        exit 0
    fi

    if [ "$DO_REMASTER" = true ]; then
        produce_iso
    fi

    summary
}

main "$@"
