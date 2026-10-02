# KDE Plasma 6 on Wayland

The Linux backend is a Swift background program, with a resident QML KWin script for
window operations. It talks directly to KDE's KGlobalAccel service over the session
D-Bus. It has no tray icon, C++ adapter, or Caps Lock remapping.

## Build and install

Merges into `master` publish a release build on GitHub's **Releases** page. Direct
pushes to `master` also publish builds. Each release is tagged `kde-<commit SHA>`
and includes `reflex-wm-kde-linux-x86_64.tar.gz` and its SHA-256 checksum.

To install a downloaded release, extract the archive into a directory and run
`./scripts/install-linux.sh` inside it. It includes the binary, KWin script,
installer, this README, and optional systemd unit. The CI build targets Linux
x86_64 on Ubuntu 24.04 (glibc 2.39 or newer) and statically links the Swift runtime;
Swift is not required to run it. The KDE and system dependencies below still apply.

Build on Linux with Swift 6.2 or newer, a C++ compiler (for the existing TOML
parser dependency), `pkg-config`, and libdbus development headers. Runtime dependencies
are Plasma 6 Wayland, KGlobalAccel, libdbus, and GLib's `gio` tool. Installation also
requires `kpackagetool6` and `kwriteconfig6` from KDE.

On Debian/Ubuntu, install `libdbus-1-dev pkg-config g++ libglib2.0-bin` in addition to
Swift and your Plasma installation. Package names differ on other distributions.

```sh
swift test
node scripts/test-kwin.cjs
./scripts/build-linux.sh
./scripts/install-linux.sh
```

The build produces `build/linux/<architecture>/reflex-wm-kde`, its KWin script package,
an optional user systemd unit, and `build/reflex-wm-kde-linux-<architecture>.tar.gz`.
The executable is built for the host Linux
architecture/distribution; this is a separate artifact from the macOS `.app`.

Create `~/.config/reflex-wm.toml`, then start the program:

```sh
~/.local/bin/reflex-wm-kde
# Or start it with your graphical session:
systemctl --user enable --now reflex-wm.service
```

reflex-wm loads and starts its QML script through KWin's D-Bus interface, unloads
it on normal shutdown, and loads it again after KWin restarts. No manual enabling
in KWin Scripts is needed. The installer disables the old package autoload setting
when upgrading from a manually enabled installation. Keep that setting disabled;
the program uses a separate runtime script ID.

The installer updates an existing script. Restart reflex-wm after upgrading to
load the new version; no logout is needed. Stop the program with Ctrl+C or
`systemctl --user stop reflex-wm.service`. A script left after a crash is replaced
on the next startup. The script package is located using `XDG_DATA_HOME` and
`XDG_DATA_DIRS`, with standard defaults.

## Configuration

The same TOML format and actions are supported. `cmd`/`super` means Meta and
`opt`/`alt` means Alt. `delete` retains the macOS meaning of Backspace; `printscr`
is the actual Print Screen key on KDE. Shortcuts use Qt's logical key semantics,
so keyboard layout behavior can differ from macOS's physical ANSI key codes.

```toml
[[shortcut]]
bind = "super + e"
action = "toggle-app"
launch_app = "org.kde.konsole"
match = [{ app_id = "org.kde.konsole" }]

[[shortcut]]
bind = "super + ctrl + i"
action = "notify-win-info"

[[shortcut]]
bind = "super + ctrl + v"
action = "toggle-vertical-split"
```

Use `notify-win-info` to discover the actual window application ID and desktop entry
ID; these may differ. `app_id` matches KWin's `resourceClass` exactly (Wayland app
ID or XWayland window class). `app_name` matches the desktop entry's `Name` or the
executable basename when available. `win_title` matches the window caption,
case-insensitively. Existing ordered match/AND semantics are retained.

`launch_app` is the **desktop entry ID**, derived from the installed `.desktop`
filename, not its `Name=` field. Both `org.kde.konsole` and
`org.kde.konsole.desktop` are accepted. User entries take precedence over system
entries; `Hidden=true` overrides prevent launching. `gio launch` handles the desktop
entry's launching rules. `launch_cmd` runs through `$SHELL -lc` (default `/bin/sh`).
They remain mutually exclusive. Do not copy macOS bundle IDs or application names
into the KDE configuration without checking them.

`[remap].caps_lock` is ignored and produces a warning; the remaining shortcuts load.
The default file path is shared with macOS. Use `--config PATH` for a different file.
Validate without connecting to KDE using:

```sh
reflex-wm-kde --config ~/.config/reflex-wm.toml --check-config
```

## Reloads and failures

TOML controls bindings on startup and reload, using explicit KGlobalAccel assignments.
Changes made in KDE Settings persist until the next successful reload. Editing or
atomically replacing the configuration file triggers reload; SIGHUP also reloads:

```sh
systemctl --user kill --signal=HUP reflex-wm.service
```

Conflicts are reported without stealing other applications' shortcuts. Invalid
configuration retains the previous bindings. If registration fails, reflex-wm
attempts to restore the actual previous bindings, including KDE Settings edits.
KDE offers no atomic binding transaction: a brief registration gap is possible,
and a failed rollback is reported explicitly. Only single-chord bindings are
supported. KDE's shortcut service handles key capture; repeat events do not repeatedly
perform window actions.

The program retries registration after the shortcut service restarts and script
loading after KWin becomes available. It checks for an unloaded runtime script
every two seconds and restores it. Pending window actions time out after five
seconds instead of being replayed later. Window metadata can be unavailable;
geometry changes remain subject to application size limits and KWin rules. Leave
fullscreen before resizing a window. Script restarts reset focus history and saved
restore geometry.

Warnings go to stderr and desktop notifications. With systemd, inspect logs using
`journalctl --user -u reflex-wm.service`. If window actions time out, check the
KWin script startup/recovery diagnostics in the logs. A second reflex-wm instance
is rejected through D-Bus name ownership.

## Live acceptance checklist

Automated tests cover binding encoding, TOML validation, desktop entries,
registration rollback/recovery, script lifecycle, D-Bus message types, file
replacement, and window logic against a mock workspace. Actual compositor behavior
must also be checked on Plasma 6 Wayland:

- Verify shortcuts work while native Wayland and XWayland applications have focus.
- Verify window info reports application ID, desktop entry, executable, and title;
  test a window whose desktop entry cannot be identified.
- Toggle a running app and return to the previous window. Launch it using both a
  desktop entry ID and `launch_cmd`; verify matching after launch and launch errors.
- Close a disposable window; cycle through two windows of one process.
- Maximize/restore, alternate left/right halves, and move across monitors with
  different sizes/scales, including a panel and a monitor above the primary display.
- Modify, add, remove, and disable shortcuts; test atomic saves and invalid TOML.
- Introduce a conflict with a KDE shortcut and verify prior bindings are restored.
- Change a binding in KDE Settings; verify it survives until file reload/SIGHUP.
- Start reflex-wm with its package disabled in KWin Scripts; verify window actions
  work without enabling it. Stop/restart the program and verify runtime script
  cleanup/replacement and duplicate-instance rejection.
- Verify automatic script reload after KWin restarts in a disposable session, and
  check missing-package and script startup/recovery diagnostics.
- Test shortcut-service restart recovery in a disposable session. Do not terminate
  your compositor to perform this check in a session containing unsaved work.

CI builds/tests on Linux. Live KDE checks are not implied by passing mocked tests.
