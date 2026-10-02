import Foundation
import ReflexWMCore
import ReflexWMKDECore

final class GlobalShortcuts: ShortcutService {
  static let destination = "org.kde.kglobalaccel"
  static let path = "/kglobalaccel"
  static let interface = "org.kde.KGlobalAccel"
  static let component = "reflex-wm"
  let bus: any DBusCalling
  init(bus: any DBusCalling) { self.bus = bus }
  private func actionID(_ id: String, _ description: String = "reflex-wm") -> DBusValue {
    .array("s", [Self.component, id, "reflex-wm", description].map(DBusValue.string))
  }
  func assign(_ registration: KDERegistration) throws -> [Int32] {
    _ = try bus.call(
      Self.destination, Self.path, Self.interface, "doRegister",
      [actionID(registration.id, registration.description)])
    let reply = try bus.call(
      Self.destination, Self.path, Self.interface, "setShortcutKeys",
      [
        actionID(registration.id, registration.description),
        .array(
          "(ai)",
          registration.keys.map {
            .structure([.array("i", [.int32($0), .int32(0), .int32(0), .int32(0)])])
          }),
        // SetPresent | NoAutoloading; deliberately do not steal conflicts.
        .uint32(UInt32(2) | UInt32(4)),
      ])
    return try Self.decodeKeys(reply.first)
  }
  func keys(for id: String) throws -> [Int32] {
    let reply = try bus.call(
      Self.destination, Self.path, Self.interface, "shortcutKeys", [actionID(id)])
    return try Self.decodeKeys(reply.first)
  }
  func remove(_ id: String) throws {
    _ = try bus.call(
      Self.destination, Self.path, Self.interface, "unregister",
      [.string(Self.component), .string(id)])
  }
  func removeStaleActions() throws {
    let reply = try bus.call(Self.destination, Self.path, Self.interface, "allMainComponents")
    guard
      reply.first?.elements.contains(where: { $0.elements.first?.string == Self.component }) == true
    else { return }
    let path = try bus.call(
      Self.destination, Self.path, Self.interface, "getComponent", [.string(Self.component)]
    ).first?.string
    guard let path else { throw ValidationError("KDE returned no shortcut component path") }
    let names = try bus.call(
      Self.destination, path, "org.kde.kglobalaccel.Component", "shortcutNames")
    for name in names.first?.elements ?? [] { if let id = name.string { try remove(id) } }
  }
  static func decodeKeys(_ value: DBusValue?) throws -> [Int32] {
    guard case .array("(ai)", let sequences) = value else {
      throw ValidationError("KDE returned invalid shortcut keys")
    }
    // KDE serializes every QKeySequence as exactly four integers, padding
    // unused chord positions with zeros (kglobalshortcutinfo_dbus.cpp).
    return try sequences.compactMap { sequence in
      guard case .structure(let fields) = sequence, fields.count == 1,
        case .array("i", let keys) = fields[0], keys.count == 4,
        keys.allSatisfy({ $0.integer != nil }),
        keys.dropFirst().allSatisfy({ $0.integer == 0 })
      else {
        throw ValidationError(
          "KDE returned a multi-step or invalid shortcut; only single chords are supported")
      }
      return keys[0].integer
    }.filter { $0 != 0 }

  }
}
