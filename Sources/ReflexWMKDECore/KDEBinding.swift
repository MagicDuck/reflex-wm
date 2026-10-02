import Foundation
import ReflexWMCore

public enum KDEBinding {
  // TOML uses unshifted ANSI key names. KWin matches shifted punctuation by
  // its resulting symbol, with the consumed Shift modifier removed.
  private static let shiftedSymbols: [String: String] = [
    "`": "~", "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
    "6": "^", "7": "&", "8": "*", "9": "(", "0": ")", "-": "_", "=": "+",
    "[": "{", "]": "}", "\\": "|", ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?",
  ]

  /// Qt::Key | Qt::KeyboardModifiers, as used by KGlobalAccel's D-Bus API.
  public static func encode(_ binding: HotKeyBinding) throws -> Int32 {
    let special: [String: Int32] = [
      "escape": 0x0100_0000, "tab": 0x0100_0001, "delete": 0x0100_0003,
      "return": 0x0100_0004, "home": 0x0100_0010, "end": 0x0100_0011,
      "left": 0x0100_0012, "up": 0x0100_0013, "right": 0x0100_0014,
      "down": 0x0100_0015, "pageup": 0x0100_0016, "pagedown": 0x0100_0017,
      "printscr": 0x0100_0009, "space": 0x20,
    ]
    let shiftedSymbol = binding.modifiers.contains(.shift) ? shiftedSymbols[binding.key] : nil
    let keyName = shiftedSymbol ?? binding.key
    var key: Int32
    if let value = special[keyName] {
      key = value
    } else if keyName.hasPrefix("f"), let number = Int32(keyName.dropFirst()),
      (1...20).contains(number)
    {
      key = 0x0100_0030 + number - 1
    } else if keyName.count == 1, let scalar = keyName.uppercased().unicodeScalars.first,
      scalar.value < 128
    {
      key = Int32(scalar.value)
    } else {
      throw ValidationError("unsupported KDE key: \(binding.key)")
    }
    if binding.modifiers.contains(.shift), shiftedSymbol == nil { key |= 0x0200_0000 }
    if binding.modifiers.contains(.control) { key |= 0x0400_0000 }
    if binding.modifiers.contains(.option) { key |= 0x0800_0000 }
    if binding.modifiers.contains(.command) { key |= 0x1000_0000 }
    return key
  }
}
