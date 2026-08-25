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
#   ./export-kde-theme-to-skel.sh                 # dry-run preview, everything
#   sudo ./export-kde-theme-to-skel.sh --apply    # export EVERYTHING for real
#   sudo ./export-kde-theme-to-skel.sh --apply --no-dconf   # skip dconf
#
# dconf export is ON BY DEFAULT. Opt out with --no-dconf.
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
for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=true ;;
        --with-dconf) WITH_DCONF=true ;;   # kept for backwards compatibility, now default anyway
        --no-dconf) WITH_DCONF=false ;;
    esac
done

EXPORT_DIR="${EXPORT_DIR:-$HOME/kde-theme-export}"

SRC_HOME="${HOME}"
SKEL="/etc/skel"

if [[ "$EUID" -eq 0 ]]; then
    echo "Please run this script as your normal user (it will call sudo itself when needed)." >&2
    exit 1
fi

echo "Source home : $SRC_HOME"
echo "Target skel : $SKEL"
echo "Export dir  : $EXPORT_DIR (for dconf dump)"
echo "Mode        : $([[ "$APPLY" == true ]] && echo APPLY || echo 'DRY RUN (pass --apply to actually copy)')"
echo

# --- Detect where the WhiteSur theme files actually live --------------------
# WhiteSur-kde / WhiteSur-gtk-theme installers can target either the user's
# home directory (default) or the whole system (`sudo ./install.sh`). If it
# went system-wide, the theme is already available to every user via
# /usr/share and this script doesn't need to (and can't, since it only reads
# $HOME) copy anything for it — only your kdeglobals/kwinrc selection of
# "WhiteSur" as the active theme name matters in that case.
echo "WhiteSur theme location check:"
check_theme_location() {
    local label="$1"; shift
    local user_hit=false sys_hit=false
    for p in "$@"; do
        case "$p" in
            "$SRC_HOME"/*) [[ -e "$p" ]] && user_hit=true ;;
            *)              [[ -e "$p" ]] && sys_hit=true ;;
        esac
    done
    if $user_hit; then
        echo "  $label: found under \$HOME — will be exported by this script."
    elif $sys_hit; then
        echo "  $label: found under /usr/share (system-wide install) — already available to all users, nothing to export."
    else
        echo "  $label: not found in either location — check it's actually installed."
    fi
}
check_theme_location "Plasma theme"       "$SRC_HOME"/.local/share/plasma/desktoptheme/WhiteSur* /usr/share/plasma/desktoptheme/WhiteSur*
check_theme_location "Window decoration"  "$SRC_HOME"/.local/share/aurorae/themes/WhiteSur* /usr/share/aurorae/themes/WhiteSur*
check_theme_location "Color scheme"       "$SRC_HOME"/.local/share/color-schemes/WhiteSur* /usr/share/color-schemes/WhiteSur*
check_theme_location "GTK theme"          "$SRC_HOME"/.themes/WhiteSur* /usr/share/themes/WhiteSur*
check_theme_location "Icon theme"         "$SRC_HOME"/.local/share/icons/WhiteSur* "$SRC_HOME"/.icons/WhiteSur* /usr/share/icons/WhiteSur*
check_theme_location "Kvantum theme"      "$SRC_HOME"/.config/Kvantum/WhiteSur* "$SRC_HOME"/.config/kvantum/WhiteSur* /usr/share/Kvantum/WhiteSur*
echo

# --- List of config paths (relative to $HOME) to export ---------------------
# --- Explicitly EXCLUDED: behavior, not theme ---------------------------------
# These files were considered and dropped because they're mostly or entirely
# BEHAVIOR settings, not appearance — not what "theme and beautification"
# should mean:
#   ~/.config/kwinrulesrc    — per-application window placement/size rules
#   ~/.config/klaunchrc      — busy-cursor / launch-feedback behavior
#   ~/.config/kcminputrc     — mouse/touchpad speed, acceleration, click
#                              behavior (its one theme-relevant key, cursor
#                              theme name, isn't worth pulling the whole
#                              behavioral file in for)
#   ~/.config/kscreenlockerrc — lock timeout / autolock timing behavior
#                               (its lock-screen theme key isn't worth it
#                               either — same tradeoff as above)

CONFIG_FILES=(
    .config/kdeglobals                                  # colors, fonts, widget style
    .config/kwinrc                                      # window decoration theme, effects
    .config/plasmarc                                    # Plasma theme
    .config/plasmashellrc                                # shell/panel appearance
    .config/plasma-org.kde.plasma.desktop-appletsrc      # panel & widget layout
    .config/ksplashrc                                     # boot splash theme
    .config/gtkrc
    .config/gtkrc-2.0
    .config/xsettingsd                                    # relays GTK theme name to X apps
    .gtkrc-2.0
)

# GTK config directories
CONFIG_DIRS=(
    .config/gtk-2.0
    .config/gtk-3.0
    .config/gtk-4.0
    .config/Kvantum
    .config/kvantum        # some setups use lowercase — copy_item skips whichever doesn't exist
    .config/fontconfig
)

# Local data: themes, icons, cursors, fonts, color schemes, panel/widget state,
# plasma look-and-feel packages — all pure appearance, nothing hardware- or
# behavior-bound
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

# --- Helper: copy one item preserving relative path -------------------------
copy_item() {
    local rel="$1"
    local src="${SRC_HOME}/${rel}"
    local dest="${SKEL}/${rel}"

    [[ -e "$src" ]] || return 0   # skip anything that doesn't exist

    echo "  + $rel"
    if [[ "$APPLY" == true ]]; then
        sudo mkdir -p "$(dirname "$dest")"
        sudo cp -a --no-preserve=ownership "$src" "$dest"
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
if [[ "$APPLY" == true ]]; then
    sudo chown -R root:root "$SKEL"
    sudo chmod -R go+rX "$SKEL"
    echo "Done. /etc/skel updated — new users will inherit this KDE/GTK setup."
    echo "Existing users are unaffected; copy manually to their \$HOME if needed."
else
    echo "Dry run complete — nothing was written."
    echo "Re-run with --apply (and sudo not required up front, script will sudo internally) to perform the copy:"
    echo "  ./export-kde-theme-to-skel.sh --apply"
fi

# --- dconf / gsettings export -----------------------------------------------
# gsettings is just a CLI on top of dconf, so exporting the relevant dconf
# paths covers both. These paths cover GTK/libadwaita theming, dark-mode
# preference, fonts, and cursor — the keys GTK4 apps commonly read instead
# of gtk-4.0/settings.ini.
# --- Explicitly EXCLUDED: hardware/device-bound config -----------------------
# These are deliberately left out because they're tied to THIS machine's
# specific hardware (monitor EDID/serial, peripheral vendor/product IDs) and
# have no business being baked into a generic installer image:
#   ~/.local/share/kscreen/          — per-monitor layout, keyed by EDID hash
#   ~/.config/kwinoutputconfig.json  — Wayland per-output config, same issue
#   /org/gnome/desktop/peripherals/  — per-mouse/touchpad/tablet dconf keys,
#                                       keyed by USB vendor+product ID
# Letting KScreen/KWin auto-detect displays and libinput auto-detect
# peripherals on first boot is the correct behavior for a fresh install.

DCONF_PATHS=(
    /org/gnome/desktop/interface/    # includes font-name, monospace-font-name, document-font-name
    /org/gnome/desktop/wm/preferences/
    /org/gnome/desktop/sound/
    /org/gtk/settings/file-chooser/
    /org/gtk/settings/color-chooser/
)

if [[ "$WITH_DCONF" == true ]]; then
    echo
    echo "dconf/gsettings export:"

    if ! command -v dconf >/dev/null 2>&1; then
        echo "  dconf command not found — skipping (install 'dconf-cli' / 'dconf' package)." >&2
    else
        mkdir -p "$EXPORT_DIR"
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
            echo "  Installed as system dconf default profile (/etc/dconf/db/site.d/00-gtk-theme)."
            echo "  Applies to ALL users at next login unless they've overridden a key themselves."
        else
            echo "  (dry run — not installed to /etc/dconf; re-run with --apply --with-dconf)"
        fi
    fi
else
    echo
    echo "(dconf/gsettings export skipped — ran with --no-dconf)"
fi

# --- SDDM (login screen) export ---------------------------------------------
# Excluded — SDDM handling was dropped from this script by request.
# If you need it later: SDDM config lives in /etc/sddm.conf(.d), and the
# active theme's files live in /usr/share/sddm/themes/<name>. Neither
# belongs in /etc/skel (it's not per-user), so it would need its own
# bundle/export step separate from everything above.

echo
echo "Export bundle root: $EXPORT_DIR"
