import Darwin
import Foundation

@MainActor
final class ConfigurationWatcher {
  private let directoryURL: URL
  private let callback: () -> Void
  private var source: DispatchSourceFileSystemObject?
  private var descriptor: Int32 = -1
  private var debounceWorkItem: DispatchWorkItem?

  init(directoryURL: URL, callback: @escaping () -> Void) {
    self.directoryURL = directoryURL
    self.callback = callback
  }

  func start() throws {
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    descriptor = open(directoryURL.path, O_EVTONLY)
    guard descriptor >= 0 else {
      throw RuntimeError("could not watch \(directoryURL.path)")
    }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .delete, .rename, .attrib],
      queue: .main
    )
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.scheduleReload() }
    }
    source.setCancelHandler { [descriptor] in
      if descriptor >= 0 { close(descriptor) }
    }
    self.source = source
    source.resume()
  }

  func stop() {
    debounceWorkItem?.cancel()
    source?.cancel()
    source = nil
    descriptor = -1
  }

  private func scheduleReload() {
    debounceWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated { self?.callback() }
    }
    debounceWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250), execute: item)
  }
}
