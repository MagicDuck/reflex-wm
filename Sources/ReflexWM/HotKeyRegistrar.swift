import Carbon
import CoreGraphics
import Foundation
import ReflexWMCore

@MainActor
final class HotKeyRegistrar {
  private struct Chord: Hashable {
    let keyCode: UInt32
    let modifiers: UInt32
  }

  private let signature: OSType = 0x5246_4C58  // RFLX
  private var eventHandler: EventHandlerRef?
  private var eventTap: CFMachPort?
  private var eventTapSource: CFRunLoopSource?
  private var registered: [UInt32: EventHotKeyRef] = [:]
  private var shortcuts: [UInt32: ValidatedShortcut] = [:]
  private var shortcutsByChord: [Chord: ValidatedShortcut] = [:]
  private var consumedKeyCodes = Set<UInt32>()
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

    let eventMask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
      | (CGEventMask(1) << CGEventType.keyUp.rawValue)
    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: hotKeySuppressionCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      ),
      let eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    else {
      if let eventHandler {
        RemoveEventHandler(eventHandler)
        self.eventHandler = nil
      }
      throw RuntimeError(
        "could not create the keyboard event filter; Accessibility permission is required"
      )
    }
    self.eventTap = eventTap
    self.eventTapSource = eventTapSource
    CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
  }

  func shutdown() {
    unregisterAll()
    if let eventTapSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
      self.eventTapSource = nil
    }
    if let eventTap {
      CFMachPortInvalidate(eventTap)
      self.eventTap = nil
    }
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
    guard shortcuts[id] != nil else { return }
  }

  fileprivate func filter(
    eventTypeRawValue: UInt32,
    keyCode: UInt32,
    eventFlagsRawValue: UInt64,
    isRepeat: Bool
  ) -> Bool {
    let type = CGEventType(rawValue: eventTypeRawValue)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
      return false
    }

    if type == .keyUp {
      return consumedKeyCodes.remove(keyCode) != nil
    }
    guard type == .keyDown else { return false }

    let flags = CGEventFlags(rawValue: eventFlagsRawValue)
    let chord = Chord(keyCode: keyCode, modifiers: carbonModifiers(for: flags))
    guard let shortcut = shortcutsByChord[chord] else { return false }
    consumedKeyCodes.insert(keyCode)
    if !isRepeat {
      Task { @MainActor [weak self] in
        self?.handler?(shortcut)
      }
    }
    return true
  }

  private func carbonModifiers(for flags: CGEventFlags) -> UInt32 {
    var modifiers: UInt32 = 0
    if flags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
    if flags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
    if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
    if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
    return modifiers
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
        OptionBits(kEventHotKeyExclusive),
        &reference
      )
      guard status == noErr, let reference else {
        throw RuntimeError(
          "could not register bind '\(binding.normalized)' (OSStatus \(status))"
        )
      }
      registered[id] = reference
      shortcuts[id] = shortcut
      shortcutsByChord[Chord(keyCode: binding.keyCode, modifiers: binding.modifiers)] = shortcut
    }
  }

  private func unregisterAll() {
    for reference in registered.values {
      UnregisterEventHotKey(reference)
    }
    registered.removeAll()
    shortcuts.removeAll()
    shortcutsByChord.removeAll()
    consumedKeyCodes.removeAll()
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

private let hotKeySuppressionCallback: CGEventTapCallBack = {
  _, type, event, userData in
  guard let userData else { return Unmanaged.passUnretained(event) }
  let registrar = Unmanaged<HotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
  let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
  let eventFlagsRawValue = event.flags.rawValue
  let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
  let consumed = MainActor.assumeIsolated {
    registrar.filter(
      eventTypeRawValue: type.rawValue,
      keyCode: keyCode,
      eventFlagsRawValue: eventFlagsRawValue,
      isRepeat: isRepeat
    )
  }
  return consumed ? nil : Unmanaged.passUnretained(event)
}
