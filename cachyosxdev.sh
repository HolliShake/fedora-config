#!/bin/bash
# ==============================================================================
# Unified macOS-like Theming Script for KDE Plasma 6 & GTK/GNOME
# Validated + hardened version — no wallpaper handling included.
# ==============================================================================

set -uo pipefail  # (not -e: we want to warn and continue, not abort on the first issue)

# === User-defined variables ===
KDE_COLOR_SCHEME="WhiteSurDark"
KDE_WIDGET_STYLE="kvantum-dark"        # matches System Settings > Application Style: "kvantum-dark"
KVANTUM_THEME="WhiteSur"               # Note: Depending on your installation, the dark variant might actually require "WhiteSurDark" here.
PLASMA_STYLE="WhiteSur-dark"           # System Settings > Plasma Style (a.k.a. Desktop Theme)
SPLASH_THEME="WhiteSur-dark"           # System Settings > Splash Screen
AURORAE_THEME="WhiteSur-dark"
GTK_THEME="WhiteSur-Dark-solid"
ICON_THEME="WhiteSur-dark"
CURSOR_THEME="WhiteSur-cursors"
CURSOR_SIZE=24

# === Logging helpers ===
info()  { echo "🔹 $*"; }
ok()    { echo "✔ $*"; }
warn()  { echo "⚠ WARNING: $*"; }
err()   { echo "❌ ERROR: $*"; }

# === Capability / tool checks ===
has_cmd() { command -v "$1" >/dev/null 2>&1; }

HAS_KDE_TOOLS=false
HAS_GNOME_TOOLS=false

if has_cmd kwriteconfig6 && has_cmd qdbus; then
    HAS_KDE_TOOLS=true
else
    warn "kwriteconfig6/qdbus not found — skipping KDE Plasma configuration."
fi

if has_cmd gsettings; then
    HAS_GNOME_TOOLS=true
else
    warn "gsettings not found — skipping GNOME/GTK configuration."
fi

if ! $HAS_KDE_TOOLS && ! $HAS_GNOME_TOOLS; then
    err "Neither KDE nor GNOME tooling is available on this system. Aborting."
    exit 1
fi

# === Theme lookup helper ===
find_theme_dir() {
    local subdir="$1" theme="$2"
    local bases=("/usr/share/$subdir" "$HOME/.local/share/$subdir" "/usr/local/share/$subdir")
    case "$subdir" in
        themes) bases+=("$HOME/.themes") ;;
        icons)  bases+=("$HOME/.icons") ;;
    esac
    for base in "${bases[@]}"; do
        if [ -d "$base/$theme" ]; then
            echo "$base/$theme"
            return 0
        fi
    done
    return 1
}

# === Theme presence checks ===
info "Checking themes and icons..."

GTK_THEME_DIR="$(find_theme_dir "themes" "$GTK_THEME")" || { err "GTK theme '$GTK_THEME' not found."; exit 1; }
ok "Found GTK theme at $GTK_THEME_DIR"

ICON_THEME_DIR="$(find_theme_dir "icons" "$ICON_THEME")" || { err "Icon theme '$ICON_THEME' not found."; exit 1; }
ok "Found icon theme at $ICON_THEME_DIR"

CURSOR_THEME_DIR="$(find_theme_dir "icons" "$CURSOR_THEME")" || { err "Cursor theme '$CURSOR_THEME' not found."; exit 1; }
ok "Found cursor theme at $CURSOR_THEME_DIR"

if AURORAE_DIR="$(find_theme_dir "aurorae/themes" "$AURORAE_THEME")"; then
    ok "Found Aurorae theme at $AURORAE_DIR"
else
    warn "Aurorae theme '$AURORAE_THEME' not found system-wide or user-locally."
fi

if PLASMA_STYLE_DIR="$(find_theme_dir "plasma/desktoptheme" "$PLASMA_STYLE")"; then
    ok "Found Plasma Style at $PLASMA_STYLE_DIR"
else
    warn "Plasma Style '$PLASMA_STYLE' not found under plasma/desktoptheme."
fi

KVANTUM_SEARCH_DIRS=("/usr/share/Kvantum" "$HOME/.local/share/Kvantum" "$HOME/.config/Kvantum")
KVANTUM_THEME_DIR=""
for base in "${KVANTUM_SEARCH_DIRS[@]}"; do
    if [ -d "$base/$KVANTUM_THEME" ]; then
        KVANTUM_THEME_DIR="$base/$KVANTUM_THEME"
        break
    fi
done
if [ -n "$KVANTUM_THEME_DIR" ]; then
    ok "Found Kvantum theme at $KVANTUM_THEME_DIR"
else
    warn "Kvantum theme '$KVANTUM_THEME' not found in expected Kvantum directories."
fi

# ==============================================================================
# === KDE Plasma 6 configuration ==============================================
# ==============================================================================
if $HAS_KDE_TOOLS; then
    info "Applying KDE Plasma 6 theme settings..."

    if has_cmd plasma-apply-colorscheme; then
        if plasma-apply-colorscheme "$KDE_COLOR_SCHEME" >/dev/null 2>&1; then
            ok "Applied color scheme via plasma-apply-colorscheme."
        else
            warn "plasma-apply-colorscheme failed, falling back to kwriteconfig6."
            kwriteconfig6 --file kdeglobals --group General --key ColorScheme "$KDE_COLOR_SCHEME"
        fi
    else
        kwriteconfig6 --file kdeglobals --group General --key ColorScheme "$KDE_COLOR_SCHEME"
    fi

    kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle "$KDE_WIDGET_STYLE"
    kwriteconfig6 --file kdeglobals --group Icons --key Theme "$ICON_THEME"
    kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme "$CURSOR_THEME"
    kwriteconfig6 --file kcminputrc --group Mouse --key cursorSize "$CURSOR_SIZE"

    kwriteconfig6 --file kwinrc --group DesktopSwitcher --key LayoutName "org.kde.breeze.desktop"
    kwriteconfig6 --file kwinrc --group WindowSwitcher --key LayoutName "org.kde.breeze.desktop"

    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library "org.kde.kwin.aurorae.v2"
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme "$AURORAE_THEME"
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key BorderSize "Tiny"
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft "XIA"
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight ""

    if has_cmd plasma-apply-desktoptheme; then
        if plasma-apply-desktoptheme "$PLASMA_STYLE" >/dev/null 2>&1; then
            ok "Applied Plasma Style via plasma-apply-desktoptheme."
        else
            kwriteconfig6 --file plasmarc --group Theme --key name "$PLASMA_STYLE"
        fi
    else
        kwriteconfig6 --file plasmarc --group Theme --key name "$PLASMA_STYLE"
    fi

    kwriteconfig6 --file ksplashrc --group KSplash --key Theme "$SPLASH_THEME"
    ok "Set Splash Screen to '$SPLASH_THEME'."

    # === FIXED KVANTUM SECTION (Combined Approach) ===
    # Step 1: Forcefully write to the config file directly
    mkdir -p "$HOME/.config/Kvantum"
    KVANTUM_CONFIG_FILE="$HOME/.config/Kvantum/kvantum.kvconfig"
    cat > "$KVANTUM_CONFIG_FILE" <<EOF
[General]
theme=$KVANTUM_THEME
EOF
    ok "Set Kvantum theme to '$KVANTUM_THEME' by directly writing to $(basename "$KVANTUM_CONFIG_FILE")."

    # Step 2: Push the update via the command-line tool if available
    if has_cmd kvantummanager; then
        kvantummanager --set "$KVANTUM_THEME" >/dev/null 2>&1
        ok "Additionally triggered Kvantum update via 'kvantummanager --set'."
    fi

    ok "KDE Plasma settings applied."
else
    warn "Skipped KDE Plasma section."
fi

# ==============================================================================
# === GNOME / GTK fallback configuration =======================================
# ==============================================================================
if $HAS_GNOME_TOOLS; then
    info "Applying GNOME/GTK fallback settings..."
    gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME"
    gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME"
    gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME"
    gsettings set org.gnome.desktop.interface cursor-size "$CURSOR_SIZE"
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
    gsettings set org.gnome.desktop.wm.preferences button-layout "close,minimize,maximize:"
    ok "GNOME/GTK settings applied."
fi

# ==============================================================================
# === GTK2 / GTK3 / GTK4 asset + CSS linking ===================================
# ==============================================================================
info "Generating GTK2 .gtkrc-2.0 configuration..."
cat > "$HOME/.gtkrc-2.0" <<EOF
gtk-enable-animations=1
gtk-theme-name="$GTK_THEME"
gtk-primary-button-warps-slider=1
gtk-toolbar-style=3
gtk-menu-images=1
gtk-button-images=1
gtk-cursor-blink-time=1000
gtk-cursor-blink=1
gtk-cursor-theme-size=$CURSOR_SIZE
gtk-cursor-theme-name="$CURSOR_THEME"
gtk-sound-theme-name="ocean"
gtk-icon-theme-name="$ICON_THEME"
gtk-font-name="Noto Sans,  10"

gtk-modules=appmenu-gtk-module
EOF
ok "Created GTK 2.0 customized .gtkrc-2.0"

info "Linking GTK3 and GTK4 theme files and generating settings..."

for GTK_VERSION in "gtk-3.0" "gtk-4.0"; do
    GTK_CONFIG="$HOME/.config/$GTK_VERSION"
    THEME_PATH="$GTK_THEME_DIR/$GTK_VERSION"
    ASSETS_PATH="$THEME_PATH/assets"

    mkdir -p "$GTK_CONFIG"

    if [ "$GTK_VERSION" = "gtk-3.0" ]; then
        cat > "$GTK_CONFIG/settings.ini" <<EOF
[Settings]
gtk-application-prefer-dark-theme=true
gtk-button-images=true
gtk-cursor-blink=true
gtk-cursor-blink-time=1000
gtk-cursor-theme-name=$CURSOR_THEME
gtk-cursor-theme-size=$CURSOR_SIZE
gtk-decoration-layout=close,minimize,maximize:
gtk-enable-animations=true
gtk-font-name=Noto Sans 10
gtk-icon-theme-name=$ICON_THEME
gtk-menu-images=true
gtk-modules=colorreload-gtk-module:window-decorations-gtk-module:appmenu-gtk-module
gtk-primary-button-warps-slider=true
gtk-shell-shows-menubar=1
gtk-sound-theme-name=ocean
gtk-theme-name=$GTK_THEME
gtk-toolbar-style=3
gtk-xft-dpi=98304
EOF
        ok "Created GTK 3.0 customized settings.ini"
    else
        cat > "$GTK_CONFIG/settings.ini" <<EOF
[Settings]
gtk-application-prefer-dark-theme=true
gtk-cursor-blink=true
gtk-cursor-blink-time=1000
gtk-cursor-theme-name=$CURSOR_THEME
gtk-cursor-theme-size=$CURSOR_SIZE
gtk-decoration-layout=close,maximize,minimize:
gtk-enable-animations=true
gtk-font-name=Noto Sans 10
gtk-icon-theme-name=$ICON_THEME
gtk-primary-button-warps-slider=true
gtk-sound-theme-name=ocean
gtk-theme-name=$GTK_THEME
gtk-xft-dpi=98304
EOF
        ok "Created GTK 4.0 customized settings.ini"
    fi

    rm -rf "$GTK_CONFIG/assets"
    rm -f "$GTK_CONFIG/gtk.css" "$GTK_CONFIG/gtk-dark.css"

    if [ -d "$ASSETS_PATH" ]; then
        cp -r "$ASSETS_PATH" "$GTK_CONFIG/assets"
        ok "Copied assets directory for $GTK_VERSION"
    fi

    if [ -f "$THEME_PATH/gtk.css" ]; then
        cp "$THEME_PATH/gtk.css" "$GTK_CONFIG/gtk.css"
        ok "Copied gtk.css for $GTK_VERSION"
    fi

    if [ -f "$THEME_PATH/gtk-dark.css" ]; then
        ln -s "$THEME_PATH/gtk-dark.css" "$GTK_CONFIG/gtk-dark.css"
        ok "Linked gtk-dark.css for $GTK_VERSION"
    fi
done

# ==============================================================================
# === Reload Desktop Environment ==============================================
# ==============================================================================
if $HAS_KDE_TOOLS; then
    info "Reloading KWin and Plasma..."
    qdbus org.kde.KWin /KWin reconfigure 2>/dev/null || warn "Could not signal KWin to reconfigure."
    qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.refreshCurrentShell 2>/dev/null || warn "Could not refresh Plasma shell."
fi

echo "✨ macOS-style theme successfully applied (wallpaper untouched, as requested)."
