import Foundation

/// One ref decorating a commit, parsed from `git log --decorate=full`'s `%D`.
nonisolated struct GitCommitRef: Hashable, Sendable {
  enum Kind: Hashable, Sendable {
    case localBranch
    case remoteBranch
    case tag
    case detachedHead
  }

  let name: String
  let kind: Kind
  let isHead: Bool
}

nonisolated struct GitCommitSummary: Equatable, Sendable, Identifiable {
  let hash: String
  let shortHash: String
  let author: String
  let date: Date
  let refs: [GitCommitRef]
  let subject: String

  var id: String { hash }
}

nonisolated struct GitCommitFileChange: Equatable, Sendable, Identifiable {
  let path: String
  /// `nil` for binary files (`-` in numstat).
  let added: Int?
  let removed: Int?

  var id: String { path }
}

nonisolated struct GitCommitDetail: Equatable, Sendable {
  let hash: String
  let author: String
  let email: String
  let date: Date
  let message: String
  let files: [GitCommitFileChange]
}

nonisolated struct GitHistorySnapshot: Equatable, Sendable {
  let commits: [GitCommitSummary]
  let upstreamRef: String?
  let aheadCount: Int
  let isTruncated: Bool
}

nonisolated struct GitDiffLine: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case context
    case added
    case removed
  }

  let kind: Kind
  let text: String
  let oldNumber: Int?
  let newNumber: Int?
}

nonisolated struct GitDiffHunk: Equatable, Sendable {
  let header: String
  let lines: [GitDiffLine]
}

nonisolated struct GitFileDiff: Equatable, Sendable {
  let hunks: [GitDiffHunk]
  let isBinary: Bool
}

// Pure parsers for the history queries. Records are separated by `%x1e` and
// fields by `%x1f`: control characters can't occur in valid UTF-8 commit text,
// so subjects/bodies with tabs, newlines, or emoji never break field splits.
extension GitClient {
  nonisolated static let commitLogFormat = "%H%x1f%h%x1f%an%x1f%aI%x1f%D%x1f%s%x1e"
  nonisolated static let commitDetailFormat = "%H%x1f%an%x1f%ae%x1f%aI%x1f%B%x1e"

  private nonisolated static let fieldSeparator: Character = "\u{1f}"
  private nonisolated static let recordSeparator: Character = "\u{1e}"

  nonisolated static func parseCommitLog(_ output: String) -> [GitCommitSummary] {
    output
      .split(separator: recordSeparator)
      .compactMap { record in
        let fields =
          record
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .split(separator: fieldSeparator, omittingEmptySubsequences: false)
          .map(String.init)
        guard fields.count == 6, let date = try? Date(fields[3], strategy: .iso8601) else {
          return nil
        }
        return GitCommitSummary(
          hash: fields[0],
          shortHash: fields[1],
          author: fields[2],
          date: date,
          refs: parseCommitRefs(fields[4]),
          subject: fields[5]
        )
      }
  }

  nonisolated static func parseCommitDetail(_ output: String) -> GitCommitDetail? {
    let parts = output.split(
      separator: recordSeparator, maxSplits: 1, omittingEmptySubsequences: false)
    guard let header = parts.first else { return nil }
    let fields =
      header
      .split(separator: fieldSeparator, omittingEmptySubsequences: false)
      .map(String.init)
    guard fields.count == 5, let date = try? Date(fields[3], strategy: .iso8601) else {
      return nil
    }
    let files = parts.count > 1 ? parseNumstat(String(parts[1])) : []
    return GitCommitDetail(
      hash: fields[0],
      author: fields[1],
      email: fields[2],
      date: date,
      message: fields[4].trimmingCharacters(in: .whitespacesAndNewlines),
      files: files
    )
  }

  nonisolated static func parseNumstat(_ output: String) -> [GitCommitFileChange] {
    output
      .split(whereSeparator: \.isNewline)
      .compactMap { line in
        let columns = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
          .map(String.init)
        guard columns.count == 3, !columns[2].isEmpty else { return nil }
        return GitCommitFileChange(
          path: columns[2],
          added: Int(columns[0]),
          removed: Int(columns[1])
        )
      }
  }

  /// Unified diff for one file. Lines before the first `@@` are file headers
  /// (`diff --git`, `index`, `---`/`+++`, rename markers) and are skipped; a
  /// `Binary files … differ` marker there flags the whole diff binary.
  nonisolated static func parseFileDiff(_ output: String) -> GitFileDiff {
    var hunks: [GitDiffHunk] = []
    var currentHeader: String?
    var currentLines: [GitDiffLine] = []
    var oldNumber = 0
    var newNumber = 0
    var isBinary = false

    func flush() {
      if let header = currentHeader {
        hunks.append(GitDiffHunk(header: header, lines: currentLines))
      }
      currentHeader = nil
      currentLines = []
    }

    for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
      if line.hasPrefix("@@") {
        flush()
        currentHeader = String(line)
        (oldNumber, newNumber) = parseHunkStarts(line)
        continue
      }
      guard currentHeader != nil else {
        if line.hasPrefix("Binary files "), line.hasSuffix(" differ") {
          isBinary = true
        }
        continue
      }
      if line.hasPrefix("diff --git") {
        flush()
      } else if line.hasPrefix("+") {
        currentLines.append(
          GitDiffLine(kind: .added, text: String(line.dropFirst()), oldNumber: nil, newNumber: newNumber))
        newNumber += 1
      } else if line.hasPrefix("-") {
        currentLines.append(
          GitDiffLine(kind: .removed, text: String(line.dropFirst()), oldNumber: oldNumber, newNumber: nil))
        oldNumber += 1
      } else if line.hasPrefix(" ") {
        currentLines.append(
          GitDiffLine(
            kind: .context, text: String(line.dropFirst()), oldNumber: oldNumber, newNumber: newNumber))
        oldNumber += 1
        newNumber += 1
      }
      // "\ No newline at end of file" and blank trailing lines fall through.
    }
    flush()
    return GitFileDiff(hunks: hunks, isBinary: isBinary)
  }

  /// `@@ -a[,b] +c[,d] @@ …` → (a, c); counts and trailing context optional.
  private nonisolated static func parseHunkStarts(_ line: Substring) -> (Int, Int) {
    let tokens = line.split(separator: " ")
    guard tokens.count >= 3,
      let old = Int(tokens[1].dropFirst().prefix(while: \.isNumber)),
      let new = Int(tokens[2].dropFirst().prefix(while: \.isNumber))
    else {
      return (0, 0)
    }
    return (old, new)
  }

  /// `%D` under `--decorate=full`, e.g.
  /// `HEAD -> refs/heads/main, refs/remotes/origin/main, tag: refs/tags/v1.0`.
  private nonisolated static func parseCommitRefs(_ decorations: String) -> [GitCommitRef] {
    decorations
      .split(separator: ",")
      .compactMap { part in
        var token = part.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return nil }
        if token == "HEAD" {
          return GitCommitRef(name: "HEAD", kind: .detachedHead, isHead: true)
        }
        var isHead = false
        if token.hasPrefix("HEAD -> ") {
          token = String(token.dropFirst("HEAD -> ".count))
          isHead = true
        }
        if token.hasPrefix("tag: refs/tags/") {
          return GitCommitRef(
            name: String(token.dropFirst("tag: refs/tags/".count)), kind: .tag, isHead: false)
        }
        if token.hasPrefix("refs/heads/") {
          return GitCommitRef(
            name: String(token.dropFirst("refs/heads/".count)), kind: .localBranch, isHead: isHead)
        }
        if token.hasPrefix("refs/remotes/") {
          return GitCommitRef(
            name: String(token.dropFirst("refs/remotes/".count)), kind: .remoteBranch,
            isHead: isHead)
        }
        return GitCommitRef(name: token, kind: .localBranch, isHead: isHead)
      }
  }
}
