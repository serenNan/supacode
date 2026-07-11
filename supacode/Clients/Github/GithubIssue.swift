import Foundation

nonisolated struct GithubIssue: Decodable, Equatable, Hashable, Identifiable {
  let number: Int
  let title: String
  let url: String
  let updatedAt: Date?
  let authorLogin: String?
  let labels: [GithubIssueLabel]
  let commentsCount: Int

  var id: Int { number }
}

nonisolated struct GithubIssueLabel: Decodable, Equatable, Hashable {
  let name: String
  let color: String
}
