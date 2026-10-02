import Foundation
import ReflexWMCore

public struct KDERegistration: Equatable, Sendable {
  public let id: String
  public let description: String
  public var keys: [Int32]
  public init(id: String, description: String, keys: [Int32]) {
    self.id = id
    self.description = description
    self.keys = keys
  }
}

public protocol ShortcutService: AnyObject {
  func assign(_ registration: KDERegistration) throws -> [Int32]
  func keys(for id: String) throws -> [Int32]
  func remove(_ id: String) throws
}

/// KGlobalAccel does not offer an atomic replace operation. Snapshot effective bindings
/// (including KDE Settings edits) and explicitly roll back if any assignment is rejected.
public final class ShortcutRegistry {
  private let service: any ShortcutService
  public private(set) var registrations: [KDERegistration] = []
  public init(service: any ShortcutService) { self.service = service }

  public func apply(_ candidate: [KDERegistration]) throws {
    let snapshot = try registrations.map {
      KDERegistration(id: $0.id, description: $0.description, keys: try service.keys(for: $0.id))
    }
    do {
      for old in registrations { try service.remove(old.id) }
      for item in candidate {
        guard try service.assign(item) == item.keys else {
          throw ValidationError(
            "shortcut '\(item.description)' was rejected; it may conflict with another application")
        }
      }
      registrations = candidate
    } catch {
      var failures: [String] = []
      for item in candidate + snapshot {
        do { try service.remove(item.id) } catch { failures.append(error.localizedDescription) }
      }
      for item in snapshot {
        do {
          if try service.assign(item) != item.keys {
            failures.append("could not restore \(item.description)")
          }
        } catch { failures.append(error.localizedDescription) }
      }
      registrations = snapshot
      if !failures.isEmpty {
        throw ValidationError(
          "\(error.localizedDescription); rollback incomplete: \(failures.joined(separator: "; "))")
      }
      throw error
    }
  }

  public func recordChange(id: String, keys: [Int32]) {
    guard let index = registrations.firstIndex(where: { $0.id == id }) else { return }
    registrations[index].keys = keys
  }

  public func recover() throws {
    for item in registrations {
      guard try service.assign(item) == item.keys else {
        throw ValidationError("could not recover shortcut '\(item.description)'")
      }
    }
  }

  public func shutdown() throws {
    var errors: [String] = []
    for item in registrations {
      do { try service.remove(item.id) } catch { errors.append(error.localizedDescription) }
    }
    registrations = []
    if !errors.isEmpty { throw ValidationError(errors.joined(separator: "; ")) }
  }
}
