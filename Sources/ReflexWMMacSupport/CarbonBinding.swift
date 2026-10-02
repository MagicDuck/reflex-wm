import Carbon
import ReflexWMCore

extension BindingModifiers {
  public var carbonModifiers: UInt32 {
    var result: UInt32 = 0
    if contains(.command) { result |= UInt32(cmdKey) }
    if contains(.control) { result |= UInt32(controlKey) }
    if contains(.shift) { result |= UInt32(shiftKey) }
    if contains(.option) { result |= UInt32(optionKey) }
    return result
  }
}

extension HotKeyBinding {
  public var carbonKeyCode: UInt32 { Self.carbonKeyCodes[key]! }
  private static let carbonKeyCodes: [String: UInt32] = {
    var values: [String: UInt32] = [
      "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B),
      "c": UInt32(kVK_ANSI_C), "d": UInt32(kVK_ANSI_D),
      "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F),
      "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H),
      "i": UInt32(kVK_ANSI_I), "j": UInt32(kVK_ANSI_J),
      "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
      "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N),
      "o": UInt32(kVK_ANSI_O), "p": UInt32(kVK_ANSI_P),
      "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R),
      "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T),
      "u": UInt32(kVK_ANSI_U), "v": UInt32(kVK_ANSI_V),
      "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
      "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
      "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1),
      "2": UInt32(kVK_ANSI_2), "3": UInt32(kVK_ANSI_3),
      "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
      "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7),
      "8": UInt32(kVK_ANSI_8), "9": UInt32(kVK_ANSI_9),
      "`": UInt32(kVK_ANSI_Grave), "-": UInt32(kVK_ANSI_Minus),
      "=": UInt32(kVK_ANSI_Equal), "[": UInt32(kVK_ANSI_LeftBracket),
      "]": UInt32(kVK_ANSI_RightBracket), "\\": UInt32(kVK_ANSI_Backslash),
      ";": UInt32(kVK_ANSI_Semicolon), "'": UInt32(kVK_ANSI_Quote),
      ",": UInt32(kVK_ANSI_Comma), ".": UInt32(kVK_ANSI_Period),
      "/": UInt32(kVK_ANSI_Slash),
      "return": UInt32(kVK_Return), "tab": UInt32(kVK_Tab),
      "space": UInt32(kVK_Space), "escape": UInt32(kVK_Escape),
      "delete": UInt32(kVK_Delete), "home": UInt32(kVK_Home),
      "end": UInt32(kVK_End), "pageup": UInt32(kVK_PageUp),
      "page up": UInt32(kVK_PageUp), "pagedown": UInt32(kVK_PageDown),
      "page down": UInt32(kVK_PageDown), "left": UInt32(kVK_LeftArrow),
      "right": UInt32(kVK_RightArrow), "up": UInt32(kVK_UpArrow),
      "down": UInt32(kVK_DownArrow), "arrowleft": UInt32(kVK_LeftArrow),
      "arrowright": UInt32(kVK_RightArrow), "arrowup": UInt32(kVK_UpArrow),
      "arrowdown": UInt32(kVK_DownArrow), "printscr": UInt32(kVK_F13),
    ]
    let functionKeys: [UInt32] = [
      UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
      UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
      UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
      UInt32(kVK_F13), UInt32(kVK_F14), UInt32(kVK_F15), UInt32(kVK_F16),
      UInt32(kVK_F17), UInt32(kVK_F18), UInt32(kVK_F19), UInt32(kVK_F20),
    ]
    for (index, code) in functionKeys.enumerated() {
      values["f\(index + 1)"] = code
    }
    return values
  }()

}
