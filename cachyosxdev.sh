#!/bin/bash
# ==============================================================================
# Unified macOS-like Theming Script for KDE Plasma 6 & GTK/GNOME
# Validated + hardened version — no wallpaper handling included.
# FIXED: Aurorae window decoration library/theme keys corrected so window
#        decorations actually load instead of falling back to "no border".
# ==============================================================================

set -uo pipefail  # (not -e: we want to warn and continue, not abort on the first issue)

# === User-defined variables ===
KDE_COLOR_SCHEME="WhiteSurDark"
KDE_WIDGET_STYLE="kvantum-dark"        # matches System Settings > Application Style: "kvantum-dark"
KVANTUM_THEME="WhiteSurDark"           # Must match the *.kvconfig filename (e.g. /usr/share/kvantum/WhiteSur/WhiteSurDark.kvconfig), not a directory name.
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

# Changed this to only strictly require kwriteconfig6 for the KDE section
if has_cmd kwriteconfig6; then
    HAS_KDE_TOOLS=true
else
    warn "kwriteconfig6 not found — skipping KDE Plasma configuration."
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

HAS_PYTHON3=false
if has_cmd python3; then
    HAS_PYTHON3=true
else
    warn "python3 not found — Chromium/VS Code preference patching will be skipped."
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

# FIXED: Kvantum themes are NOT one-directory-per-variant. A "theme" like
# "WhiteSurDark" is actually a *.kvconfig FILE living inside a parent
# folder (commonly the base theme's folder), e.g.:
#   /usr/share/kvantum/WhiteSur/WhiteSurDark.kvconfig
# The old check looked for a directory literally named "$KVANTUM_THEME",
# which never exists — that's why it reported "not found" even when the
# theme was installed correctly. We now search recursively for a
# "<theme>.kvconfig" file instead. We also check both "kvantum" and
# "Kvantum" casing, since distros differ on this.
KVANTUM_SEARCH_DIRS=(
    "/usr/share/kvantum" "/usr/share/Kvantum"
    "/usr/local/share/kvantum" "/usr/local/share/Kvantum"
    "$HOME/.local/share/kvantum" "$HOME/.local/share/Kvantum"
    "$HOME/.config/Kvantum"
)
KVANTUM_THEME_DIR=""
KVANTUM_CONFIG_MATCH=""
for base in "${KVANTUM_SEARCH_DIRS[@]}"; do
    [ -d "$base" ] || continue
    match="$(find "$base" -maxdepth 3 -type f -iname "${KVANTUM_THEME}.kvconfig" -print -quit 2>/dev/null)"
    if [ -n "$match" ]; then
        KVANTUM_CONFIG_MATCH="$match"
        KVANTUM_THEME_DIR="$(dirname "$match")"
        break
    fi
done
if [ -n "$KVANTUM_THEME_DIR" ]; then
    ok "Found Kvantum theme config at $KVANTUM_CONFIG_MATCH"
else
    warn "Kvantum theme '$KVANTUM_THEME' (${KVANTUM_THEME}.kvconfig) not found under any known Kvantum directory."
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

    # --- FIXED: window decoration (Aurorae) section --------------------------
    # The decoration plugin ID is "org.kde.kwin.aurorae" — there is NO
    # ".v2" variant. Using the wrong plugin ID means KWin can't find any
    # decoration plugin at all and falls back to drawing no border/titlebar.
    #
    # Additionally, Aurorae SVG themes must be referenced with the
    # "__aurorae__svg__" prefix in front of the theme folder name, or KWin
    # won't resolve it to the actual theme even with the right plugin.
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library "org.kde.kwin.aurorae"
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme "__aurorae__svg__$AURORAE_THEME"
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key BorderSize "Tiny"
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft "XIA"
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight ""
    ok "Set window decoration (Aurorae) to '$AURORAE_THEME'."
    # ---------------------------------------------------------------------

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

    # === Kvantum section (Combined Approach) ===
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
# === Third-party app integration: Chromium browsers, Firefox, VS Code =======
# ==============================================================================
# IMPORTANT SCOPE NOTE:
# Chromium/Electron (VS Code) apps render their OWN UI (tabs, buttons,
# scrollbars) — they do NOT use the GTK theme engine, so they will never
# visually match WhiteSur pixel-for-pixel the way a real GTK app does.
# What CAN be fixed here, and what this section does:
#   1. Window decoration — these apps draw their own client-side titlebar
#      (CSD) by default, completely ignoring KWin/Aurorae. We switch them
#      to native/system decoration so KWin actually draws the border and
#      your Aurorae theme applies.
#   2. Dark/light mode — made to follow the OS/GTK preference.
#   3. Native file-picker dialogs are real GTK widgets and already pick up
#      GTK_THEME/ICON_THEME from the env var set below.
# ==============================================================================

info "Persisting GTK theme env var for the Plasma session (affects dark-mode detection and native GTK dialogs in Chromium/Electron apps)..."
mkdir -p "$HOME/.config/plasma-workspace/env"
PLASMA_ENV_FILE="$HOME/.config/plasma-workspace/env/aa-theme-vars.sh"
cat > "$PLASMA_ENV_FILE" <<EOF
#!/bin/sh
# Auto-generated by macos-theme script.
export GTK_THEME="$GTK_THEME"
# Forces server-side decorations for GTK-linked apps (Firefox, some
# Chromium builds) regardless of their own internal CSD/SSD preference,
# which has a long history of being unreliable/broken across versions.
export GTK_CSD=0
EOF
chmod +x "$PLASMA_ENV_FILE"
ok "Wrote $PLASMA_ENV_FILE (takes effect on next login)."
# Also export for the current shell, so browsers launched from this
# terminal right after the script finishes pick it up immediately.
export GTK_THEME="$GTK_THEME"
export GTK_CSD=0

# --- Chromium-family browsers: native title bar + dark mode -----------------
info "Configuring Chromium-based browsers (native title bar, dark mode)..."

declare -A CHROMIUM_CONFIG_DIRS=(
    ["google-chrome"]="$HOME/.config/google-chrome"
    ["google-chrome-beta"]="$HOME/.config/google-chrome-beta"
    ["chromium"]="$HOME/.config/chromium"
    ["brave-browser"]="$HOME/.config/BraveSoftware/Brave-Browser"
    ["microsoft-edge"]="$HOME/.config/microsoft-edge"
    ["vivaldi"]="$HOME/.config/vivaldi"
    ["opera"]="$HOME/.config/opera"
)

patch_chromium_prefs() {
    local prefs_file="$1"
    python3 - "$prefs_file" <<'PYEOF'
import json, sys, os

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        raw = f.read()
    data = json.loads(raw)
except Exception as e:
    print(f"SKIP:{path}:{e}")
    sys.exit(0)

browser = data.setdefault("browser", {})
# custom_chrome_frame=False -> "Use system title bar and borders":
# lets KWin/Aurorae draw the window border instead of Chromium's own CSD.
changed = browser.get("custom_chrome_frame") is not False
browser["custom_chrome_frame"] = False

if changed:
    with open(path + ".bak", "w", encoding="utf-8") as f:
        f.write(raw)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f)
    print(f"OK:{path}")
else:
    print(f"NOCHANGE:{path}")
PYEOF
}

if $HAS_PYTHON3; then
    for browser_bin in "${!CHROMIUM_CONFIG_DIRS[@]}"; do
        cfg_dir="${CHROMIUM_CONFIG_DIRS[$browser_bin]}"
        { has_cmd "$browser_bin" || [ -d "$cfg_dir" ]; } || continue

        if pgrep -x "$browser_bin" >/dev/null 2>&1; then
            warn "$browser_bin is running — close it, then re-run this script (Chromium doesn't reload Preferences live)."
            continue
        fi

        found_any=false
        while IFS= read -r -d '' prefs_file; do
            found_any=true
            result="$(patch_chromium_prefs "$prefs_file")"
            profile_name="$(basename "$(dirname "$prefs_file")")"
            case "$result" in
                OK:*)       ok "Set native title bar for $browser_bin ($profile_name)." ;;
                NOCHANGE:*) ok "$browser_bin ($profile_name) already using native title bar." ;;
                SKIP:*)     warn "Could not parse Preferences for $browser_bin — left untouched ($result)." ;;
            esac
        done < <(find "$cfg_dir" -maxdepth 2 -iname "Preferences" -print0 2>/dev/null)

        $found_any || continue

        # Best-effort persistent flags file — some distro packages (notably
        # Debian/Ubuntu-style wrapper scripts) source ~/.config/<binary>-flags.conf.
        # Harmless no-op if your package doesn't read it (e.g. snap/flatpak
        # builds usually don't — pass flags via their launcher override instead).
        flags_file="$HOME/.config/${browser_bin}-flags.conf"
        if [ ! -f "$flags_file" ] || ! grep -q -- "--force-dark-mode" "$flags_file" 2>/dev/null; then
            {
                echo "--force-dark-mode"
                echo "--enable-features=WebUIDarkMode"
            } >> "$flags_file"
            ok "Added dark-mode flags to $flags_file (used only if your $browser_bin package supports flag files)."
        fi
    done
else
    warn "Skipping Chromium browser patching (python3 unavailable)."
fi

# --- Firefox: native title bar + dark mode -----------------------------------
# Search every common Firefox install layout: native package (legacy path
# and the newer XDG-compliant path some distros/builds default to now),
# Flatpak, and Snap all put profiles.ini in different places — checking
# only one silently skips the others entirely.
FIREFOX_PROFILES_INI_CANDIDATES=(
    "$HOME/.mozilla/firefox/profiles.ini"
    "$HOME/.config/mozilla/firefox/profiles.ini"
    "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox/profiles.ini"
    "$HOME/.var/app/org.mozilla.firefox/.config/mozilla/firefox/profiles.ini"
    "$HOME/snap/firefox/common/.mozilla/firefox/profiles.ini"
)
FIREFOX_RUNNING_PATTERNS=("firefox" "firefox-bin" "firefox-esr")

info "Configuring Firefox (native title bar, dark mode)..."

firefox_running=false
for pat in "${FIREFOX_RUNNING_PATTERNS[@]}"; do
    pgrep -x "$pat" >/dev/null 2>&1 && firefox_running=true
done
$firefox_running && warn "Firefox is running — close it, then re-run this script for changes to apply."

firefox_found=false
for PROFILES_INI in "${FIREFOX_PROFILES_INI_CANDIDATES[@]}"; do
    [ -f "$PROFILES_INI" ] || continue
    firefox_found=true
    firefox_base_dir="$(dirname "$PROFILES_INI")"

    while IFS= read -r rel_path; do
        [ -n "$rel_path" ] || continue
        if [[ "$rel_path" = /* ]]; then
            profile_dir="$rel_path"
        else
            profile_dir="$firefox_base_dir/$rel_path"
        fi
        [ -d "$profile_dir" ] || continue

        user_js="$profile_dir/user.js"
        touch "$user_js"

        set_pref() {
            local key="$1" val="$2"
            sed -i "/^user_pref(\"$key\"/d" "$user_js"
            echo "user_pref(\"$key\", $val);" >> "$user_js"
        }

        # Use the system window decoration (KWin/Aurorae) instead of
        # Firefox's own GTK client-side-decorated titlebar.
        set_pref "browser.tabs.inTitlebar" "0"
        # 2 = follow the OS/GTK light-dark preference automatically.
        set_pref "layout.css.prefers-color-scheme.content-override" "2"

        ok "Updated Firefox prefs in $(basename "$profile_dir")/user.js ($firefox_base_dir)"
    done < <(grep -E "^Path=" "$PROFILES_INI" | cut -d= -f2-)
done

if ! $firefox_found; then
    if has_cmd firefox || has_cmd firefox-bin || flatpak info org.mozilla.firefox >/dev/null 2>&1 || [ -d "$HOME/snap/firefox" ]; then
        warn "Firefox is installed but no profile exists yet (profiles.ini not found in any known location). Launch Firefox once to create a profile, then re-run this script."
    else
        warn "Firefox not detected — skipping Firefox configuration."
    fi
fi

# --- KWin Window Rules: FORCE decorations for Firefox & Chromium browsers ---
# Both Firefox's and Chromium's own "use system title bar" preferences have
# a long history of being unreliable or outright broken across versions
# (this is a known, recurring upstream issue, not something specific to
# your setup). Rather than depend on the app to cooperate, this forces the
# decoration directly at the KWin compositor level via a Window Rule,
# which overrides whatever the app itself requests.
#
# NOTE: for apps that paint their own tab-strip as a pseudo-titlebar (most
# Chromium browsers), forcing a KWin border on top can result in a double
# titlebar look (KWin's decoration + the app's own tab strip). This is the
# unavoidable tradeoff of forcing it — if you find it visually redundant
# for a given app, remove that app's rule below or edit it via
# System Settings > Window Management > Window Rules.
if $HAS_KDE_TOOLS && has_cmd python3; then
    info "Adding KWin Window Rules to force decorations for Firefox and Chromium browsers..."

    KWINRULES_FILE="$HOME/.config/kwinrulesrc"
    touch "$KWINRULES_FILE"

    python3 - "$KWINRULES_FILE" <<'PYEOF'
import sys, uuid, configparser

path = sys.argv[1]

# WM_CLASS (resource class) values for each target app. wmclassmatch=1 is
# an exact match; if your build reports a different class, adjust it in
# System Settings > Window Management > Window Rules (use its "Detect
# Window Properties" picker to grab the exact string).
targets = {
    "Force decorations - Firefox": "firefox",
    "Force decorations - Chromium": "chromium",
    "Force decorations - Google Chrome": "google-chrome",
    "Force decorations - Brave": "brave-browser",
    "Force decorations - Microsoft Edge": "microsoft-edge",
    "Force decorations - Vivaldi": "vivaldi",
    "Force decorations - Opera": "opera",
}

cp = configparser.ConfigParser(strict=False)
cp.optionxform = str  # preserve key casing
cp.read(path)

if "General" not in cp:
    cp["General"] = {}

existing_ids = [s for s in cp.sections() if s != "General"]
existing_wmclasses = {cp[s].get("wmclass", "") for s in existing_ids}

added = []
for description, wmclass in targets.items():
    if wmclass in existing_wmclasses:
        continue  # a rule for this app already exists — don't duplicate
    rule_id = uuid.uuid4().hex
    cp[rule_id] = {
        "Description": description,
        "wmclass": wmclass,
        "wmclassmatch": "1",       # 1 = exact match
        "wmclasscomplete": "false",
        "types": "1",              # NET::Normal windows
        # noborderrule: 3 = Force. noborder=false -> decorations ON.
        "noborder": "false",
        "noborderrule": "3",
    }
    added.append(rule_id)

if added:
    all_ids = existing_ids + added
    cp["General"]["count"] = str(len(all_ids))
    cp["General"]["rules"] = ",".join(all_ids)
    with open(path, "w") as f:
        cp.write(f, space_around_delimiters=False)
    print(f"OK:{len(added)}")
else:
    print("NOCHANGE:0")
PYEOF

    ok "KWin Window Rules updated in $KWINRULES_FILE (forces decorations for firefox/chromium/google-chrome/brave-browser/microsoft-edge/vivaldi/opera window classes not already covered)."
    warn "If a browser's WM_CLASS differs from the defaults baked into this script, open System Settings > Window Management > Window Rules and adjust that app's rule using 'Detect Window Properties'."
else
    warn "Skipping KWin Window Rules (requires KDE tools + python3)."
fi

# --- VS Code / VSCodium: native title bar + auto color scheme ---------------
declare -A VSCODE_SETTINGS_PATHS=(
    ["code"]="$HOME/.config/Code/User/settings.json"
    ["code-insiders"]="$HOME/.config/Code - Insiders/User/settings.json"
    ["codium"]="$HOME/.config/VSCodium/User/settings.json"
)

patch_vscode_settings() {
    local settings_file="$1"
    python3 - "$settings_file" <<'PYEOF'
import json, sys, os

path = sys.argv[1]
raw = ""
if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as f:
        raw = f.read()

# settings.json permits comments/trailing commas (JSONC). Only touch files
# that parse as plain JSON — otherwise leave alone rather than risk
# corrupting the user's config.
try:
    data = json.loads(raw) if raw.strip() else {}
except Exception as e:
    print(f"SKIP:{path}:{e}")
    sys.exit(0)

updates = {
    "window.titleBarStyle": "native",         # defer to KWin/Aurorae decorations
    "window.customTitleBarVisibility": "never",
    "window.autoDetectColorScheme": True,      # follow OS light/dark
}
changed = any(data.get(k) != v for k, v in updates.items())
data.update(updates)

if changed:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if raw:
        with open(path + ".bak", "w", encoding="utf-8") as f:
            f.write(raw)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    print(f"OK:{path}")
else:
    print(f"NOCHANGE:{path}")
PYEOF
}

if $HAS_PYTHON3; then
    info "Configuring VS Code / VSCodium (native title bar, auto color scheme)..."
    for bin in "${!VSCODE_SETTINGS_PATHS[@]}"; do
        settings_file="${VSCODE_SETTINGS_PATHS[$bin]}"
        parent_dir="$(dirname "$settings_file")"
        { [ -d "$parent_dir" ] || has_cmd "$bin"; } || continue

        if pgrep -f "$bin" >/dev/null 2>&1; then
            warn "$bin appears to be running — restart it after this script finishes."
        fi

        mkdir -p "$parent_dir"
        result="$(patch_vscode_settings "$settings_file")"
        case "$result" in
            OK:*)       ok "Updated $settings_file (native title bar + auto color scheme)." ;;
            NOCHANGE:*) ok "$settings_file already configured." ;;
            SKIP:*)
                warn "settings.json for $bin has comments/trailing commas — left untouched. Add manually:"
                echo '      "window.titleBarStyle": "native",'
                echo '      "window.customTitleBarVisibility": "never",'
                echo '      "window.autoDetectColorScheme": true'
                ;;
        esac
    done
else
    warn "Skipping VS Code / VSCodium patching (python3 unavailable)."
fi

# ==============================================================================
# === Reload Desktop Environment ==============================================
# ==============================================================================
if $HAS_KDE_TOOLS; then
    info "Reloading KWin and Plasma..."

    # Determine the correct qdbus command for the system
    if has_cmd qdbus6; then
        QDBUS_CMD="qdbus6"
    elif has_cmd qdbus; then
        QDBUS_CMD="qdbus"
    else
        QDBUS_CMD=""
    fi

    if [ -n "$QDBUS_CMD" ]; then
        $QDBUS_CMD org.kde.KWin /KWin reconfigure 2>/dev/null || warn "Could not signal KWin to reconfigure."
    else
        warn "Could not find 'qdbus' or 'qdbus6' to signal KWin. Log out and back in to see all changes."
    fi

    # FIXED: there is no DBus method to "refresh" plasmashell as a whole —
    # org.kde.PlasmaShell.refreshCurrentShell does not exist on Plasma 6's
    # plasmashell interface (it only exposes things like evaluateScript),
    # so that call was always guaranteed to fail. The actual documented
    # way to make plasmashell pick up new Plasma Style / desktop theme /
    # icon changes without logging out is to restart the plasmashell
    # process itself, in place.
    info "Restarting Plasma Shell to apply theme changes..."
    if has_cmd kquitapp6 && has_cmd kstart; then
        kquitapp6 plasmashell >/dev/null 2>&1
        # Give the old process a moment to fully exit before relaunching.
        sleep 1
        kstart plasmashell >/dev/null 2>&1 &
        disown
        ok "Restarted plasmashell via kquitapp6/kstart."
    elif has_cmd plasmashell; then
        pkill -x plasmashell >/dev/null 2>&1
        sleep 1
        plasmashell --replace >/dev/null 2>&1 &
        disown
        ok "Restarted plasmashell via --replace."
    else
        warn "Could not find kquitapp6/kstart or plasmashell to restart the shell. Log out and back in to see all Plasma Style/icon changes."
    fi

    # FIXED: 'reconfigure' reloads config values but doesn't always reload a
    # newly-selected decoration plugin binding on Plasma 6. Restart KWin's
    # own process in place (--replace) so the new decoration plugin actually
    # loads without requiring a full logout/login.
    if [ -n "${WAYLAND_DISPLAY:-}" ] && has_cmd kwin_wayland; then
        kwin_wayland --replace >/dev/null 2>&1 &
        disown
        ok "Restarted kwin_wayland to apply the new window decoration."
    elif has_cmd kwin_x11; then
        kwin_x11 --replace >/dev/null 2>&1 &
        disown
        ok "Restarted kwin_x11 to apply the new window decoration."
    else
        warn "Could not find kwin_x11/kwin_wayland to restart KWin in place. Log out and back in if decorations don't appear."
    fi
fi

echo "✨ macOS-style theme successfully applied (wallpaper untouched, as requested)."
