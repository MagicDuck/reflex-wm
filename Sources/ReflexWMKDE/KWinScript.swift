import Foundation
import ReflexWMCore

/// Loads QML directly, without enabling a persistent KWin package. A distinct
/// plugin name prevents KWin's package settings from unloading our runtime.
final class KWinScript {
  static let destination = "org.kde.KWin"
  static let plugin = "reflex-wm-runtime"
  private let bus: any DBusCalling
  private let file: URL
  private var owner: String?
  private enum Phase { case replacing, loading, running }
  private var phase = Phase.replacing
  private var ownsScript = false
  private var nextAttempt = Date.distantPast

  init(bus: any DBusCalling, file: URL) {
    self.bus = bus
    self.file = file
  }

  static func installedScript(environment: [String: String] = ProcessInfo.processInfo.environment)
    throws -> URL
  {
    let user =
      environment["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : $0 }
      ?? NSHomeDirectory() + "/.local/share"
    let system =
      environment["XDG_DATA_DIRS"].flatMap { $0.isEmpty ? nil : $0 }
      ?? "/usr/local/share:/usr/share"
    for directory in [user] + system.split(separator: ":").map(String.init) {
      guard directory.hasPrefix("/") else { continue }
      let url = URL(fileURLWithPath: directory).appendingPathComponent(
        "kwin/scripts/reflex-wm/contents/code/main.qml")
      if FileManager.default.isReadableFile(atPath: url.path) { return url }
    }
    throw ValidationError("KWin script package is missing; run scripts/install-linux.sh first")
  }

  func ownerChanged(_ value: String?, now: Date = Date()) {
    let value = value.flatMap { $0.isEmpty ? nil : $0 }
    guard value != owner else { return }
    owner = value
    ownsScript = false
    phase = .replacing
    nextAttempt = now
  }

  func poll(now: Date = Date()) throws {
    guard now >= nextAttempt else { return }
    nextAttempt = now.addingTimeInterval(2)
    if owner == nil {
      guard
        let value = try bus.call(
          "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetNameOwner",
          [.string(Self.destination)]
        ).first?.string, !value.isEmpty
      else {
        throw ValidationError("KWin has no session-bus owner")
      }
      owner = value
    }
    switch phase {
    case .replacing:
      // Remove a legacy manually enabled copy and any copy left after a crash.
      for name in ["reflex-wm", Self.plugin] {
        if try loaded(name) { _ = try call("unloadScript", [.string(name)]) }
      }
      phase = .loading
      // unloadScript uses deleteLater; yield to KWin before loading again.
      nextAttempt = now.addingTimeInterval(0.1)
    case .loading:
      if try loaded(Self.plugin) || loaded("reflex-wm") {
        phase = .replacing
        return
      }
      guard
        let id = try call("loadDeclarativeScript", [.string(file.path), .string(Self.plugin)])
          .first?.integer, id >= 0
      else {
        throw ValidationError("KWin refused to load the reflex-wm QML script")
      }
      ownsScript = true
      do {
        _ = try bus.call(
          owner!, "/Scripting/Script\(id)", "org.kde.kwin.Script", "run")
        phase = .running
      } catch {
        phase = .replacing
        throw error
      }
    case .running:
      if try !loaded(Self.plugin) {
        ownsScript = false
        phase = .replacing
        nextAttempt = now
      }
    }
  }

  func shutdown() throws {
    guard ownsScript, owner != nil else { return }
    _ = try call("unloadScript", [.string(Self.plugin)])
    ownsScript = false
  }

  private func loaded(_ name: String) throws -> Bool {
    guard case .bool(let value)? = try call("isScriptLoaded", [.string(name)]).first else {
      throw ValidationError("invalid KWin isScriptLoaded reply")
    }
    return value
  }

  private func call(_ method: String, _ arguments: [DBusValue]) throws -> [DBusValue] {
    guard let owner else { throw ValidationError("KWin is unavailable") }
    // Pin each call to the owner: never unload another compositor's script if
    // org.kde.KWin changes hands while a request is in flight.
    return try bus.call(owner, "/Scripting", "org.kde.kwin.Scripting", method, arguments)
  }
}
