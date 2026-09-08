# reflex-wm

`reflex-wm` is a macOS 26 menu-bar agent that binds global shortcuts to app toggling and focused-window actions. It reloads `~/.config/reflex-wm.toml` whenever the file changes.

## Requirements

- macOS 26
- Xcode 26 or a compatible Swift 6 toolchain
- Accessibility permission for window inspection and control
- Notification permission for warnings and `notify-win-info`

## Configuration

Create `~/.config/reflex-wm.toml`:

```toml
[[shortcut]]
bind = "cmd + ctrl + e"
action = "toggle-app"
launch_cmd = "kitty"
match = [
  { app_id = "net.kovidgoyal.kitty" },
  { app_name = "kitty" }
]

[[shortcut]]
bind = "cmd + ctrl + m"
action = "toggle_maximize"

[[shortcut]]
bind = "cmd + ctrl + w"
action = "close"

[[shortcut]]
bind = "cmd + ctrl + n"
action = "move_to_next_screen"

[[shortcut]]
bind = "cmd + ctrl + i"
action = "notify-win-info"
```

Bindings are case-insensitive and consist of an optional combination of `cmd`, `ctrl`, `shift`, and `opt`, followed by a key. Supported keys are letters, digits, F1–F20, arrows, Return, Tab, Space, Escape, Delete, Home, End, Page Up, Page Down, and PrintScr. An empty bind disables that shortcut definition.

For `toggle-app`, each object in `match` is tried in order. Within one object, every specified property must match the same window:

- `app_id`: exact application bundle identifier
- `app_name`: case-insensitive application name or executable basename
- `win_title`: case-insensitive accessible window title

An empty `match` array does nothing. When no window matches, `launch_cmd` runs through the user's login shell.

Configuration reloads are transactional. If a changed file is invalid or a hotkey cannot be registered, the last valid bindings stay active.

## Build and test

```sh
swift test
./scripts/build-app.sh
```

The bundle is written to `build/reflex-wm.app`. Set `CODE_SIGN_IDENTITY` when you want to use a Developer ID; otherwise the script uses ad-hoc signing.

## Install

1. Build the app.
2. Move `build/reflex-wm.app` to `/Applications`.
3. Open the app and grant Accessibility and notification access when prompted.
4. To start it at login, add `reflex-wm.app` under **System Settings → General → Login Items**.

The menu-bar item shows the current configuration status and provides commands to reload or open the configuration and quit the app.
