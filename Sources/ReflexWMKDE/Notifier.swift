import Foundation

final class Notifier {
  let bus: DBusConnection
  init(bus: DBusConnection) { self.bus = bus }
  func log(_ message: String) {
    FileHandle.standardError.write(Data("reflex-wm: \(message)\n".utf8))
  }
  func warning(_ message: String) {
    log(message)
    info(title: "reflex-wm: Warning", body: message)
  }
  func info(title: String, body: String) {
    let escapedBody = body.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    do {
      _ = try bus.call(
        "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
        "org.freedesktop.Notifications", "Notify",
        [
          .string("reflex-wm"), .uint32(0), .string("preferences-system-windows"), .string(title),
          .string(escapedBody),
          .array("s", []), .array("{sv}", []), .int32(5000),
        ])
    } catch { log("notification unavailable: \(error.localizedDescription)") }
  }
}
