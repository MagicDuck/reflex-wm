import AppKit
import ApplicationServices
import Foundation
import ReflexWMCore

struct ManagedWindow {
  let element: AXUIElement
  let application: NSRunningApplication
  let metadata: WindowMetadata

  var key: String {
    "\(application.processIdentifier):\(CFHash(element))"
  }
}

enum AXSupport {
  static func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
      return nil
    }
    return value
  }

  static func string(_ element: AXUIElement, _ name: CFString) -> String? {
    attribute(element, name) as? String
  }

  static func bool(_ element: AXUIElement, _ name: CFString) -> Bool? {
    attribute(element, name) as? Bool
  }

  static func windows(for application: NSRunningApplication) -> [ManagedWindow] {
    let appElement = AXUIElementCreateApplication(application.processIdentifier)
    guard let values = attribute(appElement, kAXWindowsAttribute as CFString) as? [AXUIElement]
    else {
      return []
    }
    return values.compactMap { window in
      guard string(window, kAXRoleAttribute as CFString) == (kAXWindowRole as String) else {
        return nil
      }
      return ManagedWindow(
        element: window,
        application: application,
        metadata: metadata(for: window, application: application)
      )
    }
  }

  static func metadata(for application: NSRunningApplication) -> WindowMetadata {
    WindowMetadata(
      appID: application.bundleIdentifier,
      appName: application.localizedName,
      executableName: application.executableURL?.lastPathComponent,
      windowTitle: nil
    )
  }

  static func focusedWindow() -> ManagedWindow? {
    let system = AXUIElementCreateSystemWide()
    guard
      let appElement = attribute(system, kAXFocusedApplicationAttribute as CFString)
        as! AXUIElement?,
      let window = attribute(appElement, kAXFocusedWindowAttribute as CFString)
        as! AXUIElement?
    else {
      return nil
    }
    var pid: pid_t = 0
    guard AXUIElementGetPid(appElement, &pid) == .success,
      let application = NSRunningApplication(processIdentifier: pid)
    else {
      return nil
    }
    return ManagedWindow(
      element: window,
      application: application,
      metadata: metadata(for: window, application: application)
    )
  }

  static func metadata(
    for window: AXUIElement,
    application: NSRunningApplication
  ) -> WindowMetadata {
    WindowMetadata(
      appID: application.bundleIdentifier,
      appName: application.localizedName,
      executableName: application.executableURL?.lastPathComponent,
      windowTitle: string(window, kAXTitleAttribute as CFString)
    )
  }

  static func sameWindow(_ lhs: ManagedWindow, _ rhs: ManagedWindow) -> Bool {
    lhs.application.processIdentifier == rhs.application.processIdentifier
      && CFEqual(lhs.element, rhs.element)
  }

  static func isValid(_ window: ManagedWindow) -> Bool {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(
      window.element,
      kAXRoleAttribute as CFString,
      &value
    ) == .success
  }

  static func frame(of window: AXUIElement) -> CGRect? {
    guard
      let positionValue = attribute(window, kAXPositionAttribute as CFString),
      let sizeValue = attribute(window, kAXSizeAttribute as CFString),
      CFGetTypeID(positionValue) == AXValueGetTypeID(),
      CFGetTypeID(sizeValue) == AXValueGetTypeID()
    else {
      return nil
    }
    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
      AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    else {
      return nil
    }
    let mainTop = NSScreen.screens.first?.frame.maxY ?? 0
    return CGRect(
      x: point.x, y: mainTop - point.y - size.height, width: size.width, height: size.height)
  }

  static func setFrame(_ frame: CGRect, of window: AXUIElement) throws {
    let mainTop = NSScreen.screens.first?.frame.maxY ?? 0
    var point = CGPoint(x: frame.minX, y: mainTop - frame.maxY)
    var size = frame.size
    guard let positionValue = AXValueCreate(.cgPoint, &point),
      let sizeValue = AXValueCreate(.cgSize, &size)
    else {
      throw RuntimeError("could not create Accessibility frame values")
    }
    let positionError = AXUIElementSetAttributeValue(
      window,
      kAXPositionAttribute as CFString,
      positionValue
    )
    let sizeError = AXUIElementSetAttributeValue(
      window,
      kAXSizeAttribute as CFString,
      sizeValue
    )
    guard positionError == .success, sizeError == .success else {
      throw RuntimeError("window does not allow position/size changes")
    }
  }
}

struct RuntimeError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}
