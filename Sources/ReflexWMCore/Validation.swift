import Foundation

public struct ValidatedShortcut: Equatable, Sendable {
  public let source: Shortcut
  public let binding: HotKeyBinding?
  public let effectiveMatches: [MatchCondition]

  public init(source: Shortcut, binding: HotKeyBinding?, effectiveMatches: [MatchCondition]) {
    self.source = source
    self.binding = binding
    self.effectiveMatches = effectiveMatches
  }
}

public struct ValidationError: LocalizedError, Equatable, Sendable {
  public let message: String

  public init(_ message: String) {
    self.message = message
  }

  public var errorDescription: String? { message }
}

public enum ConfigurationValidator {
  public static func validate(_ configuration: Configuration) throws -> [ValidatedShortcut] {
    try BindingParser.validateAliases(configuration.aliases)
    var seenBindings = Set<HotKeyBinding>()
    var result: [ValidatedShortcut] = []

    for (index, shortcut) in configuration.shortcuts.enumerated() {
      let parsed = try BindingParser.parse(shortcut.bind, aliases: configuration.aliases)
      let binding: HotKeyBinding?
      switch parsed {
      case .disabled:
        binding = nil
      case .binding(let value):
        guard seenBindings.insert(value).inserted else {
          throw ValidationError("shortcut \(index + 1) duplicates bind '\(value.normalized)'")
        }
        binding = value
      }

      let effectiveMatches: [MatchCondition]
      if shortcut.action == .toggleApp {
        guard let conditions = shortcut.match else {
          throw ValidationError("shortcut \(index + 1): toggle-app requires match")
        }
        guard shortcut.launchCommand == nil || shortcut.launchApplication == nil else {
          throw ValidationError(
            "shortcut \(index + 1): launch_cmd and launch_app are mutually exclusive"
          )
        }
        effectiveMatches = conditions.filter { !$0.isEmpty }
      } else {
        guard shortcut.match == nil else {
          throw ValidationError(
            "shortcut \(index + 1): match is only valid for toggle-app"
          )
        }
        guard shortcut.launchCommand == nil else {
          throw ValidationError(
            "shortcut \(index + 1): launch_cmd is only valid for toggle-app"
          )
        }
        guard shortcut.launchApplication == nil else {
          throw ValidationError(
            "shortcut \(index + 1): launch_app is only valid for toggle-app"
          )
        }
        effectiveMatches = []
      }

      result.append(
        ValidatedShortcut(
          source: shortcut,
          binding: binding,
          effectiveMatches: effectiveMatches
        )
      )
    }
    return result
  }
}
