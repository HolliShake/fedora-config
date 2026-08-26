#!/usr/bin/env bash
#
# cachyos-eggs.sh
#
# Unified KDE Plasma + GTK Theme Exporter & System Remastering Script
# Bakes user configuration into /etc/skel and triggers Penguins' Eggs.

set -euo pipefail

APPLY=false
WITH_DCONF=true
DIFF_MODE=false
ROLLBACK=false
ROLLBACK_ARCHIVE=""
REMASTER=false

for arg in "$@"; do
    case "$arg" in
        --apply)      APPLY=true ;;
        --remaster)   REMASTER=true; APPLY=true ;;
        --with-dconf) WITH_DCONF=true ;;
        --no-dconf)   WITH_DCONF=false ;;
        --diff)       DIFF_MODE=true ;;
        --rollback)   ROLLBACK=true ;;
        --backup=*)   ROLLBACK_ARCHIVE="${arg#--backup=}" ;;
        --backup)     : ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --apply       Export current user theme and settings to /etc/skel"
            echo "  --remaster    Export settings to /etc/skel AND build live ISO using Penguins' Eggs"
            echo "  --diff        Show differences between user configs and /etc/skel"
            echo "  --rollback    Restore /etc/skel from the latest backup"
            echo "  --no-dconf    Skip GTK/dconf export"
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

# Detect true user and home directory (even when executed with sudo)
if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    REAL_USER="$SUDO_USER"
    SRC_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
    REAL_USER="$(id -un)"
    SRC_HOME="$HOME"
fi

EXPORT_DIR="${EXPORT_DIR:-$SRC_HOME/kde-theme-export}"
BACKUP_DIR="${EXPORT_DIR}/backups"
MANIFEST_DIR="${EXPORT_DIR}/manifests"
LOG_FILE="${EXPORT_DIR}/export.log"

SKEL="/etc/skel"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
WALLPAPER_SYSTEM_DIR="${WALLPAPER_SYSTEM_DIR:-/usr/share/wallpapers/exported-theme}"

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

urldecode() {
    local data="${1//+/ }"
    printf '%b' "${data//%/\\x}" 2>/dev/null || printf '%s' "$1"
}

sanitize_basename() {
    local name="$1"
    name="${name//[^A-Za-z0-9._-]/_}"
    printf '%s' "$name"
}

echo "${C_BOLD}Source home : $SRC_HOME${C_RESET}"
echo "${C_BOLD}Target skel : $SKEL${C_RESET}"
echo "${C_BOLD}Export dir  : $EXPORT_DIR${C_RESET}"
if $ROLLBACK; then
    echo "${C_BOLD}Mode        : ROLLBACK${C_RESET}"
elif $DIFF_MODE; then
    echo "${C_BOLD}Mode        : DIFF (read-only)${C_RESET}"
elif $REMASTER; then
    echo "${C_BOLD}Mode        : EXPORT & REMASTER (Penguins' Eggs)${C_RESET}"
else
    echo "${C_BOLD}Mode        : $([[ "$APPLY" == true ]] && echo APPLY || echo 'DRY RUN (pass --apply or --remaster)')${C_RESET}"
fi
echo

# Enforce root permissions for writing operations
if [[ "$EUID" -ne 0 ]] && { $APPLY || $ROLLBACK || $REMASTER; }; then
    log ERR "Writing to /etc/skel or remastering requires root permissions."
    echo "Please run: sudo $0 $@"
    exit 1
fi

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

    rm -rf "${SKEL:?}"/*
    tar -xzf "$ROLLBACK_ARCHIVE" -C /
    log OK "Restored ${SKEL} from $ROLLBACK_ARCHIVE"

    DCONF_BACKUP="${ROLLBACK_ARCHIVE%.tar.gz}.dconf-site"
    if [[ -f "$DCONF_BACKUP" ]]; then
        mkdir -p /etc/dconf/db/site.d
        cp "$DCONF_BACKUP" /etc/dconf/db/site.d/00-gtk-theme
        dconf update
        log OK "Restored dconf site db from $DCONF_BACKUP"
    fi
    exit 0
fi

# =============================================================================
# FILE DEFINITIONS
# =============================================================================
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

# Backup current /etc/skel before altering
BACKUP_ARCHIVE=""
if [[ "$APPLY" == true ]]; then
    if [[ -d "$SKEL" ]] && find "$SKEL" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
        BACKUP_ARCHIVE="${BACKUP_DIR}/skel-backup-${TIMESTAMP}.tar.gz"
        tar -czf "$BACKUP_ARCHIVE" -C / "${SKEL#/}"
        chown "${REAL_USER}:${REAL_USER}" "$BACKUP_ARCHIVE" 2>/dev/null || true
    fi
    if [[ -f /etc/dconf/db/site.d/00-gtk-theme && -n "$BACKUP_ARCHIVE" ]]; then
        cp /etc/dconf/db/site.d/00-gtk-theme "${BACKUP_ARCHIVE%.tar.gz}.dconf-site"
        chown "${REAL_USER}:${REAL_USER}" "${BACKUP_ARCHIVE%.tar.gz}.dconf-site" 2>/dev/null || true
    fi
fi

MANIFEST_FILE="${MANIFEST_DIR}/manifest-${TIMESTAMP}.tsv"
[[ "$APPLY" == true ]] && printf 'path\tsha256\tsize_bytes\n' > "$MANIFEST_FILE"

TOTAL_FILES=0
TOTAL_BYTES=0

# =============================================================================
# COPY ENGINE
# =============================================================================
copy_item() {
    local rel="$1"
    local src="${SRC_HOME}/${rel}"
    local dest="${SKEL}/${rel}"

    [[ -e "$src" ]] || return 0

    echo "  + $rel"
    if [[ "$APPLY" == true ]]; then
        rm -rf "$dest"

        if [[ -d "$src" ]]; then
            mkdir -p "$dest"
            if ! cp -aL --no-preserve=ownership "$src"/. "$dest"/ 2>/tmp/copy-err.$$; then
                log WARN "Some items under $rel could not be fully dereferenced (broken symlinks):"
                sed 's/^/      /' /tmp/copy-err.$$ 2>/dev/null || true
            fi
            rm -f /tmp/copy-err.$$
        else
            mkdir -p "$(dirname "$dest")"
            cp -aL --no-preserve=ownership "$src" "$dest"
        fi

        while IFS= read -r -d '' f; do
            local relpath="${f#$SKEL/}"
            local sum size
            sum="$(sha256sum "$f" 2>/dev/null | awk '{print $1}')"
            size="$(stat -c%s "$f" 2>/dev/null || echo 0)"
            printf '%s\t%s\t%s\n' "$relpath" "$sum" "$size" >> "$MANIFEST_FILE"
            TOTAL_FILES=$((TOTAL_FILES + 1))
            TOTAL_BYTES=$((TOTAL_BYTES + size))
        done < <(find "$dest" -type f -print0 2>/dev/null)
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
    log INFO "Rehoming wallpaper image references (Plasma + Konsole) out of $SRC_HOME..."
    WALLPAPER_CFG_FILES=(
        "$SKEL/.config/plasma-org.kde.plasma.desktop-appletsrc"
        "$SKEL/.config/kdeglobals"
    )

    if [[ -d "$SKEL/.local/share/konsole" ]]; then
        while IFS= read -r kfile; do
            WALLPAPER_CFG_FILES+=("$kfile")
        done < <(find "$SKEL/.local/share/konsole" -type f \( -name "*.profile" -o -name "*.colorscheme" \) 2>/dev/null)
    fi

    PRIMARY_WALLPAPER_DESTPATH=""

    rehome_wallpaper_uri() {
        local uri="$1" cfgfile="$2"
        local raw_path="${uri#file://}"
        local path
        path="$(urldecode "$raw_path")"
        [[ -f "$path" ]] || return 0

        local src_hash safe_base destname destpath
        src_hash="$(printf '%s' "$path" | sha256sum | cut -c1-8)"
        safe_base="$(sanitize_basename "$(basename "$path")")"
        destname="${src_hash}-${safe_base}"
        destpath="${WALLPAPER_SYSTEM_DIR}/${destname}"

        mkdir -p "$WALLPAPER_SYSTEM_DIR"
        if test -e "$destpath"; then
            echo "  -> Already rehomed: $(basename "$path") -> $destpath"
        else
            cp "$path" "$destpath"
            echo "  -> Rehomed: $(basename "$path") -> $destpath"
            WALLPAPERS_REHOMED=$((WALLPAPERS_REHOMED + 1))
        fi

        [[ -z "$PRIMARY_WALLPAPER_DESTPATH" ]] && PRIMARY_WALLPAPER_DESTPATH="$destpath"

        local new_uri
        if [[ "$uri" == file://* ]]; then
            new_uri="file://${destpath}"
        else
            new_uri="${destpath}"
        fi

        local esc_uri esc_new
        esc_uri="$(printf '%s' "$uri" | sed -e 's/[.[\*^$#&]/\\&/g')"
        esc_new="$(printf '%s' "$new_uri" | sed -e 's/[#&\\]/\\&/g')"
        sed -i "s#${esc_uri}#${esc_new}#g" "$cfgfile"
    }

    for cfgfile in "${WALLPAPER_CFG_FILES[@]}"; do
        [[ -f "$cfgfile" ]] || continue
        while IFS= read -r match; do
            [[ -n "$match" ]] || continue
            rehome_wallpaper_uri "$match" "$cfgfile"
        done < <( {
            grep -hoE "file://${SRC_HOME}[^,\"\']*" "$cfgfile" 2>/dev/null
            grep -hoE "${SRC_HOME}[^,\"\']*\.(png|jpg|jpeg|webp|gif|svg|bmp|heic)" "$cfgfile" 2>/dev/null
        } | sort -u )
    done

    if [[ "$WALLPAPERS_REHOMED" -gt 0 ]]; then
        chmod -R go+rX "$WALLPAPER_SYSTEM_DIR"
        log OK "Rehomed $WALLPAPERS_REHOMED wallpaper reference(s) to $WALLPAPER_SYSTEM_DIR."
    fi

    # =========================================================================
    # SYSTEM-WIDE WALLPAPER DEFAULT
    # =========================================================================
    patch_system_wallpaper_default() {
        local wallpaper_path="$1"
        local xml_escaped="${wallpaper_path//&/&amp;}"
        xml_escaped="${xml_escaped//</&lt;}"
        xml_escaped="${xml_escaped//>/&gt;}"

        local candidates=(
            /usr/share/plasma/wallpapers/org.kde.image/contents/config/main.xml
            /usr/share/plasma/wallpapers/org.kde.image/contents/config/Main.xml
        )
        local patched_any=false
        local f
        for f in "${candidates[@]}"; do
            test -f "$f" || continue

            local tmp_out="/tmp/main-xml-patch.$$"
            if ! cat "$f" | awk -v newval="$xml_escaped" '
                BEGIN { in_entry = 0 }
                {
                    line = $0
                    if (line ~ /<entry[ \t]+name="Image"[ \t]+type="String"/) { in_entry = 1 }
                    if (in_entry && match(line, /<default>.*<\/default>/)) {
                        sub(/<default>.*<\/default>/, "<default>" newval "</default>", line)
                        in_entry = 0
                    }
                    print line
                }
            ' > "$tmp_out"; then
                log WARN "Could not parse $f -- leaving default wallpaper untouched there."
                rm -f "$tmp_out"
                continue
            fi

            if ! grep -qF "<default>${xml_escaped}</default>" "$tmp_out"; then
                log WARN "Didn't find an Image default entry to patch in $f -- left untouched."
                rm -f "$tmp_out"
                continue
            fi

            test -f "${f}.pre-export-orig" || cp "$f" "${f}.pre-export-orig"
            cp "$tmp_out" "$f"
            rm -f "$tmp_out"
            patched_any=true
            log OK "Set system-wide default wallpaper in $f -> $wallpaper_path"
        done

        if ! $patched_any; then
            log WARN "No org.kde.image main.xml found/patched -- new users will depend solely on copied appletsrc."
        fi
    }

    if [[ -n "$PRIMARY_WALLPAPER_DESTPATH" ]]; then
        patch_system_wallpaper_default "$PRIMARY_WALLPAPER_DESTPATH"
    fi

    # =========================================================================
    # CACHYOS BASH FIX
    # =========================================================================
    if [[ -f "$SKEL/.bashrc" ]]; then
        if ! grep -q "fastfetch" "$SKEL/.bashrc" 2>/dev/null; then
            log INFO "Injecting fastfetch trigger into skel/.bashrc for bash fallback..."
            echo -e "\n# Trigger fastfetch on interactive terminal launch (CachyOS fix)\nif [[ \$- == *i* ]]; then\n    if command -v fastfetch >/dev/null 2>&1; then\n        fastfetch\n    fi\nfi" >> "$SKEL/.bashrc"
        fi
    fi

    while IFS= read -r symlink; do
        if ! test -e "$symlink"; then
            BROKEN_SYMLINKS=$((BROKEN_SYMLINKS + 1))
        fi
    done < <(find "$SKEL" -type l 2>/dev/null)

    chown -Rh root:root "$SKEL"
    chmod -R go+rX "$SKEL"

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
            mkdir -p /etc/dconf/db/site.d /etc/dconf/profile
            cp "$DUMP_FILE" /etc/dconf/db/site.d/00-gtk-theme
            if [[ ! -f /etc/dconf/profile/user ]]; then
                printf 'user-db:user\nsystem-db:site\n' > /etc/dconf/profile/user
            fi
            dconf update
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

# =============================================================================
# PENGUINS' EGGS REMASTER
# =============================================================================
if $REMASTER; then
    echo
    log INFO "Beginning CachyOS remastering build with Penguins' Eggs..."
    
    if ! command -v eggs &>/dev/null; then
        log ERR "The 'eggs' binary was not found. Please install penguins-eggs first."
        exit 1
    fi

    KVER="$(uname -r)"
    log INFO "Detected running kernel version: $KVER"

    # Identify active kernel binary in /boot
    K_FILE=""
    for candidate in "/boot/vmlinuz-linux-cachyos-lts" "/boot/vmlinuz-linux-cachyos" "/boot/vmlinuz-linux" $(ls -1 /boot/vmlinuz* 2>/dev/null); do
        if [[ -f "$candidate" && "$candidate" != *".old"* && "$candidate" != *".bak"* ]]; then
            K_FILE="$candidate"
            break
        fi
    done

    if [[ -n "$K_FILE" ]]; then
        K_NAME="$(basename "$K_FILE")"
        log INFO "Found kernel binary: $K_FILE"

        # Determine matching initramfs
        INITRD_FILE=""
        INITRD_CANDIDATE="/boot/initramfs-${K_NAME#vmlinuz-}.img"
        if [[ -f "$INITRD_CANDIDATE" ]]; then
            INITRD_FILE="$INITRD_CANDIDATE"
        else
            INITRD_FILE="$(ls -1 /boot/initramfs*.img 2>/dev/null | head -n1 || true)"
        fi

        log INFO "Preparing kernel files across all path variants expected by Eggs..."

        # Copy kernel binary to all standard kernel path patterns expected by Eggs
        cp -f "$K_FILE" "/boot/vmlinuz-${KVER}" 2>/dev/null || true
        cp -f "$K_FILE" "/boot/vmlinuz-linux" 2>/dev/null || true
        cp -f "$K_FILE" "/boot/vmlinuz" 2>/dev/null || true
        cp -f "$K_FILE" "/boot/vmlinux-${KVER}" 2>/dev/null || true
        cp -f "$K_FILE" "/boot/vmlinux" 2>/dev/null || true
        cp -f "$K_FILE" "/vmlinuz" 2>/dev/null || true
        cp -f "$K_FILE" "/vmlinux" 2>/dev/null || true

        # Copy initramfs to all standard initrd path patterns
        if [[ -n "$INITRD_FILE" && -f "$INITRD_FILE" ]]; then
            log INFO "Found initramfs image: $INITRD_FILE"
            cp -f "$INITRD_FILE" "/boot/initramfs-${KVER}.img" 2>/dev/null || true
            cp -f "$INITRD_FILE" "/boot/initramfs-linux.img" 2>/dev/null || true
            cp -f "$INITRD_FILE" "/boot/initrd.img-${KVER}" 2>/dev/null || true
            cp -f "$INITRD_FILE" "/boot/initrd.img" 2>/dev/null || true
            cp -f "$INITRD_FILE" "/initrd.img" 2>/dev/null || true
        fi

        # Duplicate CachyOS mkinitcpio preset to linux.preset for Eggs search
        PRESET_FILE="$(ls -1 /etc/mkinitcpio.d/*.preset 2>/dev/null | head -n1 || true)"
        if [[ -n "$PRESET_FILE" && -f "$PRESET_FILE" ]]; then
            log INFO "Duplicating mkinitcpio preset ($PRESET_FILE) to linux.preset..."
            cp -f "$PRESET_FILE" "/etc/mkinitcpio.d/linux.preset" 2>/dev/null || true
            cp -f "$PRESET_FILE" "/etc/mkinitcpio.d/linux-${KVER}.preset" 2>/dev/null || true
        fi
    else
        log WARN "Could not identify kernel file in /boot. Proceeding anyway..."
    fi

    # Trigger ISO creation
    eggs produce
fi
