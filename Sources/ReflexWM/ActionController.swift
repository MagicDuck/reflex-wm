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
    guard let command = shortcut.source.launchCommand,
      !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw RuntimeError("no matching window was found and launch_cmd is not configured")
    }
    guard launchesInFlight.insert(command).inserted else { return }
    try launch(command, conditions: shortcut.effectiveMatches)
  }

  // TODO (sbadragan): this is interesting, it uses zsh to launch
  private func launch(_ command: String, conditions: [MatchCondition]) throws {
    let process = Process()
    process.executableURL = URL(
      fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    )
    process.arguments = ["-lc", command]
    process.terminationHandler = { [weak self] process in
      guard process.terminationStatus != 0 else { return }
      Task { @MainActor in
        self?.launchesInFlight.remove(command)
        self?.notifier.warning(
          "launch_cmd exited with status \(process.terminationStatus): \(command)"
        )
      }
    }
    do {
      try process.run()
    } catch {
      launchesInFlight.remove(command)
      throw RuntimeError("could not run launch_cmd: \(error.localizedDescription)")
    }

    Task { @MainActor [weak self] in
      guard let self else { return }
      for _ in 0..<50 {
        try? await Task.sleep(for: .milliseconds(200))
        if let window = windowManager.matchedWindow(for: conditions) {
          launchesInFlight.remove(command)
          try? windowManager.focus(window)
          return
        }
      }
      launchesInFlight.remove(command)
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
