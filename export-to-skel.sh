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
WALLPAPER_SYSTEM_DIR="${WALLPAPER_SYSTEM_DIR:-/usr/share/wallpapers/exported-theme}"

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

echo "${C_BOLD}Source home : $SRC_HOME${C_RESET}"
echo "${C_BOLD}Target skel : $SKEL${C_RESET}"
echo "${C_BOLD}Export dir  : $EXPORT_DIR${C_RESET}"
if $ROLLBACK; then
    echo "${C_BOLD}Mode        : ROLLBACK${C_RESET}"
elif $DIFF_MODE; then
    echo "${C_BOLD}Mode        : DIFF (read-only, no sudo, no writes)${C_RESET}"
else
    echo "${C_BOLD}Mode        : $([[ "$APPLY" == true ]] && echo APPLY || echo 'DRY RUN (pass --apply to actually copy)')${C_RESET}"
fi
echo

# =============================================================================
# ROLLBACK MODE
# =============================================================================
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

    DCONF_BACKUP="${ROLLBACK_ARCHIVE%.tar.gz}.dconf-site"
    if [[ -f "$DCONF_BACKUP" ]]; then
        sudo mkdir -p /etc/dconf/db/site.d
        sudo cp "$DCONF_BACKUP" /etc/dconf/db/site.d/00-gtk-theme
        sudo dconf update
        log OK "Restored dconf site db from $DCONF_BACKUP"
    fi
    exit 0
fi

# =============================================================================
# FILE DEFINITIONS
# =============================================================================

# Shell, KDE/Plasma, GTK, and Konsole configs
CONFIG_FILES=(
    .bashrc
    .zshrc
    .bash_profile
    .zprofile
    .profile
    .bash_aliases
    .config/starship.toml
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

# GTK, Kvantum, Shell integrations
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

# Local data: themes, icons, fonts, etc.
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

# =============================================================================
# DIFF MODE
# =============================================================================
if $DIFF_MODE; then
    printf "%-55s %-14s\n" "ITEM" "STATUS"
    printf "%-55s %-14s\n" "----" "------"
    for rel in "${ALL_ITEMS[@]}"; do
        src="${SRC_HOME}/${rel}"
        dest="${SKEL}/${rel}"
        [[ -e "$src" ]] || continue

        if [[ ! -e "$dest" ]]; then
            status="${C_GREEN}NEW${C_RESET}"
        elif [[ -d "$src" ]]; then
            if diff -rq "$src" "$dest" >/dev/null 2>&1; then
                status="${C_DIM}unchanged${C_RESET}"
            else
                status="${C_YELLOW}CHANGED${C_RESET}"
            fi
        else
            if cmp -s "$src" "$dest" 2>/dev/null; then
                status="${C_DIM}unchanged${C_RESET}"
            else
                status="${C_YELLOW}CHANGED${C_RESET}"
            fi
        fi
        printf "%-55s %b\n" "$rel" "$status"
    done
    echo
    exit 0
fi

# =============================================================================
# APPLY PRE-CHECKS & BACKUPS
# =============================================================================
if [[ "$APPLY" == true ]]; then
    log INFO "Requesting sudo access up front (needed for /etc/skel and /etc/dconf writes)..."
    if ! sudo -v; then
        log ERR "Could not obtain sudo access. Aborting before touching anything."
        exit 1
    fi
    ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap '[[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
fi

BACKUP_ARCHIVE=""
if [[ "$APPLY" == true ]]; then
    if [[ -d "$SKEL" ]] && sudo find "$SKEL" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
        BACKUP_ARCHIVE="${BACKUP_DIR}/skel-backup-${TIMESTAMP}.tar.gz"
        sudo tar -czf "$BACKUP_ARCHIVE" -C / "${SKEL#/}"
        sudo chown "$(id -u):$(id -g)" "$BACKUP_ARCHIVE"
    fi
    if [[ -f /etc/dconf/db/site.d/00-gtk-theme && -n "$BACKUP_ARCHIVE" ]]; then
        sudo cp /etc/dconf/db/site.d/00-gtk-theme "${BACKUP_ARCHIVE%.tar.gz}.dconf-site"
        sudo chown "$(id -u):$(id -g)" "${BACKUP_ARCHIVE%.tar.gz}.dconf-site"
    fi
fi

MANIFEST_FILE="${MANIFEST_DIR}/manifest-${TIMESTAMP}.tsv"
[[ "$APPLY" == true ]] && printf 'path\tsha256\tsize_bytes\n' > "$MANIFEST_FILE"

TOTAL_FILES=0
TOTAL_BYTES=0

# =============================================================================
# COPY LOGIC
# =============================================================================
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
            if ! sudo cp -aL --no-preserve=ownership "$src"/. "$dest"/ 2>/tmp/copy-err.$$; then
                log WARN "Some items under $rel could not be fully dereferenced (broken symlinks):"
                sed 's/^/      /' /tmp/copy-err.$$ 2>/dev/null || true
            fi
            rm -f /tmp/copy-err.$$
        else
            sudo mkdir -p "$(dirname "$dest")"
            sudo cp -aL --no-preserve=ownership "$src" "$dest"
        fi

        while IFS= read -r -d '' f; do
            local relpath="${f#$SKEL/}"
            local sum size
            sum="$(sudo sha256sum "$f" 2>/dev/null | awk '{print $1}')"
            size="$(sudo stat -c%s "$f" 2>/dev/null || echo 0)"
            printf '%s\t%s\t%s\n' "$relpath" "$sum" "$size" >> "$MANIFEST_FILE"
            TOTAL_FILES=$((TOTAL_FILES + 1))
            TOTAL_BYTES=$((TOTAL_BYTES + size))
        done < <(sudo find "$dest" -type f -print0 2>/dev/null)
    fi
}

echo "Files:"
for f in "${CONFIG_FILES[@]}"; do
    copy_item "$f"
done

echo
echo "Directories:"
for d in "${CONFIG_DIRS[@]}" "${DATA_DIRS[@]}"; do
    copy_item "$d"
done

echo
BROKEN_SYMLINKS=0
WALLPAPERS_REHOMED=0

if [[ "$APPLY" == true ]]; then

    # =========================================================================
    # WALLPAPER REHOMING
    # =========================================================================
    log INFO "Rehoming wallpaper image references (Plasma + Konsole) out of \$SRC_HOME..."
    WALLPAPER_CFG_FILES=(
        "$SKEL/.config/plasma-org.kde.plasma.desktop-appletsrc"
        "$SKEL/.config/kdeglobals"
    )

    if [[ -d "$SKEL/.local/share/konsole" ]]; then
        while IFS= read -r kfile; do
            WALLPAPER_CFG_FILES+=("$kfile")
        done < <(sudo find "$SKEL/.local/share/konsole" -type f \( -name "*.profile" -o -name "*.colorscheme" \) 2>/dev/null)
    fi

    rehome_wallpaper_uri() {
        local uri="$1" cfgfile="$2"
        local path="${uri#file://}"
        [[ -f "$path" ]] || return 0
        local base
        base="$(basename "$path")"
        sudo mkdir -p "$WALLPAPER_SYSTEM_DIR"
        sudo cp -n "$path" "$WALLPAPER_SYSTEM_DIR/$base" 2>/dev/null || true
        
        local new_uri
        if [[ "$uri" == file://* ]]; then
            new_uri="file://${WALLPAPER_SYSTEM_DIR}/${base}"
        else
            new_uri="${WALLPAPER_SYSTEM_DIR}/${base}"
        fi
        
        local esc_uri esc_new
        esc_uri="$(printf '%s' "$uri" | sed -e 's/[.[\*^$#&]/\\&/g')"
        esc_new="$(printf '%s' "$new_uri" | sed -e 's/[#&\\]/\\&/g')"
        sudo sed -i "s#${esc_uri}#${esc_new}#g" "$cfgfile"
        echo "  -> Rehomed: $base -> $WALLPAPER_SYSTEM_DIR/$base"
        WALLPAPERS_REHOMED=$((WALLPAPERS_REHOMED + 1))
    }
    
    for cfgfile in "${WALLPAPER_CFG_FILES[@]}"; do
        [[ -f "$cfgfile" ]] || continue
        while IFS= read -r match; do
            [[ -n "$match" ]] || continue
            rehome_wallpaper_uri "$match" "$cfgfile"
        done < <( {
            sudo grep -hoE "file://${SRC_HOME}[^,\"\']*" "$cfgfile" 2>/dev/null
            sudo grep -hoE "${SRC_HOME}[^,\"\']*\.(png|jpg|jpeg|webp|gif|svg|bmp|heic)" "$cfgfile" 2>/dev/null
        } | sort -u )
    done

    if [[ "$WALLPAPERS_REHOMED" -gt 0 ]]; then
        sudo chmod -R go+rX "$WALLPAPER_SYSTEM_DIR"
        log OK "Rehomed $WALLPAPERS_REHOMED wallpaper reference(s) to $WALLPAPER_SYSTEM_DIR."
    fi

    # =========================================================================
    # CACHYOS BASH FIX
    # =========================================================================
    if [[ -f "$SKEL/.bashrc" ]]; then
        if ! sudo grep -q "fastfetch" "$SKEL/.bashrc" 2>/dev/null; then
            log INFO "Injecting fastfetch trigger into skel/.bashrc for bash fallback..."
            echo -e "\n# Trigger fastfetch on interactive terminal launch (CachyOS fix)\nif [[ \$- == *i* ]]; then\n    if command -v fastfetch >/dev/null 2>&1; then\n        fastfetch\n    fi\nfi" | sudo tee -a "$SKEL/.bashrc" >/dev/null
        fi
    fi

    while IFS= read -r symlink; do
        tgt="$(sudo readlink "$symlink" || true)"
        BROKEN_SYMLINKS=$((BROKEN_SYMLINKS + 1))
    done < <(sudo find "$SKEL" -type l 2>/dev/null)

    sudo chown -Rh root:root "$SKEL"
    sudo chmod -R go+rX "$SKEL"

    log OK "Done. /etc/skel updated — new users will inherit this KDE/GTK setup."
else
    echo "Dry run complete — nothing was written."
fi

# =============================================================================
# DCONF GTK INTEGRATION
# =============================================================================
DCONF_PATHS=(
    /org/gnome/desktop/interface/
    /org/gnome/desktop/wm/preferences/
    /org/gnome/desktop/sound/
    /org/gtk/settings/file-chooser/
    /org/gtk/settings/color-chooser/
)

if [[ "$WITH_DCONF" == true ]]; then
    if command -v dconf >/dev/null 2>&1; then
        DUMP_FILE="${EXPORT_DIR}/gtk-dconf-export.ini"
        : > "$DUMP_FILE.tmp"

        for path in "${DCONF_PATHS[@]}"; do
            section="[$(basename "${path%/}")]"
            {
                echo "$section"
                dconf dump "$path" | tail -n +2
            } >> "$DUMP_FILE.tmp" 2>/dev/null || true
            echo >> "$DUMP_FILE.tmp"
        done
        mv "$DUMP_FILE.tmp" "$DUMP_FILE"

        if [[ "$APPLY" == true ]]; then
            sudo mkdir -p /etc/dconf/db/site.d /etc/dconf/profile
            sudo cp "$DUMP_FILE" /etc/dconf/db/site.d/00-gtk-theme
            if [[ ! -f /etc/dconf/profile/user ]]; then
                printf 'user-db:user\nsystem-db:site\n' | sudo tee /etc/dconf/profile/user >/dev/null
            fi
            sudo dconf update
            log OK "Dconf (GTK settings) successfully exported and updated."
        fi
    fi
fi

if [[ "$APPLY" == true ]]; then
    echo
    echo "${C_BOLD}Summary${C_RESET}"
    echo "  Files copied      : $TOTAL_FILES"
    echo "  Total size        : $(human_size "$TOTAL_BYTES")"
    if [[ "$BROKEN_SYMLINKS" -gt 0 ]]; then
        echo "  Broken Symlinks   : $BROKEN_SYMLINKS"
    fi
fi
