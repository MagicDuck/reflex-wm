import CWindows
import Foundation
import ReflexWMCore

final class WindowsApplication {
  private let configURL: URL
  private let notifier = WindowsNotifier()
  private let actions: WindowsActions
  private var shortcuts: [Int32: ValidatedShortcut] = [:]
  private var activeIDs: [Int32] = []
  private var lastContents: Data?
  private var lastProbe = Date.distantPast
  private var changedAt: Date?
  private var running = true

  init(configURL: URL) throws {
    self.configURL = configURL
    actions = WindowsActions(notifier: notifier)
    try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: configURL.path) {
      try "# reflex-wm shortcuts\n".write(to: configURL, atomically: true, encoding: .utf8)
    }
    guard rw_app_start("reflex-wm") != 0 else { throw WindowsBackendError.operation("could not create the Windows tray application") }
    lastContents = try? Data(contentsOf: configURL)
    reload(initial: true)
  }

  func run() {
    defer {
      for id in activeIDs { rw_hotkey_unregister(id) }
      rw_app_stop()
    }
    while running {
      let event = rw_app_poll(100)
      switch event.kind {
      case 1:
        if let shortcut = shortcuts[Int32(event.identifier)] { actions.perform(shortcut) }
      case 2: reload()
      case 3: configURL.path.withCString { rw_open_path($0) }
      case 4: running = false
      default: break
      }
      if pollConfiguration() { reload() }
      actions.pollLaunches()
    }
  }

  private func reload(initial: Bool = false) {
    do {
      let text = try String(contentsOf: configURL, encoding: .utf8)
      let configuration = try ConfigurationLoader.decode(text)
      let validated = try ConfigurationValidator.validate(configuration, supportsCapsLockRemap: false)
      var candidate: [Int32: ValidatedShortcut] = [:]
      var registrations: [(Int32, UInt32, Int32)] = []
      for (index, shortcut) in validated.shortcuts.enumerated() {
        guard let binding = shortcut.binding else { continue }
        let id = Int32(index + 1)
        let (modifiers, key) = try WindowsKeys.encode(binding)
        candidate[id] = shortcut
        registrations.append((id, modifiers, key))
      }

      let previous = shortcuts
      for id in activeIDs { rw_hotkey_unregister(id) }
      var installed: [Int32] = []
      for (id, modifiers, key) in registrations {
        guard rw_hotkey_register(id, modifiers, key) != 0 else {
          for value in installed { rw_hotkey_unregister(value) }
          var restored: [Int32] = []
          for (oldID, oldShortcut) in previous {
            guard let binding = oldShortcut.binding, let (oldModifiers, oldKey) = try? WindowsKeys.encode(binding),
                  rw_hotkey_register(oldID, oldModifiers, oldKey) != 0 else { continue }
            restored.append(oldID)
          }
          activeIDs = restored
          throw ValidationError("global shortcut '\(candidate[id]?.binding?.normalized ?? "?")' is unavailable (Win32 error \(rw_last_error())); previous bindings \(restored.count == previous.count ? "restored" : "could not be fully restored")")
        }
        installed.append(id)
      }
      activeIDs = installed
      shortcuts = candidate
      lastContents = try? Data(contentsOf: configURL)
      changedAt = nil
      notifier.status("Loaded \(installed.count) shortcuts")
      if !initial { notifier.info(title: "reflex-wm: Configuration Reloaded", body: "Loaded \(installed.count) shortcuts") }
    } catch {
      notifier.warning("configuration reload failed; previous shortcuts remain active when registration rollback succeeds: \(error.localizedDescription)")
    }
  }

  private func pollConfiguration(now: Date = Date()) -> Bool {
    guard now.timeIntervalSince(lastProbe) >= 0.5 else { return false }
    lastProbe = now
    let contents = try? Data(contentsOf: configURL)
    if contents != lastContents { lastContents = contents; changedAt = now }
    guard let changedAt, now.timeIntervalSince(changedAt) >= 0.25 else { return false }
    self.changedAt = nil
    return true
  }
}

private func defaultConfigURL() -> URL {
  URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/reflex-wm.toml")
}

let args = Array(CommandLine.arguments.dropFirst())
do {
  var config = defaultConfigURL()
  var check = false
  var showHelp = false
  var index = 0
  while index < args.count {
    switch args[index] {
    case "--config":
      index += 1
      guard index < args.count else { throw ValidationError("--config requires a path") }
      config = URL(fileURLWithPath: args[index]).standardizedFileURL
    case "--check-config": check = true
    case "--help":
      showHelp = true
    default: throw ValidationError("unknown argument: \(args[index])")
    }
    index += 1
  }
  if showHelp {
    print("Usage: reflex-wm [--config PATH] [--check-config]\nRuns as a Windows tray app; reload from its tray menu.")
  } else if check {
    let configuration = try ConfigurationLoader.decode(String(contentsOf: config, encoding: .utf8))
    let validated = try ConfigurationValidator.validate(configuration, supportsCapsLockRemap: false)
    for shortcut in validated.shortcuts { if let binding = shortcut.binding { _ = try WindowsKeys.encode(binding) } }
    print("Configuration valid for Windows (\(validated.shortcuts.filter { $0.binding != nil }.count) shortcuts)")
  } else { try WindowsApplication(configURL: config).run() }
} catch {
  FileHandle.standardError.write(Data("reflex-wm: \(error.localizedDescription)\n".utf8))
  exit(1)
}
