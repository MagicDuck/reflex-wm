import Foundation
import OSLog
import UserNotifications

@MainActor
final class Notifier {
  private let logger = Logger(subsystem: "com.reflexwm.app", category: "runtime")
  var statusDidChange: ((String) -> Void)?

  func requestAuthorization() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
      [weak self] granted, error in
      Task { @MainActor in
        if let error {
          self?.logger.error("Notification authorization failed: \(error.localizedDescription)")
        } else if !granted {
          self?.logger.notice("Notification permission was not granted")
        }
      }
    }
  }

  func info(title: String, body: String) {
    logger.info("\(title, privacy: .public): \(body, privacy: .public)")
    statusDidChange?(title)
    deliver(title: title, body: body)
  }

  func warning(_ message: String) {
    logger.error("\(message, privacy: .public)")
    statusDidChange?("Warning: \(message)")
    deliver(title: "reflex-wm Warning", body: message)
  }

  func status(_ message: String) {
    logger.info("\(message, privacy: .public)")
    statusDidChange?(message)
  }

  private func deliver(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request) { [weak self] error in
      if let error {
        self?.logger.error("Notification delivery failed: \(error.localizedDescription)")
      }
    }
  }
}
