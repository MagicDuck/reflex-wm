import CDBus
import Foundation
import ReflexWMKDECore
import XCTest

@testable import ReflexWMKDE

final class DBusTests: XCTestCase {
  func testMessageRoundTripPreservesKDEWireTypes() throws {
    let arguments: [DBusValue] = [
      .path("/component/reflex"), .array("s", [.string("reflex-wm"), .string("one")]),
      .array("(ai)", [.structure([.array("i", [.int32(0x1400_0045)])])]), .uint32(6),
      .array("{sv}", [.entry(.string("urgency"), .variant(.uint32(1)))]), .int64(100), .bool(true),
    ]
    let message = try XCTUnwrap(
      dbus_message_new_method_call("org.example.Test", "/test", "org.example.Test", "Test"))
    defer { dbus_message_unref(message) }
    try DBusConnection.append(arguments, to: message)
    XCTAssertEqual(try DBusConnection.decode(message), arguments)
    XCTAssertEqual(String(cString: dbus_message_get_signature(message)), "oasa(ai)ua{sv}xb")
  }
  func testEmptyShortcutAndNotificationContainers() throws {
    let message = try XCTUnwrap(dbus_message_new(DBUS_MESSAGE_TYPE_METHOD_CALL))
    defer { dbus_message_unref(message) }
    let arguments: [DBusValue] = [.array("(ai)", []), .array("s", []), .array("{sv}", [])]
    try DBusConnection.append(arguments, to: message)
    XCTAssertEqual(try DBusConnection.decode(message), arguments)
    XCTAssertEqual(try GlobalShortcuts.decodeKeys(arguments[0]), [])
  }
  func testReturnedShortcutKeysMustBeSingleChords() throws {
    XCTAssertEqual(
      try GlobalShortcuts.decodeKeys(
        .array("(ai)", [.structure([.array("i", [.int32(99), .int32(0), .int32(0), .int32(0)])])])),
      [99])
    XCTAssertThrowsError(
      try GlobalShortcuts.decodeKeys(.array("i", [.int32(99), .int32(0), .int32(0), .int32(0)])))
    XCTAssertThrowsError(
      try GlobalShortcuts.decodeKeys(
        .array("(ai)", [.structure([.array("i", [.int32(1), .int32(2), .int32(0), .int32(0)])])])))
  }
  func testQtSequencePaddingIsRequired() throws {
    XCTAssertThrowsError(
      try GlobalShortcuts.decodeKeys(.array("(ai)", [.structure([.array("i", [.int32(99)])])])))
    XCTAssertEqual(
      try GlobalShortcuts.decodeKeys(
        .array("(ai)", [.structure([.array("i", [.int32(0), .int32(0), .int32(0), .int32(0)])])])),
      [])
  }

  func testKDERegistrationUsesExplicitFlagsAndChecksReply() throws {
    let bus = RecordingBus()
    let shortcuts = GlobalShortcuts(bus: bus)
    let item = KDERegistration(id: "shortcut-1", description: "close", keys: [99])
    XCTAssertEqual(try shortcuts.assign(item), [99])
    XCTAssertEqual(bus.calls.map(\.0), ["doRegister", "setShortcutKeys"])
    XCTAssertEqual(bus.calls.last?.1.last, .uint32(6))
    XCTAssertEqual(
      bus.calls.last?.1[1],
      .array("(ai)", [.structure([.array("i", [.int32(99), .int32(0), .int32(0), .int32(0)])])]))
    XCTAssertEqual(
      bus.calls.first?.1.first,
      .array(
        "s", [.string("reflex-wm"), .string("shortcut-1"), .string("reflex-wm"), .string("close")]))
    try shortcuts.remove("shortcut-1")
    XCTAssertEqual(bus.calls.last?.0, "unregister")
    XCTAssertEqual(bus.calls.last?.1, [.string("reflex-wm"), .string("shortcut-1")])
    bus.accept = false
    XCTAssertEqual(try shortcuts.assign(item), [])
  }

  func testBridgeCorrelatesRepliesAndExpiresQueuedActions() throws {
    let bus = RecordingReplies()
    let bridge = WindowBridge(bus: bus)
    let next = try bridgeMessage("NextCommand")
    defer { dbus_message_unref(next) }
    XCTAssertTrue(bridge.handle(next))
    var completed = false
    bridge.enqueue("close") { result in
      if case .success = result { completed = true }
    }
    let json = try XCTUnwrap(bus.replies.last?.first?.string)
    let object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let id = try XCTUnwrap(object["id"] as? String)
    XCTAssertEqual(object["action"] as? String, "close")
    let complete = try bridgeMessage("CompleteCommand", [.string("{\"id\":\"\(id)\"}")])
    defer { dbus_message_unref(complete) }
    XCTAssertTrue(bridge.handle(complete))
    XCTAssertTrue(completed)
    var timedOut = false
    bridge.enqueue("close") { result in if case .failure = result { timedOut = true } }
    bridge.poll(now: Date().addingTimeInterval(6))
    XCTAssertTrue(timedOut)
    // A timed-out action must never execute when the script reconnects later.
    XCTAssertTrue(bridge.handle(next))
    bridge.poll(now: Date().addingTimeInterval(16))
    XCTAssertEqual(bus.replies.last, [.string("")])
  }

  func testBridgeRejectsForeignRepliesAndFailsOnDisconnect() throws {
    let bus = RecordingReplies()
    let bridge = WindowBridge(bus: bus)
    let next = try bridgeMessage("NextCommand")
    defer { dbus_message_unref(next) }
    _ = bridge.handle(next)
    var failure = false
    bridge.enqueue("close") { result in if case .failure = result { failure = true } }
    let foreign = try bridgeMessage("CompleteCommand", [.string("{\"id\":\"1\"}")], sender: ":1.6")
    defer { dbus_message_unref(foreign) }
    _ = bridge.handle(foreign)
    XCTAssertEqual(bus.errors.count, 1)
    XCTAssertFalse(failure)
    bridge.disconnected(sender: ":1.5")
    XCTAssertTrue(failure)
  }

  private func bridgeMessage(_ method: String, _ args: [DBusValue] = [], sender: String = ":1.5")
    throws -> OpaquePointer
  {
    let message = try XCTUnwrap(
      dbus_message_new_method_call(
        WindowBridge.service, WindowBridge.path, WindowBridge.interface, method))
    dbus_message_set_sender(message, sender)
    try DBusConnection.append(args, to: message)
    return message
  }

  func testPrivateSessionBusRoundTripAndDuplicateInstance() throws {
    guard ProcessInfo.processInfo.environment["DBUS_SESSION_BUS_ADDRESS"] != nil else {
      throw XCTSkip("run under dbus-run-session to test actual session-bus transport")
    }
    let bus = try DBusConnection()
    let id = try bus.call(
      "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetId")
    XCTAssertFalse(try XCTUnwrap(id.first?.string).isEmpty)
    try bus.ownName("org.reflexwm.TransportTest")
    let second = try DBusConnection()
    XCTAssertThrowsError(try second.ownName("org.reflexwm.TransportTest"))
  }

  func testWindowBridgeOnPrivateSessionBus() throws {
    guard ProcessInfo.processInfo.environment["DBUS_SESSION_BUS_ADDRESS"] != nil else {
      throw XCTSkip("run under dbus-run-session to exercise the real window bridge")
    }
    let server = try DBusConnection()
    try server.ownName(WindowBridge.service)
    let script = try DBusConnection()
    let bridge = WindowBridge(bus: server)
    let serial = try sendBridgeCall(script, "NextCommand")
    try handleBridgeCall(server, bridge)
    var completed = false
    bridge.enqueue("close") { result in if case .success = result { completed = true } }
    let reply = try receiveBridgeReply(script, serial)
    let json = try XCTUnwrap(reply.first?.string)
    let object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let id = try XCTUnwrap(object["id"] as? String)
    XCTAssertEqual(object["action"] as? String, "close")
    let completionSerial = try sendBridgeCall(
      script, "CompleteCommand", [.string("{\"id\":\"\(id)\"}")])
    try handleBridgeCall(server, bridge)
    XCTAssertEqual(try receiveBridgeReply(script, completionSerial), [])
    XCTAssertTrue(completed)
  }

  private func sendBridgeCall(
    _ bus: DBusConnection, _ method: String, _ arguments: [DBusValue] = []
  ) throws -> UInt32 {
    let message = try XCTUnwrap(
      dbus_message_new_method_call(
        WindowBridge.service, WindowBridge.path, WindowBridge.interface, method))
    defer { dbus_message_unref(message) }
    try DBusConnection.append(arguments, to: message)
    var serial: UInt32 = 0
    XCTAssertNotEqual(dbus_connection_send(bus.raw, message, &serial), 0)
    dbus_connection_flush(bus.raw)
    return serial
  }

  private func handleBridgeCall(_ bus: DBusConnection, _ bridge: WindowBridge) throws {
    for _ in 0..<100 {
      try bus.wait(milliseconds: 10)
      while let message = bus.nextMessage() {
        defer { dbus_message_unref(message) }
        if bridge.handle(message) { return }
      }
    }
    XCTFail("bridge did not receive method call")
  }

  private func receiveBridgeReply(_ bus: DBusConnection, _ serial: UInt32) throws -> [DBusValue] {
    for _ in 0..<100 {
      try bus.wait(milliseconds: 10)
      while let message = bus.nextMessage() {
        defer { dbus_message_unref(message) }
        if dbus_message_get_reply_serial(message) == serial {
          return try DBusConnection.decode(message)
        }
      }
    }
    XCTFail("script did not receive reply")
    return []
  }

  func testConfigurationWatcherHandlesAtomicReplacementAndDeletion() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("reflex-wm.toml")
    try Data("first".utf8).write(to: file)
    let watcher = try ConfigurationWatcher(url: file)
    let now = Date()
    try Data("second".utf8).write(to: file, options: .atomic)
    XCTAssertFalse(watcher.poll(now: now))
    XCTAssertTrue(watcher.poll(now: now.addingTimeInterval(0.3)))
    XCTAssertFalse(watcher.poll(now: now.addingTimeInterval(0.4)))
    try FileManager.default.removeItem(at: file)
    XCTAssertFalse(watcher.poll(now: now.addingTimeInterval(1)))
    XCTAssertTrue(watcher.poll(now: now.addingTimeInterval(1.3)))
  }
}

private final class RecordingBus: DBusCalling {
  var calls: [(String, [DBusValue])] = []
  var accept = true
  func call(
    _ destination: String, _ path: String, _ interface: String, _ method: String,
    _ arguments: [DBusValue], timeout: Int32
  ) throws -> [DBusValue] {
    calls.append((method, arguments))
    if method == "setShortcutKeys" {
      return [
        .array(
          "(ai)",
          accept ? [.structure([.array("i", [.int32(99), .int32(0), .int32(0), .int32(0)])])] : [])
      ]
    }
    return []
  }
}

private final class RecordingReplies: DBusReplying {
  var replies: [[DBusValue]] = []
  var errors: [String] = []
  func reply(to request: OpaquePointer, _ arguments: [DBusValue]) throws {
    replies.append(arguments)
  }
  func reject(_ request: OpaquePointer, name: String, reason: String) { errors.append(reason) }
}
