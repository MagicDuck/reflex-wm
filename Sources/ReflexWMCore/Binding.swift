import Foundation

public struct BindingModifiers: OptionSet, Hashable, Sendable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  public static let command = Self(rawValue: 1)
  public static let control = Self(rawValue: 2)
  public static let shift = Self(rawValue: 4)
  public static let option = Self(rawValue: 8)
}

public struct HotKeyBinding: Hashable, Sendable {
  public let key: String
  public let modifiers: BindingModifiers
  public let normalized: String

  public init(key: String, modifiers: BindingModifiers, normalized: String) {
    self.key = key
    self.modifiers = modifiers
    self.normalized = normalized
  }
}

public struct ModifierBinding: Hashable, Sendable {
  public let modifiers: BindingModifiers
  public let normalized: String
  public init(modifiers: BindingModifiers, normalized: String) {
    self.modifiers = modifiers
    self.normalized = normalized
  }
}

public enum BindingParseResult: Equatable, Sendable {
  case disabled
  case binding(HotKeyBinding)
}

public enum BindingParser {
  private static let modifierCodes: [String: BindingModifiers] = [
    "cmd": .command, "ctrl": .control, "shift": .shift, "opt": .option,
  ]
  private static let supportedKeys = Set(
    Array("abcdefghijklmnopqrstuvwxyz0123456789`-=[]\\;'.,/").map(String.init)
      + (1...20).map { "f\($0)" }
      + [
        "return", "tab", "space", "escape", "delete", "home", "end", "pageup",
        "pagedown", "left", "right", "up", "down", "printscr",
      ]
  )

  private static let keyAliases: [String: String] = [
    "page up": "pageup", "page down": "pagedown",
    "arrowleft": "left", "arrowright": "right", "arrowup": "up", "arrowdown": "down",
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
    var modifierBits: BindingModifiers = []
    var key: String?

    for (index, token) in tokens.enumerated() {
      if let modifier = modifierCodes[token] {
        guard seenModifiers.insert(token).inserted else {
          throw ValidationError("bind contains duplicate modifier '\(token)': \(value)")
        }
        modifierBits.formUnion(modifier)
      } else if supportedKeys.contains(keyAliases[token] ?? token) {
        guard key == nil else {
          throw ValidationError("bind contains more than one key: \(value)")
        }
        guard index == tokens.index(before: tokens.endIndex) else {
          throw ValidationError("the key must be the last token in bind: \(value)")
        }
        key = keyAliases[token] ?? token
      } else {
        throw ValidationError("bind contains unknown token '\(token)': \(value)")
      }
    }

    guard let key else {
      throw ValidationError("bind must contain a key: \(value)")
    }
    let modifierOrder = ["cmd", "ctrl", "shift", "opt"]
    let normalizedTokens = modifierOrder.filter(seenModifiers.contains) + [key]
    return .binding(
      HotKeyBinding(
        key: key,
        modifiers: modifierBits,
        normalized: normalizedTokens.joined(separator: "+")
      )
    )
  }

  public static func parseModifiers(
    _ value: String,
    aliases: [String: String] = [:]
  ) throws -> ModifierBinding {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw ValidationError("modifier expression must not be empty")
    }

    let rawTokens = trimmed.split(separator: "+", omittingEmptySubsequences: false).map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    guard !rawTokens.contains(where: \.isEmpty) else {
      throw ValidationError("modifier expression contains an empty token: \(value)")
    }

    let aliases = try resolvedAliases(aliases)
    let tokens = rawTokens.flatMap { aliases[$0] ?? [$0] }
    var seenModifiers = Set<String>()
    var modifierBits: BindingModifiers = []

    for token in tokens {
      guard let modifier = modifierCodes[token] else {
        throw ValidationError("modifier expression contains non-modifier '\(token)': \(value)")
      }
      guard seenModifiers.insert(token).inserted else {
        throw ValidationError(
          "modifier expression contains duplicate modifier '\(token)': \(value)"
        )
      }
      modifierBits.formUnion(modifier)
    }

    let modifierOrder = ["cmd", "ctrl", "shift", "opt"]
    let normalized = modifierOrder.filter(seenModifiers.contains).joined(separator: "+")
    return ModifierBinding(modifiers: modifierBits, normalized: normalized)
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
      guard modifierCodes[name] == nil, !supportedKeys.contains(keyAliases[name] ?? name) else {
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
      } else if supportedKeys.contains(keyAliases[token] ?? token) {
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
