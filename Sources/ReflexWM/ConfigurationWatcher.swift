import Darwin
import Foundation

@MainActor
final class ConfigurationWatcher {
  private let fileURL: URL
  private let callback: () -> Void
  private var directorySource: DispatchSourceFileSystemObject?
  private var fileSource: DispatchSourceFileSystemObject?
  private var debounceWorkItem: DispatchWorkItem?

  init(fileURL: URL, callback: @escaping () -> Void) {
    self.fileURL = fileURL
    self.callback = callback
  }

  func start() throws {
    let directoryURL = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    let descriptor = open(directoryURL.path, O_EVTONLY)
    guard descriptor >= 0 else {
      throw RuntimeError("could not watch \(directoryURL.path)")
    }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .delete, .rename, .attrib, .revoke],
      queue: .main
    )
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.scheduleReload() }
    }
    source.setCancelHandler { [descriptor] in
      if descriptor >= 0 { close(descriptor) }
    }
    directorySource = source
    source.resume()
    replaceFileWatcher()
  }

  func stop() {
    debounceWorkItem?.cancel()
    debounceWorkItem = nil
    fileSource?.cancel()
    fileSource = nil
    directorySource?.cancel()
    directorySource = nil
  }

  private func scheduleReload() {
    debounceWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        self?.replaceFileWatcher()
        self?.callback()
      }
    }
    debounceWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250), execute: item)
  }

  private func replaceFileWatcher() {
    fileSource?.cancel()
    fileSource = nil

    let descriptor = open(fileURL.path, O_EVTONLY)
    guard descriptor >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
      queue: .main
    )
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.scheduleReload() }
    }
    source.setCancelHandler { [descriptor] in
      if descriptor >= 0 { close(descriptor) }
    }
    fileSource = source
    source.resume()
  }
}
