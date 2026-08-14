#!/bin/bash

# ==============================================================================
# Unified macOS-like Theming Script for KDE Plasma 6 & GTK
# ==============================================================================

# === User-defined variables ===
KDE_COLOR_SCHEME="WhiteSurDark"
KDE_WIDGET_STYLE="kvantum"
AURORAE_THEME="__aurorae__svg__WhiteSur-dark"
GTK_THEME="WhiteSur-Dark-solid"
ICON_THEME="WhiteSur-dark"
CURSOR_THEME="WhiteSur-cursors"
WALLPAPER_PATH="/usr/share/wallpapers/WhiteSur.jpg" # Adjust to your distro's wallpaper path

# === Theme checks ===
echo "🧩 Checking themes and icons..."

if [ ! -d "/usr/share/themes/$GTK_THEME" ]; then
    echo "❌ ERROR: GTK theme '$GTK_THEME' not found in /usr/share/themes/!"
    exit 1
fi

if [ ! -d "/usr/share/icons/$ICON_THEME" ]; then
    echo "❌ ERROR: Icon theme '$ICON_THEME' not found in /usr/share/icons/!"
    exit 1
fi

if [ ! -d "/usr/share/icons/$CURSOR_THEME" ]; then
    echo "❌ ERROR: Cursor theme '$CURSOR_THEME' not found in /usr/share/icons/!"
    exit 1
fi

if [ ! -d "/usr/share/aurorae/themes/$AURORAE_THEME" ]; then
    echo "⚠ WARNING: Aurorae theme '$AURORAE_THEME' not found system-wide!"
fi

# === Apply KDE Plasma 6 settings (kwriteconfig6) ===
echo "🎨 Applying KDE Plasma 6 theme settings..."
kwriteconfig6 --file kdeglobals --group General --key ColorScheme "$KDE_COLOR_SCHEME"
kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle "$KDE_WIDGET_STYLE"
kwriteconfig6 --file kdeglobals --group Icons --key Theme "$ICON_THEME"
kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme "$CURSOR_THEME"

# Set Window Decorations (Aurorae) & move buttons (XIA = close, minimize, maximize on left)
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library "org.kde.kwin.aurorae.v2"
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme "$AURORAE_THEME"
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft "XIA"
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight ""

# === Apply GTK / GNOME fallback settings (gsettings) ===
echo "🎨 Applying GNOME/GTK fallback settings..."
gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME"
gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME"
gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME"
gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
# The GTK equivalent to KWin's "XIA":
gsettings set org.gnome.desktop.wm.preferences button-layout "close,minimize,maximize:"

# === Set Wallpaper (KDE DBus Method) ===
echo "🖼️  Setting desktop background..."
if [ -f "$WALLPAPER_PATH" ]; then
    qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
        var allDesktops = desktops();
        for (i=0;i<allDesktops.length;i++) {
            d = allDesktops[i];
            d.wallpaperPlugin = 'org.kde.image';
            d.currentConfigGroup = Array('Wallpaper', 'org.kde.image', 'General');
            d.writeConfig('Image', 'file://$WALLPAPER_PATH');
        }
    "
    echo "✔ Wallpaper set to: $WALLPAPER_PATH"
else
    echo "⚠ WARNING: Wallpaper not found at $WALLPAPER_PATH"
fi

# === GTK3 and GTK4 assets and CSS linking ===
echo "🔗 Linking GTK3 and GTK4 theme files and generating settings..."

for GTK_VERSION in "gtk-3.0" "gtk-4.0"; do
    GTK_CONFIG="$HOME/.config/$GTK_VERSION"
    THEME_PATH="/usr/share/themes/$GTK_THEME/$GTK_VERSION"
    ASSETS_PATH="$THEME_PATH/assets"

    mkdir -p "$GTK_CONFIG"

    # 1. Generate version-specific settings.ini statically
    if [ "$GTK_VERSION" = "gtk-3.0" ]; then
        # GTK 3.0 specific configuration (based on image_2665d2.png)
        cat > "$GTK_CONFIG/settings.ini" <<EOF
[Settings]
gtk-application-prefer-dark-theme=true
gtk-button-images=true
gtk-cursor-blink=true
gtk-cursor-blink-time=1000
gtk-cursor-theme-name=$CURSOR_THEME
gtk-cursor-theme-size=24
gtk-decoration-layout=close,minimize,maximize:
gtk-enable-animations=true
gtk-font-name=Noto Sans,  10
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
        echo "✔ Created GTK 3.0 customized settings.ini"
    else
        # GTK 4.0 specific configuration (based on image_2669d3.png)
        cat > "$GTK_CONFIG/settings.ini" <<EOF
[Settings]
gtk-application-prefer-dark-theme=true
gtk-cursor-blink=true
gtk-cursor-blink-time=1000
gtk-cursor-theme-name=$CURSOR_THEME
gtk-cursor-theme-size=24
gtk-decoration-layout=close,minimize,maximize:
gtk-enable-animations=true
gtk-font-name=Noto Sans,  10
gtk-icon-theme-name=$ICON_THEME
gtk-primary-button-warps-slider=true
gtk-sound-theme-name=ocean
gtk-theme-name=$GTK_THEME
gtk-xft-dpi=98304
EOF
        echo "✔ Created GTK 4.0 customized settings.ini"
    fi

    # 2. Remove old links or directories safely
    rm -rf "$GTK_CONFIG/assets"
    rm -f "$GTK_CONFIG/gtk.css" "$GTK_CONFIG/gtk-dark.css"

    # 3. Copy assets directory if available
    if [ -d "$ASSETS_PATH" ]; then
        cp -r "$ASSETS_PATH" "$GTK_CONFIG/assets"
        echo "✔ Copied assets directory for $GTK_VERSION"
    else
        echo "⚠ WARNING: No 'assets' directory found for theme '$GTK_THEME' in $GTK_VERSION"
    fi

    # 4. Copy GTK CSS files if available
    if [ -f "$THEME_PATH/gtk.css" ]; then
        cp "$THEME_PATH/gtk.css" "$GTK_CONFIG/gtk.css"
        echo "✔ Copied gtk.css for $GTK_VERSION"
    else
        echo "⚠ WARNING: gtk.css not found in theme '$GTK_THEME' ($GTK_VERSION)"
    fi

    if [ -f "$THEME_PATH/gtk-dark.css" ]; then
        ln -s "$THEME_PATH/gtk-dark.css" "$GTK_CONFIG/gtk-dark.css"
        echo "✔ Linked gtk-dark.css for $GTK_VERSION"
    else
        echo "⚠ WARNING: gtk-dark.css not found in theme '$GTK_THEME' ($GTK_VERSION)"
    fi
done

# === Reload Desktop Environment ===
echo "🔄 Reloading KWin and Plasma..."
qdbus org.kde.KWin /KWin reconfigure
qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.refreshCurrentShell

echo "✨ macOS unified theme successfully applied!"
