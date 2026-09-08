import AppKit
import ApplicationServices
import Foundation
import ReflexWMCore

@MainActor
final class WindowManager {
  private let focusTracker: FocusTracker
  private var restoreFrames: [String: CGRect] = [:]

  init(focusTracker: FocusTracker) {
    self.focusTracker = focusTracker
  }

  func matchedWindow(for conditions: [MatchCondition]) -> ManagedWindow? {
    let windows = AXSupport.allWindows()
    let indexes = MatchResolver.firstMatchingIndexes(
      conditions: conditions,
      candidates: windows.map(\.metadata)
    )
    let matches = indexes.map { windows[$0] }
    guard !matches.isEmpty else { return nil }
    if let recent = focusTracker.mostRecent(in: matches) {
      return recent
    }
    if let focused = AXSupport.focusedWindow(),
      let match = matches.first(where: { AXSupport.sameWindow($0, focused) })
    {
      return match
    }
    return matches[0]
  }

  func toggle(to target: ManagedWindow) throws {
    focusTracker.captureFocusedWindow()
    if let focused = AXSupport.focusedWindow(), AXSupport.sameWindow(focused, target) {
      guard let previous = focusTracker.previous(excluding: target) else {
        // TODO (sbadragan): just do nothing if there is nothing previous to activate?
        throw RuntimeError("there is no previous window to activate")
      }
      try focus(previous)
    } else {
      try focus(target)
    }
  }

  func focus(_ window: ManagedWindow) throws {
    if AXSupport.bool(window.element, kAXMinimizedAttribute as CFString) == true {
      let result = AXUIElementSetAttributeValue(
        window.element,
        kAXMinimizedAttribute as CFString,
        kCFBooleanFalse
      )
      guard result == .success else {
        throw RuntimeError("could not unminimize the selected window")
      }
    }
    window.application.activate(options: [])
    _ = AXUIElementSetAttributeValue(
      window.element,
      kAXMainAttribute as CFString,
      kCFBooleanTrue
    )
    _ = AXUIElementSetAttributeValue(
      window.element,
      kAXFocusedAttribute as CFString,
      kCFBooleanTrue
    )
    let result = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    guard result == .success else {
      throw RuntimeError("could not raise the selected window")
    }
    focusTracker.record(window)
  }

  func toggleMaximize() throws {
    let window = try requireFocusedWindow()
    if let restoreFrame = restoreFrames.removeValue(forKey: window.key) {
      try AXSupport.setFrame(restoreFrame, of: window.element)
      return
    }
    guard let frame = AXSupport.frame(of: window.element), let screen = screen(containing: frame)
    else {
      throw RuntimeError("could not determine the focused window's screen")
    }
    restoreFrames[window.key] = frame
    do {
      try AXSupport.setFrame(screen.visibleFrame, of: window.element)
    } catch {
      restoreFrames.removeValue(forKey: window.key)
      throw error
    }
  }

  func closeFocusedWindow() throws {
    let window = try requireFocusedWindow()
    guard
      let closeButton = AXSupport.attribute(
        window.element,
        kAXCloseButtonAttribute as CFString
      ) as! AXUIElement?
    else {
      throw RuntimeError("the focused window has no accessible close button")
    }
    guard AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success else {
      throw RuntimeError("could not close the focused window")
    }
  }

  func moveFocusedWindowToNextScreen() throws {
    let window = try requireFocusedWindow()
    guard let frame = AXSupport.frame(of: window.element) else {
      throw RuntimeError("could not read the focused window frame")
    }
    let screens = NSScreen.screens.sorted {
      if $0.frame.minX == $1.frame.minX { return $0.frame.minY > $1.frame.minY }
      return $0.frame.minX < $1.frame.minX
    }
    guard screens.count > 1, let current = screen(containing: frame),
      let index = screens.firstIndex(where: { $0 === current })
    else {
      throw RuntimeError("there is no next screen")
    }
    let mapped = ScreenGeometry.map(
      frame,
      from: current.visibleFrame,
      to: screens[(index + 1) % screens.count].visibleFrame
    )
    try AXSupport.setFrame(mapped, of: window.element)
  }

  func focusedWindowMetadata() throws -> WindowMetadata {
    try requireFocusedWindow().metadata
  }

  private func requireFocusedWindow() throws -> ManagedWindow {
    guard let window = AXSupport.focusedWindow() else {
      throw RuntimeError("there is no focused accessible window")
    }
    return window
  }

  private func screen(containing frame: CGRect) -> NSScreen? {
    NSScreen.screens.max { lhs, rhs in
      lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
    }
  }
}

extension CGRect {
  fileprivate var area: CGFloat { isNull ? 0 : width * height }
}
