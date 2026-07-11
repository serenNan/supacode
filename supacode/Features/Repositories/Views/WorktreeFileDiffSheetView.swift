import AppKit
import ComposableArchitecture
import SupacodeSettingsShared
import SwiftUI

/// Read-only unified diff of one file, presented as a sheet from the History
/// pane: green/red line highlighting, hunk headers, and old/new line gutters.
struct WorktreeFileDiffSheetView: View {
  let presented: RepositoriesFeature.PresentedFileDiff
  let worktree: Worktree?
  let onDismiss: () -> Void

  @Shared(.settingsFile) private var settingsFile

  /// Pathological diffs (lockfiles, generated code) stop rendering here.
  static let maxRenderedLines = 4000

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
    }
    .frame(minWidth: 680, idealWidth: 780, minHeight: 420, idealHeight: 580)
  }

  private var header: some View {
    HStack(spacing: 12) {
      Text(presented.filePath)
        .font(.headline)
        .monospaced()
        .lineLimit(1)
        .truncationMode(.middle)
        .help(presented.filePath)
      Spacer()
      if let localWorktree = worktree, localWorktree.host == nil {
        Button("Open in Editor", systemImage: "square.and.pencil") {
          WorktreeOpener.openFile(
            at: localWorktree.workingDirectory.appending(path: presented.filePath),
            defaultEditorID: settingsFile.global.defaultEditorID
          )
        }
        .help("Open this file in your default editor.")
      }
      Button("Close") {
        onDismiss()
      }
      .keyboardShortcut(.cancelAction)
      .help("Close the diff. (Esc)")
    }
    .padding(.horizontal)
    .padding(.vertical, 10)
  }

  @ViewBuilder
  private var content: some View {
    if let error = presented.error {
      ContentUnavailableView {
        Label("Couldn't Load Diff", systemImage: "exclamationmark.triangle")
      } description: {
        Text(error)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let diff = presented.diff {
      if diff.isBinary {
        ContentUnavailableView(
          "Binary File",
          systemImage: "doc",
          description: Text("Binary files have no textual diff.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if diff.hunks.isEmpty {
        ContentUnavailableView(
          "No Changes",
          systemImage: "equal.circle",
          description: Text("This file has no textual changes to show.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        GitDiffContentView(diff: diff, lineCap: Self.maxRenderedLines)
      }
    } else {
      VStack(spacing: 10) {
        ProgressView()
        Text("Loading diff…")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

private struct GitDiffContentView: View {
  let diff: GitFileDiff
  let lineCap: Int

  var body: some View {
    let (rows, isTruncated) = Self.rows(for: diff, cap: lineCap)
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(rows) { row in
          GitDiffRowView(row: row)
        }
        if isTruncated {
          Text("Diff truncated: showing the first \(lineCap) lines.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
        }
      }
      .padding(.vertical, 6)
    }
    .background(.background)
  }

  static func rows(for diff: GitFileDiff, cap: Int) -> (rows: [GitDiffDisplayRow], isTruncated: Bool) {
    var rows: [GitDiffDisplayRow] = []
    for hunk in diff.hunks {
      rows.append(GitDiffDisplayRow(id: rows.count, kind: .hunkHeader(hunk.header)))
      for line in hunk.lines {
        if rows.count >= cap {
          return (rows, true)
        }
        rows.append(GitDiffDisplayRow(id: rows.count, kind: .line(line)))
      }
    }
    return (rows, false)
  }
}

struct GitDiffDisplayRow: Identifiable {
  enum Kind {
    case hunkHeader(String)
    case line(GitDiffLine)
  }

  let id: Int
  let kind: Kind
}

private struct GitDiffRowView: View {
  let row: GitDiffDisplayRow

  var body: some View {
    switch row.kind {
    case .hunkHeader(let header):
      Text(header)
        .font(.caption)
        .monospaced()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
    case .line(let line):
      HStack(alignment: .firstTextBaseline, spacing: 0) {
        GitDiffGutterText(number: line.oldNumber)
        GitDiffGutterText(number: line.newNumber)
        Text(marker(for: line.kind))
          .frame(width: 16)
          .foregroundStyle(markerColor(for: line.kind))
        Text(line.text.isEmpty ? " " : line.text)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .font(.callout)
      .monospaced()
      .padding(.horizontal, 8)
      .background(background(for: line.kind))
    }
  }

  private func marker(for kind: GitDiffLine.Kind) -> String {
    switch kind {
    case .added: "+"
    case .removed: "-"
    case .context: " "
    }
  }

  private func markerColor(for kind: GitDiffLine.Kind) -> Color {
    switch kind {
    case .added: .green
    case .removed: .red
    case .context: .secondary
    }
  }

  private func background(for kind: GitDiffLine.Kind) -> Color {
    switch kind {
    case .added: .green.opacity(0.12)
    case .removed: .red.opacity(0.12)
    case .context: .clear
    }
  }
}

private struct GitDiffGutterText: View {
  let number: Int?

  var body: some View {
    Text(number.map(String.init) ?? "")
      .font(.caption)
      .monospaced()
      .foregroundStyle(.tertiary)
      .frame(width: 40, alignment: .trailing)
      .padding(.trailing, 6)
  }
}
