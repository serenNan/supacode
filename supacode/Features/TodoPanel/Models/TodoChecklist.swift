import Foundation

/// Parses GitHub-flavored markdown task lists for the Todo panel.
/// Only unchecked items are surfaced; everything else in the file is
/// display-irrelevant but must be preserved by writers.
nonisolated enum TodoChecklist {
  struct Item: Equatable, Hashable, Sendable {
    var text: String
    var lineIndex: Int
    var rawLine: String
  }

  struct Section: Equatable, Hashable, Sendable {
    var title: String?
    var items: [Item]
  }

  static func parse(_ text: String) -> [Section] {
    var sections: [Section] = []
    var currentTitle: String?
    var currentItems: [Item] = []

    func flush() {
      if !currentItems.isEmpty {
        sections.append(Section(title: currentTitle, items: currentItems))
        currentItems = []
      }
    }

    for (index, line) in text.components(separatedBy: "\n").enumerated() {
      if let heading = headingTitle(of: line) {
        flush()
        currentTitle = heading
      } else if let text = uncheckedItemText(of: line) {
        currentItems.append(Item(text: text, lineIndex: index, rawLine: line))
      }
    }
    flush()
    return sections
  }

  private static func headingTitle(of line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("#") else { return nil }
    let afterHashes = trimmed.drop(while: { $0 == "#" })
    guard afterHashes.isEmpty || afterHashes.hasPrefix(" ") else { return nil }
    return afterHashes.trimmingCharacters(in: .whitespaces)
  }

  /// Flips the checkbox marker of a task line (`[ ]` ↔ `[x]`), leaving every
  /// other byte untouched. Returns `nil` when the line is not a task item.
  static func toggling(line: String) -> String? {
    guard let marker = taskMarker(of: line) else { return nil }
    var toggled = line
    toggled.replaceSubrange(
      marker.stateIndex...marker.stateIndex,
      with: marker.state == " " ? "x" : " "
    )
    return toggled
  }

  private static func uncheckedItemText(of line: String) -> String? {
    guard let marker = taskMarker(of: line), marker.state == " " else { return nil }
    let text = marker.remainder.trimmingCharacters(in: .whitespaces)
    return text.isEmpty ? nil : text
  }

  private struct TaskMarker {
    var stateIndex: String.Index
    var state: Character
    var remainder: Substring
  }

  /// Locates the `[state]` marker of a GFM task line. Indices are valid in `line`.
  private static func taskMarker(of line: String) -> TaskMarker? {
    var rest = Substring(line).drop(while: { $0 == " " || $0 == "\t" })
    guard let bullet = rest.first, bullet == "-" || bullet == "*" || bullet == "+" else {
      return nil
    }
    rest = rest.dropFirst().drop(while: { $0 == " " })
    guard rest.hasPrefix("[") else { return nil }
    rest = rest.dropFirst()
    guard let state = rest.first, state == " " || state == "x" || state == "X" else { return nil }
    let stateIndex = rest.startIndex
    rest = rest.dropFirst()
    guard rest.hasPrefix("] ") || rest == "]" else { return nil }
    return TaskMarker(stateIndex: stateIndex, state: state, remainder: rest.dropFirst())
  }
}
