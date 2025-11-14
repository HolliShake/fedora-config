#!/bin/bash
# ------------------------------------------------------------
# GNOME Theme & Dash-to-Dock Configuration Script
# ------------------------------------------------------------
# Applies GNOME Shell, GTK, icon, and cursor themes,
# configures Dash-to-Dock settings, sets wallpaper,
# and links GTK4 theme files.
# ------------------------------------------------------------

# Only run in GNOME graphical session
if [ -z "$XDG_CURRENT_DESKTOP" ] || [[ "$XDG_CURRENT_DESKTOP" != *GNOME* ]]; then
    exit 0   # Exit the script early
fi

FLAG_FILE="/tmp/.gtk_theme_script_loaded_$USER"

# Run only once per login session
if [ -f "$FLAG_FILE" ]; then
    echo "Done!"
    exit 0
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
    ["apply-glossy-effect"]=true
    ["autohide"]=true
    ["autohide-in-fullscreen"]=false
    ["background-color"]="'#ffffff'"
    ["background-opacity"]=0.8
    ["bolt-support"]=true
    ["click-action"]="'cycle-windows'"
    ["custom-background-color"]=true
    ["custom-theme-customize-running-dots"]=false
    ["custom-theme-running-dots-border-color"]="'#ffffff'"
    ["custom-theme-running-dots-border-width"]=0
    ["custom-theme-running-dots-color"]="'#ffffff'"
    ["custom-theme-shrink"]=true
    ["customize-alphas"]=false
    ["dance-urgent-applications"]=true
    ["dash-max-icon-size"]=35
    ["default-windows-preview-to-open"]=false
    ["disable-overview-on-startup"]=false
    ["dock-fixed"]=true
    ["dock-position"]="'BOTTOM'"
    ["extend-height"]=false
    ["force-straight-corner"]=false
    ["height-fraction"]=1.0
    ["hide-delay"]=0.2
    ["hide-tooltip"]=false
    ["hot-keys"]=true
    ["hotkeys-overlay"]=true
    ["hotkeys-show-dock"]=true
    ["icon-size-fixed"]=true
    ["intellihide"]=true
    ["intellihide-mode"]="'FOCUS_APPLICATION_WINDOWS'"
    ["isolate-locations"]=true
    ["isolate-monitors"]=true
    ["isolate-workspaces"]=true
    ["manualhide"]=false
    ["max-alpha"]=0.8
    ["middle-click-action"]="'launch'"
    ["min-alpha"]=0.2
    ["minimize-shift"]=true
    ["multi-monitor"]=true
    ["preferred-monitor"]=-2
    ["preferred-monitor-by-connector"]="'HDMI-1'"
    ["pressure-threshold"]=100.0
    ["preview-size-scale"]=0.0
    ["require-pressure-to-show"]=true
    ["running-indicator-dominant-color"]=false
    ["running-indicator-style"]="'DOT'"
    ["scroll-action"]="'do-nothing'"
    ["scroll-switch-workspace"]=true
    ["scroll-to-focused-application"]=true
    ["shift-click-action"]="'minimize'"
    ["shift-middle-click-action"]="'launch'"
    ["shortcut"]="['<Super>q']"
    ["shortcut-text"]="'<Super>q'"
    ["shortcut-timeout"]=2.0
    ["show-apps-always-in-the-edge"]=false
    ["show-apps-at-top"]=true
    ["show-delay"]=0.25
    ["show-dock-urgent-notify"]=true
    ["show-favorites"]=true
    ["show-icons-emblems"]=true
    ["show-icons-notifications-counter"]=true
    ["show-mounts"]=false
    ["show-mounts-network"]=false
    ["show-mounts-only-mounted"]=true
    ["show-running"]=true
    ["show-show-apps-button"]=true
    ["show-trash"]=true
    ["show-windows-preview"]=true
    ["transparency-mode"]="'DYNAMIC'"
    ["unity-backlit-items"]=false
    ["autohide-in-fullscreen"]=true
    ["autohide"]=true
    ["workspace-agnostic-urgent-windows"]=true
)

for key in "${!dash_settings[@]}"; do
    if gsettings list-keys org.gnome.shell.extensions.dash-to-dock | grep -q "^$key$"; then
        gsettings set org.gnome.shell.extensions.dash-to-dock "$key" "${dash_settings[$key]}"
    else
        echo "⚠ Skipping unknown Dash-to-Dock key: $key"
    fi
done

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

echo "🎨 Applying VScode theme settings..."
# Find VS Code user settings.json
SETTINGS_JSON="$HOME/.config/Code/User/settings.json"

# If settings.json does not exist, create it with an empty JSON object
if [ ! -f "$SETTINGS_JSON" ]; then
    mkdir -p "$(dirname "$SETTINGS_JSON")"
    echo "{}" > "$SETTINGS_JSON"
fi

# Use jq to safely update or add the key
if command -v jq >/dev/null 2>&1; then
    # Update settings.json in-place
    tmpfile=$(mktemp)
    jq '. + {"window.titleBarStyle":"native"}' "$SETTINGS_JSON" > "$tmpfile" && mv "$tmpfile" "$SETTINGS_JSON"
    echo "✅ Updated $SETTINGS_JSON with \"window.titleBarStyle\": \"native\""
else
    # Fallback if jq is not installed: use sed/grep (less robust)
    # Check if key exists
    if grep -q '"window.titleBarStyle"' "$SETTINGS_JSON"; then
        # Replace existing line
        sed -i 's/"window.titleBarStyle".*/"window.titleBarStyle": "native",/' "$SETTINGS_JSON"
    else
        # Insert before the last closing brace
        sed -i 's/}/,\n  "window.titleBarStyle": "native"\n}/' "$SETTINGS_JSON"
    fi
    echo "✅ Updated $SETTINGS_JSON with \"window.titleBarStyle\": \"native\" (without jq)"
fi

# === Done ===
echo ""
echo "✅ All GNOME settings, themes, and wallpaper applied successfully!"
echo "🔄 Restart GNOME Shell (Alt+F2 → r → Enter) if changes don’t appear."
