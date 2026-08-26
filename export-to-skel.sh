#!/usr/bin/env bash
#
# export-kde-theme-to-skel.sh
#
# Full KDE Plasma + GTK "look & feel" exporter, for baking a themed config
# into a system installer/image. 

set -euo pipefail

APPLY=false
WITH_DCONF=true
DIFF_MODE=false
ROLLBACK=false
ROLLBACK_ARCHIVE=""

for arg in "$@"; do
    case "$arg" in
        --apply)      APPLY=true ;;
        --with-dconf) WITH_DCONF=true ;;
        --no-dconf)   WITH_DCONF=false ;;
        --diff)       DIFF_MODE=true ;;
        --rollback)   ROLLBACK=true ;;
        --backup=*)   ROLLBACK_ARCHIVE="${arg#--backup=}" ;;
        --backup)     : ;; 
        -h|--help)
            awk '/^#!/{next} /^#/{print substr($0,3); next} {exit}' "$0"
            exit 0
            ;;
    esac
done

if $ROLLBACK && [[ -z "$ROLLBACK_ARCHIVE" ]]; then
    prev=""
    for arg in "$@"; do
        if [[ "$prev" == "--backup" ]]; then
            ROLLBACK_ARCHIVE="$arg"
        fi
        prev="$arg"
    done
fi

EXPORT_DIR="${EXPORT_DIR:-$HOME/kde-theme-export}"
BACKUP_DIR="${EXPORT_DIR}/backups"
MANIFEST_DIR="${EXPORT_DIR}/manifests"
LOG_FILE="${EXPORT_DIR}/export.log"

SRC_HOME="${HOME}"
SKEL="/etc/skel"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
WALLPAPER_SYSTEM_DIR="${WALLPAPER_SYSTEM_DIR:-/usr/share/wallpapers/site-default}"

if [[ "$EUID" -eq 0 ]]; then
    echo "Please run this script as your normal user (it will call sudo itself when needed)." >&2
    exit 1
fi

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
    C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'; C_DIM=$'\033[2m'
else
    C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""; C_DIM=""
fi

mkdir -p "$EXPORT_DIR" "$BACKUP_DIR" "$MANIFEST_DIR"

log() {
    local level="$1"; shift
    local msg="$*"
    local color="$C_RESET"
    case "$level" in
        OK)   color="$C_GREEN" ;;
        WARN) color="$C_YELLOW" ;;
        ERR)  color="$C_RED" ;;
        INFO) color="$C_BLUE" ;;
    esac
    echo "${color}${msg}${C_RESET}"
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$msg" >> "$LOG_FILE"
}

human_size() {
    local bytes="$1"
    numfmt --to=iec --suffix=B "$bytes" 2>/dev/null || echo "${bytes}B"
}

if $ROLLBACK; then
    if [[ -z "$ROLLBACK_ARCHIVE" ]]; then
        ROLLBACK_ARCHIVE="$(ls -1t "${BACKUP_DIR}"/skel-backup-*.tar.gz 2>/dev/null | head -n1 || true)"
    fi

    if [[ -z "$ROLLBACK_ARCHIVE" || ! -f "$ROLLBACK_ARCHIVE" ]]; then
        log ERR "No backup archive found."
        exit 1
    fi

    log INFO "Restoring from: $ROLLBACK_ARCHIVE"
    read -r -p "This will REPLACE the current contents of ${SKEL}. Continue? [y/N] " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        log WARN "Rollback cancelled."
        exit 0
    fi

    sudo rm -rf "${SKEL:?}"/*
    sudo tar -xzf "$ROLLBACK_ARCHIVE" -C /
    log OK "Restored ${SKEL} from $ROLLBACK_ARCHIVE"
    exit 0
fi

# --- List of config paths (relative to $HOME) to export ---------------------
CONFIG_FILES=(
    .bashrc
    .zshrc
    .bash_profile
    .zprofile
    .profile
    .bash_aliases
    .config/starship.toml
    
    # KDE/Plasma/GTK/Konsole configs
    .config/kdeglobals
    .config/kwinrc
    .config/plasmarc
    .config/plasmashellrc
    .config/plasma-org.kde.plasma.desktop-appletsrc
    .config/ksplashrc
    .config/gtkrc
    .config/gtkrc-2.0
    .config/xsettingsd
    .gtkrc-2.0
    .config/kcminputrc
    .config/kwinrulesrc
    .config/konsolerc
    .config/konsoleui.rc
    .config/sessionui.rc
    .config/yakuakerc
)

CONFIG_DIRS=(
    .config/gtk-2.0
    .config/gtk-3.0
    .config/gtk-4.0
    .config/Kvantum
    .config/kvantum
    .config/fontconfig
    .config/plasma-workspace/env
    .config/fastfetch
    .config/fish
)

DATA_DIRS=(
    .local/share/plasma
    .local/share/color-schemes
    .local/share/icons
    .local/share/aurorae
    .local/share/wallpapers
    .local/share/plasma_look_and_feel
    .local/share/konsole
    .local/share/kxmlgui5/konsole
    .local/share/fonts
    .themes
    .icons
    .fonts
)

ALL_ITEMS=("${CONFIG_FILES[@]}" "${CONFIG_DIRS[@]}" "${DATA_DIRS[@]}")

if [[ "$APPLY" == true ]]; then
    log INFO "Requesting sudo access up front (needed for /etc/skel)..."
    if ! sudo -v; then
        log ERR "Could not obtain sudo access."
        exit 1
    fi
    ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap '[[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
fi

TOTAL_FILES=0
TOTAL_BYTES=0

copy_item() {
    local rel="$1"
    local src="${SRC_HOME}/${rel}"
    local dest="${SKEL}/${rel}"

    [[ -e "$src" ]] || return 0

    echo "  + $rel"
    if [[ "$APPLY" == true ]]; then
        sudo rm -rf "$dest"

        if [[ -d "$src" ]]; then
            sudo mkdir -p "$dest"
            sudo cp -aL --no-preserve=ownership "$src"/. "$dest"/ 2>/dev/null || true
        else
            sudo mkdir -p "$(dirname "$dest")"
            sudo cp -aL --no-preserve=ownership "$src" "$dest"
        fi
        
        while IFS= read -r -d '' f; do
            local size
            size="$(sudo stat -c%s "$f" 2>/dev/null || echo 0)"
            TOTAL_FILES=$((TOTAL_FILES + 1))
            TOTAL_BYTES=$((TOTAL_BYTES + size))
        done < <(sudo find "$dest" -type f -print0 2>/dev/null)
    fi
}

echo "Copying configuration files..."
for f in "${CONFIG_FILES[@]}"; do
    copy_item "$f"
done

echo "Copying configuration directories..."
for d in "${CONFIG_DIRS[@]}" "${DATA_DIRS[@]}"; do
    copy_item "$d"
done

if [[ "$APPLY" == true ]]; then
    
    # -------------------------------------------------------------------------
    # THE CACHYOS BASH FIX
    # If the user opens Konsole in Bash instead of Fish, trigger fastfetch
    # -------------------------------------------------------------------------
    if [[ -f "$SKEL/.bashrc" ]]; then
        if ! sudo grep -q "fastfetch" "$SKEL/.bashrc" 2>/dev/null; then
            log INFO "Injecting fastfetch trigger into skel/.bashrc for bash fallback..."
            echo -e "\n# Trigger fastfetch on interactive terminal launch (CachyOS fix)\nif [[ \$- == *i* ]]; then\n    if command -v fastfetch >/dev/null 2>&1; then\n        fastfetch\n    fi\nfi" | sudo tee -a "$SKEL/.bashrc" >/dev/null
        fi
    fi

    sudo chown -Rh root:root "$SKEL"
    sudo chmod -R go+rX "$SKEL"

    log OK "Done. /etc/skel updated."
    echo
    echo "${C_BOLD}Summary${C_RESET}"
    echo "  Files copied      : $TOTAL_FILES"
    echo "  Total size        : $(human_size "$TOTAL_BYTES")"
fi
