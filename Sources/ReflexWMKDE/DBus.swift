import CDBus
import Foundation
import ReflexWMCore

// libdbus's character-literal macros are not imported by Swift's Clang importer.
private enum DBusType {
  static let invalid: Int32 = 0
  static let boolean: Int32 = 98
  static let int32: Int32 = 105
  static let uint32: Int32 = 117
  static let int64: Int32 = 120
  static let string: Int32 = 115
  static let objectPath: Int32 = 111
  static let array: Int32 = 97
  static let structure: Int32 = 114
  static let variant: Int32 = 118
  static let dictEntry: Int32 = 101
}

indirect enum DBusValue: Equatable {
  case string(String)
  case path(String)
  case int32(Int32)
  case uint32(UInt32)
  case int64(Int64)
  case bool(Bool)
  case array(String, [DBusValue])
  case structure([DBusValue])
  case variant(DBusValue)
  case entry(DBusValue, DBusValue)

  var signature: String {
    switch self {
    case .string: "s"
    case .path: "o"
    case .int32: "i"
    case .uint32: "u"
    case .int64: "x"
    case .bool: "b"
    case .array(let element, _): "a" + element
    case .structure(let values): "(" + values.map(\.signature).joined() + ")"
    case .variant: "v"
    case .entry(let key, let value): "{" + key.signature + value.signature + "}"
    }
  }
  var string: String? {
    switch self {
    case .string(let value), .path(let value): value
    default: nil
    }
  }
  var elements: [DBusValue] {
    switch self {
    case .array(_, let values), .structure(let values): values
    default: []
    }
  }
  var integer: Int32? {
    if case .int32(let value) = self { return value }
    return nil
  }
}

protocol DBusCalling: AnyObject {
  func call(
    _ destination: String, _ path: String, _ interface: String, _ method: String,
    _ arguments: [DBusValue], timeout: Int32
  ) throws -> [DBusValue]
}
extension DBusCalling {
  func call(
    _ destination: String, _ path: String, _ interface: String, _ method: String,
    _ arguments: [DBusValue] = []
  ) throws -> [DBusValue] {
    try call(destination, path, interface, method, arguments, timeout: 2000)
  }
}

protocol DBusReplying: AnyObject {
  func reply(to request: OpaquePointer, _ arguments: [DBusValue]) throws
  func reject(_ request: OpaquePointer, name: String, reason: String)
}

final class DBusConnection: DBusCalling, DBusReplying {
  let raw: OpaquePointer
  init() throws {
    var error = DBusError()
    dbus_error_init(&error)
    defer { dbus_error_free(&error) }
    guard let connection = dbus_bus_get_private(DBUS_BUS_SESSION, &error) else {
      throw ValidationError(
        "could not connect to the session bus: \(error.message.map(String.init(cString:)) ?? "unknown error")"
      )
    }
    raw = connection
    dbus_connection_set_exit_on_disconnect(raw, 0)
  }
  deinit {
    dbus_connection_close(raw)
    dbus_connection_unref(raw)
  }

  func ownName(_ name: String) throws {
    var error = DBusError()
    dbus_error_init(&error)
    defer { dbus_error_free(&error) }
    let result = dbus_bus_request_name(raw, name, UInt32(DBUS_NAME_FLAG_DO_NOT_QUEUE), &error)
    guard result == DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER else {
      throw ValidationError(
        "could not own \(name); another reflex-wm instance may already be running")
    }
  }

  func addMatch(_ rule: String) throws {
    var error = DBusError()
    dbus_error_init(&error)
    defer { dbus_error_free(&error) }
    dbus_bus_add_match(raw, rule, &error)
    if dbus_error_is_set(&error) != 0 {
      throw ValidationError(
        error.message.map(String.init(cString:)) ?? "could not subscribe to D-Bus signals")
    }
  }

  func call(
    _ destination: String, _ path: String, _ interface: String, _ method: String,
    _ arguments: [DBusValue] = [], timeout: Int32 = 2000
  ) throws -> [DBusValue] {
    guard let message = dbus_message_new_method_call(destination, path, interface, method) else {
      throw ValidationError("could not allocate D-Bus message")
    }
    defer { dbus_message_unref(message) }
    try Self.append(arguments, to: message)
    var error = DBusError()
    dbus_error_init(&error)
    defer { dbus_error_free(&error) }
    guard let reply = dbus_connection_send_with_reply_and_block(raw, message, timeout, &error)
    else {
      throw ValidationError(
        "\(interface).\(method): \(error.message.map(String.init(cString:)) ?? "no reply")")
    }
    defer { dbus_message_unref(reply) }
    return try Self.decode(reply)
  }

  func reply(to request: OpaquePointer, _ arguments: [DBusValue]) throws {
    guard let reply = dbus_message_new_method_return(request) else {
      throw ValidationError("could not allocate reply")
    }
    defer { dbus_message_unref(reply) }
    try Self.append(arguments, to: reply)
    guard dbus_connection_send(raw, reply, nil) != 0 else {
      throw ValidationError("could not send reply")
    }
    dbus_connection_flush(raw)
  }

  func reject(_ request: OpaquePointer, name: String, reason: String) {
    guard let reply = dbus_message_new_error(request, name, reason) else { return }
    defer { dbus_message_unref(reply) }
    _ = dbus_connection_send(raw, reply, nil)
  }

  /// The caller owns each popped message and must unref it after handling.
  func nextMessage() -> OpaquePointer? { dbus_connection_pop_message(raw) }
  func wait(milliseconds: Int32) throws {
    guard dbus_connection_read_write(raw, milliseconds) != 0 else {
      throw ValidationError("session bus disconnected")
    }
  }

  static func append(_ arguments: [DBusValue], to message: OpaquePointer) throws {
    var iterator = DBusMessageIter()
    dbus_message_iter_init_append(message, &iterator)
    for argument in arguments { try append(argument, to: &iterator) }
  }

  private static func append(_ value: DBusValue, to iterator: inout DBusMessageIter) throws {
    var success: dbus_bool_t = 0
    switch value {
    case .string(let text), .path(let text):
      let type: Int32 = if case .path = value { DBusType.objectPath } else { DBusType.string }
      success = text.withCString { pointer in
        var pointer: UnsafePointer<CChar>? = pointer
        return dbus_message_iter_append_basic(&iterator, type, &pointer)
      }
    case .int32(var value):
      success = dbus_message_iter_append_basic(&iterator, DBusType.int32, &value)
    case .uint32(var value):
      success = dbus_message_iter_append_basic(&iterator, DBusType.uint32, &value)
    case .int64(var value):
      success = dbus_message_iter_append_basic(&iterator, DBusType.int64, &value)
    case .bool(let value):
      var integer: dbus_bool_t = value ? 1 : 0
      success = dbus_message_iter_append_basic(&iterator, DBusType.boolean, &integer)
    case .array(let signature, let values):
      try container(DBusType.array, signature: signature, values: values, iterator: &iterator)
      return
    case .structure(let values):
      try container(DBusType.structure, signature: nil, values: values, iterator: &iterator)
      return
    case .variant(let child):
      try container(
        DBusType.variant, signature: child.signature, values: [child], iterator: &iterator)
      return
    case .entry(let key, let value):
      try container(DBusType.dictEntry, signature: nil, values: [key, value], iterator: &iterator)
      return
    }
    guard success != 0 else { throw ValidationError("could not encode D-Bus argument") }
  }

  private static func container(
    _ type: Int32, signature: String?, values: [DBusValue], iterator: inout DBusMessageIter
  ) throws {
    var child = DBusMessageIter()
    let opened: dbus_bool_t
    if let signature {
      opened = signature.withCString {
        dbus_message_iter_open_container(&iterator, type, $0, &child)
      }
    } else {
      opened = dbus_message_iter_open_container(&iterator, type, nil, &child)
    }
    guard opened != 0 else { throw ValidationError("could not encode D-Bus container") }
    do {
      for value in values { try append(value, to: &child) }
    } catch {
      dbus_message_iter_abandon_container(&iterator, &child)
      throw error
    }
    guard dbus_message_iter_close_container(&iterator, &child) != 0 else {
      throw ValidationError("could not close D-Bus container")
    }
  }

  static func decode(_ message: OpaquePointer) throws -> [DBusValue] {
    var iterator = DBusMessageIter()
    guard dbus_message_iter_init(message, &iterator) != 0 else { return [] }
    return try decodeValues(&iterator)
  }
  private static func decodeValues(_ iterator: inout DBusMessageIter) throws -> [DBusValue] {
    var values: [DBusValue] = []
    repeat {
      values.append(try decodeValue(&iterator))
    } while dbus_message_iter_next(&iterator) != 0
    return values
  }
  private static func decodeValue(_ iterator: inout DBusMessageIter) throws -> DBusValue {
    let type = dbus_message_iter_get_arg_type(&iterator)
    switch type {
    case DBusType.string, DBusType.objectPath:
      var pointer: UnsafePointer<CChar>?
      dbus_message_iter_get_basic(&iterator, &pointer)
      let value = pointer.map(String.init(cString:)) ?? ""
      return type == DBusType.string ? .string(value) : .path(value)
    case DBusType.int32:
      var value: Int32 = 0
      dbus_message_iter_get_basic(&iterator, &value)
      return .int32(value)
    case DBusType.uint32:
      var value: UInt32 = 0
      dbus_message_iter_get_basic(&iterator, &value)
      return .uint32(value)
    case DBusType.int64:
      var value: Int64 = 0
      dbus_message_iter_get_basic(&iterator, &value)
      return .int64(value)
    case DBusType.boolean:
      var value: dbus_bool_t = 0
      dbus_message_iter_get_basic(&iterator, &value)
      return .bool(value != 0)
    case DBusType.array, DBusType.structure, DBusType.variant, DBusType.dictEntry:
      var child = DBusMessageIter()
      dbus_message_iter_recurse(&iterator, &child)
      let values =
        dbus_message_iter_get_arg_type(&child) == DBusType.invalid ? [] : try decodeValues(&child)
      if type == DBusType.array {
        let pointer = dbus_message_iter_get_signature(&iterator)
        defer { if let pointer { dbus_free(pointer) } }
        return .array(String((pointer.map { String(cString: $0) } ?? "a?").dropFirst()), values)
      }
      if type == DBusType.structure { return .structure(values) }
      if type == DBusType.variant, values.count == 1 { return .variant(values[0]) }
      if type == DBusType.dictEntry, values.count == 2 { return .entry(values[0], values[1]) }
      throw ValidationError("invalid D-Bus container")
    default: throw ValidationError("unsupported D-Bus type \(type)")
    }
  }
}
