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

/// The per-issue fields compared between consecutive polls of the involved
/// ("Mine") set.
nonisolated struct RepositoryIssueSnapshot: Equatable, Sendable {
  let commentsCount: Int
  let labelNames: Set<String>
  let isClosed: Bool
}

nonisolated enum RepositoryIssueUpdates {
  static func snapshot(of issues: [GithubIssue]) -> [Int: RepositoryIssueSnapshot] {
    issues.reduce(into: [:]) { result, issue in
      result[issue.number] = RepositoryIssueSnapshot(
        commentsCount: issue.commentsCount,
        labelNames: Set(issue.labels.map(\.name)),
        isClosed: issue.isClosed
      )
    }
  }

  /// Diffs the fetched involved issues against the previous poll's snapshot. A
  /// `nil` previous snapshot is the first successful load and seeds silently.
  /// `login` is the signed-in user, used to stay silent about their own newly
  /// created issues while still announcing issues that newly involve them.
  static func notifications(
    repositoryID: Repository.ID,
    previous: [Int: RepositoryIssueSnapshot]?,
    issues: [GithubIssue],
    login: String?,
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
        // Newly in the involved set. Silent for issues the user authored (they
        // created it); otherwise they were just @mentioned / assigned / replied to.
        if issue.authorLogin != login {
          append(title: "You're involved in #\(issue.number)", issue: issue)
        }
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
      if issue.isClosed != before.isClosed {
        append(title: "Issue #\(issue.number) \(issue.isClosed ? "closed" : "reopened")", issue: issue)
      }
    }
    return notifications
  }
}
