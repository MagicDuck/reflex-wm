import Foundation
import ReflexWMCore
import ReflexWMKDECore

final class ActionController {
  private struct Launch {
    let process: Process
    let matches: [MatchCondition]
    let deadline: Date
    var nextCheck: Date
    var queryPending = false
  }
  private let bridge: WindowBridge
  private let notifier: Notifier
  private let entries: DesktopEntries
  private var launches: [String: Launch] = [:]
  init(bridge: WindowBridge, notifier: Notifier, entries: DesktopEntries) {
    self.bridge = bridge
    self.notifier = notifier
    self.entries = entries
  }
  func perform(_ shortcut: ValidatedShortcut) {
    switch shortcut.source.action {
    case .toggleApp:
      guard !shortcut.effectiveMatches.isEmpty else { return }
      snapshot { result in
        do {
          if let target = try self.match(shortcut.effectiveMatches, in: result.get()) {
            self.send("toggle", fields: ["window": target])
          } else {
            try self.launch(shortcut)
          }
        } catch { self.notifier.warning(error.localizedDescription) }
      }
    case .notifyWindowInfo:
      snapshot { result in
        do {
          let object = try result.get()
          guard let focused = object["focused"] as? String,
            let windows = object["windows"] as? [[String: Any]],
            let window = windows.first(where: { $0["id"] as? String == focused })
          else {
            throw ValidationError("there is no focused application window")
          }
          let info = self.metadata(window)
          let unavailable = "<unavailable>"
          self.notifier.info(
            title: "reflex-wm: Window Info",
            body: [
              "Application ID: \(info.appID ?? unavailable)",
              "Desktop Entry ID: \(info.desktopEntryID ?? unavailable)",
              "Application: \(info.appName ?? unavailable)",
              "Executable: \(info.executableName ?? unavailable)",
              "Window Title: \(info.windowTitle ?? unavailable)",
            ].joined(separator: "\n"))
        } catch { self.notifier.warning(error.localizedDescription) }
      }
    default: send(shortcut.source.action.rawValue)
    }
  }
  private func send(_ action: String, fields: [String: Any] = [:]) {
    bridge.enqueue(action, fields: fields) { result in
      if case .failure(let error) = result { self.notifier.warning(error.localizedDescription) }
    }
  }
  private func snapshot(completion: @escaping (Result<[String: Any], Error>) -> Void) {
    bridge.enqueue("snapshot", completion: completion)
  }
  private func metadata(_ window: [String: Any]) -> WindowMetadata {
    let entry = (window["desktopEntryID"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    var executable: String?
    if let pid = window["pid"] as? Int, pid > 0,
      let path = try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/\(pid)/exe")
    {
      executable = URL(fileURLWithPath: path).lastPathComponent
    }
    let appID = (window["appID"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    return WindowMetadata(
      appID: appID, appName: entries.displayName(for: entry), executableName: executable,
      windowTitle: window["title"] as? String, desktopEntryID: entries.identifier(for: entry))
  }
  private func match(_ conditions: [MatchCondition], in object: [String: Any]) throws -> String? {
    guard let windows = object["windows"] as? [[String: Any]] else {
      throw ValidationError("invalid KWin snapshot")
    }
    let indexes = MatchResolver.firstMatchingIndexes(
      conditions: conditions, candidates: windows.map(metadata))
    return indexes.first.flatMap { windows[$0]["id"] as? String }
  }
  private func launch(_ shortcut: ValidatedShortcut) throws {
    let process = Process()
    let id: String
    if let command = shortcut.source.launchCommand?.trimmingCharacters(in: .whitespacesAndNewlines),
      !command.isEmpty
    {
      id = "command:\(command)"
      process.executableURL = URL(
        fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh")
      process.arguments = ["-lc", command]
    } else if let value = shortcut.source.launchApplication?.trimmingCharacters(
      in: .whitespacesAndNewlines), !value.isEmpty
    {
      let entry = try entries.resolve(value)
      id = "desktop:\(entry.id)"
      guard let gio = Self.executable("gio") else {
        throw ValidationError("launch_app requires gio (install GLib tools)")
      }
      process.executableURL = gio
      process.arguments = ["launch", entry.url.path]
    } else {
      throw ValidationError(
        "no matching window found and neither launch_cmd nor launch_app is configured")
    }
    guard launches[id] == nil else { return }
    try process.run()
    launches[id] = Launch(
      process: process, matches: shortcut.effectiveMatches,
      deadline: Date().addingTimeInterval(10), nextCheck: Date())
  }
  func poll(now: Date = Date()) {
    for id in Array(launches.keys) {
      guard var launch = launches[id] else { continue }
      if !launch.process.isRunning && launch.process.terminationStatus != 0 {
        launches.removeValue(forKey: id)
        notifier.warning("\(id) exited with status \(launch.process.terminationStatus)")
      } else if now >= launch.deadline {
        launches.removeValue(forKey: id)
        notifier.warning("\(id) did not create a matching window within 10 seconds")
      } else if !launch.queryPending && now >= launch.nextCheck {
        launch.queryPending = true
        launches[id] = launch
        snapshot { result in
          guard var current = self.launches[id] else { return }
          do {
            if let target = try self.match(current.matches, in: result.get()) {
              self.launches.removeValue(forKey: id)
              self.send("focus", fields: ["window": target])
            } else {
              current.queryPending = false
              current.nextCheck = Date().addingTimeInterval(0.2)
              self.launches[id] = current
            }
          } catch {
            self.launches.removeValue(forKey: id)
            self.notifier.warning(error.localizedDescription)
          }
        }
      }
    }
  }
  static func executable(_ name: String) -> URL? {
    let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin")
      .split(separator: ":")
    return paths.map { URL(fileURLWithPath: String($0)).appendingPathComponent(name) }
      .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }
}
