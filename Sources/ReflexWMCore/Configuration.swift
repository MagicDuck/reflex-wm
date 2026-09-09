import Foundation
import TOML

public struct Configuration: Decodable, Equatable, Sendable {
  public let shortcuts: [Shortcut]
  public let aliases: [String: String]
  public let remap: RemapConfiguration?

  enum CodingKeys: String, CodingKey {
    case shortcuts = "shortcut"
    case aliases
    case remap
  }

  public init(
    shortcuts: [Shortcut],
    aliases: [String: String] = [:],
    remap: RemapConfiguration? = nil
  ) {
    self.shortcuts = shortcuts
    self.aliases = aliases
    self.remap = remap
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    shortcuts = try container.decodeIfPresent([Shortcut].self, forKey: .shortcuts) ?? []
    aliases = try container.decodeIfPresent([String: String].self, forKey: .aliases) ?? [:]
    remap = try container.decodeIfPresent(RemapConfiguration.self, forKey: .remap)
  }
}

public struct RemapConfiguration: Decodable, Equatable, Sendable {
  public let capsLock: String?

  public init(capsLock: String? = nil) {
    self.capsLock = capsLock
  }

  private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
      self.stringValue = stringValue
    }

    init?(intValue: Int) {
      return nil
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: DynamicCodingKey.self)
    for key in container.allKeys where key.stringValue != "caps_lock" {
      throw DecodingError.dataCorruptedError(
        forKey: key,
        in: container,
        debugDescription: "unsupported remap key '\(key.stringValue)'"
      )
    }
    guard let capsLockKey = DynamicCodingKey(stringValue: "caps_lock") else {
      preconditionFailure("caps_lock is a valid coding key")
    }
    capsLock = try container.decodeIfPresent(String.self, forKey: capsLockKey)
  }
}

public struct Shortcut: Decodable, Equatable, Sendable {
  public let bind: String
  public let action: ShortcutAction
  public let launchCommand: String?
  public let launchApplication: String?
  public let match: [MatchCondition]?

  enum CodingKeys: String, CodingKey {
    case bind
    case action
    case launchCommand = "launch_cmd"
    case launchApplication = "launch_app"
    case match
  }

  public init(
    bind: String,
    action: ShortcutAction,
    launchCommand: String? = nil,
    launchApplication: String? = nil,
    match: [MatchCondition]? = nil
  ) {
    self.bind = bind
    self.action = action
    self.launchCommand = launchCommand
    self.launchApplication = launchApplication
    self.match = match
  }
}

public enum ShortcutAction: String, Decodable, CaseIterable, Sendable {
  case toggleApp = "toggle-app"
  case toggleMaximize = "toggle-maximize"
  case close
  case moveToNextScreen = "move-to-next-screen"
  case notifyWindowInfo = "notify-win-info"
  case focusNextAppWindow = "focus-next-app-window"
  case toggleVerticalSplit = "toggle-vertical-split"
}

public struct MatchCondition: Decodable, Equatable, Sendable {
  public let appID: String?
  public let appName: String?
  public let windowTitle: String?

  enum CodingKeys: String, CodingKey {
    case appID = "app_id"
    case appName = "app_name"
    case windowTitle = "win_title"
  }

  public init(appID: String? = nil, appName: String? = nil, windowTitle: String? = nil) {
    self.appID = appID
    self.appName = appName
    self.windowTitle = windowTitle
  }

  public var isEmpty: Bool {
    appID == nil && appName == nil && windowTitle == nil
  }

  public func matches(_ candidate: WindowMetadata) -> Bool {
    guard matchesApplication(candidate) else { return false }
    if let windowTitle {
      guard let candidateTitle = candidate.windowTitle,
        equalIgnoringCase(candidateTitle, windowTitle)
      else { return false }
    }
    return true
  }

  public func matchesApplication(_ candidate: WindowMetadata) -> Bool {
    if let appID, candidate.appID != appID {
      return false
    }
    if let appName {
      let matchesName = candidate.appName.map { equalIgnoringCase($0, appName) } ?? false
      let matchesExecutable =
        candidate.executableName.map {
          equalIgnoringCase($0, appName)
        } ?? false
      if !matchesName && !matchesExecutable {
        return false
      }
    }
    return true
  }

  private func equalIgnoringCase(_ lhs: String, _ rhs: String) -> Bool {
    let locale = Locale(identifier: "en_US_POSIX")
    return lhs.folding(options: [.caseInsensitive], locale: locale)
      == rhs.folding(options: [.caseInsensitive], locale: locale)
  }
}

public struct WindowMetadata: Equatable, Sendable {
  public let appID: String?
  public let appName: String?
  public let executableName: String?
  public let windowTitle: String?

  public init(
    appID: String?,
    appName: String?,
    executableName: String?,
    windowTitle: String?
  ) {
    self.appID = appID
    self.appName = appName
    self.executableName = executableName
    self.windowTitle = windowTitle
  }
}

public enum ConfigurationLoader {
  public static func decode(_ contents: String) throws -> Configuration {
    try TOMLDecoder().decode(Configuration.self, from: contents)
  }
}
