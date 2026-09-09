import Darwin
import Foundation

@MainActor
final class ConfigurationWatcher {
  private struct FileIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
  }

  private let fileURL: URL
  private let callback: () -> Void
  private var directorySource: DispatchSourceFileSystemObject?
  private var fileSource: DispatchSourceFileSystemObject?
  private var watchedFileIdentity: FileIdentity?
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
      MainActor.assumeIsolated { self?.directoryContentsDidChange() }
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
    watchedFileIdentity = nil
  }

  private func directoryContentsDidChange() {
    let identity = currentFileIdentity()
    guard identity != watchedFileIdentity else { return }
    watchedFileIdentity = identity
    scheduleReload()
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
    watchedFileIdentity = currentFileIdentity()

    let descriptor = open(fileURL.path, O_EVTONLY)
    guard descriptor >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .delete, .rename, .extend, .link, .revoke],
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

  private func currentFileIdentity() -> FileIdentity? {
    var fileStatus = stat()
    guard lstat(fileURL.path, &fileStatus) == 0 else { return nil }
    return FileIdentity(device: fileStatus.st_dev, inode: fileStatus.st_ino)
  }
}
