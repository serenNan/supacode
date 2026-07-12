import Darwin
import Dispatch
import Foundation

/// Watches the Todo panel's candidate todo-file locations for changes,
/// coalescing bursts of filesystem events into debounced refresh signals.
///
/// Files are watched directly via kqueue; each candidate's parent directory is
/// watched as well so a file appearing (or being atomically replaced, which
/// surfaces as rename/delete on the old inode) is picked up and the file
/// watcher re-established on the next emit.
@MainActor
final class TodoFileWatcherManager {
  private struct Watcher {
    let source: DispatchSourceFileSystemObject
  }

  private let sleep: @Sendable (Duration) async throws -> Void
  private let debounceInterval: Duration
  private var watchedURLs: [URL] = []
  private var fileWatchers: [URL: Watcher] = [:]
  private var directoryWatchers: [URL: Watcher] = [:]
  private var debounceTask: Task<Void, Never>?
  private var continuation: AsyncStream<Void>.Continuation?

  init<C: Clock<Duration>>(
    debounceInterval: Duration = .milliseconds(200),
    clock: C = ContinuousClock()
  ) {
    self.debounceInterval = debounceInterval
    self.sleep = { duration in
      try await clock.sleep(for: duration)
    }
  }

  func eventStream() -> AsyncStream<Void> {
    AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
      self.continuation = continuation
    }
  }

  func watch(urls: [URL]) {
    watchedURLs = urls.map(\.standardizedFileURL)
    resyncWatchers()
  }

  func stop() {
    debounceTask?.cancel()
    debounceTask = nil
    watchedURLs = []
    resyncWatchers()
  }

  /// Aligns live kqueue sources with `watchedURLs`: drops stale sources,
  /// watches every candidate file that exists, and every candidate's parent
  /// directory so file creation and atomic replacement are observed.
  private func resyncWatchers() {
    let desiredFiles = Set(
      watchedURLs.filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    )
    let desiredDirectories = Set(watchedURLs.map { $0.deletingLastPathComponent() })

    for (url, watcher) in fileWatchers where !desiredFiles.contains(url) {
      watcher.source.cancel()
      fileWatchers[url] = nil
    }
    for (url, watcher) in directoryWatchers where !desiredDirectories.contains(url) {
      watcher.source.cancel()
      directoryWatchers[url] = nil
    }
    for url in desiredFiles where fileWatchers[url] == nil {
      fileWatchers[url] = makeWatcher(url: url, isDirectory: false)
    }
    for url in desiredDirectories where directoryWatchers[url] == nil {
      directoryWatchers[url] = makeWatcher(url: url, isDirectory: true)
    }
  }

  private func makeWatcher(url: URL, isDirectory: Bool) -> Watcher? {
    let path = url.path(percentEncoded: false)
    let fileDescriptor = open(path, O_EVTONLY)
    guard fileDescriptor >= 0 else { return nil }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fileDescriptor,
      eventMask: [.write, .extend, .rename, .delete, .attrib],
      queue: DispatchQueue(label: "todo-file-watcher")
    )
    source.setEventHandler { @Sendable [weak self, weak source] in
      guard let source else { return }
      let event = source.data
      Task { @MainActor in
        self?.handleEvent(url: url, event: event, isDirectory: isDirectory)
      }
    }
    source.setCancelHandler { @Sendable in
      close(fileDescriptor)
    }
    source.resume()
    return Watcher(source: source)
  }

  private func handleEvent(
    url: URL,
    event: DispatchSource.FileSystemEvent,
    isDirectory: Bool
  ) {
    if !isDirectory, event.contains(.delete) || event.contains(.rename) {
      // The inode was replaced (atomic save) or removed; drop the stale
      // source now and let the post-debounce resync re-open the new file.
      fileWatchers[url]?.source.cancel()
      fileWatchers[url] = nil
    }
    scheduleEmit()
  }

  private func scheduleEmit() {
    debounceTask?.cancel()
    let sleep = self.sleep
    let interval = debounceInterval
    debounceTask = Task { [weak self, sleep] in
      try? await sleep(interval)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard let self else { return }
        self.resyncWatchers()
        self.continuation?.yield(())
      }
    }
  }
}
