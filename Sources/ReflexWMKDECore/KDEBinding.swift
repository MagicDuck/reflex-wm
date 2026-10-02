import Foundation
import ReflexWMCore

public enum KDEBinding {
  /// Qt::Key | Qt::KeyboardModifiers, as used by KGlobalAccel's D-Bus API.
  public static func encode(_ binding: HotKeyBinding) throws -> Int32 {
    let special: [String: Int32] = [
      "escape": 0x0100_0000, "tab": 0x0100_0001, "delete": 0x0100_0003,
      "return": 0x0100_0004, "home": 0x0100_0010, "end": 0x0100_0011,
      "left": 0x0100_0012, "up": 0x0100_0013, "right": 0x0100_0014,
      "down": 0x0100_0015, "pageup": 0x0100_0016, "pagedown": 0x0100_0017,
      "printscr": 0x0100_0009, "space": 0x20,
    ]
    var key: Int32
    if let value = special[binding.key] {
      key = value
    } else if binding.key.hasPrefix("f"), let number = Int32(binding.key.dropFirst()),
      (1...20).contains(number)
    {
      key = 0x0100_0030 + number - 1
    } else if binding.key.count == 1, let scalar = binding.key.uppercased().unicodeScalars.first,
      scalar.value < 128
    {
      key = Int32(scalar.value)
    } else {
      throw ValidationError("unsupported KDE key: \(binding.key)")
    }
    if binding.modifiers.contains(.shift) { key |= 0x0200_0000 }
    if binding.modifiers.contains(.control) { key |= 0x0400_0000 }
    if binding.modifiers.contains(.option) { key |= 0x0800_0000 }
    if binding.modifiers.contains(.command) { key |= 0x1000_0000 }
    return key
  }
}
