import Carbon
import CoreGraphics
import Foundation
import ReflexWMCore

@MainActor
final class HotKeyRegistrar {
  fileprivate enum FilterResult {
    case pass
    case passWithFlags(CGEventFlags)
    case consume
  }

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
  private var shortcutsByChord: [Chord: UInt32] = [:]
  private var consumedKeyCodes = Set<UInt32>()
  private var lastEventTapDispatch: [UInt32: UInt64] = [:]
  private var nextID: UInt32 = 1
  private let capsLockMonitor = CapsLockMonitor()
  private var capsLockModifiers: UInt32?

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

    let eventMask =
      (CGEventMask(1) << CGEventType.keyDown.rawValue)
      | (CGEventMask(1) << CGEventType.keyUp.rawValue)
      | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
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
    disableCapsLockRemap()
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

  func apply(
    _ candidate: [ValidatedShortcut],
    capsLockModifiers: UInt32?
  ) throws -> String? {
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
    return configureCapsLockRemap(modifiers: capsLockModifiers)
  }

  func removeAll() {
    disableCapsLockRemap()
    unregisterAll()
  }

  fileprivate func dispatch(id: UInt32, fromEventTap: Bool) {
    guard let shortcut = shortcuts[id] else { return }
    let now = DispatchTime.now().uptimeNanoseconds
    if fromEventTap {
      lastEventTapDispatch[id] = now
    } else {
      if let keyCode = shortcut.binding?.keyCode, consumedKeyCodes.contains(keyCode) {
        return
      }
      if let lastDispatch = lastEventTapDispatch[id], now - lastDispatch < 1_000_000_000 {
        return
      }
    }
    handler?(shortcut)
  }

  fileprivate func filter(
    eventTypeRawValue: UInt32,
    keyCode: UInt32,
    eventFlagsRawValue: UInt64,
    isRepeat: Bool
  ) -> FilterResult {
    let type = CGEventType(rawValue: eventTypeRawValue)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
      return .pass
    }

    let flags = CGEventFlags(rawValue: eventFlagsRawValue)
    if type == .flagsChanged, keyCode == UInt32(kVK_CapsLock), capsLockModifiers != nil {
      Task { @MainActor [weak self] in
        self?.capsLockMonitor.forceLEDsOff()
        if flags.contains(.maskAlphaShift) {
          self?.normalizeCapsLockState()
        }
      }
      return .consume
    }

    var forwardedFlags = flags
    if capsLockModifiers != nil {
      forwardedFlags.remove(.maskAlphaShift)
    }

    if type == .keyUp {
      if consumedKeyCodes.remove(keyCode) != nil {
        return .consume
      }
      return forwardedFlags == flags ? .pass : .passWithFlags(forwardedFlags)
    }
    guard type == .keyDown else {
      return forwardedFlags == flags ? .pass : .passWithFlags(forwardedFlags)
    }
    if consumedKeyCodes.contains(keyCode) {
      return .consume
    }

    var modifiers = carbonModifiers(for: forwardedFlags)
    if capsLockMonitor.isHeld, let capsLockModifiers {
      modifiers |= capsLockModifiers
    }
    let chord = Chord(keyCode: keyCode, modifiers: modifiers)
    guard let id = shortcutsByChord[chord] else {
      return forwardedFlags == flags ? .pass : .passWithFlags(forwardedFlags)
    }
    consumedKeyCodes.insert(keyCode)
    if !isRepeat {
      Task { @MainActor [weak self] in
        self?.dispatch(id: id, fromEventTap: true)
      }
    }
    return .consume
  }

  private func configureCapsLockRemap(modifiers: UInt32?) -> String? {
    guard let modifiers else {
      disableCapsLockRemap()
      return nil
    }
    if let warning = capsLockMonitor.start() {
      self.capsLockModifiers = nil
      return warning
    }
    capsLockModifiers = modifiers
    capsLockMonitor.forceLEDsOff()
    normalizeCapsLockState()
    return nil
  }

  private func disableCapsLockRemap() {
    let wasEnabled = capsLockModifiers != nil || capsLockMonitor.isRunning
    capsLockModifiers = nil
    capsLockMonitor.stop()
    if wasEnabled {
      normalizeCapsLockState()
    }
  }

  private func normalizeCapsLockState() {
    let flags = CGEventSource.flagsState(.combinedSessionState)
    guard flags.contains(.maskAlphaShift),
      let source = CGEventSource(stateID: .combinedSessionState),
      let down = CGEvent(
        keyboardEventSource: source,
        virtualKey: CGKeyCode(kVK_CapsLock),
        keyDown: true
      ),
      let up = CGEvent(
        keyboardEventSource: source,
        virtualKey: CGKeyCode(kVK_CapsLock),
        keyDown: false
      )
    else { return }
    down.setIntegerValueField(.eventSourceUserData, value: capsLockNormalizationMarker)
    up.setIntegerValueField(.eventSourceUserData, value: capsLockNormalizationMarker)
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    capsLockMonitor.forceLEDsOff()
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
      shortcutsByChord[Chord(keyCode: binding.keyCode, modifiers: binding.modifiers)] = id
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
    lastEventTapDispatch.removeAll()
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
  Task { @MainActor in registrar.dispatch(id: hotKeyID.id, fromEventTap: false) }
  return noErr
}

private let hotKeySuppressionCallback: CGEventTapCallBack = {
  _, type, event, userData in
  guard let userData else { return Unmanaged.passUnretained(event) }
  if event.getIntegerValueField(.eventSourceUserData) == capsLockNormalizationMarker {
    return Unmanaged.passUnretained(event)
  }
  let registrar = Unmanaged<HotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
  let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
  let eventFlagsRawValue = event.flags.rawValue
  let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
  let result = MainActor.assumeIsolated {
    registrar.filter(
      eventTypeRawValue: type.rawValue,
      keyCode: keyCode,
      eventFlagsRawValue: eventFlagsRawValue,
      isRepeat: isRepeat
    )
  }
  switch result {
  case .pass:
    return Unmanaged.passUnretained(event)
  case .passWithFlags(let flags):
    event.flags = flags
    return Unmanaged.passUnretained(event)
  case .consume:
    return nil
  }
}

private let capsLockNormalizationMarker: Int64 = 0x5246_4C58_4341_5053
