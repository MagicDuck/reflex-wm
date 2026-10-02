import Foundation
import ReflexWMCore

public struct DesktopEntry: Sendable {
  public let id: String
  public let url: URL
  public let name: String?
  public let hidden: Bool
}

public struct DesktopEntries: Sendable {
  public let directories: [URL]
  public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    let home = environment["HOME"] ?? NSHomeDirectory()
    let dataHome =
      environment["XDG_DATA_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil }
      ?? "\(home)/.local/share"
    let rawDirs =
      environment["XDG_DATA_DIRS"].flatMap { $0.isEmpty ? nil : $0 }
      ?? "/usr/local/share:/usr/share"
    directories =
      ([dataHome] + rawDirs.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") })
      .map {
        URL(fileURLWithPath: $0).appendingPathComponent("applications", isDirectory: true)
          .resolvingSymlinksInPath().standardizedFileURL
      }
  }
  public init(directories: [URL]) {
    self.directories = directories.map { $0.resolvingSymlinksInPath().standardizedFileURL }
  }

  public func resolve(_ value: String) throws -> DesktopEntry {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains("/"), trimmed != ".", trimmed != ".." else {
      throw ValidationError("launch_app must be a desktop entry ID, not a path or display name")
    }
    let id = trimmed.hasSuffix(".desktop") ? trimmed : trimmed + ".desktop"
    for directory in directories {
      // Nested paths become hyphenated IDs according to the Desktop Entry specification.
      let direct = directory.appendingPathComponent(id)
      if FileManager.default.fileExists(atPath: direct.path) {
        let entry = try read(direct, id: id)
        guard !entry.hidden else {
          throw ValidationError("desktop entry '\(id)' is hidden by an override")
        }
        return entry
      }
      var candidates: [URL] = []
      if let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
      {
        candidates += files.compactMap { $0 as? URL }.map {
          $0.resolvingSymlinksInPath().standardizedFileURL
        }.filter {
          $0.path.hasPrefix(directory.path + "/")
            && String($0.path.dropFirst(directory.path.count + 1)).replacingOccurrences(
              of: "/", with: "-") == id
        }.sorted { $0.path < $1.path }
      }
      for url in candidates where FileManager.default.fileExists(atPath: url.path) {
        let entry = try read(url, id: id)
        guard !entry.hidden else {
          throw ValidationError("desktop entry '\(id)' is hidden by an override")
        }
        return entry
      }
    }
    throw ValidationError("desktop entry '\(id)' was not found")
  }

  public func identifier(for value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    if value.hasPrefix("/") {
      let path = URL(fileURLWithPath: value).resolvingSymlinksInPath().path
      for directory in directories where path.hasPrefix(directory.path + "/") {
        return String(path.dropFirst(directory.path.count + 1)).replacingOccurrences(
          of: "/", with: "-")
      }
      return nil
    }
    return value.hasSuffix(".desktop") ? value : value + ".desktop"
  }

  public func displayName(for value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    if value.hasPrefix("/") { return try? read(URL(fileURLWithPath: value), id: "").name }
    return try? resolve(value).name
  }

  private func read(_ url: URL, id: String) throws -> DesktopEntry {
    let contents = try String(contentsOf: url, encoding: .utf8)
    var inEntry = false
    var values: [String: String] = [:]
    for rawLine in contents.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.hasPrefix("[") {
        inEntry = line == "[Desktop Entry]"
        continue
      }
      guard inEntry, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
        continue
      }
      values[String(line[..<separator]).trimmingCharacters(in: .whitespaces)] = String(
        line[line.index(after: separator)...])
    }
    guard values["Type"] == "Application" else {
      throw ValidationError("'\(id)' is not an Application desktop entry")
    }
    let name = values["Name"].map {
      $0.replacingOccurrences(of: "\\s", with: " ").replacingOccurrences(of: "\\n", with: "\n")
        .replacingOccurrences(of: "\\t", with: "\t").replacingOccurrences(of: "\\r", with: "\r")
        .replacingOccurrences(of: "\\\\", with: "\\")
    }
    return DesktopEntry(id: id, url: url, name: name, hidden: values["Hidden"] == "true")
  }
}
