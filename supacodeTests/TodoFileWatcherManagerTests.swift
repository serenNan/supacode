import Clocks
import Foundation
import Testing

@testable import supacode

@MainActor
struct TodoFileWatcherManagerTests {
  @Test func coalescesBurstOfWritesIntoOneEvent() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let clock = TestClock()
    let manager = TodoFileWatcherManager(clock: clock)
    let (counter, task) = Self.collect(manager.eventStream())

    manager.watch(urls: [fixture.fileURL])
    try fixture.append("- [ ] one\n")
    try fixture.append("- [ ] two\n")
    await Self.drain()
    await clock.advance(by: .milliseconds(200))
    await Self.drain()

    #expect(await counter.count == 1)
    manager.stop()
    task.cancel()
  }

  @Test func survivesAtomicReplaceAndKeepsEmitting() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let clock = TestClock()
    let manager = TodoFileWatcherManager(clock: clock)
    let (counter, task) = Self.collect(manager.eventStream())

    manager.watch(urls: [fixture.fileURL])
    try "- [x] replaced\n".write(to: fixture.fileURL, atomically: true, encoding: .utf8)
    await Self.drain()
    await clock.advance(by: .milliseconds(400))
    await Self.drain()
    let afterReplace = await counter.count
    #expect(afterReplace >= 1)

    try fixture.append("- [ ] after replace\n")
    await Self.drain()
    await clock.advance(by: .milliseconds(400))
    await Self.drain()
    #expect(await counter.count > afterReplace)

    manager.stop()
    task.cancel()
  }

  @Test func emitsWhenWatchedFileAppears() async throws {
    let fixture = try Fixture(createFile: false)
    defer { fixture.cleanUp() }
    let clock = TestClock()
    let manager = TodoFileWatcherManager(clock: clock)
    let (counter, task) = Self.collect(manager.eventStream())

    manager.watch(urls: [fixture.fileURL])
    try "- [ ] born\n".write(to: fixture.fileURL, atomically: true, encoding: .utf8)
    await Self.drain()
    await clock.advance(by: .milliseconds(200))
    await Self.drain()

    #expect(await counter.count == 1)
    manager.stop()
    task.cancel()
  }

  @Test func stopTearsDownAllWatchers() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let clock = TestClock()
    let manager = TodoFileWatcherManager(clock: clock)
    let (counter, task) = Self.collect(manager.eventStream())

    manager.watch(urls: [fixture.fileURL])
    try fixture.append("- [ ] before stop\n")
    await Self.drain()
    await clock.advance(by: .milliseconds(200))
    await Self.drain()
    #expect(await counter.count == 1)

    manager.stop()
    try fixture.append("- [ ] after stop\n")
    await Self.drain()
    await clock.advance(by: .milliseconds(400))
    await Self.drain()
    #expect(await counter.count == 1)

    task.cancel()
  }

  private static func collect(_ stream: AsyncStream<Void>) -> (Counter, Task<Void, Never>) {
    let counter = Counter()
    let task = Task {
      for await _ in stream {
        if Task.isCancelled { break }
        await counter.increment()
      }
    }
    return (counter, task)
  }

  private static func drain(_ iterations: Int = 120) async {
    for _ in 0..<iterations {
      await Task.yield()
    }
  }
}

private actor Counter {
  var count = 0
  func increment() { count += 1 }
}

private struct Fixture {
  let directory: URL
  let fileURL: URL

  init(createFile: Bool = true) throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("todo-watcher-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    fileURL = directory.appendingPathComponent("TODO.md")
    if createFile {
      try "## Seed\n".write(to: fileURL, atomically: true, encoding: .utf8)
    }
  }

  func append(_ text: String) throws {
    let handle = try FileHandle(forWritingTo: fileURL)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
  }

  func cleanUp() {
    try? FileManager.default.removeItem(at: directory)
  }
}
