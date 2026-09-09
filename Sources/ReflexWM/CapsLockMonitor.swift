import Foundation
import IOKit.hid
import OSLog
import Synchronization

final class CapsLockMonitor: @unchecked Sendable {
  private struct State {
    var pressedDevices = Set<ObjectIdentifier>()
  }

  private let logger = Logger(subsystem: "com.reflexwm.app", category: "caps-lock-remap")
  private let state = Mutex(State())
  private var manager: IOHIDManager?

  var isRunning: Bool { manager != nil }

  var isHeld: Bool {
    state.withLock { !$0.pressedDevices.isEmpty }
  }

  func start() -> String? {
    guard manager == nil else { return nil }

    let requestType = kIOHIDRequestTypeListenEvent
    let access = IOHIDCheckAccess(requestType)
    guard access == kIOHIDAccessTypeGranted else {
      return
        "Caps Lock remap disabled: keyboard input access is unavailable; enable reflex-wm in System Settings > Privacy & Security > Accessibility (or Input Monitoring if shown), then reload configuration"
    }

    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let keyboardMatch: [String: Any] = [
      kIOHIDDeviceUsagePageKey: Int(kHIDPage_GenericDesktop),
      kIOHIDDeviceUsageKey: Int(kHIDUsage_GD_Keyboard),
    ]
    let capsLockMatch: [String: Any] = [
      kIOHIDElementUsagePageKey: Int(kHIDPage_KeyboardOrKeypad),
      kIOHIDElementUsageKey: Int(kHIDUsage_KeyboardCapsLock),
    ]
    IOHIDManagerSetDeviceMatching(manager, keyboardMatch as CFDictionary)
    IOHIDManagerSetInputValueMatching(manager, capsLockMatch as CFDictionary)

    let context = Unmanaged.passUnretained(self).toOpaque()
    IOHIDManagerRegisterDeviceMatchingCallback(manager, capsLockDeviceMatchedCallback, context)
    IOHIDManagerRegisterDeviceRemovalCallback(manager, capsLockDeviceRemovedCallback, context)
    IOHIDManagerRegisterInputValueCallback(manager, capsLockInputValueCallback, context)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

    let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard status == kIOReturnSuccess else {
      IOHIDManagerUnscheduleFromRunLoop(
        manager,
        CFRunLoopGetMain(),
        CFRunLoopMode.commonModes.rawValue
      )
      return "Caps Lock remap disabled: could not open keyboard input monitor (\(status))"
    }

    self.manager = manager
    return nil
  }

  func stop() {
    guard let manager else {
      clearPressedDevices()
      return
    }
    IOHIDManagerUnscheduleFromRunLoop(
      manager,
      CFRunLoopGetMain(),
      CFRunLoopMode.commonModes.rawValue
    )
    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    self.manager = nil
    clearPressedDevices()
  }

  func forceLEDsOff() {
    guard let manager, let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
    else { return }
    for device in devices {
      forceLEDOff(device)
    }
  }

  fileprivate func deviceMatched(_ device: IOHIDDevice) {
    forceLEDOff(device)
  }

  fileprivate func deviceRemoved(_ device: IOHIDDevice) {
    let id = ObjectIdentifier(device)
    state.withLock { state in
      _ = state.pressedDevices.remove(id)
    }
  }

  fileprivate func received(_ value: IOHIDValue) {
    let element = IOHIDValueGetElement(value)
    guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_KeyboardOrKeypad),
      IOHIDElementGetUsage(element) == UInt32(kHIDUsage_KeyboardCapsLock)
    else { return }

    let device = IOHIDElementGetDevice(element)
    let id = ObjectIdentifier(device)
    if IOHIDValueGetIntegerValue(value) != 0 {
      state.withLock { state in
        _ = state.pressedDevices.insert(id)
      }
      forceLEDOff(device)
    } else {
      state.withLock { state in
        _ = state.pressedDevices.remove(id)
      }
    }
  }

  private func clearPressedDevices() {
    state.withLock { $0.pressedDevices.removeAll() }
  }

  private func forceLEDOff(_ device: IOHIDDevice) {
    let match: [String: Any] = [
      kIOHIDElementUsagePageKey: Int(kHIDPage_LEDs),
      kIOHIDElementUsageKey: Int(kHIDUsage_LED_CapsLock),
    ]
    guard
      let elements = IOHIDDeviceCopyMatchingElements(
        device,
        match as CFDictionary,
        IOOptionBits(kIOHIDOptionsTypeNone)
      ) as? [IOHIDElement]
    else { return }

    for element in elements {
      let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, 0)
      let status = IOHIDDeviceSetValue(device, element, value)
      if status != kIOReturnSuccess {
        logger.debug("Could not turn off Caps Lock LED (\(status))")
      }
    }
  }
}

private let capsLockDeviceMatchedCallback: IOHIDDeviceCallback = {
  context, result, _, device in
  guard result == kIOReturnSuccess, let context else { return }
  let monitor = Unmanaged<CapsLockMonitor>.fromOpaque(context).takeUnretainedValue()
  monitor.deviceMatched(device)
}

private let capsLockDeviceRemovedCallback: IOHIDDeviceCallback = {
  context, _, _, device in
  guard let context else { return }
  let monitor = Unmanaged<CapsLockMonitor>.fromOpaque(context).takeUnretainedValue()
  monitor.deviceRemoved(device)
}

private let capsLockInputValueCallback: IOHIDValueCallback = {
  context, result, _, value in
  guard result == kIOReturnSuccess, let context else { return }
  let monitor = Unmanaged<CapsLockMonitor>.fromOpaque(context).takeUnretainedValue()
  monitor.received(value)
}
