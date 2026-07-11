import AppKit
import ComposableArchitecture
import SwiftUI

/// Inspector pane listing the selected worktree's commit history: linear
/// first-parent list with graph dots, ref badges, an "Outgoing" group for
/// commits ahead of upstream, and an expandable per-commit detail.
struct WorktreeGitHistoryInspectorView: View {
  let repositoriesStore: StoreOf<RepositoriesFeature>
  let isFolder: Bool

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("History")
          .font(.headline)
        Spacer()
        Button("Refresh", systemImage: "arrow.clockwise") {
          repositoriesStore.send(.gitHistory(.refresh))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .disabled(repositoriesStore.gitHistory?.isLoading == true)
        .help("Reload commit history.")
      }
      .padding(.horizontal)
      .padding(.vertical, 10)
      Divider()

      if isFolder {
        ContentUnavailableView(
          "Not a Git Repository",
          systemImage: "folder",
          description: Text("This folder isn't a git repository.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let history = repositoriesStore.gitHistory {
        GitHistoryContent(history: history, repositoriesStore: repositoriesStore)
      } else {
        ContentUnavailableView(
          "No History",
          systemImage: "clock.arrow.circlepath",
          description: Text("Select a worktree to see its commit history.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }
}

private struct GitHistoryContent: View {
  let history: RepositoriesFeature.GitHistoryState
  let repositoriesStore: StoreOf<RepositoriesFeature>

  var body: some View {
    if let error = history.loadError {
      ContentUnavailableView {
        Label("Couldn't Load History", systemImage: "exclamationmark.triangle")
      } description: {
        Text(error)
      } actions: {
        Button("Retry") {
          repositoriesStore.send(.gitHistory(.refresh))
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let snapshot = history.snapshot {
      if snapshot.commits.isEmpty {
        ContentUnavailableView(
          "No Commits",
          systemImage: "clock.arrow.circlepath",
          description: Text("This repository has no commits yet.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        GitHistoryList(history: history, snapshot: snapshot, repositoriesStore: repositoriesStore)
      }
    } else {
      VStack(spacing: 10) {
        ProgressView()
        Text("Loading history…")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

private struct GitHistoryList: View {
  let history: RepositoriesFeature.GitHistoryState
  let snapshot: GitHistorySnapshot
  let repositoriesStore: StoreOf<RepositoriesFeature>

  var body: some View {
    let outgoing = Array(snapshot.commits.prefix(snapshot.aheadCount))
    let landed = Array(snapshot.commits.dropFirst(snapshot.aheadCount))
    let hasUncommitted = (history.uncommittedAdded ?? 0) + (history.uncommittedRemoved ?? 0) > 0
    // One clock for every relative timestamp, ticking each minute.
    TimelineView(.everyMinute) { context in
      Form {
        if hasUncommitted {
          Section {
            UncommittedChangesRow(
              added: history.uncommittedAdded ?? 0,
              removed: history.uncommittedRemoved ?? 0
            )
          }
        }
        if !outgoing.isEmpty {
          Section {
            commitRows(outgoing, now: context.date)
          } header: {
            Label("Outgoing", systemImage: "arrow.up")
              .font(.subheadline.weight(.medium))
              .textCase(nil)
          }
        }
        Section {
          commitRows(landed, now: context.date)
        } footer: {
          if snapshot.isTruncated {
            Text("Showing the \(snapshot.commits.count) most recent commits.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      .formStyle(.grouped)
      // Let the window's terminal background (set in WindowChromeApplier) show through.
      .scrollContentBackground(.hidden)
    }
  }

  @ViewBuilder
  private func commitRows(_ commits: [GitCommitSummary], now: Date) -> some View {
    ForEach(commits) { commit in
      GitCommitRow(
        commit: commit,
        now: now,
        isExpanded: history.expandedCommitHash == commit.hash,
        expandedDetail: history.expandedDetail,
        detailError: history.detailError,
        onTap: { repositoriesStore.send(.gitHistory(.commitTapped(hash: commit.hash))) }
      )
    }
  }
}

private struct UncommittedChangesRow: View {
  let added: Int
  let removed: Int

  var body: some View {
    HStack(spacing: 10) {
      Circle()
        .strokeBorder(.secondary, lineWidth: 1.5)
        .frame(width: 9, height: 9)
        .accessibilityHidden(true)
      Text("Uncommitted Changes")
        .font(.callout.weight(.medium))
      Spacer()
      DiffStatText(added: added, removed: removed)
    }
    .accessibilityElement(children: .combine)
  }
}

private struct GitCommitRow: View {
  let commit: GitCommitSummary
  let now: Date
  let isExpanded: Bool
  let expandedDetail: GitCommitDetail?
  let detailError: String?
  let onTap: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button(action: onTap) {
        HStack(alignment: .top, spacing: 10) {
          Circle()
            .fill(.secondary)
            .frame(width: 9, height: 9)
            .padding(.top, 3)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Text(commit.subject)
                .font(.callout.weight(commit.refs.contains(where: \.isHead) ? .semibold : .regular))
                .lineLimit(isExpanded ? nil : 1)
              Spacer(minLength: 6)
              Text(Self.relativeTime(commit.date, now: now))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .layoutPriority(1)
            }
            HStack(spacing: 4) {
              ForEach(commit.refs, id: \.self) { ref in
                GitRefBadge(ref: ref)
              }
              Text(commit.author)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
        }
        .contentShape(.rect)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .help(commit.subject)

      if isExpanded {
        GitCommitDetailView(commit: commit, detail: expandedDetail, detailError: detailError)
          .padding(.top, 6)
          .padding(.leading, 19)
      }
    }
    .contextMenu {
      Button("Copy Hash") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commit.hash, forType: .string)
      }
      Button("Copy Message") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commit.subject, forType: .string)
      }
    }
  }

  private static func relativeTime(_ date: Date, now: Date) -> String {
    guard now.timeIntervalSince(date) >= 60 else { return "now" }
    return date.formatted(.relative(presentation: .named, unitsStyle: .narrow))
  }
}

private struct GitRefBadge: View {
  let ref: GitCommitRef

  var body: some View {
    Label {
      Text(ref.name)
        .font(.caption2.weight(ref.isHead ? .bold : .regular))
        .monospaced()
        .lineLimit(1)
    } icon: {
      Image(systemName: symbolName)
        .font(.caption2)
    }
    .labelStyle(.titleAndIcon)
    .padding(.horizontal, 5)
    .padding(.vertical, 1)
    .foregroundStyle(badgeColor)
    .background(badgeColor.opacity(0.15), in: .capsule)
    .accessibilityLabel(accessibilityDescription)
  }

  private var symbolName: String {
    switch ref.kind {
    case .localBranch, .detachedHead: "arrow.triangle.branch"
    case .remoteBranch: "cloud"
    case .tag: "tag"
    }
  }

  private var badgeColor: Color {
    switch ref.kind {
    case .localBranch, .detachedHead: .blue
    case .remoteBranch: .purple
    case .tag: .green
    }
  }

  private var accessibilityDescription: String {
    switch ref.kind {
    case .localBranch: "Branch \(ref.name)"
    case .remoteBranch: "Remote branch \(ref.name)"
    case .tag: "Tag \(ref.name)"
    case .detachedHead: "Detached HEAD"
    }
  }
}

private struct GitCommitDetailView: View {
  let commit: GitCommitSummary
  let detail: GitCommitDetail?
  let detailError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let detail {
        Text(detail.message)
          .font(.callout)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: "\(detail.author) <\(detail.email)>")
          Text(detail.date.formatted(date: .abbreviated, time: .shortened))
          Text(commit.shortHash)
            .monospaced()
            .textSelection(.enabled)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        if !detail.files.isEmpty {
          VStack(alignment: .leading, spacing: 3) {
            ForEach(detail.files) { file in
              HStack(spacing: 6) {
                Text(file.path)
                  .font(.caption)
                  .monospaced()
                  .lineLimit(1)
                  .truncationMode(.middle)
                  .help(file.path)
                Spacer(minLength: 4)
                if let added = file.added, let removed = file.removed {
                  DiffStatText(added: added, removed: removed)
                } else {
                  Text("binary")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
              }
            }
          }
        }
      } else if let detailError {
        Label(detailError, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ProgressView()
          .controlSize(.small)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct DiffStatText: View {
  let added: Int
  let removed: Int

  var body: some View {
    HStack(spacing: 4) {
      Text(verbatim: "+\(added)")
        .foregroundStyle(.green)
      Text(verbatim: "-\(removed)")
        .foregroundStyle(.red)
    }
    .font(.caption)
    .monospaced()
  }
}
