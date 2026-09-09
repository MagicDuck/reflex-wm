# reflex-wm

`reflex-wm` is a macOS 26 menu-bar agent that binds global shortcuts to app toggling and focused-window actions. It reloads `~/.config/reflex-wm.toml` whenever the file changes.

## Requirements

- macOS 26
- Xcode 26 or a compatible Swift 6 toolchain
- Accessibility permission for window inspection and control
- Notification permission for warnings, automatic configuration reloads, and `notify-win-info`

## Configuration

Create `~/.config/reflex-wm.toml`:

```toml
[aliases]
meh = "ctrl+shift+opt"

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

When a configured chord is pressed, reflex-wm consumes its key-down, repeat, and key-up events. The foreground application therefore does not receive the chord or interpret it as a shortcut with fewer modifiers.

`focus-next-app-window` cycles through the accessible windows of the currently focused application. `toggle-vertical-split` alternates successful invocations between the left and right halves of the current screen's available area.

For `toggle-app`, each object in `match` is tried in order. Within one object, every specified property must match the same window:

- `app_id`: exact application bundle identifier
- `app_name`: case-insensitive application name or executable basename
- `win_title`: case-insensitive accessible window title

An empty `match` array does nothing. When no window matches, `launch_cmd` runs through the user's login shell, or `launch_app` launches the named macOS application. `launch_cmd` and `launch_app` are alternatives and cannot both appear in the same shortcut.

Configuration reloads are transactional. If a changed file is invalid or a hotkey cannot be registered, the last valid bindings stay active.
Successful filesystem-triggered reloads produce a notification; startup and manual menu reloads do not.

## Build and test

```sh
swift test
./scripts/build-app.sh
```

The bundle is written to `build/reflex-wm.app`. Set `CODE_SIGN_IDENTITY` when you want to use a Developer ID; otherwise the script uses ad-hoc signing.

example:
```sh
# assumming "reflex-wm dev" is a certificate in your login keychain
env CODE_SIGN_IDENTITY="reflex-wm dev" ./scripts/build-app.sh

cp -R build/reflex-wm.app /Applications/
```

## Install

1. Build the app.
2. Move `build/reflex-wm.app` to `/Applications`.
3. Open the app and grant Accessibility and notification access when prompted.
4. To start it at login, add `reflex-wm.app` under **System Settings → General → Login Items**.

The menu-bar item shows the current configuration status and provides commands to reload or open the configuration and quit the app.

## Application icon

The generated master is stored at `Resources/AppIcon-master.png`, with standard sizes under `Resources/AppIcon.iconset`. To regenerate the bundled ICNS resource after changing those files, run:

```sh
swift scripts/make-icns.swift Resources/AppIcon.iconset Resources/reflex-wm.icns
```
