#!/bin/bash
# ------------------------------------------------------------
# GNOME Theme & Dash-to-Dock Configuration Script
# ------------------------------------------------------------
# Applies GNOME Shell, GTK, icon, and cursor themes,
# configures Dash-to-Dock settings, sets wallpaper,
# and links GTK4 theme files.
# ------------------------------------------------------------

FLAG_FILE="/tmp/.gtk_theme_script_loaded_$USER"

# Run only once per login session
if [ -f "$FLAG_FILE" ]; then
    exit 1
fi
touch "$FLAG_FILE"

# === User-defined variables ===
GTK_THEME="Orchis-Grey-Dark-Compact-Nord"
SHELL_THEME="Orchis-Grey-Dark-Compact-Nord"
WM_THEME="Orchis-Grey-Dark-Compact-Nord"
ICON_THEME="Tela-circle-nord-dark"
CURSOR_THEME="VolantesCursors"
WALLPAPER_PATH="/usr/share/backgrounds/custom/a_woman_standing_in_front_of_a_window.jpg"  # 🖼️ Set your wallpaper path here

# === Helper function: Check GNOME extension installation ===
check_extension() {
    local ext="$1"
    if [ -d "/usr/share/gnome-shell/extensions/$ext" ]; then
        echo "✔ Extension '$ext' is installed globally."
    else
        echo "❌ ERROR: Extension '$ext' is not installed globally!"
        exit 1
    fi
}

# === Check required GNOME extensions ===
echo "🔍 Checking GNOME extensions..."
check_extension "dash-to-dock@micxgx.gmail.com"
check_extension "user-theme@gnome-shell-extensions.gcampax.github.com"

# === Ensure gnome-extensions tool is available ===
if ! command -v gnome-extensions >/dev/null 2>&1; then
    echo "❌ ERROR: 'gnome-extensions' tool not found."
    exit 1
fi

# === Enable required extensions ===
echo "🔧 Enabling required extensions..."
gnome-extensions enable dash-to-dock@micxgx.gmail.com
gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com

# === Dash-to-Dock configuration ===
echo "⚙️  Applying Dash-to-Dock settings..."

declare -A dash_settings=(
    ["apply-custom-theme"]=false
    ["autohide"]=true
    ["autohide-in-fullscreen"]=false
    ["background-opacity"]=0.8
    ["click-action"]="'cycle-windows'"
    ["custom-theme-shrink"]=true
    ["dash-max-icon-size"]=24
    ["dock-fixed"]=true
    ["dock-position"]="'LEFT'"
    ["extend-height"]=true
    ["height-fraction"]=1.0
    ["hide-delay"]=0.2
    ["hot-keys"]=true
    ["icon-size-fixed"]=true
    ["intellihide"]=true
    ["intellihide-mode"]="'FOCUS_APPLICATION_WINDOWS'"
    ["multi-monitor"]=true
    ["preferred-monitor"]=-2
    ["show-apps-always-in-the-edge"]=true
    ["show-apps-at-top"]=true
    ["show-favorites"]=true
    ["show-trash"]=true
    ["show-running"]=true
    ["transparency-mode"]="'DEFAULT'"
)

for key in "${!dash_settings[@]}"; do
    if gsettings list-keys org.gnome.shell.extensions.dash-to-dock | grep -q "^$key$"; then
        gsettings set org.gnome.shell.extensions.dash-to-dock "$key" "${dash_settings[$key]}"
    else
        echo "⚠ Skipping unknown Dash-to-Dock key: $key"
    fi
done

# Reinforce Show Applications position
gsettings set org.gnome.shell.extensions.dash-to-dock show-apps-always-in-the-edge true
gsettings set org.gnome.shell.extensions.dash-to-dock show-apps-at-top true

# === Theme checks ===
echo "🧩 Checking themes and icons..."

if [ ! -d "/usr/share/themes/$GTK_THEME" ]; then
    echo "❌ ERROR: GTK/Shell theme '$GTK_THEME' not found!"
    exit 1
fi

if [ ! -d "/usr/share/icons/$ICON_THEME" ]; then
    echo "❌ ERROR: Icon theme '$ICON_THEME' not found!"
    exit 1
fi

if [ ! -d "/usr/share/icons/$CURSOR_THEME" ]; then
    echo "❌ ERROR: Cursor theme '$CURSOR_THEME' not found!"
    exit 1
fi

# === Apply theme settings ===
echo "🎨 Applying GNOME theme settings..."
gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME"
gsettings set org.gnome.shell.extensions.user-theme name "$SHELL_THEME"
gsettings set org.gnome.desktop.wm.preferences theme "$WM_THEME"
gsettings set org.gnome.desktop.wm.preferences button-layout "appmenu:minimize,maximize,close"
gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME"
gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME"

# === Set wallpaper ===
echo "🖼️  Setting desktop background..."

if [ -f "$WALLPAPER_PATH" ]; then
    gsettings set org.gnome.desktop.background picture-uri "file://$WALLPAPER_PATH"
    gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALLPAPER_PATH"
    gsettings set org.gnome.desktop.background picture-options "zoom"
    echo "✔ Wallpaper set to: $WALLPAPER_PATH"
else
    echo "⚠ WARNING: Wallpaper not found at $WALLPAPER_PATH"
fi

# === GTK4 assets and CSS linking ===
echo "🔗 Linking GTK4 theme files..."

GTK4_CONFIG="$HOME/.config/gtk-4.0"
THEME_PATH="/usr/share/themes/$GTK_THEME/gtk-4.0"
ASSETS_PATH="$THEME_PATH/assets"

mkdir -p "$GTK4_CONFIG"

# Remove old links or directories safely
rm -rf "$GTK4_CONFIG/assets"
rm -f "$GTK4_CONFIG/gtk.css" "$GTK4_CONFIG/gtk-dark.css"

# Link assets directory if available
if [ -d "$ASSETS_PATH" ]; then
    ln -s "$ASSETS_PATH" "$GTK4_CONFIG/assets"
    echo "✔ Linked assets directory."
else
    echo "⚠ WARNING: No 'assets' directory found for theme '$GTK_THEME'"
fi

# Link GTK CSS files if available
if [ -f "$THEME_PATH/gtk.css" ]; then
    ln -s "$THEME_PATH/gtk.css" "$GTK4_CONFIG/gtk.css"
    echo "✔ Linked gtk.css"
else
    echo "⚠ WARNING: gtk.css not found in theme '$GTK_THEME'"
fi

if [ -f "$THEME_PATH/gtk-dark.css" ]; then
    ln -s "$THEME_PATH/gtk-dark.css" "$GTK4_CONFIG/gtk-dark.css"
    echo "✔ Linked gtk-dark.css"
else
    echo "⚠ WARNING: gtk-dark.css not found in theme '$GTK_THEME'"
fi

echo "🎨 Applying Firefox theme settings..."
# Find all Firefox profile directories
PROFILE_DIRS=$(find ~/.mozilla/firefox -maxdepth 1 -type d -name "*.default*" -o -name "default-*")

for PROFILE_DIR in $PROFILE_DIRS; do
    USER_JS="$PROFILE_DIR/user.js"
    PREFS_JS="$PROFILE_DIR/prefs.js"

    # Backup existing files
    [ -f "$USER_JS" ] && cp "$USER_JS" "$USER_JS.bak"
    [ -f "$PREFS_JS" ] && cp "$PREFS_JS" "$PREFS_JS.bak"

    # --- Update user.js safely ---
    # Remove old lines if exist
    if [ -f "$USER_JS" ]; then
        sed -i '/browser.tabs.inTitlebar/d' "$USER_JS"
    fi
    # Append new setting
    echo 'user_pref("browser.tabs.inTitlebar", 0);' >> "$USER_JS"

    # --- Update prefs.js (only if Firefox is closed!) ---
    if [ -f "$PREFS_JS" ]; then
        # Remove old lines
        sed -i '/browser.tabs.inTitlebar/d' "$PREFS_JS"
        # Append new setting
        echo 'user_pref("browser.tabs.inTitlebar", 0);' >> "$PREFS_JS"
    fi

    echo "Updated browser.tabs.inTitlebar in profile: $PROFILE_DIR"
done

# === Done ===
echo ""
echo "✅ All GNOME settings, themes, and wallpaper applied successfully!"
echo "🔄 Restart GNOME Shell (Alt+F2 → r → Enter) if changes don’t appear."
