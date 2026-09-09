import Foundation
import ReflexWMCore

@MainActor
final class ActionController {
  private let windowManager: WindowManager
  private let notifier: Notifier
  private var launchesInFlight = Set<String>()

  init(windowManager: WindowManager, notifier: Notifier) {
    self.windowManager = windowManager
    self.notifier = notifier
  }

  func perform(_ shortcut: ValidatedShortcut) {
    do {
      switch shortcut.source.action {
      case .toggleApp:
        try toggleApp(shortcut)
      case .toggleMaximize:
        try windowManager.toggleMaximize()
      case .close:
        try windowManager.closeFocusedWindow()
      case .moveToNextScreen:
        try windowManager.moveFocusedWindowToNextScreen()
      case .notifyWindowInfo:
        try notifyWindowInfo()
      case .focusNextAppWindow:
        try windowManager.focusNextAppWindow()
      case .toggleVerticalSplit:
        try windowManager.toggleVerticalSplit()
      }
    } catch {
      notifier.warning(error.localizedDescription)
    }
  }

  private func toggleApp(_ shortcut: ValidatedShortcut) throws {
    guard !shortcut.effectiveMatches.isEmpty else { return }
    if let window = windowManager.matchedWindow(for: shortcut.effectiveMatches) {
      try windowManager.toggle(to: window)
      return
    }
    if let command = nonEmpty(shortcut.source.launchCommand) {
      let launchID = "command:\(command)"
      guard launchesInFlight.insert(launchID).inserted else { return }
      try launch(command, launchID: launchID, conditions: shortcut.effectiveMatches)
      return
    }
    if let applicationName = nonEmpty(shortcut.source.launchApplication) {
      let launchID = "application:\(applicationName)"
      guard launchesInFlight.insert(launchID).inserted else { return }
      try launchApplication(
        named: applicationName,
        launchID: launchID,
        conditions: shortcut.effectiveMatches
      )
      return
    }
    throw RuntimeError(
      "no matching window was found and neither launch_cmd nor launch_app is configured"
    )
  }

  private func nonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func launch(
    _ command: String,
    launchID: String,
    conditions: [MatchCondition]
  ) throws {
    let process = Process()
    process.executableURL = URL(
      fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    )
    process.arguments = ["-lc", command]
    process.terminationHandler = { [weak self] process in
      guard process.terminationStatus != 0 else { return }
      Task { @MainActor in
        self?.launchesInFlight.remove(launchID)
        self?.notifier.warning(
          "launch_cmd exited with status \(process.terminationStatus): \(command)"
        )
      }
    }
    do {
      try process.run()
    } catch {
      launchesInFlight.remove(launchID)
      throw RuntimeError("could not run launch_cmd: \(error.localizedDescription)")
    }

    retryMatchingWindow(launchID: launchID, conditions: conditions)
  }

  private func launchApplication(
    named applicationName: String,
    launchID: String,
    conditions: [MatchCondition]
  ) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", applicationName]
    process.terminationHandler = { [weak self] process in
      guard process.terminationStatus != 0 else { return }
      Task { @MainActor in
        self?.launchesInFlight.remove(launchID)
        self?.notifier.warning(
          "launch_app exited with status \(process.terminationStatus): \(applicationName)"
        )
      }
    }
    do {
      try process.run()
    } catch {
      launchesInFlight.remove(launchID)
      throw RuntimeError("could not run launch_app: \(error.localizedDescription)")
    }

    retryMatchingWindow(launchID: launchID, conditions: conditions)
  }

  private func retryMatchingWindow(launchID: String, conditions: [MatchCondition]) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      for _ in 0..<50 {
        try? await Task.sleep(for: .milliseconds(200))
        if let window = windowManager.matchedWindow(for: conditions) {
          launchesInFlight.remove(launchID)
          try? windowManager.focus(window)
          return
        }
      }
      launchesInFlight.remove(launchID)
    }
  }

  private func notifyWindowInfo() throws {
    let metadata = try windowManager.focusedWindowMetadata()
    notifier.info(
      title: "reflex-wm: Window Info",
      body: WindowInfoFormatter.body(for: metadata)
    )
  }
}
