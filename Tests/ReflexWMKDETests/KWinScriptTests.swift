import Foundation
import XCTest

@testable import ReflexWMKDE

final class KWinScriptTests: XCTestCase {
  private let file = URL(fileURLWithPath: "/data/reflex-wm/kwin/main.qml")

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

  func testReplacesCrashScriptBeforeLoading() throws {
    let bus = ScriptBus()
    bus.loaded = [KWinScript.plugin]
    bus.deferDeletion = true
    let script = KWinScript(bus: bus, file: file)
    let now = Date()
    try script.poll(now: now)
    XCTAssertEqual(bus.calls.filter { $0.method == "unloadScript" }.count, 1)
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

  func testEmbeddedScriptsExactlyMatchTheirSourceFiles() throws {
    let scripts = try TemporaryKWinScripts()
    defer { try? scripts.remove() }
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
        "Resources/kwin")
    for name in ["main.qml", "windows.js"] {
      XCTAssertEqual(
        try Data(contentsOf: scripts.directory.appendingPathComponent(name)),
        try Data(contentsOf: source.appendingPathComponent(name)))
    }
  }

  func testExtractionIsPrivateUniqueAndRemovedOnDeinit() throws {
    var first: TemporaryKWinScripts? = try TemporaryKWinScripts()
    let firstDirectory = try XCTUnwrap(first?.directory)
    let second = try TemporaryKWinScripts()
    defer { try? second.remove() }
    XCTAssertNotEqual(firstDirectory, second.directory)
    for (url, permissions) in [
      (firstDirectory, 0o700), (firstDirectory.appendingPathComponent("main.qml"), 0o600),
      (firstDirectory.appendingPathComponent("windows.js"), 0o600),
    ] {
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, permissions)
    }
    first = nil
    XCTAssertFalse(FileManager.default.fileExists(atPath: firstDirectory.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: second.mainQML.path))
  }

  func testRuntimeKeepsExtractedFilesAcrossRecoveryThenRemovesAfterUnload() throws {
    let bus = ScriptBus()
    let script = try KWinScript(bus: bus)
    let now = Date()
    try script.poll(now: now)
    try script.poll(now: now.addingTimeInterval(0.2))
    let path = try XCTUnwrap(
      bus.calls.first { $0.method == "loadDeclarativeScript" }?.arguments.first?.string)
    let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
    XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    script.ownerChanged(nil, now: now.addingTimeInterval(1))
    XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    bus.loaded = []
    script.ownerChanged(":1.20", now: now.addingTimeInterval(2))
    try script.poll(now: now.addingTimeInterval(2))
    try script.poll(now: now.addingTimeInterval(2.2))
    XCTAssertEqual(bus.calls.last?.method, "run")
    XCTAssertEqual(
      bus.calls.filter { $0.method == "loadDeclarativeScript" }.last?.arguments.first?.string, path)
    bus.onUnload = { XCTAssertTrue(FileManager.default.fileExists(atPath: path)) }
    try script.shutdown()
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    try script.shutdown()
  }

  func testExtractionReportsTemporaryDirectoryFailure() {
    let missingParent = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    XCTAssertThrowsError(try TemporaryKWinScripts(parentDirectory: missingParent))
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
  var onUnload: (() -> Void)?
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
      onUnload?()
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
