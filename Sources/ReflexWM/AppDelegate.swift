import AppKit
import ApplicationServices
import Foundation
import ReflexWMCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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

    watcher = ConfigurationWatcher(directoryURL: configDirectoryURL) { [weak self] in
      self?.reloadConfiguration()
    }
    do {
      try watcher?.start()
    } catch {
      notifier.warning(error.localizedDescription)
    }
    reloadConfiguration()
  }

  func applicationWillTerminate(_ notification: Notification) {
    watcher?.stop()
    focusTracker.stop()
    hotKeys?.shutdown()
  }

  @objc private func reloadConfigurationFromMenu() {
    reloadConfiguration()
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

  private func reloadConfiguration() {
    guard let hotKeys else { return }
    do {
      let contents = try String(contentsOf: configURL, encoding: .utf8)
      let configuration = try ConfigurationLoader.decode(contents)
      let validated = try ConfigurationValidator.validate(configuration)
      try hotKeys.apply(validated)
      let activeCount = validated.filter { $0.binding != nil }.count
      notifier.status("Loaded \(activeCount) shortcut\(activeCount == 1 ? "" : "s")")
    } catch CocoaError.fileReadNoSuchFile {
      notifier.warning("configuration file not found: \(configURL.path)")
    } catch {
      notifier.warning("configuration reload failed: \(error.localizedDescription)")
    }
  }

  private func configureStatusItem() {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = NSImage(
      // TODO (sbadragan): do we want a fany app icon?
      systemSymbolName: "rectangle.3.group",
      accessibilityDescription: "reflex-wm"
    )
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

  private func requestAccessibilityPermission() {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    if !AXIsProcessTrustedWithOptions(options) {
      notifier.status("Accessibility permission required")
    }
  }
}
