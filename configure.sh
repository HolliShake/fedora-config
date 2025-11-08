#!/bin/bash
# ------------------------------------------------------------
# GNOME Theme & Dash-to-Dock Configuration Script
# ------------------------------------------------------------
# Applies GNOME Shell, GTK, icon, and cursor themes,
# configures Dash-to-Dock settings, links GTK4 theme files,
# and replaces the "Show Applications" icon with a Fedora icon.
# ------------------------------------------------------------

FLAG_FILE="/tmp/.gtk_theme_script_loaded_$USER"

# Run only once per login session
if [ -f "$FLAG_FILE" ]; then
    return 0
fi
touch "$FLAG_FILE"

# === User-defined variables ===
GTK_THEME="Orchis-Green-Dark-Compact"
SHELL_THEME="Orchis-Green-Dark-Compact"
ICON_THEME="Papirus-Dark"
CURSOR_THEME="Bibata-Modern-Ice"
FEDORA_ICON="/usr/share/icons/hicolor/48x48/apps/fedora-logo-icon.png"  # Change path if needed

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
    ["apply-custom-theme"]=true
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
    ["show-apps-at-top"]=true       # Menu-grid at the top/left
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
gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME"
gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME"

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

# === Replace the "Show Applications" icon with Fedora icon ===
echo "🪄 Replacing Show Applications icon with Fedora icon..."

# Path to Papirus show-apps icon
ICON_OVERRIDE_DIR="$HOME/.local/share/icons/$ICON_THEME/symbolic/actions"
mkdir -p "$ICON_OVERRIDE_DIR"

# Default GNOME icon name for the Show Applications button
SHOW_APPS_ICON="view-app-grid-symbolic.svg"

# Replace with Fedora icon if available
if [ -f "$FEDORA_ICON" ]; then
    echo "✔ Fedora icon found: $FEDORA_ICON"
    rm -f "$ICON_OVERRIDE_DIR/$SHOW_APPS_ICON"
    ln -sf "$FEDORA_ICON" "$ICON_OVERRIDE_DIR/$SHOW_APPS_ICON"
    echo "✔ Overridden Show Applications icon with Fedora logo."
else
    echo "⚠ WARNING: Fedora icon not found at $FEDORA_ICON — skipping icon override."
fi

# === Done ===
echo ""
echo "✅ All GNOME settings and themes applied successfully!"
echo "🟢 The menu-grid (Show Applications) icon has been replaced with the Fedora logo."
echo "🔄 Restart GNOME Shell (Alt+F2 → r → Enter) if changes don’t appear."
