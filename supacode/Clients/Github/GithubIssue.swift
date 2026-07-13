import Foundation

nonisolated struct GithubIssue: Decodable, Equatable, Hashable, Identifiable {
  let number: Int
  let title: String
  let url: String
  let updatedAt: Date?
  let authorLogin: String?
  let labels: [GithubIssueLabel]
  let commentsCount: Int
  /// Open vs. closed. Drives state-change notifications and the "Mine" list's
  /// state filter. Derived from GraphQL `state` ("OPEN"/"CLOSED").
  let isClosed: Bool
  /// GraphQL `stateReason` for closed issues: "COMPLETED", "NOT_PLANNED", or
  /// "REOPENED"; `nil` for open issues or older GHES. Lets the UI mirror
  /// GitHub's purple-completed vs. gray-not-planned status glyphs.
  let stateReason: String?

  var id: Int { number }
}

nonisolated struct GithubIssueLabel: Decodable, Equatable, Hashable {
  let name: String
  let color: String
}

/// The two issue sets fetched together each poll: `all` (the repository's open
/// issues, for the All list) and `involved` (issues the signed-in user is
/// involved in, for the Mine list and notifications). `involved` is empty when
/// there is no signed-in login to scope by.
nonisolated struct GithubIssueSets: Equatable, Sendable {
  var all: [GithubIssue]
  var involved: [GithubIssue]

  static let empty = GithubIssueSets(all: [], involved: [])
}
