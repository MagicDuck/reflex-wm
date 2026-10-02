import CDBus
import Foundation

#if os(Linux)
  import Glibc
#else
  import Darwin
#endif

final class ConfigurationWatcher {
  private let url: URL
  private var lastContents: Data?
  private var lastProbe = Date.distantPast
  private var changedAt: Date?
  #if os(Linux)
    private let descriptor: Int32
  #endif
  init(url: URL) throws {
    self.url = url
    lastContents = try? Data(contentsOf: url)
    #if os(Linux)
      descriptor = inotify_init1(Int32(IN_NONBLOCK | IN_CLOEXEC))
      guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
      if inotify_add_watch(
        descriptor, url.deletingLastPathComponent().path,
        UInt32(
          IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE | IN_DELETE | IN_ATTRIB | IN_MOVE_SELF
            | IN_DELETE_SELF)) < 0
      {
        close(descriptor)
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
    #endif
  }
  deinit {
    #if os(Linux)
      close(descriptor)
    #endif
  }
  func poll(now: Date = Date()) -> Bool {
    var event = false
    #if os(Linux)
      var buffer = [UInt8](repeating: 0, count: 16384)
      event = read(descriptor, &buffer, buffer.count) > 0
    #endif
    // Also probe periodically: directory replacement or lost inotify events must not
    // leave the program permanently watching an obsolete inode.
    if event || now.timeIntervalSince(lastProbe) >= 0.5 {
      lastProbe = now
      let contents = try? Data(contentsOf: url)
      if contents != lastContents {
        lastContents = contents
        changedAt = now
      }
    }
    if let changedAt, now.timeIntervalSince(changedAt) >= 0.25 {
      self.changedAt = nil
      return true
    }
    return false
  }
}

final class SignalMonitor {
  private var mask = sigset_t()
  init() {
    sigemptyset(&mask)
    for value in [SIGINT, SIGTERM, SIGHUP] { sigaddset(&mask, value) }
    // Block before creating Process worker threads so they inherit this mask.
    _ = pthread_sigmask(SIG_BLOCK, &mask, nil)
  }
  func poll() -> Int32? {
    var pending = sigset_t()
    sigpending(&pending)
    guard [SIGINT, SIGTERM, SIGHUP].contains(where: { sigismember(&pending, $0) == 1 }) else {
      return nil
    }
    var value: Int32 = 0
    return sigwait(&mask, &value) == 0 ? value : nil
  }
}
