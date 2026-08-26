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
#
# IMPORTANT: CachyOS is NOT an officially supported distro for Penguins'
# Eggs. It works via a community workaround (documented in fresh-eggs'
# SUPPORTED-DISTROS.md: https://github.com/pieroproietti/fresh-eggs/blob/main/SUPPORTED-DISTROS.md)
# and it is known to be fragile across eggs/kernel updates. Treat this
# block as "best effort", not a guaranteed-working pipeline. Recent eggs
# changelogs (26.x) claim native CachyOS boot-issue fixes, so keeping eggs
# itself up to date matters at least as much as anything below.
#
if $REMASTER; then
    echo
    log INFO "Beginning CachyOS remastering build with Penguins' Eggs..."
    log WARN "CachyOS support in Penguins' Eggs is community-maintained/experimental, not official upstream support."

    if ! command -v eggs &>/dev/null; then
        log ERR "The 'eggs' binary was not found. Please install penguins-eggs first."
        exit 1
    fi

    EGGS_VERSION="$(eggs -v 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
    [[ -n "$EGGS_VERSION" ]] && log INFO "Detected penguins-eggs version: $EGGS_VERSION"

    # =========================================================================
    # KERNEL SANITY CHECK
    # =========================================================================
    # The most commonly reported cause of a remastered CachyOS ISO hanging
    # at boot (flashing cursor after fsck) is having more than one CachyOS
    # kernel installed at once (e.g. linux-cachyos + linux-cachyos-lts).
    # See: https://github.com/pieroproietti/penguins-eggs/issues/745
    mapfile -t INSTALLED_KERNELS < <(pacman -Qq 2>/dev/null | grep -E '^linux-cachyos(-[a-z]+)?$' || true)
    if [[ "${#INSTALLED_KERNELS[@]}" -gt 1 ]]; then
        log WARN "Multiple CachyOS kernels detected: ${INSTALLED_KERNELS[*]}"
        log WARN "This is a known cause of unbootable remastered ISOs on CachyOS."
        read -r -p "Continue anyway? [y/N] " kconfirm
        if [[ "${kconfirm,,}" != "y" ]]; then
            log ERR "Aborting. Remove the extra kernel(s) with pacman -R, reboot, then re-run --remaster."
            exit 1
        fi
    fi

    # =========================================================================
    # ENSURE EGGS PREREQUISITES/CONFIG EXIST
    # =========================================================================
    if [[ ! -d /etc/penguins-eggs.d ]]; then
        log INFO "No eggs configuration found -- running 'eggs init' (prerequisites + config)..."
        eggs init --nointeractive 2>/dev/null || eggs config 2>/dev/null || \
            log WARN "'eggs init'/'eggs config' failed or is unavailable in this eggs version; continuing."
    fi

    # =========================================================================
    # CACHYOS COMPATIBILITY SHIM
    # (per fresh-eggs SUPPORTED-DISTROS.md — the ONLY documented fix)
    # =========================================================================
    if ! grep -q '^ID_LIKE=arch' /etc/os-release 2>/dev/null; then
        log INFO "Adding ID_LIKE=arch to /etc/os-release so eggs treats CachyOS as Arch-based..."
        cp -a /etc/os-release "/etc/os-release.pre-eggs-backup" 2>/dev/null || true
        echo 'ID_LIKE=arch' >> /etc/os-release
    fi

    KVER="$(uname -r)"
    RUNNING_INITRD="$(ls -1 /boot/initramfs-linux-cachyos*.img 2>/dev/null | grep -v fallback | head -n1 || true)"
    TARGET_INITRD="/boot/initramfs-${KVER}.img"

    if [[ -n "$RUNNING_INITRD" && -f "$RUNNING_INITRD" && ! -e "$TARGET_INITRD" ]]; then
        log INFO "Linking initramfs so eggs can find it as initramfs-\$(uname -r).img..."
        if ln -sf "$RUNNING_INITRD" "$TARGET_INITRD" 2>/dev/null; then
            log OK "Symlinked $TARGET_INITRD -> $RUNNING_INITRD"
        else
            # /boot on FAT32 (common on some CachyOS/dual-boot setups) can't hold symlinks.
            log WARN "Symlink failed (FAT32 /boot?) -- copying instead. Note: you'll need to redo this after every kernel update."
            cp -f "$RUNNING_INITRD" "$TARGET_INITRD"
        fi
    fi

    # =========================================================================
    # ARCHISO DEPENDENCY
    # =========================================================================
    if ! pacman -Qs archiso &>/dev/null; then
        log INFO "Installing missing archiso dependency (also provides the archiso_* mkinitcpio hooks)..."
        pacman -S --needed --noconfirm archiso || true
    fi

    if ! pacman -Qs grub &>/dev/null; then
        log INFO "Installing missing grub dependency..."
        pacman -S --needed --noconfirm grub || true
    fi

    # =========================================================================
    # MISSING GRUB LIVECD THEME CONFIG
    # =========================================================================
    # Confirmed live bug: some eggs installs (npm/AUR packaging) ship without
    # addons/eggs/theme/livecd/grub.theme.cfg, and the build aborts with
    # "error: .../grub.theme.cfg does not exist" while assembling the ISO's
    # GRUB config. eggs only needs the file to be present, not any specific
    # content, so provision a usable one if it's missing.
    EGGS_THEME_DIR="/usr/lib/node_modules/penguins-eggs/addons/eggs/theme/livecd"
    EGGS_THEME_CFG="${EGGS_THEME_DIR}/grub.theme.cfg"

    if [[ ! -f "$EGGS_THEME_CFG" ]]; then
        log INFO "Provisioning missing GRUB theme config file ($EGGS_THEME_CFG)..."
        mkdir -p "$EGGS_THEME_DIR"

        EXISTING_THEME_CFG="$(find /usr -path '*/theme/livecd/grub.theme.cfg' 2>/dev/null | head -n1 || true)"
        if [[ -n "$EXISTING_THEME_CFG" && -f "$EXISTING_THEME_CFG" ]]; then
            cp -f "$EXISTING_THEME_CFG" "$EGGS_THEME_CFG"
            log OK "Copied existing grub.theme.cfg from $EXISTING_THEME_CFG"
        else
            # Minimal, valid GRUB config fragment -- enough for eggs' seeker
            # to find a non-empty file rather than aborting the build.
            cat > "$EGGS_THEME_CFG" <<'EOF'
# Auto-provisioned fallback theme config (upstream file was missing).
# Minimal, safe GRUB snippet -- no custom theme/background applied.
set timeout=5
EOF
            log WARN "No existing grub.theme.cfg found on system -- wrote a minimal fallback. GRUB will boot plain (no custom theme/background)."
        fi
    fi

    # =========================================================================
    # CALAMARES
    # =========================================================================
    # Recent eggs releases (26.x) ship their own Calamares build/config; on
    # CachyOS the distro-packaged Calamares has been reported to stall at
    # the bootloader step during install. Prefer eggs' own repo if present.
    if eggs help repo &>/dev/null; then
        log INFO "Syncing Calamares from eggs' own repo (eggs repo --add)..."
        eggs repo --add 2>/dev/null || log WARN "'eggs repo --add' failed or unsupported in this version; leaving existing Calamares as-is."
    fi
    log WARN "If the produced ISO's Calamares installer stalls at the bootloader step, fall back to the built-in TUI installer: sudo eggs krill -u"

    # =========================================================================
    # LIVEROOT / BTRFS CLEANUP
    # =========================================================================
    # On a btrfs+snapper system, anything eggs creates under
    # /home/eggs/liveroot/.snapshots during the build is itself a nested
    # btrfs *subvolume*, not a plain directory. eggs' own internal cleanup
    # step runs a plain `rm -rf` against it, which can never remove a
    # subvolume ("rm -rf ... code: 1"), aborting the build. Recursively
    # find and delete every nested subvolume under the liveroot path
    # (deepest first) before eggs ever touches it.
    purge_nested_subvolumes() {
        local root="$1"
        [[ -d "$root" ]] || return 0
        if command -v btrfs &>/dev/null && findmnt -T "$root" -no FSTYPE 2>/dev/null | grep -q btrfs; then
            # List subvolumes whose path is under $root, deepest first.
            while IFS= read -r line; do
                local path
                path="$(awk '{print $NF}' <<<"$line")"
                [[ -n "$path" ]] || continue
                local abs="/${path}"
                [[ "$abs" == "$root"* ]] || continue
                btrfs subvolume delete "$abs" 2>/dev/null || true
            done < <(btrfs subvolume list -o "$root" 2>/dev/null | sort -r)
        fi
        chattr -R -i "$root" 2>/dev/null || true
        rm -rf "$root" 2>/dev/null || true
    }

    log INFO "Cleaning up liveroot build directories (including nested btrfs subvolumes)..."
    purge_nested_subvolumes "/home/eggs/liveroot/.snapshots"
    purge_nested_subvolumes "/home/eggs/liveroot"

    # =========================================================================
    # BUILD THE ISO
    # =========================================================================
    # There is no "--comp" flag in current eggs releases. Default
    # (sudo eggs produce) already uses fast zstd compression; --pendrive
    # gives a smaller/slower zstd build, --max gives the smallest/slowest
    # xz build. Use --nointeractive so this can run unattended.
    log INFO "Running: eggs produce --nointeractive"
    if ! eggs produce --nointeractive; then
        log WARN "eggs produce failed -- re-purging liveroot (including any subvolumes it created mid-build) and retrying once..."
        purge_nested_subvolumes "/home/eggs/liveroot/.snapshots"
        purge_nested_subvolumes "/home/eggs/liveroot"
        eggs produce --nointeractive
    fi
fi
