import CDBus
import Foundation
import ReflexWMCore
import ReflexWMKDECore

#if os(Linux)
  import Glibc
#else
  import Darwin
#endif

final class KDEApplication {
  private let bus: DBusConnection
  private let service: GlobalShortcuts
  private let registry: ShortcutRegistry
  private let bridge: WindowBridge
  private let kwinScript: KWinScript
  private let notifier: Notifier
  private let actions: ActionController
  private let watcher: ConfigurationWatcher
  private let configURL: URL
  private var shortcuts: [String: ValidatedShortcut] = [:]
  private var recoveryAt: Date?
  private var shortcutOwner: String?

  init(configURL: URL) throws {
    self.configURL = configURL
    bus = try DBusConnection()
    try bus.ownName(WindowBridge.service)
    service = GlobalShortcuts(bus: bus)
    registry = ShortcutRegistry(service: service)
    notifier = Notifier(bus: bus)
    bridge = WindowBridge(bus: bus)
    kwinScript = try KWinScript(bus: bus)
    actions = ActionController(bridge: bridge, notifier: notifier, entries: DesktopEntries())
    try FileManager.default.createDirectory(
      at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    watcher = try ConfigurationWatcher(url: configURL)
    try bus.addMatch(
      "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged'"
    )
    try bus.addMatch(
      "type='signal',sender='org.kde.kglobalaccel',interface='org.kde.kglobalaccel.Component'")
    try bus.addMatch(
      "type='signal',sender='org.kde.kglobalaccel',interface='org.kde.KGlobalAccel',member='yourShortcutsChanged'"
    )
    try service.removeStaleActions()
    shortcutOwner = try bus.call(
      "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetNameOwner",
      [.string(GlobalShortcuts.destination)]
    ).first?.string
    reload(initial: true)
  }
  func reload(initial: Bool = false) {
    do {
      let configuration = try ConfigurationLoader.decode(
        String(contentsOf: configURL, encoding: .utf8))
      let validated = try ConfigurationValidator.validate(
        configuration, supportsCapsLockRemap: false)
      var candidate: [KDERegistration] = []
      var mapping: [String: ValidatedShortcut] = [:]
      for (index, shortcut) in validated.shortcuts.enumerated() {
        guard let binding = shortcut.binding else { continue }
        let id = "shortcut-\(index + 1)"
        candidate.append(
          KDERegistration(
            id: id, description: "\(shortcut.source.action.rawValue): \(binding.normalized)",
            keys: [try KDEBinding.encode(binding)]))
        mapping[id] = shortcut
      }
      try registry.apply(candidate)
      shortcuts = mapping
      if configuration.remap?.capsLock != nil {
        notifier.warning("Caps Lock remapping is ignored on KDE")
      }
      notifier.log("loaded \(candidate.count) shortcuts from \(configURL.path)")
      if !initial {
        notifier.info(
          title: "reflex-wm: Configuration Reloaded", body: "Loaded \(candidate.count) shortcuts")
      }
    } catch {
      notifier.warning(
        "configuration reload failed (previous bindings restored unless rollback is reported incomplete): \(error.localizedDescription)"
      )
    }
  }
  func run(signals: SignalMonitor) throws {
    notifier.log("running; managing the KWin script automatically")
    defer {
      do { try kwinScript.shutdown() } catch {
        notifier.log("KWin script cleanup failed: \(error.localizedDescription)")
      }
      do { try registry.shutdown() } catch {
        notifier.log("shortcut cleanup failed: \(error.localizedDescription)")
      }
    }
    while true {
      if let signal = signals.poll() {
        if signal == SIGHUP { reload() } else { return }
      }
      try bus.wait(milliseconds: 50)
      while let message = bus.nextMessage() {
        defer { dbus_message_unref(message) }
        if bridge.handle(message) { continue }
        handleSignal(message)
      }
      bridge.poll()
      actions.poll()
      if watcher.poll() { reload() }
      do { try kwinScript.poll() } catch {
        notifier.log("KWin script startup/recovery failed: \(error.localizedDescription)")
      }
      if let deadline = recoveryAt, Date() >= deadline {
        do {
          try registry.recover()
          recoveryAt = nil
          notifier.log("shortcut service recovered")
        } catch {
          notifier.log("shortcut recovery failed: \(error.localizedDescription)")
          recoveryAt = Date().addingTimeInterval(2)
        }
      }
    }
  }
  private func handleSignal(_ message: OpaquePointer) {
    guard dbus_message_get_type(message) == DBUS_MESSAGE_TYPE_SIGNAL else { return }
    let interface = dbus_message_get_interface(message).map(String.init(cString:)) ?? ""
    let member = dbus_message_get_member(message).map(String.init(cString:)) ?? ""
    let sender = dbus_message_get_sender(message).map(String.init(cString:)) ?? ""
    do {
      let values = try DBusConnection.decode(message)
      if interface == "org.freedesktop.DBus", member == "NameOwnerChanged",
        sender == "org.freedesktop.DBus", values.count == 3
      {
        if let oldOwner = values[1].string, values[2].string == "" {
          bridge.disconnected(sender: oldOwner)
        }
        if values[0].string == GlobalShortcuts.destination {
          shortcutOwner = values[2].string.flatMap { $0.isEmpty ? nil : $0 }
          recoveryAt = shortcutOwner == nil ? nil : Date()
        }
        if values[0].string == KWinScript.destination {
          kwinScript.ownerChanged(values[2].string)
        }
      } else if sender == shortcutOwner, interface == "org.kde.kglobalaccel.Component",
        values.count == 3,
        values[0].string == GlobalShortcuts.component, let id = values[1].string
      {
        // One action per press; repeats/releases are consumed by KDE but do not
        // repeatedly toggle applications or close additional windows.
        if member == "globalShortcutPressed", let shortcut = shortcuts[id] {
          actions.perform(shortcut)
        }
      } else if sender == shortcutOwner, interface == GlobalShortcuts.interface,
        member == "yourShortcutsChanged", values.count == 2,
        values[0].elements.first?.string == GlobalShortcuts.component,
        let id = values[0].elements.dropFirst().first?.string
      {
        // Query current state so queued intermediate notifications from our own
        // reload cannot overwrite a newer binding selected in KDE Settings.
        registry.recordChange(id: id, keys: try service.keys(for: id))
      }
    } catch { notifier.log("D-Bus event failed: \(error.localizedDescription)") }
  }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--help") {
  print(
    "Usage: reflex-wm-kde [--config PATH] [--check-config]\nReload with SIGHUP; stop with SIGINT/SIGTERM. Requires Plasma 6 Wayland."
  )
} else {
  do {
    var config = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
      ".config/reflex-wm.toml")
    var check = false
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--config":
        index += 1
        guard index < arguments.count else { throw ValidationError("--config requires a path") }
        config = URL(fileURLWithPath: arguments[index]).standardizedFileURL
      case "--check-config": check = true
      default: throw ValidationError("unknown argument: \(arguments[index])")
      }
      index += 1
    }
    if check {
      let configuration = try ConfigurationLoader.decode(
        String(contentsOf: config, encoding: .utf8))
      let validated = try ConfigurationValidator.validate(
        configuration, supportsCapsLockRemap: false)
      for shortcut in validated.shortcuts {
        if let binding = shortcut.binding { _ = try KDEBinding.encode(binding) }
        if shortcut.binding != nil, let entry = shortcut.source.launchApplication {
          _ = try DesktopEntries().resolve(entry)
        }
      }
      print(
        "Configuration valid for KDE (\(validated.shortcuts.filter { $0.binding != nil }.count) shortcuts)"
      )
      if configuration.remap?.capsLock != nil { print("Caps Lock remapping is ignored on KDE") }
    } else {
      guard ProcessInfo.processInfo.environment["XDG_SESSION_TYPE"] == "wayland" else {
        throw ValidationError("reflex-wm's KDE backend requires a Plasma 6 Wayland session")
      }
      let signals = SignalMonitor()
      try KDEApplication(configURL: config).run(signals: signals)
    }
  } catch {
    FileHandle.standardError.write(Data("reflex-wm-kde: \(error.localizedDescription)\n".utf8))
    exit(1)
  }
}
