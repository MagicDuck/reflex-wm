import Foundation
import ReflexWMCore
import XCTest

@testable import ReflexWMKDECore

final class KDETests: XCTestCase {
  func testQtEncodingAndAliases() throws {
    for (text, expected) in [
      ("super+alt+e", Int32(0x1800_0045)), ("ctrl+printscr", 0x0500_0009),
      ("shift+delete", 0x0300_0003), ("f20", 0x0100_0043), ("ctrl+;", 0x0400_003b),
      ("super+'", 0x1000_0027), ("hyper+'", 0x1c00_0022), ("hyper+apostrophe", 0x1c00_0022),
      ("hyper+quote", 0x1c00_0022), ("shift+'", 0x0000_0022), ("hyper+;", 0x1c00_003a),
      ("hyper+/", 0x1c00_003f), ("hyper+1", 0x1c00_0021), ("shift+equal", 0x0000_002b),
      ("hyper+a", 0x1e00_0041), ("hyper+left", 0x1f00_0012),
    ] {
      guard case .binding(let binding) = try BindingParser.parse(text) else {
        return XCTFail("missing binding")
      }
      XCTAssertEqual(try KDEBinding.encode(binding), expected, text)
    }
  }
  func testCapsLockCanBeIgnoredWithoutDisablingShortcuts() throws {
    let configuration = Configuration(
      shortcuts: [Shortcut(bind: "super+e", action: .close)],
      remap: RemapConfiguration(capsLock: "not-supported"))
    XCTAssertThrowsError(try ConfigurationValidator.validate(configuration))
    let validated = try ConfigurationValidator.validate(configuration, supportsCapsLockRemap: false)
    XCTAssertNil(validated.capsLockRemap)
    XCTAssertNotNil(validated.shortcuts[0].binding)
  }
  func testDesktopEntryResolutionOverridesAndNestedIDs() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let user = root.appendingPathComponent("user")
    let system = root.appendingPathComponent("system")
    try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: system.appendingPathComponent("tools"), withIntermediateDirectories: true)
    let text = "[Desktop Entry]\nType=Application\nName=Terminal\nExec=terminal\n"
    try text.write(
      to: system.appendingPathComponent("org.example.Terminal.desktop"), atomically: true,
      encoding: .utf8)
    try text.write(
      to: system.appendingPathComponent("tools/test.desktop"), atomically: true, encoding: .utf8)
    let entries = DesktopEntries(directories: [user, system])
    XCTAssertEqual(try entries.resolve("org.example.Terminal").id, "org.example.Terminal.desktop")
    XCTAssertEqual(try entries.resolve("org.example.Terminal.desktop").name, "Terminal")
    XCTAssertEqual(try entries.resolve("tools-test").url.lastPathComponent, "test.desktop")
    XCTAssertThrowsError(try entries.resolve("Terminal"))
    XCTAssertThrowsError(try entries.resolve("../escape"))
    XCTAssertThrowsError(try entries.resolve("missing"))
    try (text + "Hidden=true\n").write(
      to: user.appendingPathComponent("org.example.Terminal.desktop"), atomically: true,
      encoding: .utf8)
    XCTAssertThrowsError(try entries.resolve("org.example.Terminal"))
  }
  func testRegistrationReplacementAndDeletion() throws {
    let service = FakeService()
    let registry = ShortcutRegistry(service: service)
    try registry.apply([item("one", 1), item("two", 2)])
    try registry.apply([item("one", 3)])
    XCTAssertEqual(service.values, ["one": [3]])
    try registry.shutdown()
    XCTAssertTrue(service.values.isEmpty)
  }
  func testConflictRollsBackEffectiveDesktopEdits() throws {
    let service = FakeService()
    let registry = ShortcutRegistry(service: service)
    try registry.apply([item("one", 1)])
    service.values["one"] = [9]  // user edited binding in KDE Settings
    service.rejected = 2
    XCTAssertThrowsError(try registry.apply([item("two", 2)]))
    XCTAssertEqual(service.values, ["one": [9]])
    XCTAssertEqual(registry.registrations.first?.keys, [9])
  }
  func testRecoveryUsesLastDesktopBinding() throws {
    let service = FakeService()
    let registry = ShortcutRegistry(service: service)
    try registry.apply([item("one", 1)])
    registry.recordChange(id: "one", keys: [8])
    service.values.removeAll()
    try registry.recover()
    XCTAssertEqual(service.values, ["one": [8]])
  }
  func testRegistrationFailureReportsIncompleteRollback() throws {
    let service = FakeService()
    let registry = ShortcutRegistry(service: service)
    try registry.apply([item("one", 1)])
    service.rejected = 1
    service.throwOnAssign = "two"
    XCTAssertThrowsError(try registry.apply([item("two", 2)])) { error in
      XCTAssertTrue(error.localizedDescription.contains("rollback incomplete"))
    }
  }
  private func item(_ id: String, _ key: Int32) -> KDERegistration {
    KDERegistration(id: id, description: id, keys: [key])
  }
}
private final class FakeService: ShortcutService {
  var values: [String: [Int32]] = [:]
  var rejected: Int32?
  var throwOnAssign: String?
  func assign(_ registration: KDERegistration) throws -> [Int32] {
    if registration.id == throwOnAssign { throw ValidationError("service unavailable") }
    let accepted = registration.keys.filter { $0 != rejected }
    values[registration.id] = accepted
    return accepted
  }
  func keys(for id: String) throws -> [Int32] { values[id] ?? [] }
  func remove(_ id: String) throws { values.removeValue(forKey: id) }
}
