import Foundation

/// A repo-level notification produced by issue snapshot diffing. Distinct from
/// `WorktreeTerminalNotification` on purpose: issues belong to a repository,
/// not to a worktree/surface, so reusing the terminal model would leak surface
/// semantics (focus muting, per-row projection) into repo-scoped data.
nonisolated struct RepositoryIssueNotification: Equatable, Identifiable, Sendable {
  let id: UUID
  let repositoryID: Repository.ID
  let issueNumber: Int
  let title: String
  let body: String
  let url: String
  let createdAt: Date
  var isRead = false
}

/// The per-issue fields compared between consecutive polls.
nonisolated struct RepositoryIssueSnapshot: Equatable, Sendable {
  let commentsCount: Int
  let labelNames: Set<String>
}

nonisolated enum RepositoryIssueUpdates {
  static func snapshot(of issues: [GithubIssue]) -> [Int: RepositoryIssueSnapshot] {
    issues.reduce(into: [:]) { result, issue in
      result[issue.number] = RepositoryIssueSnapshot(
        commentsCount: issue.commentsCount,
        labelNames: Set(issue.labels.map(\.name))
      )
    }
  }

  /// Diffs the fetched issues against the previous poll's snapshot. A `nil`
  /// previous snapshot is the first successful load and seeds silently.
  static func notifications(
    repositoryID: Repository.ID,
    previous: [Int: RepositoryIssueSnapshot]?,
    issues: [GithubIssue],
    uuid: () -> UUID,
    now: Date
  ) -> [RepositoryIssueNotification] {
    guard let previous else {
      return []
    }
    var notifications: [RepositoryIssueNotification] = []
    func append(title: String, issue: GithubIssue) {
      notifications.append(
        RepositoryIssueNotification(
          id: uuid(),
          repositoryID: repositoryID,
          issueNumber: issue.number,
          title: title,
          body: issue.title,
          url: issue.url,
          createdAt: now
        )
      )
    }
    for issue in issues {
      guard let before = previous[issue.number] else {
        append(title: "New issue #\(issue.number)", issue: issue)
        continue
      }
      if issue.commentsCount > before.commentsCount {
        append(title: "New comment on #\(issue.number)", issue: issue)
      }
      let labelNames = Set(issue.labels.map(\.name))
      if labelNames != before.labelNames {
        let added = labelNames.subtracting(before.labelNames).sorted().map { "+\($0)" }
        let removed = before.labelNames.subtracting(labelNames).sorted().map { "-\($0)" }
        let delta = (added + removed).joined(separator: " ")
        append(title: "Labels changed on #\(issue.number) (\(delta))", issue: issue)
      }
    }
    return notifications
  }
}
