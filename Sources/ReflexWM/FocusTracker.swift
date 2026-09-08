import AppKit
import ApplicationServices

@MainActor
final class FocusTracker {
  private var history: [ManagedWindow] = []
  private var observers: [pid_t: AXObserver] = [:]
  private var workspaceTokens: [NSObjectProtocol] = []

  func start() {
    let center = NSWorkspace.shared.notificationCenter
    workspaceTokens.append(
      center.addObserver(
        forName: NSWorkspace.didLaunchApplicationNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        guard
          let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication
        else { return }
        Task { @MainActor in self?.observe(application) }
      }
    )
    workspaceTokens.append(
      center.addObserver(
        forName: NSWorkspace.didTerminateApplicationNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        guard
          let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication
        else { return }
        Task { @MainActor in
          self?.observers.removeValue(forKey: application.processIdentifier)
          self?.history.removeAll {
            $0.application.processIdentifier == application.processIdentifier
          }
        }
      }
    )
    workspaceTokens.append(
      center.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.captureFocusedWindow() }
      }
    )

    for application in NSWorkspace.shared.runningApplications {
      observe(application)
    }
    captureFocusedWindow()
  }

  func stop() {
    let center = NSWorkspace.shared.notificationCenter
    workspaceTokens.forEach(center.removeObserver)
    workspaceTokens.removeAll()
    for observer in observers.values {
      CFRunLoopRemoveSource(
        CFRunLoopGetMain(),
        AXObserverGetRunLoopSource(observer),
        .commonModes
      )
    }
    observers.removeAll()
  }

  func captureFocusedWindow() {
    for application in NSWorkspace.shared.runningApplications {
      observe(application)
    }
    guard let window = AXSupport.focusedWindow() else { return }
    record(window)
  }

  func record(_ window: ManagedWindow) {
    history.removeAll { AXSupport.sameWindow($0, window) }
    history.insert(window, at: 0)
    history.removeAll { !AXSupport.isValid($0) }
    if history.count > 100 {
      history.removeLast(history.count - 100)
    }
  }

  func previous(excluding window: ManagedWindow) -> ManagedWindow? {
    history.first { !AXSupport.sameWindow($0, window) && AXSupport.isValid($0) }
  }

  func mostRecent(in candidates: [ManagedWindow]) -> ManagedWindow? {
    for recent in history {
      if let candidate = candidates.first(where: { AXSupport.sameWindow($0, recent) }) {
        return candidate
      }
    }
    return nil
  }

  private func observe(_ application: NSRunningApplication) {
    let pid = application.processIdentifier
    guard pid != ProcessInfo.processInfo.processIdentifier, observers[pid] == nil else {
      return
    }
    var observer: AXObserver?
    guard AXObserverCreate(pid, focusChangedCallback, &observer) == .success,
      let observer
    else { return }
    let appElement = AXUIElementCreateApplication(pid)
    let result = AXObserverAddNotification(
      observer,
      appElement,
      kAXFocusedWindowChangedNotification as CFString,
      Unmanaged.passUnretained(self).toOpaque()
    )
    guard result == .success || result == .notificationAlreadyRegistered else { return }
    CFRunLoopAddSource(
      CFRunLoopGetMain(),
      AXObserverGetRunLoopSource(observer),
      .commonModes
    )
    observers[pid] = observer
  }
}

private let focusChangedCallback: AXObserverCallback = { _, _, _, refcon in
  guard let refcon else { return }
  let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
  Task { @MainActor in tracker.captureFocusedWindow() }
}
