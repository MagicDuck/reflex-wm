import Foundation
import ReflexWMCore

#if os(Linux)
  import Glibc
#else
  import Darwin
#endif

/// KWin requires a path. Keep the embedded scripts together in a private
/// directory for the entire application lifetime, including KWin restarts.
final class TemporaryKWinScripts {
  let directory: URL
  var mainQML: URL { directory.appendingPathComponent("main.qml") }

  init(parentDirectory: URL = FileManager.default.temporaryDirectory) throws {
    var template = parentDirectory.appendingPathComponent("reflex-wm-kde-XXXXXX").path.utf8CString
    guard template.withUnsafeMutableBufferPointer({ mkdtemp($0.baseAddress!) != nil }) else {
      throw ValidationError("could not create a private temporary directory for the KWin scripts")
    }
    directory = URL(
      fileURLWithPath: template.withUnsafeBufferPointer { String(cString: $0.baseAddress!) },
      isDirectory: true)
    do {
      for (name, data) in [
        ("main.qml", EmbeddedKWinScripts.mainQML), ("windows.js", EmbeddedKWinScripts.windowsJS),
      ] {
        let file = directory.appendingPathComponent(name)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
      }
    } catch {
      try? remove()
      throw error
    }
  }

  deinit { try? remove() }

  func remove() throws {
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }
}
