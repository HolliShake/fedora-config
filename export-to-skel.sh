#!/usr/bin/env bash
#
# export-kde-theme-to-skel.sh
#
# Full KDE Plasma + GTK "look & feel" exporter, for baking a themed config
# into a system installer/image. Covers:
#
#   1. /etc/skel   — user-space config: KDE, GTK2/3/4, fonts, panel & widget
#                    layout, icon/cursor/window theme selection + files.
#   2. dconf/gsettings — system-wide default profile for GTK4/libadwaita
#                    apps that read theme/font/cursor from dconf instead of
#                    settings.ini. Applies to ALL users, not just new ones.
#
# Usage:
#   ./export-kde-theme-to-skel.sh                    # dry-run preview, everything
#   sudo ./export-kde-theme-to-skel.sh --apply        # export EVERYTHING for real
#   sudo ./export-kde-theme-to-skel.sh --apply --no-dconf   # skip dconf
#   ./export-kde-theme-to-skel.sh --diff              # show what WOULD change, no writes
#   sudo ./export-kde-theme-to-skel.sh --rollback     # restore /etc/skel + dconf from
#                                                      #   the most recent backup
#   sudo ./export-kde-theme-to-skel.sh --rollback --backup /path/to/skel-backup-*.tar.gz
#
# dconf export is ON BY DEFAULT. Opt out with --no-dconf.
#
# New in this version:
#   - Timestamped tar backup of /etc/skel (and the dconf site db) taken
#     automatically before any --apply write, so a bad export is reversible.
#   - --rollback restores the most recent backup (or one you name).
#   - --diff compares $HOME against the current /etc/skel and reports
#     new / changed / identical / skel-only items — no sudo, no writes.
#   - A manifest (path, sha256, size) is written for every applied export
#     so you have an audit trail of exactly what landed in /etc/skel.
#   - Upfront sudo validation with a keep-alive so the script doesn't die
#     halfway through a long copy waiting on a password prompt.
#   - SELF-CONTAINED EXPORT: every copy fully dereferences symlinks (-L), so
#     e.g. ~/.config/gtk-4.0/gtk-dark.css (normally a symlink into a theme
#     package under /usr/share or $HOME) becomes a real file with the theme's
#     actual CSS content. Built for baking into a distro image: a fresh
#     install shouldn't need the original theme package installed at all for
#     GTK4/libadwaita apps to pick up the look. Any symlink that couldn't be
#     dereferenced (broken target) is reported after the copy.
#   - Wallpaper Image= references (absolute paths with your username in them)
#     are rewritten to a stable system path so they aren't $HOME-bound either.
#
# Notes:
#   - Must be run as the user whose config you want to export (NOT as root),
#     but needs sudo/root to write to /etc/skel and /etc/dconf —
#     the script calls sudo internally as needed.
#   - /etc/skel affects new users' home directories only.
#   - The dconf site profile affects ALL users' default values.
#   - Review everything before folding this into an image build.

set -euo pipefail

APPLY=false
WITH_DCONF=true
DIFF_MODE=false
ROLLBACK=false
ROLLBACK_ARCHIVE=""

for arg in "$@"; do
    case "$arg" in
        --apply)      APPLY=true ;;
        --with-dconf) WITH_DCONF=true ;;   # kept for backwards compatibility, now default anyway
        --no-dconf)   WITH_DCONF=false ;;
        --diff)       DIFF_MODE=true ;;
        --rollback)   ROLLBACK=true ;;
        --backup=*)   ROLLBACK_ARCHIVE="${arg#--backup=}" ;;
        --backup)     : ;;  # value grabbed below if given as separate arg
        -h|--help)
            grep '^#' "$0" | sed 's/^#//' | sed '1d'
            exit 0
            ;;
    esac
done
# support `--rollback --backup /path` (space-separated form)
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
# Where wallpaper image files get "rehomed" to so config referencing them
# is no longer tied to $SRC_HOME's path or username.
WALLPAPER_SYSTEM_DIR="${WALLPAPER_SYSTEM_DIR:-/usr/share/wallpapers/site-default}"

if [[ "$EUID" -eq 0 ]]; then
    echo "Please run this script as your normal user (it will call sudo itself when needed)." >&2
    exit 1
fi

# --- Colors (only if stdout is a real terminal) ------------------------------
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
    C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'; C_DIM=$'\033[2m'
else
    C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""; C_DIM=""
fi

mkdir -p "$EXPORT_DIR" "$BACKUP_DIR" "$MANIFEST_DIR"

log() {
    # log <level> <message>  — prints to screen with color, appends plain text to LOG_FILE
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
    # human_size <bytes> -> e.g. "12.4M"
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
# ROLLBACK MODE — restore /etc/skel (and dconf site db) from a backup archive
# =============================================================================
if $ROLLBACK; then
    if [[ -z "$ROLLBACK_ARCHIVE" ]]; then
        ROLLBACK_ARCHIVE="$(ls -1t "${BACKUP_DIR}"/skel-backup-*.tar.gz 2>/dev/null | head -n1 || true)"
    fi

    if [[ -z "$ROLLBACK_ARCHIVE" || ! -f "$ROLLBACK_ARCHIVE" ]]; then
        log ERR "No backup archive found. Looked in: ${BACKUP_DIR}/skel-backup-*.tar.gz"
        log ERR "Pass one explicitly with --rollback --backup /path/to/file.tar.gz"
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
    else
        log WARN "No matching dconf backup found alongside archive (${DCONF_BACKUP}) — dconf left untouched."
    fi

    exit 0
fi

# --- Detect where the WhiteSur theme files actually live --------------------
echo "Theme location check:"
check_theme_location() {
    local label="$1"; shift
    local user_hit=false sys_hit=false
    for p in "$@"; do
        case "$p" in
            "$SRC_HOME"/*) [[ -e "$p" ]] && user_hit=true ;;
            *)             [[ -e "$p" ]] && sys_hit=true ;;
        esac
    done
    if $user_hit; then
        echo "  $label: ${C_GREEN}found under \$HOME${C_RESET} — will be copied and dereferenced into skel."
    elif $sys_hit; then
        echo "  $label: ${C_YELLOW}found under /usr/share only${C_RESET} — the theme PACKAGE itself is not copied by"
        echo "      this script (it lives outside \$HOME). Any symlink referencing it (e.g. in gtk-4.0)"
        echo "      WILL be dereferenced into real file content, but for GTK3/Plasma theme-by-NAME lookups"
        echo "      to work on a fresh install, make sure the '$label' package is also in your distro image."
    else
        echo "  $label: ${C_YELLOW}not found in either location${C_RESET} — check it's actually installed."
    fi
}
check_theme_location "Plasma theme"       "$SRC_HOME"/.local/share/plasma/desktoptheme/WhiteSur* /usr/share/plasma/desktoptheme/WhiteSur*
check_theme_location "Window decoration"  "$SRC_HOME"/.local/share/aurorae/themes/WhiteSur* /usr/share/aurorae/themes/WhiteSur*
check_theme_location "Color scheme"       "$SRC_HOME"/.local/share/color-schemes/WhiteSur* /usr/share/color-schemes/WhiteSur*
check_theme_location "GTK theme"          "$SRC_HOME"/.themes/WhiteSur* /usr/share/themes/WhiteSur*
check_theme_location "Icon theme"         "$SRC_HOME"/.local/share/icons/WhiteSur* "$SRC_HOME"/.icons/WhiteSur* /usr/share/icons/WhiteSur*
check_theme_location "Kvantum theme"      "$SRC_HOME"/.config/Kvantum/WhiteSur* "$SRC_HOME"/.config/kvantum/WhiteSur* /usr/share/Kvantum/WhiteSur*
echo

echo "${C_DIM}Note: the wallpaper *image* is exported as a plain file, and any theme"
echo "config that was a symlink (e.g. gtk-4.0/*.css) is now dereferenced into real"
echo "file content, so \$SKEL is self-contained — no dependency on /usr/share or"
echo "\$HOME existing on the target machine. The wallpaper's Image= reference"
echo "(an absolute path with your username in it) is rewritten on --apply to"
echo "point at $WALLPAPER_SYSTEM_DIR instead. Per-screen containment layout itself"
echo "is not restructured — a very different monitor count on the target machine"
echo "may still cause Plasma to fall back to its own default for that screen.${C_RESET}"
echo

# --- List of config paths (relative to $HOME) to export ---------------------
CONFIG_FILES=(
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
)

# GTK config directories
CONFIG_DIRS=(
    .config/gtk-2.0
    .config/gtk-3.0
    .config/gtk-4.0
    .config/Kvantum
    .config/kvantum
    .config/fontconfig
)

# Local data: themes, icons, cursors, fonts, color schemes
DATA_DIRS=(
    .local/share/plasma
    .local/share/color-schemes
    .local/share/icons
    .local/share/aurorae
    .local/share/wallpapers
    .local/share/plasma_look_and_feel
    .local/share/konsole
    .local/share/fonts
    .themes
    .icons
    .fonts
)

ALL_ITEMS=("${CONFIG_FILES[@]}" "${CONFIG_DIRS[@]}" "${DATA_DIRS[@]}")

# =============================================================================
# DIFF MODE — compare $HOME against current /etc/skel, no writes, no sudo
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
    echo "(diff mode only — nothing was read from or written to /etc/skel; re-run with --apply to sync)"
    exit 0
fi

# --- Pre-flight: validate sudo up front, keep it alive while we work --------
if [[ "$APPLY" == true ]]; then
    log INFO "Requesting sudo access up front (needed for /etc/skel and /etc/dconf writes)..."
    if ! sudo -v; then
        log ERR "Could not obtain sudo access. Aborting before touching anything."
        exit 1
    fi
    # keep-alive: refresh the sudo timestamp every 60s until this script exits
    ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap '[[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
fi

# --- Backup existing /etc/skel before writing anything -----------------------
BACKUP_ARCHIVE=""
if [[ "$APPLY" == true ]]; then
    if [[ -d "$SKEL" ]] && sudo find "$SKEL" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
        BACKUP_ARCHIVE="${BACKUP_DIR}/skel-backup-${TIMESTAMP}.tar.gz"
        log INFO "Backing up current $SKEL -> $BACKUP_ARCHIVE"
        sudo tar -czf "$BACKUP_ARCHIVE" -C / "${SKEL#/}"
        sudo chown "$(id -u):$(id -g)" "$BACKUP_ARCHIVE"
        log OK "Backup complete ($(human_size "$(stat -c%s "$BACKUP_ARCHIVE" 2>/dev/null || echo 0)"))."
    else
        log INFO "$SKEL is empty or missing — no backup needed."
    fi
    if [[ -f /etc/dconf/db/site.d/00-gtk-theme && -n "$BACKUP_ARCHIVE" ]]; then
        sudo cp /etc/dconf/db/site.d/00-gtk-theme "${BACKUP_ARCHIVE%.tar.gz}.dconf-site"
        sudo chown "$(id -u):$(id -g)" "${BACKUP_ARCHIVE%.tar.gz}.dconf-site"
        log OK "Backed up existing dconf site db alongside it."
    fi
fi

MANIFEST_FILE="${MANIFEST_DIR}/manifest-${TIMESTAMP}.tsv"
[[ "$APPLY" == true ]] && printf 'path\tsha256\tsize_bytes\n' > "$MANIFEST_FILE"

TOTAL_FILES=0
TOTAL_BYTES=0

# --- Helper: copy one item preserving relative path -------------------------
# IMPORTANT: this fully DEREFERENCES symlinks (-L). For a distro build, skel
# must be self-contained — a symlink to /usr/share/themes/X or to $HOME is a
# dependency on something that may not exist on the target machine at all.
# So every symlink encountered (wherever it points) is resolved to its real
# file content at export time. GTK4/libadwaita apps in particular look for
# literal files at ~/.config/gtk-4.0/{gtk.css,gtk-dark.css,...} — theme
# installers normally just symlink those to the theme package; we want the
# actual bytes there instead so nothing else needs to be installed.
copy_item() {
    local rel="$1"
    local src="${SRC_HOME}/${rel}"
    local dest="${SKEL}/${rel}"

    [[ -e "$src" ]] || return 0   # skip anything that doesn't exist (also skips broken top-level symlinks)

    echo "  + $rel"
    if [[ "$APPLY" == true ]]; then
        if [[ -d "$src" ]]; then
            # Directory: create target directory and copy contents explicitly
            # using '/.' to prevent cp from creating nested directory trees.
            # -L dereferences any symlinks found inside (e.g. gtk-4.0/gtk-dark.css
            # -> real theme file), so the copy is self-contained.
            sudo mkdir -p "$dest"
            if ! sudo cp -aL --no-preserve=ownership "$src"/. "$dest"/ 2>/tmp/copy-err.$$; then
                log WARN "Some items under $rel could not be fully dereferenced (likely a broken symlink pointing at a missing theme file):"
                sed 's/^/      /' /tmp/copy-err.$$ 2>/dev/null || true
            fi
            rm -f /tmp/copy-err.$$
        else
            # File (or top-level symlink to a file): create parent directory,
            # dereference into real content.
            sudo mkdir -p "$(dirname "$dest")"
            sudo cp -aL --no-preserve=ownership "$src" "$dest"
        fi

        # Record every regular file under this item in the manifest
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

    # --- Rehome wallpaper Image= references out of $SRC_HOME -------------
    # plasma-org.kde.plasma.desktop-appletsrc (and sometimes kdeglobals)
    # stores the wallpaper as an absolute file:// path under the exporting
    # user's home. Copied as-is, that path is meaningless (or wrong) for a
    # new user. Move the actual image to a stable system location and
    # rewrite the reference to point there instead.
    log INFO "Rehoming wallpaper image references out of \$SRC_HOME..."
    WALLPAPER_CFG_FILES=(
        "$SKEL/.config/plasma-org.kde.plasma.desktop-appletsrc"
        "$SKEL/.config/kdeglobals"
    )
    for cfgfile in "${WALLPAPER_CFG_FILES[@]}"; do
        [[ -f "$cfgfile" ]] || continue
        while IFS= read -r line; do
            raw="${line#Image=}"
            path="${raw#file://}"
            [[ "$path" == "$SRC_HOME"* ]] || continue
            [[ -f "$path" ]] || continue
            base="$(basename "$path")"
            sudo mkdir -p "$WALLPAPER_SYSTEM_DIR"
            sudo cp -n "$path" "$WALLPAPER_SYSTEM_DIR/$base" 2>/dev/null || true
            sudo sed -i "s#file://${path//\//\\/}#file://${WALLPAPER_SYSTEM_DIR}/${base}#g" "$cfgfile"
            echo "  -> Rehomed: $base -> $WALLPAPER_SYSTEM_DIR/$base"
            WALLPAPERS_REHOMED=$((WALLPAPERS_REHOMED + 1))
        done < <(sudo grep -h '^Image=' "$cfgfile" 2>/dev/null)
    done
    if [[ "$WALLPAPERS_REHOMED" -gt 0 ]]; then
        sudo chmod -R go+rX "$WALLPAPER_SYSTEM_DIR"
        log OK "Rehomed $WALLPAPERS_REHOMED wallpaper reference(s) to $WALLPAPER_SYSTEM_DIR."
    else
        log INFO "No \$HOME-bound wallpaper Image= references found to rehome."
    fi

    # --- Verify the export is actually self-contained ---------------------
    # After -L dereferencing above, nothing under $SKEL should still be a
    # symlink. If something is, it means cp couldn't resolve it (a broken
    # symlink whose target theme file/dir doesn't exist) — flag it loudly,
    # since a distro image built from this skel would ship the same break
    # to every new user.
    log INFO "Verifying export is self-contained (no leftover symlinks)..."
    while IFS= read -r symlink; do
        tgt="$(sudo readlink "$symlink" || true)"
        log WARN "Leftover symlink (not dereferenced — target likely missing): ${symlink#$SKEL/} -> $tgt"
        BROKEN_SYMLINKS=$((BROKEN_SYMLINKS + 1))
    done < <(sudo find "$SKEL" -type l 2>/dev/null)

    sudo chown -Rh root:root "$SKEL"
    sudo chmod -R go+rX "$SKEL"

    log OK "Done. /etc/skel updated — new users will inherit this KDE/GTK setup."
    log INFO "Existing users are unaffected; copy manually to their \$HOME if needed."
    [[ -n "$BACKUP_ARCHIVE" ]] && log INFO "Rollback available via: $0 --rollback --backup $BACKUP_ARCHIVE"
else
    echo "Dry run complete — nothing was written."
    echo "Re-run with --apply (and sudo not required up front, script will sudo internally) to perform the copy:"
    echo "  ./export-kde-theme-to-skel.sh --apply"
fi

# --- dconf / gsettings export -----------------------------------------------
DCONF_PATHS=(
    /org/gnome/desktop/interface/    # includes color-scheme needed for Libadwaita light/dark preference
    /org/gnome/desktop/wm/preferences/
    /org/gnome/desktop/sound/
    /org/gtk/settings/file-chooser/
    /org/gtk/settings/color-chooser/
)

if [[ "$WITH_DCONF" == true ]]; then
    echo
    echo "dconf/gsettings export:"

    if ! command -v dconf >/dev/null 2>&1; then
        log WARN "dconf command not found — skipping (install 'dconf-cli' / 'dconf' package)."
    else
        DUMP_FILE="${EXPORT_DIR}/gtk-dconf-export.ini"
        : > "$DUMP_FILE.tmp"

        for path in "${DCONF_PATHS[@]}"; do
            echo "  dumping $path"
            section="[$(basename "${path%/}")]"
            {
                echo "$section"
                dconf dump "$path" | tail -n +2   # strip dconf's own [/] header, keep keys
            } >> "$DUMP_FILE.tmp" 2>/dev/null || true
            echo >> "$DUMP_FILE.tmp"
        done
        mv "$DUMP_FILE.tmp" "$DUMP_FILE"

        echo "  -> dumped to $DUMP_FILE"

        if [[ "$APPLY" == true ]]; then
            sudo mkdir -p /etc/dconf/db/site.d /etc/dconf/profile
            sudo cp "$DUMP_FILE" /etc/dconf/db/site.d/00-gtk-theme
            # Point the default user profile at the system 'site' db as a
            # fallback layer beneath each user's own settings.
            if [[ ! -f /etc/dconf/profile/user ]]; then
                printf 'user-db:user\nsystem-db:site\n' | sudo tee /etc/dconf/profile/user >/dev/null
            fi
            sudo dconf update
            log OK "Installed as system dconf default profile (/etc/dconf/db/site.d/00-gtk-theme)."
            log INFO "Applies to ALL users at next login unless they've overridden a key themselves."
        else
            echo "  (dry run — not installed to /etc/dconf; re-run with --apply --with-dconf)"
        fi
    fi
else
    echo
    echo "(dconf/gsettings export skipped — ran with --no-dconf)"
fi

echo
echo "${C_BOLD}Export bundle root: $EXPORT_DIR${C_RESET}"

# --- Summary -------------------------------------------------------------
if [[ "$APPLY" == true ]]; then
    echo
    echo "${C_BOLD}Summary${C_RESET}"
    echo "  Files copied     : $TOTAL_FILES"
    echo "  Total size       : $(human_size "$TOTAL_BYTES")"
    echo "  Manifest         : $MANIFEST_FILE"
    echo "  Wallpapers rehomed: $WALLPAPERS_REHOMED (to $WALLPAPER_SYSTEM_DIR)"
    [[ -n "$BACKUP_ARCHIVE" ]] && echo "  Backup           : $BACKUP_ARCHIVE"
    if [[ "$BROKEN_SYMLINKS" -gt 0 ]]; then
        log WARN "$BROKEN_SYMLINKS leftover symlink(s) under /etc/skel — skel is NOT fully self-contained. Check the warnings above."
    else
        log OK "Skel is fully self-contained — no symlinks left under /etc/skel."
    fi
    echo "  Log              : $LOG_FILE"
fi
