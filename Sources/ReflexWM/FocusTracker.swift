import AppKit
import ApplicationServices

@MainActor
final class FocusTracker: NSObject {
  private var history: [ManagedWindow] = []
  private var observers: [pid_t: AXObserver] = [:]
  private var failedObserverPIDs = Set<pid_t>()
  private var workspaceTokens: [NSObjectProtocol] = []
  private var permissionRetryTimer: Timer?

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
          self?.failedObserverPIDs.remove(application.processIdentifier)
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
    if !AXIsProcessTrusted(), !failedObserverPIDs.isEmpty {
      permissionRetryTimer = Timer.scheduledTimer(
        timeInterval: 1,
        target: self,
        selector: #selector(retryObserversAfterPermissionGrant),
        userInfo: nil,
        repeats: true
      )
    }
    captureFocusedWindow()
  }

  func stop() {
    let center = NSWorkspace.shared.notificationCenter
    workspaceTokens.forEach(center.removeObserver)
    workspaceTokens.removeAll()
    permissionRetryTimer?.invalidate()
    permissionRetryTimer = nil
    for observer in observers.values {
      CFRunLoopRemoveSource(
        CFRunLoopGetMain(),
        AXObserverGetRunLoopSource(observer),
        .commonModes
      )
    }
    observers.removeAll()
    failedObserverPIDs.removeAll()
  }

  func captureFocusedWindow() {
    _ = captureFocusedWindowForToggle()
  }

  func captureFocusedWindowForToggle() -> ManagedWindow? {
    guard let window = AXSupport.focusedWindow() else { return nil }
    record(window)
    return window
  }

  func record(_ window: ManagedWindow) {
    history.removeAll { AXSupport.sameWindow($0, window) }
    history.insert(window, at: 0)
    if history.count > 100 {
      history.removeLast(history.count - 100)
    }
  }

  func previous(excluding window: ManagedWindow) -> ManagedWindow? {
    var index = 0
    while index < history.count {
      let candidate = history[index]
      if candidate.application.isTerminated {
        history.remove(at: index)
        continue
      }
      if AXSupport.sameWindow(candidate, window) {
        index += 1
        continue
      }
      if AXSupport.isValid(candidate) {
        return candidate
      }
      history.remove(at: index)
    }
    return nil
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
    else {
      failedObserverPIDs.insert(pid)
      return
    }
    let appElement = AXUIElementCreateApplication(pid)
    let result = AXObserverAddNotification(
      observer,
      appElement,
      kAXFocusedWindowChangedNotification as CFString,
      Unmanaged.passUnretained(self).toOpaque()
    )
    guard result == .success || result == .notificationAlreadyRegistered else {
      failedObserverPIDs.insert(pid)
      return
    }
    CFRunLoopAddSource(
      CFRunLoopGetMain(),
      AXObserverGetRunLoopSource(observer),
      .commonModes
    )
    observers[pid] = observer
    failedObserverPIDs.remove(pid)
  }

  @objc private func retryObserversAfterPermissionGrant() {
    guard AXIsProcessTrusted() else { return }
    permissionRetryTimer?.invalidate()
    permissionRetryTimer = nil

    let pendingPIDs = failedObserverPIDs
    failedObserverPIDs.removeAll()
    for application in NSWorkspace.shared.runningApplications
    where pendingPIDs.contains(application.processIdentifier) {
      observe(application)
    }
    captureFocusedWindow()
  }
}

private let focusChangedCallback: AXObserverCallback = { _, _, _, refcon in
  guard let refcon else { return }
  let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
  Task { @MainActor in tracker.captureFocusedWindow() }
}
