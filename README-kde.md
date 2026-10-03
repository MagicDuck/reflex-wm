# KDE Plasma 6 on Wayland

## Build and install


Build on Linux with Swift 6.2 or newer, a C++ compiler (for the existing TOML
parser dependency), `pkg-config`, and libdbus development headers. Runtime dependencies
are Plasma 6 Wayland, KGlobalAccel, libdbus, and GLib's `gio` tool.

On Debian/Ubuntu, install `libdbus-1-dev pkg-config g++ libglib2.0-bin` in addition to
Swift and your Plasma installation. Package names differ on other distributions.

```sh
swift test
node scripts/test-kwin.cjs
swift build -c release --product reflex-wm-kde --static-swift-stdlib
```

The build produces `reflex-wm-kde` with embedded KWin scripts in the directory
reported by `swift build -c release --show-bin-path`.


## Configuration

`hyper` expands to Meta+Ctrl+Alt+Shift. Shifted ANSI punctuation and digits are
registered using their resulting symbols, as KWin expects: for example,
`hyper + '` uses the double-quote symbol with Meta+Ctrl+Alt. Shift remains explicit
for letters and special keys. Keyboard layouts with different shifted symbols
can differ from the ANSI mapping.

Run `reflex-wm-kde --debug-shortcuts` to log requested and active Qt key codes,
bindings changed in KDE Settings, and received shortcut activation events. This
helps distinguish encoding differences from registration or key-capture failures.

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

`[remap].caps_lock` is ignored and produces a warning; the remaining shortcuts load.
The default file path is shared with macOS. Use `--config PATH` for a different file.
Validate without connecting to KDE using:

```sh
reflex-wm-kde --config ~/.config/reflex-wm.toml --check-config
```

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
- Start reflex-wm without registering a KWin package; verify window actions work.
  Stop/restart the program and verify runtime script
  cleanup/replacement and duplicate-instance rejection.
- Verify automatic script reload after KWin restarts in a disposable session, and
  check temporary-file extraction and script startup/recovery diagnostics.
- Test shortcut-service restart recovery in a disposable session. Do not terminate
  your compositor to perform this check in a session containing unsaved work.

CI builds/tests on Linux. Live KDE checks are not implied by passing mocked tests.
