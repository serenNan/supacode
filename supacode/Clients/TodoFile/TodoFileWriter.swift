import Foundation

/// The displayed file changed on disk after the panel last read it; the
/// targeted line no longer matches, so the toggle must not be applied.
nonisolated struct TodoFileConflictError: Error, Equatable {}

/// Conflict-checked checkbox write-back for the Todo panel.
nonisolated enum TodoFileWriter {
  static func togglingContent(
    _ content: String, lineIndex: Int, expecting rawLine: String
  ) throws -> String {
    var lines = content.components(separatedBy: "\n")
    guard lines.indices.contains(lineIndex), lines[lineIndex] == rawLine else {
      throw TodoFileConflictError()
    }
    guard let toggled = TodoChecklist.toggling(line: rawLine) else {
      throw TodoFileConflictError()
    }
    lines[lineIndex] = toggled
    return lines.joined(separator: "\n")
  }

  static func toggleLine(at url: URL, lineIndex: Int, expecting rawLine: String) throws {
    let content = try String(contentsOf: url, encoding: .utf8)
    let updated = try togglingContent(content, lineIndex: lineIndex, expecting: rawLine)
    try updated.write(to: url, atomically: true, encoding: .utf8)
  }
}
