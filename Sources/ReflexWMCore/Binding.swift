import Carbon
import Foundation

public struct HotKeyBinding: Hashable, Sendable {
  public let keyCode: UInt32
  public let modifiers: UInt32
  public let normalized: String

  public init(keyCode: UInt32, modifiers: UInt32, normalized: String) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.normalized = normalized
  }
}

public enum BindingParseResult: Equatable, Sendable {
  case disabled
  case binding(HotKeyBinding)
}

public enum BindingParser {
  private static let modifierCodes: [String: UInt32] = [
    "cmd": UInt32(cmdKey),
    "ctrl": UInt32(controlKey),
    "shift": UInt32(shiftKey),
    "opt": UInt32(optionKey),
  ]

  private static let keyCodes: [String: UInt32] = {
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

  private static let keyAliases: [String: String] = [
    "grave": "`", "backtick": "`",
    "minus": "-", "hyphen": "-",
    "equal": "=", "equals": "=",
    "leftbracket": "[", "left bracket": "[", "openbracket": "[", "open bracket": "[",
    "rightbracket": "]", "right bracket": "]", "closebracket": "]", "close bracket": "]",
    "backslash": "\\", "back slash": "\\",
    "semicolon": ";",
    "quote": "'", "apostrophe": "'",
    "comma": ",",
    "period": ".", "dot": ".",
    "slash": "/", "forwardslash": "/", "forward slash": "/",
  ]

  private static let builtinAliases: [String: String] = [
    "alt": "opt",
    "super": "cmd",
    "hyper": "cmd+ctrl+opt+shift",
  ]

  public static func validateAliases(_ aliases: [String: String]) throws {
    _ = try resolvedAliases(aliases)
  }

  public static func parse(
    _ value: String,
    aliases: [String: String] = [:]
  ) throws -> BindingParseResult {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return .disabled
    }

    let rawTokens = trimmed.split(separator: "+", omittingEmptySubsequences: false).map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    if rawTokens.contains(where: \.isEmpty) {
      throw ValidationError("bind contains an empty token: \(value)")
    }
    let aliases = try resolvedAliases(aliases)
    let tokens = rawTokens.flatMap { aliases[$0] ?? [$0] }

    var seenModifiers = Set<String>()
    var modifierBits: UInt32 = 0
    var key: (name: String, code: UInt32)?

    for (index, token) in tokens.enumerated() {
      if let modifier = modifierCodes[token] {
        guard seenModifiers.insert(token).inserted else {
          throw ValidationError("bind contains duplicate modifier '\(token)': \(value)")
        }
        modifierBits |= modifier
      } else if let keyCode = keyCodes[keyAliases[token] ?? token] {
        guard key == nil else {
          throw ValidationError("bind contains more than one key: \(value)")
        }
        guard index == tokens.index(before: tokens.endIndex) else {
          throw ValidationError("the key must be the last token in bind: \(value)")
        }
        key = (keyAliases[token] ?? token, keyCode)
      } else {
        throw ValidationError("bind contains unknown token '\(token)': \(value)")
      }
    }

    guard let key else {
      throw ValidationError("bind must contain a key: \(value)")
    }
    let modifierOrder = ["cmd", "ctrl", "shift", "opt"]
    let normalizedTokens = modifierOrder.filter(seenModifiers.contains) + [key.name]
    return .binding(
      HotKeyBinding(
        keyCode: key.code,
        modifiers: modifierBits,
        normalized: normalizedTokens.joined(separator: "+")
      )
    )
  }

  private static func resolvedAliases(
    _ configuredAliases: [String: String]
  ) throws -> [String: [String]] {
    var definitions = builtinAliases
    var configuredNames = Set<String>()

    for (rawName, definition) in configuredAliases {
      let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard !name.isEmpty, !name.contains("+") else {
        throw ValidationError("alias names must be non-empty and cannot contain '+': \(rawName)")
      }
      guard builtinAliases[name] == nil else {
        throw ValidationError("cannot redefine builtin alias '\(name)'")
      }
      guard modifierCodes[name] == nil, keyCodes[keyAliases[name] ?? name] == nil else {
        throw ValidationError("alias '\(name)' conflicts with a supported bind token")
      }
      guard configuredNames.insert(name).inserted else {
        throw ValidationError("duplicate alias name '\(name)'")
      }
      definitions[name] = definition
    }

    var resolved: [String: [String]] = [:]
    var resolving: [String] = []

    func resolve(_ name: String) throws -> [String] {
      if let cached = resolved[name] {
        return cached
      }
      if let cycleStart = resolving.firstIndex(of: name) {
        let cycle = (resolving[cycleStart...] + [name]).joined(separator: " -> ")
        throw ValidationError("alias cycle: \(cycle)")
      }
      guard let definition = definitions[name] else {
        return [name]
      }

      let trimmed = definition.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        throw ValidationError("alias '\(name)' has an empty definition")
      }
      let tokens = trimmed.split(separator: "+", omittingEmptySubsequences: false).map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      }
      guard !tokens.contains(where: \.isEmpty) else {
        throw ValidationError("alias '\(name)' contains an empty token")
      }

      resolving.append(name)
      var expanded: [String] = []
      for token in tokens {
        if definitions[token] != nil {
          expanded.append(contentsOf: try resolve(token))
        } else {
          expanded.append(token)
        }
      }
      resolving.removeLast()

      try validateAliasTokens(expanded, name: name)
      resolved[name] = expanded
      return expanded
    }

    for name in definitions.keys.sorted() {
      _ = try resolve(name)
    }
    return resolved
  }

  private static func validateAliasTokens(_ tokens: [String], name: String) throws {
    var seenModifiers = Set<String>()
    var sawKey = false

    for (index, token) in tokens.enumerated() {
      if modifierCodes[token] != nil {
        guard seenModifiers.insert(token).inserted else {
          throw ValidationError("alias '\(name)' contains duplicate modifier '\(token)'")
        }
      } else if keyCodes[keyAliases[token] ?? token] != nil {
        guard !sawKey else {
          throw ValidationError("alias '\(name)' contains more than one key")
        }
        guard index == tokens.index(before: tokens.endIndex) else {
          throw ValidationError("the key must be the last token in alias '\(name)'")
        }
        sawKey = true
      } else {
        throw ValidationError("alias '\(name)' contains unknown token '\(token)'")
      }
    }
  }
}
