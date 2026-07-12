import ComposableArchitecture
import Foundation

/// File IO and change watching for the Todo panel's markdown checklists.
struct TodoFileClient: Sendable {
  /// Returns the file's contents, or `nil` when it doesn't exist or is unreadable.
  var read: @Sendable (URL) async -> String?
  /// Flips one task line's checkbox, verifying the line is unchanged on disk first.
  /// Throws `TodoFileConflictError` when the file changed under the panel.
  var toggleLine: @Sendable (_ url: URL, _ lineIndex: Int, _ rawLine: String) async throws -> Void
  /// Re-targets the watcher to these candidate locations.
  var watch: @MainActor @Sendable (_ urls: [URL]) -> Void
  /// Debounced change signals for the watched locations.
  var events: @MainActor @Sendable () -> AsyncStream<Void>
  /// Tears down all watchers.
  var stopWatching: @MainActor @Sendable () -> Void
}

extension TodoFileClient: DependencyKey {
  static let liveValue = TodoFileClient(
    read: { url in
      try? String(contentsOf: url, encoding: .utf8)
    },
    toggleLine: { url, lineIndex, rawLine in
      try TodoFileWriter.toggleLine(at: url, lineIndex: lineIndex, expecting: rawLine)
    },
    watch: { _ in fatalError("TodoFileClient.watch not configured") },
    events: { fatalError("TodoFileClient.events not configured") },
    stopWatching: { fatalError("TodoFileClient.stopWatching not configured") }
  )

  static let testValue = TodoFileClient(
    read: { _ in nil },
    toggleLine: { _, _, _ in },
    watch: { _ in },
    events: { AsyncStream { $0.finish() } },
    stopWatching: {}
  )

  /// Live wiring bound to a long-lived manager owned by the app entry point.
  @MainActor
  static func live(manager: TodoFileWatcherManager) -> TodoFileClient {
    var client = liveValue
    client.watch = { urls in manager.watch(urls: urls) }
    client.events = { manager.eventStream() }
    client.stopWatching = { manager.stop() }
    return client
  }
}

extension DependencyValues {
  var todoFile: TodoFileClient {
    get { self[TodoFileClient.self] }
    set { self[TodoFileClient.self] = newValue }
  }
}
