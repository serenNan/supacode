import Foundation

/// A clicked terminal link resolved to a file inside a worktree: a path
/// relative to the worktree root (git semantics) plus an optional 1-based
/// line number parsed from a `path:line` / `path:line:col` suffix.
struct TerminalFileReference: Equatable, Sendable {
  let relativePath: String
  let line: Int?

  /// True for media / binary extensions (images, PDF, audio/video, archives,
  /// office documents) that have no useful textual diff: these open with the
  /// system default application instead of the diff viewer.
  var prefersSystemOpen: Bool {
    let ext = (relativePath as NSString).pathExtension.lowercased()
    return Self.systemOpenExtensions.contains(ext)
  }

  private static let systemOpenExtensions: Set<String> = [
    // Images
    "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif",
    "ico", "icns", "svg",
    // Documents
    "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "pages", "numbers",
    // Audio / video
    "mp3", "wav", "aac", "flac", "m4a", "ogg", "mp4", "mov", "avi", "mkv", "webm",
    // Archives / images
    "zip", "tar", "gz", "bz2", "xz", "7z", "rar", "dmg", "iso",
  ]

  /// Resolves the raw text of a clicked terminal link. Accepts bare paths,
  /// `path:line`, `path:line:col`, and `file://` URIs; any other URL scheme
  /// does not resolve. Relative paths resolve against `pwd` (the surface's
  /// OSC 7 working directory), falling back to the worktree root. The file
  /// must exist and lie inside `worktreeRoot`. `fileExists` is injected so
  /// tests never touch the disk.
  static func resolve(
    clicked: String,
    pwd: String?,
    worktreeRoot: URL,
    fileExists: (String) -> Bool
  ) -> TerminalFileReference? {
    let trimmed = clicked.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if trimmed.lowercased().hasPrefix("file://") {
      guard let url = URL(string: trimmed) else { return nil }
      return reference(
        path: url.path(percentEncoded: false), line: nil,
        pwd: pwd, worktreeRoot: worktreeRoot, fileExists: fileExists
      )
    }
    // Authority-form URLs with any other scheme (https://, ssh://, …) are
    // not file references. A scheme-less colon like `notes.txt:12` is a
    // path candidate, so only `://` disqualifies.
    if trimmed.contains("://") { return nil }

    for candidate in candidates(for: trimmed) {
      if let resolved = reference(
        path: candidate.path, line: candidate.line,
        pwd: pwd, worktreeRoot: worktreeRoot, fileExists: fileExists
      ) {
        return resolved
      }
    }
    return nil
  }

  /// Interpretations of the clicked text, most-literal first: the exact
  /// string, then with up to two trailing `:<digits>` suffixes stripped
  /// (line, then line:column). A real file whose name contains a colon
  /// therefore beats the `path:line` reading.
  private static func candidates(for text: String) -> [(path: String, line: Int?)] {
    var result: [(path: String, line: Int?)] = [(text, nil)]
    var current = Substring(text)
    for _ in 0..<2 {
      guard let colon = current.lastIndex(of: ":"),
        colon != current.startIndex,
        let number = Int(current[current.index(after: colon)...])
      else { break }
      current = current[..<colon]
      result.append((String(current), number >= 1 ? number : nil))
    }
    return result
  }

  private static func reference(
    path: String,
    line: Int?,
    pwd: String?,
    worktreeRoot: URL,
    fileExists: (String) -> Bool
  ) -> TerminalFileReference? {
    let expanded = NSString(string: path).expandingTildeInPath
    let absolute: URL
    if expanded.hasPrefix("/") {
      absolute = URL(filePath: expanded)
    } else {
      let base = URL(filePath: pwd ?? worktreeRoot.path, directoryHint: .isDirectory)
      absolute = URL(filePath: expanded, relativeTo: base)
    }
    let standardized = absolute.standardizedFileURL.path(percentEncoded: false)
    guard fileExists(standardized) else { return nil }

    let rootPath = worktreeRoot.standardizedFileURL.path(percentEncoded: false)
    let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    guard standardized.hasPrefix(rootPrefix) else { return nil }
    let relativePath = String(standardized.dropFirst(rootPrefix.count))
    guard !relativePath.isEmpty else { return nil }
    return TerminalFileReference(relativePath: relativePath, line: line)
  }
}
