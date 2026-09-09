# reflex-wm macOS Menu-Bar Agent

## Summary

Create a standalone Swift 6 menu-bar application targeting macOS 26. The app registers configurable global shortcuts, manipulates windows through macOS Accessibility APIs, reports focused-window metadata, and hot-reloads `~/.config/reflex-wm.toml`.

Use Swift Package Manager, `swift-toml`, and a bundle script that produces a signed `reflex-wm.app`.

## Configuration Interface

Every shortcut requires `bind` and `action`:

```toml
[[shortcut]]
bind = "cmd + ctrl + e"
action = "toggle-app"
launch_cmd = "kitty"
match = [
  { app_id = "net.kovidgoyal.kitty", win_title = "shell" },
  { app_name = "kitty" }
]

[[shortcut]]
bind = "cmd + ctrl + s"
action = "toggle-app"
launch_app = "Safari"
match = [{ app_name = "Safari" }]

[[shortcut]]
bind = "cmd + ctrl + m"
action = "toggle_maximize"

[[shortcut]]
bind = "cmd + ctrl + i"
action = "notify-win-info"

[[shortcut]]
bind = "PrintScr"
action = "move_to_next_screen"
```

- Supported actions are `toggle-app`, `toggle_maximize`, `close`, `move_to_next_screen`, and `notify-win-info`.
- Parse `bind` by splitting on `+`, trimming whitespace, and matching tokens case-insensitively.
- A non-empty bind must contain exactly one supported key and zero or more unique modifiers from `cmd`, `ctrl`, `shift`, and `opt`. Reject duplicate modifiers, unknown tokens, modifier-only bindings, or multiple keys.
- Support letters, digits, F1-F20, arrows, Return, Tab, Space, Escape, Delete, Home, End, Page Up, Page Down, and PrintScr.
- Validate an empty bind normally but register no hotkey for it.
- Reject duplicate normalized non-empty binds.
- `toggle-app` requires a `match` array and may specify either `launch_cmd` or `launch_app`, but never both. An empty match array, or one containing only empty objects, performs no action and does not launch anything.
- `launch_cmd` runs through the user's login shell. `launch_app` launches the named macOS application, for example `launch_app = "Safari"`.
- Reject `match`, `launch_cmd`, and `launch_app` on every action other than `toggle-app`.

Each match condition is an inline table containing any combination of:

```toml
{ app_id = "bundle.identifier", app_name = "Application", win_title = "Window title" }
```

- `app_id` matches the owning application's bundle identifier exactly.
- `app_name` matches case-insensitively against either its application name or executable basename.
- `win_title` matches case-insensitively against the window's Accessibility title.
- All populated fields within one condition must match the same window—logical AND.
- Skip empty condition objects.
- Evaluate conditions in array order—ordered OR—and stop at the first condition producing one or more windows.
- When the successful condition returns multiple windows, select the most recently focused one, followed by the app's focused/main window and then its first standard window.

## Implementation

- Build an AppKit `NSStatusItem` agent with `LSUIElement=true`, bundle identifier `com.reflexwm.app`, and menu items for accessibility/config status, Reload Configuration, Open Configuration, and Quit.
- Request Accessibility and notification permissions at startup. Mirror warnings and window information through unified logging and menu status when notifications are unavailable.
- Register normalized non-empty bindings through Carbon `RegisterEventHotKey`.
- Reserve hotkeys exclusively and use an active session event tap to consume the complete key-down/repeat/key-up sequence for exact configured chords, preventing foreground applications from interpreting partial shortcuts.
- Watch the configuration directory to detect direct writes, atomic replacements, deletion, and recreation. Debounce changes and retain the complete previous configuration if parsing, validation, or hotkey registration fails.
- Track application activation and focused-window changes using `NSWorkspace` and accessibility observers. Record a recency-ordered history of valid windows, excluding reflex-wm itself.
- For `toggle-app`:
  - Evaluate non-empty match conditions in order.
  - If that exact window is currently focused, activate and raise the previous valid window.
  - Otherwise unminimize, activate, focus, and raise the selected window.
  - If no condition matches and `launch_cmd` exists, run it asynchronously through the user's login shell with `-lc`. If `launch_app` exists instead, launch the named application through macOS Launch Services using `/usr/bin/open -a`. Suppress duplicate launches briefly and retry all conditions in their original order while waiting for a window.
  - Report missing launch methods and launch failures, but treat empty/effectively-empty match arrays as intentional no-ops.
- Apply focused-window actions as follows:
  - `toggle_maximize`: save the focused standard window's frame, fill its screen's visible frame, and restore the saved frame on the next invocation.
  - `close`: invoke the focused standard window's Accessibility close action.
  - `move_to_next_screen`: order screens left-to-right then top-to-bottom, wrap at the end, and preserve the focused window's normalized geometry.
  - `notify-win-info`: inspect the focused window and deliver a notification titled `reflex-wm: Window Info` whose body contains separate `Bundle ID`, `Application`, `Executable`, and `Window Title` lines.
- For unavailable `notify-win-info` fields, display `<unavailable>` rather than omitting the field. If there is no focused window or Accessibility access is unavailable, emit a warning notification instead.
- Centralize conversion between accessibility's top-left coordinates and AppKit screen coordinates, including negative display origins.
- Provide README instructions for building, installing the `.app`, granting Accessibility/notification permissions, creating the config, and adding the app through macOS Login Items.

## Test Plan

- Test bind parsing for whitespace, casing, optional modifiers, PrintScr, empty binds, duplicates, unsupported tokens, duplicate modifiers, missing keys, and multiple keys.
- Test all five actions, required `match`, mutually exclusive launch methods, forbidden app fields on non-`toggle-app` actions, empty match arrays, empty objects, malformed conditions, and transactional reload failures.
- Test match-condition AND behavior, ordered fallback between conditions, exact bundle matching, case-insensitive app/title matching, and selection among multiple matching windows.
- Test app toggling, previous-window restoration, minimized/destroyed windows, launching, retry matching, failed commands, and duplicate-launch suppression with protocol-backed fakes.
- Test `notify-win-info` formatting with complete metadata, missing bundle IDs, missing names/titles, absent focused windows, denied Accessibility access, and denied notification permission.
- Test maximize/restore and proportional screen movement across different resolutions, visible-frame insets, negative coordinates, and wraparound display ordering.
- Test transactional reloads for valid edits, malformed TOML, duplicate shortcuts, registration conflicts, file deletion/recreation, and atomic file replacement.
- Verify `swift test`, release compilation, app-bundle assembly, `Info.plist` validation, executable signing, and launch as a menu-bar-only agent.
- Manually verify global shortcuts, permission prompts, focus restoration, config notifications, multi-display movement, app launch/toggle behavior, and Login Item startup on macOS 26.

## Assumptions

- Action names remain exactly `toggle-app`, `toggle_maximize`, `close`, `move_to_next_screen`, and `notify-win-info`.
- The application name and executable basename are reported separately so neither value is lost.
- String matching uses locale-independent case folding.
- Letter and digit names map to macOS ANSI virtual-key positions rather than changing with the active keyboard layout.
- Empty binds and effectively empty match arrays are deliberate disabled/no-op configurations, not errors.
- Maximize restoration is process-local; saved frames are not persisted across reflex-wm restarts or window destruction.
- If a window was already maximized before reflex-wm recorded its frame, the first maximize invocation may produce no visible size change.
- Window-management operations require Accessibility permission; shortcuts remain registered while permission is missing, but affected invocations report a warning.
- v1 has no settings window, automatic updater, persistent window history, or self-managed launch-at-login registration.
