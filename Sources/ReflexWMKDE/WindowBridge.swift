import CDBus
import Foundation
import ReflexWMCore

/// KWin's scripting API can issue asynchronous D-Bus calls but does not expose a
/// custom D-Bus server. The resident QML script long-polls this queue instead.
final class WindowBridge {
  static let service = "org.reflexwm.ReflexWM"
  static let path = "/org/reflexwm/ReflexWM"
  static let interface = "org.reflexwm.ReflexWM"
  private let bus: any DBusReplying
  private var waiting: OpaquePointer?
  private var waitingSince = Date.distantPast
  private var scriptSender: String?
  private var nextID: UInt64 = 1
  private var queue: [(String, String)] = []
  private var pending: [String: (Date, (Result<[String: Any], Error>) -> Void)] = [:]

  init(bus: any DBusReplying) { self.bus = bus }
  deinit { if let waiting { dbus_message_unref(waiting) } }

  func enqueue(
    _ action: String, fields: [String: Any] = [:],
    completion: @escaping (Result<[String: Any], Error>) -> Void
  ) {
    guard pending.count < 64 else {
      completion(.failure(ValidationError("too many pending window actions")))
      return
    }
    let id = String(nextID)
    nextID &+= 1
    var object = fields
    object["id"] = id
    object["action"] = action
    object["version"] = 1
    do {
      let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
      let json = String(decoding: data, as: UTF8.self)
      pending[id] = (Date().addingTimeInterval(5), completion)
      queue.append((id, json))
      deliver()
    } catch { completion(.failure(error)) }
  }

  func handle(_ message: OpaquePointer) -> Bool {
    guard dbus_message_get_type(message) == DBUS_MESSAGE_TYPE_METHOD_CALL,
      dbus_message_get_path(message).map(String.init(cString:)) == Self.path
    else { return false }
    let interface = dbus_message_get_interface(message).map(String.init(cString:)) ?? ""
    let member = dbus_message_get_member(message).map(String.init(cString:)) ?? ""
    if interface == "org.freedesktop.DBus.Introspectable", member == "Introspect" {
      try? bus.reply(to: message, [.string(Self.introspection)])
      return true
    }
    guard interface == Self.interface else {
      bus.reject(
        message, name: "org.freedesktop.DBus.Error.UnknownInterface", reason: "unknown interface")
      return true
    }
    let sender = dbus_message_get_sender(message).map(String.init(cString:)) ?? ""
    do {
      switch member {
      case "NextCommand":
        guard try DBusConnection.decode(message).isEmpty else {
          throw ValidationError("NextCommand takes no arguments")
        }
        if let waiting {
          try bus.reply(to: waiting, [.string("")])
          dbus_message_unref(waiting)
          self.waiting = nil
        }
        if scriptSender != sender {
          scriptSender = sender
          failPending("KWin script connected or restarted; retry the action")
        }
        waiting = dbus_message_ref(message)
        waitingSince = Date()
        deliver()
      case "CompleteCommand":
        guard sender == scriptSender else {
          throw ValidationError("response is not from the connected KWin script")
        }
        let args = try DBusConnection.decode(message)
        guard args.count == 1, let json = args[0].string,
          let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
          let id = object["id"] as? String
        else { throw ValidationError("invalid command result") }
        try bus.reply(to: message, [])
        if let (_, completion) = pending.removeValue(forKey: id) {
          if let error = object["error"] as? String {
            completion(.failure(ValidationError(error)))
          } else {
            completion(.success(object))
          }
        }
      default:
        bus.reject(
          message, name: "org.freedesktop.DBus.Error.UnknownMethod", reason: "unknown method")
      }
    } catch {
      bus.reject(
        message, name: "org.freedesktop.DBus.Error.InvalidArgs", reason: error.localizedDescription)
    }
    return true
  }

  func poll(now: Date = Date()) {
    if waiting != nil, now.timeIntervalSince(waitingSince) >= 15 { deliver(heartbeat: true) }
    let expired = pending.filter { $0.value.0 <= now }.map(\.key)
    for id in expired {
      guard let (_, completion) = pending.removeValue(forKey: id) else { continue }
      queue.removeAll { $0.0 == id }
      completion(
        .failure(
          ValidationError(
            "KWin action timed out; check reflex-wm's KWin script startup/recovery logs")))
    }
  }
  func disconnected(sender: String) {
    guard sender == scriptSender else { return }
    scriptSender = nil
    if let waiting {
      dbus_message_unref(waiting)
      self.waiting = nil
    }
    failPending("KWin disconnected; retry after it restarts")
  }
  private func failPending(_ reason: String) {
    let callbacks = Array(pending.values)
    pending = [:]
    queue = []
    for (_, callback) in callbacks { callback(.failure(ValidationError(reason))) }
  }
  private func deliver(heartbeat: Bool = false) {
    guard let request = waiting, !queue.isEmpty || heartbeat else { return }
    let next = queue.first
    do {
      try bus.reply(to: request, [.string(next?.1 ?? "")])
      if next != nil { queue.removeFirst() }
    } catch { failPending(error.localizedDescription) }
    dbus_message_unref(request)
    waiting = nil
  }
  static let introspection = """
    <node><interface name="org.reflexwm.ReflexWM">
    <method name="NextCommand"><arg type="s" direction="out"/></method>
    <method name="CompleteCommand"><arg type="s" direction="in"/></method>
    </interface></node>
    """
}
