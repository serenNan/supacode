import Foundation
import Testing

@testable import supacode

struct TodoFileWriterTests {
  @Test func togglesOnlyTheTargetLine() throws {
    let content = "## H\n- [ ] one\n- [ ] two\nprose\n"
    let result = try TodoFileWriter.togglingContent(content, lineIndex: 2, expecting: "- [ ] two")
    #expect(result == "## H\n- [ ] one\n- [x] two\nprose\n")
  }

  @Test func throwsConflictWhenLineChangedOnDisk() {
    let content = "- [ ] rewritten by someone else"
    #expect(throws: TodoFileConflictError.self) {
      try TodoFileWriter.togglingContent(content, lineIndex: 0, expecting: "- [ ] original")
    }
  }

  @Test func throwsConflictWhenIndexOutOfBounds() {
    #expect(throws: TodoFileConflictError.self) {
      try TodoFileWriter.togglingContent("- [ ] only", lineIndex: 5, expecting: "- [ ] only")
    }
  }

  @Test func throwsConflictWhenTargetIsNotATaskLine() {
    #expect(throws: TodoFileConflictError.self) {
      try TodoFileWriter.togglingContent("prose line", lineIndex: 0, expecting: "prose line")
    }
  }

  @Test func preservesCarriageReturnsAndTrailingNewline() throws {
    let content = "- [ ] crlf task\r\n- [ ] second\r\n"
    let result = try TodoFileWriter.togglingContent(content, lineIndex: 0, expecting: "- [ ] crlf task\r")
    #expect(result == "- [x] crlf task\r\n- [ ] second\r\n")
  }

  @Test func toggleLineRewritesTheFileOnDisk() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("todo-writer-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("TODO.md")
    try "## H\n- [ ] disk task\n".write(to: url, atomically: true, encoding: .utf8)

    try TodoFileWriter.toggleLine(at: url, lineIndex: 1, expecting: "- [ ] disk task")

    #expect(try String(contentsOf: url, encoding: .utf8) == "## H\n- [x] disk task\n")
  }
}
