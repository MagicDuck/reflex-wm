#!/bin/sh
set -eu
if [ "$(uname -s)" != Linux ]; then
    echo 'Install this backend inside a Plasma 6 Wayland session on Linux.' >&2
    exit 1
fi
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output="$project_root/build/linux/$(uname -m)"
# Release archives place the binary beside the scripts directory.
if [ -x "$project_root/reflex-wm-kde" ]; then
    output="$project_root"
fi
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
command -v kpackagetool6 >/dev/null || { echo 'Install kpackagetool6 first.' >&2; exit 1; }
command -v gio >/dev/null || { echo 'Install GLib tools (gio) first.' >&2; exit 1; }
command -v kwriteconfig6 >/dev/null || { echo 'Install KDE configuration tools (kwriteconfig6) first.' >&2; exit 1; }
[ -x "$output/reflex-wm-kde" ] || { echo 'Run scripts/build-linux.sh first, or extract the complete release archive.' >&2; exit 1; }
mkdir -p "$HOME/.local/bin" "$config_home/systemd/user"
install -m 755 "$output/reflex-wm-kde" "$HOME/.local/bin/reflex-wm-kde"
if kpackagetool6 --type KWin/Script --show reflex-wm >/dev/null 2>&1; then
    kpackagetool6 --type KWin/Script --upgrade "$output/kwin/reflex-wm"
else
    kpackagetool6 --type KWin/Script --install "$output/kwin/reflex-wm"
fi
# The program loads its own runtime script. Disable legacy package autoloading
# so a previously enabled copy cannot compete with it after KWin reconfigures.
kwriteconfig6 --file kwinrc --group Plugins --key reflex-wmEnabled false
# The unit uses KDE's graphical-session environment and does not need a tray UI.
install -m 644 "$output/reflex-wm.service" "$config_home/systemd/user/reflex-wm.service"
systemctl --user daemon-reload
printf '%s\n' 'Installed reflex-wm-kde.' \
    'The program loads and starts its KWin script automatically.' \
    'After an upgrade, restart reflex-wm to load the updated script.' \
    'Create ~/.config/reflex-wm.toml, then run: systemctl --user enable --now reflex-wm.service' \
    "Or run directly: $HOME/.local/bin/reflex-wm-kde"
