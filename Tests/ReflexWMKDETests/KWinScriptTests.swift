import Foundation
import XCTest

@testable import ReflexWMKDE

final class KWinScriptTests: XCTestCase {
  private let file = URL(fileURLWithPath: "/data/kwin/scripts/reflex-wm/contents/code/main.qml")

  func testLoadsQMLAndRunsOnlyItsScriptThenUnloadsOnShutdown() throws {
    let bus = ScriptBus()
    let script = KWinScript(bus: bus, file: file)
    let now = Date()
    try script.poll(now: now)
    try script.poll(now: now.addingTimeInterval(0.2))
    XCTAssertEqual(bus.calls.filter { $0.method == "loadDeclarativeScript" }.count, 1)
    let load = try XCTUnwrap(bus.calls.first { $0.method == "loadDeclarativeScript" })
    XCTAssertEqual(load.arguments, [.string(file.path), .string(KWinScript.plugin)])
    XCTAssertEqual(load.destination, ":1.10")
    let run = try XCTUnwrap(bus.calls.first { $0.method == "run" })
    XCTAssertEqual(run.path, "/Scripting/Script7")
    XCTAssertEqual(run.interface, "org.kde.kwin.Script")
    try script.poll(now: now.addingTimeInterval(3))
    XCTAssertEqual(bus.calls.filter { $0.method == "run" }.count, 1)
    try script.shutdown()
    XCTAssertEqual(bus.calls.last?.method, "unloadScript")
    XCTAssertEqual(bus.calls.last?.arguments, [.string(KWinScript.plugin)])
  }

  func testReplacesCrashAndLegacyScriptsBeforeLoading() throws {
    let bus = ScriptBus()
    bus.loaded = ["reflex-wm", KWinScript.plugin]
    bus.deferDeletion = true
    let script = KWinScript(bus: bus, file: file)
    let now = Date()
    try script.poll(now: now)
    XCTAssertEqual(bus.calls.filter { $0.method == "unloadScript" }.count, 2)
    try script.poll(now: now.addingTimeInterval(0.2))
    XCTAssertFalse(bus.calls.contains { $0.method == "loadDeclarativeScript" })
    // Model KWin processing deleteLater before the next lifecycle attempt.
    bus.loaded = []
    try script.poll(now: now.addingTimeInterval(3))
    try script.poll(now: now.addingTimeInterval(3.2))
    XCTAssertEqual(bus.calls.filter { $0.method == "run" }.count, 1)
  }

  func testRecoversAfterOwnerReplacementAndDoesNotCleanUpOldOwner() throws {
    let bus = ScriptBus()
    let script = KWinScript(bus: bus, file: file)
    let now = Date()
    try script.poll(now: now)
    try script.poll(now: now.addingTimeInterval(0.2))
    script.ownerChanged(nil, now: now.addingTimeInterval(1))
    let before = bus.calls.count
    try script.shutdown()
    XCTAssertEqual(bus.calls.count, before)
    bus.loaded = []
    script.ownerChanged(":1.20", now: now.addingTimeInterval(2))
    try script.poll(now: now.addingTimeInterval(2))
    try script.poll(now: now.addingTimeInterval(2.2))
    XCTAssertEqual(bus.calls.filter { $0.method == "run" }.map(\.destination), [":1.10", ":1.20"])
    try script.shutdown()
    XCTAssertEqual(bus.calls.last?.destination, ":1.20")
  }

  func testRecoversExternallyUnloadedScript() throws {
    let bus = ScriptBus()
    let script = KWinScript(bus: bus, file: file)
    let now = Date()
    try script.poll(now: now)
    try script.poll(now: now.addingTimeInterval(0.2))
    bus.loaded = []
    try script.poll(now: now.addingTimeInterval(3))
    try script.poll(now: now.addingTimeInterval(3.1))
    try script.poll(now: now.addingTimeInterval(3.3))
    XCTAssertEqual(bus.calls.filter { $0.method == "run" }.count, 2)
  }

  func testRunFailureRetriesAndCanBeCleanedUp() throws {
    let bus = ScriptBus()
    bus.failRun = true
    let script = KWinScript(bus: bus, file: file)
    let now = Date()
    try script.poll(now: now)
    XCTAssertThrowsError(try script.poll(now: now.addingTimeInterval(0.2)))
    bus.failRun = false
    try script.poll(now: now.addingTimeInterval(3))
    try script.poll(now: now.addingTimeInterval(3.2))
    XCTAssertEqual(bus.calls.filter { $0.method == "run" }.count, 2)
    try script.shutdown()
    XCTAssertFalse(bus.loaded.contains(KWinScript.plugin))
  }

  func testUnavailableKWinRetriesAndInvalidLoadIsRejected() throws {
    let bus = ScriptBus()
    bus.unavailable = true
    let script = KWinScript(bus: bus, file: file)
    let now = Date()
    XCTAssertThrowsError(try script.poll(now: now))
    try script.poll(now: now.addingTimeInterval(1))
    XCTAssertEqual(bus.calls.count, 1)
    bus.unavailable = false
    try script.poll(now: now.addingTimeInterval(3))
    bus.loadID = -1
    XCTAssertThrowsError(try script.poll(now: now.addingTimeInterval(3.2)))
    XCTAssertFalse(bus.calls.contains { $0.method == "run" })
    bus.loadID = 7
    try script.poll(now: now.addingTimeInterval(6))
    XCTAssertTrue(bus.calls.contains { $0.method == "run" })
  }

  func testInstalledScriptUsesXDGDirectoriesAndReportsMissingPackage() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let user = directory.appendingPathComponent("user")
    let system = directory.appendingPathComponent("system")
    let relative = "kwin/scripts/reflex-wm/contents/code/main.qml"
    let environment = ["XDG_DATA_HOME": user.path, "XDG_DATA_DIRS": system.path]
    XCTAssertThrowsError(try KWinScript.installedScript(environment: environment))
    for root in [system, user] {
      let target = root.appendingPathComponent(relative)
      try FileManager.default.createDirectory(
        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data("test".utf8).write(to: target)
      XCTAssertEqual(try KWinScript.installedScript(environment: environment), target)
    }
  }
}

private final class ScriptBus: DBusCalling {
  struct Call {
    let destination: String
    let path: String
    let interface: String
    let method: String
    let arguments: [DBusValue]
  }
  var calls: [Call] = []
  var loaded: Set<String> = []
  var deferDeletion = false
  var failRun = false
  var unavailable = false
  var loadID: Int32 = 7
  func call(
    _ destination: String, _ path: String, _ interface: String, _ method: String,
    _ arguments: [DBusValue], timeout: Int32
  ) throws -> [DBusValue] {
    calls.append(
      Call(
        destination: destination, path: path, interface: interface, method: method,
        arguments: arguments))
    switch method {
    case "GetNameOwner":
      if unavailable { throw NSError(domain: "test", code: 1) }
      return [.string(":1.10")]
    case "isScriptLoaded": return [.bool(loaded.contains(arguments[0].string!))]
    case "unloadScript":
      if !deferDeletion { loaded.remove(arguments[0].string!) }
      return [.bool(true)]
    case "loadDeclarativeScript":
      if loadID >= 0 { loaded.insert(arguments[1].string!) }
      return [.int32(loadID)]
    case "run":
      if failRun { throw NSError(domain: "test", code: 2) }
      return []
    default: throw NSError(domain: "test", code: 3)
    }
  }
}
