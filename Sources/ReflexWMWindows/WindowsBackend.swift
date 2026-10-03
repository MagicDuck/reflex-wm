import CWindows
import Foundation
import ReflexWMCore

struct WindowsWindow {
  let id: String
  let metadata: WindowMetadata
  let pid: Int
}

enum WindowsBackendError: LocalizedError {
  case operation(String)
  var errorDescription: String? {
    switch self { case .operation(let message): message }
  }
}

enum WindowsKeys {
  static func encode(_ binding: HotKeyBinding) throws -> (UInt32, Int32) {
    guard let keyName = binding.key.withCString({ name in
      let key = rw_key_code(name)
      return key == 0 ? nil : key
    }) else { throw ValidationError("unsupported Windows key: \(binding.key)") }
    var modifiers: UInt32 = 0x4000 // MOD_NOREPEAT
    if binding.modifiers.contains(.command) { modifiers |= 0x0008 } // MOD_WIN
    if binding.modifiers.contains(.control) { modifiers |= 0x0002 }
    if binding.modifiers.contains(.shift) { modifiers |= 0x0004 }
    if binding.modifiers.contains(.option) { modifiers |= 0x0001 }
    return (modifiers, keyName)
  }
}

final class WindowsNotifier {
  func status(_ text: String) { text.withCString { rw_app_status($0) } }
  func info(title: String, body: String) {
    title.withCString { titlePointer in body.withCString { rw_app_notify(titlePointer, $0) } }
  }
  func warning(_ message: String) {
    FileHandle.standardError.write(Data("reflex-wm: \(message)\n".utf8))
    info(title: "reflex-wm Warning", body: message)
    status("Warning: \(message)")
  }
}

final class WindowsActions {
  private let notifier: WindowsNotifier
  private var restoreRects: [String: CGRect] = [:]
  private var recentWindows: [String] = []
  private var nextSplit: VerticalSplitSide = .left
  private var launchChecks: [String: (ValidatedShortcut, Date)] = [:]

  init(notifier: WindowsNotifier) { self.notifier = notifier }

  func perform(_ shortcut: ValidatedShortcut) {
    rememberForeground()
    do {
      switch shortcut.source.action {
      case .toggleApp: try toggleApp(shortcut)
      case .toggleMaximize: try toggleMaximize()
      case .close: try closeFocused()
      case .moveToNextScreen: try moveToNextScreen()
      case .notifyWindowInfo: try notifyWindowInfo()
      case .focusNextAppWindow: try focusNextAppWindow()
      case .toggleVerticalSplit: try toggleVerticalSplit()
      }
    } catch { notifier.warning(error.localizedDescription) }
  }

  func pollLaunches(now: Date = Date()) {
    guard !launchChecks.isEmpty else { return }
    let windows = snapshot()
    for (id, entry) in Array(launchChecks) {
      let (shortcut, deadline) = entry
      if let window = matched(shortcut.effectiveMatches, windows: windows) {
        try? focus(window)
        launchChecks.removeValue(forKey: id)
      } else if now >= deadline {
        notifier.warning("launched application did not create a matching window within 10 seconds")
        launchChecks.removeValue(forKey: id)
      }
    }
  }

  private func toggleApp(_ shortcut: ValidatedShortcut) throws {
    guard !shortcut.effectiveMatches.isEmpty else { return }
    let windows = snapshot()
    if let target = matched(shortcut.effectiveMatches, windows: windows) {
      if target.id == foregroundID() {
        guard let previous = recentWindows.reversed().first(where: { $0 != target.id }),
              let previousWindow = windows.first(where: { $0.id == previous }) else {
          throw failure("there is no previous window to activate")
        }
        try focus(previousWindow)
      } else { try focus(target) }
      return
    }
    let launchID: String
    if let command = nonEmpty(shortcut.source.launchCommand) {
      launchID = "command:\(command)"
      guard launchChecks[launchID] == nil else { return }
      let started = command.withCString { rw_launch_command($0) }
      guard started != 0 else { throw WindowsBackendError.operation("could not start launch_cmd (Win32 error \(rw_last_error()))") }
    } else if let application = nonEmpty(shortcut.source.launchApplication) {
      launchID = "application:\(application.lowercased())"
      guard launchChecks[launchID] == nil else { return }
      let started = application.withCString { rw_launch_app($0) }
      guard started != 0 else { throw WindowsBackendError.operation("could not launch application '\(application)'") }
    } else {
      throw WindowsBackendError.operation("no matching window was found and neither launch_cmd nor launch_app is configured")
    }
    launchChecks[launchID] = (shortcut, Date().addingTimeInterval(10))
  }

  private func closeFocused() throws {
    let window = try focusedWindow()
    guard window.id.withCString({ rw_window_close($0) }) != 0 else { throw failure("could not close the focused window") }
  }

  private func toggleMaximize() throws {
    let window = try focusedWindow(); let rect = try frame(window)
    if let restore = restoreRects.removeValue(forKey: window.id) { try setFrame(restore, of: window); return }
    guard let screen = screens().max(by: { intersectionArea($0, rect) < intersectionArea($1, rect) }) else { throw failure("could not determine the focused window's monitor") }
    restoreRects[window.id] = rect
    do { try setFrame(screen, of: window) } catch { restoreRects.removeValue(forKey: window.id); throw error }
  }

  private func toggleVerticalSplit() throws {
    let window = try focusedWindow(); let rect = try frame(window)
    guard let screen = screens().max(by: { intersectionArea($0, rect) < intersectionArea($1, rect) }) else { throw failure("could not determine the focused window's monitor") }
    let half = ScreenGeometry.verticalHalf(screen, side: nextSplit)
    try setFrame(half, of: window); restoreRects.removeValue(forKey: window.id); nextSplit = nextSplit.opposite
  }

  private func moveToNextScreen() throws {
    let window = try focusedWindow(); let rect = try frame(window); let all = screens()
    guard all.count > 1, let current = all.indices.max(by: { intersectionArea(all[$0], rect) < intersectionArea(all[$1], rect) }) else { throw failure("there is no next monitor") }
    try setFrame(ScreenGeometry.map(rect, from: all[current], to: all[(current + 1) % all.count]), of: window)
    restoreRects.removeValue(forKey: window.id)
  }

  private func focusNextAppWindow() throws {
    let current = try focusedWindow()
    let same = snapshot().filter { $0.pid == current.pid }
    guard same.count > 1, let index = same.firstIndex(where: { $0.id == current.id }) else { throw failure("the focused application has no next window") }
    try focus(same[(index + 1) % same.count])
  }

  private func notifyWindowInfo() throws {
    let info = try focusedWindow().metadata
    let unavailable = "<unavailable>"
    notifier.info(title: "reflex-wm: Window Info", body: [
      "Application ID: \(info.appID ?? unavailable)",
      "Application: \(info.appName ?? unavailable)",
      "Executable: \(info.executableName ?? unavailable)",
      "Window Title: \(info.windowTitle ?? unavailable)",
    ].joined(separator: "\n"))
  }

  private func focusedWindow() throws -> WindowsWindow {
    guard let id = foregroundID(), let window = snapshot().first(where: { $0.id == id }) else { throw failure("there is no focused application window") }
    return window
  }

  private func focus(_ window: WindowsWindow) throws {
    rememberForeground()
    recentWindows.removeAll { $0 == window.id }
    let result = window.id.withCString { rw_window_focus($0) } != 0
    guard result else { throw failure("could not focus the selected window") }
    recentWindows.append(window.id)
  }

  private func rememberForeground() {
    guard let current = foregroundID() else { return }
    recentWindows.removeAll { $0 == current }
    recentWindows.append(current)
  }

  private func matched(_ conditions: [MatchCondition], windows: [WindowsWindow]) -> WindowsWindow? {
    let normalizedWindows = windows.map { window in
      WindowsWindow(id: window.id, metadata: WindowMetadata(appID: window.metadata.appID?.lowercased(),
        appName: window.metadata.appName, executableName: window.metadata.executableName,
        windowTitle: window.metadata.windowTitle), pid: window.pid)
    }
    let normalizedConditions = conditions.map {
      MatchCondition(appID: $0.appID?.lowercased(), appName: $0.appName, windowTitle: $0.windowTitle)
    }
    let indexes = MatchResolver.firstMatchingIndexes(conditions: normalizedConditions, candidates: normalizedWindows.map(\.metadata))
    let matches = indexes.compactMap { normalizedWindows.indices.contains($0) ? normalizedWindows[$0] : nil }
    for id in recentWindows.reversed() { if let window = matches.first(where: { $0.id == id }) { return window } }
    return matches.first
  }

  private func snapshot() -> [WindowsWindow] {
    guard let raw = rw_snapshot_json() else { return [] }
    defer { rw_free(raw) }
    let data = Data(String(cString: raw).utf8)
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let records = object["windows"] as? [[String: Any]] else { return [] }
    return records.compactMap { item in
      guard let id = item["id"] as? String else { return nil }
      return WindowsWindow(id: id,
        metadata: WindowMetadata(appID: item["appID"] as? String, appName: item["appName"] as? String,
          executableName: item["executableName"] as? String, windowTitle: item["title"] as? String),
        pid: item["pid"] as? Int ?? 0)
    }
  }

  private func foregroundID() -> String? {
    guard let raw = rw_snapshot_json() else { return nil }; defer { rw_free(raw) }
    guard let object = (try? JSONSerialization.jsonObject(with: Data(String(cString: raw).utf8))) as? [String: Any] else { return nil }
    return object["focused"] as? String
  }

  private func screens() -> [CGRect] {
    (0..<rw_monitor_count()).compactMap { index in
      var x: Int32 = 0, y: Int32 = 0, width: Int32 = 0, height: Int32 = 0
      guard rw_monitor_rect(index, &x, &y, &width, &height) != 0 else { return nil }
      return CGRect(x: Int(x), y: Int(y), width: Int(width), height: Int(height))
    }
  }
  private func frame(_ window: WindowsWindow) throws -> CGRect {
    var x: Int32 = 0, y: Int32 = 0, width: Int32 = 0, height: Int32 = 0
    guard window.id.withCString({ rw_window_rect($0, &x, &y, &width, &height) }) != 0 else { throw failure("could not read the focused window frame") }
    return CGRect(x: Int(x), y: Int(y), width: Int(width), height: Int(height))
  }
  private func setFrame(_ rect: CGRect, of window: WindowsWindow) throws {
    let result = window.id.withCString { rw_window_set_rect($0, Int32(rect.minX.rounded()), Int32(rect.minY.rounded()), Int32(rect.width.rounded()), Int32(rect.height.rounded())) }
    guard result != 0 else { throw failure("window does not allow position or size changes") }
  }
  private func intersectionArea(_ screen: CGRect, _ rect: CGRect) -> CGFloat {
    let area = screen.intersection(rect)
    return area.isNull ? 0 : area.width * area.height
  }
  private func nonEmpty(_ value: String?) -> String? { value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
  private func failure(_ message: String) -> WindowsBackendError { .operation(message) }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
