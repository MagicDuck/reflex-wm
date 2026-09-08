import Carbon
import Foundation
import ReflexWMCore

@MainActor
final class HotKeyRegistrar {
  private let signature: OSType = 0x5246_4C58  // RFLX
  private var eventHandler: EventHandlerRef?
  private var registered: [UInt32: EventHotKeyRef] = [:]
  private var shortcuts: [UInt32: ValidatedShortcut] = [:]
  private var nextID: UInt32 = 1

  var handler: ((ValidatedShortcut) -> Void)?

  init() throws {
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      hotKeyEventCallback,
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )
    guard status == noErr else {
      throw RuntimeError("could not install the global hotkey event handler (\(status))")
    }
  }

  func shutdown() {
    unregisterAll()
    if let eventHandler {
      RemoveEventHandler(eventHandler)
      self.eventHandler = nil
    }
  }

  func apply(_ candidate: [ValidatedShortcut]) throws {
    let previous = shortcuts.values.sorted { lhs, rhs in
      (lhs.binding?.normalized ?? "") < (rhs.binding?.normalized ?? "")
    }
    unregisterAll()
    do {
      try register(candidate)
    } catch {
      unregisterAll()
      do {
        try register(previous)
      } catch {
        unregisterAll()
      }
      throw error
    }
  }

  func removeAll() {
    unregisterAll()
  }

  fileprivate func dispatch(id: UInt32) {
    guard let shortcut = shortcuts[id] else { return }
    handler?(shortcut)
  }

  private func register(_ values: [ValidatedShortcut]) throws {
    for shortcut in values {
      guard let binding = shortcut.binding else { continue }
      let id = nextID
      nextID &+= 1
      var reference: EventHotKeyRef?
      let status = RegisterEventHotKey(
        binding.keyCode,
        binding.modifiers,
        EventHotKeyID(signature: signature, id: id),
        GetApplicationEventTarget(),
        0,
        &reference
      )
      guard status == noErr, let reference else {
        throw RuntimeError(
          "could not register bind '\(binding.normalized)' (OSStatus \(status))"
        )
      }
      registered[id] = reference
      shortcuts[id] = shortcut
    }
  }

  private func unregisterAll() {
    for reference in registered.values {
      UnregisterEventHotKey(reference)
    }
    registered.removeAll()
    shortcuts.removeAll()
  }
}

private let hotKeyEventCallback: EventHandlerUPP = { _, event, userData in
  guard let event, let userData else { return OSStatus(eventNotHandledErr) }
  var hotKeyID = EventHotKeyID()
  let status = GetEventParameter(
    event,
    EventParamName(kEventParamDirectObject),
    EventParamType(typeEventHotKeyID),
    nil,
    MemoryLayout<EventHotKeyID>.size,
    nil,
    &hotKeyID
  )
  guard status == noErr else { return status }
  let registrar = Unmanaged<HotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
  Task { @MainActor in registrar.dispatch(id: hotKeyID.id) }
  return noErr
}
