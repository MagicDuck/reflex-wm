# reflex-wm

`reflex-wm` is an app that allows window manipulation using global shortcuts.

Supported systems:
- macOS 26
- KDE/Wayland
- Windows 10/11

It reloads the config at `~/.config/reflex-wm.toml` whenever it changes.

## Requirements

- macOS 26
- Xcode 26 or a compatible Swift 6 toolchain (for building)
- Accessibility permission for window inspection, control, global shortcuts, and Caps Lock remapping
- Notification permission for warnings, automatic configuration reloads, and `notify-win-info`

## Configuration

Create `~/.config/reflex-wm.toml`:

```toml
[aliases]
meh = "ctrl + shift + opt"

[remap]
caps_lock = "hyper"

[[shortcut]]
bind = "meh + e"
action = "toggle-app"
launch_cmd = "kitty"
match = [
  { app_id = "net.kovidgoyal.kitty" },
  { app_name = "kitty" }
]

[[shortcut]]
bind = "cmd + ctrl + s"
action = "toggle-app"
launch_app = "Safari"
match = [{ app_name = "Safari" }]

[[shortcut]]
bind = "cmd + ctrl + m"
action = "toggle-maximize"

[[shortcut]]
bind = "cmd + ctrl + w"
action = "close"

[[shortcut]]
bind = "cmd + ctrl + n"
action = "move-to-next-screen"

[[shortcut]]
bind = "cmd + ctrl + i"
action = "notify-win-info"

[[shortcut]]
bind = "cmd + ctrl + j"
action = "focus-next-app-window"

[[shortcut]]
bind = "cmd + ctrl + v"
action = "toggle-vertical-split"
```

Bindings are case-insensitive and consist of an optional combination of `cmd`, `ctrl`, `shift`, and `opt`, followed by a key. Supported keys are letters, digits, unshifted ANSI punctuation (except `+`, which separates bind tokens), F1–F20, arrows, Return, Tab, Space, Escape, Delete, Home, End, Page Up, Page Down, and PrintScr. Punctuation can be written literally (for example, `cmd + ;`, `cmd + .`, or `cmd + /`) or with a readable name such as `semicolon`, `dot`, or `forward slash`. An empty bind disables that shortcut definition.

The optional `[aliases]` table defines case-insensitive bind fragments. Aliases can reference other aliases. `alt = "opt"`, `super = "cmd"`, and `hyper = "cmd+ctrl+opt+shift"` are built in and cannot be redefined. For example, `bind = "meh+j"` above expands to `ctrl+shift+opt+j`.

*macOS only:* The optional `[remap]` table currently supports only `caps_lock`. Its value uses the same modifier and alias syntax as a bind, but must resolve entirely to one or more modifiers. With `caps_lock = "hyper"`, holding Caps Lock while pressing `e` triggers a `hyper+e` binding. The remap is internal to reflex-wm: an unbound `CapsLock+key` combination passes the key to the active application without Caps Lock or synthetic modifiers. Caps Lock's normal capitalization behavior is suppressed while the remap is active, and reflex-wm keeps the Caps Lock LED off on keyboards that expose a writable LED control.

*macOS only:* On current macOS versions, the keyboard-listening access needed for Caps Lock remapping is normally included with **Accessibility** permission, so a separate **Input Monitoring** grant is not usually required. If keyboard input access is unavailable, reflex-wm loads the remaining shortcuts, disables the remap, and reports a warning. Verify reflex-wm is enabled under **System Settings → Privacy & Security → Accessibility**; if macOS exposes keyboard access separately, enable it under **Input Monitoring** as well, then reload the configuration. Secure Event Input can temporarily prevent the event filter from applying the remap.

When a configured chord is pressed, reflex-wm consumes its key-down, repeat, and key-up events. The foreground application therefore does not receive the chord or interpret it as a shortcut with fewer modifiers.

Configuration reloads are transactional. If a changed file is invalid or a hotkey cannot be registered, the last valid bindings stay active.

## Actions
- `notify-win-info` creates a notification with current window information 
- `close` closes the current window
- `focus-next-app-window` cycles through the accessible windows of the currently focused application.
- `toggle-maximize` toggles current window size between maximum available screen space and previous saved geometry
- `toggle-vertical-split` alternate invocations resize the current window to take up left/right halves of the current screen's available area.
- `move-to-next-screen` moves current window to next screen (left-to-right and top-to-bottom)
- `toggle-app` toggles focus of app window or launches the app. See more in-depth explanation of options below.

### toggle-app configuration
For `toggle-app`, each object in `match` is tried in order. Within one object, every specified property must match the same window:

- `app_id`:
  - macOS: exact application bundle identifier
  - linux: exact match of window `resourceClass`
  - windows: exact match of app executable path
- `app_name`: case-insensitive application name or executable basename
- `win_title`: case-insensitive accessible window title

An empty `match` array does nothing. When no window matches, the application is launched. There are 2 alternatives that are exclusive:
- `launch_cmd` runs through the user's login shell
- `launch_app`
  - macOS: launches the named macOS application.
  - linux: launches the app with the specified .desktop filename (`.desktop` extension is optional) 
  - windows: passed to windows shell as installed application name / executable

## Build & Install

### macOS 
```sh
swift test
./scripts/build-macos-app.sh
```

The bundle is written to `build/reflex-wm.app`. Set `CODE_SIGN_IDENTITY` when you want to use a Developer ID; otherwise the script uses ad-hoc signing.

example:
```sh
# assumming "reflex-wm dev" is a certificate in your login keychain
env CODE_SIGN_IDENTITY="reflex-wm dev" ./scripts/build-macos-app.sh

cp -R build/reflex-wm.app /Applications/
```

Overall workflow:
1. Build the app.
2. Move `build/reflex-wm.app` to `/Applications`.
3. Open the app and grant Accessibility and notification access when prompted.
4. To start it at login, add `reflex-wm.app` under **System Settings → General → Login Items**.

The menu-bar item shows the current configuration status and provides commands to reload or open the configuration and quit the app.

### Windows

- Windows 10 22H2 or Windows 11
- Swift 6.2 toolchain for Windows

Build with `swift build -c release`; the executable is `.build/release/reflex-wm.exe`. Run it once to create `%USERPROFILE%\.config\reflex-wm.toml`, then edit the configuration and start the executable again. Run `reflex-wm.exe --check-config` to validate it without opening the tray app. The tray icon menu provides status, reload, open configuration, and quit commands. To run at sign-in, place a shortcut to `reflex-wm.exe` in the user's Startup folder (`shell:startup`).

Window and monitor actions use Win32 window geometry and monitor work areas. Window-manager restrictions or applications that reject external resize/focus requests can prevent an action. Notification messages appear through the reflex-wm tray icon.

### Linux - KDE

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

## Application icon

The generated master is stored at `Resources/AppIcon-master.png`, with standard sizes under `Resources/AppIcon.iconset`. To regenerate the bundled ICNS resource after changing those files, run:

```sh
swift scripts/make-icns.swift Resources/AppIcon.iconset Resources/reflex-wm.icns
```
