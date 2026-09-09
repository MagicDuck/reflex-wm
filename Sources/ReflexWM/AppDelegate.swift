import AppKit
import ApplicationServices
import Foundation
import ReflexWMCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private enum ReloadSource {
    case startup
    case menu
    case fileSystem
  }

  private let configDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config", isDirectory: true)
  private lazy var configURL = configDirectoryURL.appendingPathComponent("reflex-wm.toml")

  private let notifier = Notifier()
  private let focusTracker = FocusTracker()
  private lazy var windowManager = WindowManager(focusTracker: focusTracker)
  private lazy var actionController = ActionController(
    windowManager: windowManager,
    notifier: notifier
  )
  private var hotKeys: HotKeyRegistrar?
  private var watcher: ConfigurationWatcher?
  private var statusItem: NSStatusItem?
  private var statusMenuItem: NSMenuItem?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.accessory)
    configureStatusItem()
    notifier.statusDidChange = { [weak self] status in
      self?.statusMenuItem?.title = status
    }
    notifier.requestAuthorization()
    requestAccessibilityPermission()
    focusTracker.start()

    do {
      let registrar = try HotKeyRegistrar()
      registrar.handler = { [weak self] shortcut in
        self?.actionController.perform(shortcut)
      }
      hotKeys = registrar
    } catch {
      notifier.warning(error.localizedDescription)
    }

    watcher = ConfigurationWatcher(fileURL: configURL) { [weak self] in
      self?.reloadConfiguration(source: .fileSystem)
    }
    do {
      try watcher?.start()
    } catch {
      notifier.warning(error.localizedDescription)
    }
    reloadConfiguration(source: .startup)
  }

  func applicationWillTerminate(_ notification: Notification) {
    watcher?.stop()
    focusTracker.stop()
    hotKeys?.shutdown()
  }

  @objc private func reloadConfigurationFromMenu() {
    reloadConfiguration(source: .menu)
  }

  @objc private func openConfiguration() {
    if FileManager.default.fileExists(atPath: configURL.path) {
      NSWorkspace.shared.open(configURL)
    } else {
      NSWorkspace.shared.open(configDirectoryURL)
    }
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }

  private func reloadConfiguration(source: ReloadSource) {
    guard let hotKeys else { return }
    do {
      let contents = try String(contentsOf: configURL, encoding: .utf8)
      let configuration = try ConfigurationLoader.decode(contents)
      let validated = try ConfigurationValidator.validate(configuration)
      try hotKeys.apply(validated)
      let activeCount = validated.filter { $0.binding != nil }.count
      let status = "Loaded \(activeCount) shortcut\(activeCount == 1 ? "" : "s")"
      if source == .fileSystem || source == .menu {
        notifier.info(title: "reflex-wm: Configuration Reloaded", body: status)
      }
      notifier.status(status)
    } catch CocoaError.fileReadNoSuchFile {
      notifier.warning("configuration file not found: \(configURL.path)")
    } catch {
      notifier.warning("configuration reload failed: \(error.localizedDescription)")
    }
  }

  private func configureStatusItem() {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = menuBarIcon()
    statusItem.button?.imageScaling = .scaleProportionallyDown
    let menu = NSMenu()
    let status = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    status.isEnabled = false
    menu.addItem(status)
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Reload Configuration",
      action: #selector(reloadConfigurationFromMenu),
      keyEquivalent: "r"
    ).target = self
    menu.addItem(
      withTitle: "Open Configuration",
      action: #selector(openConfiguration),
      keyEquivalent: "o"
    ).target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit reflex-wm", action: #selector(quit), keyEquivalent: "q")
      .target = self
    statusItem.menu = menu
    self.statusItem = statusItem
    statusMenuItem = status
  }

  private func menuBarIcon() -> NSImage? {
    if let iconURL = Bundle.main.url(forResource: "reflex-wm", withExtension: "icns"),
      let icon = NSImage(contentsOf: iconURL)
    {
      icon.size = NSSize(width: 18, height: 18)
      icon.isTemplate = false
      icon.accessibilityDescription = "reflex-wm"
      return icon
    }
    return NSImage(
      systemSymbolName: "rectangle.3.group",
      accessibilityDescription: "reflex-wm"
    )
  }

  private func requestAccessibilityPermission() {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    if !AXIsProcessTrustedWithOptions(options) {
      notifier.status("Accessibility permission required")
    }
  }
}
